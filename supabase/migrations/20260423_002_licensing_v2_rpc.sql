-- Licensing v2 RPC contract (server-authoritative)
-- Scope: licensing RPC only. No Flutter/accounting changes.

begin;

-- =========
-- Helper functions
-- =========

create or replace function public.fn_license_error(
  p_error_code text,
  p_message text,
  p_retriable boolean default false
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'ok', false,
    'error_code', p_error_code,
    'message', p_message,
    'retriable', p_retriable,
    'server_time', now()
  );
$$;

create or replace function public.fn_license_token_hash(p_token text)
returns text
language sql
immutable
as $$
  select encode(
 extensions.digest(
   convert_to(coalesce(p_token,''),'UTF8'),
   'sha256'
 ),
 'hex'
);
$$;

create or replace function public.fn_license_issue_raw_token(p_bytes int default 32)
returns text
language sql
volatile
as $$
  select replace(
           replace(
             trim(trailing '=' from encode(extensions.gen_random_bytes(greatest(16, p_bytes)), 'base64')),
             '+', '-'
           ),
           '/', '_'
         );
$$;

create or replace function public.fn_license_is_admin_context()
returns boolean
language sql
stable
as $$
  select coalesce(auth.role(), '') = 'service_role';
$$;

create or replace function public.fn_license_log_event(
  p_event_type license_event_type_enum,
  p_license_id uuid default null,
  p_device_row_id uuid default null,
  p_session_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_request_id uuid default null,
  p_idempotency_key text default null,
  p_ip inet default null,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.license_events (
    license_id,
    device_row_id,
    session_id,
    event_type,
    event_payload,
    request_id,
    idempotency_key,
    ip,
    user_agent
  )
  values (
    p_license_id,
    p_device_row_id,
    p_session_id,
    p_event_type,
    coalesce(p_payload, '{}'::jsonb),
    p_request_id,
    nullif(trim(coalesce(p_idempotency_key, '')), ''),
    p_ip,
    nullif(trim(coalesce(p_user_agent, '')), '')
  );
exception
  when unique_violation then
    -- Duplicate event/idempotency row: safe no-op for retries.
    return;
  when others then
    -- For idempotent/response-carrying writes, failing silently can break replay safety.
    if nullif(trim(coalesce(p_idempotency_key, '')), '') is not null
       or (coalesce(p_payload, '{}'::jsonb) ? 'response') then
      raise exception using
        message = 'fn_license_log_event failed for idempotent flow',
        detail = sqlerrm;
    end if;
    -- Non-critical telemetry event: do not break the main RPC.
    raise warning 'fn_license_log_event non-critical failure: %', sqlerrm;
    return;
end;
$$;

create or replace function public.fn_license_get_idempotent_response(
  p_event_type public.license_event_type_enum,
  p_idempotency_key text
)
returns jsonb
language sql
stable
as $$
  select e.event_payload -> 'response'
  from public.license_events e
  where e.event_type = p_event_type::text
    and e.idempotency_key = p_idempotency_key
    and e.deleted_at is null
    and (e.event_payload ? 'response')
  order by e.id desc
  limit 1;
$$;

create or replace function public.fn_license_lock_idempotency(
  p_scope text,
  p_idempotency_key text
)
returns void
language sql
volatile
as $$
  select pg_advisory_xact_lock(
    hashtextextended(coalesce(p_scope, '') || ':' || coalesce(p_idempotency_key, ''), 0)
  );
$$;

-- =========
-- RPC: activate_license
-- =========
create or replace function public.activate_license(
  p_activation_code text,
  p_device_id text,
  p_device_fingerprint_hash text,
  p_platform text default null,
  p_app_version text default null,
  p_idempotency_key text default null,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_response jsonb;
  v_existing jsonb;
  v_license public.licenses%rowtype;
  v_device public.license_devices%rowtype;
  v_active_count integer;
  v_access_token text;
  v_refresh_token text;
  v_access_hash text;
  v_refresh_hash text;
  v_access_exp timestamptz;
  v_refresh_exp timestamptz;
  v_session_id uuid;
  v_grace_ends timestamptz;
begin
  if coalesce(trim(p_idempotency_key), '') = '' then
    return public.fn_license_error('missing_idempotency_key', 'idempotency_key is required', false);
  end if;
  if coalesce(trim(p_activation_code), '') = '' then
    return public.fn_license_error('invalid_activation_code', 'activation code is required', false);
  end if;
  if coalesce(trim(p_device_id), '') = '' then
    return public.fn_license_error('invalid_device_id', 'device_id is required', false);
  end if;
  if length(trim(coalesce(p_device_fingerprint_hash, ''))) < 16 then
    return public.fn_license_error('invalid_device_fingerprint', 'device fingerprint is invalid', false);
  end if;

  perform public.fn_license_lock_idempotency('activate_license', p_idempotency_key);
  v_existing := public.fn_license_get_idempotent_response('rpc_activate', p_idempotency_key);
  if v_existing is not null then
    return v_existing;
  end if;

  select *
  into v_license
  from public.licenses
  where upper(code) = upper(trim(p_activation_code))
    and deleted_at is null
  for update;

  if not found then
    v_response := public.fn_license_error('invalid_activation_code', 'activation code not found', false);
    perform public.fn_license_log_event('rpc_activate', null, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if v_license.status <> 'active' then
    v_response := public.fn_license_error('license_not_active', 'license is not active', false);
    perform public.fn_license_log_event('rpc_activate', v_license.id, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if v_license.expires_at is not null and v_license.expires_at <= v_now then
    update public.licenses
      set status = 'expired', version = version + 1
    where id = v_license.id and status = 'active';
    v_response := public.fn_license_error('license_expired', 'license expired', false);
    perform public.fn_license_log_event('rpc_activate', v_license.id, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select *
  into v_device
  from public.license_devices
  where license_id = v_license.id
    and device_id = trim(p_device_id)
    and deleted_at is null
  for update;

  if found and v_device.status in ('revoked', 'blocked') then
    v_response := public.fn_license_error('device_revoked', 'device is revoked or blocked', false);
    perform public.fn_license_log_event('rpc_activate', v_license.id, v_device.id, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if not found then
    select count(*)
    into v_active_count
    from public.license_devices
    where license_id = v_license.id
      and status = 'active'
      and deleted_at is null;

    if v_active_count >= v_license.max_devices then
      v_response := public.fn_license_error('device_limit_exceeded', 'max_devices reached', false);
      perform public.fn_license_log_event('rpc_activate', v_license.id, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
      return v_response;
    end if;

    insert into public.license_devices (
      license_id, device_id, device_fingerprint_hash, platform, app_version, status,
      activated_at, last_seen_at, last_validate_at, grace_ends_at
    )
    values (
      v_license.id, trim(p_device_id), trim(p_device_fingerprint_hash), nullif(trim(coalesce(p_platform, '')), ''), nullif(trim(coalesce(p_app_version, '')), ''), 'active',
      v_now, v_now, v_now, v_now + make_interval(hours => v_license.grace_hours)
    )
    returning * into v_device;
  else
    update public.license_devices
      set status = 'active',
          device_fingerprint_hash = trim(p_device_fingerprint_hash),
          platform = coalesce(nullif(trim(coalesce(p_platform, '')), ''), platform),
          app_version = coalesce(nullif(trim(coalesce(p_app_version, '')), ''), app_version),
          last_seen_at = v_now,
          last_validate_at = v_now,
          grace_ends_at = v_now + make_interval(hours => v_license.grace_hours),
          replacement_state = null,
          replacement_request_id = null,
          replacement_expires_at = null,
          replacement_reason = null,
          replacement_confirmed_at = null,
          replacement_new_device_id = null,
          replacement_new_fingerprint_hash = null,
          replacement_new_platform = null,
          replacement_new_app_version = null,
          version = version + 1
    where id = v_device.id
    returning * into v_device;
  end if;

  v_access_token := public.fn_license_issue_raw_token(32);
  v_refresh_token := public.fn_license_issue_raw_token(48);
  v_access_hash := public.fn_license_token_hash(v_access_token);
  v_refresh_hash := public.fn_license_token_hash(v_refresh_token);
  v_access_exp := v_now + interval '20 minutes';
  v_refresh_exp := v_now + interval '30 days';
  v_grace_ends := coalesce(v_device.grace_ends_at, v_now);

  insert into public.license_sessions (
    license_id, device_row_id, device_id, state,
    access_token_hash, refresh_token_hash,
    issued_at, access_expires_at, refresh_expires_at, last_seen_at
  )
  values (
    v_license.id, v_device.id, v_device.device_id, 'active',
    v_access_hash, v_refresh_hash,
    v_now, v_access_exp, v_refresh_exp, v_now
  )
  returning id into v_session_id;

  perform public.fn_license_log_event(
    'activate',
    v_license.id,
    v_device.id,
    v_session_id,
    jsonb_build_object('app_version', p_app_version, 'platform', p_platform),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  v_response := jsonb_build_object(
    'ok', true,
    'license_status', v_license.status,
    'device_status', v_device.status,
    'access_token', v_access_token,
    'access_expires_at', v_access_exp,
    'refresh_token', v_refresh_token,
    'refresh_expires_at', v_refresh_exp,
    'grace_ends_at', v_grace_ends,
    'entitlements', coalesce(v_license.metadata -> 'entitlements', '{}'::jsonb),
    'server_time', v_now,
    'request_id', v_request_id
  );

  perform public.fn_license_log_event(
    'rpc_activate',
    v_license.id,
    v_device.id,
    v_session_id,
    jsonb_build_object('response', v_response),
    v_request_id,
    p_idempotency_key,
    p_request_ip,
    p_user_agent
  );

  return v_response;
end;
$$;

-- =========
-- RPC: validate_license
-- =========
create or replace function public.validate_license(
  p_access_token text,
  p_device_id text,
  p_app_version text default null,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_access_hash text := public.fn_license_token_hash(p_access_token);
  v_s public.license_sessions%rowtype;
  v_d public.license_devices%rowtype;
  v_l public.licenses%rowtype;
  v_grace_ends timestamptz;
begin
  if coalesce(trim(p_access_token), '') = '' then
    return public.fn_license_error('invalid_access_token', 'access token is required', false);
  end if;
  if coalesce(trim(p_device_id), '') = '' then
    return public.fn_license_error('invalid_device_id', 'device_id is required', false);
  end if;

  select * into v_s
  from public.license_sessions
  where access_token_hash = v_access_hash
    and deleted_at is null
  limit 1;

  if not found then
    return public.fn_license_error('invalid_access_token', 'session not found', false);
  end if;

  if v_s.state <> 'active' then
    return public.fn_license_error('session_revoked', 'session is not active', false);
  end if;

  if v_s.access_expires_at <= v_now then
    update public.license_sessions
      set state = 'expired',
          version = version + 1
    where id = v_s.id and state = 'active';
    return public.fn_license_error('session_expired', 'access token expired', false);
  end if;

  select * into v_d from public.license_devices where id = v_s.device_row_id and deleted_at is null;
  if not found then
    return public.fn_license_error('device_not_found', 'device binding not found', false);
  end if;

  if v_d.device_id <> trim(p_device_id) then
    return public.fn_license_error('device_mismatch', 'device mismatch', false);
  end if;

  select * into v_l from public.licenses where id = v_s.license_id and deleted_at is null;
  if not found then
    return public.fn_license_error('license_not_found', 'license not found', false);
  end if;

  if v_l.status <> 'active' then
    return public.fn_license_error('license_not_active', 'license is not active', false);
  end if;

  if v_l.expires_at is not null and v_l.expires_at <= v_now then
    update public.licenses set status = 'expired', version = version + 1 where id = v_l.id and status = 'active';
    return public.fn_license_error('license_expired', 'license expired', false);
  end if;

  if v_d.status <> 'active' then
    return public.fn_license_error('device_not_active', 'device is not active', false);
  end if;

  v_grace_ends := v_now + make_interval(hours => v_l.grace_hours);
  update public.license_devices
    set last_seen_at = v_now,
        last_validate_at = v_now,
        app_version = coalesce(nullif(trim(coalesce(p_app_version, '')), ''), app_version),
        last_ip = coalesce(p_request_ip, last_ip),
        grace_ends_at = v_grace_ends,
        version = version + 1
  where id = v_d.id;

  update public.license_sessions
    set last_seen_at = v_now,
        version = version + 1
  where id = v_s.id;

  perform public.fn_license_log_event(
    'validate',
    v_l.id,
    v_d.id,
    v_s.id,
    jsonb_build_object('app_version', p_app_version),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  return jsonb_build_object(
    'ok', true,
    'effective_status', 'licensed',
    'license_status', v_l.status,
    'device_status', v_d.status,
    'grace_ends_at', v_grace_ends,
    'entitlements', coalesce(v_l.metadata -> 'entitlements', '{}'::jsonb),
    'server_time', v_now,
    'request_id', v_request_id
  );
end;
$$;

-- =========
-- RPC: heartbeat_license
-- =========
create or replace function public.heartbeat_license(
  p_access_token text,
  p_device_id text,
  p_app_version text default null,
  p_client_time timestamptz default null,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_valid jsonb;
  v_access_hash text := public.fn_license_token_hash(p_access_token);
  v_s public.license_sessions%rowtype;
  v_d public.license_devices%rowtype;
  v_l public.licenses%rowtype;
  v_grace_ends timestamptz;
begin
  v_valid := public.validate_license(p_access_token, p_device_id, p_app_version, p_request_ip, p_user_agent);
  if coalesce((v_valid ->> 'ok')::boolean, false) = false then
    return v_valid;
  end if;

  select * into v_s from public.license_sessions where access_token_hash = v_access_hash and deleted_at is null limit 1;
  select * into v_d from public.license_devices where id = v_s.device_row_id and deleted_at is null;
  select * into v_l from public.licenses where id = v_s.license_id and deleted_at is null;

  v_grace_ends := v_now + make_interval(hours => v_l.grace_hours);
  update public.license_devices
    set last_seen_at = v_now,
        last_heartbeat_at = v_now,
        app_version = coalesce(nullif(trim(coalesce(p_app_version, '')), ''), app_version),
        last_ip = coalesce(p_request_ip, last_ip),
        grace_ends_at = v_grace_ends,
        version = version + 1
  where id = v_d.id;

  perform public.fn_license_log_event(
    'heartbeat',
    v_l.id,
    v_d.id,
    v_s.id,
    jsonb_build_object('client_time', p_client_time),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  return jsonb_build_object(
    'ok', true,
    'effective_status', 'licensed',
    'grace_ends_at', v_grace_ends,
    'next_heartbeat_at', v_now + interval '6 hours',
    'server_time', v_now,
    'request_id', v_request_id
  );
end;
$$;

-- =========
-- RPC: refresh_session
-- =========
create or replace function public.refresh_session(
  p_refresh_token text,
  p_device_id text,
  p_idempotency_key text,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_existing jsonb;
  v_response jsonb;
  v_refresh_hash text := public.fn_license_token_hash(p_refresh_token);
  v_old public.license_sessions%rowtype;
  v_d public.license_devices%rowtype;
  v_l public.licenses%rowtype;
  v_new_session_id uuid;
  v_access_token text;
  v_refresh_token text;
  v_access_hash text;
  v_new_refresh_hash text;
  v_access_exp timestamptz;
  v_refresh_exp timestamptz;
  v_grace_ends timestamptz;
begin
  if coalesce(trim(p_idempotency_key), '') = '' then
    return public.fn_license_error('missing_idempotency_key', 'idempotency_key is required', false);
  end if;
  if coalesce(trim(p_refresh_token), '') = '' then
    return public.fn_license_error('invalid_refresh_token', 'refresh token is required', false);
  end if;
  if coalesce(trim(p_device_id), '') = '' then
    return public.fn_license_error('invalid_device_id', 'device_id is required', false);
  end if;

  perform public.fn_license_lock_idempotency('refresh_session', p_idempotency_key);
  v_existing := public.fn_license_get_idempotent_response('rpc_refresh', p_idempotency_key);
  if v_existing is not null then
    return v_existing;
  end if;

  select *
  into v_old
  from public.license_sessions
  where refresh_token_hash = v_refresh_hash
    and deleted_at is null
  for update;

  if not found then
    v_response := public.fn_license_error('invalid_refresh_token', 'refresh token not found', false);
    perform public.fn_license_log_event('rpc_refresh', null, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if v_old.state = 'rotated' then
    update public.license_sessions
      set state = 'compromised',
          compromised_at = v_now,
          revoked_reason = 'refresh_token_reused',
          version = version + 1
    where id = v_old.id and state = 'rotated';

    update public.license_sessions
      set state = 'compromised',
          compromised_at = v_now,
          revoked_reason = 'refresh_token_reused',
          version = version + 1
    where device_row_id = v_old.device_row_id
      and state = 'active'
      and deleted_at is null;

    perform public.fn_license_log_event(
      'compromise_detected',
      v_old.license_id,
      v_old.device_row_id,
      v_old.id,
      jsonb_build_object('reason', 'refresh_token_reused'),
      v_request_id,
      null,
      p_request_ip,
      p_user_agent
    );
    v_response := public.fn_license_error('refresh_token_reused', 'refresh token reuse detected', false);
    perform public.fn_license_log_event('rpc_refresh', v_old.license_id, v_old.device_row_id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if v_old.state <> 'active' then
    v_response := public.fn_license_error('session_revoked', 'session is not active', false);
    perform public.fn_license_log_event('rpc_refresh', v_old.license_id, v_old.device_row_id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if v_old.refresh_expires_at <= v_now then
    update public.license_sessions
      set state = 'expired',
          version = version + 1
    where id = v_old.id and state = 'active';
    v_response := public.fn_license_error('session_expired', 'refresh token expired', false);
    perform public.fn_license_log_event('rpc_refresh', v_old.license_id, v_old.device_row_id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select * into v_d from public.license_devices where id = v_old.device_row_id and deleted_at is null for update;
  if not found then
    v_response := public.fn_license_error('device_not_found', 'device not found', false);
    perform public.fn_license_log_event('rpc_refresh', v_old.license_id, v_old.device_row_id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;
  if v_d.device_id <> trim(p_device_id) then
    v_response := public.fn_license_error('device_mismatch', 'device mismatch', false);
    perform public.fn_license_log_event('rpc_refresh', v_old.license_id, v_old.device_row_id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;
  if v_d.status <> 'active' then
    v_response := public.fn_license_error('device_not_active', 'device is not active', false);
    perform public.fn_license_log_event('rpc_refresh', v_old.license_id, v_d.id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select * into v_l from public.licenses where id = v_old.license_id and deleted_at is null for update;
  if not found then
    v_response := public.fn_license_error('license_not_found', 'license not found', false);
    perform public.fn_license_log_event('rpc_refresh', v_old.license_id, v_d.id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;
  if v_l.status <> 'active' then
    v_response := public.fn_license_error('license_not_active', 'license is not active', false);
    perform public.fn_license_log_event('rpc_refresh', v_l.id, v_d.id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;
  if v_l.expires_at is not null and v_l.expires_at <= v_now then
    update public.licenses set status = 'expired', version = version + 1 where id = v_l.id and status = 'active';
    v_response := public.fn_license_error('license_expired', 'license expired', false);
    perform public.fn_license_log_event('rpc_refresh', v_l.id, v_d.id, v_old.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  v_access_token := public.fn_license_issue_raw_token(32);
  v_refresh_token := public.fn_license_issue_raw_token(48);
  v_access_hash := public.fn_license_token_hash(v_access_token);
  v_new_refresh_hash := public.fn_license_token_hash(v_refresh_token);
  v_access_exp := v_now + interval '20 minutes';
  v_refresh_exp := v_now + interval '30 days';
  v_grace_ends := v_now + make_interval(hours => v_l.grace_hours);

  insert into public.license_sessions (
    license_id, device_row_id, device_id, state,
    access_token_hash, refresh_token_hash,
    issued_at, access_expires_at, refresh_expires_at, last_seen_at
  )
  values (
    v_l.id, v_d.id, v_d.device_id, 'active',
    v_access_hash, v_new_refresh_hash,
    v_now, v_access_exp, v_refresh_exp, v_now
  )
  returning id into v_new_session_id;

  update public.license_sessions
    set state = 'rotated',
        rotated_at = v_now,
        replaced_by_session_id = v_new_session_id,
        version = version + 1
  where id = v_old.id
    and state = 'active';

  update public.license_devices
    set last_seen_at = v_now,
        grace_ends_at = v_grace_ends,
        version = version + 1
  where id = v_d.id;

  perform public.fn_license_log_event(
    'refresh',
    v_l.id,
    v_d.id,
    v_new_session_id,
    '{}'::jsonb,
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  v_response := jsonb_build_object(
    'ok', true,
    'access_token', v_access_token,
    'refresh_token', v_refresh_token,
    'access_expires_at', v_access_exp,
    'refresh_expires_at', v_refresh_exp,
    'license_status', v_l.status,
    'device_status', v_d.status,
    'grace_ends_at', v_grace_ends,
    'server_time', v_now,
    'request_id', v_request_id
  );

  perform public.fn_license_log_event(
    'rpc_refresh',
    v_l.id,
    v_d.id,
    v_new_session_id,
    jsonb_build_object('response', v_response),
    v_request_id,
    p_idempotency_key,
    p_request_ip,
    p_user_agent
  );

  return v_response;
end;
$$;

-- =========
-- RPC: list_my_devices
-- =========
create or replace function public.list_my_devices(
  p_access_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_check jsonb;
  v_now timestamptz := now();
  v_hash text := public.fn_license_token_hash(p_access_token);
  v_s public.license_sessions%rowtype;
  v_items jsonb;
begin
  v_check := public.validate_license(p_access_token, coalesce(
    (select device_id from public.license_sessions where access_token_hash = v_hash and deleted_at is null limit 1),
    ''
  ));
  if coalesce((v_check ->> 'ok')::boolean, false) = false then
    return v_check;
  end if;

  select * into v_s from public.license_sessions where access_token_hash = v_hash and deleted_at is null limit 1;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'device_id', d.device_id,
        'status', d.status,
        'activated_at', d.activated_at,
        'last_seen_at', d.last_seen_at,
        'app_version', d.app_version,
        'platform', d.platform,
        'grace_ends_at', d.grace_ends_at,
        'is_current', (d.id = v_s.device_row_id)
      )
      order by (d.id = v_s.device_row_id) desc, d.last_seen_at desc nulls last
    ),
    '[]'::jsonb
  )
  into v_items
  from public.license_devices d
  where d.license_id = v_s.license_id
    and d.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'devices', v_items,
    'server_time', v_now
  );
end;
$$;

-- =========
-- RPC: request_device_replacement
-- =========
create or replace function public.request_device_replacement(
  p_access_token text,
  p_new_device_id text,
  p_new_device_fingerprint_hash text,
  p_target_old_device_id text,
  p_reason text,
  p_idempotency_key text,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_existing jsonb;
  v_response jsonb;
  v_hash text := public.fn_license_token_hash(p_access_token);
  v_s public.license_sessions%rowtype;
  v_l public.licenses%rowtype;
  v_old public.license_devices%rowtype;
  v_active_count integer;
  v_replace_id uuid := gen_random_uuid();
  v_expires timestamptz := now() + interval '15 minutes';
begin
  if coalesce(trim(p_idempotency_key), '') = '' then
    return public.fn_license_error('missing_idempotency_key', 'idempotency_key is required', false);
  end if;
  if coalesce(trim(p_new_device_id), '') = '' then
    return public.fn_license_error('invalid_new_device_id', 'new_device_id is required', false);
  end if;
  if length(trim(coalesce(p_new_device_fingerprint_hash, ''))) < 16 then
    return public.fn_license_error('invalid_device_fingerprint', 'new device fingerprint is invalid', false);
  end if;
  if coalesce(trim(p_target_old_device_id), '') = '' then
    return public.fn_license_error('target_device_required', 'target old device is required', false);
  end if;

  perform public.fn_license_lock_idempotency('request_device_replacement', p_idempotency_key);
  v_existing := public.fn_license_get_idempotent_response('rpc_request_replacement', p_idempotency_key);
  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_s from public.license_sessions
  where access_token_hash = v_hash and state = 'active' and deleted_at is null
  for update;
  if not found or v_s.access_expires_at <= v_now then
    v_response := public.fn_license_error('invalid_access_token', 'active session required', false);
    perform public.fn_license_log_event('rpc_request_replacement', null, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select * into v_l from public.licenses where id = v_s.license_id and deleted_at is null for update;
  if not found or v_l.status <> 'active' then
    v_response := public.fn_license_error('license_not_active', 'license is not active', false);
    perform public.fn_license_log_event('rpc_request_replacement', v_s.license_id, v_s.device_row_id, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if trim(p_new_device_id) = trim(p_target_old_device_id) then
    v_response := public.fn_license_error('replacement_invalid', 'new and old device must differ', false);
    perform public.fn_license_log_event('rpc_request_replacement', v_l.id, v_s.device_row_id, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select count(*) into v_active_count
  from public.license_devices
  where license_id = v_l.id and status = 'active' and deleted_at is null;

  if v_active_count < v_l.max_devices then
    v_response := public.fn_license_error('replacement_not_needed', 'active slots are still available', false);
    perform public.fn_license_log_event('rpc_request_replacement', v_l.id, null, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if exists (
    select 1
    from public.license_devices d
    where d.license_id = v_l.id
      and d.deleted_at is null
      and d.status = 'pending_replacement'
      and d.replacement_state in ('requested', 'awaiting_confirmation', 'executing')
      and d.replacement_expires_at > v_now
  ) then
    v_response := public.fn_license_error('replacement_conflict', 'another replacement request is already active', false);
    perform public.fn_license_log_event('rpc_request_replacement', v_l.id, null, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select * into v_old
  from public.license_devices
  where license_id = v_l.id
    and device_id = trim(p_target_old_device_id)
    and deleted_at is null
  for update;

  if not found or v_old.status <> 'active' then
    v_response := public.fn_license_error('target_device_not_active', 'target old device must be active', false);
    perform public.fn_license_log_event('rpc_request_replacement', v_l.id, null, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  begin
    update public.license_devices
      set status = 'pending_replacement',
          replacement_state = 'awaiting_confirmation',
          replacement_request_id = v_replace_id,
          replacement_expires_at = v_expires,
          replacement_reason = nullif(trim(coalesce(p_reason, '')), ''),
          replacement_new_device_id = trim(p_new_device_id),
          replacement_new_fingerprint_hash = trim(p_new_device_fingerprint_hash),
          replacement_new_platform = null,
          replacement_new_app_version = null,
          version = version + 1
    where id = v_old.id;
  exception
    when unique_violation then
      v_response := public.fn_license_error('replacement_conflict', 'another replacement request is already active', false);
      perform public.fn_license_log_event('rpc_request_replacement', v_l.id, v_old.id, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
      return v_response;
  end;

  perform public.fn_license_log_event(
    'replacement_requested',
    v_l.id,
    v_old.id,
    v_s.id,
    jsonb_build_object(
      'replacement_request_id', v_replace_id,
      'target_old_device_id', p_target_old_device_id,
      'new_device_id', p_new_device_id
    ),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  v_response := jsonb_build_object(
    'ok', true,
    'replacement_request_id', v_replace_id,
    'state', 'awaiting_confirmation',
    'expires_at', v_expires,
    'server_time', v_now,
    'request_id', v_request_id
  );

  perform public.fn_license_log_event(
    'rpc_request_replacement',
    v_l.id,
    v_old.id,
    v_s.id,
    jsonb_build_object('response', v_response),
    v_request_id,
    p_idempotency_key,
    p_request_ip,
    p_user_agent
  );

  return v_response;
end;
$$;

-- =========
-- RPC: confirm_device_replacement
-- =========
create or replace function public.confirm_device_replacement(
  p_access_token text,
  p_replacement_request_id uuid,
  p_idempotency_key text,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_existing jsonb;
  v_response jsonb;
  v_hash text := public.fn_license_token_hash(p_access_token);
  v_s public.license_sessions%rowtype;
  v_l public.licenses%rowtype;
  v_old public.license_devices%rowtype;
  v_new public.license_devices%rowtype;
  v_access_token text;
  v_refresh_token text;
  v_access_hash text;
  v_refresh_hash text;
  v_access_exp timestamptz;
  v_refresh_exp timestamptz;
  v_new_session_id uuid;
  v_grace_ends timestamptz;
begin
  if p_replacement_request_id is null then
    return public.fn_license_error('replacement_request_required', 'replacement_request_id is required', false);
  end if;
  if coalesce(trim(p_idempotency_key), '') = '' then
    return public.fn_license_error('missing_idempotency_key', 'idempotency_key is required', false);
  end if;

  perform public.fn_license_lock_idempotency('confirm_device_replacement', p_idempotency_key);
  v_existing := public.fn_license_get_idempotent_response('rpc_confirm_replacement', p_idempotency_key);
  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_s
  from public.license_sessions
  where access_token_hash = v_hash
    and state = 'active'
    and deleted_at is null
  for update;

  if not found or v_s.access_expires_at <= v_now then
    v_response := public.fn_license_error('invalid_access_token', 'active session required', false);
    perform public.fn_license_log_event('rpc_confirm_replacement', null, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select * into v_l from public.licenses where id = v_s.license_id and deleted_at is null for update;
  if not found or v_l.status <> 'active' then
    v_response := public.fn_license_error('license_not_active', 'license is not active', false);
    perform public.fn_license_log_event('rpc_confirm_replacement', v_s.license_id, v_s.device_row_id, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  select * into v_old
  from public.license_devices
  where license_id = v_l.id
    and replacement_request_id = p_replacement_request_id
    and deleted_at is null
  for update;

  if not found then
    v_response := public.fn_license_error('replacement_request_not_found', 'replacement request not found', false);
    perform public.fn_license_log_event('rpc_confirm_replacement', v_l.id, null, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if v_old.status <> 'pending_replacement' or v_old.replacement_state <> 'awaiting_confirmation' then
    v_response := public.fn_license_error('replacement_request_conflict', 'replacement state is not confirmable', false);
    perform public.fn_license_log_event('rpc_confirm_replacement', v_l.id, v_old.id, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if v_old.replacement_expires_at is null or v_old.replacement_expires_at <= v_now then
    update public.license_devices
      set replacement_state = 'expired',
          status = 'active',
          replacement_reason = coalesce(replacement_reason, 'expired'),
          version = version + 1
    where id = v_old.id;
    v_response := public.fn_license_error('replacement_request_expired', 'replacement request expired', false);
    perform public.fn_license_log_event('replacement_expired', v_l.id, v_old.id, v_s.id, jsonb_build_object('replacement_request_id', p_replacement_request_id), v_request_id, null, p_request_ip, p_user_agent);
    perform public.fn_license_log_event('rpc_confirm_replacement', v_l.id, v_old.id, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  update public.license_devices
    set replacement_state = 'executing',
        version = version + 1
  where id = v_old.id;

  select * into v_new
  from public.license_devices
  where license_id = v_l.id
    and device_id = v_old.replacement_new_device_id
    and deleted_at is null
  for update;

  if found and v_new.status in ('revoked', 'blocked') then
    v_response := public.fn_license_error('target_device_revoked', 'new device is blocked or revoked', false);
    perform public.fn_license_log_event('rpc_confirm_replacement', v_l.id, v_old.id, v_s.id, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  if not found then
    insert into public.license_devices (
      license_id, device_id, device_fingerprint_hash, platform, app_version,
      status, activated_at, last_seen_at, last_validate_at, grace_ends_at
    )
    values (
      v_l.id,
      v_old.replacement_new_device_id,
      v_old.replacement_new_fingerprint_hash,
      v_old.replacement_new_platform,
      v_old.replacement_new_app_version,
      'active',
      v_now,
      v_now,
      v_now,
      v_now + make_interval(hours => v_l.grace_hours)
    )
    returning * into v_new;
  else
    update public.license_devices
      set status = 'active',
          device_fingerprint_hash = coalesce(v_old.replacement_new_fingerprint_hash, device_fingerprint_hash),
          platform = coalesce(v_old.replacement_new_platform, platform),
          app_version = coalesce(v_old.replacement_new_app_version, app_version),
          last_seen_at = v_now,
          last_validate_at = v_now,
          grace_ends_at = v_now + make_interval(hours => v_l.grace_hours),
          version = version + 1
    where id = v_new.id
    returning * into v_new;
  end if;

  update public.license_devices
    set status = 'released',
        released_at = v_now,
        release_reason = coalesce(replacement_reason, 'device_replacement'),
        replacement_state = 'completed',
        replacement_confirmed_at = v_now,
        version = version + 1
  where id = v_old.id;

  -- Revoke all active sessions on old device.
  update public.license_sessions
    set state = 'revoked',
        revoked_at = v_now,
        revoked_reason = 'device_replacement',
        version = version + 1
  where device_row_id = v_old.id
    and state = 'active'
    and deleted_at is null;

  v_access_token := public.fn_license_issue_raw_token(32);
  v_refresh_token := public.fn_license_issue_raw_token(48);
  v_access_hash := public.fn_license_token_hash(v_access_token);
  v_refresh_hash := public.fn_license_token_hash(v_refresh_token);
  v_access_exp := v_now + interval '20 minutes';
  v_refresh_exp := v_now + interval '30 days';
  v_grace_ends := v_now + make_interval(hours => v_l.grace_hours);

  insert into public.license_sessions (
    license_id, device_row_id, device_id, state,
    access_token_hash, refresh_token_hash,
    issued_at, access_expires_at, refresh_expires_at, last_seen_at
  )
  values (
    v_l.id, v_new.id, v_new.device_id, 'active',
    v_access_hash, v_refresh_hash,
    v_now, v_access_exp, v_refresh_exp, v_now
  )
  returning id into v_new_session_id;

  perform public.fn_license_log_event(
    'replacement_confirmed',
    v_l.id,
    v_new.id,
    v_new_session_id,
    jsonb_build_object(
      'replacement_request_id', p_replacement_request_id,
      'released_device_id', v_old.device_id,
      'activated_device_id', v_new.device_id
    ),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  v_response := jsonb_build_object(
    'ok', true,
    'state', 'completed',
    'released_device_id', v_old.device_id,
    'activated_device_id', v_new.device_id,
    'access_token', v_access_token,
    'refresh_token', v_refresh_token,
    'access_expires_at', v_access_exp,
    'refresh_expires_at', v_refresh_exp,
    'grace_ends_at', v_grace_ends,
    'server_time', v_now,
    'request_id', v_request_id
  );

  perform public.fn_license_log_event(
    'rpc_confirm_replacement',
    v_l.id,
    v_new.id,
    v_new_session_id,
    jsonb_build_object('response', v_response),
    v_request_id,
    p_idempotency_key,
    p_request_ip,
    p_user_agent
  );

  return v_response;
end;
$$;

-- =========
-- Admin RPCs
-- =========

create or replace function public.revoke_license_admin(
  p_license_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_existing jsonb;
  v_response jsonb;
  v_license public.licenses%rowtype;
begin
  if not public.fn_license_is_admin_context() then
    return public.fn_license_error('forbidden', 'admin context required', false);
  end if;
  if p_license_id is null then
    return public.fn_license_error('license_required', 'license id is required', false);
  end if;
  if coalesce(trim(p_idempotency_key), '') = '' then
    return public.fn_license_error('missing_idempotency_key', 'idempotency_key is required', false);
  end if;

  perform public.fn_license_lock_idempotency('revoke_license_admin', p_idempotency_key);
  v_existing := public.fn_license_get_idempotent_response('rpc_admin_revoke_license', p_idempotency_key);
  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_license
  from public.licenses
  where id = p_license_id and deleted_at is null
  for update;

  if not found then
    v_response := public.fn_license_error('license_not_found', 'license not found', false);
    perform public.fn_license_log_event('rpc_admin_revoke_license', p_license_id, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  update public.licenses
    set status = 'revoked',
        revoked_at = v_now,
        revoked_reason = nullif(trim(coalesce(p_reason, '')), ''),
        version = version + 1
  where id = v_license.id;

  update public.license_devices
    set status = 'revoked',
        revoked_at = v_now,
        revoked_reason = coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'license_revoked'),
        version = version + 1
  where license_id = v_license.id
    and deleted_at is null
    and status in ('active', 'pending_replacement', 'released');

  update public.license_sessions
    set state = 'revoked',
        revoked_at = v_now,
        revoked_reason = coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'license_revoked'),
        version = version + 1
  where license_id = v_license.id
    and deleted_at is null
    and state in ('active', 'rotated');

  perform public.fn_license_log_event(
    'revoke_license',
    v_license.id,
    null,
    null,
    jsonb_build_object('reason', p_reason),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  v_response := jsonb_build_object(
    'ok', true,
    'license_id', v_license.id,
    'status', 'revoked',
    'server_time', v_now,
    'request_id', v_request_id
  );

  perform public.fn_license_log_event(
    'rpc_admin_revoke_license',
    v_license.id,
    null,
    null,
    jsonb_build_object('response', v_response),
    v_request_id,
    p_idempotency_key,
    p_request_ip,
    p_user_agent
  );

  return v_response;
end;
$$;

create or replace function public.revoke_device_admin(
  p_license_id uuid,
  p_device_id text,
  p_reason text,
  p_idempotency_key text,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_existing jsonb;
  v_response jsonb;
  v_d public.license_devices%rowtype;
begin
  if not public.fn_license_is_admin_context() then
    return public.fn_license_error('forbidden', 'admin context required', false);
  end if;
  if p_license_id is null or coalesce(trim(p_device_id), '') = '' then
    return public.fn_license_error('invalid_input', 'license_id and device_id are required', false);
  end if;
  if coalesce(trim(p_idempotency_key), '') = '' then
    return public.fn_license_error('missing_idempotency_key', 'idempotency_key is required', false);
  end if;

  perform public.fn_license_lock_idempotency('revoke_device_admin', p_idempotency_key);
  v_existing := public.fn_license_get_idempotent_response('rpc_admin_revoke_device', p_idempotency_key);
  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_d
  from public.license_devices
  where license_id = p_license_id
    and device_id = trim(p_device_id)
    and deleted_at is null
  for update;

  if not found then
    v_response := public.fn_license_error('device_not_found', 'device not found', false);
    perform public.fn_license_log_event('rpc_admin_revoke_device', p_license_id, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  update public.license_devices
    set status = 'revoked',
        revoked_at = v_now,
        revoked_reason = coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'device_revoked_by_admin'),
        version = version + 1
  where id = v_d.id;

  update public.license_sessions
    set state = 'revoked',
        revoked_at = v_now,
        revoked_reason = coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'device_revoked_by_admin'),
        version = version + 1
  where device_row_id = v_d.id
    and deleted_at is null
    and state in ('active', 'rotated');

  perform public.fn_license_log_event(
    'revoke_device',
    v_d.license_id,
    v_d.id,
    null,
    jsonb_build_object('reason', p_reason),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  v_response := jsonb_build_object(
    'ok', true,
    'license_id', v_d.license_id,
    'device_id', v_d.device_id,
    'status', 'revoked',
    'server_time', v_now,
    'request_id', v_request_id
  );

  perform public.fn_license_log_event(
    'rpc_admin_revoke_device',
    v_d.license_id,
    v_d.id,
    null,
    jsonb_build_object('response', v_response),
    v_request_id,
    p_idempotency_key,
    p_request_ip,
    p_user_agent
  );

  return v_response;
end;
$$;

create or replace function public.release_device_admin(
  p_license_id uuid,
  p_device_id text,
  p_reason text,
  p_idempotency_key text,
  p_request_ip inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_request_id uuid := gen_random_uuid();
  v_existing jsonb;
  v_response jsonb;
  v_d public.license_devices%rowtype;
begin
  if not public.fn_license_is_admin_context() then
    return public.fn_license_error('forbidden', 'admin context required', false);
  end if;
  if p_license_id is null or coalesce(trim(p_device_id), '') = '' then
    return public.fn_license_error('invalid_input', 'license_id and device_id are required', false);
  end if;
  if coalesce(trim(p_idempotency_key), '') = '' then
    return public.fn_license_error('missing_idempotency_key', 'idempotency_key is required', false);
  end if;

  perform public.fn_license_lock_idempotency('release_device_admin', p_idempotency_key);
  v_existing := public.fn_license_get_idempotent_response('rpc_admin_release_device', p_idempotency_key);
  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_d
  from public.license_devices
  where license_id = p_license_id
    and device_id = trim(p_device_id)
    and deleted_at is null
  for update;

  if not found then
    v_response := public.fn_license_error('device_not_found', 'device not found', false);
    perform public.fn_license_log_event('rpc_admin_release_device', p_license_id, null, null, jsonb_build_object('response', v_response), v_request_id, p_idempotency_key, p_request_ip, p_user_agent);
    return v_response;
  end if;

  update public.license_devices
    set status = 'released',
        released_at = v_now,
        release_reason = coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'released_by_admin'),
        version = version + 1
  where id = v_d.id;

  update public.license_sessions
    set state = 'revoked',
        revoked_at = v_now,
        revoked_reason = 'device_released',
        version = version + 1
  where device_row_id = v_d.id
    and deleted_at is null
    and state in ('active', 'rotated');

  perform public.fn_license_log_event(
    'release_device',
    v_d.license_id,
    v_d.id,
    null,
    jsonb_build_object('reason', p_reason),
    v_request_id,
    null,
    p_request_ip,
    p_user_agent
  );

  v_response := jsonb_build_object(
    'ok', true,
    'license_id', v_d.license_id,
    'device_id', v_d.device_id,
    'status', 'released',
    'server_time', v_now,
    'request_id', v_request_id
  );

  perform public.fn_license_log_event(
    'rpc_admin_release_device',
    v_d.license_id,
    v_d.id,
    null,
    jsonb_build_object('response', v_response),
    v_request_id,
    p_idempotency_key,
    p_request_ip,
    p_user_agent
  );

  return v_response;
end;
$$;

-- =========
-- Grants
-- =========
revoke all on function public.activate_license(text,text,text,text,text,text,inet,text) from public;
revoke all on function public.validate_license(text,text,text,inet,text) from public;
revoke all on function public.heartbeat_license(text,text,text,timestamptz,inet,text) from public;
revoke all on function public.refresh_session(text,text,text,inet,text) from public;
revoke all on function public.list_my_devices(text) from public;
revoke all on function public.request_device_replacement(text,text,text,text,text,text,inet,text) from public;
revoke all on function public.confirm_device_replacement(text,uuid,text,inet,text) from public;
revoke all on function public.revoke_license_admin(uuid,text,text,inet,text) from public;
revoke all on function public.revoke_device_admin(uuid,text,text,text,inet,text) from public;
revoke all on function public.release_device_admin(uuid,text,text,text,inet,text) from public;

grant execute on function public.activate_license(text,text,text,text,text,text,inet,text) to anon, authenticated, service_role;
grant execute on function public.validate_license(text,text,text,inet,text) to anon, authenticated, service_role;
grant execute on function public.heartbeat_license(text,text,text,timestamptz,inet,text) to anon, authenticated, service_role;
grant execute on function public.refresh_session(text,text,text,inet,text) to anon, authenticated, service_role;
grant execute on function public.list_my_devices(text) to anon, authenticated, service_role;
grant execute on function public.request_device_replacement(text,text,text,text,text,text,inet,text) to anon, authenticated, service_role;
grant execute on function public.confirm_device_replacement(text,uuid,text,inet,text) to anon, authenticated, service_role;

-- Admin RPC are protected in-function by fn_license_is_admin_context (service_role required).
grant execute on function public.revoke_license_admin(uuid,text,text,inet,text) to service_role;
grant execute on function public.revoke_device_admin(uuid,text,text,text,inet,text) to service_role;
grant execute on function public.release_device_admin(uuid,text,text,text,inet,text) to service_role;

commit;
