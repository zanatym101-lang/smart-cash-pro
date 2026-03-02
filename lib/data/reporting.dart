import '../models/claim.dart';
import '../models/transaction.dart';

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

class ReconciliationLine {
  final String label;
  final double opening;
  final double inflow;
  final double outflow;
  final double expectedClosing;
  final double actualClosing;

  const ReconciliationLine({
    required this.label,
    required this.opening,
    required this.inflow,
    required this.outflow,
    required this.expectedClosing,
    required this.actualClosing,
  });

  double get diff => actualClosing - expectedClosing;
  bool get ok => diff.abs() < 0.0001;
}

class ReconciliationReport {
  final ReconciliationLine drawer;
  final ReconciliationLine wallets;
  final ReconciliationLine total;

  const ReconciliationReport({
    required this.drawer,
    required this.wallets,
    required this.total,
  });

  bool get ok => drawer.ok && wallets.ok && total.ok;
}

class ReportData {
  final ProfitReport profit;
  final DrawerCashflow cashflow;
  final OperationalSummary ops;
  final ClaimsSnapshot claims;
  final ReconciliationReport reconciliation;

  const ReportData({
    required this.profit,
    required this.cashflow,
    required this.ops,
    required this.claims,
    required this.reconciliation,
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
  static ({double drawerDelta, double walletsDelta}) _postedDelta(Txn t) {
    if (t.status != 'posted') return (drawerDelta: 0, walletsDelta: 0);

    switch (t.kind) {
      case 'transfer':
        final sentAmount = t.amount - t.networkFee;
        if (t.mode == 'type1') {
          return (
            drawerDelta: sentAmount + t.clientFee,
            walletsDelta: -t.amount,
          );
        }
        if (t.mode == 'type2_v2') {
          return (
            drawerDelta: sentAmount + t.clientFee + t.networkFee,
            walletsDelta: -t.amount,
          );
        }
        return (drawerDelta: sentAmount, walletsDelta: -t.amount);

      case 'receive':
        if (t.mode == 'cash') {
          return (
            drawerDelta: -(t.amount - t.clientFee),
            walletsDelta: t.amount,
          );
        }
        if (t.mode == 'deduct') {
          return (
            drawerDelta: -(t.amount - t.clientFee),
            walletsDelta: t.amount,
          );
        }
        return (drawerDelta: 0, walletsDelta: t.amount + t.clientFee);

      case 'external_funding':
        return (drawerDelta: 0, walletsDelta: t.amount);

      case 'drawer_deposit':
        return (drawerDelta: t.amount, walletsDelta: 0);

      case 'claim_collect':
        return (drawerDelta: t.amount, walletsDelta: 0);

      case 'claim_pay':
        return (drawerDelta: -t.amount, walletsDelta: 0);

      case 'claim_open_receivable':
        return (drawerDelta: -t.amount, walletsDelta: 0);

      case 'claim_open_payable':
        return (drawerDelta: t.amount, walletsDelta: 0);

      case 'pending_settlement_adjust':
        return (drawerDelta: t.amount, walletsDelta: 0);

      case 'fawry_cash':
        return (drawerDelta: t.amount + t.clientFee, walletsDelta: 0);

      case 'fawry_credit':
        return (drawerDelta: 0, walletsDelta: 0);

      case 'fawry_fund_drawer':
        return (drawerDelta: -t.amount, walletsDelta: 0);

      case 'expense':
        return (drawerDelta: -t.amount, walletsDelta: 0);

      default:
        return (drawerDelta: 0, walletsDelta: 0);
    }
  }

  static ReconciliationReport _buildReconciliation({
    required List<Txn> txns,
    required DateRange range,
  }) {
    double drawerOpening = 0;
    double walletsOpening = 0;
    double drawerIn = 0;
    double drawerOut = 0;
    double walletsIn = 0;
    double walletsOut = 0;
    double drawerClosing = 0;
    double walletsClosing = 0;

    final postedSorted = txns.where((t) => t.status == 'posted').toList()
      ..sort((a, b) {
        final c = a.entryDate.compareTo(b.entryDate);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });

    var seenDrawer = 0.0;
    var seenWallets = 0.0;
    var openingCaptured = false;
    var closingCaptured = false;

    for (final t in postedSorted) {
      final d = _postedDelta(t);
      final inRange = range.contains(t.entryDate);

      if (!openingCaptured && !t.entryDate.isBefore(range.start)) {
        drawerOpening = seenDrawer;
        walletsOpening = seenWallets;
        openingCaptured = true;
      }

      if (inRange) {
        if (d.drawerDelta >= 0) {
          drawerIn += d.drawerDelta;
        } else {
          drawerOut += -d.drawerDelta;
        }
        if (d.walletsDelta >= 0) {
          walletsIn += d.walletsDelta;
        } else {
          walletsOut += -d.walletsDelta;
        }
      }

      seenDrawer += d.drawerDelta;
      seenWallets += d.walletsDelta;

      if (inRange) {
        drawerClosing = seenDrawer;
        walletsClosing = seenWallets;
        closingCaptured = true;
      }
    }

    if (!openingCaptured) {
      drawerOpening = seenDrawer;
      walletsOpening = seenWallets;
    }

    if (!closingCaptured) {
      if (range.end.isBefore(range.start)) {
        drawerClosing = drawerOpening;
        walletsClosing = walletsOpening;
      } else {
        drawerClosing = drawerOpening + drawerIn - drawerOut;
        walletsClosing = walletsOpening + walletsIn - walletsOut;
      }
    }

    final drawerLine = ReconciliationLine(
      label: 'الدرج',
      opening: drawerOpening,
      inflow: drawerIn,
      outflow: drawerOut,
      expectedClosing: drawerOpening + drawerIn - drawerOut,
      actualClosing: drawerClosing,
    );

    final walletsLine = ReconciliationLine(
      label: 'المحافظ',
      opening: walletsOpening,
      inflow: walletsIn,
      outflow: walletsOut,
      expectedClosing: walletsOpening + walletsIn - walletsOut,
      actualClosing: walletsClosing,
    );

    final totalLine = ReconciliationLine(
      label: 'الإجمالي',
      opening: drawerLine.opening + walletsLine.opening,
      inflow: drawerLine.inflow + walletsLine.inflow,
      outflow: drawerLine.outflow + walletsLine.outflow,
      expectedClosing: drawerLine.expectedClosing + walletsLine.expectedClosing,
      actualClosing: drawerLine.actualClosing + walletsLine.actualClosing,
    );

    return ReconciliationReport(
      drawer: drawerLine,
      wallets: walletsLine,
      total: totalLine,
    );
  }

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
          final sentAmount = t.amount - t.networkFee;
          if (t.mode == 'type1') {
            addInflow('تحويل (النوع 1)', sentAmount + t.clientFee);
          } else if (t.mode == 'type2_v2') {
            addInflow(
              'تحويل (النوع 2)',
              sentAmount + t.clientFee + t.networkFee,
            );
          } else {
            addInflow('تحويل (النوع 2 قديم)', sentAmount);
          }
          break;

        case 'receive':
          receiveCount++;
          profitReceive += t.clientFee;
          if (t.mode == 'cash') {
            addOutflow('استلام (نقدي)', t.amount - t.clientFee);
          } else if (t.mode == 'deduct') {
            addOutflow('استلام (خصم من المبلغ)', t.amount - t.clientFee);
          }
          break;

        case 'fawry_cash':
          fawryCashCount++;
          profitFawry += t.clientFee;
          addInflow('فوري نقدي (تحصيل من العميل)', t.amount + t.clientFee);
          break;

        case 'fawry_credit':
          fawryCreditCount++;
          profitFawry += t.clientFee;
          break;

        case 'fawry_fund_drawer':
          addOutflow('شحن رصيد فوري من الدرج', t.amount);
          break;

        case 'expense':
          expenseCount++;
          addOutflow('مصروفات', t.amount);
          break;

        case 'drawer_deposit':
          if (t.amount >= 0) {
            addInflow('تعديل الدرج (إضافة)', t.amount);
          } else {
            addOutflow('تعديل الدرج (خصم)', -t.amount);
          }
          break;

        case 'claim_open_receivable':
          addOutflow('فتح مستحق لنا', t.amount);
          break;

        case 'claim_open_payable':
          addInflow('فتح مستحق علينا', t.amount);
          break;

        case 'claim_collect':
          claimCollectCount++;
          addInflow('تحصيل مستحقات لنا', t.amount);
          break;

        case 'claim_pay':
          claimPayCount++;
          addOutflow('سداد مستحقات علينا', t.amount);
          break;

        case 'pending_settlement_adjust':
          if (t.amount >= 0) {
            addInflow('تسوية تحصيل معلّق', t.amount);
          } else {
            addOutflow('تسوية تحصيل معلّق', -t.amount);
          }
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
      reconciliation: _buildReconciliation(txns: txns, range: range),
    );
  }

  static SmartInsights buildSmart({
    required List<Txn> txns,
    required DateRange range,
  }) {
    bool inRange(Txn t) => range.contains(t.entryDate);

    String dayKey(DateTime d) {
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    double txnProfit(Txn t) => t.clientFee > 0 ? t.clientFee : 0;

    double txnVolume(Txn t) {
      switch (t.kind) {
        case 'transfer':
          if (t.mode == 'type2_v2') {
            return t.amount + t.clientFee;
          }
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
