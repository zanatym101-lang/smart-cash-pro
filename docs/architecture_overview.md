# King Wallet Accounting Architecture Overview

## Project Overview

King Wallet Accounting is a Flutter/Dart accounting app for electronic-wallet operations. The app stores data locally with SQLite and keeps financial state derived from transactions rather than storing wallet balances as the source of truth.

The core accounting flow is:

- `Txn` data is created by screens and `AppDb`.
- Transaction specs are built in `lib/accounting/specs.dart`.
- Specs are applied by `lib/accounting/engine.dart`.
- Ledger/state is rebuilt from transactions when needed.
- UI balances and reports read derived state from `AppDb` and reporting helpers.

This project has production-sensitive logic. Future changes should prefer small, isolated edits with tests, especially around transactions, ledger, backup/restore, admin security, and customer settlements.

## Main Layers And Modules

- `lib/models/`: Plain data models such as `Txn`, `Wallet`, `Claim`, `DailyClose`, `AppSettings`, `LicenseInfo`, and attachments.
- `lib/accounting/`: Core accounting engine, money helpers, and transaction specs. This layer should stay deterministic and should not depend on UI.
- `lib/data/app_db.dart`: Main data facade and shared part-library entry point.
- `lib/data/app_db_*.dart`: Feature-specific `AppDb` extensions split by responsibility.
- `lib/data/sqlite/`: SQLite persistence backend.
- `lib/data/reporting.dart` and `lib/data/report_exporter.dart`: Report calculations and export helpers.
- `lib/services/`: Service layer for admin security, cloud license checks, notifications, drive backup, and assistant integration.
- `lib/screens/`: Flutter UI screens and extracted screen sections/helpers.
- `test/`: Accounting, safety, serialization, screen smoke, export, and text integrity tests.

## AppDb Data Architecture

`AppDb` is implemented as a Dart part-library. `lib/data/app_db.dart` imports shared dependencies and declares `part` files.

Current important `AppDb` parts:

- `app_db_internal.dart`: loading, saving, shared internal state helpers.
- `app_db_wallets.dart`: wallet management.
- `app_db_transactions.dart`: shared transaction glue/facade helpers.
- `app_db_transactions_create.dart`: create workflows.
- `app_db_transactions_approve.dart`: pending approval workflows.
- `app_db_transactions_cancel.dart`: cancel/reject workflows.
- `app_db_transactions_settlement.dart`: pending settlement adjustments.
- `app_db_claims.dart`: claims and claim settlements.
- `app_db_reports.dart`: report-facing data helpers.
- `app_db_admin.dart`: small shared admin/settings glue.
- `app_db_admin_license.dart`: license and trial behavior.
- `app_db_admin_maintenance.dart`: app settings, developer PIN, quick actions, default fees.
- `app_db_admin_backup.dart`: backup export, JSON export, encrypted backup creation, backup metadata.
- `app_db_admin_restore.dart`: database restore, JSON restore, encrypted restore guard/failure tracking.
- `app_db_audit.dart`: audit chain helpers.
- `app_db_sync.dart`: sync outbox helpers.
- `app_db_health.dart`: integrity and health checks.
- `app_db_contacts.dart` and `app_db_customer_files.dart`: contacts/customer-related support.

Because these are `part` files, private helpers are shared within the same library. This keeps extraction low-risk, but future changes must still avoid accidental name collisions between private extension methods.

## Admin Security Architecture

Admin PIN, biometric settings, and lockout policy are owned by:

- `lib/services/admin_security_service.dart`

UI screens should call `AdminSecurityService`, not direct `AppDb` policy methods.

Relevant screens:

- `lib/screens/admin_gate_screen.dart`
- `lib/screens/admin_settings_screen.dart`
- `lib/screens/admin_settings_security_section.dart`

`AppDb` should remain a raw storage/access backend for settings where needed. Do not reintroduce admin security policy directly into screens or general database code.

## Transaction Workflow Architecture

Transaction logic is split by workflow:

- Create: `app_db_transactions_create.dart`
- Approve pending: `app_db_transactions_approve.dart`
- Cancel/reject: `app_db_transactions_cancel.dart`
- Pending settlement adjustment: `app_db_transactions_settlement.dart`
- Shared transaction helpers: `app_db_transactions.dart`

Important safety points:

- Wallet balances must be changed through transaction/spec/engine/ledger behavior, not by direct balance mutation.
- Pending/deferred transfer and receive behavior is intentionally sensitive. It affects actual wallet liquidity immediately, and approval must not double-apply the impact.
- Canceling an actual-applied deferred transfer/receive must reverse the actual impact safely.
- Rebuild behavior must remain compatible with the transaction list.
- Approval must remain idempotency-safe and must not allow the same transaction to be approved twice.

## Admin Backup, Restore, And License Architecture

Admin storage-related behavior is split into:

- `app_db_admin_backup.dart`: DB backup, JSON backup, encrypted backup, checksum sidecars, backup settings sidecars.
- `app_db_admin_restore.dart`: DB restore, JSON restore, encrypted restore, secure restore lockout.
- `app_db_admin_license.dart`: trial, activation, cloud license sync, local legacy activation behavior where currently allowed.
- `app_db_admin_maintenance.dart`: app settings, developer PIN, quick actions, default network/receive fees.
- `app_db_admin.dart`: shared settings file read/write and admin guard.

Do not change these without tests:

- Backup package format.
- JSON keys.
- Encryption format/version.
- Checksum sidecar behavior.
- Secure restore lockout behavior.
- License/trial counters and activation behavior.

## Reports Screen Structure

The reports UI has been split into focused files:

- `reports_screen.dart`: high-level screen composition and state wiring.
- `reports_date_range_helpers.dart`: date range helpers.
- `reports_export_section.dart`: export UI/actions.
- `reports_summary_cards.dart`: summary cards.
- `reports_tabs_sections.dart`: report tab sections.
- `reports_daily_close_section.dart`: daily close UI section.

Report calculations should stay in data/reporting helpers where possible. Avoid moving financial calculations directly into UI widgets.

## Customers Screen Structure

The customers UI has been reduced into focused helpers:

- `customers_screen.dart`: high-level screen and state wiring.
- `customer_filters_and_sort.dart`: filtering and sorting.
- `customer_bucket_builder.dart`: grouping/bucketing.
- `customer_attachment_actions.dart`: attachment actions.
- `customers_navigation_actions.dart`: navigation helpers.
- `customers_list_section.dart`: list rendering.
- `customer_details_panel.dart`: expanded/details panel.

Customer ledger rows should preserve historical rows. Settlements should add new rows rather than rewriting old financial rows unless explicitly intended and covered by tests.

## Important Safety Rules For Future Changes

- Do not change accounting behavior during structural refactors.
- Do not mutate balances directly without a transaction/ledger path.
- Do not allow approval of the same pending transaction twice.
- Do not change SQLite schema or persistence semantics casually.
- Do not change backup, restore, encryption, or license behavior during unrelated work.
- Preserve Arabic UI text unless the task explicitly asks for text changes.
- Keep changes small: edit, test, review, then continue.
- Prefer extracting code over redesigning architecture when the goal is maintainability.
- When moving code between `part` files, keep method signatures and method bodies unchanged unless a tiny internal rename is required to avoid collisions.
- Be careful with Arabic text encoding. Run text integrity tests after edits that may touch Arabic strings.

## Areas Still Needing Future Refactor

- Further reduce large data modules after each area has stronger targeted tests.
- Continue separating UI composition from business decisions in complex screens.
- Add more focused tests around customer settlement combinations and deferred customer balances.
- Add more focused tests around backup compatibility and corrupted restore inputs.
- Consider gradually moving policy-heavy logic from `AppDb` into service classes, while keeping `AppDb` as storage/facade.
- Review private helper names across `part` files to avoid future extension-name ambiguity.

## Testing Guidance For Risky Changes

Run the smallest relevant tests first, then the full suite before finishing.

Recommended commands:

- `dart analyze`
- `flutter test test/accounting_engine_test.dart`
- `flutter test test/accounting_safety_test.dart`
- `flutter test test/screen_flows_test.dart`
- `flutter test test/screen_heavy_smoke_test.dart`
- `flutter test test/text_integrity_test.dart`
- `flutter test`

For transaction, claim, settlement, approval, rollback, or rebuild changes, always run:

- `flutter test test/accounting_engine_test.dart test/accounting_safety_test.dart`
- `flutter test`

For backup, restore, encryption, or license changes, always run:

- `flutter test test/accounting_safety_test.dart`
- `flutter test test/admin_settings_screen_test.dart test/screen_flows_test.dart`
- `flutter test`

For UI-only structural refactors, run:

- `dart analyze`
- The relevant screen smoke tests.
- `flutter test` before final handoff.
