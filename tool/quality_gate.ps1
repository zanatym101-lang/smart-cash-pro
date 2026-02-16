$ErrorActionPreference = "Stop"

Write-Host "==> flutter pub get"
flutter pub get

Write-Host "==> flutter analyze"
flutter analyze

Write-Host "==> flutter test --coverage"
flutter test --coverage

Write-Host "==> coverage summary"
$minEffective = if ($env:COVERAGE_MIN_EFFECTIVE) { $env:COVERAGE_MIN_EFFECTIVE } else { "38.0" }
if (Get-Command python -ErrorAction SilentlyContinue) {
  python tool/coverage_summary.py --input coverage/lcov.info --out coverage/summary.txt --json coverage/summary.json --min-effective $minEffective
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
  py -3 tool/coverage_summary.py --input coverage/lcov.info --out coverage/summary.txt --json coverage/summary.json --min-effective $minEffective
} else {
  Write-Warning "Python not found; skipping coverage summary generation."
}

Write-Host "==> flutter build apk --release"
flutter build apk --release

Write-Host "Quality gate passed."
Write-Host "APK: build\\app\\outputs\\flutter-apk\\app-release.apk"
Write-Host "Coverage: coverage\\summary.txt"
