# Session Memory

آخر تحديث: 2026-04-25

## مهم

هذا الملف معمول لحفظ ملخص الجلسة الحالية محليًا داخل المشروع.
إذا اختفى الشات من VS Code، نستخدم هذا الملف كنقطة استكمال سريعة.

## حالة المشروع الحالية

- المشروع: `king_wallet_accounting`
- المرحلة الحالية: صيانة آمنة + تثبيت السلوك المحاسبي
- لا يوجد تغيير مطلوب الآن في business logic إلا بطلب صريح

## نقاط محاسبية مهمة تم تثبيتها

### 1) Semantics الحالية للعمليات الآجلة

- `pending transfer` و `pending receive` يؤثران على الأرصدة الفعلية من لحظة الإنشاء
- `availableLiquidityNow == actualTreasuryApproved`
- `realCapitalApproved == actualTreasuryApproved + claimsNet`
- `pendingInflow` و `pendingOutflow` مؤشرات معلوماتية فقط، ولا يجب إضافتهما أو طرحهما مرة ثانية من الرصيد الفعلي

### 2) Bug confirmed ثم fixed

السيناريو:

- pending transfer = 1000
- partial collection = 500
- الخزينة كانت تزيد 500 بشكل صحيح
- ثم عند `confirmPending` كانت ترجع 500 بشكل خاطئ

السبب:

- `confirmPending` كان ينشئ `pending_settlement_adjust` في حالة لا تحتاج adjust

الإصلاح:

- تم منع إنشاء `pending_settlement_adjust` عندما تكون العملية المعلقة مطبقة على الأرصدة من البداية (`appliedOnCreate`)

النتيجة:

- السطر الأصلي يبقى ثابتًا
- `claim_collect` يبقى كسطر مستقل
- `confirmPending` لا يعكس التحصيل السابق خطأ

## تغييرات UI labels الأخيرة

تم توحيد أسماء العرض فقط بدون أي تغيير منطقي:

- `تحويل معلّق` -> `تحويل آجل`
- `استلام معلّق` -> `استلام آجل`
- `فوري آجل معلّق` -> `فوري آجل`

ملفات متأثرة:

- `lib/screens/customers_screen.dart`
- `lib/screens/pending_screen.dart`
- `lib/data/app_db_transactions_settlement.dart`

## اختبارات أضيفت مؤخرًا

- `test/pending_partial_collection_regression_test.dart`
  - يثبت أن partial collection لا يتم عكسه خطأ عند `confirmPending`

- `test/treasury_snapshot_invariant_test.dart`
  - يثبت:
    - `availableLiquidityNow == actualTreasuryApproved`
    - `realCapitalApproved == actualTreasuryApproved + claimsNet`

## نتيجة آخر تحقق

- `flutter test` ناجح
- `dart analyze` ناجح

## ملاحظات مهمة

- توجد تحذيرات `drift` أثناء بعض اختبارات restore عن فتح قاعدة البيانات أكثر من مرة
- هذه التحذيرات ليست failure حاليًا، والاختبارات نفسها تمر

## لو رجعنا بعد اختفاء الشات

ابدأ من هنا وقل:

> اقرأ `SESSION_MEMORY.md` وكمل من آخر حالة

## حقيقة مهمة بخصوص حفظ الشات

أنا أقدر أحفظ لك محتوى الجلسة داخل ملفات محلية مثل هذا الملف.
لكن لا أتحكم مباشرة في سياسة حفظ تاريخ الشات داخل واجهة VS Code نفسها.
لو الامتداد أو الجلسة عندك بيمسح history عند الإغلاق، فهذا غالبًا من إعدادات العميل أو الامتداد، وليس من داخل المشروع.
