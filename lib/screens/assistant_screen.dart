import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../models/claim.dart';
import '../models/transaction.dart';
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
            'أهلاً بك. اسألني عن: السيولة، الخزنة الفعلية، المعلق، الأرباح، المستحقات، الدرج، المحافظ، فوري.',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || _loading) return;

    setState(() {
      _messages.add(_AssistantMessage(isUser: true, text: q));
      _controller.clear();
      _loading = true;
    });

    try {
      final result = await Future.wait([
        AppDb.instance.getTreasurySnapshot(),
        AppDb.instance.listTxns(),
        AppDb.instance.listClaims(),
      ]);

      final snap = result[0] as TreasurySnapshot;
      final txns = result[1] as List<Txn>;
      final claims = result[2] as List<Claim>;

      final payload = _buildCloudPayload(
        question: q,
        snap: snap,
        txns: txns,
        claims: claims,
      );

      final localAnswer = _buildAnswer(
        question: q,
        snap: snap,
        txns: txns,
        claims: claims,
      );
      final useLocal = !_isGenericAnswer(localAnswer);

      String answer;
      if (useLocal) {
        answer = localAnswer;
      } else {
        try {
          answer = await CloudAssistantService.ask(payload);
        } catch (_) {
          answer = localAnswer;
        }
      }

      if (!mounted) return;
      setState(
        () => _messages.add(_AssistantMessage(isUser: false, text: answer)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _AssistantMessage(isUser: false, text: 'تعذر قراءة البيانات: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isGenericAnswer(String text) {
    return text.contains('يمكنك سؤالي بصيغة مباشرة');
  }

  String _stripTags(String? note) {
    if (note == null || note.trim().isEmpty) return '';
    var v = note;
    v = v.replaceAll(RegExp(r'claim_id:\d+'), '');
    v = v.replaceAll(RegExp(r'pending_txn:\d+'), '');
    v = v.replaceAll(RegExp(r'\s+-\s+-+'), ' - ');
    return v.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  Map<String, dynamic> _buildCloudPayload({
    required String question,
    required TreasurySnapshot snap,
    required List<Txn> txns,
    required List<Claim> claims,
  }) {
    final posted = txns.where((t) => t.status == 'posted').toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    final recent = posted.take(20).map((t) {
      return {
        'id': t.id,
        'kind': t.kind,
        'status': t.status,
        'amount': t.amount,
        'clientFee': t.clientFee,
        'networkFee': t.networkFee,
        'mode': t.mode,
        'entryDate': t.entryDate.toIso8601String(),
        'party': (t.party ?? '').trim(),
        'note': _stripTags(t.note),
        'reference': (t.reference ?? '').trim(),
        'service': (t.serviceName ?? '').trim(),
      };
    }).toList();

    final openClaims = claims.where((c) => c.status == 'open').toList();
    final receivable = openClaims
        .where((c) => c.type == 'receivable')
        .fold<double>(0, (s, c) => s + c.amount);
    final payable = openClaims
        .where((c) => c.type == 'payable')
        .fold<double>(0, (s, c) => s + c.amount);

    return {
      'question': question,
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
      'claims': {
        'openReceivable': receivable,
        'openPayable': payable,
        'count': openClaims.length,
      },
      'recentTxns': recent,
    };
  }

  String _buildAnswer({
    required String question,
    required TreasurySnapshot snap,
    required List<Txn> txns,
    required List<Claim> claims,
  }) {
    final q = question.toLowerCase();
    bool hasAny(List<String> keys) => keys.any(q.contains);
    String money(double v) => v.toStringAsFixed(2);

    final postedTxns = txns.where((t) => t.status == 'posted').toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    final latest = postedTxns.isNotEmpty ? postedTxns.first : null;

    if (hasAny(['سيولة', 'المتاحة'])) {
      return 'السيولة المتاحة الآن = ${money(snap.availableLiquidityNow)}\n'
          'الخزنة الفعلية = ${money(snap.actualTreasuryApproved)}\n'
          'صافي المعلق = ${money(snap.pendingNet)}';
    }

    if (hasAny(['خزنة', 'الخزنة الفعلية', 'رأس المال'])) {
      return 'الخزنة الفعلية = ${money(snap.actualTreasuryApproved)}\n'
          'رأس المال الحقيقي (معتمد) = ${money(snap.realCapitalApproved)}';
    }

    if (hasAny(['درج', 'الخزنة'])) {
      return 'الدرج (فعلي) = ${money(snap.drawerActualBalance)}\n'
          'الدرج (متاح) = ${money(snap.drawerBalance)}';
    }

    if (hasAny(['محفظ', 'محافظ'])) {
      return 'المحافظ (فعلي) = ${money(snap.walletsActualTotal)}\n'
          'المحافظ (متاح) = ${money(snap.walletsTotal)}';
    }

    if (hasAny(['فوري'])) {
      return 'فوري (فعلي) = ${money(snap.fawryActualBalance)}\n'
          'فوري (متاح) = ${money(snap.fawryBalance)}';
    }

    if (hasAny(['ربح اليوم', 'اليوم'])) {
      return 'ربح اليوم = ${money(snap.dailyProfit)}\n'
          'ربح الشهر = ${money(snap.monthlyProfit)}';
    }

    if (hasAny(['ربح الشهر', 'الشهر'])) {
      return 'ربح الشهر = ${money(snap.monthlyProfit)}\n'
          'إجمالي الربح المعتمد = ${money(snap.profitApprovedTotal)}';
    }

    if (hasAny(['معلق', 'المعلقة'])) {
      return 'عدد العمليات المعلقة = ${snap.pendingCount}\n'
          'داخل المعلق = ${money(snap.pendingInflow)}\n'
          'خارج المعلق = ${money(snap.pendingOutflow)}\n'
          'صافي المعلق = ${money(snap.pendingNet)}';
    }

    if (hasAny(['مستحق', 'لنا', 'علينا'])) {
      final receivable = claims
          .where((c) => c.status == 'open' && c.type == 'receivable')
          .fold<double>(0, (s, c) => s + c.amount);
      final payable = claims
          .where((c) => c.status == 'open' && c.type == 'payable')
          .fold<double>(0, (s, c) => s + c.amount);
      final net = receivable - payable;
      final netLabel = net >= 0 ? 'لنا' : 'علينا';
      return 'مبالغ لنا (مفتوحة) = ${money(receivable)}\n'
          'مبالغ علينا (مفتوحة) = ${money(payable)}\n'
          'الفرق = ${money(net.abs())} ($netLabel)';
    }

    if (hasAny(['اخر', 'آخر', 'عملية'])) {
      if (latest == null) return 'لا توجد عمليات معتمدة بعد.';
      return 'آخر عملية معتمدة:\n'
          'النوع: ${_kindLabel(latest.kind)}\n'
          'المبلغ: ${money(latest.amount)}\n'
          'الوقت: ${latest.entryDate}';
    }

    return 'يمكنك سؤالي بصيغة مباشرة مثل:\n'
        '1. كم السيولة المتاحة؟\n'
        '2. كم رصيد الدرج؟\n'
        '3. كم المعلق؟\n'
        '4. كم أرباح اليوم؟\n'
        '5. كم مبالغ لنا وعلينا؟';
  }

  String _kindLabel(String k) {
    switch (k) {
      case 'transfer':
        return 'تحويل';
      case 'receive':
        return 'استلام';
      case 'expense':
        return 'مصروف';
      case 'external_funding':
        return 'تمويل محفظة';
      case 'drawer_deposit':
        return 'تعديل درج';
      case 'claim_collect':
        return 'تحصيل مستحقات';
      case 'claim_pay':
        return 'سداد مستحقات';
      case 'fawry_cash':
        return 'فوري نقدي';
      case 'fawry_credit':
        return 'فوري آجل';
      case 'fawry_fund_drawer':
        return 'شحن فوري من الدرج';
      default:
        return k;
    }
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
                final m = _messages[index];
                return Align(
                  alignment: m.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 360),
                    decoration: BoxDecoration(
                      color: m.isUser
                          ? const Color(0xFF0F172A)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        color: m.isUser ? Colors.white : Colors.black87,
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
