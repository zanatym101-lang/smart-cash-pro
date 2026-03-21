# Build Note - v1.0.0-rc1

تاريخ التوثيق: 2026-03-21

## تعريف النسخة
- Release Candidate: `v1.0.0-rc1`
- فرع الإصدار: `release/v1.0.0-rc1`
- baseline المرجعي من `main`: `a3c10ca`

## baseline الذي تم التحقق منه
- `flutter analyze`
- `flutter test`

## مسار الـ CI / Build
ملف الإعداد:
- `codemagic.yaml`

الـ workflow الحالي:
- `android_ci`

الخطوات الأساسية:
- `flutter pub get`
- `flutter analyze`
- `flutter test --coverage --reporter expanded`
- `flutter build apk --release`
- `flutter build appbundle --release`

## الـ artifacts المستهدفة
- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

## ملاحظات مهمة
- هذه النسخة يجب أن تُبنى من نفس نقطة الـ RC فقط
- لا يجوز إدخال تغييرات محلية مؤجلة داخل build الـ RC
- إذا ظهر bug أثناء RC:
  - يُصلح بـ commit صغير
  - ثم ننتقل إلى `v1.0.0-rc2`

