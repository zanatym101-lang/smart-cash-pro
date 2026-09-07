# Smart Cash Pro Clean Architecture Final

This document records the target isolated architecture and the current legacy
dependency classification for the isolation phase.

## Final Layers

Target flow:

`UI -> ViewModel -> UseCase -> Repository -> Events -> Snapshot -> UI`

- UI: Flutter screens render state and collect user intent only.
- ViewModel: screen-specific state shaping, validation messages, filters, and
  command orchestration.
- UseCase: the only accounting write boundary.
- Repository: persistence ports for events, snapshots, customers, and history.
- Events: immutable accounting facts from the domain engine.
- Snapshot: read model derived from events by `buildSnapshot`.
- UI read models: `CustomerAccountBuilder` and snapshot-backed view models.

## Event Flow

The clean accounting engine emits domain events such as:

- `OpeningBalancesRecorded`
- `DeferredTransferCreated`
- `DeferredReceiveCreated`
- `WalletDebited`
- `WalletCredited`
- `DrawerAdjusted`
- `PartialCollected`
- `PartialPaid`
- `PendingConfirmed`
- `ClaimOpened`
- `ClaimPartiallySettled`
- `ClaimFullySettled`

Use cases persist events through `EventRepository`, then rebuild and persist the
snapshot through `SnapshotRepository`. Screens must not duplicate formulas for
drawer, wallets, pending amounts, claims, liquidity, or capital.

## SMS And AI Flow

SMS/AI remains advisory:

`SMS inbox -> deterministic parser -> optional AI suggestion -> duplicate check -> review screen -> user confirmation -> use case/execution gateway`

Rules:

- AI never writes accounting directly.
- AI never bypasses review.
- AI output is only a `ParsedTransactionDraft` or advisory metadata.
- Duplicate high confidence blocks.
- Duplicate medium confidence warns and requires override.
- SMS never auto-creates transactions.

## Customer Ledger Flow

Customer account state is a read model:

`AppDb history/events -> CustomerAccountBuilder -> CustomerAccountSummary + ledger rows -> Customers UI`

The builder preserves stories:

- original deferred operation
- partial settlement rows
- open remaining claim
- final settlement

Rows remain separate. Settlements are not merged into the original operation.

## Legacy Dependency Classification

### STILL ACTIVE

These paths still carry production history or live write behavior and must not
be removed until a clean repository writes equivalent history:

- `lib/data/app_db*.dart`
- `lib/data/sqlite/app_database.dart`
- `lib/screens/transfer_screen.dart`
- `lib/screens/receive_screen.dart`
- `lib/screens/claims_screen.dart`
- `lib/screens/customers_screen.dart`
- `lib/screens/pending_screen.dart`
- `lib/screens/tx_details_screen.dart`
- `lib/screens/treasury_screen.dart`
- `lib/screens/fawry_screen.dart`
- `lib/screens/expenses_screen.dart`
- `lib/screens/wallet_funding_screen.dart`
- `lib/ai_sms/sms_execution_gateway.dart`

Reason: these paths still persist live transaction rows, claim rows, audit
records, sync outbox records, wallet history, and SMS-reviewed operations.

### NEEDS BRIDGE

These are clean-compatible but currently bridge from legacy snapshots/history:

- `TreasurySnapshot` in `lib/data/app_db.dart`
- pilot comparison helpers in transfer, receive, and claims screens
- `PilotMismatchLogService`
- `PilotStatusService`
- AppDb-backed SMS execution gateway
- report screens that read AppDb treasury/report data

Required bridge: an AppDb-history-to-event projection or a repository adapter
that preserves existing Drift rows while making domain events the primary write
source.

### SAFE TO REMOVE

Nothing in the current live accounting path is safe to remove blindly yet.
Candidate removal must wait until the bridge proves parity for:

- treasury snapshot
- customer balances
- deferred stories
- claims lifecycle
- SMS reviewed execution
- audit/outbox history

### UNKNOWN

These require a separate pass because they may contain non-accounting state or
admin-only behavior:

- backup/restore internals
- license/admin security storage
- cloud sync and Drive backup services
- generated Drift code
- older `lib/accounting/*` engine once AppDb no longer depends on it

## Isolation Rationale

The project already has a stable clean domain engine, use cases, event
repositories, snapshot builder, SMS/AI advisory flow, duplicate detection, and
customer ledger read model. The remaining risk is not formula correctness; it
is history preservation. Existing AppDb methods still write transaction,
claim, audit, and outbox history that users depend on.

Therefore removal order is:

1. Add migration parity tests.
2. Build AppDb history projection or clean repository bridge.
3. Move screen commands into ViewModels.
4. Route ViewModels through UseCases only.
5. Replace treasury/report calculations with event snapshots.
6. Remove pilot/shadow toggles after clean path is primary.
7. Remove old AppDb accounting formulas only after all history reads use clean
   read models.

## Current Isolation Status

The safe boundary after this pass is:

- Customer account presentation uses `CustomerAccountBuilder`.
- Clean snapshot parity is covered by migration tests.
- SMS/AI remains advisory and review-gated.
- Legacy write paths are explicitly classified and remain active until bridged.

