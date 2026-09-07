import '../../models/claim.dart';
import '../../models/transaction.dart';
import '../../domain/models/customer_account.dart' as domain;
import 'customer_account_models.dart';

import '../../models/wallet.dart';

class CustomerAccountBuilder {
  const CustomerAccountBuilder._();

  static List<CustomerAccount> fromAppDbData({
    required List<Txn> txns,
    required List<Claim> claims,
    List<domain.CustomerAccountAdjustment> adjustments = const [],
    List<Wallet> wallets = const [],
  }) {
    final buckets = <String, _AccountBucket>{};
    final txnById = {for (final txn in txns) txn.id: txn};
    final pendingSettlements = <int, List<Txn>>{};
    final claimSettlements = <int, List<Txn>>{};
    final walletById = {for (final w in wallets) w.id: w};

    for (final txn in txns) {
      if (txn.status != 'posted') continue;
      if (!_isSettlement(txn)) continue;
      final pendingId = _extractPendingSettlementRef(txn.note);
      if (pendingId != null) {
        pendingSettlements.putIfAbsent(pendingId, () => []).add(txn);
      }
      final claimId = _extractClaimIdFromNote(txn.note);
      if (claimId != null) {
        claimSettlements.putIfAbsent(claimId, () => []).add(txn);
      }
    }

    _AccountBucket bucketFor({required String name, String? phone}) {
      final normalizedName = name.trim().isEmpty
          ? 'عميل بدون اسم'
          : name.trim();
      final normalizedPhone = _normalizePhone(phone ?? '');
      final key = normalizedPhone.isNotEmpty
          ? 'p:$normalizedPhone'
          : 'n:${normalizedName.toLowerCase()}';
      return buckets.putIfAbsent(
        key,
        () => _AccountBucket(
          name: normalizedName,
          phone: normalizedPhone.isEmpty ? null : normalizedPhone,
        ),
      );
    }

    for (final txn in txns) {
      if (txn.status == 'rolled_back' ||
          txn.status == 'canceled' ||
          txn.status == 'reversed' ||
          txn.status == 'reverse_entry' ||
          txn.isReversed) {
        continue;
      }
      if (!_isCustomerFacingDeferred(txn)) continue;
      final name = (txn.party ?? '').trim();
      if (name.isEmpty) continue;
      final bucket = bucketFor(
        name: name,
        phone: _extractPhone(txn.note) ?? _extractPhone(txn.reference),
      );
      _addDeferredStory(
        bucket: bucket,
        txn: txn,
        settlements: pendingSettlements[txn.id] ?? const [],
        walletById: walletById,
      );
    }

    for (final claim in claims) {
      if (claim.status == 'cancelled' || claim.status == 'reversed') continue;
      final name = claim.party.trim();
      if (name.isEmpty) continue;
      final sourceTxn = claim.sourceTxnId == null
          ? null
          : txnById[claim.sourceTxnId];
      final bucket = bucketFor(
        name: name,
        phone:
            _extractPhone(claim.note) ??
            _extractPhone(sourceTxn?.note) ??
            _extractPhone(sourceTxn?.reference),
      );
      _addClaimStory(
        bucket: bucket,
        claim: claim,
        sourceTxn: sourceTxn,
        settlements: claimSettlements[claim.id] ?? const [],
        walletById: walletById,
      );
    }

    for (final adj in adjustments) {
      final name = adj.customerId.trim();
      if (name.isEmpty) continue;
      final bucket = bucketFor(
        name: name,
        phone: _extractPhone(adj.note),
      );
      _addAdjustmentStory(
        bucket: bucket,
        adjustment: adj,
      );
    }

    for (final entry in pendingSettlements.entries) {
      final sourceTxn = txnById[entry.key];
      if (sourceTxn != null && _isCustomerFacingDeferred(sourceTxn)) continue;
      final name = (sourceTxn?.party ?? '').trim();
      if (name.isEmpty) continue;
      final bucket = bucketFor(
        name: name,
        phone:
            _extractPhone(sourceTxn?.note) ??
            _extractPhone(sourceTxn?.reference),
      );
      for (final settlement in entry.value) {
        _addSettlementRow(
          bucket: bucket,
          settlement: settlement,
          storySourceTxnId: entry.key,
          remainingAfter: 0,
          sourceKind: sourceTxn?.kind,
          walletById: walletById,
        );
      }
    }

    final accounts = buckets.values.map((bucket) => bucket.toAccount()).toList()
      ..sort((a, b) {
        if (a.summary.archived != b.summary.archived) {
          return a.summary.archived ? 1 : -1;
        }
        final balance = b.summary.netBalance.abs().compareTo(
          a.summary.netBalance.abs(),
        );
        if (balance != 0) return balance;
        return a.summary.customerName.compareTo(b.summary.customerName);
      });
    return List.unmodifiable(accounts);
  }

  static void _addDeferredStory({
    required _AccountBucket bucket,
    required Txn txn,
    required List<Txn> settlements,
    required Map<int, Wallet> walletById,
  }) {
    final due = _deferredDue(txn);
    var remaining = due;
    final isForUs = txn.kind == 'transfer' || txn.kind == 'fawry_credit';
    final sortedSettlements = [...settlements]..sort(_oldestFirst);

    for (final settlement in sortedSettlements) {
      remaining = (remaining - settlement.amount).clamp(0, 1e18).toDouble();
      _addSettlementRow(
        bucket: bucket,
        settlement: settlement,
        storySourceTxnId: txn.id,
        remainingAfter: remaining,
        sourceKind: txn.kind,
        walletById: walletById,
      );
    }

    if (txn.status == 'pending' && remaining > 0) {
      if (isForUs) {
        bucket.openDeferredForUs += remaining;
      } else {
        bucket.openDeferredAgainstUs += remaining;
      }
      bucket.openItemsCount++;
    }

    bucket.rows.add(
      CustomerLedgerRow(
        id: 'txn:${txn.id}',
        storySourceTxnId: txn.id,
        date: txn.entryDate,
        title: _deferredTitle(txn),
        description: _deferredDescription(txn),
        direction: isForUs
            ? CustomerLedgerDirection.forUs
            : CustomerLedgerDirection.againstUs,
        amount: due,
        remainingBalanceAfterRow: due,
        status: txn.status == 'pending' && remaining > 0
            ? (remaining < due
                  ? CustomerLedgerRowStatus.partial
                  : CustomerLedgerRowStatus.open)
            : CustomerLedgerRowStatus.closed,
        sourceType: isForUs
            ? CustomerLedgerSourceType.deferredTransfer
            : CustomerLedgerSourceType.deferredReceive,
        walletId: txn.walletFromId ?? txn.walletToId,
        walletName: walletById[txn.walletFromId ?? txn.walletToId]?.name,
        walletPhone: walletById[txn.walletFromId ?? txn.walletToId]?.phone,
      ),
    );
  }

  static void _addClaimStory({
    required _AccountBucket bucket,
    required Claim claim,
    required Txn? sourceTxn,
    required List<Txn> settlements,
    required Map<int, Wallet> walletById,
  }) {
    final settled = settlements.fold<double>(0, (sum, txn) => sum + txn.amount);
    final originalAmount = claim.status == 'open'
        ? claim.amount + settled
        : claim.amount > settled
        ? claim.amount
        : settled;
    final isForUs = claim.type == 'receivable';
    var remaining = originalAmount;
    final sortedSettlements = [...settlements]..sort(_oldestFirst);

    for (final settlement in sortedSettlements) {
      remaining = (remaining - settlement.amount).clamp(0, 1e18).toDouble();
      _addSettlementRow(
        bucket: bucket,
        settlement: settlement,
        storySourceTxnId: claim.sourceTxnId,
        claimId: claim.id,
        remainingAfter: remaining,
        sourceKind: claim.type,
        walletById: walletById,
      );
    }

    if (claim.status == 'open' && claim.amount > 0) {
      if (isForUs) {
        bucket.openClaimsForUs += claim.amount;
      } else {
        bucket.openClaimsAgainstUs += claim.amount;
      }
      bucket.openItemsCount++;
    }

    final storySourceTxnId = claim.sourceTxnId ?? sourceTxn?.id;
    bucket.rows.add(
      CustomerLedgerRow(
        id: 'claim:${claim.id}',
        storySourceTxnId: storySourceTxnId,
        date: claim.entryDate,
        title: isForUs ? 'مستحق لنا' : 'مستحق علينا',
        description: claim.note ?? 'Claim#${claim.id}',
        direction: isForUs
            ? CustomerLedgerDirection.forUs
            : CustomerLedgerDirection.againstUs,
        amount: originalAmount,
        remainingBalanceAfterRow: claim.amount,
        status: claim.status == 'open'
            ? (settled > 0
                  ? CustomerLedgerRowStatus.partial
                  : CustomerLedgerRowStatus.open)
            : CustomerLedgerRowStatus.closed,
        sourceType: isForUs
            ? CustomerLedgerSourceType.claimReceivable
            : CustomerLedgerSourceType.claimPayable,
      ),
    );
  }
  static void _addAdjustmentStory({
    required _AccountBucket bucket,
    required domain.CustomerAccountAdjustment adjustment,
  }) {
    final amount = adjustment.amount.toDouble();
    final isForUs = adjustment.type == domain.CustomerAdjustmentType.add;

    // We consider unallocated adjustments as open claims-like items.
    // If they have allocations, they would reduce the remaining balance of the linked item, 
    // but for simplicity in UI, we treat them as independent rows for now.
    var remaining = amount;
    for (final alloc in adjustment.allocations) {
      remaining = (remaining - alloc.allocatedAmount.toDouble()).clamp(0, 1e18).toDouble();
    }

    if (remaining > 0) {
      if (isForUs) {
        bucket.openClaimsForUs += remaining;
      } else {
        bucket.openClaimsAgainstUs += remaining;
      }
      bucket.openItemsCount++;
    }

    bucket.rows.add(
      CustomerLedgerRow(
        id: 'adj:${adjustment.id}',
        storySourceTxnId: null,
        date: adjustment.date,
        title: isForUs ? 'تسوية (إضافة)' : 'تسوية (خصم)',
        description: adjustment.note ?? 'تسوية حساب',
        direction: isForUs
            ? CustomerLedgerDirection.forUs
            : CustomerLedgerDirection.againstUs,
        amount: amount,
        remainingBalanceAfterRow: remaining,
        status: remaining > 0
            ? (remaining < amount ? CustomerLedgerRowStatus.partial : CustomerLedgerRowStatus.open)
            : CustomerLedgerRowStatus.closed,
        sourceType: CustomerLedgerSourceType.adjustment,
      ),
    );
  }

  static void _addSettlementRow({
    required _AccountBucket bucket,
    required Txn settlement,
    required int? storySourceTxnId,
    required double remainingAfter,
    required String? sourceKind,
    int? claimId,
    required Map<int, Wallet> walletById,
  }) {
    final isCollection = settlement.kind == 'claim_collect';
    final isOffset = _isOffsetSettlement(settlement.note);
    final rowTitle = isOffset
        ? '🔄 مقاصة تسوية / إغلاق حساب'
        : (isCollection ? 'تحصيل' : 'سداد');
    final rowDesc = isOffset
        ? (settlement.note?.trim().isNotEmpty == true
            ? settlement.note!
            : '🔄 مقاصة تسوية داخلية (الصافي 0.00 ج.م) — تسوية حساب')
        : (settlement.note ?? 'Txn#${settlement.id}');

    bucket.rows.add(
      CustomerLedgerRow(
        id: 'txn:${settlement.id}',
        storySourceTxnId: storySourceTxnId,
        date: settlement.entryDate,
        title: rowTitle,
        description: rowDesc,
        direction: isCollection
            ? CustomerLedgerDirection.againstUs
            : CustomerLedgerDirection.forUs,
        amount: settlement.amount,
        remainingBalanceAfterRow: remainingAfter,
        status: remainingAfter > 0
            ? CustomerLedgerRowStatus.partial
            : CustomerLedgerRowStatus.closed,
        sourceType: CustomerLedgerSourceType.settlement,
        walletId: settlement.walletFromId ?? settlement.walletToId,
        walletName: walletById[settlement.walletFromId ?? settlement.walletToId]?.name,
        walletPhone: walletById[settlement.walletFromId ?? settlement.walletToId]?.phone,
      ),
    );
  }

  static bool _isOffsetSettlement(String? note) {
    if (note == null) return false;
    return note.contains('إغلاق تلقائي') ||
        note.contains('مقاصة') ||
        note.contains('إغلاق حساب') ||
        note.contains('offset') ||
        note.contains('تسوية / إغلاق');
  }

  static bool _isCustomerFacingDeferred(Txn txn) {
    return txn.kind == 'transfer' ||
        txn.kind == 'receive' ||
        txn.kind == 'fawry_credit';
  }

  static bool _isSettlement(Txn txn) {
    return txn.kind == 'claim_collect' || txn.kind == 'claim_pay';
  }

  static double _deferredDue(Txn txn) {
    if (txn.kind == 'transfer') {
      if (txn.mode == 'type2_v2') return txn.amount + txn.clientFee;
      final base = txn.amount - txn.networkFee;
      if (txn.mode == 'type1') return base + txn.clientFee;
      return base;
    }
    if (txn.kind == 'receive') {
      if (txn.mode == 'cash') return txn.amount;
      if (txn.mode == 'deduct') {
        return (txn.amount - txn.clientFee).clamp(0, 1e18);
      }
      return 0;
    }
    if (txn.kind == 'fawry_credit') return txn.amount + txn.clientFee;
    return txn.amount;
  }

  static String _deferredTitle(Txn txn) {
    if (txn.kind == 'transfer') return 'تحويل آجل';
    if (txn.kind == 'receive') return 'استلام آجل';
    if (txn.kind == 'fawry_credit') return 'فوري آجل';
    return txn.kind;
  }

  static String _deferredDescription(Txn txn) {
    final parts = <String>[];
    if ((txn.serviceName ?? '').trim().isNotEmpty) {
      parts.add(txn.serviceName!.trim());
    }
    if ((txn.note ?? '').trim().isNotEmpty) {
      parts.add(txn.note!.trim());
    }
    parts.add('Txn#${txn.id}');
    return parts.join(' | ');
  }

  static int? _extractPendingSettlementRef(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final match = RegExp(r'pending_txn:(\d+)').firstMatch(note);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static int? _extractClaimIdFromNote(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final match = RegExp(r'claim_id:(\d+)').firstMatch(note);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static String? _extractPhone(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'\d{10,15}').firstMatch(text);
    return match?.group(0);
  }

  static String _normalizePhone(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  static int _oldestFirst(Txn a, Txn b) {
    final date = a.entryDate.compareTo(b.entryDate);
    if (date != 0) return date;
    return a.id.compareTo(b.id);
  }
}

class _AccountBucket {
  _AccountBucket({required this.name, this.phone});

  final String name;
  final String? phone;
  final List<CustomerLedgerRow> rows = [];
  double openDeferredForUs = 0;
  double openDeferredAgainstUs = 0;
  double openClaimsForUs = 0;
  double openClaimsAgainstUs = 0;
  int openItemsCount = 0;

  CustomerAccount toAccount() {
    final chronological = [...rows]..sort(_compareRowsChronological);
    final computedRows = <CustomerLedgerRow>[];
    var runningNet = 0.0;
    for (final r in chronological) {
      if (r.direction == CustomerLedgerDirection.forUs) {
        runningNet += r.amount;
      } else if (r.direction == CustomerLedgerDirection.againstUs) {
        runningNet -= r.amount;
      }
      computedRows.add(r.copyWith(remainingBalanceAfterRow: runningNet));
    }
    computedRows.sort(_compareRows);
    final totalForUs = openDeferredForUs + openClaimsForUs;
    final totalAgainstUs = openDeferredAgainstUs + openClaimsAgainstUs;
    final netBalance = totalForUs - totalAgainstUs;
    return CustomerAccount(
      summary: CustomerAccountSummary(
        customerName: name,
        phone: phone,
        totalForUs: totalForUs,
        totalAgainstUs: totalAgainstUs,
        netBalance: netBalance,
        openDeferredForUs: openDeferredForUs,
        openDeferredAgainstUs: openDeferredAgainstUs,
        openClaimsForUs: openClaimsForUs,
        openClaimsAgainstUs: openClaimsAgainstUs,
        openItemsCount: openItemsCount,
        archived: netBalance.abs() < 0.0001,
      ),
      rows: List.unmodifiable(computedRows),
    );
  }

  int _compareRowsChronological(CustomerLedgerRow a, CustomerLedgerRow b) {
    final aStoryDate = _storyAnchor(a);
    final bStoryDate = _storyAnchor(b);
    final storyDate = aStoryDate.compareTo(bStoryDate);
    if (storyDate != 0) return storyDate;
    if (a.storySourceTxnId != null &&
        a.storySourceTxnId == b.storySourceTxnId) {
      final aIsSettlement = a.sourceType == CustomerLedgerSourceType.settlement;
      final bIsSettlement = b.sourceType == CustomerLedgerSourceType.settlement;
      if (aIsSettlement != bIsSettlement) {
        return aIsSettlement ? 1 : -1;
      }
      final date = a.date.compareTo(b.date);
      if (date != 0) return date;
      return a.id.compareTo(b.id);
    }
    final story = (a.storySourceTxnId ?? -1).compareTo(
      b.storySourceTxnId ?? -1,
    );
    if (story != 0) return story;
    final aIsSettlement = a.sourceType == CustomerLedgerSourceType.settlement;
    final bIsSettlement = b.sourceType == CustomerLedgerSourceType.settlement;
    if (aIsSettlement != bIsSettlement) {
      return aIsSettlement ? 1 : -1;
    }
    final date = a.date.compareTo(b.date);
    if (date != 0) return date;
    return a.id.compareTo(b.id);
  }

  int _compareRows(CustomerLedgerRow a, CustomerLedgerRow b) {
    final aStoryDate = _storyAnchor(a);
    final bStoryDate = _storyAnchor(b);
    final storyDate = bStoryDate.compareTo(aStoryDate);
    if (storyDate != 0) return storyDate;
    if (a.storySourceTxnId != null &&
        a.storySourceTxnId == b.storySourceTxnId) {
      final date = b.date.compareTo(a.date);
      if (date != 0) return date;
      return b.id.compareTo(a.id);
    }
    final story = (b.storySourceTxnId ?? -1).compareTo(
      a.storySourceTxnId ?? -1,
    );
    if (story != 0) return story;
    final date = b.date.compareTo(a.date);
    if (date != 0) return date;
    return b.id.compareTo(a.id);
  }

  DateTime _storyAnchor(CustomerLedgerRow row) {
    if (row.storySourceTxnId == null) return row.date;
    final original = rows.where((candidate) {
      return candidate.storySourceTxnId == row.storySourceTxnId &&
          (candidate.sourceType == CustomerLedgerSourceType.deferredTransfer ||
              candidate.sourceType == CustomerLedgerSourceType.deferredReceive);
    }).toList();
    if (original.isNotEmpty) return original.first.date;
    return row.date;
  }
}
