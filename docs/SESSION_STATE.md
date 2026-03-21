# SESSION_STATE (Smart Cash Pro)

## 2026-03-07 Update (cloud license rollout)
- Cloud license endpoints verified manually:
  - `POST /api/license/activate` ✅
  - `POST /api/license/status` ✅
  - `POST /api/license/refresh` ✅
- Test-suite compatibility restored:
  - Added legacy local activation fallback for non-production/test runs only.
  - Release behavior remains cloud-first.
- Local quality checks:
  - `flutter analyze` ✅
  - `flutter test` ✅ (all passed)
- Android build:
  - `build/app/outputs/flutter-apk/app-release.apk` ✅

## 2026-03-07 Update (developer tools cleanup)
- Removed local activation code generator UI from developer tools by default.
- Added compile-time guard:
  - `SHOW_LEGACY_CODE_GENERATOR=true` shows legacy block only for internal builds.
- Cloud activation remains the only visible activation path in release.
- Rebuilt + installed release APK on connected phone:
  - device `HZQL1838LAKA2700279` ✅

آخر تحديث: 2026-03-05 (تحديث أمني API Assistant)
المشروع: `C:\Users\Zanaty\king_wallet_accounting`

## قواعد عمل ثابتة
- عدم تغيير المنطق المحاسبي إلا بموافقة صريحة من المستخدم.
- بعد أي تعديل: تشغيل تحليل/اختبارات قبل البناء.
- المرجع الأساسي للمتابعة بين الجلسات هو هذا الملف.

## الحالة الحالية المختصرة
- تم الانتهاء من تحسينات كبيرة في العملاء/المستحقات/التقارير خلال الجلسات السابقة.
- اختبارات المشروع المحلية كانت آخر مرة ناجحة (`flutter analyze` و `flutter test`).
- Proxy الذكاء السحابي على Vercel يعمل ويرد، لكن ما زالت هناك نواقص أمان قبل الإطلاق العام.

## النواقص المفتوحة (أولوية من الأعلى)
1. استكمال ضبط بيئة الإنتاج على Vercel:
   - تعيين `ASSISTANT_ALLOWED_ORIGINS`.
   - تعيين `ASSISTANT_CLIENT_TOKEN`.
   - تعيين حدود `ASSISTANT_DAILY_QUOTA` و`ASSISTANT_MONTHLY_QUOTA`.
2. تحسين استجابة المساعد:
   - إجابات أدق مبنية على Snapshot فعلي من التطبيق.
   - تنسيق عربي واضح ومتسق حسب نوع السؤال (مختصر/تفصيلي).
3. إنذار داخل التطبيق قرب نفاد الحصة اليومية/الشهرية.

## ما تم تنفيذه الآن (Backend Security)
- تم إغلاق CORS المفتوح:
  - لم يعد هناك `Access-Control-Allow-Origin: *` بشكل افتراضي.
  - المتصفح يُقبل فقط عند أصل موجود في `ASSISTANT_ALLOWED_ORIGINS`.
- تم تشديد التوثيق في `api/assistant`:
  - إلزام `X-SCP-Client-Id`.
  - تحقق `Token + HMAC Signature + Timestamp + Nonce`.
  - حماية Replay للـ nonce.
- تم إضافة Quota يومي/شهري لكل عميل:
  - `ASSISTANT_DAILY_QUOTA` (افتراضي 1500).
  - `ASSISTANT_MONTHLY_QUOTA` (افتراضي 20000).
  - إرجاع رؤوس متابعة: `X-SCP-Quota-Day-Remaining` و`X-SCP-Quota-Month-Remaining`.

## Security Status Flags (2026-03-06)
- [x] `ASSISTANT_CLIENT_TOKEN` set in Vercel (Production + Preview)
- [x] `ASSISTANT_ALLOWED_ORIGINS` set in Vercel
- [x] `ASSISTANT_DAILY_QUOTA` / `ASSISTANT_MONTHLY_QUOTA` set
- [x] Production redeploy completed
- [x] Endpoint health check returned `answer` + `model`
- [ ] App rebuild with final `--dart-define` token

## ما لا يزال مطلوبًا تأكيده من المستخدم
- هل نبدأ فورًا بخطة الأمان الثلاثية كاملة للـ assistant (CORS + Auth + Quota)؟
- هل الحد اليومي/الشهري يكون موحدًا أم لكل جهاز/عميل؟

## أوامر تحقق سريعة (قبل أي بناء)
```powershell
flutter analyze
flutter test
```

## مخرجات البناء القياسية
- APK Release:
  - `build/app/outputs/flutter-apk/app-release.apk`

## ملاحظة تشغيلية
- أي قرار جديد يُسجل هنا فورًا قبل بدء التنفيذ حتى لا يضيع السياق.

## 2026-03-13 Update (customer balance column fix)
- Fixed customer detail right-side `الرصيد` display logic to show per-line remaining amount more accurately for open claims, pending outstanding lines, and settlement lines.
- Local checks:
  - `flutter analyze` ✅
  - `flutter test` ✅ (all passed)
- Android build:
  - `build/app/outputs/flutter-apk/app-release.apk` ✅
- ADB status during build/install step:
  - no connected devices detected
