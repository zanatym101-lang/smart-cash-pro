import '../../domain/models/treasury_ledger.dart';
import '../../models/transaction.dart';
import '../../accounting/engine.dart';
import '../../domain/models/money.dart';

class TreasuryLedgerBuilder {
  static TreasuryAccount build({
    required List<LedgerEntry> drawerEntries,
    required Map<String, Txn> txnsMap,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    double openingQ = 0;
    double inQ = 0;
    double outQ = 0;
    double expensesQ = 0;
    double adjustmentsQ = 0;
    double closingQ = 0;

    final rows = <TreasuryLedgerRow>[];

    // Filter by date range and calculate opening balance
    for (final entry in drawerEntries) {
      if (startDate != null && entry.ts.isBefore(startDate)) {
        openingQ += entry.deltaQirsh;
        closingQ += entry.deltaQirsh;
        continue;
      }
      if (endDate != null && entry.ts.isAfter(endDate)) {
        continue;
      }

      closingQ += entry.deltaQirsh;
      
      final txnIdStr = entry.txId.replaceAll('txn:', '');
      final txn = txnsMap[txnIdStr];
      
      TreasuryEventType eventType = TreasuryEventType.cashReceived;
      String description = '';
      String? reference;
      
      final kind = entry.meta['kind'] as String?;
      if (txn != null) {
        description = _getDescriptionForTxn(txn, kind);
        reference = txn.reference ?? txn.party;
        eventType = _getEventType(txn, entry.deltaQirsh);
        
        if (eventType == TreasuryEventType.expense) {
          expensesQ += entry.deltaQirsh.abs();
        } else if (eventType == TreasuryEventType.adjustment) {
          adjustmentsQ += entry.deltaQirsh;
        } else {
          if (entry.deltaQirsh > 0) {
            inQ += entry.deltaQirsh;
          } else {
            outQ += entry.deltaQirsh.abs();
          }
        }
      } else {
        // Fallback if txn is missing (e.g., deleted or legacy)
        description = 'عملية غير معروفة (${entry.txId})';
        if (entry.deltaQirsh > 0) {
          inQ += entry.deltaQirsh;
        } else {
          outQ += entry.deltaQirsh.abs();
        }
      }

      rows.add(
        TreasuryLedgerRow(
          id: '${entry.txId}_${entry.ts.millisecondsSinceEpoch}',
          date: entry.ts,
          eventId: entry.txId,
          eventType: eventType,
          amount: Money.fromQirsh(entry.deltaQirsh),
          balanceAfter: Money.fromQirsh(closingQ.toInt()),
          description: description,
          reference: reference,
        ),
      );
    }

    return TreasuryAccount(
      openingBalance: Money.fromQirsh(openingQ.toInt()),
      totalIn: Money.fromQirsh(inQ.toInt()),
      totalOut: Money.fromQirsh(outQ.toInt()),
      expenses: Money.fromQirsh(expensesQ.toInt()),
      adjustments: Money.fromQirsh(adjustmentsQ.toInt()),
      closingBalance: Money.fromQirsh(closingQ.toInt()),
      rows: rows.reversed.toList(), // descending (newest first)
    );
  }

  static TreasuryEventType _getEventType(Txn txn, int deltaQirsh) {
    switch (txn.kind) {
      case 'expense':
        return TreasuryEventType.expense;
      case 'transfer':
      case 'receive':
        return deltaQirsh > 0 ? TreasuryEventType.cashReceived : TreasuryEventType.cashTransferred;
      case 'drawer_fund':
      case 'drawer_deposit':
      case 'drawer_withdraw':
      case 'claim_collect':
      case 'claim_pay':
      case 'claim_open_receivable':
      case 'claim_open_payable':
      case 'pending_settlement_adjust':
        if (txn.note?.contains('تمويل') == true || txn.kind == 'drawer_deposit') {
          return TreasuryEventType.funding;
        } else if (txn.note?.contains('سحب') == true || txn.kind == 'drawer_withdraw') {
          return TreasuryEventType.withdrawal;
        } else if (txn.kind.startsWith('claim')) {
          return TreasuryEventType.settlement;
        }
        return TreasuryEventType.adjustment;
      case 'fawry_cash':
        return TreasuryEventType.cashReceived;
      default:
        return TreasuryEventType.adjustment;
    }
  }

  static String _getDescriptionForTxn(Txn txn, String? metaKind) {
    if (txn.kind == 'expense') {
      return 'مصروف: ${txn.note ?? txn.serviceName ?? ''}';
    } else if (txn.kind == 'transfer') {
      return 'استلام نقدي لتحويل مرسل';
    } else if (txn.kind == 'receive') {
      return 'صرف نقدي لتحويل مستلم';
    } else if (txn.kind == 'fawry_cash') {
      return 'عملية فوري نقداً';
    } else if (txn.kind == 'drawer_fund' || txn.kind == 'drawer_deposit' || txn.kind == 'drawer_withdraw') {
      return txn.note ?? 'تعديل درج';
    } else if (txn.kind.startsWith('claim')) {
      return txn.note ?? 'تسوية آجل';
    }
    return txn.note ?? txn.kind;
  }
}
