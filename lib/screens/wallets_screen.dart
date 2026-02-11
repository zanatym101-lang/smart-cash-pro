import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../models/wallet.dart';
import '../utils/phone_provider.dart';
import '../widgets/app_title.dart';
import 'wallet_funding_screen.dart';

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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total => _balances.values.fold(0.0, (a, b) => a + b);

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
    final openingBalanceCtrl = TextEditingController(text: '0');

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
                    'المزوّد: ${providerFromPhone(normalizePhone(phoneCtrl.text))}',
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
                final openingBalance = wallet == null
                    ? (double.tryParse(openingBalanceCtrl.text.trim()) ?? -1.0)
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
                    () => error = 'حد تنبيه الرصيد لا يمكن أن يكون سالب',
                  );
                  return;
                }
                if (openingBalance < 0) {
                  setState(() => error = 'رصيد أول المدة لا يمكن أن يكون سالب');
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
      await AppDb.instance.addWallet(
        name: data.name,
        phone: data.phone,
        openingBalance: data.openingBalance,
        dailyLimit: data.dailyLimit,
        monthlyLimit: data.monthlyLimit,
        lowBalanceThreshold: data.lowBalanceThreshold,
        allowNegative: false,
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
      await AppDb.instance.updateWallet(
        walletId: w.id,
        name: data.name,
        phone: data.phone,
        dailyLimit: data.dailyLimit,
        monthlyLimit: data.monthlyLimit,
        lowBalanceThreshold: data.lowBalanceThreshold,
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Text('جاري التحميل...')
                    : _error != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('حدث خطأ أثناء التحميل'),
                          const SizedBox(height: 8),
                          Text(_error!),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إجمالي أرصدة المحافظ: ${_total.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'عدد المحافظ: ${_wallets.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
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
                final provider = providerFromPhone(w.phone);
                final color = _providerColor(provider);
                return InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => _editWallet(w),
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
                                w.name,
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
                                provider,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'المتاح: ${bal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الفعلي (معتمد): ${actual.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'رقم: ${w.phone.isEmpty ? 'غير محدد' : w.phone}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            _pill(
                              'حد يومي: ${w.dailyLimit.toStringAsFixed(0)}',
                            ),
                            _pill(
                              'حد شهري: ${w.monthlyLimit.toStringAsFixed(0)}',
                            ),
                            if (w.lowBalanceThreshold > 0)
                              _pill(
                                'تنبيه رصيد: ${w.lowBalanceThreshold.toStringAsFixed(0)}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            if (!_loading && _error == null)
              Text(
                'ملاحظة: المتاح يشمل العمليات المعلّقة، والفعلي يشمل المعتمد فقط.',
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
