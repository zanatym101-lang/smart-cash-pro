# Event Replay - Phase 5

## الهدف

هذه المرحلة تضيف طبقة Replay قابلة للمراجعة فوق بيانات `AppDb` الحالية، بدون حذف legacy وبدون تغيير سلوك الإنتاج.

المسار الحالي:

`AppDb history`
→ `LegacyHistoryBridgeService`
→ clean accounting events
→ `AccountingReplayEngine`
→ deterministic snapshots
→ parity report against legacy snapshots

## نماذج الأحداث

تمت إضافة أحداث Phase 5 الدلالية بجانب أحداث المحرك الحالية:

- `TransferCreatedEvent`
- `ReceiveCreatedEvent`
- `DeferredTransferEvent`
- `DeferredReceiveEvent`
- `SettlementEvent`
- `ClaimCreatedEvent`
- `ClaimSettledEvent`
- `TreasuryDepositEvent`
- `TreasuryWithdrawEvent`
- `WalletFundingEvent`
- `ExpenseEvent`
- `DailyCloseEvent`
- `PendingConfirmedEvent`
- `PendingCancelledEvent`
- `RollbackEvent`

تمت إضافة `FawryBalanceAdjusted` أيضًا لأن فوري له float مستقل داخل الخزنة ولا يمكن مطابقته بدقة إذا تم دمجه داخل الدرج فقط.

## Replay lifecycle

1. قراءة السجل من `AppDb`.
2. تحويل العمليات القديمة إلى أحداث مرتبة.
3. الحفاظ على metadata لكل حدث:
   - `source = legacy_appdb`
   - `migratedAt`
   - `originalLegacyId`
   - `originalLegacyTable`
   - `originalLegacyKind`
4. تشغيل الأحداث بالترتيب داخل `AccountingReplayEngine`.
5. إنتاج snapshots حتمية.

## Snapshot lifecycle

`AccountingReplayEngine` ينتج:

- `TreasurySnapshot`
- `WalletSnapshot`
- `CustomerSnapshot`
- `ClaimsSnapshot`
- `ProfitSnapshot`

ويحتفظ أيضًا بـ `AccountingSnapshot` المجمع المستخدم في اختبارات parity القديمة.

## Parity strategy

`HistoryReplayService.verifyLegacyParity()` يقارن replay مع `AppDb.getTreasurySnapshot()` في:

- drawer
- wallets
- fawry
- pending receivable/payable
- claims receivable/payable
- available liquidity
- real capital
- profit/client fees

عند وجود اختلاف ينتج `HistoryReplayParityReport` يحتوي `ReplayDrift` لكل حقل، ويتم تسجيل drift بشكل sanitized بدون بيانات حساسة.

## Rollback safety

- `PendingCancelledEvent` و `RollbackEvent` لا يكتبان في قاعدة البيانات.
- هما أحداث replay فقط لعكس الأثر داخل snapshot عند بناء التاريخ.
- لا يوجد data rewrite في هذه المرحلة.

## Migration status

تم:

- إضافة event models الدلالية.
- إضافة `AccountingReplayEngine`.
- توسيع `LegacyHistoryBridgeService` لإخراج أحداث Phase 5.
- إضافة snapshot parity report.
- إضافة اختبارات replay حتمية واختبارات drift/parity.
- إضافة دعم Fawry float داخل clean snapshot.

لم يتم بعد:

- تحويل dashboard/reports إلى قراءة replay snapshots.
- حذف legacy AppDb calculations.
- جعل clean event store هو مصدر الإنتاج الوحيد.

## Bridge dependencies

ما زال مطلوبًا:

- `AppDbBridgeWriter` ككاتب إنتاج مؤقت.
- `LegacyHistoryBridgeService` كمصدر قراءة تاريخي.
- AppDb لحفظ التاريخ الحقيقي حتى Phase لاحقة.

## Recommended Phase 6

1. Persist replayed clean events in Drift event repository behind a safety flag.
2. Add startup parity health check without changing UI reads.
3. Add report/dashboard read adapters that can compare legacy vs replay snapshots in shadow mode.
4. Promote replay snapshots gradually only after drift reports stay clean.
