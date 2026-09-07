# Phase 6 - Event Persistence and Shadow Reads

## الهدف

هذه المرحلة تنقل replay من وضع parity فقط إلى وضع إنتاجي آمن كطبقة ظل:

- حفظ clean accounting events في Drift.
- تشغيل health checks عند البداية.
- تشغيل shadow reads للداشبورد والتقارير والخزنة والعملاء.
- عدم تبديل واجهة الإنتاج إلى clean reads بعد.
- عدم حذف `AppDb` أو legacy calculations.

## Event persistence lifecycle

المسار الحالي:

`CleanWriteGateway`
→ production write عبر `AppDbBridgeWriter`
→ shadow semantic events اختيارية
→ `DriftEventRepository`
→ جدول `accounting_events`
→ replay لاحقًا

جدول `accounting_events` يحتوي:

- `seq`
- `event_id`
- `event_type`
- `payload`
- `created_at`
- `source`
- `migrated_at`
- `original_legacy_id`
- `replay_sequence`
- `checksum`

`checksum` يحسب من نوع الحدث والـ payload بشكل deterministic، ويستخدم في integrity checks.

## Parity lifecycle

1. قراءة legacy snapshot من `AppDb`.
2. تحويل history إلى events عبر `LegacyHistoryBridgeService`.
3. replay عبر `AccountingReplayEngine`.
4. مقارنة الحقول الأساسية:
   - drawer
   - wallets
   - fawry
   - pending
   - claims
   - liquidity
   - capital
   - profit
5. إنتاج `HistoryReplayParityReport`.

## Replay health checks

تمت إضافة `ParityHealthService`.

المسؤوليات:

- startup parity verification.
- drift reporting.
- snapshot comparison.
- replay integrity checks.

مستويات drift:

- `INFO`
- `WARNING`
- `CRITICAL`

أي checksum failure أو critical drift يجعل الحالة غير صحية.

## Shadow read architecture

تمت إضافة `ShadowReadAdapters`.

المناطق المدعومة:

- dashboard
- reports
- treasury summary
- customer balances

القاعدة المهمة:

UI ما زالت تقرأ من legacy source.  
Shadow adapters تحسب replay silently وتقارن فقط.  
لا يوجد production read switch في Phase 6.

## Drift escalation strategy

- فروق صغيرة داخل tolerance لا تنتج finding.
- فروق فوق warning threshold تصبح `WARNING`.
- فروق فوق critical threshold تصبح `CRITICAL`.
- التقارير لا توقف الإنتاج حاليًا، لكنها تمنع promotion إلى clean reads.

## Promotion criteria

لا يتم نقل dashboard/reports إلى clean snapshots إلا بعد:

1. checksum integrity مستقر.
2. startup parity health أخضر.
3. shadow reads أخضر لفترة كافية.
4. Drift reports بلا CRITICAL.
5. وجود rollback path واضح للعودة إلى legacy reads.

## Migration status

تم:

- توسيع `DriftEventRepository` بmetadata/checksum.
- دعم حفظ وقراءة semantic events.
- إضافة optional shadow event persistence داخل `CleanWriteGateway`.
- إضافة `ParityHealthService`.
- إضافة `ShadowReadAdapters`.
- إضافة اختبارات persistence/restart/checksum/shadow parity.

ما زال مطلوبًا:

- تشغيل health check فعليًا عند startup تحت feature flag.
- تخزين health reports في جدول مخصص إن لزم.
- shadow read telemetry في production build.
- promotion plan منفصل للداشبورد والتقارير.

## Remaining bridge dependencies

- `AppDbBridgeWriter` ما زال كاتب الإنتاج.
- `AppDb` ما زال مصدر الحقيقة التخزيني.
- `LegacyHistoryBridgeService` مطلوب لإعادة بناء history.
- clean event persistence لا يبدل legacy persistence بعد.
