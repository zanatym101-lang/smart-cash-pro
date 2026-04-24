-- Licensing v2 schema (contract freeze)
-- Scope: licensing tables only. No accounting tables touched.

begin;

create extension if not exists pgcrypto;

-- =========
-- Enums
-- =========
do $$
begin
  if not exists (select 1 from pg_type where typname = 'license_status_enum') then
    create type public.license_status_enum as enum ('active', 'suspended', 'expired', 'revoked');
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'license_device_status_enum') then
    create type public.license_device_status_enum as enum (
      'active',
      'pending_replacement',
      'released',
      'revoked',
      'blocked'
    );
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'license_session_state_enum') then
    create type public.license_session_state_enum as enum (
      'active',
      'rotated',
      'revoked',
      'expired',
      'compromised'
    );
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'license_replacement_state_enum') then
    create type public.license_replacement_state_enum as enum (
      'requested',
      'awaiting_confirmation',
      'executing',
      'completed',
      'cancelled',
      'expired'
    );
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'license_event_type_enum') then
    create type public.license_event_type_enum as enum (
      'activate',
      'validate',
      'heartbeat',
      'refresh',
      'revoke_license',
      'revoke_device',
      'release_device',
      'replacement_requested',
      'replacement_confirmed',
      'replacement_cancelled',
      'replacement_expired',
      'compromise_detected',
      'rpc_activate',
      'rpc_refresh',
      'rpc_request_replacement',
      'rpc_confirm_replacement',
      'rpc_admin_revoke_license',
      'rpc_admin_revoke_device',
      'rpc_admin_release_device'
    );
  end if;
end $$;

-- =========
-- licenses
-- =========
create table if not exists public.licenses (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  status public.license_status_enum not null default 'active',
  plan_id text null,
  max_devices integer not null default 1 check (max_devices > 0),
  expires_at timestamptz null,
  grace_hours integer not null default 72 check (grace_hours between 0 and 720),
  metadata jsonb not null default '{}'::jsonb,
  version bigint not null default 1,
  revoked_at timestamptz null,
  revoked_reason text null,
  revoked_by uuid null,
  suspended_at timestamptz null,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.licenses
  add column if not exists code text,
  add column if not exists status public.license_status_enum default 'active',
  add column if not exists plan_id text,
  add column if not exists max_devices integer default 1,
  add column if not exists expires_at timestamptz,
  add column if not exists grace_hours integer default 72,
  add column if not exists metadata jsonb default '{}'::jsonb,
  add column if not exists version bigint default 1,
  add column if not exists revoked_at timestamptz,
  add column if not exists revoked_reason text,
  add column if not exists revoked_by uuid,
  add column if not exists suspended_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

create unique index if not exists uq_licenses_code_live
  on public.licenses (upper(code))
  where deleted_at is null;

create index if not exists idx_licenses_status_live
  on public.licenses (status)
  where deleted_at is null;

-- =========
-- license_devices
-- =========
create table if not exists public.license_devices (
  id uuid primary key default gen_random_uuid(),
  license_id uuid not null references public.licenses(id) on delete restrict,
  device_id text not null,
  device_fingerprint_hash text not null,
  fingerprint_version smallint not null default 1,
  platform text null,
  app_version text null,
  status public.license_device_status_enum not null default 'active',

  activated_at timestamptz not null default now(),
  last_seen_at timestamptz null,
  last_validate_at timestamptz null,
  last_heartbeat_at timestamptz null,
  last_ip inet null,
  grace_ends_at timestamptz null,

  replacement_state public.license_replacement_state_enum null,
  replacement_request_id uuid null,
  replacement_expires_at timestamptz null,
  replacement_reason text null,
  replacement_confirmed_at timestamptz null,
  replacement_new_device_id text null,
  replacement_new_fingerprint_hash text null,
  replacement_new_platform text null,
  replacement_new_app_version text null,

  released_at timestamptz null,
  release_reason text null,
  revoked_at timestamptz null,
  revoked_reason text null,
  revoked_by uuid null,

  version bigint not null default 1,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_license_devices_fingerprint_not_blank check (length(trim(device_fingerprint_hash)) >= 16),
  constraint chk_license_devices_device_not_blank check (length(trim(device_id)) >= 8)
);

create unique index if not exists uq_license_devices_license_device_live
  on public.license_devices (license_id, device_id)
  where deleted_at is null;

create index if not exists idx_license_devices_license_status_live
  on public.license_devices (license_id, status)
  where deleted_at is null;

create index if not exists idx_license_devices_replacement_live
  on public.license_devices (license_id, replacement_request_id)
  where deleted_at is null and replacement_request_id is not null;

create unique index if not exists uq_license_devices_one_active_replacement_per_license
  on public.license_devices (license_id)
  where deleted_at is null
    and status = 'pending_replacement'
    and replacement_state in ('requested', 'awaiting_confirmation', 'executing');

create index if not exists idx_license_devices_last_seen_live
  on public.license_devices (last_seen_at desc)
  where deleted_at is null;

-- =========
-- license_sessions
-- =========
create table if not exists public.license_sessions (
  id uuid primary key default gen_random_uuid(),
  license_id uuid not null references public.licenses(id) on delete restrict,
  device_row_id uuid not null references public.license_devices(id) on delete restrict,
  device_id text not null,

  state public.license_session_state_enum not null default 'active',
  access_token_hash text not null,
  refresh_token_hash text not null,
  token_jti uuid not null default gen_random_uuid(),
  refresh_jti uuid not null default gen_random_uuid(),

  issued_at timestamptz not null default now(),
  access_expires_at timestamptz not null,
  refresh_expires_at timestamptz not null,
  last_seen_at timestamptz null,

  rotated_at timestamptz null,
  replaced_by_session_id uuid null references public.license_sessions(id) on delete set null,
  revoked_at timestamptz null,
  revoked_reason text null,
  compromised_at timestamptz null,

  version bigint not null default 1,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_license_sessions_access_hash_not_blank check (length(trim(access_token_hash)) >= 32),
  constraint chk_license_sessions_refresh_hash_not_blank check (length(trim(refresh_token_hash)) >= 32),
  constraint chk_license_sessions_expiry_order check (refresh_expires_at > access_expires_at)
);

create unique index if not exists uq_license_sessions_access_hash_live
  on public.license_sessions (access_token_hash)
  where deleted_at is null;

create unique index if not exists uq_license_sessions_refresh_hash_live
  on public.license_sessions (refresh_token_hash)
  where deleted_at is null;

create index if not exists idx_license_sessions_device_state_live
  on public.license_sessions (device_row_id, state)
  where deleted_at is null;

create index if not exists idx_license_sessions_license_state_live
  on public.license_sessions (license_id, state)
  where deleted_at is null;

-- =========
-- license_events
-- =========
create table if not exists public.license_events (
  id bigserial primary key,
  license_id uuid null references public.licenses(id) on delete set null,
  device_row_id uuid null references public.license_devices(id) on delete set null,
  session_id uuid null references public.license_sessions(id) on delete set null,

  event_type public.license_event_type_enum not null,
  event_payload jsonb not null default '{}'::jsonb,
  request_id uuid null,
  idempotency_key text null,
  ip inet null,
  user_agent text null,

  created_at timestamptz not null default now(),
  deleted_at timestamptz null
);

create index if not exists idx_license_events_license_time
  on public.license_events (license_id, created_at desc)
  where deleted_at is null;

create index if not exists idx_license_events_device_time
  on public.license_events (device_row_id, created_at desc)
  where deleted_at is null;

create index if not exists idx_license_events_type_time
  on public.license_events (event_type, created_at desc)
  where deleted_at is null;

-- Idempotency storage via events table (unique per RPC event type + key).
create unique index if not exists uq_license_events_idempotency
  on public.license_events (event_type, idempotency_key)
  where deleted_at is null and idempotency_key is not null
    and event_type in (
      'rpc_activate',
      'rpc_refresh',
      'rpc_request_replacement',
      'rpc_confirm_replacement',
      'rpc_admin_revoke_license',
      'rpc_admin_revoke_device',
      'rpc_admin_release_device'
    );

-- =========
-- updated_at trigger
-- =========
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_licenses_updated_at on public.licenses;
create trigger trg_licenses_updated_at
before update on public.licenses
for each row execute function public.tg_set_updated_at();

drop trigger if exists trg_license_devices_updated_at on public.license_devices;
create trigger trg_license_devices_updated_at
before update on public.license_devices
for each row execute function public.tg_set_updated_at();

drop trigger if exists trg_license_sessions_updated_at on public.license_sessions;
create trigger trg_license_sessions_updated_at
before update on public.license_sessions
for each row execute function public.tg_set_updated_at();

commit;
