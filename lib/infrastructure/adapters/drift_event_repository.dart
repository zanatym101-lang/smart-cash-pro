import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../application/ports/event_repository.dart';
import '../../data/sqlite/app_database.dart';
import '../../domain/services/accounting_engine.dart';
import '../../domain/services/accounting_event_models.dart';

class StoredAccountingEventRecord {
  const StoredAccountingEventRecord({
    required this.sequence,
    required this.eventId,
    required this.eventType,
    required this.payload,
    required this.createdAt,
    this.source = 'clean_gateway',
    this.migratedAt,
    this.originalLegacyId,
    this.replaySequence,
    this.checksum,
  });

  final int sequence;
  final String eventId;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String source;
  final DateTime? migratedAt;
  final String? originalLegacyId;
  final int? replaySequence;
  final String? checksum;

  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    'event_id': eventId,
    'event_type': eventType,
    'timestamp': createdAt.toUtc().toIso8601String(),
    'payload': payload,
    'source': source,
    'migrated_at': migratedAt?.toUtc().toIso8601String(),
    'original_legacy_id': originalLegacyId,
    'replay_sequence': replaySequence,
    'checksum': checksum,
  };
}

class DriftEventRepository implements EventRepository {
  DriftEventRepository(this.db, {required this.storePath});

  final AppDatabase db;
  final String storePath;
  bool _initialized = false;
  int _idCounter = 0;

  Future<void> close() => db.close();

  Future<void> clearEvents() async {
    await _ensureInitialized();
    await db.customStatement('DELETE FROM accounting_events');
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS accounting_events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'clean_gateway',
        migrated_at TEXT,
        original_legacy_id TEXT,
        replay_sequence INTEGER,
        checksum TEXT
      )
    ''');
    await _addColumnIfMissing(
      'accounting_events',
      'source',
      "TEXT NOT NULL DEFAULT 'clean_gateway'",
    );
    await _addColumnIfMissing('accounting_events', 'migrated_at', 'TEXT');
    await _addColumnIfMissing(
      'accounting_events',
      'original_legacy_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      'accounting_events',
      'replay_sequence',
      'INTEGER',
    );
    await _addColumnIfMissing('accounting_events', 'checksum', 'TEXT');
    _initialized = true;
  }

  Future<void> _addColumnIfMissing(
    String table,
    String column,
    String definition,
  ) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    final exists = rows.any((row) => row.data['name'] == column);
    if (exists) return;
    await db.customStatement(
      'ALTER TABLE $table ADD COLUMN $column $definition',
    );
  }

  @override
  Future<List<AccountingEvent>> loadEvents() async {
    await _ensureInitialized();
    final rows = await db.customSelect('''
      SELECT event_type, payload
      FROM accounting_events
      ORDER BY seq ASC
    ''').get();
    return rows
        .map(
          (row) => _eventFromStored(
            row.data['event_type']! as String,
            jsonDecode(row.data['payload']! as String) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  Future<List<StoredAccountingEventRecord>> loadStoredEventRecords() async {
    await _ensureInitialized();
    final rows = await db.customSelect('''
      SELECT
        seq,
        event_id,
        event_type,
        payload,
        created_at,
        source,
        migrated_at,
        original_legacy_id,
        replay_sequence,
        checksum
      FROM accounting_events
      ORDER BY seq ASC
    ''').get();
    return rows
        .map(
          (row) => StoredAccountingEventRecord(
            sequence: row.data['seq']! as int,
            eventId: row.data['event_id']! as String,
            eventType: row.data['event_type']! as String,
            payload:
                jsonDecode(row.data['payload']! as String)
                    as Map<String, dynamic>,
            createdAt: DateTime.parse(row.data['created_at']! as String),
            source: (row.data['source'] as String?) ?? 'clean_gateway',
            migratedAt: row.data['migrated_at'] == null
                ? null
                : DateTime.parse(row.data['migrated_at']! as String),
            originalLegacyId: row.data['original_legacy_id'] as String?,
            replaySequence: row.data['replay_sequence'] as int?,
            checksum: row.data['checksum'] as String?,
          ),
        )
        .toList(growable: false);
  }

  Future<bool> verifyIntegrity() async {
    final records = await loadStoredEventRecords();
    for (final record in records) {
      final checksum = record.checksum;
      if (checksum == null || checksum.isEmpty) return false;
      if (checksum != computeChecksum(record.eventType, record.payload)) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> saveEvents(List<AccountingEvent> events) async {
    if (events.isEmpty) return;
    await _ensureInitialized();
    await db.transaction(() async {
      for (final event in events) {
        final now = DateTime.now().toUtc();
        final eventId = '${now.microsecondsSinceEpoch}-${_idCounter++}';
        final eventType = _eventType(event);
        final payload = _eventToStored(event);
        final checksum = computeChecksum(eventType, payload);
        await db.customStatement(
          '''
          INSERT INTO accounting_events (
            event_id,
            event_type,
            payload,
            created_at,
            source,
            migrated_at,
            original_legacy_id,
            replay_sequence,
            checksum
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            eventId,
            eventType,
            jsonEncode(payload),
            now.toIso8601String(),
            'clean_gateway',
            null,
            null,
            null,
            checksum,
          ],
        );
      }
    });
  }

  String computeChecksum(String eventType, Map<String, dynamic> payload) {
    final canonical = jsonEncode({
      'eventType': eventType,
      'payload': _sortJson(payload),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Object? _sortJson(Object? value) {
    if (value is Map) {
      final sorted = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        sorted[key] = _sortJson(value[key]);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_sortJson).toList(growable: false);
    }
    return value;
  }

  String _eventType(AccountingEvent event) => switch (event) {
    DeferredTransferEvent() => 'DeferredTransferEvent',
    DeferredReceiveEvent() => 'DeferredReceiveEvent',
    TransferCreatedEvent() => 'TransferCreatedEvent',
    ReceiveCreatedEvent() => 'ReceiveCreatedEvent',
    SettlementEvent() => 'SettlementEvent',
    ClaimCreatedEvent() => 'ClaimCreatedEvent',
    ClaimSettledEvent() => 'ClaimSettledEvent',
    TreasuryDepositEvent() => 'TreasuryDepositEvent',
    TreasuryWithdrawEvent() => 'TreasuryWithdrawEvent',
    WalletFundingEvent() => 'WalletFundingEvent',
    FawryBalanceAdjusted() => 'FawryBalanceAdjusted',
    ExpenseEvent() => 'ExpenseEvent',
    DailyCloseEvent() => 'DailyCloseEvent',
    PendingConfirmedEvent() => 'PendingConfirmedEvent',
    PendingCancelledEvent() => 'PendingCancelledEvent',
    RollbackEvent() => 'RollbackEvent',
    OpeningBalancesRecorded() => 'OpeningBalancesRecorded',
    DeferredTransferCreated() => 'DeferredTransferCreated',
    DeferredReceiveCreated() => 'DeferredReceiveCreated',
    WalletDebited() => 'WalletDebited',
    WalletCredited() => 'WalletCredited',
    DrawerAdjusted() => 'DrawerAdjusted',
    ClientFeeApplied() => 'ClientFeeApplied',
    NetworkFeeApplied() => 'NetworkFeeApplied',
    PartialCollected() => 'PartialCollected',
    PartialPaid() => 'PartialPaid',
    PendingConfirmed() => 'PendingConfirmed',
    ClaimOpened() => 'ClaimOpened',
    ClaimPartiallySettled() => 'ClaimPartiallySettled',
    ClaimFullySettled() => 'ClaimFullySettled',
    ClaimClosed() => 'ClaimClosed',
    _ => throw StateError('Unsupported accounting event type: $event'),
  };

  Map<String, dynamic> _eventToStored(AccountingEvent event) => switch (event) {
    DeferredTransferEvent() => _transferCreatedToJson(event),
    DeferredReceiveEvent() => _receiveCreatedToJson(event),
    TransferCreatedEvent() => _transferCreatedToJson(event),
    ReceiveCreatedEvent() => _receiveCreatedToJson(event),
    SettlementEvent() => {
      'settlement': _settlementToJson(event.settlement),
      'remainingAmount': event.remainingAmount,
      'direction': event.direction.name,
      'note': event.note,
    },
    ClaimCreatedEvent() => {
      'claimId': event.claimId,
      'direction': event.direction.name,
      'customerName': event.customerName,
      'originalAmount': event.originalAmount,
      'remainingAmount': event.remainingAmount,
      'sourceTransactionId': event.sourceTransactionId,
    },
    ClaimSettledEvent() => {
      'claimId': event.claimId,
      'settledAmount': event.settledAmount,
      'remainingAmount': event.remainingAmount,
      'direction': event.direction.name,
      'fullSettlement': event.fullSettlement,
    },
    TreasuryDepositEvent() => {
      'transactionId': event.transactionId,
      'amount': event.amount,
      'note': event.note,
    },
    TreasuryWithdrawEvent() => {
      'transactionId': event.transactionId,
      'amount': event.amount.abs(),
      'note': event.note,
    },
    WalletFundingEvent() => {
      'transactionId': event.transactionId,
      'walletId': event.walletId,
      'amount': event.amount,
      'note': event.note,
    },
    FawryBalanceAdjusted() => {
      'transactionId': event.transactionId,
      'amount': event.amount,
      'note': event.note,
    },
    ExpenseEvent() => {
      'transactionId': event.transactionId,
      'amount': event.amount.abs(),
      'category': event.category,
      'note': event.note,
    },
    DailyCloseEvent() => {
      'closeId': event.closeId,
      'dateKey': event.dateKey,
      'closed': event.closed,
    },
    PendingConfirmedEvent() => {
      'transactionId': event.transactionId,
      'kind': event.kind.name,
      'remainingAmount': event.remainingAmount,
    },
    PendingCancelledEvent() => {
      'transactionId': event.transactionId,
      'kind': event.kind.name,
      'walletDelta': event.walletDelta,
      'drawerDelta': event.drawerDelta,
    },
    RollbackEvent() => {
      'transactionId': event.transactionId,
      'walletDelta': event.walletDelta,
      'drawerDelta': event.drawerDelta,
      'clientFeeDelta': event.clientFeeDelta,
      'networkFeeDelta': event.networkFeeDelta,
    },
    OpeningBalancesRecorded() => {
      'drawer': event.drawer,
      'wallets': event.wallets,
    },
    DeferredTransferCreated() => {
      'transaction': _deferredTransferToJson(event.transaction),
    },
    DeferredReceiveCreated() => {
      'transaction': _deferredReceiveToJson(event.transaction),
    },
    WalletDebited() => {
      'transactionId': event.transactionId,
      'amount': event.amount,
    },
    WalletCredited() => {
      'transactionId': event.transactionId,
      'amount': event.amount,
    },
    DrawerAdjusted() => {
      'transactionId': event.transactionId,
      'amount': event.amount,
    },
    ClientFeeApplied() => {
      'transactionId': event.transactionId,
      'amount': event.amount,
    },
    NetworkFeeApplied() => {
      'transactionId': event.transactionId,
      'amount': event.amount,
    },
    PartialCollected() => {
      'settlement': _settlementToJson(event.settlement),
      'remainingAmount': event.remainingAmount,
      'direction': event.direction.name,
    },
    PartialPaid() => {
      'settlement': _settlementToJson(event.settlement),
      'remainingAmount': event.remainingAmount,
      'direction': event.direction.name,
    },
    PendingConfirmed() => {
      'transactionId': event.transactionId,
      'kind': event.kind.name,
      'remainingAmount': event.remainingAmount,
    },
    ClaimOpened() => {'claim': _claimToJson(event.claim)},
    ClaimPartiallySettled() => {
      'claimId': event.claimId,
      'settledAmount': event.settledAmount,
      'remainingAmount': event.remainingAmount,
    },
    ClaimFullySettled() => {
      'claimId': event.claimId,
      'settledAmount': event.settledAmount,
    },
    ClaimClosed() => {'claimId': event.claimId},
    _ => throw StateError('Unsupported accounting event payload: $event'),
  };

  AccountingEvent _eventFromStored(
    String type,
    Map<String, dynamic> json,
  ) => switch (type) {
    'DeferredTransferEvent' => DeferredTransferEvent(
      transactionId: json['transactionId'] as String,
      walletId: json['walletId'] as int,
      walletDebitAmount: (json['walletDebitAmount'] as num).toDouble(),
      customerAmount: (json['customerAmount'] as num).toDouble(),
      clientFee: (json['clientFee'] as num).toDouble(),
      networkFee: (json['networkFee'] as num).toDouble(),
      customerName: json['customerName'] as String?,
    ),
    'TransferCreatedEvent' => TransferCreatedEvent(
      transactionId: json['transactionId'] as String,
      walletId: json['walletId'] as int,
      walletDebitAmount: (json['walletDebitAmount'] as num).toDouble(),
      customerAmount: (json['customerAmount'] as num).toDouble(),
      clientFee: (json['clientFee'] as num).toDouble(),
      networkFee: (json['networkFee'] as num).toDouble(),
      customerName: json['customerName'] as String?,
      posted: json['posted'] as bool? ?? true,
    ),
    'DeferredReceiveEvent' => DeferredReceiveEvent(
      transactionId: json['transactionId'] as String,
      walletId: json['walletId'] as int,
      walletCreditAmount: (json['walletCreditAmount'] as num).toDouble(),
      payableAmount: (json['payableAmount'] as num).toDouble(),
      commission: (json['commission'] as num? ?? 0).toDouble(),
      receiveType: json['receiveType'] as String? ?? 'cash',
      customerName: json['customerName'] as String?,
    ),
    'ReceiveCreatedEvent' => ReceiveCreatedEvent(
      transactionId: json['transactionId'] as String,
      walletId: json['walletId'] as int,
      walletCreditAmount: (json['walletCreditAmount'] as num).toDouble(),
      payableAmount: (json['payableAmount'] as num).toDouble(),
      commission: (json['commission'] as num? ?? 0).toDouble(),
      receiveType: json['receiveType'] as String? ?? 'cash',
      customerName: json['customerName'] as String?,
      posted: json['posted'] as bool? ?? true,
    ),
    'SettlementEvent' => SettlementEvent(
      settlement: _settlementFromJson(
        json['settlement'] as Map<String, dynamic>,
      ),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
      direction: CashFlowDirection.values.byName(json['direction'] as String),
      note: json['note'] as String?,
    ),
    'ClaimCreatedEvent' => ClaimCreatedEvent(
      claimId: json['claimId'] as String,
      direction: ClaimType.values.byName(json['direction'] as String),
      customerName: json['customerName'] as String,
      originalAmount: (json['originalAmount'] as num).toDouble(),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
      sourceTransactionId: json['sourceTransactionId'] as String? ?? 'manual',
    ),
    'ClaimSettledEvent' => ClaimSettledEvent(
      claimId: json['claimId'] as String,
      settledAmount: (json['settledAmount'] as num).toDouble(),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
      direction: ClaimType.values.byName(json['direction'] as String),
      fullSettlement: json['fullSettlement'] as bool? ?? false,
    ),
    'TreasuryDepositEvent' => TreasuryDepositEvent(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
      note: json['note'] as String?,
    ),
    'TreasuryWithdrawEvent' => TreasuryWithdrawEvent(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
      note: json['note'] as String?,
    ),
    'WalletFundingEvent' => WalletFundingEvent(
      transactionId: json['transactionId'] as String,
      walletId: json['walletId'] as int,
      amount: (json['amount'] as num).toDouble(),
      note: json['note'] as String?,
    ),
    'FawryBalanceAdjusted' => FawryBalanceAdjusted(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
      note: json['note'] as String?,
    ),
    'ExpenseEvent' => ExpenseEvent(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: json['category'] as String,
      note: json['note'] as String?,
    ),
    'DailyCloseEvent' => DailyCloseEvent(
      closeId: json['closeId'] as String,
      dateKey: json['dateKey'] as String,
      closed: json['closed'] as bool,
    ),
    'PendingConfirmedEvent' => PendingConfirmedEvent(
      transactionId: json['transactionId'] as String,
      kind: PendingKind.values.byName(json['kind'] as String),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
    ),
    'PendingCancelledEvent' => PendingCancelledEvent(
      transactionId: json['transactionId'] as String,
      kind: PendingKind.values.byName(json['kind'] as String),
      walletDelta: (json['walletDelta'] as num? ?? 0).toDouble(),
      drawerDelta: (json['drawerDelta'] as num? ?? 0).toDouble(),
    ),
    'RollbackEvent' => RollbackEvent(
      transactionId: json['transactionId'] as String,
      walletDelta: (json['walletDelta'] as num? ?? 0).toDouble(),
      drawerDelta: (json['drawerDelta'] as num? ?? 0).toDouble(),
      clientFeeDelta: (json['clientFeeDelta'] as num? ?? 0).toDouble(),
      networkFeeDelta: (json['networkFeeDelta'] as num? ?? 0).toDouble(),
    ),
    'OpeningBalancesRecorded' => OpeningBalancesRecorded(
      drawer: (json['drawer'] as num).toDouble(),
      wallets: (json['wallets'] as num).toDouble(),
    ),
    'DeferredTransferCreated' => DeferredTransferCreated(
      transaction: _deferredTransferFromJson(
        json['transaction'] as Map<String, dynamic>,
      ),
    ),
    'DeferredReceiveCreated' => DeferredReceiveCreated(
      transaction: _deferredReceiveFromJson(
        json['transaction'] as Map<String, dynamic>,
      ),
    ),
    'WalletDebited' => WalletDebited(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
    ),
    'WalletCredited' => WalletCredited(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
    ),
    'DrawerAdjusted' => DrawerAdjusted(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
    ),
    'ClientFeeApplied' => ClientFeeApplied(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
    ),
    'NetworkFeeApplied' => NetworkFeeApplied(
      transactionId: json['transactionId'] as String,
      amount: (json['amount'] as num).toDouble(),
    ),
    'PartialCollected' => PartialCollected(
      settlement: _settlementFromJson(
        json['settlement'] as Map<String, dynamic>,
      ),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
      direction: CashFlowDirection.values.byName(json['direction'] as String),
    ),
    'PartialPaid' => PartialPaid(
      settlement: _settlementFromJson(
        json['settlement'] as Map<String, dynamic>,
      ),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
      direction: CashFlowDirection.values.byName(json['direction'] as String),
    ),
    'PendingConfirmed' => PendingConfirmed(
      transactionId: json['transactionId'] as String,
      kind: PendingKind.values.byName(json['kind'] as String),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
    ),
    'ClaimOpened' => ClaimOpened(
      claim: _claimFromJson(json['claim'] as Map<String, dynamic>),
    ),
    'ClaimPartiallySettled' => ClaimPartiallySettled(
      claimId: json['claimId'] as String,
      settledAmount: (json['settledAmount'] as num).toDouble(),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
    ),
    'ClaimFullySettled' => ClaimFullySettled(
      claimId: json['claimId'] as String,
      settledAmount: (json['settledAmount'] as num).toDouble(),
    ),
    'ClaimClosed' => ClaimClosed(claimId: json['claimId'] as String),
    _ => throw StateError('Unknown accounting event type: $type'),
  };

  Map<String, dynamic> _deferredTransferToJson(DeferredTransfer transaction) =>
      {
        'id': transaction.id,
        'walletAmount': transaction.walletAmount,
        'clientFee': transaction.clientFee,
        'networkFee': transaction.networkFee,
        'originalCustomerAmount': transaction.originalCustomerAmount,
        'status': transaction.status.name,
      };

  Map<String, dynamic> _transferCreatedToJson(TransferCreatedEvent event) => {
    'transactionId': event.transactionId,
    'walletId': event.walletId,
    'walletDebitAmount': event.walletDebitAmount,
    'customerAmount': event.customerAmount,
    'clientFee': event.clientFee,
    'networkFee': event.networkFee,
    'customerName': event.customerName,
    'posted': event.posted,
  };

  Map<String, dynamic> _receiveCreatedToJson(ReceiveCreatedEvent event) => {
    'transactionId': event.transactionId,
    'walletId': event.walletId,
    'walletCreditAmount': event.walletCreditAmount,
    'payableAmount': event.payableAmount,
    'commission': event.commission,
    'receiveType': event.receiveType,
    'customerName': event.customerName,
    'posted': event.posted,
  };

  DeferredTransfer _deferredTransferFromJson(Map<String, dynamic> json) =>
      DeferredTransfer(
        id: json['id'] as String,
        walletAmount: (json['walletAmount'] as num).toDouble(),
        clientFee: (json['clientFee'] as num).toDouble(),
        networkFee: (json['networkFee'] as num).toDouble(),
        originalCustomerAmount: (json['originalCustomerAmount'] as num)
            .toDouble(),
        status: DeferredTransferStatus.values.byName(json['status'] as String),
      );

  Map<String, dynamic> _deferredReceiveToJson(DeferredReceive transaction) => {
    'id': transaction.id,
    'walletAmount': transaction.walletAmount,
    'originalPayableAmount': transaction.originalPayableAmount,
    'status': transaction.status.name,
  };

  DeferredReceive _deferredReceiveFromJson(Map<String, dynamic> json) =>
      DeferredReceive(
        id: json['id'] as String,
        walletAmount: (json['walletAmount'] as num).toDouble(),
        originalPayableAmount: (json['originalPayableAmount'] as num)
            .toDouble(),
        status: DeferredTransferStatus.values.byName(json['status'] as String),
      );

  Map<String, dynamic> _settlementToJson(SettlementEntry settlement) => {
    'id': settlement.id,
    'deferredTransferId': settlement.deferredTransferId,
    'deferredReceiveId': settlement.deferredReceiveId,
    'claimId': settlement.claimId,
    'amount': settlement.amount,
  };

  SettlementEntry _settlementFromJson(Map<String, dynamic> json) =>
      SettlementEntry(
        id: json['id'] as String,
        deferredTransferId: json['deferredTransferId'] as String?,
        deferredReceiveId: json['deferredReceiveId'] as String?,
        claimId: json['claimId'] as String?,
        amount: (json['amount'] as num).toDouble(),
      );

  Map<String, dynamic> _claimToJson(ClaimEntry claim) => {
    'id': claim.id,
    'type': claim.type.name,
    'sourceDeferredTransferId': claim.sourceDeferredTransferId,
    'originalAmount': claim.originalAmount,
    'remainingAmount': claim.remainingAmount,
    'status': claim.status.name,
  };

  ClaimEntry _claimFromJson(Map<String, dynamic> json) => ClaimEntry(
    id: json['id'] as String,
    type: ClaimType.values.byName(json['type'] as String),
    sourceDeferredTransferId: json['sourceDeferredTransferId'] as String,
    originalAmount: (json['originalAmount'] as num).toDouble(),
    remainingAmount: (json['remainingAmount'] as num).toDouble(),
    status: ClaimStatus.values.byName(json['status'] as String),
  );
}
