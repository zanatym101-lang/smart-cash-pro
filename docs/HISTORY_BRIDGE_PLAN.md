# AppDb History Bridge Plan

## Purpose

The bridge converts existing AppDb history into clean accounting events without
rewriting or deleting legacy data. AppDb remains the read-only source for
historical rows during migration. Clean events and snapshots become the
calculation source for new UI/reporting work.

## What Still Depends On Legacy

Still active:

- transaction rows in AppDb/Drift
- claim rows and claim settlement rows
- wallet opening balance history
- pending/deferred settlement rows
- audit log and sync outbox records
- SMS-reviewed execution persistence through `AppDbSmsExecutionGateway`
- reports and screens that call `AppDb.instance.getTreasurySnapshot()`

These dependencies cannot be removed until clean event persistence can preserve
the same historical shape and audit/sync behavior.

## Bridge Strategy

`LegacyHistoryBridgeService` reads:

- legacy transactions
- deferred transfer/receive rows
- claim rows
- settlement rows
- wallet funding/opening rows
- SMS-created transaction rows

It emits:

- clean `AccountingEvent` instances
- bridge metadata beside each event:
  - `source = legacy_appdb`
  - `migratedAt`
  - `originalLegacyId`
  - `originalLegacyTable`
  - `originalLegacyKind`

The bridge does not mutate AppDb, does not rewrite IDs, and does not delete
history.

## Replay Strategy

`HistoryReplayService` consumes bridged events and rebuilds:

`bridged events -> buildSnapshot(events) -> AccountingSnapshot`

Replay tests compare rebuilt snapshots with live AppDb summaries for:

- treasury parity
- pending/deferred parity
- claims parity
- profit parity
- customer/deferred story visibility

## Migration Phases

1. Read-only bridge
   - Project legacy rows into clean events.
   - Add replay parity tests.

2. Clean read models
   - Point treasury/report/customer ViewModels at replayed snapshots.
   - Keep AppDb as read-only historical source.

3. Dual write with verification
   - New accounting writes go through UseCases.
   - AppDb writes remain only as compatibility persistence if needed.
   - Compare UseCase snapshots against legacy summaries.

4. Clean write primary
   - UseCases persist clean events directly.
   - AppDb transaction/claim rows become derived/export compatibility views.

5. Legacy removal
   - Remove pilot toggles and shadow comparison code.
   - Remove old formula paths only after parity remains green.

## Rollback Strategy

Rollback is simple during phases 1 and 2 because the bridge is read-only:

- disable clean replay consumers
- continue reading AppDb summaries directly
- retain all existing AppDb data

During dual-write phases:

- keep legacy AppDb writes until event replay has proven parity
- gate clean consumers behind explicit feature flags
- keep mismatch logs and snapshot diffs for forensic review

## Safety Rules

- No history deletion.
- No data rewrite.
- No direct accounting mutation from bridge/replay.
- AppDb remains read-only bridge source.
- Clean engine and `buildSnapshot` become the calculation source.
- SMS/AI remains advisory and review-gated.
- User confirmation remains required for SMS execution.

