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

String _stripSystemTags(String input) {
  var v = input;
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

  String _normalizePhone(String raw) {
    final b = StringBuffer();
    for (final r in raw.runes) {
      final ch = String.fromCharCode(r);
      final cu = ch.codeUnitAt(0);
      if (cu >= 48 && cu <= 57) b.write(ch);
    }
    return b.toString();
  }

  String? _extractPhone(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final matches = RegExp(r'\d{10,15}').allMatches(text);
    if (matches.isEmpty) return null;
    final phone = _normalizePhone(matches.first.group(0) ?? '');
    return phone.isEmpty ? null : phone;
  }

  int? _extractPendingSettlementRef(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final m = RegExp(r'pending_txn:(\d+)').firstMatch(note);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  int? _extractClaimIdFromNote(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final m = RegExp(r'claim_id:(\d+)').firstMatch(note);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  String _bucketKey({required String name, String? phone}) {
    final p = _normalizePhone(phone ?? '');
    if (p.isNotEmpty) return 'p:$p';
    return 'n:${name.trim().toLowerCase()}';
  }

  String _customerKeyFor(_CustomerBucket c) {
    return _bucketKey(name: c.name, phone: c.phone);
  }

  bool _isPinned(_CustomerBucket c) {
    return _pinnedCustomers.contains(_customerKeyFor(c));
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
            return 'تحويل معلّق';
          case 'receive':
            return 'استلام معلّق';
          case 'fawry_credit':
            return 'فوري آجل معلّق';
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
        final original = claim.amount + totalSettled;
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
            name: normalizedName,
            phone: normalizedPhone.isEmpty ? null : normalizedPhone,
          ),
        );
      }

      final openClaimSourceTxnIds = <int>{};
      for (final c in claims) {
        if (c.status != 'open') continue;
        final name = c.party.trim();
        if (name.isEmpty) continue;
        if (c.sourceTxnId != null) {
          openClaimSourceTxnIds.add(c.sourceTxnId!);
        }
        final phone = _extractPhone(c.note);
        final b = bucketFor(name: name, phone: phone);
        final settledForClaim = settledByClaimId[c.id] ?? 0;
        final displayAmount = c.amount + settledForClaim;
        if (c.type == 'receivable') {
          b.receivableClaims += c.amount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.receivable,
              amount: displayAmount,
              title: 'مستحق مفتوح (عليه)',
              details: _detailsForClaimLine(c),
              ref: 'Claim#${c.id}',
              lineType: _CustomerLineType.claimOpen,
              claimId: c.id,
              claimType: c.type,
            ),
          );
        } else if (c.type == 'payable') {
          b.payableClaims += c.amount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.payable,
              amount: displayAmount,
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
              b.lines.add(
                _CustomerLine(
                  date: t.entryDate,
                  side: _LineSide.receivable,
                  amount: due,
                  title: 'تحويل معلّق',
                  details: _detailsForTransfer(t),
                  ref: 'Txn#${t.id}',
                  lineType: _CustomerLineType.txn,
                  txnId: t.id,
                  txnKind: t.kind,
                  txnStatus: t.status,
                ),
              );
            }
            continue;
          }

          if (t.kind == 'receive') {
            final dueBase = _pendingReceiveDue(t);
            final settled = pendingSettled[t.id] ?? 0;
            final due = (dueBase - settled).clamp(0, 1e18).toDouble();
            if (due > 0) {
              b.payablePending += due;
              b.lines.add(
                _CustomerLine(
                  date: t.entryDate,
                  side: _LineSide.payable,
                  amount: due,
                  title: 'استلام معلّق',
                  details: _detailsForReceive(t),
                  ref: 'Txn#${t.id}',
                  lineType: _CustomerLineType.txn,
                  txnId: t.id,
                  txnKind: t.kind,
                  txnStatus: t.status,
                ),
              );
            }
            continue;
          }

          if (t.kind == 'fawry_credit') {
            final dueBase = t.amount + t.clientFee;
            final settled = pendingSettled[t.id] ?? 0;
            final due = (dueBase - settled).clamp(0, 1e18).toDouble();
            if (due > 0) {
              b.receivablePending += due;
              b.lines.add(
                _CustomerLine(
                  date: t.entryDate,
                  side: _LineSide.receivable,
                  amount: due,
                  title: 'فوري آجل معلّق',
                  details: _detailsForFawry(t),
                  ref: 'Txn#${t.id}',
                  lineType: _CustomerLineType.txn,
                  txnId: t.id,
                  txnKind: t.kind,
                  txnStatus: t.status,
                ),
              );
            }
            continue;
          }
        }

        final pendingRef = pendingRefFromNote;
        final claimIdForTxn = _extractClaimIdFromNote(t.note);
        final pendingSource = pendingRef != null ? txnById[pendingRef] : null;
        final remainingAfter = pendingRef != null
            ? settlementRemainingByTxnId[t.id]
            : null;
        final sourceKindLabel = pendingRef != null
            ? settlementSourceLabelByTxnId[t.id]
            : null;

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
        c.lines.sort((a, b) => b.date.compareTo(a.date));
        if (c.lines.isNotEmpty) {
          c.lastActivity = c.lines.first.date;
        }
      }
      customers.sort((a, b) {
        final aPinned = pinned.contains(_customerKeyFor(a));
        final bPinned = pinned.contains(_customerKeyFor(b));
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        final aDate =
            a.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
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

  List<_CustomerBucket> get _filtered {
    final q = _query.trim().toLowerCase();
    Iterable<_CustomerBucket> base = _customers;

    switch (_listFilter) {
      case _CustomerListFilter.archived:
        base = base.where((c) => c.isArchived);
        break;
      case _CustomerListFilter.receivable:
        base = base.where((c) => !c.isArchived && c.receivableTotal > 0);
        break;
      case _CustomerListFilter.payable:
        base = base.where((c) => !c.isArchived && c.payableTotal > 0);
        break;
      case _CustomerListFilter.pending:
        base = base.where(
          (c) =>
              !c.isArchived &&
              (c.receivablePending > 0 || c.payablePending > 0),
        );
        break;
      case _CustomerListFilter.all:
        base = base.where((c) => !c.isArchived);
        break;
    }

    if (q.isNotEmpty) {
      base = base.where((c) {
        final name = c.name.toLowerCase();
        final phone = (c.phone ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q);
      });
    }

    final list = base.toList();
    list.sort((a, b) {
      final aPinned = _pinnedCustomers.contains(_customerKeyFor(a));
      final bPinned = _pinnedCustomers.contains(_customerKeyFor(b));
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      final aDate = a.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return list;
  }

  Future<double?> _promptSettlementAmount({
    required String actionLabel,
    required String party,
    required double remaining,
  }) async {
    final ctrl = TextEditingController();
    String? error;
    try {
      return await showDialog<double>(
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
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
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
                  final value = double.tryParse(ctrl.text.trim());
                  if (value == null || value <= 0) {
                    setState(() => error = 'أدخل مبلغًا صحيحًا');
                    return;
                  }
                  if (value > remaining) {
                    setState(() => error = 'المبلغ أكبر من المتبقي');
                    return;
                  }
                  Navigator.of(ctx).pop(value);
                },
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
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
        final amount = await _promptSettlementAmount(
          actionLabel: actionLabel,
          party: party,
          remaining: remainingBefore,
        );
        if (amount == null) return;
        await run(() async {
          if (line.pendingTxnId != null) {
            await AppDb.instance.rollbackPendingSettlement(line.txnId!);
            await AppDb.instance.addPendingSettlementForTxn(
              pendingTxnId: line.pendingTxnId!,
              amount: amount,
            );
            return;
          }
          if (line.claimId != null) {
            await AppDb.instance.rollbackClaimSettlement(line.txnId!);
            await AppDb.instance.settleClaim(
              claimId: line.claimId!,
              amount: amount,
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
        line.amount,
      );
      final amount = isFull
          ? remaining
          : await _promptSettlementAmount(
              actionLabel: actionLabel,
              party: party,
              remaining: remaining,
            );
      if (amount == null) return;

      await run(() async {
        await AppDb.instance.settleClaim(
          claimId: line.claimId!,
          amount: amount,
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
        final amount = await _promptSettlementAmount(
          actionLabel: actionLabel,
          party: party,
          remaining: line.amount,
        );
        if (amount == null) return;
        await run(() async {
          await AppDb.instance.addPendingSettlementForTxn(
            pendingTxnId: line.txnId!,
            amount: amount,
          );
        });
      } else if (action == _LineAction.confirmPending) {
        final ok = await _confirmAction(
          title: 'اعتماد عملية معلّقة',
          body: 'سيتم تنفيذ العملية رقم #${line.txnId}.',
          okText: 'اعتماد',
        );
        if (!ok) return;
        await run(() async {
          await AppDb.instance.confirmPending(line.txnId!);
        });
      } else if (action == _LineAction.cancelPending) {
        final ok = await _confirmAction(
          title: 'إلغاء عملية معلّقة',
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

  Future<void> _openCustomer(_CustomerBucket c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CustomerSheet(
        customer: c,
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
      ),
    );
  }

  void _showLineDetails(_CustomerLine line) {
    final d = line.date;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final sideLabel = line.side == _LineSide.receivable
        ? 'عليه (تحصيل)'
        : 'له (سداد)';
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
              if (line.txnStatus != null && line.txnStatus!.trim().isNotEmpty)
                Text('الحالة: ${line.txnStatus}'),
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
                  _listFilterChip('المعلّق', _CustomerListFilter.pending),
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

  Widget _summaryCard({
    required double receivable,
    required double payable,
    required double net,
    required int customers,
  }) {
    final netLabel = net >= 0 ? 'الصافي لنا' : 'الصافي علينا';
    final netValue = net >= 0 ? net : -net;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إجمالي العملاء: $customers',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          _row('إجمالي لنا', receivable),
          _row('إجمالي علينا', payable),
          _row(netLabel, netValue),
        ],
      ),
    );
  }

  Widget _listFilterChip(
    String label,
    _CustomerListFilter value, {
    int? count,
  }) {
    final selected = _listFilter == value;
    final text = count != null ? '$label ($count)' : label;
    return ChoiceChip(
      label: Text(text),
      selected: selected,
      onSelected: (_) => setState(() => _listFilter = value),
    );
  }

  Widget _row(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerCard(_CustomerBucket c, {required bool showArchivedLabel}) {
    final netLabel = c.net >= 0 ? 'صافي عليه' : 'صافي له';
    final netValue = c.net >= 0 ? c.net : -c.net;
    final archivedTag = showArchivedLabel ? ' | مؤرشف' : '';
    final isPinned = _isPinned(c);
    final showWarning =
        _customerAlertThreshold > 0 &&
        (c.receivableTotal >= _customerAlertThreshold ||
            c.payableTotal >= _customerAlertThreshold);
    final last = c.lastActivity;
    final lastText = last == null
        ? 'لا توجد حركة'
        : 'آخر حركة: ${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}';

    return Card(
      child: ListTile(
        onTap: () => _openCustomer(c),
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(
          c.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${c.phone ?? 'بدون هاتف'}$archivedTag\n$lastText\n$netLabel: ${netValue.toStringAsFixed(2)} | عليه: ${c.receivableTotal.toStringAsFixed(2)} | له: ${c.payableTotal.toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showWarning)
              const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
            IconButton(
              onPressed: () => _togglePin(c),
              icon: Icon(
                isPinned ? Icons.star : Icons.star_border,
                color: isPinned ? Colors.amber : Colors.grey,
              ),
              tooltip: isPinned ? 'إزالة التثبيت' : 'تثبيت',
              visualDensity: VisualDensity.compact,
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _CustomerSheet extends StatefulWidget {
  final _CustomerBucket customer;
  final VoidCallback onTransferPending;
  final VoidCallback onReceivePending;
  final VoidCallback onFawryCredit;
  final VoidCallback onReport;
  final Future<void> Function(_CustomerLine line, _LineAction action)
  onLineAction;
  final void Function(_CustomerLine line) onShowDetails;
  final Set<int> busyIds;

  const _CustomerSheet({
    required this.customer,
    required this.onTransferPending,
    required this.onReceivePending,
    required this.onFawryCredit,
    required this.onReport,
    required this.onLineAction,
    required this.onShowDetails,
    required this.busyIds,
  });

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

enum _CustomerLineFilter { all, claims, settlements, pending, posted }

class _CustomerSheetState extends State<_CustomerSheet> {
  _CustomerLineFilter _filter = _CustomerLineFilter.all;

  _CustomerBucket get customer => widget.customer;
  VoidCallback get onTransferPending => widget.onTransferPending;
  VoidCallback get onReceivePending => widget.onReceivePending;
  VoidCallback get onFawryCredit => widget.onFawryCredit;
  VoidCallback get onReport => widget.onReport;
  Future<void> Function(_CustomerLine line, _LineAction action)
  get onLineAction => widget.onLineAction;
  void Function(_CustomerLine line) get onShowDetails => widget.onShowDetails;
  Set<int> get busyIds => widget.busyIds;

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

  String? _extractDetailPart(String? details, String prefix) {
    if (details == null) return null;
    final parts = details
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    for (final p in parts) {
      if (p.startsWith(prefix)) return p;
    }
    return null;
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

  String _customerKey() {
    final phone = _normalizePhone(customer.phone ?? '');
    if (phone.isNotEmpty) return 'p:$phone';
    return 'n:${customer.name.trim().toLowerCase()}';
  }

  Future<void> _quickSettleLatestClaim() async {
    final openClaims =
        customer.lines
            .where((l) => l.lineType == _CustomerLineType.claimOpen)
            .toList()
          ..sort((a, b) {
            final c = b.date.compareTo(a.date);
            if (c != 0) return c;
            final aId = a.claimId ?? 0;
            final bId = b.claimId ?? 0;
            return bId.compareTo(aId);
          });
    if (openClaims.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستحقات مفتوحة لهذا العميل')),
      );
      return;
    }
    final latest = openClaims.first;
    final action = latest.claimType == 'receivable'
        ? _LineAction.collectPartial
        : _LineAction.payPartial;
    await onLineAction(latest, action);
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

  String? _buildSettlementDetails(_CustomerLine line) {
    final parts = <String>[];
    if (line.sourceKindLabel != null &&
        line.sourceKindLabel!.trim().isNotEmpty) {
      parts.add('نوع العملية: ${line.sourceKindLabel}');
    }
    final service = _extractServiceLine(line.details);
    if (service != null) parts.add(service);
    if (line.remainingAfter != null) {
      parts.add(
        'المتبقي بعد التحصيل: ${line.remainingAfter!.toStringAsFixed(2)}',
      );
    }
    if (parts.isEmpty) return null;
    return parts.join(' | ');
  }

  String? _compactDetailsForLine(_CustomerLine line) {
    if (line.lineType == _CustomerLineType.claimOpen) {
      return line.details != null ? _stripSystemTags(line.details!) : null;
    }
    switch (line.txnKind) {
      case 'transfer':
        final requiredLine = _extractDetailPart(
          line.details,
          'المطلوب من العميل:',
        );
        final sentLine = _extractDetailPart(line.details, 'المحوّل للعميل:');
        final feeLine = _extractDetailPart(line.details, 'عمولة العميل:');
        final parts = <String>[];
        if (requiredLine != null) parts.add(requiredLine);
        if (sentLine != null) parts.add(sentLine);
        if (feeLine != null && !feeLine.endsWith(': 0.00')) parts.add(feeLine);
        return parts.isEmpty ? null : parts.join(' | ');
      case 'receive':
        final amountLine = _extractDetailPart(line.details, 'المبلغ المستلم:');
        final feeLine = _extractDetailPart(line.details, 'العمولة/الربح:');
        final parts = <String>[];
        if (amountLine != null) parts.add(amountLine);
        if (feeLine != null && !feeLine.endsWith(': 0.00')) parts.add(feeLine);
        return parts.isEmpty ? null : parts.join(' | ');
      case 'fawry_cash':
      case 'fawry_credit':
        final service = _extractServiceLine(line.details);
        final parts = <String>[];
        if (service != null) parts.add(service);
        parts.add('الإجمالي: ${line.amount.toStringAsFixed(2)}');
        return parts.join(' | ');
      case 'claim_collect':
      case 'claim_pay':
        return _buildSettlementDetails(line);
      default:
        if (line.details == null) return null;
        final trimmed = _stripSystemTags(line.details!);
        return trimmed.isEmpty ? null : trimmed;
    }
  }

  Map<_CustomerLine, double> _computeBalances(List<_CustomerLine> lines) {
    final sorted = List<_CustomerLine>.from(lines)
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        final aId = a.txnId ?? a.claimId ?? 0;
        final bId = b.txnId ?? b.claimId ?? 0;
        return aId.compareTo(bId);
      });
    double running = 0;
    final map = <_CustomerLine, double>{};
    for (final l in sorted) {
      running += l.side == _LineSide.receivable ? l.amount : -l.amount;
      map[l] = running;
    }
    return map;
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

  String _lineChipLabel(_CustomerLine line) {
    if (line.lineType == _CustomerLineType.claimOpen) {
      return line.claimType == 'receivable' ? 'مستحق (عليه)' : 'مستحق (له)';
    }
    if (line.txnKind == 'claim_collect') return 'تحصيل';
    if (line.txnKind == 'claim_pay') return 'سداد';
    if (line.txnKind == 'transfer') {
      return line.txnStatus == 'pending' ? 'تحويل معلّق' : 'تحويل';
    }
    if (line.txnKind == 'receive') {
      return line.txnStatus == 'pending' ? 'استلام معلّق' : 'استلام';
    }
    if (line.txnKind == 'fawry_cash') return 'فوري نقدي';
    if (line.txnKind == 'fawry_credit') {
      return line.txnStatus == 'pending' ? 'فوري آجل معلّق' : 'فوري آجل';
    }
    return line.title;
  }

  Color _lineChipColor(_CustomerLine line) {
    if (line.txnStatus == 'pending') {
      return const Color(0xFFB45309);
    }
    switch (line.txnKind) {
      case 'transfer':
        return const Color(0xFF2563EB);
      case 'receive':
        return const Color(0xFF0EA5E9);
      case 'fawry_cash':
        return const Color(0xFFF59E0B);
      case 'fawry_credit':
        return const Color(0xFF10B981);
      case 'claim_collect':
        return const Color(0xFF16A34A);
      case 'claim_pay':
        return const Color(0xFFDC2626);
      default:
        return line.side == _LineSide.receivable
            ? const Color(0xFF047857)
            : const Color(0xFFB91C1C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final netLabel = customer.net >= 0 ? 'الصافي عليه' : 'الصافي له';
    final netValue = customer.net >= 0 ? customer.net : -customer.net;
    final netColor = customer.net >= 0
        ? const Color(0xFF047857)
        : const Color(0xFFB91C1C);
    final balances = _computeBalances(customer.lines);
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: onTransferPending,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('تحويل معلّق'),
              ),
              ElevatedButton.icon(
                onPressed: onReceivePending,
                icon: const Icon(Icons.call_received),
                label: const Text('استلام معلّق'),
              ),
              ElevatedButton.icon(
                onPressed: onFawryCredit,
                icon: const Icon(Icons.flash_on),
                label: const Text('فوري آجل'),
              ),
              ElevatedButton.icon(
                onPressed: onReport,
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('تقرير العميل'),
              ),
                ElevatedButton.icon(
                  onPressed: _quickSettleLatestClaim,
                  icon: const Icon(Icons.done_all),
                  label: const Text('تسوية آخر مستحق'),
                ),
                ElevatedButton.icon(
                  onPressed: _openAttachments,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('مرفقات العميل'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('الكل', _CustomerLineFilter.all),
              _filterChip('المستحقات', _CustomerLineFilter.claims),
              _filterChip('التحصيل/السداد', _CustomerLineFilter.settlements),
              _filterChip('المعلّق', _CustomerLineFilter.pending),
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
                        final date =
                            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                        final amountSign = line.side == _LineSide.receivable
                            ? '+'
                            : '-';
                        final amountColor = line.side == _LineSide.receivable
                            ? const Color(0xFF047857)
                            : const Color(0xFFB91C1C);
                        final amountBg = amountColor.withValues(alpha: 0.12);
                        final balance = balances[line] ?? customer.net;
                        final balanceColor = balance >= 0
                            ? const Color(0xFF047857)
                            : const Color(0xFFB91C1C);
                        final balanceBg = balanceColor.withValues(alpha: 0.12);
                        final balanceLabel = balance.toStringAsFixed(2);

                        final actions = <PopupMenuEntry<_LineAction>>[];
                        final isSettlement =
                            line.txnKind == 'claim_collect' ||
                            line.txnKind == 'claim_pay';
                        final chipLabel = _lineChipLabel(line);
                        final chipColor = _lineChipColor(line);
                        final displayTitle = isSettlement
                            ? (line.txnKind == 'claim_collect'
                                  ? 'تحصيل مستحق'
                                  : 'سداد مستحق')
                            : line.title;
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
                              child: Text('تنفيذ المعلّق'),
                            ),
                          );
                          actions.add(
                            const PopupMenuItem(
                              value: _LineAction.cancelPending,
                              child: Text('إلغاء المعلّق'),
                            ),
                          );
                        }

                        final busy =
                            (line.claimId != null &&
                                busyIds.contains(line.claimId)) ||
                            (line.txnId != null &&
                                busyIds.contains(line.txnId));

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
                                  text:
                                      '$amountSign${line.amount.toStringAsFixed(2)}',
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
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: chipColor.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  chipLabel,
                                                  style: TextStyle(
                                                    color: chipColor,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                displayTitle,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if ((displayDetails ?? '')
                                                  .trim()
                                                  .isNotEmpty)
                                                Text(
                                                  displayDetails!.trim(),
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                              // تفاصيل فقط بدون مرجع/حالة لعرض مبسط
                                            ],
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
          background: const Color(0xFF1E40AF).withValues(alpha: 0.08),
          textColor: const Color(0xFF1E40AF),
          align: Alignment.center,
          bold: true,
        ),
        _tableCell(
          text: 'المبلغ',
          flex: 2,
          background: const Color(0xFF1E40AF).withValues(alpha: 0.08),
          textColor: const Color(0xFF1E40AF),
          align: Alignment.center,
          bold: true,
        ),
        _tableCell(
          text: 'التفاصيل',
          flex: 4,
          background: const Color(0xFF1E40AF).withValues(alpha: 0.08),
          textColor: const Color(0xFF1E40AF),
          align: Alignment.center,
          bold: true,
        ),
        _tableCell(
          text: 'الرصيد',
          flex: 2,
          background: const Color(0xFF1E40AF).withValues(alpha: 0.08),
          textColor: const Color(0xFF1E40AF),
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

class _CustomerAttachmentsSheet extends StatefulWidget {
  final _CustomerBucket customer;
  final String customerKey;

  const _CustomerAttachmentsSheet({
    required this.customer,
    required this.customerKey,
  });

  @override
  State<_CustomerAttachmentsSheet> createState() =>
      _CustomerAttachmentsSheetState();
}

class _CustomerAttachmentsSheetState extends State<_CustomerAttachmentsSheet> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CustomerAttachment> _items = [];

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
      final items = await AppDb.instance.listCustomerAttachments(
        customerKey: widget.customerKey,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addAttachment() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر قراءة مسار الملف')));
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDb.instance.addCustomerAttachment(
        customerKey: widget.customerKey,
        customerName: widget.customer.name,
        customerPhone: widget.customer.phone,
        sourcePath: path,
        displayName: file.name,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttachment(CustomerAttachment att) async {
    final f = File(att.filePath);
    if (!await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('الملف غير موجود')));
      return;
    }
    await OpenFilex.open(att.filePath);
  }

  Future<void> _deleteAttachment(CustomerAttachment att) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المرفق'),
        content: Text('حذف ${att.fileName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AppDb.instance.deleteCustomerAttachment(att.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.75;
    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'مرفقات العميل',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _addAttachment,
                  icon: const Icon(Icons.add),
                  tooltip: 'إضافة ملف',
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text('العميل: ${widget.customer.name}'),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 8),
            if (!_loading && _items.isEmpty)
              const Center(child: Text('لا توجد مرفقات بعد')),
            if (_items.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  // ignore: unnecessary_underscores
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final item = _items[idx];
                    final date =
                        '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}-${item.createdAt.day.toString().padLeft(2, '0')}';
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(item.fileName),
                      subtitle: Text(date),
                      onTap: () => _openAttachment(item),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'open') {
                            _openAttachment(item);
                          } else if (v == 'delete') {
                            _deleteAttachment(item);
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'open', child: Text('فتح')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
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
}

class _CustomerBucket {
  final String name;
  final String? phone;

  double receivableClaims = 0;
  double payableClaims = 0;
  double receivablePending = 0;
  double payablePending = 0;
  final List<_CustomerLine> lines = [];
  DateTime? lastActivity;

  _CustomerBucket({required this.name, this.phone});

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
