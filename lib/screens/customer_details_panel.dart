part of 'customers_screen.dart';

class _CustomerSheet extends StatefulWidget {
  final _CustomerBucket customer;
  final VoidCallback onTransfer;
  final VoidCallback onReceive;
  final VoidCallback onTransferPending;
  final VoidCallback onReceivePending;
  final VoidCallback onFawryCash;
  final VoidCallback onFawryCredit;
  final VoidCallback onReport;
  final Future<void> Function(_CustomerLine line, _LineAction action)
  onLineAction;
  final void Function(_CustomerLine line) onShowDetails;
  final Set<int> busyIds;
  final Future<void> Function() onRefresh;

  const _CustomerSheet({
    required this.customer,
    required this.onTransfer,
    required this.onReceive,
    required this.onTransferPending,
    required this.onReceivePending,
    required this.onFawryCash,
    required this.onFawryCredit,
    required this.onReport,
    required this.onLineAction,
    required this.onShowDetails,
    required this.busyIds,
    required this.onRefresh,
  });

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

enum _CustomerLineFilter { all, claims, settlements, pending, posted }

class _SettlementAmountInput {
  final double amount;
  final String? note;

  const _SettlementAmountInput({required this.amount, required this.note});
}

class _CustomerSheetState extends State<_CustomerSheet> {
  _CustomerLineFilter _filter = _CustomerLineFilter.all;
  bool _showActions = false;
  bool _batchBusy = false;

  _CustomerBucket get customer => widget.customer;
  VoidCallback get onTransfer => widget.onTransfer;
  VoidCallback get onReceive => widget.onReceive;
  VoidCallback get onTransferPending => widget.onTransferPending;
  VoidCallback get onReceivePending => widget.onReceivePending;
  VoidCallback get onFawryCash => widget.onFawryCash;
  VoidCallback get onFawryCredit => widget.onFawryCredit;
  VoidCallback get onReport => widget.onReport;
  Future<void> Function(_CustomerLine line, _LineAction action)
  get onLineAction => widget.onLineAction;
  void Function(_CustomerLine line) get onShowDetails => widget.onShowDetails;
  Set<int> get busyIds => widget.busyIds;
  Future<void> Function() get onRefresh => widget.onRefresh;

  String? _extractServiceLine(String? details) {
    if (details == null) return null;
    final lines = details
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final l in lines) {
      if (l.startsWith('خدمة:')) return l;
    }
    return null;
  }

  String? _extractSettlementNote(String? details) {
    if (details == null) return null;
    final m = RegExp(r'ملاحظة التسوية:\s*(.+)$').firstMatch(details.trim());
    if (m == null) return null;
    final note = (m.group(1) ?? '').trim();
    return note.isEmpty ? null : note;
  }

  String _normalizePhone(String raw) {
    final buf = StringBuffer();
    for (final r in raw.runes) {
      final ch = String.fromCharCode(r);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  String? _extractPhone(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final matches = RegExp(r'\d{10,15}').allMatches(text);
    if (matches.isEmpty) return null;
    final phone = _normalizePhone(matches.first.group(0) ?? '');
    return phone.isEmpty ? null : phone;
  }

  String _customerKey() {
    final phone = _normalizePhone(customer.phone ?? '');
    if (phone.isNotEmpty) return 'p:$phone';
    return 'n:${customer.name.trim().toLowerCase()}';
  }

  String _formatLineDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _openAttachments() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CustomerAttachmentsSheet(
        customer: customer,
        customerKey: _customerKey(),
      ),
    );
  }

  List<_CustomerLine> _openSettlementLinesOfType(String type) {
    final expectedSide = type == 'receivable'
        ? _LineSide.receivable
        : _LineSide.payable;
    final lines = customer.lines.where((l) {
      if (l.effectiveDisplayAmount <= 0) return false;
      if (l.lineType == _CustomerLineType.claimOpen && l.claimType == type) {
        return true;
      }
      if (l.lineType != _CustomerLineType.txn || l.txnStatus != 'pending') {
        return false;
      }
      if (l.side != expectedSide) return false;
      return l.txnKind == 'transfer' ||
          l.txnKind == 'receive' ||
          l.txnKind == 'fawry_credit';
    }).toList();
    lines.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      final aId = a.claimId ?? a.txnId ?? 0;
      final bId = b.claimId ?? b.txnId ?? 0;
      return aId.compareTo(bId);
    });
    return lines;
  }

  Future<Map<int, double>> _openClaimRemainingById() async {
    final claims = await AppDb.instance.listClaims(status: 'open');
    return {for (final c in claims) c.id: c.amount};
  }

  double _remainingForSettlementLine(
    _CustomerLine line,
    Map<int, double> claimRemainingById,
  ) {
    final claimId = line.claimId;
    if (claimId != null && line.lineType == _CustomerLineType.claimOpen) {
      return claimRemainingById[claimId] ?? 0;
    }
    if (line.txnId != null &&
        line.lineType == _CustomerLineType.txn &&
        line.txnStatus == 'pending') {
      return line.effectiveDisplayAmount;
    }
    return 0;
  }

  Future<void> _settleOpenSettlementLine(
    _CustomerLine line, {
    required double amount,
    String? note,
  }) async {
    final claimId = line.claimId;
    if (claimId != null && line.lineType == _CustomerLineType.claimOpen) {
      await AppDb.instance.settleClaim(
        claimId: claimId,
        amount: amount,
        note: note,
      );
      return;
    }

    final txnId = line.txnId;
    if (txnId != null &&
        line.lineType == _CustomerLineType.txn &&
        line.txnStatus == 'pending') {
      await AppDb.instance.addPendingSettlementForTxn(
        pendingTxnId: txnId,
        amount: amount,
        note: note,
      );
      return;
    }

    throw Exception('لا يمكن تسوية هذا السطر.');
  }

  List<_CustomerLine> _openDeferredLinesOfSide(_LineSide side) {
    final lines = customer.lines.where((l) {
      if (l.lineType != _CustomerLineType.txn || l.txnStatus != 'pending') {
        return false;
      }
      if (l.side != side || l.effectiveDisplayAmount <= 0) return false;
      if (side == _LineSide.receivable) {
        return l.txnKind == 'transfer' || l.txnKind == 'fawry_credit';
      }
      return l.txnKind == 'receive';
    }).toList();
    lines.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      return (a.txnId ?? 0).compareTo(b.txnId ?? 0);
    });
    return lines;
  }

  Future<void> _settleOppositeDeferred() async {
    final receivableLines = _openDeferredLinesOfSide(_LineSide.receivable);
    final payableLines = _openDeferredLinesOfSide(_LineSide.payable);
    if (receivableLines.isEmpty || payableLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد عمليات آجلة متقابلة للتسوية')),
      );
      return;
    }

    final receivableTotal = receivableLines.fold<double>(
      0,
      (sum, line) => sum + line.effectiveDisplayAmount,
    );
    final payableTotal = payableLines.fold<double>(
      0,
      (sum, line) => sum + line.effectiveDisplayAmount,
    );
    final settleTotal = receivableTotal < payableTotal
        ? receivableTotal
        : payableTotal;
    if (settleTotal <= 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسوية الآجل المتقابل'),
        content: Text(
          'سيتم عمل مقاصة بين الآجل له والآجل عليه لهذا العميل بقيمة ${settleTotal.toStringAsFixed(2)}.\n'
          'لن يتم تغيير المحافظ؛ سيتم فقط إنشاء سطور تسوية توضح المقاصة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تنفيذ التسوية'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) return;

    await _runBatch('تمت تسوية الآجل المتقابل بنجاح ✅', () async {
      var receiveIndex = 0;
      var payIndex = 0;
      var receivableRemaining =
          receivableLines[receiveIndex].effectiveDisplayAmount;
      var payableRemaining = payableLines[payIndex].effectiveDisplayAmount;
      var leftToSettle = settleTotal;

      while (leftToSettle > 0 &&
          receiveIndex < receivableLines.length &&
          payIndex < payableLines.length) {
        final takeA = receivableRemaining < payableRemaining
            ? receivableRemaining
            : payableRemaining;
        final take = takeA < leftToSettle ? takeA : leftToSettle;
        if (take <= 0) break;

        const note = 'تسوية آجل متقابل';
        await _settleOpenSettlementLine(
          receivableLines[receiveIndex],
          amount: take,
          note: note,
        );
        await _settleOpenSettlementLine(
          payableLines[payIndex],
          amount: take,
          note: note,
        );

        leftToSettle -= take;
        receivableRemaining -= take;
        payableRemaining -= take;

        if (receivableRemaining <= 0.0001) {
          receiveIndex++;
          if (receiveIndex < receivableLines.length) {
            receivableRemaining =
                receivableLines[receiveIndex].effectiveDisplayAmount;
          }
        }
        if (payableRemaining <= 0.0001) {
          payIndex++;
          if (payIndex < payableLines.length) {
            payableRemaining = payableLines[payIndex].effectiveDisplayAmount;
          }
        }
      }
    });
  }

  Future<String?> _pickSettlementType() async {
    final hasReceivable = _openSettlementLinesOfType('receivable').isNotEmpty;
    final hasPayable = _openSettlementLinesOfType('payable').isNotEmpty;
    if (!hasReceivable && !hasPayable) return null;
    if (hasReceivable && !hasPayable) return 'receivable';
    if (!hasReceivable && hasPayable) return 'payable';

    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_received),
              title: const Text('تسوية مبالغ مفتوحة لنا (تحصيل)'),
              onTap: () => Navigator.of(ctx).pop('receivable'),
            ),
            ListTile(
              leading: const Icon(Icons.call_made),
              title: const Text('تسوية مبالغ مفتوحة علينا (سداد)'),
              onTap: () => Navigator.of(ctx).pop('payable'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_SettlementAmountInput?> _promptTotalAmount({
    required String title,
    required String label,
    required double maxAmount,
  }) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;
    try {
      final result = await showDialog<_SettlementAmountInput>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الإجمالي المتاح: ${maxAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final value = double.tryParse(amountCtrl.text.trim());
                  if (value == null || value <= 0) {
                    setState(() => error = 'أدخل مبلغًا صحيحًا');
                    return;
                  }
                  if (value > maxAmount) {
                    setState(() => error = 'المبلغ أكبر من الإجمالي المتاح');
                    return;
                  }
                  final note = noteCtrl.text.trim();
                  Navigator.of(ctx).pop(
                    _SettlementAmountInput(
                      amount: value,
                      note: note.isEmpty ? null : note,
                    ),
                  );
                },
                child: const Text('تنفيذ'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return null;
      await WidgetsBinding.instance.endOfFrame;
      return result;
    } finally {
      amountCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _runBatch(
    String successMessage,
    Future<void> Function() action,
  ) async {
    if (_batchBusy) return;
    setState(() => _batchBusy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      await onRefresh();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _settleAllClaims() async {
    final type = await _pickSettlementType();
    if (type == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مبالغ مفتوحة للتسوية')),
      );
      return;
    }
    final lines = _openSettlementLinesOfType(type);
    if (lines.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مبالغ مفتوحة للتسوية')),
      );
      return;
    }
    if (!mounted) return;
    final label = type == 'receivable' ? 'تحصيل' : 'سداد';
    final remainingById = await _openClaimRemainingById();
    if (!mounted) return;
    final total = lines.fold<double>(
      0,
      (sum, line) => sum + _remainingForSettlementLine(line, remainingById),
    );
    if (total <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مبالغ متبقية للتسوية')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label كل المبالغ المفتوحة'),
        content: Text(
          'سيتم تنفيذ $label لعدد ${lines.length} بند مفتوح.\n'
          'الإجمالي المتبقي: ${total.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تنفيذ'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _runBatch('تمت تسوية كل المبالغ المفتوحة بنجاح ✅', () async {
      for (final line in lines) {
        final remaining = _remainingForSettlementLine(line, remainingById);
        if (remaining <= 0) continue;
        await _settleOpenSettlementLine(line, amount: remaining);
      }
    });
  }

  Future<void> _settlePartialFromTotal() async {
    final type = await _pickSettlementType();
    if (type == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مبالغ مفتوحة للتسوية')),
      );
      return;
    }
    final lines = _openSettlementLinesOfType(type);
    if (lines.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مبالغ مفتوحة للتسوية')),
      );
      return;
    }
    final remainingById = await _openClaimRemainingById();
    final total = lines.fold<double>(0, (sum, line) {
      return sum + _remainingForSettlementLine(line, remainingById);
    });
    if (total <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مبالغ متبقية للتسوية')),
      );
      return;
    }
    final actionLabel = type == 'receivable' ? 'تحصيل' : 'سداد';
    final result = await _promptTotalAmount(
      title: '$actionLabel جزئي من الإجمالي',
      label: 'مبلغ $actionLabel',
      maxAmount: total,
    );
    if (!mounted) return;
    if (result == null) return;

    await _runBatch('تم تنفيذ التسوية الجزئية بنجاح ✅', () async {
      var remainingAmount = result.amount;
      for (final line in lines) {
        if (remainingAmount <= 0) break;
        final claimRemaining = _remainingForSettlementLine(line, remainingById);
        if (claimRemaining <= 0) continue;
        final take = remainingAmount < claimRemaining
            ? remainingAmount
            : claimRemaining;
        if (take <= 0) continue;
        await _settleOpenSettlementLine(line, amount: take, note: result.note);
        remainingAmount -= take;
      }
    });
  }

  Future<void> _addClaimForCustomer(String type) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(
              type == 'receivable' ? 'إضافة مستحق لنا' : 'إضافة مستحق علينا',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('العميل: ${customer.name}'),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final value = double.tryParse(amountCtrl.text.trim());
                  if (value == null || value <= 0) {
                    setState(() => error = 'أدخل مبلغًا صحيحًا');
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
      final amount = double.parse(amountCtrl.text.trim());
      await _runBatch('تمت إضافة المستحق بنجاح ✅', () async {
        await AppDb.instance.addClaim(
          type: type,
          party: customer.name,
          amount: amount,
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          phone: customer.phone,
        );
      });
    } finally {
      amountCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _openAddOperationMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('تحويل'),
              onTap: () => Navigator.of(ctx).pop('transfer'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('تحويل آجل'),
              onTap: () => Navigator.of(ctx).pop('transfer_pending'),
            ),
            ListTile(
              leading: const Icon(Icons.call_received),
              title: const Text('استلام'),
              onTap: () => Navigator.of(ctx).pop('receive'),
            ),
            ListTile(
              leading: const Icon(Icons.call_received),
              title: const Text('استلام آجل'),
              onTap: () => Navigator.of(ctx).pop('receive_pending'),
            ),
            ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('فوري نقدي'),
              onTap: () => Navigator.of(ctx).pop('fawry_cash'),
            ),
            ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('فوري آجل'),
              onTap: () => Navigator.of(ctx).pop('fawry_credit'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('مستحق لنا'),
              onTap: () => Navigator.of(ctx).pop('claim_receivable'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('مستحق علينا'),
              onTap: () => Navigator.of(ctx).pop('claim_payable'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'transfer':
        onTransfer();
        return;
      case 'receive':
        onReceive();
        return;
      case 'transfer_pending':
        onTransferPending();
        return;
      case 'receive_pending':
        onReceivePending();
        return;
      case 'fawry_cash':
        onFawryCash();
        return;
      case 'fawry_credit':
        onFawryCredit();
        return;
      case 'claim_receivable':
        await _addClaimForCustomer('receivable');
        return;
      case 'claim_payable':
        await _addClaimForCustomer('payable');
        return;
      default:
        return;
    }
  }

  String? _buildSettlementDetails(_CustomerLine line) {
    final parts = <String>[];
    if (line.txnKind == 'claim_collect') {
      parts.add(
        line.sourceKindLabel?.trim().isNotEmpty == true
            ? 'تحصيل من ${line.sourceKindLabel}'
            : 'تحصيل من مستحق',
      );
    } else {
      parts.add(
        line.sourceKindLabel?.trim().isNotEmpty == true
            ? 'سداد إلى ${line.sourceKindLabel}'
            : 'سداد مستحق',
      );
    }
    if (line.remainingAfter != null && line.remainingAfter! > 0) {
      parts.add('متبقي ${line.remainingAfter!.toStringAsFixed(2)}');
    }
    final settlementNote = _extractSettlementNote(line.details);
    if (settlementNote != null && settlementNote.isNotEmpty) {
      parts.add(settlementNote);
    }
    return parts.join(' - ');
  }

  String? _firstReadablePart(String? raw) {
    if (raw == null) return null;
    final cleaned = _stripSystemTags(raw).trim();
    if (cleaned.isEmpty) return null;
    final parts = cleaned
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where(
          (e) =>
              !e.startsWith('مرجع العملية:') &&
              !e.startsWith('مرجع المستحق:') &&
              !e.startsWith('نوع الربط:'),
        )
        .toList();
    if (parts.isEmpty) return null;
    return parts.first;
  }

  String? _amountBreakdownForLine(_CustomerLine line) {
    final original = line.effectiveOriginalAmount;
    final remaining = line.effectiveDisplayAmount;
    final settled = line.effectiveSettledAmount;
    if (original <= 0) return null;
    return 'الأصل: ${original.toStringAsFixed(2)} | '
        'تم تسويته: ${settled.toStringAsFixed(2)} | '
        'المتبقي: ${remaining.toStringAsFixed(2)}';
  }

  String? _joinCompactParts(List<String?> parts) {
    final clean = parts
        .map((e) => (e ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (clean.isEmpty) return null;
    return clean.join(' | ');
  }

  String? _compactDetailsForLine(_CustomerLine line) {
    if (line.lineType == _CustomerLineType.claimOpen) {
      return _joinCompactParts([
        _amountBreakdownForLine(line),
        _firstReadablePart(line.details) ??
            (line.claimType == 'receivable'
                ? 'مستحق مفتوح عليه'
                : 'مستحق مفتوح له'),
      ]);
    }
    switch (line.txnKind) {
      case 'transfer':
        final parts = <String>[];
        if (line.txnStatus == 'pending') {
          final breakdown = _amountBreakdownForLine(line);
          if (breakdown != null) parts.add(breakdown);
        }
        final phone = _extractPhone(line.details);
        if (phone != null) parts.add('هاتف $phone');
        final note = _firstReadablePart(line.details);
        if (note != null &&
            !note.startsWith('المطلوب من العميل:') &&
            !note.startsWith('المحوّل للعميل:') &&
            !note.startsWith('عمولة العميل:')) {
          parts.add(note);
        }
        if (parts.isEmpty) parts.add('تحويل للعميل');
        return parts.isEmpty ? null : parts.join(' | ');
      case 'receive':
        final parts = <String>[];
        if (line.txnStatus == 'pending') {
          final breakdown = _amountBreakdownForLine(line);
          if (breakdown != null) parts.add(breakdown);
        }
        final phone = _extractPhone(line.details);
        if (phone != null) parts.add('هاتف $phone');
        final note = _firstReadablePart(line.details);
        if (note != null &&
            !note.startsWith('المبلغ المستلم:') &&
            !note.startsWith('العمولة/الربح:')) {
          parts.add(note);
        }
        if (parts.isEmpty) parts.add('استلام من العميل');
        return parts.isEmpty ? null : parts.join(' | ');
      case 'fawry_cash':
      case 'fawry_credit':
        if (line.txnStatus == 'pending') {
          return _joinCompactParts([
            _amountBreakdownForLine(line),
            () {
              final service = _extractServiceLine(line.details);
              if (service != null) {
                return service.replaceFirst('الخدمة:', '').trim();
              }
              return 'فوري آجل';
            }(),
          ]);
        }
        final service = _extractServiceLine(line.details);
        if (service != null) {
          return service.replaceFirst('الخدمة:', '').trim();
        }
        return line.txnKind == 'fawry_credit' ? 'فوري آجل' : 'فوري نقدي';
      case 'claim_collect':
      case 'claim_pay':
        return _buildSettlementDetails(line);
      default:
        return _firstReadablePart(line.details);
    }
  }

  Map<_CustomerLine, double> _computeBalances({
    required List<_CustomerLine> lines,
    required double currentNet,
  }) {
    final map = <_CustomerLine, double>{};
    var runningAfter = currentNet;
    for (final l in lines) {
      map[l] = runningAfter;
      final delta = l.side == _LineSide.receivable ? l.amount : -l.amount;
      runningAfter -= delta;
    }
    return map;
  }

  double _displayBalanceAmountForLine(
    _CustomerLine line,
    Map<_CustomerLine, double> balances,
    double currentNet,
  ) {
    return (balances[line] ?? currentNet).abs();
  }

  _LineSide _displayBalanceSideForLine(
    _CustomerLine line,
    Map<_CustomerLine, double> balances,
    double currentNet,
  ) {
    final runningBalance = balances[line] ?? currentNet;
    return runningBalance >= 0 ? _LineSide.receivable : _LineSide.payable;
  }

  List<_CustomerLine> _applyFilter(List<_CustomerLine> lines) {
    switch (_filter) {
      case _CustomerLineFilter.claims:
        return lines
            .where((l) => l.lineType == _CustomerLineType.claimOpen)
            .toList();
      case _CustomerLineFilter.settlements:
        return lines
            .where(
              (l) =>
                  l.lineType == _CustomerLineType.txn &&
                  (l.txnKind == 'claim_collect' || l.txnKind == 'claim_pay'),
            )
            .toList();
      case _CustomerLineFilter.pending:
        return lines
            .where(
              (l) =>
                  l.lineType == _CustomerLineType.txn &&
                  l.txnStatus == 'pending',
            )
            .toList();
      case _CustomerLineFilter.posted:
        return lines
            .where(
              (l) =>
                  l.lineType == _CustomerLineType.txn &&
                  l.txnStatus == 'posted',
            )
            .toList();
      case _CustomerLineFilter.all:
        return lines;
    }
  }

  Widget _filterChip(String label, _CustomerLineFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        if (!v) return;
        setState(() => _filter = value);
      },
    );
  }

  Widget _summaryPill({
    required String label,
    required double value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Color _sideFillColor(_LineSide side) {
    return side == _LineSide.receivable
        ? const Color(0xFFF28B82)
        : const Color(0xFF9FE29A);
  }

  Color _sideTextColor(_LineSide side) {
    return Colors.black87;
  }

  String _displayTitleForLine(_CustomerLine line) {
    if (line.lineType == _CustomerLineType.claimOpen) {
      return 'مستحق';
    }
    switch (line.txnKind) {
      case 'claim_collect':
        return 'تحصيل';
      case 'claim_pay':
        return 'سداد';
      case 'transfer':
        return line.txnStatus == 'pending' ? 'تحويل آجل' : 'تحويل';
      case 'receive':
        return line.txnStatus == 'pending' ? 'استلام آجل' : 'استلام';
      case 'fawry_cash':
        return 'فوري نقدي';
      case 'fawry_credit':
        return line.txnStatus == 'pending' ? 'فوري آجل' : 'فوري آجل';
      default:
        return line.title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final netLabel = customer.net >= 0 ? 'الصافي عليه' : 'الصافي له';
    final netValue = customer.net >= 0 ? customer.net : -customer.net;
    final netColor = customer.net >= 0
        ? const Color(0xFF047857)
        : const Color(0xFFB91C1C);
    final balances = _computeBalances(
      lines: customer.lines,
      currentNet: customer.net,
    );
    final visibleLines = _applyFilter(customer.lines);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  customer.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text('الهاتف: ${customer.phone ?? 'غير مسجل'}'),
          const SizedBox(height: 8),
          Row(
            children: [
              _summaryPill(
                label: 'له',
                value: customer.payableTotal,
                color: const Color(0xFF047857),
              ),
              const SizedBox(width: 6),
              _summaryPill(
                label: 'عليه',
                value: customer.receivableTotal,
                color: const Color(0xFFB91C1C),
              ),
              const SizedBox(width: 6),
              _summaryPill(label: netLabel, value: netValue, color: netColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'إجراءات سريعة',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _showActions = !_showActions),
                icon: Icon(
                  _showActions ? Icons.expand_less : Icons.expand_more,
                ),
                tooltip: _showActions ? 'إخفاء الإجراءات' : 'إظهار الإجراءات',
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _batchBusy ? null : _openAddOperationMenu,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('إضافة عملية'),
                ),
                ElevatedButton.icon(
                  onPressed: _batchBusy ? null : _settleAllClaims,
                  icon: const Icon(Icons.done_all),
                  label: const Text('تسوية كل المفتوح'),
                ),
                ElevatedButton.icon(
                  onPressed: _batchBusy ? null : _settlePartialFromTotal,
                  icon: const Icon(Icons.tune),
                  label: const Text('تسوية جزئية من الإجمالي'),
                ),
                ElevatedButton.icon(
                  onPressed: _batchBusy ? null : _settleOppositeDeferred,
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('تسوية الآجل المتقابل'),
                ),
                ElevatedButton.icon(
                  onPressed: onReport,
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('تقرير العميل'),
                ),
                ElevatedButton.icon(
                  onPressed: _openAttachments,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('مرفقات العميل'),
                ),
              ],
            ),
            crossFadeState: _showActions
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('الكل', _CustomerLineFilter.all),
              _filterChip('المستحقات', _CustomerLineFilter.claims),
              _filterChip('التحصيل/السداد', _CustomerLineFilter.settlements),
              _filterChip('الآجل', _CustomerLineFilter.pending),
              _filterChip('المعتمد', _CustomerLineFilter.posted),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visibleLines.isEmpty
                ? const Center(child: Text('لا توجد حركات مرتبطة لهذا العميل'))
                : ListView(
                    children: [
                      _tableHeader(context),
                      const SizedBox(height: 6),
                      ...visibleLines.map((line) {
                        final d = line.date;
                        final date = _formatLineDate(d);
                        final amountColor = _sideTextColor(line.side);
                        final amountBg = _sideFillColor(line.side);
                        final balance = _displayBalanceAmountForLine(
                          line,
                          balances,
                          customer.net,
                        );
                        final balanceSide = _displayBalanceSideForLine(
                          line,
                          balances,
                          customer.net,
                        );
                        final balanceColor = _sideTextColor(balanceSide);
                        final balanceBg = _sideFillColor(balanceSide);
                        final balanceLabel = balance.toStringAsFixed(2);

                        final actions = <PopupMenuEntry<_LineAction>>[];
                        final isSettlement =
                            line.txnKind == 'claim_collect' ||
                            line.txnKind == 'claim_pay';
                        final displayTitle = _displayTitleForLine(line);
                        final displayDetails = isSettlement
                            ? _buildSettlementDetails(line)
                            : _compactDetailsForLine(line);
                        if (line.lineType == _CustomerLineType.claimOpen) {
                          final isReceivable = line.claimType == 'receivable';
                          actions.add(
                            PopupMenuItem(
                              value: isReceivable
                                  ? _LineAction.collectPartial
                                  : _LineAction.payPartial,
                              child: Text(
                                isReceivable ? 'تحصيل جزئي' : 'سداد جزئي',
                              ),
                            ),
                          );
                          actions.add(
                            PopupMenuItem(
                              value: isReceivable
                                  ? _LineAction.collectFull
                                  : _LineAction.payFull,
                              child: Text(
                                isReceivable ? 'تحصيل كلي' : 'سداد كلي',
                              ),
                            ),
                          );
                        } else if (line.lineType == _CustomerLineType.txn &&
                            isSettlement &&
                            line.txnStatus == 'posted') {
                          final isCollect = line.txnKind == 'claim_collect';
                          actions.add(
                            PopupMenuItem(
                              value: _LineAction.editSettlement,
                              child: Text(
                                isCollect ? 'تعديل التحصيل' : 'تعديل السداد',
                              ),
                            ),
                          );
                          actions.add(
                            PopupMenuItem(
                              value: _LineAction.deleteSettlement,
                              child: Text(
                                isCollect ? 'حذف التحصيل' : 'حذف السداد',
                              ),
                            ),
                          );
                        } else if (line.lineType == _CustomerLineType.txn &&
                            !isSettlement &&
                            line.txnStatus == 'posted' &&
                            (line.txnKind == 'transfer' ||
                                line.txnKind == 'receive' ||
                                line.txnKind == 'fawry_cash' ||
                                line.txnKind == 'fawry_credit')) {
                          actions.add(
                            const PopupMenuItem(
                              value: _LineAction.rollbackPosted,
                              child: Text('إلغاء العملية'),
                            ),
                          );
                        } else if (line.lineType == _CustomerLineType.txn &&
                            line.txnStatus == 'pending') {
                          if (line.txnKind == 'transfer' ||
                              line.txnKind == 'fawry_credit') {
                            actions.add(
                              const PopupMenuItem(
                                value: _LineAction.collectPendingPartial,
                                child: Text('تحصيل جزئي'),
                              ),
                            );
                          } else if (line.txnKind == 'receive') {
                            actions.add(
                              const PopupMenuItem(
                                value: _LineAction.payPendingPartial,
                                child: Text('سداد جزئي'),
                              ),
                            );
                          }
                          actions.add(
                            const PopupMenuItem(
                              value: _LineAction.confirmPending,
                              child: Text('اعتماد الآجل'),
                            ),
                          );
                          actions.add(
                            const PopupMenuItem(
                              value: _LineAction.cancelPending,
                              child: Text('إلغاء الآجل'),
                            ),
                          );
                        }

                        final busy =
                            (line.claimId != null &&
                                busyIds.contains(line.claimId)) ||
                            (line.txnId != null &&
                                busyIds.contains(line.txnId));
                        final canConfirmPending =
                            line.lineType == _CustomerLineType.txn &&
                            line.txnStatus == 'pending';

                        return InkWell(
                          onTap: () => onShowDetails(line),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                _tableCell(
                                  text: date,
                                  flex: 2,
                                  background: Colors.transparent,
                                  align: Alignment.center,
                                ),
                                _tableCell(
                                  text: line.amount.toStringAsFixed(2),
                                  flex: 2,
                                  background: amountBg,
                                  textColor: amountColor,
                                  align: Alignment.center,
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                displayTitle,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              if ((displayDetails ?? '')
                                                  .trim()
                                                  .isNotEmpty)
                                                Text(
                                                  displayDetails!.trim(),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                              // تفاصيل فقط بدون مرجع/حالة لعرض مبسط
                                            ],
                                          ),
                                        ),
                                        if (canConfirmPending)
                                          Padding(
                                            padding:
                                                const EdgeInsetsDirectional.only(
                                                  start: 4,
                                                ),
                                            child: OutlinedButton.icon(
                                              onPressed: busy
                                                  ? null
                                                  : () => onLineAction(
                                                      line,
                                                      _LineAction
                                                          .confirmPending,
                                                    ),
                                              icon: const Icon(
                                                Icons.verified_outlined,
                                                size: 16,
                                              ),
                                              label: const Text('اعتماد'),
                                              style: OutlinedButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                          ),
                                        if (actions.isNotEmpty)
                                          PopupMenuButton<_LineAction>(
                                            onSelected: busy
                                                ? null
                                                : (action) => onLineAction(
                                                    line,
                                                    action,
                                                  ),
                                            itemBuilder: (_) => actions,
                                            icon: const Icon(
                                              Icons.more_vert,
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                _tableCell(
                                  text: balanceLabel,
                                  flex: 2,
                                  background: balanceBg,
                                  textColor: balanceColor,
                                  align: Alignment.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _tableHeader(BuildContext context) {
    return Row(
      children: [
        _tableCell(
          text: 'التاريخ',
          flex: 2,
          background: const Color(0xFF0EA5E9),
          textColor: Colors.white,
          align: Alignment.center,
          bold: true,
        ),
        _tableCell(
          text: 'المبلغ',
          flex: 2,
          background: const Color(0xFF0EA5E9),
          textColor: Colors.white,
          align: Alignment.center,
          bold: true,
        ),
        _tableCell(
          text: 'التفاصيل',
          flex: 4,
          background: const Color(0xFF0EA5E9),
          textColor: Colors.white,
          align: Alignment.center,
          bold: true,
        ),
        _tableCell(
          text: 'الرصيد',
          flex: 2,
          background: const Color(0xFF0EA5E9),
          textColor: Colors.white,
          align: Alignment.center,
          bold: true,
        ),
      ],
    );
  }

  Widget _tableCell({
    required String text,
    required int flex,
    required Color background,
    Color textColor = Colors.black87,
    Alignment align = Alignment.centerLeft,
    bool bold = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        alignment: align,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
