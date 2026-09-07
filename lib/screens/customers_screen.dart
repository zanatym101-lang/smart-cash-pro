import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../application/write_gateway/clean_write_gateway.dart';
import '../application/write_gateway/write_intents.dart';
import '../data/app_db.dart';
import '../data/report_exporter.dart';
import '../data/reporting.dart';
import '../models/transaction.dart';
import '../models/claim.dart';
import '../models/customer_attachment.dart';
import '../widgets/app_title.dart';
import 'customer_account/customer_account_builder.dart';
import 'customer_account/customer_account_models.dart';
import 'customer_report_screen.dart';
import 'receive_screen.dart';
import 'transfer_screen.dart';
import '../data/sqlite/customer_adjustments_repository.dart';
import '../domain/models/customer_account.dart' as domain;
import 'customer_adjustment_dialog.dart';

String _stripSystemTags(String input) {
  var v = input;
  v = v.replaceAllMapped(
    RegExp(
      r'settlement_note:\s*(.+?)(?=\s+-\s+(?:claim_id|pending_txn):\d+|$)',
    ),
    (m) => 'ملاحظة التسوية: ${(m.group(1) ?? '').trim()}',
  );
  v = v.replaceAll(RegExp(r'claim_id:\d+'), '');
  v = v.replaceAll(RegExp(r'pending_txn:\d+'), '');
  v = v.replaceAll(RegExp(r'\s+-\s+-+'), ' - ');
  v = v.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return v;
}

enum _CustomerListFilter { all, receivable, payable, pending, archived }
enum _CustomerSort { recentActivity, highestReceivable, highestPayable, oldestActivity }

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
  _CustomerSort _sort = _CustomerSort.recentActivity;

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
    return c.key;
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

  int _customerLineIdentity(_CustomerLine line) {
    return line.txnId ?? line.claimId ?? 0;
  }

  DateTime _customerLineStoryAnchorDate(_CustomerLine line) {
    return line.storyAnchorDate ?? line.date;
  }

  int _customerLineGroupIdentity(_CustomerLine line) {
    if (line.storySourceTxnId != null) return line.storySourceTxnId!;
    if (line.txnId != null) return line.txnId!;
    return -(line.claimId ?? 0);
  }

  int _customerLineStoryStage(_CustomerLine line) {
    if (line.storySourceTxnId == null) return 99;
    if (line.lineType == _CustomerLineType.claimOpen) return 2;
    if (line.lineType == _CustomerLineType.txn &&
        line.txnId == line.storySourceTxnId &&
        (line.txnKind == 'transfer' ||
            line.txnKind == 'receive' ||
            line.txnKind == 'fawry_credit')) {
      return 0;
    }
    if (line.lineType == _CustomerLineType.txn &&
        (line.txnKind == 'claim_collect' || line.txnKind == 'claim_pay')) {
      return 1;
    }
    return 99;
  }

  int _compareCustomerLines(_CustomerLine a, _CustomerLine b) {
    final aGroupDate = _customerLineStoryAnchorDate(a);
    final bGroupDate = _customerLineStoryAnchorDate(b);
    final groupDate = bGroupDate.compareTo(aGroupDate);
    if (groupDate != 0) return groupDate;

    final aStory = a.storySourceTxnId;
    final bStory = b.storySourceTxnId;
    if (aStory != null && bStory != null && aStory == bStory) {
      final stage = _customerLineStoryStage(
        b,
      ).compareTo(_customerLineStoryStage(a));
      if (stage != 0) return stage;
      final date = b.date.compareTo(a.date);
      if (date != 0) return date;
      return _customerLineIdentity(b).compareTo(_customerLineIdentity(a));
    }

    final groupIdentity = _customerLineGroupIdentity(
      b,
    ).compareTo(_customerLineGroupIdentity(a));
    if (groupIdentity != 0) return groupIdentity;

    final date = b.date.compareTo(a.date);
    if (date != 0) return date;
    return _customerLineIdentity(b).compareTo(_customerLineIdentity(a));
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
      final wallets = await AppDb.instance.listWallets();
      final adjustments = await CustomerAdjustmentsRepository(AppDb.instance.sqlite).getAllAdjustments();
      final txnById = {for (final t in txns) t.id: t};
      final claimById = {for (final c in claims) c.id: c};
      final walletById = {for (final w in wallets) w.id: w};
      final claimSourceTxnById = <int, int?>{
        for (final c in claims) c.id: c.sourceTxnId,
      };

      final settlementByPending = <int, List<Txn>>{};
      final settlementByClaim = <int, List<Txn>>{};
      final settledByClaimId = <int, double>{};
      final storyAnchorDateByTxnId = <int, DateTime>{};
      for (final t in txns) {
        storyAnchorDateByTxnId[t.id] = t.entryDate;
      }
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
            : claim.amount > totalSettled
            ? claim.amount
            : totalSettled;
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
      final deferredSourceTxnIds = settlementByPending.keys.toSet();

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
        final sourceTxn = c.sourceTxnId == null ? null : txnById[c.sourceTxnId];
        if (c.status == 'open' && c.sourceTxnId != null) {
          openClaimSourceTxnIds.add(c.sourceTxnId!);
          deferredSourceTxnIds.add(c.sourceTxnId!);
        }
        final phone =
            _extractPhone(c.note) ??
            _extractPhone(sourceTxn?.note) ??
            _extractPhone(sourceTxn?.reference);
        final b = bucketFor(name: name, phone: phone);
        final settledForClaim = settledByClaimId[c.id] ?? 0;
        final displayAmount = c.status == 'open'
            ? c.amount + settledForClaim
            : c.amount > settledForClaim
            ? c.amount
            : settledForClaim;
        if (c.type == 'receivable') {
          if (c.status == 'open') b.receivableClaims += c.amount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.receivable,
              amount: displayAmount,
              title: 'مستحق',
              details: _detailsForClaimLine(c),
              ref: 'Claim#${c.id}',
              lineType: _CustomerLineType.claimOpen,
              claimId: c.id,
              claimType: c.type,
              txnStatus: c.status,
              storySourceTxnId: c.sourceTxnId,
              storyAnchorDate: c.sourceTxnId == null
                  ? null
                  : storyAnchorDateByTxnId[c.sourceTxnId!],
            ),
          );
        } else if (c.type == 'payable') {
          if (c.status == 'open') b.payableClaims += c.amount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.payable,
              amount: displayAmount,
              title: 'مستحق',
              details: _detailsForClaimLine(c),
              ref: 'Claim#${c.id}',
              lineType: _CustomerLineType.claimOpen,
              claimId: c.id,
              claimType: c.type,
              txnStatus: c.status,
              storySourceTxnId: c.sourceTxnId,
              storyAnchorDate: c.sourceTxnId == null
                  ? null
                  : storyAnchorDateByTxnId[c.sourceTxnId!],
            ),
          );
        }
      }

      for (final adj in adjustments) {
        final name = adj.customerId.trim();
        if (name.isEmpty) continue;
        final b = bucketFor(
          name: name,
          phone: _extractPhone(adj.note),
        );
        final amountDouble = adj.amount.toDouble();
        final isForUs = adj.type == domain.CustomerAdjustmentType.add;
        b.lines.add(
          _CustomerLine(
            date: adj.date,
            side: isForUs ? _LineSide.receivable : _LineSide.payable,
            amount: amountDouble,
            displayAmount: amountDouble,
            title: isForUs ? 'تسوية (إضافة)' : 'تسوية (خصم)',
            details: adj.note ?? 'تسوية حساب',
            ref: 'Adj#${adj.id}',
            lineType: _CustomerLineType.adjustment,
            txnStatus: 'posted',
          ),
        );
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
        final claimIdFromNote = _extractClaimIdFromNote(t.note);
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
        if ((name.isEmpty || (phone ?? '').trim().isEmpty) &&
            claimIdFromNote != null) {
          final claim = claimById[claimIdFromNote];
          if (claim != null) {
            if (name.isEmpty) {
              name = claim.party.trim();
            }
            phone ??= _extractPhone(claim.note);
            final sourceTxnId = claim.sourceTxnId;
            if ((phone ?? '').trim().isEmpty && sourceTxnId != null) {
              final src = txnById[sourceTxnId];
              if (src != null) {
                phone = _extractPhone(src.note) ?? _extractPhone(src.reference);
              }
            }
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
            if (dueBase > 0) {
              b.receivablePending += due;
              b.lines.add(
                _CustomerLine(
                  date: t.entryDate,
                  side: _LineSide.receivable,
                  amount: dueBase,
                  displayAmount: dueBase,
                  title: 'تحويل آجل',
                  details: _detailsForTransfer(t),
                  ref: 'Txn#${t.id}',
                  lineType: _CustomerLineType.txn,
                  txnId: t.id,
                  txnKind: t.kind,
                  txnStatus: t.status,
                  remainingAfter: due,
                  storySourceTxnId: t.id,
                  storyAnchorDate: t.entryDate,
                  walletId: t.walletFromId ?? t.walletToId,
                  walletName: walletById[t.walletFromId ?? t.walletToId]?.name,
                  walletPhone: walletById[t.walletFromId ?? t.walletToId]?.phone,
                ),
              );
            }
            continue;
          }

          if (t.kind == 'receive') {
            final dueBase = _pendingReceiveDue(t);
            final settled = pendingSettled[t.id] ?? 0;
            final due = (dueBase - settled).clamp(0, 1e18).toDouble();
            if (dueBase > 0) {
              b.payablePending += due;
              b.lines.add(
                _CustomerLine(
                  date: t.entryDate,
                  side: _LineSide.payable,
                  amount: dueBase,
                  displayAmount: dueBase,
                  title: 'استلام آجل',
                  details: _detailsForReceive(t),
                  ref: 'Txn#${t.id}',
                  lineType: _CustomerLineType.txn,
                  txnId: t.id,
                  txnKind: t.kind,
                  txnStatus: t.status,
                  remainingAfter: due,
                  storySourceTxnId: t.id,
                  storyAnchorDate: t.entryDate,
                  walletId: t.walletFromId ?? t.walletToId,
                  walletName: walletById[t.walletFromId ?? t.walletToId]?.name,
                  walletPhone: walletById[t.walletFromId ?? t.walletToId]?.phone,
                ),
              );
            }
            continue;
          }

          if (t.kind == 'fawry_credit') {
            final dueBase = t.amount + t.clientFee;
            final settled = pendingSettled[t.id] ?? 0;
            final due = (dueBase - settled).clamp(0, 1e18).toDouble();
            if (dueBase > 0) {
              b.receivablePending += due;
              b.lines.add(
                _CustomerLine(
                  date: t.entryDate,
                  side: _LineSide.receivable,
                  amount: dueBase,
                  displayAmount: dueBase,
                  title: 'فوري آجل',
                  details: _detailsForFawry(t),
                  ref: 'Txn#${t.id}',
                  lineType: _CustomerLineType.txn,
                  txnId: t.id,
                  txnKind: t.kind,
                  txnStatus: t.status,
                  remainingAfter: due,
                  storySourceTxnId: t.id,
                  storyAnchorDate: t.entryDate,
                  walletId: t.walletFromId ?? t.walletToId,
                  walletName: walletById[t.walletFromId ?? t.walletToId]?.name,
                  walletPhone: walletById[t.walletFromId ?? t.walletToId]?.phone,
                ),
              );
            }
            continue;
          }
        }

        final pendingRef = pendingRefFromNote;
        final claimIdForTxn = claimIdFromNote;
        final pendingSource = pendingRef != null ? txnById[pendingRef] : null;
        final remainingAfter = settlementRemainingByTxnId[t.id];
        final sourceKindLabel = settlementSourceLabelByTxnId[t.id];
        final originatedDeferred =
            t.status == 'posted' && deferredSourceTxnIds.contains(t.id);
        final storySourceTxnId =
            pendingRef ??
            claimSourceTxnById[claimIdForTxn] ??
            (originatedDeferred ? t.id : null);
        final customerFacingAmount = originatedDeferred
            ? (t.kind == 'transfer'
                  ? _pendingTransferDue(t)
                  : t.kind == 'receive'
                  ? _pendingReceiveDue(t)
                  : t.kind == 'fawry_credit'
                  ? t.amount + t.clientFee
                  : _txnVolume(t))
            : _txnVolume(t);

        b.lines.add(
          _CustomerLine(
            date: t.entryDate,
            side: _txnSide(t),
            amount: customerFacingAmount,
            displayAmount: customerFacingAmount,
            title: originatedDeferred ? pendingLabel(t) : _kindLabel(t),
            details: t.kind == 'transfer'
                ? _detailsForTransfer(t)
                : t.kind == 'receive'
                ? _detailsForReceive(t)
                : (t.kind == 'fawry_cash' || t.kind == 'fawry_credit')
                ? _detailsForFawry(t)
                : (t.kind == 'claim_collect' || t.kind == 'claim_pay')
                ? (pendingSource != null
                      ? _detailsForPendingSettlement(t, pendingSource)
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
            storySourceTxnId: storySourceTxnId,
            storyAnchorDate: storySourceTxnId == null
                ? null
                : storyAnchorDateByTxnId[storySourceTxnId],
            walletId: t.walletFromId ?? t.walletToId,
            walletName: walletById[t.walletFromId ?? t.walletToId]?.name,
            walletPhone: walletById[t.walletFromId ?? t.walletToId]?.phone,
          ),
        );
      }

      final customers = map.values.where((c) => c.lines.isNotEmpty).toList();
      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: txns,
        claims: claims,
        adjustments: adjustments,
      );
      final accountByKey = <String, CustomerAccount>{
        for (final account in accounts)
          _bucketKey(
            name: account.summary.customerName,
            phone: account.summary.phone,
          ): account,
      };
      for (final c in customers) {
        c.account = accountByKey[_customerKeyFor(c)];
        c.lines.sort(_compareCustomerLines);
        if (c.lines.isNotEmpty) {
          c.lastActivity = c.lines
              .map((l) => l.date)
              .reduce((a, b) => a.isAfter(b) ? a : b);
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

  String? _detailsForPendingSettlement(Txn settlement, Txn source) {
    final parts = <String>[];
    final sourceDetails = _detailsForPendingSource(source);
    if (sourceDetails != null && sourceDetails.trim().isNotEmpty) {
      parts.add(sourceDetails.trim());
    }
    final settlementDetails = _detailsForClaimTxn(settlement);
    if (settlementDetails.trim().isNotEmpty) {
      parts.add(settlementDetails.trim());
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  String _kindLabel(Txn t) {
    switch (t.kind) {
      case 'transfer':
        return t.status == 'pending' ? 'تحويل آجل' : 'تحويل';
      case 'receive':
        return t.status == 'pending' ? 'استلام آجل' : 'استلام';
      case 'fawry_cash':
        return 'فوري نقدي';
      case 'fawry_credit':
        return 'فوري آجل';
      case 'claim_collect':
        return 'تحصيل';
      case 'claim_pay':
        return 'سداد';
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

  double _lineDisplayAmount(_CustomerLine line) {
    return line.displayAmount ?? line.amount;
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

    // عند البحث: يبحث في كل العملاء (نشطين + أرشيف) بغض النظر عن الفلتر المحدد
    if (q.isNotEmpty) {
      base = base.where((c) {
        final name = c.name.toLowerCase();
        final phone = (c.phone ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q);
      });
    } else {
      // بدون بحث: طبّق الفلتر المحدد
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
    }

    final list = base.toList();
    list.sort((a, b) {
      final aPinned = _pinnedCustomers.contains(_customerKeyFor(a));
      final bPinned = _pinnedCustomers.contains(_customerKeyFor(b));
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      
      switch (_sort) {
        case _CustomerSort.highestReceivable:
          return b.receivableTotal.compareTo(a.receivableTotal);
        case _CustomerSort.highestPayable:
          return b.payableTotal.compareTo(a.payableTotal);
        case _CustomerSort.oldestActivity:
          final aDate = a.lastActivity ?? DateTime.now();
          final bDate = b.lastActivity ?? DateTime.now();
          return aDate.compareTo(bDate);
        case _CustomerSort.recentActivity:
          final aDate = a.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
      }
    });
    return list;
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
                  FocusScope.of(ctx).unfocus();
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

  Future<_SettlementNoteInput?> _confirmSettlementWithNote({
    required String title,
    required String body,
    required String okText,
  }) async {
    var noteText = '';
    final result = await showDialog<_SettlementNoteInput>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => noteText = value,
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
              final note = noteText.trim();
              FocusScope.of(ctx).unfocus();
              Navigator.of(
                ctx,
              ).pop(_SettlementNoteInput(note: note.isEmpty ? null : note));
            },
            child: Text(okText),
          ),
        ],
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    return result;
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
          withNote: true,
        );
        if (result == null) return;
        await run(() async {
          if (line.pendingTxnId != null) {
            await CleanWriteGateway.appDbBridge().execute(
              RollbackTransactionIntent(
                transactionId: line.txnId!.toString(),
                rollbackType: RollbackTransactionType.pendingSettlement,
              ),
            );
            await CleanWriteGateway.appDbBridge().execute(
              CreateSettlementIntent(
                itemId: line.pendingTxnId!.toString(),
                settlementId:
                    'pending-${line.pendingTxnId}-settlement-${DateTime.now().microsecondsSinceEpoch}',
                sourceType: line.side == _LineSide.receivable
                    ? SettlementSourceType.deferredTransfer
                    : SettlementSourceType.deferredReceive,
                amount: result.amount,
                note: result.note,
              ),
            );
            return;
          }
          if (line.claimId != null) {
            await CleanWriteGateway.appDbBridge().execute(
              RollbackTransactionIntent(
                transactionId: line.txnId!.toString(),
                rollbackType: RollbackTransactionType.claimSettlement,
              ),
            );
            await CleanWriteGateway.appDbBridge().execute(
              SettleClaimIntent(
                claimId: line.claimId!.toString(),
                settlementId:
                    'claim-${line.claimId}-settlement-${DateTime.now().microsecondsSinceEpoch}',
                amount: result.amount,
                note: result.note,
              ),
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
          await CleanWriteGateway.appDbBridge().execute(
            RollbackTransactionIntent(
              transactionId: line.txnId!.toString(),
              rollbackType: RollbackTransactionType.pendingSettlement,
            ),
          );
          return;
        }
        if (line.claimId != null) {
          await CleanWriteGateway.appDbBridge().execute(
            RollbackTransactionIntent(
              transactionId: line.txnId!.toString(),
              rollbackType: RollbackTransactionType.claimSettlement,
            ),
          );
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
        await CleanWriteGateway.appDbBridge().execute(
          RollbackTransactionIntent(transactionId: line.txnId!.toString()),
        );
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
      final result = isFull
          ? await _confirmSettlementWithNote(
              title: isReceivable ? 'تحصيل مستحق كلي' : 'سداد مستحق كلي',
              body:
                  'سيتم ${isReceivable ? 'تحصيل' : 'سداد'} المبلغ المتبقي كاملًا: ${remaining.toStringAsFixed(2)}.',
              okText: isReceivable ? 'تحصيل كلي' : 'سداد كلي',
            ).then(
              (value) => value == null
                  ? null
                  : _SettlementAmountInput(amount: remaining, note: value.note),
            )
          : await _promptSettlementAmount(
              actionLabel: actionLabel,
              party: party,
              remaining: remaining,
              withNote: true,
            );
      if (result == null) return;

      await run(() async {
        await CleanWriteGateway.appDbBridge().execute(
          SettleClaimIntent(
            claimId: line.claimId!.toString(),
            settlementId:
                'claim-${line.claimId}-settlement-${DateTime.now().microsecondsSinceEpoch}',
            amount: result.amount,
            note: result.note,
          ),
        );
      });
      return;
    }

    if (line.lineType == _CustomerLineType.txn && (line.txnStatus == 'pending' || line.txnKind == 'claim_collect' || line.txnKind == 'claim_pay')) {
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
          remaining: line.remainingAfter ?? line.amount,
          withNote: true,
        );
        if (result == null) return;
        await run(() async {
          await CleanWriteGateway.appDbBridge().execute(
            CreateSettlementIntent(
              itemId: (line.pendingTxnId ?? line.txnId!).toString(),
              settlementId:
                  'pending-${(line.pendingTxnId ?? line.txnId!)}-settlement-${DateTime.now().microsecondsSinceEpoch}',
              sourceType: line.side == _LineSide.receivable
                  ? SettlementSourceType.deferredTransfer
                  : SettlementSourceType.deferredReceive,
              amount: result.amount,
              note: result.note,
            ),
          );
        });
      } else if (action == _LineAction.collectPendingFull ||
          action == _LineAction.payPendingFull) {
        final isCollect = action == _LineAction.collectPendingFull;
        final confirmation = await _confirmSettlementWithNote(
          title: isCollect ? 'تحصيل كلي للآجل' : 'سداد كلي للآجل',
          body:
              'سيتم ${isCollect ? 'تحصيل' : 'سداد'} المبلغ المتبقي كاملًا ثم إغلاق العملية الآجلة رقم #${line.txnId}.',
          okText: isCollect ? 'تحصيل كلي' : 'سداد كلي',
        );
        if (confirmation == null) return;
        await run(() async {
          await CleanWriteGateway.appDbBridge().execute(
            CreateSettlementIntent(
              itemId: (line.pendingTxnId ?? line.txnId!).toString(),
              settlementId:
                  'pending-${(line.pendingTxnId ?? line.txnId!)}-settlement-${DateTime.now().microsecondsSinceEpoch}',
              sourceType: line.side == _LineSide.receivable
                  ? SettlementSourceType.deferredTransfer
                  : SettlementSourceType.deferredReceive,
              amount: line.remainingAfter ?? line.amount,
              fullSettlement: true,
              note: confirmation.note,
            ),
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
          await CleanWriteGateway.appDbBridge().execute(
            ConfirmPendingIntent(
              pendingTxnId: line.txnId!.toString(),
              claimId:
                  'pending-${line.txnId}-claim-${DateTime.now().microsecondsSinceEpoch}',
            ),
          );
        });
      } else if (action == _LineAction.cancelPending) {
        final ok = await _confirmAction(
          title: 'إلغاء عملية معلّقة',
          body: 'سيتم إلغاء العملية رقم #${line.txnId}.',
          okText: 'إلغاء',
        );
        if (!ok) return;
        await run(() async {
          await CleanWriteGateway.appDbBridge().execute(
            CancelPendingIntent(pendingTxnId: line.txnId!.toString()),
          );
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
        onAdjust: () async {
          Navigator.of(ctx).pop();
          await CustomerAdjustmentDialog.show(
            context,
            customerName: c.name,
            customerPhone: c.phone,
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
        return 'مغلق';
      case 'pending':
        return 'آجل';
      case 'reversed': return 'معكوس'; case 'reverse_entry': return 'قيد عكسي'; case 'rolled_back':
        return 'ملغي';
      default:
        return trimmed;
    }
  }

  void _showLineDetails(_CustomerLine line) {
    final d = line.date;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    
    String sideLabel;
    if (line.side == _LineSide.receivable) {
      sideLabel = line.lineType == _CustomerLineType.claimOpen ? 'مستحقات (لنا)' : 'لنا';
    } else {
      sideLabel = line.lineType == _CustomerLineType.claimOpen ? 'مستحقات (علينا)' : 'علينا';
    }

    final statusLabel = _txnStatusLabel(line.txnStatus);
    final details = line.details == null ? null : _stripSystemTags(line.details!);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل العملية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('العنوان: ${line.title}'),
              Text('التاريخ: $date'),
              Text('النوع: $sideLabel'),
              Text('المبلغ: ${_lineDisplayAmount(line).toStringAsFixed(2)}'),
              Text('المرجع: ${line.ref}'),
              if (statusLabel != null) Text('الحالة: $statusLabel'),
              if (line.walletName != null || line.walletPhone != null)
                Text('المحفظة/الخزنة: ${[line.walletName, line.walletPhone].where((e) => e != null && e.trim().isNotEmpty).join(' - ')}'),
              if (details != null && details.trim().isNotEmpty)
                Text('التفاصيل: $details'),
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
          PopupMenuButton<_CustomerSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'ترتيب القائمة',
            onSelected: (val) => setState(() => _sort = val),
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: _CustomerSort.recentActivity, child: Text('آخر تعامل (الأحدث)')),
              PopupMenuItem(value: _CustomerSort.oldestActivity, child: Text('أقدم تعامل (الأقدم)')),
              PopupMenuItem(value: _CustomerSort.highestReceivable, child: Text('الأكثر مديونية (لنا)')),
              PopupMenuItem(value: _CustomerSort.highestPayable, child: Text('الأكثر دائنية (علينا)')),
            ],
          ),
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
                  'أرشيف',
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
    final net = c.net;
    final netAbs = net.abs();
    final isPinned = _isPinned(c);
    final showWarning =
        _customerAlertThreshold > 0 &&
        (c.receivableTotal >= _customerAlertThreshold ||
            c.payableTotal >= _customerAlertThreshold);
    final last = c.lastActivity;
    final lastText = last == null
        ? 'لا توجد حركة'
        : 'آخر حركة: ${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}';
    final archivedTag = showArchivedLabel ? ' · مؤرشف' : '';

    // نص المتبقي: إما "لنا: +X.XX ج.م" أو "علينا: -X.XX ج.م" أو "خالص / متزن (0.00 ج.م)"
    final String remainingText;
    final Color remainingColor;
    if (netAbs < 0.001) {
      remainingText = 'خالص / متزن (0.00 ج.م)';
      remainingColor = const Color(0xFF0369A1);
    } else if (net > 0) {
      remainingText = 'لنا: +${netAbs.toStringAsFixed(2)} ج.م';
      remainingColor = const Color(0xFF047857);
    } else {
      remainingText = 'علينا: -${netAbs.toStringAsFixed(2)} ج.م';
      remainingColor = const Color(0xFFB91C1C);
    }

    return Card(
      child: ListTile(
        onTap: () => _openCustomer(c),
        leading: CircleAvatar(
          backgroundColor: net > 0.001
              ? const Color(0xFFD1FAE5)
              : net < -0.001
                  ? const Color(0xFFFFE4E4)
                  : const Color(0xFFDBEAFE),
          child: Icon(
            Icons.person,
            color: net > 0.001
                ? const Color(0xFF047857)
                : net < -0.001
                    ? const Color(0xFFB91C1C)
                    : const Color(0xFF0369A1),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${c.name}$archivedTag',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lastText,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 2),
            Text(
              'لنا: ${c.receivableTotal.toStringAsFixed(2)} | علينا: ${c.payableTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 2),
            Text(
              remainingText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: remainingColor,
              ),
            ),
          ],
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
  final VoidCallback onTransfer;
  final VoidCallback onReceive;
  final VoidCallback onAdjust;
  final VoidCallback onTransferPending;
  final VoidCallback onReceivePending;
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
    required this.onAdjust,
    required this.onTransferPending,
    required this.onReceivePending,
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

enum _CustomerAccountFilter {
  all,
  forUs,
  againstUs,
  deferredTransfers,
  deferredReceives,
  claims,
  settlements,
  archivedClosed,
}

enum _OpenSettlementTargetKind { deferred, claim }

enum _SettlementMode { selectedItems, total }

enum _TotalSettlementOrder {
  oldestFirst,
  newestFirst,
  claimsFirst,
  deferredFirst,
}

class _SettlementAmountInput {
  final double amount;
  final String? note;

  const _SettlementAmountInput({required this.amount, required this.note});
}

class _SettlementNoteInput {
  final String? note;

  const _SettlementNoteInput({required this.note});
}

class _PartialOpenSettlementInput {
  final Map<String, double> amountsByItemId;
  final String? note;

  const _PartialOpenSettlementInput({
    required this.amountsByItemId,
    required this.note,
  });
}

class _TotalSettlementInput {
  final double amount;
  final String? note;
  final _TotalSettlementOrder order;

  const _TotalSettlementInput({
    required this.amount,
    required this.note,
    required this.order,
  });
}

class _CustomerSheetState extends State<_CustomerSheet> {
  _CustomerLineFilter _filter = _CustomerLineFilter.all;
  _CustomerAccountFilter _accountFilter = _CustomerAccountFilter.all;
  bool _showActions = false;
  bool _showAdvancedFilters = false;
  bool _batchBusy = false;

  _CustomerBucket get customer => widget.customer;
  VoidCallback get onTransfer => widget.onTransfer;
  VoidCallback get onReceive => widget.onReceive;
  VoidCallback get onAdjust => widget.onAdjust;
  VoidCallback get onTransferPending => widget.onTransferPending;
  VoidCallback get onReceivePending => widget.onReceivePending;
  VoidCallback get onReport => widget.onReport;
  Future<void> Function(_CustomerLine line, _LineAction action)
  get onLineAction => widget.onLineAction;
  void Function(_CustomerLine line) get onShowDetails => widget.onShowDetails;
  Set<int> get busyIds => widget.busyIds;
  Future<void> Function() get onRefresh => widget.onRefresh;

  double _lineDisplayAmount(_CustomerLine line) {
    return line.displayAmount ?? line.amount;
  }

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
    final cleanDetails = _stripSystemTags(details);
    final m = RegExp(
      r'ملاحظة التسوية:\s*(.+)$',
    ).firstMatch(cleanDetails.trim());
    if (m == null) return null;
    final note = (m.group(1) ?? '').trim();
    return note.isEmpty ? null : note;
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
        await CleanWriteGateway.appDbBridge().execute(
          CreateClaimIntent(
            claimId: 'claim-ui-${DateTime.now().microsecondsSinceEpoch}',
            type: type == 'receivable'
                ? ClaimDirection.receivable
                : ClaimDirection.payable,
            party: customer.name,
            amount: amount,
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            phone: customer.phone,
          ),
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
            /* ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('فوري نقدي'),
              onTap: () => Navigator.of(ctx).pop('fawry_cash'),
            ),
            ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('فوري آجل'),
              onTap: () => Navigator.of(ctx).pop('fawry_credit'),
            ), */
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
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('تسوية حساب'),
              onTap: () => Navigator.of(ctx).pop('adjust'),
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
      case 'claim_receivable':
        await _addClaimForCustomer('receivable');
        return;
      case 'claim_payable':
        await _addClaimForCustomer('payable');
        return;
      case 'adjust':
        onAdjust();
        return;
      default:
        return;
    }
  }

  bool _isOffsetLine(_CustomerLine line) {
    final text = '${line.details ?? ''} ${line.ref} ${line.title}';
    return text.contains('إغلاق تلقائي') ||
        text.contains('مقاصة') ||
        text.contains('إغلاق حساب') ||
        text.contains('offset') ||
        text.contains('تسوية / إغلاق');
  }

  String? _buildSettlementDetails(_CustomerLine line) {
    final isOffset = _isOffsetLine(line);
    final primary = <String>['المبلغ: ${line.amount.toStringAsFixed(2)}'];
    final secondary = <String>[];
    final service = _extractServiceLine(line.details);
    if (line.remainingAfter != null) {
      primary.add('المتبقي: ${line.remainingAfter!.toStringAsFixed(2)}');
    }
    if (isOffset) {
      secondary.add('🔄 مقاصة تسوية داخلية تصفير الحساب إلى 0.00 (بدون حركة نقدية)');
    }
    final settlementNote = _extractSettlementNote(line.details);
    if (settlementNote != null) secondary.add('ملاحظة: $settlementNote');
    if (service != null) secondary.add(service);

    final lines = <String>[primary.join(' | ')];
    if (secondary.isNotEmpty) lines.add(secondary.join(' | '));
    return lines.join('\n');
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
        parts.add('الإجمالي: ${_lineDisplayAmount(line).toStringAsFixed(2)}');
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

  Map<_CustomerLine, double> _computeBalances({
    required List<_CustomerLine> lines,
    required double currentNet,
  }) {
    final map = <_CustomerLine, double>{};
    final deferredStoryIds = lines
        .where(
          (line) =>
              line.txnId != null &&
              line.txnId == line.storySourceTxnId &&
              (line.txnKind == 'transfer' ||
                  line.txnKind == 'receive' ||
                  line.txnKind == 'fawry_credit'),
        )
        .map((line) => line.txnId!)
        .toSet();
    final chronological = [...lines]..sort(_compareSimpleLedgerChronological);
    var runningAfter = 0.0;
    for (final l in chronological) {
      final isDeferredClaimMarker =
          l.lineType == _CustomerLineType.claimOpen &&
          l.storySourceTxnId != null &&
          deferredStoryIds.contains(l.storySourceTxnId);
      final delta = isDeferredClaimMarker
          ? 0
          : (l.side == _LineSide.receivable ? l.amount : -l.amount);
      runningAfter += delta;
      map[l] = runningAfter;
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
    // صفوف التسوية (تحصيل/سداد) تُخفى من كل الفلاتر ماعدا فلتر "التسويات"
    bool isSettlement(_CustomerLine l) =>
        l.txnKind == 'claim_collect' || l.txnKind == 'claim_pay';

    var filtered = switch (_accountFilter) {
      _CustomerAccountFilter.forUs =>
        lines.where((l) => l.side == _LineSide.receivable && !isSettlement(l)).toList(),
      _CustomerAccountFilter.againstUs =>
        lines.where((l) => l.side == _LineSide.payable && !isSettlement(l)).toList(),
      _CustomerAccountFilter.deferredTransfers =>
        lines
            .where((l) => !isSettlement(l) && (l.txnKind == 'transfer' || l.title.contains('تحويل')))
            .toList(),
      _CustomerAccountFilter.deferredReceives =>
        lines
            .where((l) => !isSettlement(l) && (l.txnKind == 'receive' || l.title.contains('استلام')))
            .toList(),
      _CustomerAccountFilter.claims =>
        lines
            .where(
              (l) =>
                  !isSettlement(l) &&
                  (l.lineType == _CustomerLineType.claimOpen || l.claimId != null),
            )
            .toList(),
      _CustomerAccountFilter.settlements =>
        // فلتر "التسويات" فقط يعرض هذه الصفوف
        lines
            .where((l) => l.txnKind == 'claim_collect' || l.txnKind == 'claim_pay')
            .toList(),
      _CustomerAccountFilter.archivedClosed =>
        lines
            .where(
              (l) =>
                  !isSettlement(l) &&
                  (l.txnStatus == 'posted' ||
                   l.txnStatus == 'rolled_back' ||
                   (l.remainingAfter != null && l.remainingAfter! <= 0)),
            )
            .toList(),
			_CustomerAccountFilter.all => lines.toList(),
        // الكل: جميع الصفوف ما عدا صفوف التسوية
    };

    switch (_filter) {
      case _CustomerLineFilter.claims:
        return filtered
            .where(
              (l) =>
                  l.lineType == _CustomerLineType.claimOpen ||
                  l.claimId != null,
            )
            .toList();
      case _CustomerLineFilter.settlements:
        // البحث في القائمة الأصلية (lines) وليس filtered، لأن filtered تحذف صفوف التسوية
        return lines
            .where(
              (l) =>
                  l.lineType == _CustomerLineType.txn &&
                  (l.txnKind == 'claim_collect' || l.txnKind == 'claim_pay'),
            )
            .toList();
      case _CustomerLineFilter.pending:
        return filtered
            .where(
              (l) =>
                  l.lineType == _CustomerLineType.txn &&
                  l.txnStatus == 'pending',
            )
            .toList();
      case _CustomerLineFilter.posted:
        return filtered
            .where(
              (l) =>
                  l.lineType == _CustomerLineType.txn &&
                  l.txnStatus == 'posted',
            )
            .toList();
      case _CustomerLineFilter.all:
        return filtered;
    }
  }

  int _compareSimpleLedgerChronological(_CustomerLine a, _CustomerLine b) {
    final anchor = _simpleLedgerAnchorDate(
      a,
    ).compareTo(_simpleLedgerAnchorDate(b));
    if (anchor != 0) return anchor;
    final story = (a.storySourceTxnId ?? a.txnId ?? -(a.claimId ?? 0))
        .compareTo(b.storySourceTxnId ?? b.txnId ?? -(b.claimId ?? 0));
    if (story != 0) return story;
    final stage = _simpleLedgerStage(a).compareTo(_simpleLedgerStage(b));
    if (stage != 0) return stage;
    final date = a.date.compareTo(b.date);
    if (date != 0) return date;
    return _simpleLedgerIdentity(a).compareTo(_simpleLedgerIdentity(b));
  }

  int _compareSimpleLedgerDisplay(_CustomerLine a, _CustomerLine b) {
    final chronological = _compareSimpleLedgerChronological(a, b);
    return -chronological;
  }

  DateTime _simpleLedgerAnchorDate(_CustomerLine line) {
    return line.storyAnchorDate ?? line.date;
  }

  int _simpleLedgerIdentity(_CustomerLine line) {
    return line.txnId ?? -(line.claimId ?? 0);
  }

  int _simpleLedgerStage(_CustomerLine line) {
    if (line.lineType == _CustomerLineType.claimOpen &&
        line.storySourceTxnId != null &&
        line.txnStatus != 'closed') {
      return 2;
    }
    if (line.txnKind == 'claim_collect' || line.txnKind == 'claim_pay') {
      return 1;
    }
    return 0;
  }

  List<_CustomerLine> buildSimpleCustomerLedger(_CustomerBucket customer) {
    final sorted = [...customer.lines]..sort(_compareSimpleLedgerDisplay);
    return sorted.where((line) {
      final details = (line.details ?? '').toLowerCase();
      final title = line.title.toLowerCase();
      final isClosureMirror = details.contains('مقاصة تسوية') ||
          details.contains('تسوية داخلية بدون حركة نقدية') ||
          title.contains('مقاصة تسوية');
      if (isClosureMirror && line.lineType == _CustomerLineType.txn) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<_CustomerLine> _openSettlementTargets(
    _LineSide side, {
    required _OpenSettlementTargetKind kind,
  }) {
    return buildSimpleCustomerLedger(customer)
        .where((line) {
          if (line.side != side) return false;
          if (line.lineType == _CustomerLineType.claimOpen) {
            return kind == _OpenSettlementTargetKind.claim &&
                line.txnStatus != 'closed' &&
                (line.remainingAfter ?? line.amount) > 0;
          }
          final isDeferred =
              line.lineType == _CustomerLineType.txn &&
              line.txnStatus == 'pending' &&
              (line.txnKind == 'transfer' ||
                  line.txnKind == 'receive' ||
                  line.txnKind == 'fawry_credit');
          return kind == _OpenSettlementTargetKind.deferred &&
              isDeferred &&
              (line.remainingAfter ?? line.amount) > 0;
        })
        .toList(growable: false);
  }

  List<_CustomerLine> _allOpenSettlementTargets(_LineSide side) {
    final seen = <String>{};
    final all = <_CustomerLine>[
      ..._openSettlementTargets(side, kind: _OpenSettlementTargetKind.deferred),
      ..._openSettlementTargets(side, kind: _OpenSettlementTargetKind.claim),
    ];
    return all
        .where((line) {
          final id = _openCustomerItemForLine(line).itemId;
          return seen.add(id);
        })
        .toList(growable: false);
  }

  Future<double> _resolveClaimRemaining(int claimId, double fallback) async {
    try {
      final claims = await AppDb.instance.listClaims(status: 'open');
      for (final claim in claims) {
        if (claim.id == claimId) return claim.amount;
      }
    } catch (_) {}
    return fallback;
  }

  /// يُغلق كل البنود المفتوحة (آجلة + مستحقات) عندما يكون الصافي = صفر
  /// بدون أي تأثير على الخزينة لأن الطرفين متساويان
  Future<void> _closeBalancedAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إغلاق الحساب تلقائياً'),
        content: const Text(
          'الصافي = صفر، سيتم إغلاق جميع البنود المفتوحة (آجلة ومستحقات) دفعة واحدة.\n\n'
          'هذا الإجراء آمن ولن يؤثر على رصيد الخزينة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإغلاق'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // جمع كل البنود المفتوحة
    final allReceivableDeferred = _openSettlementTargets(
      _LineSide.receivable,
      kind: _OpenSettlementTargetKind.deferred,
    );
    final allPayableDeferred = _openSettlementTargets(
      _LineSide.payable,
      kind: _OpenSettlementTargetKind.deferred,
    );
    final allReceivableClaim = _openSettlementTargets(
      _LineSide.receivable,
      kind: _OpenSettlementTargetKind.claim,
    );
    final allPayableClaim = _openSettlementTargets(
      _LineSide.payable,
      kind: _OpenSettlementTargetKind.claim,
    );

    final allTargets = [
      ...allReceivableDeferred,
      ...allPayableDeferred,
      ...allReceivableClaim,
      ...allPayableClaim,
    ];

    if (allTargets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بنود مفتوحة لإغلاقها')),
        );
      }
      return;
    }

    await _runSelectedSettlement(
      successMessage: 'تم إغلاق الحساب بنجاح ✅',
      action: () async {
        for (final line in allTargets) {
          await _settleLineFully(
            line,
            note: '🔄 مقاصة تسوية / إغلاق حساب (تسوية داخلية بدون حركة نقدية في الخزينة)',
          );
        }
      },
    );
  }

  Future<void> _quickCollect() async {
    final netReceivable = customer.receivableTotal - customer.payableTotal;
    final isNegative = netReceivable < -0.001;
    bool isCashIn = !isNegative;

    final defaultInAmount = customer.receivableTotal > 0
        ? customer.receivableTotal
        : (netReceivable > 0 ? netReceivable : 0.0);
    final defaultOutAmount = customer.payableTotal > 0
        ? customer.payableTotal
        : (netReceivable < 0 ? netReceivable.abs() : 0.0);

    final amtCtrl = TextEditingController(
      text: isCashIn
          ? (defaultInAmount > 0 ? defaultInAmount.toStringAsFixed(2) : '')
          : (defaultOutAmount > 0 ? defaultOutAmount.toStringAsFixed(2) : ''),
    );
    final noteCtrl = TextEditingController(
      text: isCashIn ? 'قبض كاش من العميل' : 'دفع كاش للعميل',
    );

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final actionColor =
              isCashIn ? const Color(0xFF047857) : const Color(0xFFB91C1C);
          final netAbs = netReceivable.abs();
          final String netDisplay;
          final Color netColor;
          if (netAbs < 0.001) {
            netDisplay = 'خالص / متزن (0.00 ج.م)';
            netColor = const Color(0xFF0369A1);
          } else if (netReceivable > 0) {
            netDisplay = 'لنا: +${netAbs.toStringAsFixed(2)} ج.م';
            netColor = const Color(0xFF047857);
          } else {
            netDisplay = 'علينا: -${netAbs.toStringAsFixed(2)} ج.م';
            netColor = const Color(0xFFB91C1C);
          }

          return AlertDialog(
            title: const Text(
              '💰 حركة نقدية / تسوية سريعة',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'العميل: ${customer.name}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إجمالي لنا: ${customer.receivableTotal.toStringAsFixed(2)} ج.م | إجمالي علينا: ${customer.payableTotal.toStringAsFixed(2)} ج.م',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'صافي الرصيد: $netDisplay',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: netColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Segmented Switch: قبض كاش (In) vs دفع كاش (Out)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              isCashIn = true;
                              if (amtCtrl.text.isEmpty ||
                                  amtCtrl.text ==
                                      defaultOutAmount.toStringAsFixed(2)) {
                                amtCtrl.text = defaultInAmount > 0
                                    ? defaultInAmount.toStringAsFixed(2)
                                    : '';
                              }
                              if (noteCtrl.text == 'دفع كاش للعميل' ||
                                  noteCtrl.text.isEmpty) {
                                noteCtrl.text = 'قبض كاش من العميل';
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isCashIn
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'قبض كاش من العميل 🟢',
                              style: TextStyle(
                                color: isCashIn ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              isCashIn = false;
                              if (amtCtrl.text.isEmpty ||
                                  amtCtrl.text ==
                                      defaultInAmount.toStringAsFixed(2)) {
                                amtCtrl.text = defaultOutAmount > 0
                                    ? defaultOutAmount.toStringAsFixed(2)
                                    : '';
                              }
                              if (noteCtrl.text == 'قبض كاش من العميل' ||
                                  noteCtrl.text.isEmpty) {
                                noteCtrl.text = 'دفع كاش للعميل';
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !isCashIn
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'دفع كاش للعميل 🔴',
                              style: TextStyle(
                                color:
                                    !isCashIn ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: isCashIn
                          ? 'المبلغ المقبوض (ج.م) [دخول خزينة]'
                          : 'المبلغ المدفوع (ج.م) [خروج من الخزينة]',
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(
                        isCashIn
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        color: actionColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: actionColor),
                onPressed: () {
                  final val = double.tryParse(amtCtrl.text.trim());
                  if (val == null || val <= 0) return;
                  Navigator.pop(ctx, true);
                },
                child: Text(
                  isCashIn
                      ? 'تأكيد القبض والتسجيل بالخزينة 🟢'
                      : 'تأكيد الدفع والخصم من الخزينة 🔴',
                ),
              ),
            ],
          );
        },
      ),
    );

    if (res != true || !mounted) return;
    final actionAmount = double.tryParse(amtCtrl.text.trim()) ?? 0.0;
    if (actionAmount <= 0) return;

    if (isCashIn) {
      // Cash IN: Collect cash from customer (reduce open receivables)
      await _runSelectedSettlement(
        successMessage:
            'تم قبض $actionAmount ج.م وتسجيلها بالخزينة بنجاح ✅',
        action: () async {
          var remainingToCollect = actionAmount;
          final receivableTargets =
              _allOpenSettlementTargets(_LineSide.receivable);

          for (final target in receivableTargets) {
            if (remainingToCollect <= 0) break;
            final item = _openCustomerItemForLine(target);
            final targetRem = item.remainingAmount;
            if (targetRem <= 0) continue;
            final payNow = (targetRem <= remainingToCollect)
                ? targetRem
                : remainingToCollect;
            if (payNow >= targetRem) {
              await _settleLineFully(
                target,
                note: noteCtrl.text.trim().isEmpty
                    ? 'قبض كاش سريع'
                    : noteCtrl.text.trim(),
              );
            } else {
              await _settleLinePartially(
                target,
                amount: payNow,
                note: noteCtrl.text.trim().isEmpty
                    ? 'قبض كاش سريع جزئي'
                    : noteCtrl.text.trim(),
              );
            }
            remainingToCollect -= payNow;
          }

          if (remainingToCollect > 0) {
            await CleanWriteGateway.appDbBridge().execute(
              CreateClaimIntent(
                claimId:
                    'claim-excess-${DateTime.now().microsecondsSinceEpoch}',
                type: ClaimDirection.payable,
                party: customer.name,
                amount: remainingToCollect,
                note:
                    '${noteCtrl.text.trim().isEmpty ? 'قبض كاش سريع' : noteCtrl.text.trim()} (فائض تحصيل)',
                phone: customer.phone,
              ),
            );
          }
        },
      );
    } else {
      // Cash OUT: Pay cash to customer (settle open payables)
      await _runSelectedSettlement(
        successMessage:
            'تم دفع $actionAmount ج.م وخصمها من الخزينة بنجاح ✅',
        action: () async {
          var remainingToPay = actionAmount;
          final payableTargets = _allOpenSettlementTargets(_LineSide.payable);

          for (final target in payableTargets) {
            if (remainingToPay <= 0) break;
            final item = _openCustomerItemForLine(target);
            final targetRem = item.remainingAmount;
            if (targetRem <= 0) continue;
            final payNow =
                (targetRem <= remainingToPay) ? targetRem : remainingToPay;
            if (payNow >= targetRem) {
              await _settleLineFully(
                target,
                note: noteCtrl.text.trim().isEmpty
                    ? 'دفع كاش سريع'
                    : noteCtrl.text.trim(),
              );
            } else {
              await _settleLinePartially(
                target,
                amount: payNow,
                note: noteCtrl.text.trim().isEmpty
                    ? 'دفع كاش سريع جزئي'
                    : noteCtrl.text.trim(),
              );
            }
            remainingToPay -= payNow;
          }

          if (remainingToPay > 0) {
            await CleanWriteGateway.appDbBridge().execute(
              CreateClaimIntent(
                claimId:
                    'claim-excess-${DateTime.now().microsecondsSinceEpoch}',
                type: ClaimDirection.receivable,
                party: customer.name,
                amount: remainingToPay,
                note:
                    '${noteCtrl.text.trim().isEmpty ? 'دفع كاش سريع' : noteCtrl.text.trim()} (فائض سداد)',
                phone: customer.phone,
              ),
            );
          }
        },
      );
    }

    if (!mounted) return;
    final remainingNet = customer.receivableTotal - customer.payableTotal;
    if (remainingNet.abs() < 0.001) {
      final hasOpenItems = _openSettlementTargets(
            _LineSide.receivable,
            kind: _OpenSettlementTargetKind.deferred,
          ).isNotEmpty ||
          _openSettlementTargets(
            _LineSide.payable,
            kind: _OpenSettlementTargetKind.deferred,
          ).isNotEmpty ||
          _openSettlementTargets(
            _LineSide.receivable,
            kind: _OpenSettlementTargetKind.claim,
          ).isNotEmpty ||
          _openSettlementTargets(
            _LineSide.payable,
            kind: _OpenSettlementTargetKind.claim,
          ).isNotEmpty;
      if (hasOpenItems) {
        await _closeBalancedAccount();
      }
    }
  }

  Future<void> _quickSettleOpenItem({
    required _LineSide side,
    required bool full,
    required _OpenSettlementTargetKind kind,
  }) async {
    final targets = _openSettlementTargets(side, kind: kind);
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد عملية مفتوحة')));
      return;
    }
    final mode = await _pickSettlementMode();
    if (!mounted) return;
    if (mode == null) return;

    if (mode == _SettlementMode.total) {
      final totalTargets = _allOpenSettlementTargets(side);
      if (totalTargets.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('لا توجد عملية مفتوحة')));
        return;
      }
      await _quickSettleFromTotal(
        targets: totalTargets,
        side: side,
        full: full,
      );
      return;
    }

    final selected = targets.length == 1
        ? <_CustomerLine>[targets.single]
        : await _pickOpenSettlementTargets(targets);
    if (selected == null || selected.isEmpty) return;

    final actionLabel = side == _LineSide.receivable ? 'تحصيل' : 'سداد';
    final fullLabel = '$actionLabel كلي';

    if (full) {
      final confirmation = await _confirmQuickFullSettlement(
        targets: selected,
        title: kind == _OpenSettlementTargetKind.claim
            ? '$fullLabel للمستحق'
            : '$fullLabel للآجل',
        okText: fullLabel,
      );
      if (confirmation == null) return;
      await _runSelectedSettlement(
        successMessage: 'تم التنفيذ بنجاح ✅',
        action: () async {
          for (final line in selected) {
            await _settleLineFully(line, note: confirmation.note);
          }
        },
      );
      return;
    }

    final partial = await _promptPartialSettlementForItems(
      targets: selected,
      actionLabel: actionLabel,
    );
    if (partial == null || partial.amountsByItemId.isEmpty) return;
    await _runSelectedSettlement(
      successMessage: 'تم التنفيذ بنجاح ✅',
      action: () async {
        for (final line in selected) {
          final item = _openCustomerItemForLine(line);
          final amount = partial.amountsByItemId[item.itemId];
          if (amount == null || amount <= 0) continue;
          await _settleLinePartially(line, amount: amount, note: partial.note);
        }
      },
    );
  }

  Future<void> _quickSettleFromTotal({
    required List<_CustomerLine> targets,
    required _LineSide side,
    required bool full,
  }) async {
    final totalOpen = targets.fold<double>(
      0,
      (sum, line) => sum + _openCustomerItemForLine(line).remainingAmount,
    );
    final actionLabel = side == _LineSide.receivable ? 'تحصيل' : 'سداد';
    final input = await _promptTotalSettlement(
      targets: targets,
      actionLabel: actionLabel,
      totalOpen: totalOpen,
      full: full,
    );
    if (input == null) return;

    final ordered = _orderTotalSettlementTargets(targets, input.order);
    final note = _totalSettlementNote(input.note);
    await _runSelectedSettlement(
      successMessage: 'تم التنفيذ بنجاح ✅',
      action: () async {
        var remainingInput = input.amount;
        for (final line in ordered) {
          if (remainingInput <= 0.0001) break;
          final item = _openCustomerItemForLine(line);
          final allocation = remainingInput > item.remainingAmount
              ? item.remainingAmount
              : remainingInput;
          if (allocation >= item.remainingAmount - 0.0001) {
            await _settleLineFully(line, note: note);
          } else {
            await _settleLinePartially(line, amount: allocation, note: note);
          }
          remainingInput -= allocation;
        }
      },
    );
  }

  Future<void> _runSelectedSettlement({
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    if (_batchBusy) return;
    setState(() => _batchBusy = true);
    try {
      await action();
      await onRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _settleLineFully(_CustomerLine line, {String? note}) async {
    final gateway = CleanWriteGateway.appDbBridge();
    if (line.lineType == _CustomerLineType.claimOpen) {
      await gateway.execute(
        CreateClaimSettlementIntent(
          claimId: line.claimId!.toString(),
          settlementId:
              'claim-${line.claimId}-settlement-${DateTime.now().microsecondsSinceEpoch}',
          amount: await _resolveClaimRemaining(line.claimId!, line.amount),
          fullSettlement: true,
          note: note,
        ),
      );
      return;
    }
    await gateway.execute(
      CreateSettlementIntent(
        itemId: (line.pendingTxnId ?? line.txnId!).toString(),
        settlementId:
            'pending-${(line.pendingTxnId ?? line.txnId!)}-settlement-${DateTime.now().microsecondsSinceEpoch}',
        sourceType: line.side == _LineSide.receivable
            ? SettlementSourceType.deferredTransfer
            : SettlementSourceType.deferredReceive,
        amount: _openCustomerItemForLine(line).remainingAmount,
        fullSettlement: true,
        note: note,
      ),
    );
  }

  Future<void> _settleLinePartially(
    _CustomerLine line, {
    required double amount,
    String? note,
  }) async {
    final gateway = CleanWriteGateway.appDbBridge();
    if (line.lineType == _CustomerLineType.claimOpen) {
      await gateway.execute(
        CreateClaimSettlementIntent(
          claimId: line.claimId!.toString(),
          settlementId:
              'claim-${line.claimId}-settlement-${DateTime.now().microsecondsSinceEpoch}',
          amount: amount,
          note: note,
        ),
      );
      return;
    }
    await gateway.execute(
      CreateSettlementIntent(
        itemId: (line.pendingTxnId ?? line.txnId!).toString(),
        settlementId:
            'pending-${(line.pendingTxnId ?? line.txnId!)}-settlement-${DateTime.now().microsecondsSinceEpoch}',
        sourceType: line.side == _LineSide.receivable
            ? SettlementSourceType.deferredTransfer
            : SettlementSourceType.deferredReceive,
        amount: amount,
        note: note,
      ),
    );
  }

  Future<List<_CustomerLine>?> _pickOpenSettlementTargets(
    List<_CustomerLine> targets,
  ) {
    final selectedIds = <String>{};
    return showModalBottomSheet<List<_CustomerLine>>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setState) => ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                Text(
                  'اختر العملية المفتوحة',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ...targets.map((line) {
                  final item = _openCustomerItemForLine(line);
                  final date = _shortDate(item.createdAt);
                  final selected = selectedIds.contains(item.itemId);
                  return CheckboxListTile(
                    value: selected,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(item.title),
                    subtitle: Text(
                      '$date | الأصل: ${item.originalAmount.toStringAsFixed(2)} | المتبقي: ${item.remainingAmount.toStringAsFixed(2)}',
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedIds.add(item.itemId);
                        } else {
                          selectedIds.remove(item.itemId);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: selectedIds.isEmpty
                            ? null
                            : () => Navigator.of(ctx).pop(
                                targets
                                    .where(
                                      (line) => selectedIds.contains(
                                        _openCustomerItemForLine(line).itemId,
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                        child: const Text('متابعة'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_SettlementMode?> _pickSettlementMode() async {
    return showDialog<_SettlementMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر طريقة التسوية:'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_SettlementMode.selectedItems),
              child: const Text('تحديد عمليات'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(_SettlementMode.total),
              child: const Text('من الإجمالي'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<_TotalSettlementInput?> _promptTotalSettlement({
    required List<_CustomerLine> targets,
    required String actionLabel,
    required double totalOpen,
    required bool full,
  }) async {
    var amountText = full ? totalOpen.toStringAsFixed(2) : '';
    var noteText = '';
    var order = _TotalSettlementOrder.oldestFirst;
    String? error;
    final result = await showDialog<_TotalSettlementInput>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('$actionLabel من الإجمالي'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إجمالي المفتوح: ${totalOpen.toStringAsFixed(2)}'),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: amountText,
                  readOnly: full,
                  onChanged: (value) => amountText = value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    hintText: full ? totalOpen.toStringAsFixed(2) : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<_TotalSettlementOrder>(
                  initialValue: order,
                  decoration: const InputDecoration(
                    labelText: 'ترتيب التوزيع',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _TotalSettlementOrder.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_totalSettlementOrderLabel(value)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => order = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => noteText = value,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = full
                    ? totalOpen
                    : double.tryParse(amountText.trim());
                if (amount == null || amount <= 0) {
                  setState(() => error = 'أدخل مبلغًا صحيحًا');
                  return;
                }
                if (amount > totalOpen + 0.0001) {
                  setState(() => error = 'المبلغ أكبر من إجمالي المفتوح');
                  return;
                }
                final note = noteText.trim();
                FocusScope.of(ctx).unfocus();
                Navigator.of(ctx).pop(
                  _TotalSettlementInput(
                    amount: amount,
                    note: note.isEmpty ? null : note,
                    order: order,
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
  }

  Future<_SettlementNoteInput?> _confirmQuickFullSettlement({
    required List<_CustomerLine> targets,
    required String title,
    required String okText,
  }) async {
    var noteText = '';
    final result = await showDialog<_SettlementNoteInput>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...targets.map((line) {
                final item = _openCustomerItemForLine(line);
                final ref = item.linkedTxnId == null
                    ? ''
                    : ' #${item.linkedTxnId}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${item.title}$ref - المتبقي: ${item.remainingAmount.toStringAsFixed(2)}',
                  ),
                );
              }),
              const SizedBox(height: 10),
              TextField(
                onChanged: (value) => noteText = value,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final note = noteText.trim();
              FocusScope.of(ctx).unfocus();
              Navigator.of(
                ctx,
              ).pop(_SettlementNoteInput(note: note.isEmpty ? null : note));
            },
            child: Text(okText),
          ),
        ],
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    return result;
  }

  List<_CustomerLine> _orderTotalSettlementTargets(
    List<_CustomerLine> targets,
    _TotalSettlementOrder order,
  ) {
    final ordered = [...targets];
    int byOldest(_CustomerLine a, _CustomerLine b) {
      final date = a.date.compareTo(b.date);
      if (date != 0) return date;
      return _simpleLedgerIdentity(a).compareTo(_simpleLedgerIdentity(b));
    }

    int byNewest(_CustomerLine a, _CustomerLine b) => -byOldest(a, b);

    bool isClaim(_CustomerLine line) =>
        line.lineType == _CustomerLineType.claimOpen;

    switch (order) {
      case _TotalSettlementOrder.oldestFirst:
        ordered.sort(byOldest);
        break;
      case _TotalSettlementOrder.newestFirst:
        ordered.sort(byNewest);
        break;
      case _TotalSettlementOrder.claimsFirst:
        ordered.sort((a, b) {
          final claim = (isClaim(b) ? 1 : 0).compareTo(isClaim(a) ? 1 : 0);
          if (claim != 0) return claim;
          return byOldest(a, b);
        });
        break;
      case _TotalSettlementOrder.deferredFirst:
        ordered.sort((a, b) {
          final deferred = (isClaim(a) ? 1 : 0).compareTo(isClaim(b) ? 1 : 0);
          if (deferred != 0) return deferred;
          return byOldest(a, b);
        });
        break;
    }
    return ordered;
  }

  String _totalSettlementNote(String? userNote) {
    final note = (userNote ?? '').trim();
    if (note.isEmpty) return 'تسوية من الإجمالي';
    return 'تسوية من الإجمالي - $note';
  }

  String _totalSettlementOrderLabel(_TotalSettlementOrder order) {
    return switch (order) {
      _TotalSettlementOrder.oldestFirst => 'الأقدم أولًا',
      _TotalSettlementOrder.newestFirst => 'الأحدث أولًا',
      _TotalSettlementOrder.claimsFirst => 'المستحقات أولًا',
      _TotalSettlementOrder.deferredFirst => 'الآجل أولًا',
    };
  }

  Future<_PartialOpenSettlementInput?> _promptPartialSettlementForItems({
    required List<_CustomerLine> targets,
    required String actionLabel,
  }) async {
    final rawAmounts = <String, String>{};
    var noteText = '';
    String? error;
    final result = await showDialog<_PartialOpenSettlementInput>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('$actionLabel جزئي'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...targets.map((line) {
                  final item = _openCustomerItemForLine(line);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      onChanged: (value) => rawAmounts[item.itemId] = value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${item.title} - المتبقي ${item.remainingAmount.toStringAsFixed(2)}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  );
                }),
                TextField(
                  onChanged: (value) => noteText = value,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final values = <String, double>{};
                for (final line in targets) {
                  final item = _openCustomerItemForLine(line);
                  final raw = (rawAmounts[item.itemId] ?? '').trim();
                  if (raw.isEmpty) continue;
                  final value = double.tryParse(raw);
                  if (value == null || value <= 0) {
                    setState(() => error = 'أدخل مبلغًا صحيحًا');
                    return;
                  }
                  if (value > item.remainingAmount) {
                    setState(() => error = 'المبلغ أكبر من المتبقي');
                    return;
                  }
                  values[item.itemId] = value;
                }
                if (values.isEmpty) {
                  setState(() => error = 'اختر مبلغًا لعملية واحدة على الأقل');
                  return;
                }
                final note = noteText.trim();
                FocusScope.of(ctx).unfocus();
                Navigator.of(ctx).pop(
                  _PartialOpenSettlementInput(
                    amountsByItemId: values,
                    note: note.isEmpty ? null : note,
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
  }

  OpenCustomerItem _openCustomerItemForLine(_CustomerLine line) {
    final sourceType = switch (line.lineType) {
      _CustomerLineType.claimOpen =>
        line.claimType == 'payable'
            ? CustomerLedgerSourceType.claimPayable
            : CustomerLedgerSourceType.claimReceivable,
      _CustomerLineType.txn =>
        line.txnKind == 'receive'
            ? CustomerLedgerSourceType.deferredReceive
            : CustomerLedgerSourceType.deferredTransfer,
      _CustomerLineType.adjustment => CustomerLedgerSourceType.adjustment,
    };
    final id = switch (line.lineType) {
      _CustomerLineType.claimOpen => 'claim:${line.claimId}',
      _CustomerLineType.txn => 'pending:${line.txnId}',
      _CustomerLineType.adjustment => 'adj:${line.ref.split('#').last}',
    };
    return OpenCustomerItem(
      itemId: id,
      sourceType: sourceType,
      title: _lineChipLabel(line),
      originalAmount: _lineDisplayAmount(line),
      remainingAmount: line.remainingAfter ?? line.amount,
      createdAt: line.date,
      linkedTxnId: line.lineType == _CustomerLineType.txn
          ? line.txnId
          : line.storySourceTxnId,
    );
  }

  String _shortDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _lineChipLabel(_CustomerLine line) {
    if (line.lineType == _CustomerLineType.claimOpen) {
      return 'مستحق';
    }
    if (line.txnKind == 'claim_collect' || line.txnKind == 'claim_pay') {
      if (_isOffsetLine(line)) {
        return '🔄 مقاصة تسوية / إغلاق حساب';
      }
      if (line.txnKind == 'claim_collect') {
        return (line.remainingAfter ?? 0) > 0 ? 'تحصيل جزئي' : 'تحصيل كلي';
      }
      return (line.remainingAfter ?? 0) > 0 ? 'سداد جزئي' : 'سداد كلي';
    }
    if (line.txnKind == 'transfer') {
      return line.txnStatus == 'pending' ? 'تحويل آجل' : 'تحويل';
    }
    if (line.txnKind == 'receive') {
      return line.txnStatus == 'pending' ? 'استلام آجل' : 'استلام';
    }
    if (line.txnKind == 'fawry_cash') return 'فوري نقدي';
    if (line.txnKind == 'fawry_credit') {
      return 'فوري آجل';
    }
    return line.title;
  }

  Color _lineChipColor(_CustomerLine line) {
    if (_isOffsetLine(line)) {
      return const Color(0xFF7C3AED);
    }
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
    final accountSummary = customer.account?.summary;
    final totalForUs = accountSummary?.totalForUs ?? customer.receivableTotal;
    final totalAgainstUs =
        accountSummary?.totalAgainstUs ?? customer.payableTotal;
    final openForUs = accountSummary == null
        ? customer.receivableTotal
        : accountSummary.openDeferredForUs + accountSummary.openClaimsForUs;
    final openAgainstUs = accountSummary == null
        ? customer.payableTotal
        : accountSummary.openDeferredAgainstUs +
              accountSummary.openClaimsAgainstUs;
    final netBalance = totalForUs - totalAgainstUs;
    final isClosed =
        openForUs.abs() < 0.0001 &&
        openAgainstUs.abs() < 0.0001 &&
        netBalance.abs() < 0.0001;
    final isBalanced = !isClosed && netBalance.abs() < 0.0001;
    final netColor = isClosed
        ? const Color(0xFF64748B)
        : isBalanced
            ? const Color(0xFF0369A1)
            : netBalance >= 0
                ? const Color(0xFF047857)
                : const Color(0xFFB91C1C);
    final ledgerLines = buildSimpleCustomerLedger(customer);
    final balances = _computeBalances(
      lines: ledgerLines,
      currentNet: netBalance,
    );
    final visibleLines = _applyFilter(ledgerLines);

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () async {
                      if (customer.account == null) return;
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _batchBusy = true);
                      try {
                        final path = await ReportExporter.exportCustomerPdf(
                          account: customer.account!,
                          range: DateRange(start: DateTime(2000), end: DateTime(2099)),
                        );
                        // ignore: deprecated_member_use
                        await Share.shareXFiles([XFile(path)], text: 'كشف حساب: ${customer.name}');
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text('خطأ أثناء تصدير الـ PDF: $e')));
                      } finally {
                        setState(() => _batchBusy = false);
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                    tooltip: 'تصدير كشف حساب PDF',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Text('الهاتف: ${customer.phone ?? 'غير مسجل'}'),
              if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    String cleanPhone = customer.phone ?? '';
                    const arabicToEnglish = {'٠':'0','١':'1','٢':'2','٣':'3','٤':'4','٥':'5','٦':'6','٧':'7','٨':'8','٩':'9'};
                    for (var e in arabicToEnglish.entries) {
                      cleanPhone = cleanPhone.replaceAll(e.key, e.value);
                    }
                    cleanPhone = cleanPhone.replaceAll(RegExp(r'[^\d+]'), '');
                    String phone = cleanPhone.startsWith('+') ? cleanPhone : '+2$cleanPhone';
                    phone = phone.replaceAll('+', '');
                    final url = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent("مرحبا ${customer.name}، بخصوص حسابك:")}');
                    try {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('Could not launch WhatsApp: $e');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wechat, color: Colors.green, size: 16),
                        SizedBox(width: 4),
                        Text('واتساب', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _CustomerCompactSummaryStrip(
            netBalance: netBalance,
            totalForUs: totalForUs,
            totalAgainstUs: totalAgainstUs,
            openForUs: openForUs,
            openAgainstUs: openAgainstUs,
            statusLabel: isClosed ? 'مغلق / صفر' : isBalanced ? 'متعادل' : 'مفتوح',
            netColor: netColor,
          ),
          if (isBalanced) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0369A1),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('إغلاق الحساب تلقائياً (الصافي = صفر)'),
                onPressed: _batchBusy ? null : () => _closeBalancedAccount(),
              ),
            ),
          ],
          if (_openSettlementTargets(
                _LineSide.receivable,
                kind: _OpenSettlementTargetKind.deferred,
              ).isNotEmpty ||
              _openSettlementTargets(
                _LineSide.payable,
                kind: _OpenSettlementTargetKind.deferred,
              ).isNotEmpty ||
              _openSettlementTargets(
                _LineSide.receivable,
                kind: _OpenSettlementTargetKind.claim,
              ).isNotEmpty ||
              _openSettlementTargets(
                _LineSide.payable,
                kind: _OpenSettlementTargetKind.claim,
              ).isNotEmpty) ...[
            const SizedBox(height: 6),
            _CustomerOpenSettlementActions(
              canCollectDeferred: _openSettlementTargets(
                _LineSide.receivable,
                kind: _OpenSettlementTargetKind.deferred,
              ).isNotEmpty,
              canPayDeferred: _openSettlementTargets(
                _LineSide.payable,
                kind: _OpenSettlementTargetKind.deferred,
              ).isNotEmpty,
              canCollectClaim: _openSettlementTargets(
                _LineSide.receivable,
                kind: _OpenSettlementTargetKind.claim,
              ).isNotEmpty,
              canPayClaim: _openSettlementTargets(
                _LineSide.payable,
                kind: _OpenSettlementTargetKind.claim,
              ).isNotEmpty,
              onCollectDeferredPartial: () => _quickSettleOpenItem(
                side: _LineSide.receivable,
                full: false,
                kind: _OpenSettlementTargetKind.deferred,
              ),
              onCollectDeferredFull: () => _quickSettleOpenItem(
                side: _LineSide.receivable,
                full: true,
                kind: _OpenSettlementTargetKind.deferred,
              ),
              onPayDeferredPartial: () => _quickSettleOpenItem(
                side: _LineSide.payable,
                full: false,
                kind: _OpenSettlementTargetKind.deferred,
              ),
              onPayDeferredFull: () => _quickSettleOpenItem(
                side: _LineSide.payable,
                full: true,
                kind: _OpenSettlementTargetKind.deferred,
              ),
              onCollectClaimPartial: () => _quickSettleOpenItem(
                side: _LineSide.receivable,
                full: false,
                kind: _OpenSettlementTargetKind.claim,
              ),
              onCollectClaimFull: () => _quickSettleOpenItem(
                side: _LineSide.receivable,
                full: true,
                kind: _OpenSettlementTargetKind.claim,
              ),
              onPayClaimPartial: () => _quickSettleOpenItem(
                side: _LineSide.payable,
                full: false,
                kind: _OpenSettlementTargetKind.claim,
              ),
              onPayClaimFull: () => _quickSettleOpenItem(
                side: _LineSide.payable,
                full: true,
                kind: _OpenSettlementTargetKind.claim,
              ),
            ),
          ],
          const SizedBox(height: 8),
          _CustomerQuickActionsSection(
            showActions: _showActions,
            batchBusy: _batchBusy,
            onToggle: () => setState(() => _showActions = !_showActions),
            onAddOperation: _openAddOperationMenu,
            onQuickCollect: () => _quickCollect(),
            onReport: onReport,
            onOpenAttachments: _openAttachments,
          ),
          const SizedBox(height: 8),
          _CustomerLedgerFilters(
            lineFilter: _filter,
            accountFilter: _accountFilter,
            showAdvanced: _showAdvancedFilters,
            onLineFilterSelected: (value) {
              setState(() => _filter = value);
            },
            onAccountFilterSelected: (value) {
              setState(() => _accountFilter = value);
            },
            onToggleAdvanced: () {
              setState(() => _showAdvancedFilters = !_showAdvancedFilters);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visibleLines.isEmpty
                ? const Center(child: Text('لا توجد حركات مرتبطة لهذا العميل'))
                : ListView(
                    children: [
                      const _CustomerTableHeader(),
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
                        final balance = _displayBalanceAmountForLine(
                          line,
                          balances,
                          netBalance,
                        );
                        final balanceSide = _displayBalanceSideForLine(
                          line,
                          balances,
                          netBalance,
                        );
                        final isZero = balance.abs() < 0.001;
                        final balanceColor = isZero
                            ? const Color(0xFF0369A1)
                            : (balanceSide == _LineSide.receivable
                                ? const Color(0xFF047857)
                                : const Color(0xFFB91C1C));
                        final balanceBg = balanceColor.withValues(alpha: 0.12);
                        final balanceLabel = isZero
                            ? '0.00'
                            : (balanceSide == _LineSide.receivable
                                ? '+${balance.toStringAsFixed(2)}'
                                : '-${balance.toStringAsFixed(2)}');

                        final actions = <PopupMenuEntry<_LineAction>>[];
                        final isSettlement =
                            line.txnKind == 'claim_collect' ||
                            line.txnKind == 'claim_pay';
                        final chipLabel = _lineChipLabel(line);
                        final chipColor = _lineChipColor(line);
                        final rawDisplayTitle = isSettlement
                            ? _lineChipLabel(line)
                            : line.title;
                        final displayTitle = rawDisplayTitle == chipLabel
                            ? ''
                            : rawDisplayTitle;
                        final displayDetails = isSettlement
                            ? _buildSettlementDetails(line)
                            : _compactDetailsForLine(line);
                        if (line.lineType == _CustomerLineType.claimOpen &&
                            line.txnStatus != 'closed') {
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
                          
                          if (line.remainingAfter != null && line.remainingAfter! > 0) {
                            actions.add(
                              PopupMenuItem(
                                value: isCollect
                                    ? _LineAction.collectPendingPartial
                                    : _LineAction.payPendingPartial,
                                child: Text(isCollect ? 'تحصيل جزء' : 'سداد جزء'),
                              ),
                            );
                            actions.add(
                              PopupMenuItem(
                                value: isCollect
                                    ? _LineAction.collectPendingFull
                                    : _LineAction.payPendingFull,
                                child: Text(isCollect ? 'تحصيل المتبقي' : 'سداد المتبقي'),
                              ),
                            );
                          }

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
                            actions.add(
                              const PopupMenuItem(
                                value: _LineAction.collectPendingFull,
                                child: Text('تحصيل كلي'),
                              ),
                            );
                          } else if (line.txnKind == 'receive') {
                            actions.add(
                              const PopupMenuItem(
                                value: _LineAction.payPendingPartial,
                                child: Text('سداد جزئي'),
                              ),
                            );
                            actions.add(
                              const PopupMenuItem(
                                value: _LineAction.payPendingFull,
                                child: Text('سداد كلي'),
                              ),
                            );
                          }
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

                        return _CustomerLineRowPresentation(
                          date: date,
                          amountText:
                              '$amountSign${_lineDisplayAmount(line).toStringAsFixed(2)}',
                          amountBg: amountBg,
                          amountColor: amountColor,
                          chipLabel: chipLabel,
                          chipColor: chipColor,
                          displayTitle: displayTitle,
                          displayDetails: displayDetails,
                          actions: actions,
                          onMenuSelected: busy
                              ? null
                              : (action) => onLineAction(line, action),
                          balanceLabel: balanceLabel,
                          balanceBg: balanceBg,
                          balanceColor: balanceColor,
                          onTap: () => onShowDetails(line),
                          walletName: line.walletName,
                          walletPhone: line.walletPhone,
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
}

class _CustomerCompactSummaryStrip extends StatelessWidget {
  final double netBalance;
  final double totalForUs;
  final double totalAgainstUs;
  final double openForUs;
  final double openAgainstUs;
  final String statusLabel;
  final Color netColor;

  const _CustomerCompactSummaryStrip({
    required this.netBalance,
    required this.totalForUs,
    required this.totalAgainstUs,
    required this.openForUs,
    required this.openAgainstUs,
    required this.statusLabel,
    required this.netColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final netAbs = netBalance.abs();
    final String netDisplay;
    final Color effectiveNetColor;
    if (netAbs < 0.001) {
      netDisplay = 'خالص / متزن (0.00 ج.م)';
      effectiveNetColor = const Color(0xFF0369A1);
    } else if (netBalance > 0) {
      netDisplay = 'لنا: +${netAbs.toStringAsFixed(2)} ج.م';
      effectiveNetColor = const Color(0xFF047857);
    } else {
      netDisplay = 'علينا: -${netAbs.toStringAsFixed(2)} ج.م';
      effectiveNetColor = const Color(0xFFB91C1C);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'الصافي: $netDisplay',
                  style: textTheme.titleMedium?.copyWith(
                    color: effectiveNetColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: netColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: netColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'لنا: ${totalForUs.toStringAsFixed(2)} | علينا: ${totalAgainstUs.toStringAsFixed(2)}',
            style: textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'مفتوح لنا: ${openForUs.toStringAsFixed(2)} | مفتوح علينا: ${openAgainstUs.toStringAsFixed(2)}',
            style: textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerOpenSettlementActions extends StatelessWidget {
  final bool canCollectDeferred;
  final bool canPayDeferred;
  final bool canCollectClaim;
  final bool canPayClaim;
  final Future<void> Function() onCollectDeferredPartial;
  final Future<void> Function() onCollectDeferredFull;
  final Future<void> Function() onPayDeferredPartial;
  final Future<void> Function() onPayDeferredFull;
  final Future<void> Function() onCollectClaimPartial;
  final Future<void> Function() onCollectClaimFull;
  final Future<void> Function() onPayClaimPartial;
  final Future<void> Function() onPayClaimFull;

  const _CustomerOpenSettlementActions({
    required this.canCollectDeferred,
    required this.canPayDeferred,
    required this.canCollectClaim,
    required this.canPayClaim,
    required this.onCollectDeferredPartial,
    required this.onCollectDeferredFull,
    required this.onPayDeferredPartial,
    required this.onPayDeferredFull,
    required this.onCollectClaimPartial,
    required this.onCollectClaimFull,
    required this.onPayClaimPartial,
    required this.onPayClaimFull,
  });

  @override
  Widget build(BuildContext context) {
    // الأزرار السريعة للتحصيل/السداد تم حذفها — استخدم زر "إغلاق الحساب" بدلاً منها
    return const SizedBox.shrink();
  }
}

class _CustomerLedgerFilters extends StatelessWidget {
  final _CustomerLineFilter lineFilter;
  final _CustomerAccountFilter accountFilter;
  final bool showAdvanced;
  final ValueChanged<_CustomerLineFilter> onLineFilterSelected;
  final ValueChanged<_CustomerAccountFilter> onAccountFilterSelected;
  final VoidCallback onToggleAdvanced;

  const _CustomerLedgerFilters({
    required this.lineFilter,
    required this.accountFilter,
    required this.showAdvanced,
    required this.onLineFilterSelected,
    required this.onAccountFilterSelected,
    required this.onToggleAdvanced,
  });

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: (value) {
        if (value) onSelected();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(
              label: 'الكل',
              selected:
                  accountFilter == _CustomerAccountFilter.all &&
                  lineFilter == _CustomerLineFilter.all,
              onSelected: () {
                onAccountFilterSelected(_CustomerAccountFilter.all);
                onLineFilterSelected(_CustomerLineFilter.all);
              },
            ),
            _chip(
              label: 'لنا',
              selected: accountFilter == _CustomerAccountFilter.forUs,
              onSelected: () {
                onAccountFilterSelected(_CustomerAccountFilter.forUs);
                onLineFilterSelected(_CustomerLineFilter.all);
              },
            ),
            _chip(
              label: 'علينا',
              selected: accountFilter == _CustomerAccountFilter.againstUs,
              onSelected: () {
                onAccountFilterSelected(_CustomerAccountFilter.againstUs);
                onLineFilterSelected(_CustomerLineFilter.all);
              },
            ),
            _chip(
              label: 'المستحقات',
              selected:
                  accountFilter == _CustomerAccountFilter.claims ||
                  lineFilter == _CustomerLineFilter.claims,
              onSelected: () {
                onAccountFilterSelected(_CustomerAccountFilter.claims);
                onLineFilterSelected(_CustomerLineFilter.claims);
              },
            ),
            ActionChip(
              avatar: Icon(
                showAdvanced ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: const Text('المزيد'),
              visualDensity: VisualDensity.compact,
              onPressed: onToggleAdvanced,
            ),
          ],
        ),
        if (showAdvanced)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(
                  label: 'التحويلات الآجلة',
                  selected:
                      accountFilter == _CustomerAccountFilter.deferredTransfers,
                  onSelected: () {
                    onAccountFilterSelected(
                      _CustomerAccountFilter.deferredTransfers,
                    );
                    onLineFilterSelected(_CustomerLineFilter.all);
                  },
                ),
                _chip(
                  label: 'الاستلامات الآجلة',
                  selected:
                      accountFilter == _CustomerAccountFilter.deferredReceives,
                  onSelected: () {
                    onAccountFilterSelected(
                      _CustomerAccountFilter.deferredReceives,
                    );
                    onLineFilterSelected(_CustomerLineFilter.all);
                  },
                ),
                _chip(
                  label: 'تسويات الحساب',
                  selected: accountFilter == _CustomerAccountFilter.settlements,
                  onSelected: () {
                    onAccountFilterSelected(_CustomerAccountFilter.settlements);
                    onLineFilterSelected(_CustomerLineFilter.all);
                  },
                ),
                _chip(
                  label: 'غير النشط/المغلق',
                  selected:
                      accountFilter == _CustomerAccountFilter.archivedClosed,
                  onSelected: () {
                    onAccountFilterSelected(
                      _CustomerAccountFilter.archivedClosed,
                    );
                    onLineFilterSelected(_CustomerLineFilter.all);
                  },
                ),
                _chip(
                  label: 'آجل',
                  selected:
                      accountFilter ==
                          _CustomerAccountFilter.deferredTransfers ||
                      accountFilter == _CustomerAccountFilter.deferredReceives,
                  onSelected: () {
                    onAccountFilterSelected(
                      _CustomerAccountFilter.deferredTransfers,
                    );
                    onLineFilterSelected(_CustomerLineFilter.all);
                  },
                ),
                _chip(
                  label: 'مغلق',
                  selected:
                      accountFilter == _CustomerAccountFilter.archivedClosed,
                  onSelected: () {
                    onAccountFilterSelected(
                      _CustomerAccountFilter.archivedClosed,
                    );
                    onLineFilterSelected(_CustomerLineFilter.all);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CustomerLineRowPresentation extends StatelessWidget {
  final String date;
  final String amountText;
  final Color amountBg;
  final Color amountColor;
  final String chipLabel;
  final Color chipColor;
  final String displayTitle;
  final String? displayDetails;
  final List<PopupMenuEntry<_LineAction>> actions;
  final ValueChanged<_LineAction>? onMenuSelected;
  final String balanceLabel;
  final Color balanceBg;
  final Color balanceColor;
  final VoidCallback onTap;
  final String? walletName;
  final String? walletPhone;

  const _CustomerLineRowPresentation({
    required this.date,
    required this.amountText,
    required this.amountBg,
    required this.amountColor,
    required this.chipLabel,
    required this.chipColor,
    required this.displayTitle,
    required this.displayDetails,
    required this.actions,
    required this.onMenuSelected,
    required this.balanceLabel,
    required this.balanceBg,
    required this.balanceColor,
    required this.onTap,
    this.walletName,
    this.walletPhone,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            _CustomerTableCell(
              text: date,
              flex: 2,
              background: Colors.transparent,
              align: Alignment.center,
            ),
            _CustomerTableCell(
              text: amountText,
              flex: 2,
              background: amountBg,
              textColor: amountColor,
              align: Alignment.center,
            ),
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: chipColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
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
                          if (displayTitle.trim().isNotEmpty)
                            Text(
                              displayTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if ((displayDetails ?? '').trim().isNotEmpty)
                            Text(
                              displayDetails!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (walletName != null || walletPhone != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.account_balance_wallet, size: 12, color: Colors.blueGrey),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      [walletName, walletPhone].where((e) => e != null && e.trim().isNotEmpty).join(' - '),
                                      style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // تفاصيل فقط بدون مرجع/حالة لعرض مبسط
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty)
                      PopupMenuButton<_LineAction>(
                        onSelected: onMenuSelected,
                        itemBuilder: (_) => actions,
                        icon: const Icon(Icons.more_vert, size: 18),
                      ),
                  ],
                ),
              ),
            ),
            _CustomerTableCell(
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
  }
}

class _CustomerQuickActionsSection extends StatelessWidget {
  final bool showActions;
  final bool batchBusy;
  final VoidCallback onToggle;
  final VoidCallback onAddOperation;
  final VoidCallback? onQuickCollect;
  final VoidCallback onReport;
  final VoidCallback onOpenAttachments;

  const _CustomerQuickActionsSection({
    required this.showActions,
    required this.batchBusy,
    required this.onToggle,
    required this.onAddOperation,
    this.onQuickCollect,
    required this.onReport,
    required this.onOpenAttachments,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
              onPressed: onToggle,
              icon: Icon(showActions ? Icons.expand_less : Icons.expand_more),
              tooltip: showActions ? 'إخفاء الإجراءات' : 'إظهار الإجراءات',
            ),
          ],
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onQuickCollect != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                  ),
                  onPressed: batchBusy ? null : onQuickCollect,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('💰 حركة نقدية / تسوية سريعة'),
                ),
              ElevatedButton.icon(
                onPressed: batchBusy ? null : onAddOperation,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('إضافة عملية'),
              ),
              ElevatedButton.icon(
                onPressed: onReport,
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('تقرير العميل'),
              ),
              ElevatedButton.icon(
                onPressed: onOpenAttachments,
                icon: const Icon(Icons.attach_file),
                label: const Text('مرفقات العميل'),
              ),
            ],
          ),
          crossFadeState: showActions
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}

class _CustomerTableHeader extends StatelessWidget {
  const _CustomerTableHeader();

  @override
  Widget build(BuildContext context) {
    final headerBg = const Color(0xFF1E40AF).withValues(alpha: 0.08);
    const headerTextColor = Color(0xFF1E40AF);
    return Row(
      children: [
        _CustomerTableCell(
          text: 'التاريخ',
          flex: 2,
          background: headerBg,
          textColor: headerTextColor,
          align: Alignment.center,
          bold: true,
        ),
        _CustomerTableCell(
          text: 'المبلغ',
          flex: 2,
          background: headerBg,
          textColor: headerTextColor,
          align: Alignment.center,
          bold: true,
        ),
        _CustomerTableCell(
          text: 'التفاصيل',
          flex: 4,
          background: headerBg,
          textColor: headerTextColor,
          align: Alignment.center,
          bold: true,
        ),
        _CustomerTableCell(
          text: 'الرصيد',
          flex: 2,
          background: headerBg,
          textColor: headerTextColor,
          align: Alignment.center,
          bold: true,
        ),
      ],
    );
  }
}

class _CustomerTableCell extends StatelessWidget {
  final String text;
  final int flex;
  final Color background;
  final Color textColor;
  final Alignment align;
  final bool bold;

  const _CustomerTableCell({
    required this.text,
    required this.flex,
    required this.background,
    this.textColor = Colors.black87,
    this.align = Alignment.centerLeft,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
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

enum _CustomerLineType { claimOpen, txn, adjustment }

enum _LineAction {
  collectPartial,
  collectFull,
  payPartial,
  payFull,
  collectPendingPartial,
  payPendingPartial,
  collectPendingFull,
  payPendingFull,
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
  final int? storySourceTxnId;
  final DateTime? storyAnchorDate;
  final int? walletId;
  final String? walletName;
  final String? walletPhone;

  const _CustomerLine({
    required this.date,
    required this.side,
    required this.amount,
    this.displayAmount,
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
    this.storySourceTxnId,
    this.storyAnchorDate,
    this.walletId,
    this.walletName,
    this.walletPhone,
  });
}

class _CustomerBucket {
  final String key;
  final String name;
  final String? phone;
  CustomerAccount? account;

  double receivableClaims = 0;
  double payableClaims = 0;
  double receivablePending = 0;
  double payablePending = 0;
  final List<_CustomerLine> lines = [];
  DateTime? lastActivity;

  _CustomerBucket({required this.key, required this.name, this.phone});

  double get receivableTotal =>
      account?.summary.totalForUs ?? (receivableClaims + receivablePending);
  double get payableTotal =>
      account?.summary.totalAgainstUs ?? (payableClaims + payablePending);
  double get net => receivableTotal - payableTotal;
  bool get isArchived {
    final accountArchived = account?.summary.archived;
    if (accountArchived != null) return accountArchived;
    if (net.abs() >= 0.0001) {
      return false;
    }
    return true;
  }

  bool get hasOverdue {
    if (account == null) return false;
    final now = DateTime.now();
    for (final row in account!.rows) {
      if (row.status == CustomerLedgerRowStatus.open || row.status == CustomerLedgerRowStatus.partial) {
        if (row.direction == CustomerLedgerDirection.forUs) {
          if (now.difference(row.date).inDays >= 7) {
            return true;
          }
        }
      }
    }
    return false;
  }
}