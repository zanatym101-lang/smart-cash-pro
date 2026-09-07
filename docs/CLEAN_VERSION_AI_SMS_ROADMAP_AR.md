# Smart Cash Pro - خارطة طريق النسخة النظيفة + SMS + AI

هذه الوثيقة هي **خطة تنفيذ** وليست كودًا.  
الهدف منها هو إعادة بناء Smart Cash Pro حول الـ accounting engine الجديد المثبت بالاختبارات، مع إضافة SMS + AI بطريقة آمنة وقابلة للتدرج.

مبادئ الخطة:
- عدم كسر النظام الحالي
- عدم نقل منطق Legacy غير المنضبط إلى النسخة النظيفة
- جعل **المحاسبة هي المصدر الوحيد للحقيقة**
- جعل SMS وAI طبقات مساعدة فقط
- عدم السماح بأي كتابة محاسبية تلقائية بدون موافقة المستخدم

---

## 1. الهدف العام

لدينا اليوم وضعان:

1. **النظام القديم**
   - `AppDb + Screens`
   - مستقر وظيفيًا
   - لكنه legacy وفيه تداخل بين UI وstorage وبعض تشكيل العرض

2. **النظام الجديد**
   - `domain accounting engine`
   - `events`
   - `snapshot builder`
   - `use cases`
   - `repositories`
   - `pilot integrations`

الهدف الآن ليس “ترقيع” النسخة القديمة أكثر، بل إنشاء **Clean Version** جديدة تعتمد على:
- محاسبة معزولة
- application layer واضحة
- storage adapters فقط
- presentation جديدة أنظف
- طبقة `ai_sms` تضيف parsing ومراجعة ومطابقة آمنة

---

## 2. الشكل المستهدف للمعمارية

```text
lib/
  domain/
  application/
    use_cases/
    ports/
  infrastructure/
    adapters/
    persistence/
    parsers/
  presentation/
    screens/
    view_models/
    widgets/
  ai_sms/
    models/
    rules/
    parsers/
    scoring/
    review/
```

### 2.1 `domain`
مسؤول عن:
- الـ entities
- الـ value objects
- الـ accounting engine
- الـ events
- الـ snapshot builder
- invariants

يمنع فيه:
- Flutter
- Drift
- `AppDb`
- `dart:io`
- أي side effects

### 2.2 `application/use_cases`
مسؤول عن:
- أوامر الاستخدام
- ترتيب التنفيذ
- استدعاء الـ engine
- حفظ الأحداث
- إعادة بناء snapshot

يمنع فيه:
- UI logic
- Widgets
- business logic خارج الـ engine

### 2.3 `infrastructure`
مسؤول عن:
- repositories implementations
- event store
- snapshot persistence
- file/storage adapters
- SMS adapters
- AI adapters

قاعدة صارمة:
- infrastructure **لا تحسب** ولا “تفهم” المحاسبة
- storage فقط

### 2.4 `presentation`
مسؤول عن:
- الشاشات
- الإدخال
- عرض النتائج
- review flows
- diagnostics

قاعدة صارمة:
- UI لا تحسب drawer
- UI لا تحسب claims
- UI لا تبني snapshot بنفسها

### 2.5 `ai_sms`
مسؤول عن:
- تمثيل الرسائل
- parsing
- قواعد المطابقة
- confidence scoring
- duplicate detection
- بناء `ParsedTransactionDraft`

قاعدة صارمة:
- AI/SMS **لا يكتب** محاسبة مباشرة

---

## 3. استراتيجية الترحيل Migration Strategy

### 3.1 ما الذي نحتفظ به من النظام القديم؟

نحتفظ بما يلي:
- الـ accounting semantics المثبتة بالاختبارات
- الـ verified engine الجديد
- snapshot builder الجديد
- use cases الجديدة
- repository contracts
- parity tests بين القديم والجديد
- قواعد التحقق الحساسة:
  - no double cash
  - pending != cash
  - confirmPending no duplicate effect
  - original amount preserved
  - settlement rows separate

كما نحتفظ مرجعيًا بـ:
- `docs/SMART_CASH_PRO_SRS_AR.md`
- regression tests الحالية

### 3.2 ما الذي سيتم Retire تدريجيًا؟

يتم تقاعد الآتي تدريجيًا:
- منطق الأعمال داخل `AppDb`
- تشكيل customer ledger داخل الشاشات القديمة
- الحسابات المشتقة داخل UI
- أي parsing أو inference داخل screens
- أي ربط مباشر بين UI والـ DB بدون use case

### 3.3 ما الذي يجب ألا ننسخه أبدًا من الشاشات القديمة؟

لا يُنقل إلى النسخة النظيفة:
- sorting hacks المبنية على UI state
- تجميع الأرصدة داخل widgets
- استخراج semantics من `note` كنقطة truth رئيسية
- أي logic داخل screen يقرر:
  - هل العملية pending؟
  - هل هذا cash effect؟
  - هل claim مفتوح أو مغلق؟
- أي duplication في:
  - customer report math
  - dashboard math
  - statement math

### 3.4 توصية الترحيل

التوصية الرسمية:
- **لا نعيد كتابة كل التطبيق دفعة واحدة**
- نبني النسخة النظيفة **parallel**
- ثم نعمل cutover شاشة بشاشة أو feature بfeature

---

## 4. المبادئ المحاسبية التي يجب تجميدها

هذه قواعد لا يجوز كسرها في النسخة الجديدة:

1. **No double cash**
   - لا يدخل نفس النقد مرتين

2. **Pending != cash**
   - العملية الآجلة ليست تحصيلًا نقديًا

3. **Original amount preserved**
   - المبلغ الأصلي يبقى محفوظًا

4. **Settlement rows separate**
   - كل تحصيل/سداد صف مستقل

5. **confirmPending safe**
   - `confirmPending` لا ينشئ cash effect
   - فقط يحول remaining إلى claim إذا لزم

6. **Pending must require customer**
   - لا يوجد deferred transfer/receive بدون عميل

7. **Review before post**
   - لا posting تلقائي من SMS أو AI

8. **Snapshot is derived**
   - snapshot تُبنى من events فقط

---

## 5. تصميم ميزة SMS

### 5.1 النطاق في النسخة النظيفة

ميزة SMS ستكون على مرحلتين:

#### المرحلة الأولى
- Paste message يدويًا
- بدون صلاحيات SMS
- parsing محلي
- draft + review

#### المرحلة الثانية
- قراءة رسائل Android بإذن صريح
- inbox ingestion
- duplicate detection
- AI fallback

### 5.2 خطة أذونات Android SMS

الخطة الموصى بها:

#### Step 1
- لا صلاحيات SMS
- Clipboard/manual paste فقط

#### Step 2
- طلب:
  - `READ_SMS`
  - وربما `RECEIVE_SMS` لاحقًا إن احتجنا live monitoring
- الطلب يكون:
  - opt-in
  - من شاشة admin / settings / setup
  - مع شرح واضح أن الغرض parsing فقط

#### Step 3
- إضافة inbox import scope:
  - آخر X رسائل فقط
  - أو من senders محددين

قاعدة صارمة:
- لا background auto-post
- لا parsing صامت

### 5.3 أسماء المرسلين المتوقع دعمها

في Phase C ندعم rules محلية لمجموعة مرسلين/قنوات معروفة مثل:
- Vodafone Cash
- Etisalat Cash
- Orange Cash
- WePay / المحافظ المشابهة
- أي رسائل شركات خدمات تحويل/استلام متكررة في السوق المحلي

يجب أن تُخزن القواعد في:
- `SmsSourceRule`
- مع sender aliases متعددة

### 5.4 قواعد parsing

المطلوب من parser استخراج:
- نوع العملية:
  - transfer
  - receive
  - unknown
- amount
- phone number
- provider / sender
- fee إذا أمكن
- reference number إذا أمكن
- date/time إن كانت موجودة
- customer candidate إذا وجد تطابق هاتف

### 5.5 duplicate detection

يجب منع تسجيل نفس الرسالة/العملية مرتين.

آلية مقترحة:
- hash مبني على:
  - normalized sender
  - normalized body
  - extracted amount
  - extracted phone
  - extracted reference
  - received timestamp bucket

نتيجة الفحص:
- `exact_duplicate`
- `possible_duplicate`
- `no_duplicate`

### 5.6 confidence scoring

نظام score مقترح:
- amount extracted: +0.30
- operation type clear: +0.20
- phone extracted: +0.15
- sender matched by rule: +0.15
- customer matched by phone: +0.10
- reference extracted: +0.05
- fee extracted: +0.05

تصنيف:
- `>= 0.85` ثقة عالية
- `0.60 - 0.84` ثقة متوسطة
- `< 0.60` ثقة منخفضة

### 5.7 Review screen قبل الحفظ

ممنوع الحفظ المباشر.

الشاشة يجب أن تسمح للمستخدم بـ:
- تعديل النوع
- تعديل المبلغ
- تعديل العميل
- تعديل العمولة
- تحديد هل العملية deferred أم لا
- اختيار المحفظة
- تأكيد الحفظ أو الإلغاء

---

## 6. تصميم AI

### 6.1 دور AI المسموح

AI مسموح له فقط أن ينتج:
- `ParsedTransactionDraft`

أي:
- تحليل الرسالة
- اقتراح نوع العملية
- اقتراح العميل
- اقتراح fee/reference
- إضافة warnings

### 6.2 دور AI الممنوع

AI ممنوع أن:
- يكتب transaction مباشرة
- يفتح claim مباشرة
- يسوي claim
- يؤكد pending
- يعدل snapshot
- يكتب في DB مباشرة

### 6.3 قاعدة approval

قاعدة ثابتة:
- user approval required دائمًا

### 6.4 low confidence path

إذا confidence منخفضة:
- لا يسمح إلا بـ review يدوي كامل
- ويجب إظهار warnings واضحة:
  - نوع العملية غير مؤكد
  - العميل غير مؤكد
  - العمولة غير مؤكدة
  - reference ناقص

### 6.5 AI integration boundary

الـ AI يوضع في:
- `ai_sms/parsers/`
- أو adapter داخل infrastructure

ويُرجع:
- draft
- score
- reasons

ولا يعرف شيئًا عن:
- `AppDb`
- `AccountingEngineState`
- posting

---

## 7. نماذج البيانات المطلوبة

### 7.1 `IncomingMessage`

يمثل الرسالة الخام.

حقول مقترحة:
- `id`
- `sourceType`:
  - pasted
  - sms_inbox
  - sms_live
- `sender`
- `body`
- `receivedAt`
- `deviceMessageId`
- `normalizedSender`
- `hash`

### 7.2 `ParsedTransactionDraft`

يمثل النتيجة القابلة للمراجعة قبل الحفظ.

حقول مقترحة:
- `draftId`
- `rawMessageId`
- `operationType`
- `isDeferredCandidate`
- `amount`
- `clientFee`
- `networkFee`
- `phone`
- `provider`
- `reference`
- `customerId`
- `customerName`
- `walletId`
- `confidenceScore`
- `warnings`
- `parseSource`
  - local_rule
  - ai
  - hybrid

### 7.3 `MessageParseResult`

يمثل ناتج parsing الكامل.

حقول:
- `draft`
- `matchedRuleId`
- `duplicateCheckResult`
- `confidenceScore`
- `reasons`
- `requiresManualReview`

### 7.4 `SmsSourceRule`

يمثل قاعدة parsing محلية لمصدر رسائل.

حقول:
- `id`
- `sourceName`
- `senderPatterns`
- `operationPatterns`
- `amountPatterns`
- `phonePatterns`
- `feePatterns`
- `referencePatterns`
- `priority`
- `enabled`

### 7.5 `DuplicateCheckResult`

حقول:
- `status`
  - `exact_duplicate`
  - `possible_duplicate`
  - `no_duplicate`
- `matchedTransactionId`
- `matchedMessageId`
- `reason`
- `confidence`

---

## 8. قواعد الأمان والسلوك

هذه القواعد mandatory:

1. لا posting تلقائي بدون user confirmation
2. لا AI يكتب محاسبة مباشرة
3. لا double cash
4. pending يتطلب customer
5. original amount preserved
6. settlements separate
7. confirmPending لا يكرر cash effect
8. duplicate detection يعمل قبل save
9. low confidence لا يُمرر بصمت
10. parsing errors لا تفسد المحاسبة

---

## 9. مراحل التنفيذ

## Phase A: Message Parser بدون AI

### الهدف
بناء parser محلي بسيط يعتمد على rules فقط.

### ما ينفذ
- `IncomingMessage`
- `SmsSourceRule`
- `ParsedTransactionDraft`
- `MessageParseResult`
- local parsing service
- paste-only flow

### ما لا ينفذ
- AI
- SMS permissions
- auto import
- DB persistence للرسائل الحية

### الاختبارات المطلوبة
- rule parsing tests
- amount extraction tests
- phone extraction tests
- sender matching tests
- malformed message tests
- unknown sender tests

### شرط الانتقال
- يجب أن ينجح parsing المحلي للسيناريوهات المعروفة
- لا false positives خطيرة

---

## Phase B: Review Screen

### الهدف
بناء شاشة review قبل أي save.

### ما ينفذ
- عرض draft
- تعديل الحقول
- اختيار العميل
- اختيار المحفظة
- اختيار deferred أو posted
- warnings واضحة

### ما لا ينفذ
- auto save
- auto post

### الاختبارات المطلوبة
- widget tests لشاشة المراجعة
- validation tests
- customer-required-for-pending tests
- cancel flow tests

### شرط الانتقال
- لا يمكن حفظ draft ناقص
- pending لا يمر بدون عميل

---

## Phase C: Local Rule Parser لمصادر حقيقية

### الهدف
توسيع parser المحلي لدعم الرسائل الشائعة.

### ما ينفذ
- قواعد Vodafone
- قواعد Etisalat
- قواعد Orange
- قواعد WePay/مشابهة
- registry للمرسلين

### ما لا ينفذ
- AI fallback

### الاختبارات المطلوبة
- fixtures حقيقية لرسائل متعددة
- sender alias tests
- fee extraction tests
- ambiguous message tests
- regression suite لكل provider

### شرط الانتقال
- parser المحلي ينجح في majority من الرسائل المعروفة

---

## Phase D: AI Fallback Parser

### الهدف
استخدام AI فقط عندما يفشل parser المحلي أو تكون الثقة منخفضة.

### ما ينفذ
- AI adapter
- prompt format موحد
- تحويل output إلى `ParsedTransactionDraft`
- merge strategy مع local parser

### ما لا ينفذ
- direct save
- autonomous posting

### الاختبارات المطلوبة
- AI contract tests
- schema validation tests
- low confidence tests
- prompt/output guard tests
- offline fallback tests

### شرط الانتقال
- أي AI output يجب أن يتحول إلى draft فقط
- لا output غير منظم يُقبل

---

## Phase E: Reconciliation + Duplicate Prevention

### الهدف
منع التكرار وربط الرسائل بالعمليات.

### ما ينفذ
- duplicate check service
- message hash strategy
- pending review queue
- linking بين الرسالة والعملية المعتمدة

### الاختبارات المطلوبة
- exact duplicate tests
- possible duplicate tests
- repeated sender same amount tests
- delayed SMS arrival tests
- replay prevention tests

### شرط الانتقال
- لا يمكن تسجيل نفس الرسالة مرتين دون تحذير

---

## Phase F: Production Hardening

### الهدف
تحويل الميزة إلى وضع production-ready.

### ما ينفذ
- Android permission flow
- inbox import
- logs/diagnostics
- admin controls
- feature flags
- telemetry آمنة
- privacy boundaries

### الاختبارات المطلوبة
- permission tests
- import batch tests
- performance tests
- privacy tests
- failure recovery tests
- rollback tests

### شرط الإطلاق
- لا crash على unsupported devices
- parsing failures لا تؤثر على المحاسبة
- duplicate prevention stable
- review flow mandatory

---

## 10. ما الذي نحتفظ به من النظام الحالي في النسخة النظيفة؟

### نحتفظ
- accounting engine الجديد
- event model
- snapshot builder
- use cases
- repository contracts
- parity tests
- customer/pending/claims invariants

### نعيد كتابة
- presentation بالكامل تقريبًا
- customer screens
- reports screens التي تعتمد على legacy shaping
- admin flows التي تختلط مع storage

### نؤجل
- cutover الكامل
- replacement الكامل لـ `AppDb`
- schema migration الكبير

---

## 11. ما الذي يجب ألا ننسخه من النظام القديم؟

1. أي logic داخل screens يحسب الأرصدة
2. أي parsing معتمد على `note` كـ source of truth وحيد
3. أي fallback UI يعوض نقص domain logic
4. أي sorting مبني على “ماذا يظهر أجمل” بدل event chronology
5. أي claim/pending math داخل widgets

---

## 12. الاختبارات المطلوبة كطبقة حماية عامة

بالإضافة إلى اختبارات كل مرحلة، نحتاج حزمة anti-regression عامة:

### 12.1 Accounting invariants
- no double cash
- pending != cash
- confirmPending safe
- original amount preserved
- settlements separate

### 12.2 Message safety
- no auto save
- no save without review
- no pending without customer
- low confidence requires manual review

### 12.3 Duplicate protection
- exact duplicate blocked
- possible duplicate warned
- different message same amount still checked carefully

### 12.4 UI protection
- review screen always reachable
- cancel path does not mutate accounting
- edited draft persists only after explicit confirm

---

## 13. ترتيب التنفيذ الموصى به

الترتيب الصحيح:

1. تثبيت `domain + application` كمرجع ثابت
2. تنفيذ `Phase A`
3. تنفيذ `Phase B`
4. تنفيذ `Phase C`
5. بعدها فقط `Phase D`
6. ثم `Phase E`
7. ثم `Phase F`

ما لا يجب فعله مبكرًا:
- عدم طلب SMS permission قبل اكتمال parser المحلي
- عدم إدخال AI قبل وجود review screen
- عدم ربط AI مباشرة بالمحاسبة
- عدم عمل cutover من النظام القديم قبل parity كافية

---

## 14. قرار معماري نهائي

النسخة النظيفة يجب أن تعتمد على:

- **محاسبة معزولة**
- **Use Cases واضحة**
- **Storage كـ adapter فقط**
- **UI بدون حسابات**
- **SMS/AI كطبقة draft + review فقط**

باختصار:
- الـ accounting engine هو authority
- الـ UI مجرد مستهلك
- الـ DB مجرد مخزن
- الـ AI مجرد مساعد اقتراح

---

## 15. الخلاصة التنفيذية

هذه الخطة لا تهدف إلى “تحسين ميزة” فقط، بل إلى:
- نقل Smart Cash Pro من legacy stable system
- إلى clean modular system
- يمكنه دعم:
  - SMS parsing
  - AI assistance
  - duplicate prevention
  - review-first accounting

أهم قاعدة يجب عدم كسرها في كل خطوة:

**لا شيء يكتب في المحاسبة إلا بعد موافقة المستخدم، ومن خلال الـ use case والـ accounting engine فقط.**
