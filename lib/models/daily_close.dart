class DailyClose {
  final int id;
  final String dateKey; // yyyy-MM-dd
  final DateTime closedAt;

  final double drawerBalance;
  final double walletsTotal;
  final double treasuryTotal;

  final double profitTotal;
  final double profitTransfer;
  final double profitReceive;
  final double profitFawry;

  final double inflow;
  final double outflow;
  final double net;

  final int transferCount;
  final int receiveCount;
  final int fawryCashCount;
  final int fawryCreditCount;
  final int expenseCount;
  final int claimCollectCount;
  final int claimPayCount;
  final int pendingCount;

  const DailyClose({
    required this.id,
    required this.dateKey,
    required this.closedAt,
    required this.drawerBalance,
    required this.walletsTotal,
    required this.treasuryTotal,
    required this.profitTotal,
    required this.profitTransfer,
    required this.profitReceive,
    required this.profitFawry,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.transferCount,
    required this.receiveCount,
    required this.fawryCashCount,
    required this.fawryCreditCount,
    required this.expenseCount,
    required this.claimCollectCount,
    required this.claimPayCount,
    required this.pendingCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateKey': dateKey,
        'closedAt': closedAt.toIso8601String(),
        'drawerBalance': drawerBalance,
        'walletsTotal': walletsTotal,
        'treasuryTotal': treasuryTotal,
        'profitTotal': profitTotal,
        'profitTransfer': profitTransfer,
        'profitReceive': profitReceive,
        'profitFawry': profitFawry,
        'inflow': inflow,
        'outflow': outflow,
        'net': net,
        'transferCount': transferCount,
        'receiveCount': receiveCount,
        'fawryCashCount': fawryCashCount,
        'fawryCreditCount': fawryCreditCount,
        'expenseCount': expenseCount,
        'claimCollectCount': claimCollectCount,
        'claimPayCount': claimPayCount,
        'pendingCount': pendingCount,
      };

  static DailyClose fromJson(Map<String, dynamic> j) => DailyClose(
        id: (j['id'] as num).toInt(),
        dateKey: (j['dateKey'] ?? '').toString(),
        closedAt: DateTime.parse(
          (j['closedAt'] ?? DateTime.now().toIso8601String()).toString(),
        ),
        drawerBalance: (j['drawerBalance'] as num?)?.toDouble() ?? 0,
        walletsTotal: (j['walletsTotal'] as num?)?.toDouble() ?? 0,
        treasuryTotal: (j['treasuryTotal'] as num?)?.toDouble() ?? 0,
        profitTotal: (j['profitTotal'] as num?)?.toDouble() ?? 0,
        profitTransfer: (j['profitTransfer'] as num?)?.toDouble() ?? 0,
        profitReceive: (j['profitReceive'] as num?)?.toDouble() ?? 0,
        profitFawry: (j['profitFawry'] as num?)?.toDouble() ?? 0,
        inflow: (j['inflow'] as num?)?.toDouble() ?? 0,
        outflow: (j['outflow'] as num?)?.toDouble() ?? 0,
        net: (j['net'] as num?)?.toDouble() ?? 0,
        transferCount: (j['transferCount'] as num?)?.toInt() ?? 0,
        receiveCount: (j['receiveCount'] as num?)?.toInt() ?? 0,
        fawryCashCount: (j['fawryCashCount'] as num?)?.toInt() ?? 0,
        fawryCreditCount: (j['fawryCreditCount'] as num?)?.toInt() ?? 0,
        expenseCount: (j['expenseCount'] as num?)?.toInt() ?? 0,
        claimCollectCount: (j['claimCollectCount'] as num?)?.toInt() ?? 0,
        claimPayCount: (j['claimPayCount'] as num?)?.toInt() ?? 0,
        pendingCount: (j['pendingCount'] as num?)?.toInt() ?? 0,
      );
}
