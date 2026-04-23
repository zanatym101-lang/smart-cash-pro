import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../data/app_db.dart';
import '../models/transaction.dart';
import '../models/claim.dart';
import '../models/customer_attachment.dart';
import '../widgets/app_title.dart';
import 'customer_report_screen.dart';
import 'fawry_screen.dart';
import 'receive_screen.dart';
import 'transfer_screen.dart';

part 'customer_filters_and_sort.dart';
part 'customer_bucket_builder.dart';
part 'customer_attachment_actions.dart';
part 'customer_details_panel.dart';
part 'customers_list_section.dart';
part 'customers_navigation_actions.dart';

String _stripSystemTags(String input) {
  var v = input;
  v = v.replaceAllMapped(
    RegExp(r'settlement_note:\s*(.+?)(?=\s+-\s+claim_id:\d+|$)'),
    (m) => 'ملاحظة التسوية: ${(m.group(1) ?? '').trim()}',
  );
  v = v.replaceAll(RegExp(r'claim_id:\d+'), '');
  v = v.replaceAll(RegExp(r'pending_txn:\d+'), '');
  v = v.replaceAll(RegExp(r'\s+-\s+-+'), ' - ');
  v = v.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return v;
}

enum _CustomerListFilter { all, receivable, payable, pending, archived }

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  bool _loading = true;
  String? _error;
  String _query = '';
  List<_CustomerBucket> _customers = [];
  final Set<int> _busyIds = {};
  Set<String> _pinnedCustomers = {};
  double _customerAlertThreshold = 0;
  _CustomerListFilter _listFilter = _CustomerListFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _setMountedState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  String? _inferPartyFromClaimNote(Txn t) {
    if (t.kind != 'claim_collect' && t.kind != 'claim_pay') return null;
    final note = (t.note ?? '').trim();
    if (note.isEmpty) return null;
    final patterns = <RegExp>[
      RegExp(r'تحصيل مستحقات من\s+([^-\n]+)'),
      RegExp(r'سداد مستحقات إلى\s+([^-\n]+)'),
      RegExp(r'سداد مستحقات الى\s+([^-\n]+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(note);
      if (m != null) {
        final name = (m.group(1) ?? '').trim();
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final settings = await AppDb.instance.getAppSettings();
      final pinned = settings.pinnedCustomers.map((e) => e.toString()).toSet();
      final alertThreshold = settings.customerAlertThreshold;

      final txns = await AppDb.instance.listTxns();
      final claims = await AppDb.instance.listClaims();
      final txnById = {for (final t in txns) t.id: t};

      final settlementByPending = <int, List<Txn>>{};
      final settlementByClaim = <int, List<Txn>>{};
      final settledByClaimId = <int, double>{};
      for (final t in txns) {
        if (t.status != 'posted') continue;
        if (t.kind != 'claim_collect' && t.kind != 'claim_pay') continue;
        final ref = _extractPendingSettlementRef(t.note);
        if (ref == null) continue;
        settlementByPending.putIfAbsent(ref, () => []).add(t);
      }
      for (final t in txns) {
        if (t.status != 'posted') continue;
        if (t.kind != 'claim_collect' && t.kind != 'claim_pay') continue;
        final claimId = _extractClaimIdFromNote(t.note);
        if (claimId == null) continue;
        settlementByClaim.putIfAbsent(claimId, () => []).add(t);
        settledByClaimId[claimId] = (settledByClaimId[claimId] ?? 0) + t.amount;
      }

      final pendingSettled = <int, double>{};
      final settlementRemainingByTxnId = <int, double>{};
      final settlementSourceLabelByTxnId = <int, String>{};

      double pendingDue(Txn t) {
        if (t.kind == 'transfer') return _pendingTransferDue(t);
        if (t.kind == 'receive') return _pendingReceiveDue(t);
        if (t.kind == 'fawry_credit') return t.amount + t.clientFee;
        return 0;
      }

      String pendingLabel(Txn t) {
        switch (t.kind) {
          case 'transfer':
            return 'تحويل آجل';
          case 'receive':
            return 'استلام آجل';
          case 'fawry_credit':
            return 'فوري آجل';
          default:
            return t.kind;
        }
      }

      for (final entry in settlementByPending.entries) {
        final pendingTxn = txnById[entry.key];
        if (pendingTxn == null) continue;
        final due = pendingDue(pendingTxn);
        var remaining = due;
        final list = entry.value
          ..sort((a, b) {
            final c = a.entryDate.compareTo(b.entryDate);
            if (c != 0) return c;
            return a.id.compareTo(b.id);
          });
        for (final s in list) {
          remaining = (remaining - s.amount).clamp(0, 1e18).toDouble();
          settlementRemainingByTxnId[s.id] = remaining;
          settlementSourceLabelByTxnId[s.id] = pendingLabel(pendingTxn);
        }
        pendingSettled[entry.key] = (due - remaining).clamp(0, 1e18).toDouble();
      }

      for (final entry in settlementByClaim.entries) {
        final claimId = entry.key;
        Claim? claim;
        for (final c in claims) {
          if (c.id == claimId) {
            claim = c;
            break;
          }
        }
        if (claim == null) continue;
        final totalSettled = settledByClaimId[claimId] ?? 0;
        final original = claim.status == 'open'
            ? claim.amount + totalSettled
            : (totalSettled > claim.amount ? totalSettled : claim.amount);
        var remaining = original;
        final list = entry.value
          ..sort((a, b) {
            final c = a.entryDate.compareTo(b.entryDate);
            if (c != 0) return c;
            return a.id.compareTo(b.id);
          });
        for (final s in list) {
          remaining = (remaining - s.amount).clamp(0, 1e18).toDouble();
          settlementRemainingByTxnId[s.id] = remaining;
          settlementSourceLabelByTxnId[s.id] = claim.type == 'receivable'
              ? 'مستحق (عليه)'
              : 'مستحق (له)';
        }
      }

      final map = <String, _CustomerBucket>{};

      _CustomerBucket bucketFor({required String name, String? phone}) {
        final normalizedName = name.trim().isEmpty
            ? 'عميل بدون اسم'
            : name.trim();
        final normalizedPhone = _normalizePhone(phone ?? '');
        final key = _bucketKey(name: normalizedName, phone: normalizedPhone);
        return map.putIfAbsent(
          key,
          () => _CustomerBucket(
            key: key,
            name: normalizedName,
            phone: normalizedPhone.isEmpty ? null : normalizedPhone,
          ),
        );
      }

      final openClaimSourceTxnIds = <int>{};
      for (final c in claims) {
        final name = c.party.trim();
        if (name.isEmpty) continue;
        if (c.status == 'open' && c.sourceTxnId != null) {
          openClaimSourceTxnIds.add(c.sourceTxnId!);
        }
        final phone = _extractPhone(c.note);
        final b = bucketFor(name: name, phone: phone);
        final settledForClaim = settledByClaimId[c.id] ?? 0;
        final remainingAmount = c.status == 'open' ? c.amount : 0.0;
        final originalAmount = c.status == 'open'
            ? c.amount + settledForClaim
            : (settledForClaim > c.amount ? settledForClaim : c.amount);
        final settledAmount = (originalAmount - remainingAmount)
            .clamp(0, 1e18)
            .toDouble();
        if (c.type == 'receivable') {
          b.receivableClaims += remainingAmount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.receivable,
              amount: originalAmount,
              displayAmount: remainingAmount,
              originalAmount: originalAmount,
              settledAmount: settledAmount,
              title: 'مستحق مفتوح (عليه)',
              details: _detailsForClaimLine(c),
              ref: 'Claim#${c.id}',
              lineType: _CustomerLineType.claimOpen,
              claimId: c.id,
              claimType: c.type,
            ),
          );
        } else if (c.type == 'payable') {
          b.payableClaims += remainingAmount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.payable,
              amount: originalAmount,
              displayAmount: remainingAmount,
              originalAmount: originalAmount,
              settledAmount: settledAmount,
              title: 'مستحق مفتوح (له)',
              details: _detailsForClaimLine(c),
              ref: 'Claim#${c.id}',
              lineType: _CustomerLineType.claimOpen,
              claimId: c.id,
              claimType: c.type,
            ),
          );
        }
      }

      for (final t in txns) {
        if (t.kind == 'expense') continue;
        if (t.status == 'rolled_back' || t.status == 'canceled') {
          continue;
        }
        if (t.kind == 'fawry_credit' &&
            t.status == 'posted' &&
            openClaimSourceTxnIds.contains(t.id)) {
          // هذا الفوري الآجل له مستحق مفتوح ظاهر بالفعل، لا نكرر السطر.
          continue;
        }
        if (t.kind == 'claim_open_receivable' ||
            t.kind == 'claim_open_payable') {
          continue;
        }
        var name = (t.party ?? '').trim();
        if (name.isEmpty) {
          name = _inferPartyFromClaimNote(t) ?? '';
        }
        String? phone = _extractPhone(t.note) ?? _extractPhone(t.reference);
        final pendingRefFromNote = _extractPendingSettlementRef(t.note);
        if ((name.isEmpty || (phone ?? '').trim().isEmpty) &&
            pendingRefFromNote != null) {
          final src = txnById[pendingRefFromNote];
          if (src != null) {
            if (name.isEmpty) {
              name = (src.party ?? '').trim();
            }
            phone ??= _extractPhone(src.note) ?? _extractPhone(src.reference);
          }
        }
        if (name.isEmpty && (phone ?? '').trim().isEmpty) continue;
        final b = bucketFor(
          name: name.isEmpty ? 'عميل بدون اسم' : name,
          phone: phone,
        );

        if (t.status == 'pending') {
          if (t.kind == 'transfer') {
            final dueBase = _pendingTransferDue(t);
            final settled = pendingSettled[t.id] ?? 0;
            final due = (dueBase - settled).clamp(0, 1e18).toDouble();
            if (due > 0) {
              b.receivablePending += due;
            }
            b.lines.add(
              _CustomerLine(
                date: t.entryDate,
                side: _LineSide.receivable,
                amount: dueBase,
                displayAmount: due,
                originalAmount: dueBase,
                settledAmount: settled,
                title: 'تحويل آجل',
                details: _detailsForTransfer(t),
                ref: 'Txn#${t.id}',
                lineType: _CustomerLineType.txn,
                txnId: t.id,
                txnKind: t.kind,
                txnStatus: t.status,
              ),
            );
            continue;
          }

          if (t.kind == 'receive') {
            final dueBase = _pendingReceiveDue(t);
            final settled = pendingSettled[t.id] ?? 0;
            final due = (dueBase - settled).clamp(0, 1e18).toDouble();
            if (due > 0) {
              b.payablePending += due;
            }
            b.lines.add(
              _CustomerLine(
                date: t.entryDate,
                side: _LineSide.payable,
                amount: dueBase,
                displayAmount: due,
                originalAmount: dueBase,
                settledAmount: settled,
                title: 'استلام آجل',
                details: _detailsForReceive(t),
                ref: 'Txn#${t.id}',
                lineType: _CustomerLineType.txn,
                txnId: t.id,
                txnKind: t.kind,
                txnStatus: t.status,
              ),
            );
            continue;
          }

          if (t.kind == 'fawry_credit') {
            final dueBase = t.amount + t.clientFee;
            final settled = pendingSettled[t.id] ?? 0;
            final due = (dueBase - settled).clamp(0, 1e18).toDouble();
            if (due > 0) {
              b.receivablePending += due;
            }
            b.lines.add(
              _CustomerLine(
                date: t.entryDate,
                side: _LineSide.receivable,
                amount: dueBase,
                displayAmount: due,
                originalAmount: dueBase,
                settledAmount: settled,
                title: 'فوري آجل',
                details: _detailsForFawry(t),
                ref: 'Txn#${t.id}',
                lineType: _CustomerLineType.txn,
                txnId: t.id,
                txnKind: t.kind,
                txnStatus: t.status,
              ),
            );
            continue;
          }
        }

        final pendingRef = pendingRefFromNote;
        final claimIdForTxn = _extractClaimIdFromNote(t.note);
        final pendingSource = pendingRef != null ? txnById[pendingRef] : null;
        final remainingAfter = settlementRemainingByTxnId[t.id];
        final sourceKindLabel = settlementSourceLabelByTxnId[t.id];

        b.lines.add(
          _CustomerLine(
            date: t.entryDate,
            side: _txnSide(t),
            amount: _txnVolume(t),
            title: _kindLabel(t),
            details: t.kind == 'transfer'
                ? _detailsForTransfer(t)
                : t.kind == 'receive'
                ? _detailsForReceive(t)
                : (t.kind == 'fawry_cash' || t.kind == 'fawry_credit')
                ? _detailsForFawry(t)
                : (t.kind == 'claim_collect' || t.kind == 'claim_pay')
                ? (pendingSource != null
                      ? _detailsForPendingSource(pendingSource)
                      : _detailsForClaimTxn(t))
                : t.note,
            ref: 'Txn#${t.id} (${t.status})',
            lineType: _CustomerLineType.txn,
            txnId: t.id,
            txnKind: t.kind,
            txnStatus: t.status,
            remainingAfter: remainingAfter,
            sourceKindLabel: sourceKindLabel,
            pendingTxnId: pendingRef,
            claimId: claimIdForTxn,
          ),
        );
      }

      final customers = map.values.where((c) => c.lines.isNotEmpty).toList();
      for (final c in customers) {
        c.lines.sort(_compareCustomerLinesDesc);
        if (c.lines.isNotEmpty) {
          c.lastActivity = c.lines.first.date;
        }
      }
      customers.sort((a, b) {
        final aPinned = pinned.contains(_customerKeyFor(a));
        final bPinned = pinned.contains(_customerKeyFor(b));
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        final aDate = a.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _customers = customers;
        _pinnedCustomers = pinned;
        _customerAlertThreshold = alertThreshold;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePinnedCustomers(Set<String> keys) async {
    try {
      final settings = await AppDb.instance.getAppSettings();
      await AppDb.instance.setAppSettings(
        settings.copyWith(pinnedCustomers: keys.toList()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _togglePin(_CustomerBucket c) async {
    final key = _customerKeyFor(c);
    final next = Set<String>.from(_pinnedCustomers);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    setState(() => _pinnedCustomers = next);
    await _savePinnedCustomers(next);
  }

  Future<void> _editAlertThreshold() async {
    final ctrl = TextEditingController(
      text: _customerAlertThreshold <= 0
          ? ''
          : _customerAlertThreshold.toStringAsFixed(2),
    );
    final res = await showDialog<double?>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('حد تنبيه العملاء'),
    content: TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        hintText: 'أدخل الحد (0 لتعطيل التنبيه)',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(null),
        child: const Text('إلغاء'),
      ),
      ElevatedButton(
        onPressed: () {
          final raw = ctrl.text.trim();
          if (raw.isEmpty) {
            Navigator.of(ctx).pop(0);
            return;
          }
          final parsed = double.tryParse(raw.replaceAll(',', ''));
          Navigator.of(ctx).pop(parsed);
        },
        child: const Text('حفظ'),
      ),
    ],
  ),
);

if (!mounted) return;   // ✅ أضف هذا السطر

if (res == null) return;
    final double value = res.isNaN || res < 0 ? 0.0 : res;
    try {
      final settings = await AppDb.instance.getAppSettings();
      await AppDb.instance.setAppSettings(
        settings.copyWith(customerAlertThreshold: value),
      );
      if (!mounted) return;
      setState(() => _customerAlertThreshold = value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  String _detailsForTransfer(Txn t) {
    final entered = _pendingTransferDue(t).toStringAsFixed(2);
    final sent = (t.amount - t.networkFee).toStringAsFixed(2);
    final fee = t.clientFee.toStringAsFixed(2);
    final nf = t.networkFee.toStringAsFixed(2);
    final phone = _extractPhone(t.note);
    final parts = <String>[
      'المطلوب من العميل: $entered',
      'المحوّل للعميل: $sent',
      'عمولة العميل: $fee',
      'رسوم الشبكة: $nf',
      'نوع التحويل: ${t.mode}',
    ];
    if (phone != null) parts.add('الهاتف: $phone');
    return parts.join(' | ');
  }

  String _detailsForReceive(Txn t) {
    final amt = t.amount.toStringAsFixed(2);
    final fee = t.clientFee.toStringAsFixed(2);
    final phone = _extractPhone(t.note);
    final parts = <String>[
      'المبلغ المستلم: $amt',
      'العمولة/الربح: $fee',
      'نوع الاستلام: ${t.mode}',
    ];
    if (phone != null) parts.add('الهاتف: $phone');
    return parts.join(' | ');
  }

  String _detailsForFawry(Txn t) {
    final svc = (t.serviceName ?? '').trim();
    final ref = (t.reference ?? '').trim();
    final base = t.amount.toStringAsFixed(2);
    final fee = t.clientFee.toStringAsFixed(2);
    final phone = _extractPhone(t.note);
    final parts = <String>[
      'الخدمة: $svc',
      'قيمة الخدمة: $base',
      'الربح/العمولة: $fee',
    ];
    if (ref.isNotEmpty) parts.add('المرجع: $ref');
    if (phone != null) parts.add('الهاتف: $phone');
    return parts.join(' | ');
  }

  String? _detailsForClaimLine(Claim c) {
    final parts = <String>[];
    final note = (c.note ?? '').trim();
    if (note.isNotEmpty) parts.add(note);
    if (c.sourceTxnId != null) {
      parts.add('مرجع العملية: Txn#${c.sourceTxnId}');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  String _detailsForClaimTxn(Txn t) {
    final parts = <String>[];
    final note = (t.note ?? '').trim();
    if (note.isNotEmpty) parts.add(_stripSystemTags(note));
    return parts.join(' | ');
  }

  String? _detailsForPendingSource(Txn t) {
    if (t.kind == 'transfer') return _detailsForTransfer(t);
    if (t.kind == 'receive') return _detailsForReceive(t);
    if (t.kind == 'fawry_cash' || t.kind == 'fawry_credit') {
      return _detailsForFawry(t);
    }
    return t.note;
  }

  String _kindLabel(Txn t) {
    switch (t.kind) {
      case 'transfer':
        return 'تحويل';
      case 'receive':
        return 'استلام';
      case 'fawry_cash':
        return 'فوري نقدي';
      case 'fawry_credit':
        return 'فوري آجل';
      case 'claim_collect':
        return 'تحصيل مستحق';
      case 'claim_pay':
        return 'سداد مستحق';
      default:
        return t.kind;
    }
  }

  double _transferBaseAmount(Txn t) {
    if (t.mode == 'type2_v2') return t.amount + t.clientFee;
    return t.amount - t.networkFee;
  }

  double _txnVolume(Txn t) {
    switch (t.kind) {
      case 'transfer':
        return _transferBaseAmount(t);
      case 'fawry_cash':
      case 'fawry_credit':
        return t.amount + t.clientFee;
      default:
        return t.amount;
    }
  }

  _LineSide _txnSide(Txn t) {
    switch (t.kind) {
      case 'receive':
        return _LineSide.payable;
      case 'claim_collect':
        return _LineSide.payable; // تحصيل يقلل المستحق علينا العميل
      case 'claim_pay':
        return _LineSide.receivable; // سداد يقلل علينا فيزيد الصافي
      default:
        return _LineSide.receivable;
    }
  }

  String _formatLineDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  double _pendingTransferDue(Txn t) {
    if (t.mode == 'type2_v2') return t.amount + t.clientFee;
    final base = t.amount - t.networkFee;
    if (t.mode == 'type1') return base + t.clientFee;
    return base;
  }

  double _pendingReceiveDue(Txn t) {
    if (t.mode == 'cash') return t.amount;
    if (t.mode == 'deduct') {
      return (t.amount - t.clientFee).clamp(0, 1e18).toDouble();
    }
    return 0;
  }

  Future<_SettlementAmountInput?> _promptSettlementAmount({
    required String actionLabel,
    required String party,
    required double remaining,
    bool withNote = false,
  }) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;
    try {
      final result = await showDialog<_SettlementAmountInput>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text('$actionLabel المستحق'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الطرف: $party'),
                const SizedBox(height: 6),
                Text('المتبقي: ${remaining.toStringAsFixed(2)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (withNote) ...[
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
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
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
                  if (value > remaining) {
                    setState(() => error = 'المبلغ أكبر من المتبقي');
                    return;
                  }
                  final note = noteCtrl.text.trim();
                  Navigator.of(ctx).pop(
                    _SettlementAmountInput(
                      amount: value,
                      note: withNote && note.isNotEmpty ? note : null,
                    ),
                  );
                },
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      return result;
    } finally {
      amountCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<double> _resolveClaimRemaining(int claimId, double fallback) async {
    try {
      final claims = await AppDb.instance.listClaims(status: 'open');
      for (final c in claims) {
        if (c.id == claimId) return c.amount;
      }
    } catch (_) {}
    return fallback;
  }

  Future<bool> _confirmAction({
    required String title,
    required String body,
    required String okText,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _handleLineAction(_CustomerLine line, _LineAction action) async {
    final key = line.claimId ?? line.txnId;
    if (key != null && _busyIds.contains(key)) return;

    Future<void> run(Future<void> Function() fn) async {
      if (key != null) setState(() => _busyIds.add(key));
      try {
        await fn();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم التنفيذ بنجاح ✅')));
        }
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      } finally {
        if (mounted && key != null) setState(() => _busyIds.remove(key));
      }
    }

    if (action == _LineAction.editSettlement ||
        action == _LineAction.deleteSettlement) {
      if (line.txnId == null) return;
      final isCollect = line.txnKind == 'claim_collect';
      final actionLabel = isCollect ? 'تحصيل' : 'سداد';
      final party = () {
        try {
          return _customers.firstWhere((c) => c.lines.contains(line)).name;
        } catch (_) {
          return 'العميل';
        }
      }();

      if (action == _LineAction.editSettlement) {
        final remainingBefore = (line.remainingAfter ?? 0) + line.amount;
        final result = await _promptSettlementAmount(
          actionLabel: actionLabel,
          party: party,
          remaining: remainingBefore,
        );
        if (result == null) return;
        await run(() async {
          if (line.pendingTxnId != null) {
            await AppDb.instance.rollbackPendingSettlement(line.txnId!);
            await AppDb.instance.addPendingSettlementForTxn(
              pendingTxnId: line.pendingTxnId!,
              amount: result.amount,
            );
            return;
          }
          if (line.claimId != null) {
            await AppDb.instance.rollbackClaimSettlement(line.txnId!);
            await AppDb.instance.settleClaim(
              claimId: line.claimId!,
              amount: result.amount,
            );
            return;
          }
          throw Exception('لا يمكن تعديل هذه العملية.');
        });
        return;
      }

      final ok = await _confirmAction(
        title: 'حذف $actionLabel',
        body: 'سيتم حذف عملية $actionLabel رقم #${line.txnId}.',
        okText: 'حذف',
      );
      if (!ok) return;
      await run(() async {
        if (line.pendingTxnId != null) {
          await AppDb.instance.rollbackPendingSettlement(line.txnId!);
          return;
        }
        if (line.claimId != null) {
          await AppDb.instance.rollbackClaimSettlement(line.txnId!);
          return;
        }
        throw Exception('لا يمكن حذف هذه العملية.');
      });
      return;
    }

    if (action == _LineAction.rollbackPosted) {
      if (line.txnId == null) return;
      final ok = await _confirmAction(
        title: 'إلغاء عملية',
        body: 'سيتم إلغاء العملية رقم #${line.txnId} وعكس تأثيرها.',
        okText: 'إلغاء العملية',
      );
      if (!ok) return;
      await run(() async {
        await AppDb.instance.rollbackPosted(line.txnId!);
      });
      return;
    }

    if (line.lineType == _CustomerLineType.claimOpen) {
      final isReceivable = line.claimType == 'receivable';
      final actionLabel = isReceivable ? 'تحصيل' : 'سداد';
      final isFull =
          action == _LineAction.collectFull || action == _LineAction.payFull;

      final party = () {
        try {
          return _customers.firstWhere((c) => c.lines.contains(line)).name;
        } catch (_) {
          return 'العميل';
        }
      }();

      final remaining = await _resolveClaimRemaining(
        line.claimId!,
        line.effectiveDisplayAmount,
      );
      final result = isFull
          ? _SettlementAmountInput(amount: remaining, note: null)
          : await _promptSettlementAmount(
              actionLabel: actionLabel,
              party: party,
              remaining: remaining,
              withNote: true,
            );
      if (result == null) return;

      await run(() async {
        await AppDb.instance.settleClaim(
          claimId: line.claimId!,
          amount: result.amount,
          note: result.note,
        );
      });
      return;
    }

    if (line.lineType == _CustomerLineType.txn && line.txnStatus == 'pending') {
      if (action == _LineAction.collectPendingPartial ||
          action == _LineAction.payPendingPartial) {
        final actionLabel = action == _LineAction.collectPendingPartial
            ? 'تحصيل'
            : 'سداد';
        final party = () {
          try {
            return _customers.firstWhere((c) => c.lines.contains(line)).name;
          } catch (_) {
            return 'العميل';
          }
        }();
        final result = await _promptSettlementAmount(
          actionLabel: actionLabel,
          party: party,
          remaining: line.amount,
        );
        if (result == null) return;
        await run(() async {
          await AppDb.instance.addPendingSettlementForTxn(
            pendingTxnId: line.txnId!,
            amount: result.amount,
          );
        });
      } else if (action == _LineAction.confirmPending) {
        final ok = await _confirmAction(
          title: 'اعتماد عملية آجلة',
          body: 'سيتم تنفيذ العملية رقم #${line.txnId}.',
          okText: 'اعتماد',
        );
        if (!ok) return;
        await run(() async {
          await AppDb.instance.confirmPending(line.txnId!);
        });
      } else if (action == _LineAction.cancelPending) {
        final ok = await _confirmAction(
          title: 'إلغاء عملية آجلة',
          body: 'سيتم إلغاء العملية رقم #${line.txnId}.',
          okText: 'إلغاء',
        );
        if (!ok) return;
        await run(() async {
          await AppDb.instance.cancelPending(line.txnId!);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final archivedCount = _customers.where((c) => c.isArchived).length;
    final totalReceivable = items.fold<double>(
      0,
      (s, c) => s + c.receivableTotal,
    );
    final totalPayable = items.fold<double>(0, (s, c) => s + c.payableTotal);
    final net = totalReceivable - totalPayable;

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'العملاء'),
        actions: [
          IconButton(
            tooltip: 'حد التنبيه',
            onPressed: _editAlertThreshold,
            icon: const Icon(Icons.tune),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _summaryCard(
              receivable: totalReceivable,
              payable: totalPayable,
              net: net,
              customers: items.length,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _listFilterChip('الكل', _CustomerListFilter.all),
                _listFilterChip('لنا', _CustomerListFilter.receivable),
                _listFilterChip('علينا', _CustomerListFilter.payable),
                _listFilterChip('الآجل', _CustomerListFilter.pending),
                _listFilterChip(
                  'الأرشيف',
                  _CustomerListFilter.archived,
                  count: archivedCount,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                labelText: 'بحث باسم العميل أو رقم الهاتف',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('خطأ: $_error'),
                ),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('لا توجد بيانات عملاء حاليًا.')),
              )
            else
              ...items.map(
                (c) => _customerCard(
                  c,
                  showArchivedLabel:
                      _listFilter == _CustomerListFilter.archived &&
                      c.isArchived,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _LineSide { receivable, payable }

enum _CustomerLineType { claimOpen, txn }

enum _LineAction {
  collectPartial,
  collectFull,
  payPartial,
  payFull,
  collectPendingPartial,
  payPendingPartial,
  confirmPending,
  cancelPending,
  editSettlement,
  deleteSettlement,
  rollbackPosted,
}

class _CustomerLine {
  final DateTime date;
  final _LineSide side;
  final double amount;
  final double? displayAmount;
  final double? originalAmount;
  final double? settledAmount;
  final String title;
  final String? details;
  final String ref;
  final _CustomerLineType lineType;
  final int? claimId;
  final String? claimType;
  final int? txnId;
  final String? txnKind;
  final String? txnStatus;
  final double? remainingAfter;
  final String? sourceKindLabel;
  final int? pendingTxnId;

  const _CustomerLine({
    required this.date,
    required this.side,
    required this.amount,
    this.displayAmount,
    this.originalAmount,
    this.settledAmount,
    required this.title,
    required this.details,
    required this.ref,
    required this.lineType,
    this.claimId,
    this.claimType,
    this.txnId,
    this.txnKind,
    this.txnStatus,
    this.remainingAfter,
    this.sourceKindLabel,
    this.pendingTxnId,
  });

  double get effectiveDisplayAmount => displayAmount ?? amount;
  double get effectiveOriginalAmount => originalAmount ?? amount;
  double get effectiveSettledAmount {
    if (settledAmount != null) return settledAmount!;
    final settled = effectiveOriginalAmount - effectiveDisplayAmount;
    return settled > 0 ? settled : 0;
  }
}

class _CustomerBucket {
  final String key;
  final String name;
  final String? phone;

  double receivableClaims = 0;
  double payableClaims = 0;
  double receivablePending = 0;
  double payablePending = 0;
  final List<_CustomerLine> lines = [];
  DateTime? lastActivity;

  _CustomerBucket({required this.key, required this.name, this.phone});

  double get receivableTotal => receivableClaims + receivablePending;
  double get payableTotal => payableClaims + payablePending;
  double get net => receivableTotal - payableTotal;
  bool get isArchived {
    if (receivableTotal.abs() >= 0.0001 || payableTotal.abs() >= 0.0001) {
      return false;
    }
    return true;
  }
}
