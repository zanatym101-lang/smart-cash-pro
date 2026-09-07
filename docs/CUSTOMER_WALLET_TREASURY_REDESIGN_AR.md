# Smart Cash Pro — Customer, Wallet, and Treasury Redesign

## 1. السلوك الحالي (Current Behavior)
* **حسابات العملاء:** تعتمد على تراكم العمليات (تحويل، استلام). يتم السماح بأرشفة العميل (Archived) عندما يصبح الرصيد صفراً. لا يوجد مفهوم حقيقي لتسوية الحساب (Adjustment) كحركة مستقلة؛ التسويات قد تغير العملية الأصلية. لا توجد حماية حاسمة ضد تكرار العميل باستخدام رقم الهاتف (Duplicate Prevention).
* **المحفظة (Wallet):** لا يوجد سجل (Ledger) محاسبي مستقل لكل محفظة. التقارير وحساب الأرصدة يتم بشكل تقريبي من خلال واجهة المستخدم (UI formulas) مما قد يسبب فجوة محاسبية.
* **الخزينة (Treasury):** تتداخل حركاتها مع العمليات العامة ولا تملك دفتراً (Ledger) مستقلاً يوضح الأرصدة الافتتاحية والختامية بوضوح بناءً على الأحداث (Events).
* **تفاصيل العمليات:** يحتاج المستخدم للدخول إلى تفاصيل كل عملية لمعرفة المحفظة المستخدمة ورقمها.

## 2. السلوك المطلوب (Requested Behavior)
* **حساب العميل (Customer Account):** تحويله لحساب مالي موحد يشمل (الإجمالي لنا، الإجمالي علينا، الصافي، المفتوح لنا، المفتوح علينا).
* **التسويات (Account Adjustments):** إضافة أو خصم مبالغ من الحساب كحركة مستقلة في السجل بدون أي تغيير للعملية الأصلية. دعم التخصيص (بدون تخصيص، الأقدم أولاً، الأحدث أولاً، عملية محددة).
* **إدارة العملاء:** إلغاء الأرشفة، والاحتفاظ بالعميل كحساب مفتوح برصيد صفري ليبقى متاحاً للبحث وإعادة الاستخدام. منع التكرار بناءً على رقم الهاتف (`normalizedPhone`) مع إظهار تحذير للتشابه في الأسماء.
* **سجل المحفظة (Wallet Ledger):** دفتر مستقل لكل محفظة، يحتوي على الحركات، العمولات، الصافي، والرصيد، ويُعتمد في حساباته على أحداث ثابتة (Events/Snapshots) وليس على شاشة المستخدم.
* **سجل الخزينة (Treasury Ledger):** سجل خاص يوثق حركات الخزينة بتفاصيلها.
* **الشفافية في العرض:** إظهار اسم المحفظة ورقمها في سجل العمليات العام وسجل العميل دون الحاجة لفتح تفاصيل العملية.

## 3. نموذج النطاق (Domain Model)
* **Customer:** `id, name, phone, normalizedPhone, status (open/zero balance), totalForUs, totalAgainstUs, netBalance, openForUs, openAgainstUs`
* **CustomerAccountAdjustment:** `id, customerId, type (add/subtract), amount, date, note`
* **AllocationRow:** `id, adjustmentId, linkedItemId, allocatedAmount`
* **WalletAccount:** `walletId, walletName, walletNumber, currentBalance, totalReceived, totalTransferred, totalFees, netMovement`
* **WalletLedgerRow:** `id, date, transactionId, transactionType, customerId, amount, fee, balanceAfter, reference`
* **TreasuryAccount:** `openingBalance, totalIn, totalOut, expenses, adjustments, closingBalance`
* **TreasuryLedgerRow:** `id, date, eventId, reference, description, amount, balanceAfter`

## 4. الثوابت المحاسبية (Invariants)
1. **الرصيد الصافي للعميل:** يجب ألا يتعارض `Customer Balance` مع مجموع `Open Items Total` عند احتساب التسويات غير المخصصة.
2. **العمليات الأصلية:** ممنوع منعاً باتاً تعديل قيمة أو خصائص العملية الأصلية (مثل: تحويل آجل) عند حدوث سداد أو خصم (Adjustment/Settlement).
3. **الدقة المالية (No Double Cash Effect):** لا يمكن تسجيل تأثير نقدي مرتين لنفس العملية. ولا يجوز وجود مطالبات مخفية (Hidden Claims).
4. **سلامة الكتابة (Write Integrity):** كل تعديل يجب أن يمر حصراً عبر `CleanWriteGateway` و `Events` قابلة لإعادة التشغيل (Replay-safe). لا يسمح بالكتابة المباشرة في قاعدة البيانات من الـ UI، ولا من الذكاء الاصطناعي، ولا من قراءة الـ SMS بشكل مباشر بدون مرور بالبنية التحتية.

## 5. نموذج الأحداث (Event Model)
لتوافق تام مع `AccountingReplayEngine`:
* `CustomerAdjustmentCreatedEvent`: يوثق إنشاء تسوية (إضافة/خصم).
* `AdjustmentAllocatedEvent`: يوثق توزيع قيمة التسوية على عمليات محددة.
* `WalletTransactionRecordedEvent`: يسجل حركة دخول/خروج من المحفظة وتأثيرها على الرصيد.
* `TreasuryTransactionRecordedEvent`: يسجل حركة مخصصة للخزينة.
يجب أن تدعم الأحداث الجديدة إعادة التشغيل (Replay-Safe) دون كسر العمليات القديمة.

## 6. نموذج واجهة المستخدم (UI Model)
* **شاشة العميل (Customer):** ستعرض الحقول الخمسة للأرصدة بوضوح. ستحتوي سجل العمليات (الذي سيعرض الأحدث أولاً، مع إظهار تفاصيل المحفظة والتسويات كصفوف مستقلة).
* **إضافة عميل:** واجهة ترفض إنشاء العميل إن كان الهاتف (`normalizedPhone`) موجوداً مسبقاً، وتقترح فتح حساب العميل الموجود.
* **تقارير المحفظة والخزينة والعميل (Reports):** تعتمد بالكامل على فلتر الفترة الزمنية، مدعومة بإمكانية التصدير (Export-ready)، ونتائجها حتمية (Deterministic) بناءً على الـ Snapshots.

## 7. خطة الترحيل (Migration Plan)
1. **Phase A:** تحليل وتأسيس النماذج (Models) والثوابت (Invariants) في الكود (بدون تعديل الواجهات).
2. **Phase B:** إضافة `CustomerAccountAdjustment` ومنع التكرار (Duplicate Prevention). تعديل منطق العميل ليصبح `Open / Zero Balance` وإلغاء الأرشفة.
3. **Phase C:** بناء سجل المحفظة (Wallet Ledger) وإعداد الأحداث الخاصة به.
4. **Phase D:** بناء سجل الخزينة (Treasury Ledger) وإعداد الأحداث الخاصة به.
5. **Phase E:** بناء التقارير الموحدة للعميل، المحفظة، والخزينة بناءً على البيانات الدقيقة.
6. **Phase F (Shadow Parity):** تشغيل النظامين جنباً إلى جنب للتحقق من تطابق الأرصدة (Parity Validation).
7. **Phase G (Production Promotion):** اعتماد القراءة من النماذج الجديدة في بيئة الإنتاج.

## 8. خطة التوافقية الرجعية (Backward Compatibility Plan)
* كافة الأحداث التاريخية المحفوظة (Persisted Events) سيتم إعادة قراءتها (Replay) دون مشاكل من خلال الـ `AccountingReplayEngine`.
* في حال غياب بيانات (مثل `walletNumber` في العمليات القديمة)، سيتم جلبها عبر `walletId` في طبقة بناء السجل (Ledger Builder) لتُعرض في الـ UI بشكل سليم.
* لا مساس بـ Events القديمة؛ الأحداث الجديدة فقط هي من ستُستخدم للميزات المضافة.

## 9. خطة التراجع (Rollback Plan)
* الاعتماد على Event Sourcing يوفر حماية قوية. في حالة الطوارئ يمكن الرجوع للإصدار السابق من التطبيق (الذي سيتجاهل أحداث التحديث الجديدة `CustomerAdjustmentCreatedEvent` و `WalletTransactionRecordedEvent`).
* لن يتم حذف أي بيانات أو أعمدة من قاعدة البيانات الحالية لضمان إمكانية العمل بالنظام القديم إذا لزم الأمر.

## 10. خطة الاختبار (Test Plan)
يجب اجتياز كافة الاختبارات الآتية بنجاح قبل الترقية النهائية:
1. Customer adjustment add
2. Customer adjustment subtract
3. Adjustment without allocation
4. Adjustment allocated to oldest item
5. Adjustment allocated to selected item
6. Deferred transfer + settlement + adjustment
7. Deferred receive + settlement + adjustment
8. No duplicate customer by phone
9. Existing customer remains searchable at zero balance
10. Wallet ledger parity
11. Wallet balance parity
12. Treasury ledger parity
13. Treasury balance parity
14. Customer report parity
15. Replay parity
16. No duplicate cash effect
17. No hidden claim
