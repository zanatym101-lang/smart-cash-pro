# Clean Write Gateway - Phase 2

## الهدف

هذه المرحلة تبدأ عزل مسارات الكتابة الحسابية عن الاستدعاءات المباشرة لـ `AppDb`، بدون حذف النظام القديم وبدون تغيير سلوك الإنتاج الحالي.

القاعدة الحالية:

UI / SMS
→ `CleanWriteGateway`
→ clean write intent
→ clean UseCase/Event flow عندما يكون المسار مدعومًا
→ `AppDbBridgeWriter` مؤقتًا للحفاظ على قاعدة البيانات الحالية وسلوك الإنتاج

## الملفات الجديدة

| الملف | الدور | الحالة |
|---|---|---|
| `lib/application/write_gateway/write_intents.dart` | نماذج أوامر الكتابة الحسابية | CLEAN_KEEP |
| `lib/application/write_gateway/clean_write_gateway.dart` | بوابة تنفيذ أوامر الكتابة عبر UseCases ثم bridge مؤقت | CLEAN_KEEP |
| `lib/infrastructure/write_gateway/app_db_bridge_writer.dart` | كاتب مؤقت يعكس نفس العملية داخل `AppDb` | LEGACY_BRIDGE_REQUIRED |
| `test/clean_write_gateway_test.dart` | اختبارات parity وحراسة لمسارات gateway | CLEAN_KEEP |

## المسارات التي بدأت الهجرة

| المسار | الحالة | ملاحظات |
|---|---|---|
| إنشاء تحويل فوري | migrated through gateway | يدعم clean events للـ `type1`، وAppDb bridge يحفظ الإنتاج |
| إنشاء تحويل آجل | migrated through gateway | يدعم clean events للـ `type1`، وAppDb bridge يحفظ الإنتاج |
| إنشاء استلام فوري | migrated through gateway | clean مدعوم حاليًا فقط لـ `cash` بدون commission |
| إنشاء استلام آجل | migrated through gateway | clean مدعوم حاليًا فقط لـ `cash` بدون commission |
| SMS execution | migrated through gateway | لا يكتب مباشرة `addTransfer/addReceive`، ولا يزال يطلب review/duplicate checks |
| تسويات العملاء من الشاشة | migrated through gateway bridge | التسويات المحددة والإجمالية تمر عبر gateway، وAppDb bridge يحفظ السلوك |

## المسارات التي لا تزال legacy direct

| المسار | سبب الإبقاء | خطوة الهجرة التالية |
|---|---|---|
| `pending_screen.dart` confirm/cancel | يحتاج mapping واضح لأحداث confirm/cancel/cancelled | إضافة intents لـ confirm/cancel |
| `tx_details_screen.dart` confirm/cancel/rollback | عمليات إدارية وحساسة | نقلها بعد parity tests منفصلة |
| `claims_screen.dart` إنشاء claim وتسويته من الشاشة | create claim يحتاج intent مستقل وmetadata parity | إضافة `CreateClaimIntent` ثم bridge |
| treasury drawer deposit | ليس ضمن نطاق Phase 2 الحالي | مرحلة treasury write gateway |
| wallet funding / wallets / expenses / fawry | ليست accounting core transfer/receive settlement في هذه المرحلة | مراحل منفصلة |
| dashboard/reports | read flows فقط في هذه المرحلة | Phase لاحقة لتحويل القراءة إلى snapshots |

## مسؤوليات AppDbBridgeWriter

- يحافظ على نفس التخزين الحالي في `AppDb`.
- لا يصبح مصدر الحقيقة طويل المدى.
- يستخدم فقط كطبقة bridge أثناء migration.
- لا يغير معادلات الحساب أو شكل التاريخ.
- يعيد `legacyId` للشاشات حتى تظل رسائل النجاح الحالية كما هي.

## حدود clean execution الحالية

- `type2` transfers ما زالت bridge-only لأن clean engine لا يغطيها بالكامل بعد.
- receive بأنواع غير `cash` أو commission غير صفرية bridge-only مؤقتًا.
- item-specific settlement من بيانات AppDb التاريخية يتم mirror عبر bridge؛ clean replay الكامل يحتاج `HistoryBridgeService` في Phase لاحقة بدل baseline aggregate snapshot.
- لا يتم استخدام Drift event store كمسار إنتاج دائم في هذه المرحلة حتى لا يتداخل مع pilot code القديم الذي يمسح جدول `accounting_events`.

## Rollback strategy

الرجوع آمن ومباشر:

1. إعادة استدعاء الشاشات إلى `AppDb.instance.addTransfer/addReceive/settle...`.
2. حذف استخدام `CleanWriteGateway.appDbBridge()` من المسار المتأثر فقط.
3. لا يوجد data rewrite ولا حذف history في هذه المرحلة.
4. `AppDb` ما زال يحتوي على السجل الإنتاجي الكامل.

## Parity status

تمت إضافة اختبارات تغطي:

- transfer intent clean treasury parity.
- settlement intent ينشئ settlement row مرتبطة بالعنصر.
- claim settlement intent يحدث claim balance.
- AppDb bridge يحافظ على live treasury parity.
- SMS execution لم يعد يستدعي `AppDb.instance.addTransfer/addReceive` مباشرة.

## توصية Phase 3

الخطوة الأكثر أمانًا:

1. إضافة `CreateClaimIntent`.
2. نقل `claims_screen.dart` إلى gateway.
3. إضافة intents لـ `ConfirmPendingIntent` و`CancelPendingIntent`.
4. نقل `pending_screen.dart` و`tx_details_screen.dart` تدريجيًا.
5. بعد ذلك استخدام `LegacyHistoryBridgeService` لتغذية clean event store من التاريخ الحقيقي بدل baseline aggregate snapshot.

## Phase 3 - Claims and Pending Gateway

### migrated flows

| flow | status | notes |
|---|---|---|
| create claim | migrated through gateway | `CreateClaimIntent` writes clean events when possible and mirrors to AppDb |
| settle claim | migrated through gateway | `SettleClaimIntent` / legacy-compatible `CreateClaimSettlementIntent` |
| confirm pending | migrated through gateway | `ConfirmPendingIntent`; AppDb bridge is still production persistence |
| cancel pending | migrated through gateway | `CancelPendingIntent`; bridge-only until clean cancel events exist |
| rollback posted/settlement | migrated through gateway | `RollbackTransactionIntent`; bridge-only for safety |
| `claims_screen.dart` writes | migrated | no direct `addClaim/settleClaim` UI calls |
| `pending_screen.dart` writes | migrated | no direct `confirmPending/cancelPending` UI calls |
| `tx_details_screen.dart` writes | migrated | no direct `confirm/cancel/rollback` UI calls |
| customer claim/pending actions | migrated | edit/delete/settle/confirm/cancel actions use gateway |

### new intents

- `CreateClaimIntent`
- `SettleClaimIntent`
- `ConfirmPendingIntent`
- `CancelPendingIntent`
- `RollbackTransactionIntent`

### bridge-only limits

- `CancelPendingIntent` is bridge-only because the clean event model does not yet have a cancel event.
- `RollbackTransactionIntent` is bridge-only because rollback/reversal events are not modeled yet.
- Pending confirm from live AppDb history is bridge-only in `appDbBridge()` mode until Phase 4 uses `LegacyHistoryBridgeService` to seed item-level clean history instead of aggregate baseline events.
- Claim and settlement writes still preserve AppDb as the production record during migration.

### parity status after Phase 3

Added tests cover claim creation, claim settlement, pending confirm, pending cancel, rollback, and guard checks that migrated screens do not call direct AppDb claim/pending write methods.

### remaining direct AppDb write paths

| area | reason |
|---|---|
| treasury drawer deposit | treasury gateway not migrated yet |
| wallet funding | wallet/funding subsystem not migrated yet |
| wallet create/update/reset limits | settings/administration, outside accounting write gateway scope so far |
| fawry | separate accounting flow still legacy-active |
| expenses | separate ledger flow still legacy-active |
| daily close/reopen | reporting/admin operation, not migrated yet |
| backup/restore/admin/license/audit | infrastructure/admin paths, keep outside accounting migration for now |
| dashboard/reports | reads only in this phase; no migration yet |

### rollback strategy after Phase 3

Rollback remains simple because no data rewrite happened:

1. Restore the affected screen call from `CleanWriteGateway.appDbBridge().execute(...)` to the previous AppDb method.
2. Keep the intent classes and tests; they are additive and do not change stored data.
3. AppDb remains the production persistence source.

### recommended Phase 4

Move from aggregate baseline clean execution to real item-level clean replay:

1. Use `LegacyHistoryBridgeService` before gateway execution to seed clean repositories with real transactions, claims, settlements, and pending items.
2. Add clean events for cancel and rollback/reversal.
3. Migrate treasury writes: drawer deposit and wallet funding.
4. Only after parity remains green, start dashboard/report read migration to snapshots.

## Phase 4 - Treasury and Wallet Write Isolation

### migrated flows

| flow | status | notes |
|---|---|---|
| drawer deposit | migrated through gateway | `DrawerDepositIntent`; AppDb bridge preserves the current drawer transaction behavior |
| drawer withdraw | migrated through gateway | `DrawerWithdrawIntent`; bridge writes the same signed drawer adjustment used before |
| wallet external funding | migrated through gateway | `WalletFundingIntent`; keeps wallet-only funding behavior |
| wallet create/update | migrated through gateway | `WalletAdjustmentIntent`; admin wallet metadata and opening balance behavior preserved |
| wallet usage resets | migrated through gateway | daily/monthly single-wallet and all-wallet resets use `WalletAdjustmentIntent` |
| expense create/update/delete | migrated through gateway | `ExpenseIntent`; drawer/profit behavior remains AppDb-backed |
| fawry service creation | migrated through gateway | `FawryIntent`; cash/credit and pending behavior unchanged |
| daily close/reopen | migrated through gateway | `DailyCloseIntent`; reporting data is still read from AppDb |

### new intents

- `DrawerDepositIntent`
- `DrawerWithdrawIntent`
- `WalletFundingIntent`
- `WalletAdjustmentIntent`
- `ExpenseIntent`
- `FawryIntent`
- `DailyCloseIntent`

### bridge responsibilities

- Treasury/wallet Phase 4 flows are bridge-only for clean execution for now.
- `CleanWriteGateway` returns `clean_gateway_treasury_wallet_bridge_only` for these intents.
- `AppDbBridgeWriter` remains responsible for the exact production mutation while the clean event model gains treasury, wallet administration, expense, fawry, and daily-close events.
- No stored history is rewritten and no AppDb tables/files are deleted.

### parity status after Phase 4

Added tests cover:

- drawer deposit/withdraw treasury parity.
- wallet funding parity.
- expense create/update/delete drawer parity.
- fawry profit parity.
- wallet admin bridge routing.
- daily close/reopen bridge routing.
- guard checks that migrated treasury/wallet screens no longer call direct AppDb write methods.

### remaining legacy paths after Phase 4

| area | status |
|---|---|
| dashboard/report calculations | still legacy read path; intentionally not migrated in Phase 4 |
| backup/restore/admin/license/audit | infrastructure/admin paths; outside accounting write gateway scope |
| clean treasury/wallet event persistence | not complete; needs Phase 5 event modeling and history replay |
| AppDbBridgeWriter | still required as temporary production bridge |

### rollback strategy after Phase 4

Rollback is still low-risk:

1. Repoint the affected screen method from `CleanWriteGateway.appDbBridge().execute(...)` to the previous AppDb call.
2. Keep the additive intent classes; they do not rewrite stored data.
3. AppDb remains the production persistence source during this phase.

### recommended Phase 5

1. Add clean event models/use cases for treasury and wallet funding/adjustment flows.
2. Extend `LegacyHistoryBridgeService` to replay drawer, wallet funding, expense, fawry, and daily-close history.
3. Add snapshot parity tests using real bridged history instead of aggregate baselines.
4. Start dashboard/report read migration only after treasury and profit parity are stable.
