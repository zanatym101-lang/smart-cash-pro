import 'package:flutter/material.dart';

import '../application/write_gateway/clean_write_gateway.dart';
import '../application/write_gateway/write_intents.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/wallet.dart';
import '../utils/phone_provider.dart';
import '../widgets/app_title.dart';
import 'wallet_funding_screen.dart';
import 'wallet_ledger/wallet_ledger_screen.dart';
import '../models/transaction.dart';

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  bool _loading = true;
  String? _error;

  List<Wallet> _wallets = [];
  final Map<int, double> _balances = {};
  final Map<int, double> _actualBalances = {};
  final Map<int, WalletLimitUsage> _limitUsage = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final wallets = await AppDb.instance.listWallets();
      final balanceList = await Future.wait(
        wallets.map((w) => AppDb.instance.getWalletAvailableBalance(w.id)),
      );
      final actualList = await Future.wait(
        wallets.map((w) => AppDb.instance.getWalletBalance(w.id)),
      );
      final usageMap = await AppDb.instance.getWalletLimitUsage();
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _balances
          ..clear()
          ..addAll({
            for (var i = 0; i < wallets.length; i++)
              wallets[i].id: balanceList[i],
          });
        _actualBalances
          ..clear()
          ..addAll({
            for (var i = 0; i < wallets.length; i++)
              wallets[i].id: actualList[i],
          });
        _limitUsage
          ..clear()
          ..addAll(usageMap);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total => _balances.values.fold(0.0, (a, b) => a + b);
  double get _totalActual => _actualBalances.values.fold(0.0, (a, b) => a + b);
  double get _totalPendingImpact => _total - _totalActual;

  Color _providerColor(String provider) {
    switch (provider.toLowerCase()) {
      case 'vodafone':
        return const Color(0xFFE11D48);
      case 'etisalat':
        return const Color(0xFF16A34A);
      case 'orange':
        return const Color(0xFFF97316);
      case 'we':
        return const Color(0xFF0EA5E9);
      default:
        return const Color(0xFF64748B);
    }
  }

  Future<_WalletFormData?> _walletDialog({
    required String title,
    Wallet? wallet,
  }) async {
    final nameCtrl = TextEditingController(text: wallet?.name ?? '');
    final phoneCtrl = TextEditingController(text: wallet?.phone ?? '');
    final dailyCtrl = TextEditingController(
      text: (wallet?.dailyLimit ?? 60000).toStringAsFixed(0),
    );
    final monthlyCtrl = TextEditingController(
      text: (wallet?.monthlyLimit ?? 200000).toStringAsFixed(0),
    );
    final lowBalCtrl = TextEditingController(
      text: (wallet?.lowBalanceThreshold ?? 0).toStringAsFixed(0),
    );
    final openingBalanceCtrl = TextEditingController(text: '');

    String? error;

    return showDialog<_WalletFormData>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم المحفظة'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'رقم المحفظة (هاتف)',
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'المزوّد: ${providerDisplayName(providerFromPhone(normalizePhone(phoneCtrl.text)))}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dailyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الحد اليومي للتحويل',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: monthlyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الحد الشهري للتحويل',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lowBalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'حد تنبيه الرصيد (اختياري)',
                  ),
                ),
                if (wallet == null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: openingBalanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'رصيد أول المدة (اختياري)',
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final daily = double.tryParse(dailyCtrl.text.trim()) ?? -1;
                final monthly = double.tryParse(monthlyCtrl.text.trim()) ?? -1;
                final lowBal = double.tryParse(lowBalCtrl.text.trim()) ?? -1;
                final openingBalanceText = openingBalanceCtrl.text.trim();
                final openingBalance = wallet == null
                    ? (openingBalanceText.isEmpty
                          ? 0.0
                          : (double.tryParse(openingBalanceText) ?? -1.0))
                    : 0.0;

                if (name.isEmpty) {
                  setState(() => error = 'اسم المحفظة مطلوب');
                  return;
                }
                if (phone.isEmpty) {
                  setState(() => error = 'رقم المحفظة مطلوب');
                  return;
                }
                if (daily <= 0) {
                  setState(() => error = 'الحد اليومي يجب أن يكون أكبر من صفر');
                  return;
                }
                if (monthly <= 0) {
                  setState(() => error = 'الحد الشهري يجب أن يكون أكبر من صفر');
                  return;
                }
                if (monthly < daily) {
                  setState(
                    () => error =
                        'الحد الشهري يجب أن يكون أكبر من أو يساوي الحد اليومي',
                  );
                  return;
                }
                if (lowBal < 0) {
                  setState(
                    () => error = 'حد تنبيه الرصيد لا يمكن أن يكون سالبًا',
                  );
                  return;
                }
                if (openingBalance < 0) {
                  setState(
                    () => error = 'رصيد أول المدة لا يمكن أن يكون سالبًا',
                  );
                  return;
                }

                Navigator.of(ctx).pop(
                  _WalletFormData(
                    name: name,
                    phone: phone,
                    openingBalance: openingBalance,
                    dailyLimit: daily,
                    monthlyLimit: monthly,
                    lowBalanceThreshold: lowBal,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addWallet() async {
    final data = await _walletDialog(title: 'إضافة محفظة');
    if (data == null) return;

    try {
      await CleanWriteGateway.appDbBridge().execute(
        WalletAdjustmentIntent(
          adjustmentType: WalletAdjustmentType.createWallet,
          name: data.name,
          phone: data.phone,
          openingBalance: data.openingBalance,
          dailyLimit: data.dailyLimit,
          monthlyLimit: data.monthlyLimit,
          lowBalanceThreshold: data.lowBalanceThreshold,
          allowNegative: false,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت إضافة المحفظة بنجاح')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الإضافة: $e')));
    }
  }

  Future<void> _editWallet(Wallet w) async {
    final data = await _walletDialog(title: 'تعديل محفظة', wallet: w);
    if (data == null) return;

    try {
      await CleanWriteGateway.appDbBridge().execute(
        WalletAdjustmentIntent(
          adjustmentType: WalletAdjustmentType.updateWallet,
          walletId: w.id,
          name: data.name,
          phone: data.phone,
          dailyLimit: data.dailyLimit,
          monthlyLimit: data.monthlyLimit,
          lowBalanceThreshold: data.lowBalanceThreshold,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تعديل المحفظة بنجاح')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التعديل: $e')));
    }
  }

  Future<void> _resetUsage({
    required Wallet wallet,
    required bool monthly,
  }) async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا الإجراء متاح للأدمن فقط')),
      );
      return;
    }

    final scopeText = monthly ? 'الشهري' : 'اليومي';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد التصفير'),
        content: Text(
          'هل تريد تصفير استهلاك الحد $scopeText للمحفظة "${wallet.name}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await CleanWriteGateway.appDbBridge().execute(
        WalletAdjustmentIntent(
          adjustmentType: monthly
              ? WalletAdjustmentType.resetMonthlyUsage
              : WalletAdjustmentType.resetDailyUsage,
          walletId: wallet.id,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تصفير الاستهلاك $scopeText بنجاح')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التصفير: $e')));
    }
  }

  Future<void> _resetAllUsage({required bool monthly}) async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا الإجراء متاح للأدمن فقط')),
      );
      return;
    }
    final scopeText = monthly ? 'الشهري' : 'اليومي';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد التصفير الجماعي'),
        content: Text('هل تريد تصفير استهلاك الحد $scopeText لكل المحافظ؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await CleanWriteGateway.appDbBridge().execute(
        WalletAdjustmentIntent(
          adjustmentType: monthly
              ? WalletAdjustmentType.resetAllMonthlyUsage
              : WalletAdjustmentType.resetAllDailyUsage,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التصفير الجماعي $scopeText بنجاح')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التصفير الجماعي: $e')));
    }
  }

  Future<void> _showMiniStatement(BuildContext context, int walletId, String walletName) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return FutureBuilder(
          future: AppDb.instance.listTxns(), // Needs optimizing for large DB, but fine for now
          builder: (ctx, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            final txns = snapshot.data as List<Txn>;
            final walletTxns = txns.where((t) => t.walletFromId == walletId || t.walletToId == walletId).toList();
            walletTxns.sort((a, b) => b.entryDate.compareTo(a.entryDate));
            final latest = walletTxns.take(5).toList();

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('أحدث العمليات: $walletName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (latest.isEmpty) const Text('لا توجد عمليات مسجلة.'),
                  ...latest.map((t) {
                    final isOut = t.walletFromId == walletId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isOut ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                        child: Icon(
                          isOut ? Icons.arrow_upward : Icons.arrow_downward,
                          color: isOut ? Colors.red : Colors.green,
                        ),
                      ),
                      title: Text(t.party ?? (isOut ? 'سحب/صرف' : 'إيداع/تمويل')),
                      subtitle: Text('${t.entryDate.year}-${t.entryDate.month}-${t.entryDate.day}'),
                      trailing: Text(
                        '${isOut ? "-" : "+"}${t.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isOut ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _reconcileWallet(Wallet w) async {
    if (!AppSession.isAdmin) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عفوا، أنت لست أدمن')));
      return;
    }
    final actBalance = _actualBalances[w.id] ?? 0.0;
    final ctrl = TextEditingController(text: actBalance.toStringAsFixed(2));
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('مطابقة رصيد: ${w.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الرصيد الفعلي الحالي في التطبيق: $actBalance'),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'الرصيد الفعلي في خط الموبايل',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حفظ وتسوية'),
          ),
        ],
      ),
    );

    if (res == true) {
      final actual = double.tryParse(ctrl.text);
      if (actual != null && actual != actBalance) {
        setState(() { _loading = true; });
        try {
          await AppDb.instance.reconcileWalletBalance(
            walletId: w.id,
            actualBalance: actual,
          );
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت تسوية الرصيد بنجاح')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        } finally {
          _load();
        }
      }
    }
  }

  Widget _buildLiquidityChart() {
    double totalWallets = _actualBalances.values.fold(0.0, (a, b) => a + b);
    if (totalWallets <= 0) return const SizedBox.shrink();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('توزيع السيولة النقدية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: _wallets.map((w) {
                  final bal = _actualBalances[w.id] ?? 0.0;
                  if (bal <= 0) return const SizedBox.shrink();
                  return Expanded(
                    flex: (bal).toInt(),
                    child: Tooltip(
                      message: '${w.name}: ${bal.toStringAsFixed(0)}',
                      child: Container(
                        height: 20,
                        color: Colors.primaries[w.id % Colors.primaries.length],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _wallets.map((w) {
                final bal = _actualBalances[w.id] ?? 0.0;
                if (bal <= 0) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: Colors.primaries[w.id % Colors.primaries.length]),
                    const SizedBox(width: 4),
                    Text('${w.name} (${((bal/totalWallets)*100).toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'المحافظ'),
        actions: [
          IconButton(
            tooltip: 'تمويل محفظة',
            icon: const Icon(Icons.add_card),
            onPressed: _loading
                ? null
                : () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const WalletFundingScreen(),
                      ),
                    );
                    if (changed == true) _load();
                  },
          ),
          IconButton(
            tooltip: 'إضافة محفظة',
            icon: const Icon(Icons.add),
            onPressed: _loading ? null : _addWallet,
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'تصفير استهلاك الحدود',
            onSelected: (value) async {
              if (value == 'reset_all_daily') {
                await _resetAllUsage(monthly: false);
              } else if (value == 'reset_all_monthly') {
                await _resetAllUsage(monthly: true);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'reset_all_daily',
                child: Text('تصفير يومي لكل المحافظ'),
              ),
              PopupMenuItem(
                value: 'reset_all_monthly',
                child: Text('تصفير شهري لكل المحافظ'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (!_loading && _wallets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildLiquidityChart(),
              ),
            _WalletSummaryCardPresentation(
              loading: _loading,
              errorText: _error,
              totalText: _total.toStringAsFixed(2),
              totalActualText: _totalActual.toStringAsFixed(2),
              totalPendingImpactText:
                  '${_totalPendingImpact >= 0 ? '+' : '-'}${_totalPendingImpact.abs().toStringAsFixed(2)}',
              walletCountText: _wallets.length.toString(),
              onRetry: _load,
            ),
            const SizedBox(height: 10),
            if (!_loading && _error == null && _wallets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('لا توجد محافظ')),
              )
            else
              ..._wallets.map((w) {
                final bal = _balances[w.id] ?? 0.0;
                final actual = _actualBalances[w.id] ?? 0.0;
                final pendingImpact = bal - actual;
                final usage = _limitUsage[w.id];
                final provider = providerFromPhone(w.phone);
                final providerName = providerDisplayName(provider);
                final color = _providerColor(provider);
                final double dLimit = usage?.dailyLimit ?? w.dailyLimit;
                final double mLimit = usage?.monthlyLimit ?? w.monthlyLimit;
                final double dUsed = usage?.dailyUsed ?? 0.0;
                final double mUsed = usage?.monthlyUsed ?? 0.0;
                final double dRatio = dLimit > 0 ? (dUsed / dLimit).clamp(0.0, 1.0) : 0.0;
                final double mRatio = mLimit > 0 ? (mUsed / mLimit).clamp(0.0, 1.0) : 0.0;

                return _WalletCardPresentation(
                  walletName: w.name,
                  providerName: providerName,
                  phoneText: w.phone.isEmpty ? 'غير محدد' : w.phone,
                  availableText: bal.toStringAsFixed(2),
                  actualText: actual.toStringAsFixed(2),
                  pendingImpactText:
                      '${pendingImpact >= 0 ? '+' : '-'}${pendingImpact.abs().toStringAsFixed(2)}',
                  dailyUsageText: '${dUsed.toStringAsFixed(0)} / ${dLimit.toStringAsFixed(0)}',
                  monthlyUsageText: '${mUsed.toStringAsFixed(0)} / ${mLimit.toStringAsFixed(0)}',
                  dailyUsageRatio: dRatio,
                  monthlyUsageRatio: mRatio,
                  color: color,
                  onTap: () => _editWallet(w),
                  onLongPress: () => _showMiniStatement(context, w.id, w.name),
                  onMenuSelected: (value) async {
                    if (value == 'view_ledger') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WalletLedgerScreen(wallet: w),
                        ),
                      );
                    } else if (value == 'reset_daily') {
                      await _resetUsage(wallet: w, monthly: false);
                    } else if (value == 'reset_monthly') {
                      await _resetUsage(wallet: w, monthly: true);
                    } else if (value == 'reconcile') {
                      await _reconcileWallet(w);
                    }
                  },
                );
              }),
            const SizedBox(height: 8),
            if (!_loading && _error == null)
              Text(
                'المتاح يشمل العمليات المعلقة، بينما الفعلي يشمل المعتمد فقط.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _addWallet,
        child: const Icon(Icons.add),
      ),
    );
  }
}

Widget _pill(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}

class _WalletSummaryCardPresentation extends StatelessWidget {
  final bool loading;
  final String? errorText;
  final String totalText;
  final String totalActualText;
  final String totalPendingImpactText;
  final String walletCountText;
  final VoidCallback onRetry;

  const _WalletSummaryCardPresentation({
    required this.loading,
    required this.errorText,
    required this.totalText,
    required this.totalActualText,
    required this.totalPendingImpactText,
    required this.walletCountText,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: loading
            ? const Text('جارٍ التحميل...')
            : errorText != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حدث خطأ أثناء التحميل'),
                  const SizedBox(height: 8),
                  Text(errorText!),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إجمالي أرصدة المحافظ المتاحة: $totalText',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'إجمالي فعلي (معتمد): $totalActualText',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تأثير المعلق على المحافظ: $totalPendingImpactText',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'عدد المحافظ: $walletCountText',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );
  }
}

class _WalletFormData {
  final String name;
  final String phone;
  final double openingBalance;
  final double dailyLimit;
  final double monthlyLimit;
  final double lowBalanceThreshold;

  const _WalletFormData({
    required this.name,
    required this.phone,
    required this.openingBalance,
    required this.dailyLimit,
    required this.monthlyLimit,
    required this.lowBalanceThreshold,
  });
}

class _WalletCardPresentation extends StatelessWidget {
  final String walletName;
  final String providerName;
  final String phoneText;
  final String availableText;
  final String actualText;
  final String pendingImpactText;
  final String dailyUsageText;
  final String monthlyUsageText;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<String> onMenuSelected;

  const _WalletCardPresentation({
    required this.walletName,
    required this.providerName,
    required this.phoneText,
    required this.availableText,
    required this.actualText,
    required this.pendingImpactText,
    required this.dailyUsageText,
    required this.monthlyUsageText,
    required this.color,
    required this.onTap,
    this.onLongPress,
    required this.onMenuSelected,
    this.dailyUsageRatio = 0.0,
    this.monthlyUsageRatio = 0.0,
  });

  final double dailyUsageRatio;
  final double monthlyUsageRatio;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.92),
              color.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    walletName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    providerName,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: onMenuSelected,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'view_ledger',
                      child: Text('كشف الحساب'),
                    ),
                    PopupMenuItem(
                      value: 'reset_daily',
                      child: Text('تصفير استهلاك اليوم'),
                    ),
                    PopupMenuItem(
                      value: 'reset_monthly',
                      child: Text('تصفير استهلاك الشهر'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'المتاح: $availableText',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'الفعلي (معتمد): $actualText',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 4),
            Text(
              'تأثير المعلق: $pendingImpactText',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 8),
            Text(
              'رقم المحفظة: $phoneText',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 10),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _pill('اليومي: $dailyUsageText'),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: dailyUsageRatio,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          color: _getProgressColor(dailyUsageRatio),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _pill('الشهري: $monthlyUsageText'),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: monthlyUsageRatio,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          color: _getProgressColor(monthlyUsageRatio),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white24, height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => onMenuSelected('reconcile'),
                  icon: const Icon(Icons.balance, color: Colors.white, size: 16),
                  label: const Text('مطابقة', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                TextButton.icon(
                  onPressed: () => onMenuSelected('view_ledger'),
                  icon: const Icon(Icons.list_alt, color: Colors.white, size: 16),
                  label: const Text('سجل', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                TextButton.icon(
                  onPressed: () => onMenuSelected('reset_daily'),
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                  label: const Text('تصفير', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getProgressColor(double ratio) {
    if (ratio >= 0.9) return Colors.redAccent;
    if (ratio >= 0.75) return Colors.orangeAccent;
    return Colors.greenAccent;
  }
}
