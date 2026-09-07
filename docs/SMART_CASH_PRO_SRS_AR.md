# Smart Cash Pro - مواصفات المتطلبات البرمجية

هذا المستند يصف **السلوك الحالي الفعلي** لتطبيق **Smart Cash Pro** كما هو مستخرج من الكود والاختبارات الحالية، وليس كتصور نظري فقط.

الهدف من المستند:
- توثيق قواعد العمل الحالية
- توثيق المعادلات المحاسبية المعتمدة
- توثيق semantics الصحيحة للعمليات الآجلة والمستحقات
- توثيق أهم invariants والاختبارات الحارسة
- توثيق المخاطر المعروفة حاليًا

---

## 1. نظرة عامة

Smart Cash Pro هو تطبيق إدارة سيولة ومحافظ وتحويلات واستلامات ومتابعة آجِل ومستحقات، مع دعم:
- الخزنة (الدرج)
- المحافظ
- العمليات الفورية والآجلة
- المستحقات لنا/علينا
- المصروفات
- التقارير
- النسخ الاحتياطي والاسترجاع
- نظام ترخيص محلي/سحابي هجين

---

## 2. أنواع العمليات الحالية

### 2.1 العمليات الأساسية
- **تحويل** `transfer`
  - تحويل عادي
  - تحويل آجل
  - الأنواع:
    - `type1`
    - `type2_v2`
    - دعم legacy `type2`

- **استلام** `receive`
  - استلام عادي
  - استلام آجل
  - الأوضاع:
    - `cash`
    - `deduct`
    - `electronic`

### 2.2 الآجل والتسويات
- **تحويل آجل**
- **استلام آجل**
- **تحصيل جزئي** من عملية آجلة
  - `claim_collect`
- **سداد جزئي** لعملية آجلة
  - `claim_pay`
- **تنفيذ المعلق**
  - `confirmPending(...)`
- **إلغاء المعلق**
  - `cancelPending(...)`
- **قيد ضبط تسوية الآجل**
  - `pending_settlement_adjust`

### 2.3 المستحقات
- **فتح مستحق لنا**
  - `claim_open_receivable`
- **فتح مستحق علينا**
  - `claim_open_payable`
- **تحصيل مستحق**
  - `claim_collect`
- **سداد مستحق**
  - `claim_pay`

### 2.4 التمويل والمصروفات
- **تمويل محفظة**
  - `external_funding`
- **إيداع/تعديل درج**
  - `drawer_deposit`
- **مصروفات**
  - `expense`

### 2.5 فوري (مدعوم داخليًا)
- `fawry_cash`
- `fawry_credit`
- `fawry_fund_drawer`

> ملاحظة: تم إخفاء فوري من أجزاء من الواجهة، لكن الدعم المحاسبي والتاريخي ما زال موجودًا داخليًا.

### 2.6 العمليات الإدارية
- **Rollback**
  - `rollback`
- **استرجاع/نسخ احتياطي**
- **الترخيص والتفعيل**

---

## 3. قواعد العمل Business Rules

### 3.1 قواعد عامة
- لا يجوز اعتماد العملية مرتين.
- لا يجوز إلغاء عملية معتمدة.
- لا يجوز تسوية مبلغ أكبر من المتبقي.
- لا يجوز rollback لتسوية ليست الأخيرة في تسلسلها.

### 3.2 قواعد العمليات الآجلة
- العمليات الآجلة (`transfer` / `receive` / `fawry_credit`) **تتطلب اختيار عميل**.
- التحصيل الجزئي/السداد الجزئي لا يعدل السطر الأصلي.
- كل تحصيل/سداد جزئي يظهر كسطر مستقل.
- `confirmPending`:
  - يحوّل العملية من `pending` إلى `posted`
  - إذا بقي مبلغ مفتوح ينشئ مستحقًا مفتوحًا
  - لا يضيف cash effect مرة ثانية

### 3.3 قواعد المستحقات
- المستحق نوعان:
  - `receivable` لنا
  - `payable` علينا
- يمكن فتح المستحق:
  - مباشرة
  - أو نتيجة باقي عملية آجلة بعد `confirmPending`
  - أو من `fawry_credit`

### 3.4 قواعد العرض
- **المبلغ الأصلي** للعملية الأصلية يجب أن يبقى محفوظًا في السجل والتقرير.
- **المتبقي المفتوح** يجب أن يُعرض كمعلومة منفصلة، وليس باستبدال الأصل.
- التسويات تظهر كصفوف مستقلة.

---

## 4. المعادلات المحاسبية الحالية

المصدر الأساسي:
- `TreasurySnapshot` في `lib/data/app_db.dart`

### 4.1 الخزنة الفعلية المعتمدة

```text
actualTreasuryApproved =
  drawerActualBalance +
  walletsActualTotal +
  fawryActualBalance
```

### 4.2 السيولة المتاحة

```text
availableLiquidityNow = actualTreasuryApproved
```

المعنى الحالي:
- **Cash-only**
- لا تُضاف ولا تُطرح قيم `pendingInflow` أو `pendingOutflow` مرة ثانية

### 4.3 صافي المستحقات

```text
claimsNet =
  (claimsReceivableOpen + pendingReceivableOpen) -
  (claimsPayableOpen + pendingPayableOpen)
```

### 4.4 رأس المال الحقيقي

```text
realCapitalApproved = actualTreasuryApproved + claimsNet
```

### 4.5 KPIs الآجل

```text
pendingNet   = pendingInflow - pendingOutflow
pendingTotal = pendingInflow + pendingOutflow
```

المعنى:
- مؤشرات معلوماتية فقط
- ليست تصحيحًا إضافيًا للسيولة

---

## 5. معنى كل قيمة

### 5.1 الأرصدة الفعلية
- `drawerActualBalance`
  - رصيد الدرج الفعلي من العمليات المعتمدة
- `walletsActualTotal`
  - مجموع أرصدة المحافظ الفعلية
- `fawryActualBalance`
  - رصيد فوري الداخلي

### 5.2 الالتزامات/المفتوح
- `claimsReceivableOpen`
  - مستحقات مفتوحة لنا
- `claimsPayableOpen`
  - مستحقات مفتوحة علينا
- `pendingReceivableOpen`
  - متبقي التحويلات/الآجل المفتوح لنا قبل الاعتماد النهائي
- `pendingPayableOpen`
  - متبقي الاستلامات الآجلة المفتوح علينا قبل الاعتماد النهائي

### 5.3 مؤشرات الآجل
- `pendingInflow`
  - أثر pending receive على المحافظ
- `pendingOutflow`
  - أثر pending transfer على المحافظ

---

## 6. Semantics الصحيحة للآجل

هذه من أهم قواعد النظام الحالية:

### 6.1 pending transfer
- **لا يزيد الدرج وقت الإنشاء**
- يخفض المحفظة فقط
- يفتح حقًا/ذمة على العميل

### 6.2 pending receive
- لا يعمل pre-credit أو pre-debit غير صحيح للدرج عند الإنشاء
- يؤثر على المحفظة فقط حسب النوع

### 6.3 دخول الكاش
- الكاش يدخل فقط عند:
  - `claim_collect`
  - أو `claim_pay`

### 6.4 الحفاظ على الأصل
- الصف الأصلي يحافظ على:
  - المبلغ الأصلي
  - التاريخ الأصلي
- المتبقي يظهر كمعلومة منفصلة

### 6.5 التسويات الجزئية
- تسوية كل جزء تظهر كسطر مستقل
- لا يجوز تعديل السطر الأصلي ليصبح هو المتبقي

### 6.6 confirmPending
- لا يكرر cash effect
- إذا بقي مبلغ مفتوح:
  - ينشئ claim مفتوح
- إذا أُغلق كاملًا:
  - لا يضيف cash جديد

---

## 7. تأثير كل عملية على الدرج والمحافظ والمستحقات

### 7.1 transfer
- المحفظة:
  - تنخفض
- الدرج:
  - يتأثر فقط إذا كانت العملية ليست deferred cashless
- في الآجل الحالي:
  - لا يحدث pre-credit للدرج عند الإنشاء

### 7.2 receive
- المحفظة:
  - تزيد
- الدرج:
  - يتأثر فقط حسب mode وعند التوقيت الصحيح

### 7.3 claim_collect
- يزيد الدرج

### 7.4 claim_pay
- ينقص الدرج

### 7.5 claim_open_receivable
- يفتح مستحقًا لنا

### 7.6 claim_open_payable
- يفتح مستحقًا علينا

### 7.7 expense
- ينقص الدرج

### 7.8 external_funding
- يزيد المحفظة

### 7.9 drawer_deposit
- يزيد/يعدل الدرج

### 7.10 fawry_cash
- الدرج: `amount + fee`
- فوري: `-amount`

### 7.11 fawry_credit
- فوري: `-amount`
- ثم ينشئ claim على العميل

---

## 8. شاشة العميل، التقرير، والداشبورد

### 8.1 شاشة العميل
- summary يعرض **المتبقي المفتوح الحقيقي**
- الصف الأصلي يعرض **الأصل**
- صف التحصيل/السداد يظهر مستقلًا

### 8.2 تقرير العميل
- `currentReceivable = openReceivable + pendingReceivable`
- `currentPayable = openPayable + pendingPayable`
- `statementRows` تحفظ:
  - الأصل
  - التحصيل/السداد
  - المستحق المفتوح

### 8.3 Dashboard
- بطاقة الآجل المفتوح تعرض **المتبقي المفتوح الحقيقي**
- داخل/خارج الأجل والفرق مبنية على remaining open
- السيولة تعرض cash-only

### 8.4 PDF / Excel
- التصدير يعتمد على `statementRows`
- وبالتالي يحافظ على:
  - الصف الأصلي
  - صف التسوية
  - صف المتبقي المفتوح

---

## 9. المحافظ والخزنة

### 9.1 الخزنة
- يوجد:
  - درج فعلي
  - خزنة فعلية كلية
- الخزنة الفعلية = درج + محافظ + فوري فعلي

### 9.2 المحافظ
- كل محفظة لها:
  - رصيد فعلي
  - تأثير معلق
  - حدود يومية/شهرية
  - تنبيهات رصيد منخفض

### 9.3 التحقق من الرصيد
- لا يُسمح بمحفظة سالبة في الحالات غير المسموح بها
- توجد حماية ضد negative posted / negative available

---

## 10. المستحقات Claims

### 10.1 الأنواع
- `receivable`
- `payable`

### 10.2 السلوك
- فتح مستحق
- تسوية كاملة
- تسوية جزئية
- rollback لتسوية المستحق الأخيرة فقط

### 10.3 العرض الزمني
- في شاشة المستحقات:
  - الأصل
  - ثم التحصيل/السداد
  - ثم المتبقي المفتوح

---

## 11. المصروفات

- المصروف ينقص الدرج
- المصروف له:
  - مبلغ
  - فئة
  - ملاحظة
- يدخل في التقارير وصافي الربح

---

## 12. الأرباح

### 12.1 داخل TreasurySnapshot
- `profitApprovedTotal`
- `dailyProfit`
- `monthlyProfit`

كلها تعتمد على:
- `clientFee`
- للعمليات `posted`

### 12.2 في التقارير

```text
صافي الربح = إجمالي العمولات - المصروفات
```

---

## 13. Backup / Restore

### 13.1 الأنواع
- DB backup
- JSON backup
- Encrypted backup

### 13.2 الحماية
- checksum sidecar
- verification before restore
- secure restore lockout:
  - 3 محاولات
  - قفل 15 دقيقة

### 13.3 restore sequencing
- إغلاق DB الرئيسي
- فتح sourceDb
- قراءة snapshot
- غلق sourceDb
- إعادة فتح DB الرئيسي

### 13.4 حماية الترخيص داخل النسخة
- يتم استثناء/تنظيف المفاتيح الحساسة من backup/restore مثل:
  - `cloudToken`
  - `serverAuthRefreshToken`
  - `activationCode`
  - `cloudDeviceId`
  - مفاتيح `serverAuthDiag*`

---

## 14. Licensing

### 14.1 الوضع الحالي
- النظام **hybrid**
- يوجد:
  - تفعيل محلي legacy
  - ومسار RPC أحدث

### 14.2 الموجود داخل العميل
- `_licenseSecret`
- `generateActivationCodeForDeviceCode(...)`
- local activation path

### 14.3 RPCs الجديدة
- `activate_license`
- `validate_license`
- `heartbeat_license`
- `refresh_session`

### 14.4 الحالة الحالية
- `useServerAuthoritativeLicense = false`
- المسار السحابي الجديد خلف feature flag
- لا يوجد cutover افتراضي بعد

### 14.5 Hardening الحالي
- retry/backoff
- kill-switch diagnostic
- compromise diagnostic
- fallback للـ legacy
- sanitization في backup/restore

---

## 15. Invariants الحالية

### 15.1 Treasury invariants
- `availableLiquidityNow == actualTreasuryApproved`
- `realCapitalApproved == actualTreasuryApproved + claimsNet`

### 15.2 Deferred invariants
- no duplicate cash effects
- pending KPIs informational only
- الأصل لا يُستبدل بالمتبقي
- الترتيب الزمني محفوظ

### 15.3 Data safety invariants
- restore الفاشل لا يفسد الحالة الحالية
- integrity checks ترصد:
  - duplicate ids
  - next ids invalid
  - missing references
  - negative balances
  - broken audit chain

---

## 16. أهم الاختبارات الموجودة

### 16.1 المحاسبة
- `accounting_engine_test.dart`
- `accounting_safety_test.dart`
- `transaction_integrity_test.dart`

### 16.2 Deferred regressions
- `pending_transfer_cash_collection_accounting_regression_test.dart`
- `pending_transfer_confirm_partial_collection_regression_test.dart`
- `pending_partial_collection_regression_test.dart`
- `customer_pending_ledger_regression_test.dart`
- `customer_report_pending_settlement_regression_test.dart`
- `dashboard_pending_open_regression_test.dart`
- `claims_chronology_regression_test.dart`
- `deferred_history_regression_shield_test.dart`

### 16.3 Invariants
- `treasury_snapshot_invariant_test.dart`

### 16.4 Backup / Restore
- `license_backup_sanitization_test.dart`
- restore tests داخل `accounting_safety_test.dart`

### 16.5 Licensing
- `license_rpc_service_test.dart`
- `license_phase_b_integration_test.dart`
- `license_phase_c_activation_test.dart`
- `license_phase_d0_decision_test.dart`

---

## 17. Edge Cases المهمة

- منع اعتماد العملية مرتين
- منع cancel بعد الاعتماد
- منع settlement بأكثر من المتبقي
- منع rollback لتسوية ليست الأخيرة
- منع إنشاء pending transfer/receive بدون عميل
- معالجة duplicate ids
- منع negative wallet balances
- restore من ملف تالف أو غير موجود لا يفسد الحالة
- secure restore lockout
- partial settlement قبل confirmPending
- confirmPending بعد partial settlement
- تحويل remainder إلى claim مفتوح بدون تكرار cash

---

## 18. Known Risks

### 18.1 Licensing security risk
- ما زال `_licenseSecret` داخل التطبيق
- local activation legacy ما زال موجودًا
- secure storage ليس مكتملًا بعد

### 18.2 Semantic complexity risk
- الفرق بين:
  - cash-only liquidity
  - pending KPIs
  - real capital
قد يُساء استخدامه في شاشات جديدة إن لم تعتمد على `TreasurySnapshot` بحذر

### 18.3 Fawry legacy surface
- فوري retired جزئيًا من الواجهة
- لكنه ما زال موجودًا محاسبيًا وتاريخيًا

### 18.4 Restore sensitivity
- restore path مستقر الآن لكنه منطقة عالية الحساسية

### 18.5 UI chronology risk
- أي إعادة تشكيل كبيرة في الواجهات الحساسة قد تكسر وضوح chronology إن لم تمر عبر regression suite

---

## 19. خلاصة تنفيذية

المعنى المحاسبي الحالي المعتمد في Smart Cash Pro هو:

- **السيولة المتاحة = النقد الفعلي فقط**
- **رأس المال الحقيقي = النقد الفعلي + المفتوح لنا - المفتوح علينا**
- **الآجل المفتوح = التزام/مستحق منفصل عن الكاش**
- **التحصيل/السداد الجزئي لا يغير الأصل**
- **confirmPending لا يكرر cash effect**
- **سجل العميل + تقرير العميل + التصدير + شاشة المستحقات يجب أن يحافظوا على الأصل والتسويات والمتبقي بوضوح**

هذا المستند يمثل **الوصف التشغيلي الحالي** للنظام، ويصلح كمرجع دعم وصيانة واختبارات ومراجعة قبل أي تغيير لاحق.
