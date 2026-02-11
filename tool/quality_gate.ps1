$ErrorActionPreference = "Stop"

Write-Host "==> flutter pub get"
flutter pub get

Write-Host "==> flutter analyze"
flutter analyze

Write-Host "==> flutter test"
flutter test

Write-Host "==> flutter build apk --release"
flutter build apk --release

Write-Host "Quality gate passed."
Write-Host "APK: build\\app\\outputs\\flutter-apk\\app-release.apk"
