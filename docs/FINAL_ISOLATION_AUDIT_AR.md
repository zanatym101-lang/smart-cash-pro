# تدقيق العزل النهائي - Smart Cash Pro

تاريخ التدقيق: 2026-05-18  
النطاق: مرحلة 1 فقط - تدقيق وتصنيف وحواجز اختبار.  
القرار المهم: لا يتم حذف أي كود legacy الآن. الإزالة لا تبدأ إلا بعد bridge + parity + replay + تحويل UI/use cases.

## ملخص تنفيذي

المشروع مستقر وظيفيًا، لكنه ما زال hybrid:

- النظام النظيف موجود وقابل للاختبار: domain accounting engine، use cases، ports، snapshots، drift event repository، history bridge/replay.
- AppDb ما زال مصدر التشغيل التاريخي والحي لعدد كبير من الشاشات والتقارير.
- بعض الشاشات تستخدم clean use cases كـ pilot/shadow فقط، ثم تكتب فعليًا عبر AppDb.
- شاشة العملاء تستخدم CustomerAccountBuilder في الملخص/العرض، لكن التسويات نفسها لا تزال AppDb write path.
- SMS core يخطط عبر UseCases، لكن التنفيذ الحي في التطبيق يمر عبر AppDbSmsExecutionGateway كـ bridge مؤقت.

الهدف الآمن للمرحلة التالية: جعل AppDb مصدر قراءة تاريخي فقط، ونقل الكتابة تدريجيًا إلى UseCases + Events، مع replay/parity قبل إزالة أي مسار legacy.

## تصنيف الملفات

| الملف/النطاق | التصنيف | الاعتماد الحالي | مستوى الخطر | خطوة الهجرة المقترحة |
|---|---|---|---|---|
| `lib/domain/services/accounting_engine.dart` | CLEAN_KEEP | محرك domain للأحداث والتسويات | منخفض | تثبيته كمصدر معادلات الحساب |
| `lib/domain/services/snapshot_builder.dart` | CLEAN_KEEP | يبني snapshot من الأحداث | منخفض | جعله مصدر dashboard/treasury/reports |
| `lib/application/use_cases/*` | CLEAN_KEEP | use cases للعمليات النظيفة | منخفض | توسيعها لتغطي كل عمليات UI |
| `lib/application/ports/*` | CLEAN_KEEP | عقود repos | منخفض | تثبيت واجهات UI/ViewModel عليها |
| `lib/infrastructure/adapters/in_memory_*` | CLEAN_KEEP | اختبارات وذاكرة | منخفض | تبقى للاختبارات والـ preview |
| `lib/infrastructure/adapters/drift_event_repository.dart` | CLEAN_KEEP | event store على Drift | متوسط | اعتماده كـ production event source بعد parity |
| `lib/data/sqlite/app_database*.dart` | CLEAN_KEEP | Drift schema والتنفيذ | متوسط | الحفاظ عليه، مع فصل جداول legacy/event |
| `lib/services/legacy_history_bridge_service.dart` | LEGACY_BRIDGE_REQUIRED | يقرأ AppDb history ويصدر events | عال | توسيع التغطية ثم تشغيل replay دوري |
| `lib/services/history_replay_service.dart` | LEGACY_BRIDGE_REQUIRED | replay من bridged events | متوسط | استخدامه في parity jobs قبل أي UI switch |
| `lib/data/app_db*.dart` | LEGACY_ACTIVE | مصدر التخزين والكتابة الحالي | عال جدًا | تجميده كـ legacy read/write مؤقت ثم تحويله read-only bridge |
| `lib/accounting/engine.dart`, `money.dart`, `specs.dart` | LEGACY_ACTIVE | AppDb يستخدمه لحسابات قديمة | عال | لا يحذف قبل نقل AppDb formulas إلى clean engine أو إلغاء AppDb writes |
| `lib/screens/transfer_screen.dart` | LEGACY_ACTIVE | يكتب عبر AppDb، مع pilot use case | عال | Phase 2: ViewModel -> UseCase، AppDb فقط parity/history |
| `lib/screens/receive_screen.dart` | LEGACY_ACTIVE | يكتب عبر AppDb، مع pilot use case | عال | نفس مسار transfer |
| `lib/screens/claims_screen.dart` | LEGACY_ACTIVE | يكتب AppDb، pilot clean | عال | نقل create/settle claim إلى UseCases |
| `lib/screens/pending_screen.dart` | LEGACY_ACTIVE | confirm/cancel مباشرة في AppDb | عال | تحويل confirm/cancel إلى UseCases |
| `lib/screens/customers_screen.dart` | LEGACY_BRIDGE_REQUIRED | يعرض عبر CustomerAccountBuilder لكن يكتب AppDb | عال | فصل CustomerAccountViewModel ثم settlement use cases |
| `lib/screens/customer_account/*` | CLEAN_KEEP | models/builder لدفتر العملاء | متوسط | جعله مصدر عرض موحد لكل customer UI/report |
| `lib/screens/dashboard_screen.dart` | LEGACY_ACTIVE | يقرأ AppDb snapshots + txns + claims | متوسط | التحويل إلى AccountingSnapshotBuilder |
| `lib/screens/treasury_screen.dart` | LEGACY_ACTIVE | AppDb treasury snapshot + drawerDeposit | عال | treasury snapshot من clean events، drawer movements عبر use case |
| `lib/screens/reports_screen.dart`, `reports_*` | LEGACY_ACTIVE | تقارير من AppDb txns/claims/closes | عال | reports من clean snapshots + bridged history |
| `lib/screens/customer_report_screen.dart` | LEGACY_ACTIVE | AppDb txns/claims مع منطق عرض خاص | متوسط | استخدام CustomerAccountBuilder/clean rows فقط |
| `lib/screens/ledger_screen.dart`, `tx_details_screen.dart` | LEGACY_ACTIVE | قراءة وتنفيذ AppDb مباشر | متوسط | ledger من events، actions عبر UseCases |
| `lib/ai_sms/sms_accounting_integration_service.dart` | CLEAN_KEEP | core validation/plan عبر UseCases | متوسط | إبقاؤه، واستبدال gateway الحي لاحقًا |
| `lib/ai_sms/parsed_draft_to_use_case_mapper.dart` | CLEAN_KEEP | mapping SMS -> UseCase plans | منخفض | يبقى |
| `lib/ai_sms/sms_execution_gateway.dart` | LEGACY_BRIDGE_REQUIRED | AppDbSmsExecutionGateway يكتب AppDb | عال | استبداله بـ clean repository gateway بعد migration |
| `lib/ai_sms/sms_review_screen.dart` | CLEAN_KEEP | مراجعة يدوية فقط | منخفض | يبقى advisory/review gate |
| `lib/ai_sms/ai_parsing_service.dart` و matching/anomaly | CLEAN_KEEP | advisory فقط، لا كتابة | منخفض | يبقى بدون authority |
| `lib/ai_sms/sms_inbox_screen.dart` | LEGACY_BRIDGE_REQUIRED | يقرأ AppDb wallets/customers ويحقن gateway | متوسط | تمرير repositories/ViewModels بدل AppDb |
| `lib/services/drive_backup_service.dart` | LEGACY_ACTIVE | backup/restore عبر AppDb raw backup | عال | لا يغير قبل تحديد event-store backup format |
| `lib/screens/drive_backup_screen.dart` | LEGACY_ACTIVE | restore AppDb مباشر | عال | إضافة clean event backup/restore ثم parity |
| `lib/screens/admin_settings_*`, `audit_log_screen.dart` | LEGACY_ACTIVE | إعدادات/صيانة/AppDb audit | متوسط | فصل settings/audit repositories |
| `lib/screens/wallets_screen.dart`, `wallet_funding_screen.dart` | LEGACY_ACTIVE | محافظ وتمويل عبر AppDb | عال | use cases للمحافظ والحركات |
| `lib/screens/fawry_screen.dart`, `expenses_screen.dart` | LEGACY_ACTIVE | عمليات غير معزولة بعد | عال | تحديد clean events لها قبل النقل |
| `lib/screens/assistant_screen.dart` | LEGACY_ACTIVE | يقرأ AppDb snapshots/txns/claims | متوسط | قراءات clean snapshots فقط |
| `lib/services/pilot_*` | SAFE_REMOVE_LATER | monitoring pilot/shadow | متوسط | يحذف بعد switch النهائي واستقرار parity |
| `lib/debug/*` | SAFE_REMOVE_LATER | diagnostics فقط | منخفض | يحذف/يعطل في prod بعد انتهاء migration |
| `docs/CLEAN_ARCHITECTURE_FINAL.md`, `docs/HISTORY_BRIDGE_PLAN.md` | CLEAN_KEEP | وثائق حالية | منخفض | تحديثها بعد كل phase |
| `test/*use_case*`, `snapshot_builder`, `history_bridge`, `parity` | CLEAN_KEEP | regression/parity | منخفض | زيادة التغطية قبل أي إزالة |
| `test/accounting_engine_test.dart` | LEGACY_BRIDGE_REQUIRED | يغطي engine القديم المستخدم من AppDb | متوسط | لا يحذف قبل إلغاء اعتماد AppDb عليه |
| `web/sql-wasm.wasm`, web sqlite executor | CLEAN_KEEP | تشغيل Drift/Web | منخفض | يبقى |
| `web_run.out`, `web_run.err` | UNKNOWN | مخرجات تشغيل محلية | منخفض | راجع يدويًا؛ غالبًا safe remove later بعد التأكد |

## الاعتمادات الحالية حسب المجال

### AppDb direct transaction flows

المسارات النشطة:

- `transfer_screen.dart` -> `AppDb.instance.addTransfer`
- `receive_screen.dart` -> `AppDb.instance.addReceive`
- `claims_screen.dart` -> `AppDb.instance.addClaim` و `settleClaim`
- `pending_screen.dart` و `tx_details_screen.dart` -> `confirmPending/cancelPending/rollbackPosted`
- `customers_screen.dart` -> settlement/edit/rollback عبر AppDb
- `fawry_screen.dart`, `wallet_funding_screen.dart`, `expenses_screen.dart`, `treasury_screen.dart` -> AppDb writes

الخطر: عال. هذه هي نقطة hybrid الرئيسية. لا يتم حذفها قبل أن تملك UseCases تغطية وظيفية كاملة.

### customer calculations

- العرض الجديد يستخدم `CustomerAccountBuilder.fromAppDbData`.
- `customers_screen.dart` لا يزال يحتوي shaping UI وسلوك settlement.
- `customer_report_screen.dart` لا يزال يبني تقرير العميل من AppDb مباشرة.

الخطر: متوسط/عال. يجب توحيد كل customer report/list/detail على `CustomerAccountBuilder` أو ViewModel فوقه.

### dashboard / treasury

- `dashboard_screen.dart` يقرأ AppDb snapshot و txns/claims.
- `treasury_screen.dart` يقرأ `AppDb.getTreasurySnapshot` ويكتب `drawerDeposit`.

الخطر: عال لأن dashboard/treasury هي مصدر ثقة بصري. المرحلة التالية تحتاج snapshot parity قبل التحويل.

### reports

- `reports_screen.dart`, `reporting.dart`, `report_exporter.dart` تعتمد على AppDb txns/claims/closes.
- لا تزال التقارير بحاجة bridge حتى لا تضيع daily close/history.

الخطر: عال. لا تنقل reports قبل replay كامل ومقارنة export outputs.

### claims

- `claims_screen.dart` يحتوي pilot clean use case، لكن الكتابة النهائية AppDb.
- settlement display والـ chronology مستقرة لكنها legacy-driven.

الخطر: عال. يجب تحويل create/settle إلى UseCases مع AppDb shadow فقط.

### SMS execution

- `SmsAccountingIntegrationService` core يخطط ويفذ عبر UseCases عند عدم وجود gateway.
- الإنتاج الحالي يستخدم `AppDbSmsExecutionGateway` كـ live bridge للكتابة في AppDb.
- duplicate detection والمراجعة اليدوية مستقرة.

الخطر: متوسط/عال. لا يزال هناك bridge write. Phase 2 يجب أن يوفر clean live gateway ثم يجعل AppDb للقراءة/compat فقط.

### AI advisory

- AI parsing، customer matching، anomaly detection لا تكتب accounting.
- Review confirmation لازمة.

الخطر: منخفض. يجب الحفاظ على هذه الحدود.

### backup / restore

- Google Drive/local backup يلتف حول AppDb backup/restore.
- لا يوجد بعد format نهائي يضمن clean event store + legacy history معًا كحزمة migration كاملة.

الخطر: عال. لا تغير restore behavior قبل تصميم backup version جديد يشمل event store.

### drift persistence

- `AppDatabase` موجود.
- `DriftEventRepository` موجود ويحفظ `accounting_events`.
- AppDb legacy tables ما زالت مهمة للإنتاج.

الخطر: متوسط. Drift هو طريق clean persistence، لكنه لم يصبح مصدر الحقيقة الوحيد بعد.

### history bridge

- `LegacyHistoryBridgeService` و `HistoryReplayService` موجودان.
- يغطيان txns/claims/settlements بدرجة جيدة، لكن يحتاجان parity أوسع للـ reports/treasury/customer histories.

الخطر: متوسط. هذا هو المسار الصحيح للإزالة الآمنة لاحقًا.

## ما لا يجب حذفه الآن

- أي ملف `lib/data/app_db*.dart`.
- أي جدول Drift legacy في `app_database.dart`.
- `lib/accounting/*` لأن AppDb لا يزال يعتمد عليه.
- `transfer_screen.dart`, `receive_screen.dart`, `claims_screen.dart`, `pending_screen.dart`.
- `customers_screen.dart` قبل فصل settlement ViewModel/use cases.
- `sms_execution_gateway.dart` قبل وجود clean production gateway.
- backup/restore AppDb paths قبل backup format جديد.
- pilot/debug services قبل اكتمال migration ومرور parity لفترة كافية.

## حواجز الاختبار المضافة

تمت إضافة `test/final_isolation_guard_test.dart` لتثبيت الحدود التالية:

- SMS integration core لا يعتمد مباشرة على `AppDb` ويخطط عبر UseCases.
- AI advisory services لا تحتوي أي write path للمحاسبة.
- customer ledger screen يستخدم `CustomerAccountBuilder`.
- full pending settlement لا ينشئ hidden claim.
- total settlement implementation يوزع إلى per-item settlement rows ولا يكتفي بصف عام.

## توصية Phase 2

ابدأ بـ "Clean Write Gateway Phase" وليس removal:

1. إنشاء ViewModel/Controller لكل من transfer/receive/claims/pending يكتب عبر UseCases.
2. إبقاء AppDb write كـ shadow أو rollback path مؤقت، مع parity snapshot قبل/بعد.
3. استبدال `AppDbSmsExecutionGateway` بـ clean event gateway، ثم bridge AppDb للقراءة فقط أثناء الانتقال.
4. تحويل dashboard/treasury إلى `AccountingSnapshotBuilder` من clean events.
5. تحويل customer report إلى `CustomerAccountBuilder`.
6. توسيع backup ليشمل event store + legacy history metadata.
7. بعد 2-3 دورات parity كاملة بدون mismatch: صنف pilot/debug/legacy builders كـ `SAFE_REMOVE_LATER` وابدأ إزالة صغيرة ومراجعة.

