# Support / Handoff Note - v1.0.0-rc1

تاريخ التوثيق: 2026-03-21

## ما تم تأجيله بعد v1.0
- أي تغييرات محلية متبقية في `lib/data/app_db_transactions.dart`
- أي تغييرات واسعة أو غير محسومة في `lib/main.dart`
- أي تغييرات control-flow أوسع في `lib/screens/admin_settings_screen.dart`
- الملفات المحلية غير المتتبعة الخاصة بالأدوات أو الملخصات المرحلية
- الاختبارات الثقيلة غير اللازمة لإغلاق `v1.0`

## الملفات الحساسة التي تحتاج مراجعة لاحقًا
- `lib/data/app_db_transactions.dart`
- `lib/main.dart`
- أي licensing/admin logic
- أي flows مرتبطة بـ `approval / settlement / balances`

## أين تبدأ الجلسة القادمة
بعد إنهاء `RC1` بنجاح:
1. مراجعة نتيجة build من Codemagic
2. تنفيذ smoke يدوي سريع على artifact الناتج
3. إذا ظهرت مشكلة:
   - إصلاح صغير فقط
   - ثم `v1.0.0-rc2`
4. إذا لم تظهر مشكلة:
   - الانتقال إلى tag نهائي `v1.0.0`

## ملاحظة تشغيلية
أي فروع محلية مؤجلة أو `stash` حالية ليست جزءًا من `v1.0.0-rc1` ويجب أن تظل خارج مسار الإصدار.
