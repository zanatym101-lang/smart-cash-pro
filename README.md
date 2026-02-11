# King Wallet Accounting

Flutter app for cash drawer + wallets accounting with ledger, pending approvals,
expenses, claims (receivables/payables), and Fawry services.

## Data Storage (Windows)

Local JSON files are stored under the app support directory:

- `%APPDATA%\\king_wallet_accounting\\king_wallet_data.json`
- `%APPDATA%\\king_wallet_accounting\\king_wallet_settings.json`

## Reset / Clear Local Data

Option 1 (in app):
- Admin Settings → "تصفير مع بيانات البداية" أو "تصفير كامل بدون بيانات".

Option 2 (manual):
- Close the app, then delete the two files above.

Note: On next launch the app seeds initial wallets and a drawer deposit.

## Quality Gate

This project includes an automated quality gate in `.github/workflows/quality-gate.yml`.

Every CI run executes:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --release`

Local run (Windows PowerShell):

- `.\tool\quality_gate.ps1`
