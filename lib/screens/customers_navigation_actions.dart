part of 'customers_screen.dart';

extension _CustomersNavigationActions on _CustomersScreenState {
  Future<void> _openCustomer(_CustomerBucket c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CustomerSheet(
        customer: c,
        onTransfer: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  TransferScreen(initialParty: c.name, initialPhone: c.phone),
            ),
          );
          _load();
        },
        onReceive: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  ReceiveScreen(initialParty: c.name, initialPhone: c.phone),
            ),
          );
          _load();
        },
        onTransferPending: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => TransferScreen(
                initialParty: c.name,
                initialPhone: c.phone,
                forcePendingDefault: true,
              ),
            ),
          );
          _load();
        },
        onReceivePending: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => ReceiveScreen(
                initialParty: c.name,
                initialPhone: c.phone,
                forcePendingDefault: true,
              ),
            ),
          );
          _load();
        },
        onFawryCredit: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => FawryScreen(
                initialParty: c.name,
                initialPhone: c.phone,
                startCredit: true,
              ),
            ),
          );
          _load();
        },
        onFawryCash: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => FawryScreen(
                initialParty: c.name,
                initialPhone: c.phone,
                startCredit: false,
              ),
            ),
          );
          _load();
        },
        onReport: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => CustomerReportScreen(
                customerName: c.name,
                customerPhone: c.phone,
              ),
            ),
          );
          _load();
        },
        onLineAction: _handleLineAction,
        onShowDetails: _showLineDetails,
        busyIds: _busyIds,
        onRefresh: _load,
      ),
    );
  }

  String? _txnStatusLabel(String? status) {
    if (status == null) return null;
    final trimmed = status.trim();
    if (trimmed.isEmpty) return null;
    switch (trimmed) {
      case 'posted':
        return 'معتمد';
      case 'pending':
        return 'آجل';
      case 'rolled_back':
        return 'ملغي';
      default:
        return trimmed;
    }
  }

  void _showLineDetails(_CustomerLine line) {
    final d = line.date;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final sideLabel = line.side == _LineSide.receivable
        ? 'عليه (تحصيل)'
        : 'له (سداد)';
    final statusLabel = _txnStatusLabel(line.txnStatus);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل العملية'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('العنوان: ${line.title}'),
              Text('التاريخ: $date'),
              Text('النوع: $sideLabel'),
              Text('المبلغ: ${line.amount.toStringAsFixed(2)}'),
              Text('المرجع: ${line.ref}'),
              if (statusLabel != null) Text('الحالة: $statusLabel'),
              if (line.details != null && line.details!.trim().isNotEmpty)
                Text('التفاصيل: ${line.details}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
