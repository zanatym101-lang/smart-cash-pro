// Dashboard: KPIs + navigation (admin-aware)
import 'package:flutter/material.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/license_info.dart';
import '../models/quick_action_item.dart';

import '../widgets/app_title.dart';
import 'wallets_screen.dart';
import 'treasury_screen.dart';
import 'transfer_screen.dart';
import 'receive_screen.dart';
import 'pending_screen.dart';
import 'wallet_funding_screen.dart';
import 'ledger_screen.dart';
import 'expenses_screen.dart';
import 'admin_settings_screen.dart';
import 'claims_screen.dart';
import 'fawry_screen.dart';
import 'reports_screen.dart';
import 'help_screen.dart';
import 'quick_actions_order_screen.dart';
import 'customers_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TreasurySnapshot? _snap;
  LicenseInfo? _license;
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;
  _DashboardFocus _focus = _DashboardFocus.treasury;
  List<String> _actionOrder = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        AppDb.instance.getTreasurySnapshot(),
        AppDb.instance.getLicenseInfo(),
        AppDb.instance.getQuickActionsOrder(),
      ]);
      final s = results[0] as TreasurySnapshot;
      final license = results[1] as LicenseInfo;
      final order = (results[2] as List).map((e) => e.toString()).toList();
      if (!mounted) return;
      setState(() {
        _snap = s;
        _license = license;
        _actionOrder = order;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    String? hint,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  if (hint != null) ...[
                    const SizedBox(height: 6),
                    Text(hint, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard({
    required TreasurySnapshot snap,
    required bool isAdmin,
    LicenseInfo? license,
  }) {
    final total = snap.drawerBalance + snap.walletsTotal;
    final totalActual = snap.drawerActualBalance + snap.walletsActualTotal;
    final isTrial = license != null && !license.isActivated;
    final trialDaysLeft = license?.daysLeft ?? 0;
    final focusPending = _focus == _DashboardFocus.pending;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _miniIcon(Icons.analytics_outlined),
              const SizedBox(width: 8),
              _miniIcon(Icons.edit_outlined),
              const SizedBox(width: 8),
              _miniIcon(Icons.calculate_outlined, active: true),
              const Spacer(),
              SegmentedButton<_DashboardFocus>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return Colors.white.withValues(alpha: 0.12);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFF0F172A);
                    }
                    return Colors.white70;
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: _DashboardFocus.treasury,
                    label: Text('الخزنة'),
                  ),
                  ButtonSegment(
                    value: _DashboardFocus.pending,
                    label: Text('المعلّق'),
                  ),
                ],
                selected: {_focus},
                onSelectionChanged: (v) {
                  setState(() => _focus = v.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            focusPending ? 'العمليات المعلّقة' : 'إجمالي السيولة المتاحة',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            focusPending ? '${snap.pendingCount}' : total.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (!focusPending) ...[
            _darkRow('الخزنة (كاش) - متاح', snap.drawerBalance),
            _darkRow('المحافظ - متاح', snap.walletsTotal),
            const SizedBox(height: 6),
            _darkRow('إجمالي فعلي (معتمد)', totalActual),
            const SizedBox(height: 6),
            _darkRow('ربح اليوم', snap.dailyProfit),
          ] else ...[
            Text(
              'الأثر محسوب في المتاح حتى قبل الاعتماد',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (isAdmin)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                      _load();
                    },
                    child: const Text('عرض التقارير'),
                  ),
                ),
              if (isAdmin) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LedgerScreen()),
                    );
                    _load();
                  },
                  child: const Text('سجل العمليات'),
                ),
              ),
            ],
          ),
          if (isTrial) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'تجريبي • متبقي $trialDaysLeft يوم',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniIcon(IconData icon, {bool active = false}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: active ? const Color(0xFF0F172A) : Colors.white70,
        size: 18,
      ),
    );
  }

  Widget _darkRow(String label, double value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, {String? hint, Widget? action}) {
    final trailing =
        action ??
        (hint == null
            ? null
            : Text(hint, style: Theme.of(context).textTheme.bodySmall));
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...?(trailing == null ? null : [trailing]),
        ],
      ),
    );
  }

  List<QuickActionItem> _applyOrder(
    List<QuickActionItem> items,
    List<String> order,
  ) {
    if (order.isEmpty) return items;
    final byId = {for (final i in items) i.id: i};
    final sorted = <QuickActionItem>[];
    for (final id in order) {
      final item = byId.remove(id);
      if (item != null) sorted.add(item);
    }
    sorted.addAll(byId.values);
    return sorted;
  }

  Future<void> _openReorder(bool isAdmin) async {
    final visible = _actions(isAdmin);
    final order = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) =>
            QuickActionsOrderScreen(items: List<QuickActionItem>.from(visible)),
      ),
    );
    if (order == null) return;
    await AppDb.instance.setQuickActionsOrder(order);
    await _load();
  }

  Widget _actionGrid(List<QuickActionItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int cross = 2;
        if (width >= 900) {
          cross = 4;
        } else if (width >= 600) {
          cross = 3;
        } else if (width >= 360) {
          cross = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: width < 360 ? 1.2 : 1.05,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _ActionTile(item: items[i]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    final isAdmin = AppSession.isAdmin;
    final license = _license;

    return Scaffold(
      appBar: AppBar(
        title: AppTitle(
          subtitle: isAdmin ? 'لوحة التحكم (أدمن)' : 'لوحة التحكم',
        ),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'إعدادات الأدمن',
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminSettingsScreen(),
                  ),
                );
              },
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
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
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
                  ),
                ),
              )
            else if (s != null) ...[
              _heroCard(snap: s, isAdmin: isAdmin, license: license),
              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'آخر تحديث: ${_lastUpdated!.toLocal()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),

              _sectionTitle(
                'الإجراءات السريعة',
                action: TextButton.icon(
                  onPressed: () => _openReorder(isAdmin),
                  icon: const Icon(Icons.tune),
                  label: const Text('ترتيب'),
                ),
              ),
              _actionGrid(_applyOrder(_actions(isAdmin), _actionOrder)),

              _sectionTitle('ملخصات سريعة'),
              _kpiCard(
                title: 'إجمالي الخزنة (متاح)',
                value: (s.drawerBalance + s.walletsTotal).toStringAsFixed(2),
                icon: Icons.summarize,
                hint:
                    'الفعلي: ${(s.drawerActualBalance + s.walletsActualTotal).toStringAsFixed(2)}',
              ),
              _kpiCard(
                title: 'ربح الشهر',
                value: s.monthlyProfit.toStringAsFixed(2),
                icon: Icons.calendar_month,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<QuickActionItem> _actions(bool isAdmin) {
    final items = <QuickActionItem>[
      QuickActionItem(
        id: 'help',
        title: 'شرح البرنامج',
        icon: Icons.help_outline,
        color: const Color(0xFF06B6D4),
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HelpScreen()));
        },
      ),
      QuickActionItem(
        id: 'transfer',
        title: isAdmin ? 'تحويل' : 'تحويل (معلّق)',
        icon: Icons.swap_horiz,
        color: const Color(0xFF14B8A6),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TransferScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'receive',
        title: isAdmin ? 'استلام' : 'استلام (معلّق)',
        icon: Icons.call_received,
        color: const Color(0xFF1D4ED8),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ReceiveScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'fawry',
        title: 'خدمات فوري',
        icon: Icons.flash_on,
        color: const Color(0xFFF97316),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const FawryScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'wallets',
        title: 'المحافظ',
        icon: Icons.account_balance_wallet,
        color: const Color(0xFF64748B),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const WalletsScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'customers',
        title: 'العملاء',
        icon: Icons.people_alt_outlined,
        color: const Color(0xFF0891B2),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CustomersScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'treasury',
        title: 'الخزنة',
        icon: Icons.account_balance,
        color: const Color(0xFF0F172A),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TreasuryScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'pending',
        title: 'المعلّق',
        icon: Icons.pending_actions,
        color: const Color(0xFF0EA5E9),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PendingScreen()));
          _load();
        },
      ),
    ];

    if (isAdmin) {
      items.addAll([
        QuickActionItem(
          id: 'reports',
          title: 'التقارير',
          icon: Icons.analytics,
          color: const Color(0xFF10B981),
          onTap: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
            _load();
          },
        ),
        QuickActionItem(
          id: 'expenses',
          title: 'المصروفات',
          icon: Icons.money_off_csred,
          color: const Color(0xFFEF4444),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const ExpensesScreen()),
            );
            if (changed == true) _load();
          },
        ),
        QuickActionItem(
          id: 'claims',
          title: 'مستحقات',
          icon: Icons.request_quote,
          color: const Color(0xFF8B5CF6),
          onTap: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ClaimsScreen()));
            _load();
          },
        ),
        QuickActionItem(
          id: 'wallet_funding',
          title: 'تمويل محفظة',
          icon: Icons.add_card,
          color: const Color(0xFF0F766E),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const WalletFundingScreen()),
            );
            if (changed == true) _load();
          },
        ),
      ]);
    }

    return items;
  }
}

enum _DashboardFocus { treasury, pending }

class _ActionTile extends StatelessWidget {
  final QuickActionItem item;

  const _ActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              item.color.withValues(alpha: 0.18),
              item.color.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const Spacer(),
            Text(
              item.title,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
