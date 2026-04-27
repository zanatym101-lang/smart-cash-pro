import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../models/app_settings.dart';
import '../models/claim.dart';
import '../models/license_info.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import '../services/cloud_assistant_service.dart';
import '../widgets/app_title.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_AssistantMessage> _messages = <_AssistantMessage>[];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _AssistantMessage(
        isUser: false,
        text:
            'مرحبًا بك. اسألني عن:\n'
            '- السيولة والخزنة ورأس المال\n'
            '- الأرباح والمصروفات\n'
            '- المستحقات والآجل\n'
            '- طريقة عمل النظام المحاسبي',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask(String raw) async {
    final question = raw.trim();
    if (question.isEmpty || _loading) return;

    setState(() {
      _messages.add(_AssistantMessage(isUser: true, text: question));
      _controller.clear();
      _loading = true;
    });

    try {
      final results = await Future.wait<dynamic>([
        AppDb.instance.getTreasurySnapshot(),
        AppDb.instance.listTxns(),
        AppDb.instance.listClaims(),
        AppDb.instance.listWallets(),
        AppDb.instance.getAppSettings(),
        AppDb.instance.getWalletLimitUsage(),
        AppDb.instance.getLicenseInfo(),
      ]);

      final snap = results[0] as TreasurySnapshot;
      final txns = results[1] as List<Txn>;
      final claims = results[2] as List<Claim>;
      final wallets = results[3] as List<Wallet>;
      final settings = results[4] as AppSettings;
      final usageByWallet = results[5] as Map<int, WalletLimitUsage>;
      final license = results[6] as LicenseInfo;

      final walletSnapshots = await _loadWalletSnapshots(
        wallets: wallets,
        usageByWallet: usageByWallet,
      );

      final payload = _buildCloudPayload(
        question: question,
        snap: snap,
        txns: txns,
        claims: claims,
        settings: settings,
        wallets: walletSnapshots,
        deviceCode: license.deviceCode,
      );

      final localAnswer = _buildLocalAnswer(
        question: question,
        snap: snap,
        txns: txns,
        claims: claims,
        settings: settings,
        wallets: walletSnapshots,
      );

      String answer;
      try {
        answer = await CloudAssistantService.ask(payload);
        if (_looksInsufficient(answer)) {
          answer = localAnswer;
        }
      } catch (_) {
        answer = localAnswer;
      }

      if (!mounted) return;
      setState(
        () => _messages.add(_AssistantMessage(isUser: false, text: answer)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _AssistantMessage(
            isUser: false,
            text: 'تعذر قراءة البيانات من النظام: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<_WalletSnapshot>> _loadWalletSnapshots({
    required List<Wallet> wallets,
    required Map<int, WalletLimitUsage> usageByWallet,
  }) async {
    final rows = await Future.wait(
      wallets.map((wallet) async {
        final available = await AppDb.instance.getWalletAvailableBalance(
          wallet.id,
        );
        final actual = await AppDb.instance.getWalletBalance(wallet.id);
        final usage = usageByWallet[wallet.id];
        return _WalletSnapshot(
          id: wallet.id,
          name: wallet.name,
          phone: wallet.phone,
          provider: _providerFromPhone(wallet.phone),
          availableBalance: available,
          actualBalance: actual,
          dailyUsed: usage?.dailyUsed ?? 0,
          dailyLimit: usage?.dailyLimit ?? 0,
          monthlyUsed: usage?.monthlyUsed ?? 0,
          monthlyLimit: usage?.monthlyLimit ?? 0,
        );
      }),
    );
    rows.sort((a, b) => b.availableBalance.compareTo(a.availableBalance));
    return rows;
  }

  Map<String, dynamic> _buildCloudPayload({
    required String question,
    required TreasurySnapshot snap,
    required List<Txn> txns,
    required List<Claim> claims,
    required AppSettings settings,
    required List<_WalletSnapshot> wallets,
    required String deviceCode,
  }) {
    final sortedTxns = List<Txn>.from(txns)
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    final posted = sortedTxns.where((t) => t.status == 'posted').toList();
    final pending = sortedTxns.where((t) => t.status == 'pending').toList();

    final openClaims = claims.where((c) => c.status == 'open').toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    final receivable = openClaims
        .where((c) => c.type == 'receivable')
        .fold<double>(0, (s, c) => s + c.amount);
    final payable = openClaims
        .where((c) => c.type == 'payable')
        .fold<double>(0, (s, c) => s + c.amount);

    final txnsByStatus = <String, int>{};
    final postedByKind = <String, int>{};
    final pendingByKind = <String, int>{};
    final expensePosted = <String, double>{'count': 0, 'total': 0};

    for (final t in txns) {
      txnsByStatus[t.status] = (txnsByStatus[t.status] ?? 0) + 1;
      if (t.status == 'posted') {
        postedByKind[t.kind] = (postedByKind[t.kind] ?? 0) + 1;
        if (t.kind == 'expense') {
          expensePosted['count'] = (expensePosted['count'] ?? 0) + 1;
          expensePosted['total'] = (expensePosted['total'] ?? 0) + t.amount;
        }
      } else if (t.status == 'pending') {
        pendingByKind[t.kind] = (pendingByKind[t.kind] ?? 0) + 1;
      }
    }

    final recentTxns = sortedTxns.take(60).map((t) {
      return {
        'id': t.id,
        'kind': t.kind,
        'kindLabel': _kindLabel(t.kind),
        'status': t.status,
        'amount': t.amount,
        'clientFee': t.clientFee,
        'networkFee': t.networkFee,
        'mode': t.mode,
        'party': (t.party ?? '').trim(),
        'service': (t.serviceName ?? '').trim(),
        'reference': (t.reference ?? '').trim(),
        'note': _stripSystemTags(t.note),
        'entryDate': t.entryDate.toIso8601String(),
      };
    }).toList();

    final openClaimsRows = openClaims.take(80).map((c) {
      return {
        'id': c.id,
        'type': c.type,
        'typeLabel': c.type == 'receivable' ? 'مبلغ لنا' : 'مبلغ علينا',
        'party': c.party,
        'amount': c.amount,
        'entryDate': c.entryDate.toIso8601String(),
        'note': _stripSystemTags(c.note),
        'sourceTxnId': c.sourceTxnId,
      };
    }).toList();

    return {
      'question': question,
      'meta': {
        'generatedAt': DateTime.now().toIso8601String(),
        'businessName': settings.businessName,
        'currency': settings.currency,
        'dayStartHour': settings.dayStartHour,
        'deviceCode': deviceCode,
      },
      'programGuide': _programGuideData(),
      'snapshot': {
        'availableLiquidityNow': snap.availableLiquidityNow,
        'actualTreasuryApproved': snap.actualTreasuryApproved,
        'realCapitalApproved': snap.realCapitalApproved,
        'drawerActualBalance': snap.drawerActualBalance,
        'drawerBalance': snap.drawerBalance,
        'walletsActualTotal': snap.walletsActualTotal,
        'walletsTotal': snap.walletsTotal,
        'fawryActualBalance': snap.fawryActualBalance,
        'fawryBalance': snap.fawryBalance,
        'pendingCount': snap.pendingCount,
        'pendingInflow': snap.pendingInflow,
        'pendingOutflow': snap.pendingOutflow,
        'pendingNet': snap.pendingNet,
        'dailyProfit': snap.dailyProfit,
        'monthlyProfit': snap.monthlyProfit,
        'profitApprovedTotal': snap.profitApprovedTotal,
      },
      'wallets': wallets
          .map(
            (w) => {
              'id': w.id,
              'name': w.name,
              'phone': w.phone,
              'provider': w.provider,
              'availableBalance': w.availableBalance,
              'actualBalance': w.actualBalance,
              'dailyUsed': w.dailyUsed,
              'dailyLimit': w.dailyLimit,
              'monthlyUsed': w.monthlyUsed,
              'monthlyLimit': w.monthlyLimit,
            },
          )
          .toList(),
      'claims': {
        'openReceivable': receivable,
        'openPayable': payable,
        'openNet': receivable - payable,
        'openCount': openClaims.length,
        'openRows': openClaimsRows,
      },
      'txnsSummary': {
        'total': txns.length,
        'postedCount': posted.length,
        'pendingCount': pending.length,
        'byStatus': txnsByStatus,
        'postedByKind': postedByKind,
        'pendingByKind': pendingByKind,
        'expensePosted': expensePosted,
      },
      'recentTxns': recentTxns,
    };
  }

  String _buildLocalAnswer({
    required String question,
    required TreasurySnapshot snap,
    required List<Txn> txns,
    required List<Claim> claims,
    required AppSettings settings,
    required List<_WalletSnapshot> wallets,
  }) {
    final q = question.toLowerCase().trim();
    bool containsAny(List<String> keys) =>
        keys.any((k) => q.contains(k.toLowerCase()));
    String m(double v) => v.toStringAsFixed(2);

    final openClaims = claims.where((c) => c.status == 'open').toList();
    final receivable = openClaims
        .where((c) => c.type == 'receivable')
        .fold<double>(0, (s, c) => s + c.amount);
    final payable = openClaims
        .where((c) => c.type == 'payable')
        .fold<double>(0, (s, c) => s + c.amount);

    final posted = txns.where((t) => t.status == 'posted').toList();
    final pending = txns.where((t) => t.status == 'pending').toList();
    posted.sort((a, b) => b.entryDate.compareTo(a.entryDate));

    final responseMode = (() {
      if (containsAny([
        '?????',
        '??? ????',
        '???? ????',
        '????',
        '????????',
        '????? ????????',
      ])) {
        return 'how';
      }
      if (containsAny(['?????', '??????', '?? ????????', '???? ????'])) {
        return 'detailed';
      }
      if (containsAny(['?????', '???', '???', '?????', '?????', '???'])) {
        return 'diagnostic';
      }
      if (containsAny([
        '??',
        '?????',
        '???????',
        '????',
        '??? ?????',
        '???',
        '?????',
        '???',
        '?????',
        '????',
        '?????',
        '?????',
      ])) {
        return 'numeric';
      }
      return 'diagnostic';
    })();

    String singleLine(String text) => text.replaceAll('\n', ' | ').trim();

    String section(String title, String value) {
      final v = value.trim();
      if (v.isEmpty) return '';
      if (v.contains('\n')) return '$title:\n$v';
      return '$title: $v';
    }

    String compose({
      required String summary,
      required String numbers,
      required String formula,
      String notes = '',
      String action = '',
    }) {
      final s = section('??????? ????????', summary);
      final n = section('??????? ?????????', numbers);
      final f = section('????? ??????', formula);
      final no = section('??????? ????', notes);
      final ac = section('??????? ??????? ????', action);

      if (responseMode == 'numeric') {
        return [
          singleLine(s),
          singleLine(n),
          singleLine(f),
        ].where((e) => e.trim().isNotEmpty).join('\n');
      }

      return [s, n, f, no, ac].where((e) => e.trim().isNotEmpty).join('\n');
    }

    if (containsAny([
      '?????',
      '??? ????',
      '???? ????',
      '????',
      '????????',
      '????? ????????',
    ])) {
      return compose(
        summary: '??? ????? ??? ???????? ?????????.',
        numbers:
            '??? ????????: ${txns.length} | ???????: ${posted.length} | ??????: ${pending.length}',
        formula:
            '??????? ??????? = ?????? ??????? + ???? ??????\n??? ????? ??????? = ?????? ??????? + (??? - ?????)',
        notes: _programGuideText(),
        action: '??? ??????? ????????: ????? / ?????? / ???? / ???????.',
      );
    }

    if (containsAny(['????', '????? ????', '????? ??????', '?? ????????'])) {
      final topWallets = wallets.take(3).toList();
      final walletsText = topWallets.isEmpty
          ? '- ?? ???? ?????.'
          : topWallets
                .map(
                  (w) =>
                      '- ${w.name}: ???? ${m(w.availableBalance)} | ???? ${m(w.actualBalance)}',
                )
                .join('\n');

      return compose(
        summary: '???? ?????? ??????? ???? ????????.',
        numbers:
            '??????? ??????? ${m(snap.availableLiquidityNow)} | ?????? ??????? ${m(snap.actualTreasuryApproved)} | ??? ????? ??????? ${m(snap.realCapitalApproved)}',
        formula:
            '?????? ??? ????????? = ??? ${m(receivable)} - ????? ${m(payable)}',
        notes:
            '??? ????????: ?????? ${txns.length} | ????? ${posted.length} | ???? ${pending.length}\n???? ???????:\n$walletsText',
        action: '????? ??? ????? ?????? ????? ?? ????? ????.',
      );
    }

    if (containsAny(['?????', '???????'])) {
      return compose(
        summary:
            '??????? ??????? ???? ?? ${m(snap.availableLiquidityNow)} ${settings.currency}.',
        numbers:
            '?????? ??????? ${m(snap.actualTreasuryApproved)} | ?????? ?????? ${m(snap.pendingInflow)} | ???? ?????? ${m(snap.pendingOutflow)}',
        formula:
            '??????? ??????? = ?????? ??????? ??? ?????? ?????? ????????? ???????.',
        notes:
            '???? ??????/???? ?????? ????? ??????? ?????? ??????? ????? ??????.',
      );
    }

    if (containsAny(['????', '??? ?????'])) {
      return compose(
        summary:
            '?????? ??????? ${m(snap.actualTreasuryApproved)} ???? ????? ??????? ${m(snap.realCapitalApproved)}.',
        numbers:
            '??? ${m(receivable)} | ????? ${m(payable)} | ????? ????? ?????? ${m(snap.pendingInflow)} | ???? ????? ?????? ${m(snap.pendingOutflow)}',
        formula:
            '??? ????? ??????? = ?????? ??????? + ???????? ??????? ?????? ??? - ????????? ??????? ?????? ?????.',
        notes:
            '???? ??????/???? ?????? ????????? ??????? ?????? ???????? ???????.',
      );
    }

    if (containsAny(['??? ?????', '???', '?????'])) {
      return compose(
        summary: '????? ?????? ???? ????????.',
        numbers:
            '??? ????? ${m(snap.dailyProfit)} | ??? ????? ${m(snap.monthlyProfit)} | ?????? ????? ??????? ${m(snap.profitApprovedTotal)}',
        formula: '?????? ????? = ????? ????? ???????? ???????? ???.',
      );
    }

    if (containsAny(['?????', '???', '?????'])) {
      final net = receivable - payable;
      final netLabel = net >= 0 ? '???' : '?????';
      return compose(
        summary: '???? ????????? ${m(net.abs())} ($netLabel).',
        numbers: '??? ${m(receivable)} | ????? ${m(payable)}',
        formula: '${m(receivable)} - ${m(payable)} = ${m(net)}',
      );
    }

    if (containsAny(['????', '???????'])) {
      return compose(
        summary: '??? ???????? ??????? ${snap.pendingCount}.',
        numbers:
            '???? ?????? ${m(snap.pendingInflow)} | ???? ?????? ${m(snap.pendingOutflow)}',
        formula:
            '???? ???????? ??????? ????????. ?? ????? ?????? ?????? ??????? ????? ?? ??? ????? ???????.',
        notes:
            '???? ?????? ?????? ???? ????????? ? ???? ?????? ?????? ???? ????????? ??????.',
      );
    }

    if (containsAny(['?????', '?????'])) {
      if (wallets.isEmpty) {
        return compose(
          summary: '?? ???? ????? ??????.',
          numbers: '?????? ??????? ?????? 0.00 | ?????? ??????? ?????? 0.00',
          formula: '?? ???? ?? ??? ????? ??????.',
        );
      }
      final rows = wallets
          .take(6)
          .map(
            (w) =>
                '${w.name} (${w.provider}) - ???? ${m(w.availableBalance)} / ???? ${m(w.actualBalance)}',
          )
          .join('\n');
      return compose(
        summary: '?????? ??????? ???? ????????.',
        numbers:
            '?????? ?????? ${m(snap.walletsTotal)} | ?????? ?????? ${m(snap.walletsActualTotal)}',
        formula: '?????? ??????? = ????? ????? ??????? ??? ?????? ????????.',
        notes: rows,
      );
    }

    if (containsAny(['??? ?????', '??? ?????', '???? ?????'])) {
      if (posted.isEmpty) {
        return compose(
          summary: '?? ???? ?????? ?????? ??????.',
          numbers: '?????? ??????? 0',
          formula: '?? ???? ?? ??? ?????.',
        );
      }
      final last = posted.first;
      return compose(
        summary: '??? ????? ??????: ${_kindLabel(last.kind)}.',
        numbers:
            '?????? ${m(last.amount)} | ?????? ${_statusLabel(last.status)} | ????? ${last.entryDate}',
        formula:
            '?? ??? ???? ????? ??? ????? ???????? ???????? ???????? ??? ???????.',
      );
    }

    return compose(
      summary: '?????? ????? ????? ????.',
      numbers: '?? ???? ????? ????? ???????? ????? ?????.',
      formula: '?? ???? ????? ?????? ??? ????? ??? ??????.',
      notes:
          '?????: ?? ??????? ???????? | ?? ???? ?????????? | ???? ????? ??? ????????.',
      action: '???? ????? ????? ?????? ?? ????? ?????? ?? ?????? ??? ??????.',
    );
  }

  bool _looksInsufficient(String text) {
    final t = text.toLowerCase();
    return t.contains('لا تتوفر بيانات كافية') ||
        t.contains('غير متاح') ||
        t.contains('غير متوفرة') ||
        t.contains('غير كافية');
  }

  String _stripSystemTags(String? text) {
    if (text == null || text.trim().isEmpty) return '';
    var v = text;
    v = v.replaceAll(RegExp(r'claim_id:\d+'), '');
    v = v.replaceAll(RegExp(r'pending_txn:\d+'), '');
    v = v.replaceAll(RegExp(r'\s{2,}'), ' ');
    return v.trim();
  }

  String _providerFromPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('010')) return 'فودافون';
    if (digits.startsWith('011')) return 'اتصالات';
    if (digits.startsWith('012')) return 'أورنج';
    if (digits.startsWith('015')) return 'وي';
    return 'غير محدد';
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'transfer':
        return 'تحويل';
      case 'receive':
        return 'استلام';
      case 'expense':
        return 'مصروف';
      case 'external_funding':
        return 'تمويل محفظة';
      case 'drawer_deposit':
        return 'تعديل الدرج';
      case 'claim_open_receivable':
        return 'فتح مستحق لنا';
      case 'claim_open_payable':
        return 'فتح مستحق علينا';
      case 'claim_collect':
        return 'تحصيل مستحق';
      case 'claim_pay':
        return 'سداد مستحق';
      case 'fawry_cash':
        return 'خدمة نقدية';
      case 'fawry_credit':
        return 'خدمة آجلة';
      case 'fawry_fund_drawer':
        return 'شحن رصيد خدمة من الدرج';
      case 'pending_settlement_adjust':
        return 'تسوية آجل';
      default:
        return kind;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'posted':
        return 'معتمد';
      case 'pending':
        return 'آجل';
      case 'canceled':
        return 'ملغي';
      case 'rolled_back':
        return 'معكوس';
      default:
        return status;
    }
  }

  Map<String, dynamic> _programGuideData() {
    return {
      'principles': [
        'وحدة الحساب الداخلية قرش، والعرض في الواجهة جنيه.',
        'المحافظ لا تصبح سالبة.',
        'الدرج قد يصبح سالبًا حسب التشغيل.',
      ],
      'liquidityFormulas': {
        'actualTreasuryApproved': 'drawerActual + walletsActual + fawryActual',
        'availableLiquidityNow':
            'cash only = actualTreasuryApproved',
        'realCapitalApproved':
            'actualTreasuryApproved + open receivables - open payables',
      },
      'claimsMeaning': {'receivable': 'مبالغ لنا', 'payable': 'مبالغ علينا'},
      'txnRules': {
        'transfer':
            'تحويل نوع 1: عمولة كاش. تحويل نوع 2: خصم من المبلغ مع رسوم شبكة.',
        'receive': 'استلام نقدي/خصم/إلكتروني حسب نوع العملية.',
        'claims': 'تحصيل/سداد المستحقات يدعم جزئي وكلي.',
      },
    };
  }

  String _programGuideText() {
    return 'طريقة عمل البرنامج المحاسبية باختصار:\n'
        '1) كل حركة تُسجل كعملية (آجلة أو معتمدة).\n'
        '2) السيولة المتاحة تعكس النقد الفعلي فقط، والآجل يبقى مؤشرات متابعة منفصلة.\n'
        '3) المستحقات نوعان: لنا (Receivable) وعلينا (Payable).\n'
        '4) مؤشرات داخل الأجل/خارج الأجل للمتابعة فقط، ولا تُضاف أو تُطرح من السيولة مرة أخرى.\n'
        '5) رأس المال الحقيقي = النقد الفعلي + ما لنا مفتوحًا - ما علينا مفتوحًا.\n'
        '6) التحويل/الاستلام يتابعان كأثر نقدي وكمتابعة آجلة حسب نوع العملية.\n'
        '7) التحصيل الجزئي يقلل المستحق ويُبقيه مفتوحًا حتى الإغلاق الكامل.\n'
        '8) النظام يمنع سالب المحافظ ويحافظ على اتساق القيود.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'المساعد الذكي')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 380),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? const Color(0xFF0F172A)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: message.isUser ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    decoration: const InputDecoration(
                      labelText: 'اكتب سؤالك',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _ask(_controller.text),
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('إرسال'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantMessage {
  final bool isUser;
  final String text;

  const _AssistantMessage({required this.isUser, required this.text});
}

class _WalletSnapshot {
  final int id;
  final String name;
  final String phone;
  final String provider;
  final double availableBalance;
  final double actualBalance;
  final double dailyUsed;
  final double dailyLimit;
  final double monthlyUsed;
  final double monthlyLimit;

  const _WalletSnapshot({
    required this.id,
    required this.name,
    required this.phone,
    required this.provider,
    required this.availableBalance,
    required this.actualBalance,
    required this.dailyUsed,
    required this.dailyLimit,
    required this.monthlyUsed,
    required this.monthlyLimit,
  });
}
