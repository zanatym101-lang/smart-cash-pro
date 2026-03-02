# ملخص الجلسة والحالة الحالية (Session Handover)

تاريخ: 2026-02-18

## 1) ما هو المشروع
- الاسم: **Smart Cash Pro**
- النوع: Flutter (Android / Windows)
- المجال: إدارة المحافظ الإلكترونية + الدرج + فوري + المستحقات + التقارير + الأمان + النسخ الاحتياطي.

## 2) ما الذي تم إنجازه حتى الآن
- تثبيت منطق محاسبي واضح مع فصل:
  - المحافظ
  - الدرج
  - فوري
  - المستحقات
  - الأرباح
- دعم العمليات:
  - تحويل (نوع1/نوع2_v2 + legacy)
  - استلام (نقدي/خصم/إلكتروني)
  - مصروفات
  - تمويل محفظة
  - تعديل درج
  - فوري (نقدي/آجل + شحن فوري من الدرج)
  - مستحقات (فتح + تحصيل/سداد جزئي وكلي)
- دعم pending/posted + confirm/cancel + rollback بقيود أمان.
- إضافة Daily Close / Reopen مع حوكمة.
- إصلاحات استقرار مهمة (read-only DB, duplicate repair, backup/restore, file sharing).
- تجهيز CI/CD:
  - GitHub Quality Gate
  - Codemagic Android CI + APK/AAB + coverage summary
- رفع التغطية الاختبارية بشكل كبير.

## 3) حالة الجودة الحالية
- `flutter analyze`: ناجح (0 مشاكل)
- `flutter test`: ناجح (88 اختبار)
- coverage effective: `69.13%`
- Accounting Core coverage: `80.32%`

ملفات القياس:
- `coverage/summary.txt`
- `coverage/summary.json`

## 4) قواعد ثابتة يجب عدم كسرها
- المحافظ لا تصبح سالبة.
- الدرج وفوري يمكن أن يصبحا سالبين حسب السيناريو.
- الربح لا يتكرر (خصوصًا فوري آجل + تحصيل claim).
- لا تعديل في منطق محاسبي إلا باتفاق صريح.

## 5) أهم ملفات المنطق
- `lib/data/app_db_transactions.dart`
- `lib/data/app_db_wallets.dart`
- `lib/data/app_db_claims.dart`
- `lib/data/app_db_reports.dart`
- `lib/data/reporting.dart`
- `lib/accounting/engine.dart`
- `lib/accounting/specs.dart`

## 6) المستندات الجاهزة الآن
- تقدم الاختبارات: `docs/testing_progress_report_2026-02-18_ar.md`
- منهج العمل المحاسبي: `docs/accounting_logic_ar.md`
- هذا الملخص: `docs/session_handover_2026-02-18_ar.md`

## 7) خطوات سريعة للتحقق بعد أي تعديل
1. `flutter analyze`
2. `flutter test`
3. `flutter test --coverage`
4. `python tool/coverage_summary.py --input coverage/lcov.info --out coverage/summary.txt --json coverage/summary.json`

## 8) خطة العمل التالية المقترحة
- زيادة تغطية الملفات ذات lost-lines العالية بدون تعديل منطق محاسبي.
- ثم Test Lab دورية على APK release قبل أي نشر واسع.

---
نص مختصر لإعادة تهيئة أي جلسة جديدة:

"نحن نعمل على مشروع Smart Cash Pro داخل `C:\Users\Zanaty\king_wallet_accounting`. المرجع المحاسبي الرسمي موجود في `docs/accounting_logic_ar.md`، وحالة الجودة في `docs/testing_progress_report_2026-02-18_ar.md`. ممنوع تغيير منطق محاسبي دون موافقة صريحة. ابدأ من الحالة الحالية وكمّل التحسينات الاختبارية/الاستقرار." 
