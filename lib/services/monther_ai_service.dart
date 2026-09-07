import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../application/write_gateway/clean_write_gateway.dart';
import '../application/write_gateway/write_intents.dart';
import '../data/app_db.dart';
import '../data/sqlite/customer_adjustments_repository.dart';
import '../domain/models/customer_account.dart';
import '../domain/models/money.dart';
import 'package:uuid/uuid.dart';
import '../screens/customer_account/customer_account_builder.dart';

class MontherAiService {
  static final MontherAiService instance = MontherAiService._();
  MontherAiService._();

  GenerativeModel? _model;
  ChatSession? _chatSession;

  // ذاكرة المحادثات المحفوظة
  static const String _historyKey = 'monther_chat_history';
  static const int _maxSavedMessages = 40;

  bool get isInitialized => _model != null;

  void init(String apiKey) {
    if (apiKey.trim().isEmpty) return;
    _model = GenerativeModel(
      model: 'gemini-3.6-flash',
      apiKey: apiKey,
    );
  }

  /// تحميل تاريخ المحادثة من الذاكرة المحلية
  Future<List<Map<String, String>>> loadSavedHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map((m) => {'role': m['role'] as String, 'text': m['text'] as String})
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// حفظ تاريخ المحادثة في الذاكرة المحلية
  Future<void> saveHistory(List<Map<String, String>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final toSave = messages.length > _maxSavedMessages
        ? messages.sublist(messages.length - _maxSavedMessages)
        : messages;
    await prefs.setString(_historyKey, jsonEncode(toSave));
  }

  /// مسح تاريخ المحادثة
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<void> startNewChat({List<Map<String, String>>? savedHistory}) async {
    if (!isInitialized) return;
    final contextData = await _buildContextString();

    // بناء تاريخ المحادثة مع السياق الافتراضي
    final history = <Content>[
      Content.text(contextData),
      Content.model([
        TextPart(
          'مرحباً! أنا **منذر**، مساعدك الذكي في **سمارت كاش برو**. '
          'اطلعت على حساباتك ومعاملاتك. '
          'كيف يمكنني مساعدتك؟',
        ),
      ]),
    ];

    // إضافة المحادثات السابقة المحفوظة
    if (savedHistory != null && savedHistory.isNotEmpty) {
      for (final msg in savedHistory) {
        final role = msg['role'];
        final text = msg['text'] ?? '';
        if (role == 'user') {
          history.add(Content.text(text));
        } else {
          history.add(Content.model([TextPart(text)]));
        }
      }
    }

    _chatSession = _model!.startChat(history: history);
  }

  /// توليد تقرير يومي تلقائي
  Future<String> generateDailyReport() async {
    if (_chatSession == null) return '';
    try {
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final prompt =
          'قدّم لي تقريراً يومياً موجزاً ومنظماً عن اليوم ($todayStr). '
          'يشمل: الربح اليوم، معاملات اليوم، '
          'العملاء الذين لديهم بنود مفتوحة أو متأخرة، '
          'وأي تنبيهات أو ملاحظات مهمة. '
          'أجب بتنسيق جميل مع استخدام الرموز التعبيرية.';
      final response = await _chatSession!.sendMessage(Content.text(prompt));
      return response.text ?? '';
    } catch (e) {
      return '';
    }
  }


  Future<String> _buildContextString() async {
    final db = AppDb.instance;
    final wallets = await db.listWallets();
    final snapshot = await db.getTreasurySnapshot();
    final allClaims = await db.listClaims();
    final openClaims = allClaims.where((c) => c.status == 'open').toList();
    final allTxns = await db.listTxns();
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // ===================== معاملات اليوم التفصيلية =====================
    final todayTxns = allTxns.where((t) {
      final d = t.entryDate;
      return d.year == today.year &&
          d.month == today.month &&
          d.day == today.day &&
          t.status == 'posted';
    }).toList();
    double todayProfit = 0;
    final todayBuffer = StringBuffer();
    if (todayTxns.isEmpty) {
      todayBuffer.writeln('لا توجد معاملات مسجلة اليوم بعد.');
    } else {
      for (final t in todayTxns) {
        if (t.kind == 'transfer' || t.kind == 'fawry_credit') {
          todayProfit += t.clientFee;
        }
        todayBuffer.writeln(
          '• ${_kindAr(t.kind)}'
          ' | ${t.amount.toStringAsFixed(2)} ج'
          '${t.clientFee > 0 ? " | رسوم: ${t.clientFee.toStringAsFixed(2)} ج" : ""}'
          '${t.party != null ? " | الطرف: ${t.party}" : ""}'
          '${t.note != null && t.note!.isNotEmpty ? " | ملاحظة: ${t.note}" : ""}',
        );
      }
    }

    // Recent transactions (last 15 posted)
    final recentPosted = allTxns.where((t) => t.status == 'posted').take(15).toList();

    // Customer accounts
    final accounts = CustomerAccountBuilder.fromAppDbData(
      txns: allTxns,
      claims: allClaims,
      wallets: wallets,
    );

    // ===================== اقتراحات ذكية: عملاء متأخرون =====================
    final alertBuffer = StringBuffer();
    for (final acc in accounts) {
      final summary = acc.summary;
      final openForUs = summary.openDeferredForUs + summary.openClaimsForUs;
      if (openForUs > 0.01) {
        // أقدم مطالبة مفتوحة لهذا العميل
        final customerClaims = openClaims
            .where((c) => c.type == 'receivable' && c.party == summary.customerName)
            .toList()
          ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
        if (customerClaims.isNotEmpty) {
          final oldest = customerClaims.first;
          final daysDue = today.difference(oldest.entryDate).inDays;
          if (daysDue >= 7) {
            alertBuffer.writeln(
              '⚠️ "${summary.customerName}": مستحقات لنا ${openForUs.toStringAsFixed(2)} ج منذ $daysDue يوماً'
              ' (أقدم مطالبة: ${oldest.entryDate.toString().substring(0, 10)})',
            );
          }
        }
      }
    }

    // Build customer summary
    final customerSummary = StringBuffer();
    for (final acc in accounts) {
      final summary = acc.summary;
      final net = summary.totalForUs - summary.totalAgainstUs;
      final openForUs = summary.openDeferredForUs + summary.openClaimsForUs;
      final openAgainstUs =
          summary.openDeferredAgainstUs + summary.openClaimsAgainstUs;
      final status =
          openForUs.abs() < 0.01 && openAgainstUs.abs() < 0.01 && net.abs() < 0.01
              ? 'مغلق'
              : net.abs() < 0.01
              ? 'متعادل'
              : 'مفتوح';
      customerSummary.writeln(
        'العميل "${summary.customerName}"${summary.phone != null ? " (${summary.phone})" : ""}: '
        'لنا: ${summary.totalForUs.toStringAsFixed(2)} | '
        'علينا: ${summary.totalAgainstUs.toStringAsFixed(2)} | '
        'الصافي: ${net.toStringAsFixed(2)} | '
        'مفتوح لنا: ${openForUs.toStringAsFixed(2)} | '
        'مفتوح علينا: ${openAgainstUs.toStringAsFixed(2)} | '
        'الحالة: $status',
      );

    }
    
    // Customer Insights
    final activeAccounts = accounts.where((a) => !a.summary.archived).toList();
    activeAccounts.sort((a, b) => b.summary.netBalance.compareTo(a.summary.netBalance));
    final topDebtors = activeAccounts.where((a) => a.summary.netBalance > 0).take(3).toList();
    
    activeAccounts.sort((a, b) => a.summary.netBalance.compareTo(b.summary.netBalance));
    final topCreditors = activeAccounts.where((a) => a.summary.netBalance < 0).take(3).toList();

    if (topDebtors.isNotEmpty) {
      customerSummary.writeln('\nأكثر العملاء مديونية (لنا):');
      for (final a in topDebtors) {
        customerSummary.writeln('- ${a.summary.customerName}: ${a.summary.netBalance.toStringAsFixed(2)} ج');
      }
    }
    if (topCreditors.isNotEmpty) {
      customerSummary.writeln('\nأكثر العملاء دائنية (علينا):');
      for (final a in topCreditors) {
        customerSummary.writeln('- ${a.summary.customerName}: ${a.summary.netBalance.abs().toStringAsFixed(2)} ج');
      }
    }

    // Wallet balances
    final walletSummary = StringBuffer();
    for (final w in wallets) {
      final bal = await db.getWalletBalance(w.id);
      walletSummary.writeln(
        '- محفظة "${w.name}": الرصيد = ${bal.toStringAsFixed(2)}',
      );
    }

    // Claims summary per customer
    final claimsBuffer = StringBuffer();
    final claimsMap = <String, Map<String, double>>{};
    for (final c in openClaims) {
      claimsMap.putIfAbsent(c.party, () => {'receivable': 0, 'payable': 0});
      claimsMap[c.party]![c.type] =
          (claimsMap[c.party]![c.type] ?? 0) + c.amount;
    }
    if (claimsMap.isEmpty) {
      claimsBuffer.writeln('لا توجد مستحقات مفتوحة حالياً.');
    } else {
      for (final entry in claimsMap.entries) {
        final rec = entry.value['receivable'] ?? 0;
        final pay = entry.value['payable'] ?? 0;
        claimsBuffer.writeln(
          '- ${entry.key}: مستحق لنا: ${rec.toStringAsFixed(2)} | مستحق علينا: ${pay.toStringAsFixed(2)}',
        );
      }
    }

    // Recent transactions summary
    final recentBuffer = StringBuffer();
    for (final t in recentPosted.take(15)) {
      final kindAr = _kindAr(t.kind);
      recentBuffer.writeln(
        '- $kindAr | ${t.amount.toStringAsFixed(2)} ج | '
        '${t.party ?? ""} | ${t.entryDate.toString().substring(0, 10)} | ${t.note ?? ""}',
      );
    }

    final buf = StringBuffer();

    // ===================== LAYER 1: SYSTEM IDENTITY =====================
    buf.writeln('''
أنت "منذر"، المساعد الذكي المالي والمحاسبي المدمج في برنامج "سمارت كاش برو".
طوّرك فريق متخصص لمساعدة مستخدمي البرنامج على فهم حساباتهم واتخاذ قرارات مالية صحيحة.
تاريخ اليوم: $todayStr

==== هويتك وأسلوبك ====
- اسمك "منذر" وتتحدث دائماً بضمير المتكلم
- أسلوبك: احترافي، ودود، واضح، ومختصر
- تكتب الأرقام بشكل جميل ومنسق
- لا تُطوّل الرد إلا إذا طُلب منك التفاصيل
- إذا لم تجد المعلومة في البيانات، أخبر المستخدم بتفقد الشاشة المناسبة في التطبيق
- لا تُجيب على أسئلة خارج نطاق البرنامج المالي
''');

    // ===================== LAYER 2: HOW THE APP WORKS =====================
    buf.writeln('''
==== كيف يعمل برنامج سمارت كاش برو ====

البرنامج نظام محاسبي متكامل لإدارة تحويلات الأموال والمحافظ الإلكترونية.

**المحافظ (Wallets):**
كل محفظة تمثل حساباً إلكترونياً (مثل: محفظة فودافون كاش، اتصالات كاش، إلخ).
كل محفظة لها رصيد خاص بها.

**الخزنة (Treasury):**
الخزنة الفعلية = مجموع أرصدة كل المحافظ + النقد الحقيقي.
السيولة المتاحة = المبلغ الجاهز للصرف الفوري (لا يشمل المعلّقة).

**العمليات الرئيسية:**
1. تحويل (transfer): إرسال مبلغ من محفظة إلى شخص ما
2. استلام (receive): استلام مبلغ من شخص في محفظة
3. صرف (expense): مصروف من الخزنة
4. تمويل محفظة (wallet_funding): إضافة رصيد لمحفظة

**الآجل (Deferred/Pending):**
عندما يدفع أحد الأموال لكن المبلغ لم يُسلَّم بعد (أو العكس)، تصبح العملية "آجلة".
- تحويل آجل: أرسلنا للعميل ولم يدفع لنا بعد
- استلام آجل: العميل دفع لنا ولكن لم نُسلّم بعد

**المستحقات (Claims):**
- مستحق لنا (receivable): شخص مديون لنا بمبلغ محدد
- مستحق علينا (payable): نحن مدينون لشخص بمبلغ محدد
- المستحق "مفتوح" = لم يُسدَّد بعد
- المستحق "مغلق" = تم تسديده

**حسابات العملاء:**
كل عميل له حساب يجمع كل المعاملات معه (آجلة + مستحقات).
- "لنا": مجموع ما يديننا به العميل
- "علينا": مجموع ما ندين به للعميل
- "الصافي": الفرق (موجب = العميل مدين لنا | سالب = نحن مدينون له)
- "متعادل": الصافي صفر لكن يوجد بنود مفتوحة
- "مغلق": كل الحسابات صفر ومغلقة

**الأرباح:**
الربح = رسوم العمليات (clientFee) من التحويلات والعمليات.
''');

    // ===================== LAYER 3: LIVE FINANCIAL DATA =====================
    buf.writeln('''
==== البيانات المالية الحالية (محدّثة لحظياً) ====

📊 ملخص الخزنة:
- السيولة المتاحة الآن: ${snapshot.availableLiquidityNow.toStringAsFixed(2)} ج.م
- الخزنة الفعلية (الإجمالي): ${snapshot.actualTreasuryApproved.toStringAsFixed(2)} ج.م
- إجمالي مستحقاتنا (لنا): ${snapshot.claimsReceivableOpen.toStringAsFixed(2)} ج.م
- إجمالي مستحقاتنا (علينا): ${snapshot.claimsPayableOpen.toStringAsFixed(2)} ج.م
- ربح اليوم ($todayStr): ${todayProfit.toStringAsFixed(2)} ج.م

💼 أرصدة المحافظ:
${walletSummary.toString().trim()}

📅 معاملات اليوم ($todayStr) — ${todayTxns.length} معاملة — ربح: ${todayProfit.toStringAsFixed(2)} ج.م:
${todayBuffer.toString().trim()}

📋 المستحقات المفتوحة تفصيلاً:
${claimsBuffer.toString().trim()}

${alertBuffer.isNotEmpty ? "🚨 تنبيهات عملاء متأخرون عن السداد:\n${alertBuffer.toString().trim()}\n" : "✅ لا توجد تأخيرات في السداد تستحق التنبيه حالياً.\n"}

👥 حسابات العملاء (جميع العملاء):
${customerSummary.toString().trim()}

📜 آخر 15 عملية مسجلة:
${recentBuffer.toString().trim()}
''');

    // ===================== LAYER 4: SCREEN GUIDE =====================
    buf.writeln('''
==== دليل شاشات البرنامج ====
إذا سألك المستخدم عن كيفية استخدام شاشة معينة، أرشده إلى:

- الرئيسية (Dashboard): ملخص سريع للخزنة والعمليات المعلقة + الإجراءات السريعة
- المحافظ: عرض كل المحافظ وأرصدتها وكشف حسابها
- العملاء: عرض كل العملاء وحساباتهم التفصيلية (لنا، علينا، آجل، مستحق)
- التحويل: إرسال مبلغ لشخص (يمكن فورياً أو آجلاً)
- الاستلام: استلام مبلغ من شخص
- المصروفات: تسجيل مصروف يُخصم من الخزنة
- التقارير: عرض ملخص الأرباح والعمليات خلال فترة زمنية
- الخزينة: عرض كشف حساب كامل لحركة الخزنة
- المعلّقة (Pending): عرض العمليات التي لم تكتمل بعد (آجلة)
- الإعدادات: إدارة كلمة المرور، النسخ الاحتياطي، المزامنة
''');

    buf.writeln('''
==== تعليمات نهائية مهمة ====
1. إذا سأل عن عميل بالاسم، ابحث عنه في "حسابات العملاء" أعلاه وأعطه البيانات الدقيقة
2. إذا سأل "ماذا عملنا اليوم؟" أو "معاملات اليوم"، أجب من قائمة "معاملات اليوم" أعلاه
3. إذا رأيت عملاء في قائمة "تنبيهات المتأخرين"، اذكرهم بشكل استباقي عند المناسبة
4. إذا كان الرصيد منخفضاً أو العميل متأخراً في السداد، نبّه المستخدم بلطف
5. دائماً اذكر الأرقام بوحدة "ج.م" (جنيه مصري)
6. اسمك "منذر" ولا تعرّف عن نفسك بأي اسم آخر
7. تتذكر محادثاتنا السابقة وتستند إليها عند الحاجة
8. **تسجيل العمليات**: إذا طلب منك المستخدم تسجيل "مصروف" أو "دخل" أو إضافة "عميل جديد"، قم بالرد بنص عادي كما تحب ولكن أضف في نهاية ردك كود التسجيل التالي:
[ACTION:ADD_EXPENSE:المبلغ:التفاصيل] أو [ACTION:ADD_INCOME:المبلغ:التفاصيل]
أو لإضافة عميل:
[ACTION:ADD_CUSTOMER:الاسم:رقم_الموبايل:المبلغ_الابتدائي_موجب_لنا_سالب_علينا:ملاحظة]
(مثال: إضافة عميل إبراهيم 0100 بمديونية 500 له: [ACTION:ADD_CUSTOMER:إبراهيم:0100:-500:رصيد افتتاحي]).
''');

    return buf.toString();
  }

  String _kindAr(String kind) {
    return switch (kind) {
      'transfer' => 'تحويل',
      'receive' => 'استلام',
      'expense' => 'مصروف',
      'wallet_funding' => 'تمويل محفظة',
      'claim_collect' => 'تحصيل مستحق',
      'claim_pay' => 'سداد مستحق',
      'fawry_credit' => 'فوري',
      _ => kind,
    };
  }

  Future<String> sendMessage(String text) async {
    if (_chatSession == null) {
      return 'عذراً، يجب إدخال API Key أولاً.';
    }
    try {
      final response = await _chatSession!.sendMessage(Content.text(text));
      var responseText = response.text ?? 'لا يوجد رد.';

      // Intercept Action Commands
      if (responseText.contains('[ACTION:ADD_EXPENSE:')) {
        final regex = RegExp(r'\[ACTION:ADD_EXPENSE:(.+?):(.+?)\]');
        final match = regex.firstMatch(responseText);
        if (match != null) {
          final amountStr = match.group(1) ?? '0';
          final note = match.group(2) ?? '';
          final amount = double.tryParse(amountStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
          
          if (amount > 0) {
            await CleanWriteGateway.appDbBridge().execute(
              ExpenseIntent(
                action: ExpenseIntentAction.create,
                amount: amount,
                category: 'منذر',
                note: note,
              ),
            );
            // إزالة سطر الأمر من الرد
            responseText = responseText.replaceAll(match.group(0)!, '').trim();
          }
        }
      }
      if (responseText.contains('[ACTION:ADD_INCOME:')) {
        final regex = RegExp(r'\[ACTION:ADD_INCOME:(.+?):(.+?)\]');
        final match = regex.firstMatch(responseText);
        if (match != null) {
          final amountStr = match.group(1) ?? '0';
          final note = match.group(2) ?? '';
          final amount = double.tryParse(amountStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
          
          if (amount > 0) {
            await CleanWriteGateway.appDbBridge().execute(
              DrawerDepositIntent(
                amount: amount,
                note: note,
              ),
            );
            responseText = responseText.replaceAll(match.group(0)!, '').trim();
          }
        }
      }

      if (responseText.contains('[ACTION:ADD_CUSTOMER:')) {
        final regex = RegExp(r'\[ACTION:ADD_CUSTOMER:(.+?):(.+?):(.+?):(.+?)\]');
        final match = regex.firstMatch(responseText);
        if (match != null) {
          final name = match.group(1)?.trim() ?? '';
          
          final amountStr = match.group(3) ?? '0';
          final note = match.group(4) ?? '';
          final amount = double.tryParse(amountStr.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0.0;
          
          if (name.isNotEmpty) {
            final repo = CustomerAdjustmentsRepository(AppDb.instance.sqlite);
            await repo.saveAdjustment(
              CustomerAccountAdjustment(
                id: const Uuid().v4(),
                customerId: name,
                type: amount >= 0 ? CustomerAdjustmentType.add : CustomerAdjustmentType.subtract,
                amount: Money((amount.abs() * 100).toInt()),
                date: DateTime.now(),
                note: note,
              )
            );
            responseText = responseText.replaceAll(match.group(0)!, '').trim();
          }
        }

        if (responseText.contains('[ACTION:ADD_TRANSFER:')) {
          final regex = RegExp(r'\[ACTION:ADD_TRANSFER:(.+?):(.+?):(.+?):(.+?):(.+?):(.+?)\]');
          final match = regex.firstMatch(responseText);
          if (match != null) {
            final amount = double.tryParse(match.group(1)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0.0;
            final walletId = int.tryParse(match.group(2)?.replaceAll(RegExp(r'[^0-9]'), '') ?? '1') ?? 1;
            final clientFee = double.tryParse(match.group(3)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0.0;
            final networkFee = double.tryParse(match.group(4)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0.0;
            var party = match.group(5)?.trim();
            if (party == 'null' || party == '') party = null;
            final note = match.group(6)?.trim();
            
            if (amount > 0) {
              await CleanWriteGateway.appDbBridge().execute(
                CreateTransferIntent(
                  transactionId: const Uuid().v4(),
                  settlementId: const Uuid().v4(),
                  claimId: const Uuid().v4(),
                  walletId: walletId,
                  amount: amount,
                  clientFee: clientFee,
                  networkFee: networkFee,
                  transferType: 'type1',
                  party: party,
                  note: note,
                ),
              );
              responseText = responseText.replaceAll(match.group(0)!, '').trim();
            }
          }
        }

        if (responseText.contains('[ACTION:ADD_RECEIVE:')) {
          final regex = RegExp(r'\[ACTION:ADD_RECEIVE:(.+?):(.+?):(.+?):(.+?):(.+?)\]');
          final match = regex.firstMatch(responseText);
          if (match != null) {
            final amount = double.tryParse(match.group(1)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0.0;
            final walletId = int.tryParse(match.group(2)?.replaceAll(RegExp(r'[^0-9]'), '') ?? '1') ?? 1;
            final commission = double.tryParse(match.group(3)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0.0;
            var party = match.group(4)?.trim();
            if (party == 'null' || party == '') party = null;
            final note = match.group(5)?.trim();
            
            if (amount > 0) {
              await CleanWriteGateway.appDbBridge().execute(
                CreateReceiveIntent(
                  transactionId: const Uuid().v4(),
                  settlementId: const Uuid().v4(),
                  claimId: const Uuid().v4(),
                  walletId: walletId,
                  amount: amount,
                  commission: commission,
                  receiveType: 'receive',
                  party: party,
                  note: note,
                ),
              );
              responseText = responseText.replaceAll(match.group(0)!, '').trim();
            }
          }
        }
      }
      return responseText;
    } catch (e) {
      return 'حدث خطأ غير متوقع: $e';
    }
  }

  List<Content> get chatHistory => _chatSession?.history.toList() ?? [];
}
