import '../models/transaction.dart';
import '../models/claim.dart';

class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange({required this.start, required this.end});

  bool contains(DateTime d) {
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

class ProfitReport {
  final double transfer;
  final double receive;
  final double fawry;

  const ProfitReport({
    required this.transfer,
    required this.receive,
    required this.fawry,
  });

  double get total => transfer + receive + fawry;
}

class DrawerCashflow {
  final double inflow;
  final double outflow;
  final Map<String, double> inflowByType;
  final Map<String, double> outflowByType;

  const DrawerCashflow({
    required this.inflow,
    required this.outflow,
    required this.inflowByType,
    required this.outflowByType,
  });

  double get net => inflow - outflow;
}

class OperationalSummary {
  final int transferCount;
  final int receiveCount;
  final int fawryCashCount;
  final int fawryCreditCount;
  final int expenseCount;
  final int claimCollectCount;
  final int claimPayCount;
  final int pendingCount;

  const OperationalSummary({
    required this.transferCount,
    required this.receiveCount,
    required this.fawryCashCount,
    required this.fawryCreditCount,
    required this.expenseCount,
    required this.claimCollectCount,
    required this.claimPayCount,
    required this.pendingCount,
  });
}

class ClaimsSnapshot {
  final double receivableOpen;
  final double payableOpen;

  const ClaimsSnapshot({
    required this.receivableOpen,
    required this.payableOpen,
  });

  double get net => receivableOpen - payableOpen;
}

class ReportData {
  final ProfitReport profit;
  final DrawerCashflow cashflow;
  final OperationalSummary ops;
  final ClaimsSnapshot claims;

  const ReportData({
    required this.profit,
    required this.cashflow,
    required this.ops,
    required this.claims,
  });
}

class DayInsight {
  final String dateKey;
  final double profit;
  final double volume;
  final int count;

  const DayInsight({
    required this.dateKey,
    required this.profit,
    required this.volume,
    required this.count,
  });
}

class CustomerInsight {
  final String name;
  final double profit;
  final double volume;
  final int count;

  const CustomerInsight({
    required this.name,
    required this.profit,
    required this.volume,
    required this.count,
  });
}

class SmartInsights {
  final List<DayInsight> bestProfitDays;
  final List<DayInsight> mostActiveDays;
  final List<CustomerInsight> topCustomersByProfit;
  final List<CustomerInsight> topCustomersByVolume;

  const SmartInsights({
    required this.bestProfitDays,
    required this.mostActiveDays,
    required this.topCustomersByProfit,
    required this.topCustomersByVolume,
  });
}

class ReportCalculator {
  static ReportData build({
    required List<Txn> txns,
    required List<Claim> claims,
    required DateRange range,
  }) {
    bool inRange(Txn t) => range.contains(t.entryDate);

    final posted = txns
        .where((t) => t.status == 'posted' && inRange(t))
        .toList();
    final pendingCount = txns
        .where((t) => t.status == 'pending' && inRange(t))
        .length;

    double profitTransfer = 0;
    double profitReceive = 0;
    double profitFawry = 0;

    final inflowByType = <String, double>{};
    final outflowByType = <String, double>{};

    double inflow = 0;
    double outflow = 0;

    int transferCount = 0;
    int receiveCount = 0;
    int fawryCashCount = 0;
    int fawryCreditCount = 0;
    int expenseCount = 0;
    int claimCollectCount = 0;
    int claimPayCount = 0;

    void addInflow(String label, double amount) {
      if (amount <= 0) return;
      inflow += amount;
      inflowByType[label] = (inflowByType[label] ?? 0) + amount;
    }

    void addOutflow(String label, double amount) {
      if (amount <= 0) return;
      outflow += amount;
      outflowByType[label] = (outflowByType[label] ?? 0) + amount;
    }

    for (final t in posted) {
      switch (t.kind) {
        case 'transfer':
          transferCount++;
          profitTransfer += t.clientFee;
          final baseAmount = t.amount - t.networkFee;
          if (t.mode == 'type1') {
            addInflow('تحويل (نوع 1)', baseAmount + t.clientFee);
          } else {
            addInflow('تحويل (نوع 2)', baseAmount);
          }
          break;
        case 'receive':
          receiveCount++;
          profitReceive += t.clientFee;
          if (t.mode == 'cash') {
            addOutflow('استلام (نقدي)', t.amount);
          } else if (t.mode == 'deduct') {
            addOutflow('استلام (خصم)', t.amount - t.clientFee);
          }
          break;
        case 'fawry_cash':
          fawryCashCount++;
          profitFawry += t.clientFee;
          addInflow('فوري نقدي (تحصيل)', t.amount + t.clientFee);
          addOutflow('فوري نقدي (تكلفة)', t.amount);
          break;
        case 'fawry_credit':
          fawryCreditCount++;
          profitFawry += t.clientFee;
          addOutflow('فوري آجل (تكلفة)', t.amount);
          break;
        case 'expense':
          expenseCount++;
          addOutflow('مصروفات', t.amount);
          break;
        case 'drawer_deposit':
          if (t.amount >= 0) {
            addInflow('تمويل درج', t.amount);
          } else {
            addOutflow('تمويل درج (سالب)', -t.amount);
          }
          break;
        case 'claim_collect':
          claimCollectCount++;
          addInflow('تحصيل مستحقات', t.amount);
          break;
        case 'claim_pay':
          claimPayCount++;
          addOutflow('سداد مستحقات', t.amount);
          break;
        default:
          break;
      }
    }

    final receivableOpen = claims
        .where((c) => c.status == 'open' && c.type == 'receivable')
        .fold<double>(0, (s, c) => s + c.amount);
    final payableOpen = claims
        .where((c) => c.status == 'open' && c.type == 'payable')
        .fold<double>(0, (s, c) => s + c.amount);

    return ReportData(
      profit: ProfitReport(
        transfer: profitTransfer,
        receive: profitReceive,
        fawry: profitFawry,
      ),
      cashflow: DrawerCashflow(
        inflow: inflow,
        outflow: outflow,
        inflowByType: inflowByType,
        outflowByType: outflowByType,
      ),
      ops: OperationalSummary(
        transferCount: transferCount,
        receiveCount: receiveCount,
        fawryCashCount: fawryCashCount,
        fawryCreditCount: fawryCreditCount,
        expenseCount: expenseCount,
        claimCollectCount: claimCollectCount,
        claimPayCount: claimPayCount,
        pendingCount: pendingCount,
      ),
      claims: ClaimsSnapshot(
        receivableOpen: receivableOpen,
        payableOpen: payableOpen,
      ),
    );
  }

  static SmartInsights buildSmart({
    required List<Txn> txns,
    required DateRange range,
  }) {
    bool inRange(Txn t) => range.contains(t.entryDate);

    String dayKey(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    double txnProfit(Txn t) => t.clientFee > 0 ? t.clientFee : 0;

    double txnVolume(Txn t) {
      switch (t.kind) {
        case 'transfer':
          return t.amount - t.networkFee;
        case 'fawry_cash':
        case 'fawry_credit':
          return t.amount + t.clientFee;
        default:
          return t.amount;
      }
    }

    bool isOperational(Txn t) {
      if (t.kind == 'drawer_deposit') return false;
      if (t.kind == 'external_funding') return false;
      if (t.kind == 'rollback') return false;
      return true;
    }

    final dayMap = <String, DayInsight>{};
    final customerMap = <String, CustomerInsight>{};

    for (final t in txns) {
      if (t.status != 'posted') continue;
      if (!inRange(t)) continue;
      if (!isOperational(t)) continue;

      final key = dayKey(t.entryDate);
      final profit = txnProfit(t);
      final volume = txnVolume(t);

      final existing = dayMap[key];
      dayMap[key] = DayInsight(
        dateKey: key,
        profit: (existing?.profit ?? 0) + profit,
        volume: (existing?.volume ?? 0) + volume,
        count: (existing?.count ?? 0) + 1,
      );

      final party = (t.party ?? '').trim();
      if (party.isNotEmpty) {
        final c = customerMap[party];
        customerMap[party] = CustomerInsight(
          name: party,
          profit: (c?.profit ?? 0) + profit,
          volume: (c?.volume ?? 0) + volume,
          count: (c?.count ?? 0) + 1,
        );
      }
    }

    final bestProfitDays = dayMap.values.toList()
      ..sort((a, b) => b.profit.compareTo(a.profit));
    final mostActiveDays = dayMap.values.toList()
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        if (c != 0) return c;
        return b.volume.compareTo(a.volume);
      });
    final topCustomersByProfit = customerMap.values.toList()
      ..sort((a, b) => b.profit.compareTo(a.profit));
    final topCustomersByVolume = customerMap.values.toList()
      ..sort((a, b) => b.volume.compareTo(a.volume));

    return SmartInsights(
      bestProfitDays: bestProfitDays.take(5).toList(),
      mostActiveDays: mostActiveDays.take(5).toList(),
      topCustomersByProfit: topCustomersByProfit.take(5).toList(),
      topCustomersByVolume: topCustomersByVolume.take(5).toList(),
    );
  }
}
