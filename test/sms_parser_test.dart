import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';
import 'package:king_wallet_accounting/ai_sms/sms_review_screen.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/services/sms_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_sms_parser_test_');

  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  const packageInfoChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
  const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');
  const googleSignInChannel = MethodChannel('plugins.flutter.io/google_sign_in');
  const openFileChannel = MethodChannel('open_file');
  const printingChannel = MethodChannel('net.nfet.printing');
  const filePickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

  String? mockClipboardText;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall methodCall) async {
      return supportDir.path;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (MethodCall methodCall) async {
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(googleSignInChannel, (MethodCall call) async {
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(openFileChannel, (MethodCall call) async {
      return {'type': 0, 'message': 'done'};
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printingChannel, (MethodCall call) async {
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (MethodCall call) async {
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (MethodCall methodCall) async {
      return {
        'appName': 'King Wallet Accounting',
        'packageName': 'com.kingwallet.accounting',
        'version': '1.0.0',
        'buildNumber': '1',
      };
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (MethodCall methodCall) async {
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.getData') {
        return mockClipboardText != null ? {'text': mockClipboardText} : null;
      }
      if (call.method == 'Clipboard.setData') {
        mockClipboardText = (call.arguments as Map?)?['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.hasStrings') {
        return {'value': mockClipboardText != null && mockClipboardText!.isNotEmpty};
      }
      return null;
    });
  });

  tearDownAll(() {
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
    await db.drawerDeposit(amount: 10000);
  }

  group('SmsParser Phone Extraction & Normalization', () {
    setUp(() async {
      await resetAndActivate();
    });
    test('extracts phone with English digits', () {
      const text = 'تم استلام مبلغ 500 جنيه من 01012345678 بنجاح';
      final phone = SmsParser.extractPhone(text);
      expect(phone, '01012345678');
    });

    test('extracts phone with Arabic digits', () {
      const text = 'تم تحويل مبلغ 1000 جنيه لرقم ٠١١٢٣٤٥٦٧٨٩ كود العملية 9876';
      final phone = SmsParser.extractPhone(text);
      expect(phone, '01123456789');
    });

    test('extracts phone with +20 prefix', () {
      const text = 'وصلك 250 ج من +201234567890';
      final phone = SmsParser.extractPhone(text);
      expect(phone, '01234567890');
    });

    test('normalizes Arabic and Persian digits to Latin', () {
      expect(SmsParser.normalizeArabicDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(SmsParser.normalizeArabicDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(SmsParser.normalizePhone('+20 (010) 123-45678'), '2001012345678');
    });

    test('returns null when no valid Egyptian phone number exists', () {
      expect(SmsParser.extractPhone('كود التحقق الخاص بك هو 1234'), isNull);
    });
  });

  group('SmsParser Customer Auto-Matching & One-Tap Save', () {
    setUp(() async {
      await resetAndActivate();
    });

    test('autoMatchCustomer finds existing customer from recent numbers', () async {
      final db = AppDb.instance;
      await db.addRecentNumber(phone: '01099887766', name: 'محمد سمير');

      final parsed = SmsParser.parseText(
        'تم استلام 700 جنيه من 01099887766 رقم العملية 554433',
      );

      final matched = await SmsParser.autoMatchCustomer(parsed.draft, db: db);
      expect(matched.customerName, 'محمد سمير');
      expect(matched.amount, 700.0);
      expect(matched.operationType, ParsedOperationType.receive);
    });

    test('autoMatchCustomer finds existing customer from previous transactions', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'كاش 1',
        phone: '01000000001',
        openingBalance: 5000,
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 200,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        party: 'محمود عبد الفتاح',
        note: 'رقم: 01555443322',
      );

      final parsed = SmsParser.parseText(
        'تم تحويل 200 ج لرقم 01555443322',
      );

      final matched = await SmsParser.autoMatchCustomer(parsed.draft, db: db);
      expect(matched.customerName, 'محمود عبد الفتاح');
    });

    test('autoMatchCustomer leaves phone if customer not found', () async {
      final db = AppDb.instance;
      final parsed = SmsParser.parseText(
        'تم استلام 300 جنيه من 01200112233 رقم المرجع: 778899',
      );

      final matched = await SmsParser.autoMatchCustomer(parsed.draft, db: db);
      expect(matched.customerName, '01200112233');
    });

    test('saveCustomer saves customer and enables subsequent auto-matching', () async {
      final db = AppDb.instance;
      expect(await SmsParser.lookupCustomerByPhone('01055556666', db: db), isNull);

      await SmsParser.saveCustomer(
        phone: '01055556666',
        name: 'كريم نبيل',
        db: db,
      );

      final customerName = await SmsParser.lookupCustomerByPhone('01055556666', db: db);
      expect(customerName, 'كريم نبيل');

      final parsed = SmsParser.parseText('تم تحويل 450 جنيه لرقم 01055556666');
      final matched = await SmsParser.autoMatchCustomer(parsed.draft, db: db);
      expect(matched.customerName, 'كريم نبيل');
    });
  });

  group('SmsParser WhatsApp Receipt Button & URI Building', () {
    test('formatWhatsAppReceipt produces formatted receipt with all fields', () {
      final draft = ParsedTransactionDraft(
        operationType: ParsedOperationType.transfer,
        amount: 850.5,
        sender: 'Vodafone Cash',
        effectiveDate: DateTime(2026, 8, 29, 14, 30),
        reference: 'TXN-998811',
        provider: 'فودافون كاش',
        customerName: 'طارق علي',
        confidence: ParseConfidence.high,
        warnings: const [],
        rawMessage: 'تم تحويل 850.5 جنيه لطارق علي',
      );

      final receipt = SmsParser.formatWhatsAppReceipt(draft, storeName: 'سوبر ماركت الهدى');
      expect(receipt, contains('🧾 *إيصال معاملة مالية - سوبر ماركت الهدى*'));
      expect(receipt, contains('📌 *العملية:* تحويل رصيد / كاش'));
      expect(receipt, contains('💰 *المبلغ:* 850.50 ج.م'));
      expect(receipt, contains('🏦 *الجهة / المحفظة:* فودافون كاش'));
      expect(receipt, contains('👤 *الطرف الآخر / العميل:* طارق علي'));
      expect(receipt, contains('🔢 *رقم المرجع:* #TXN-998811'));
      expect(receipt, contains('📅 *التاريخ:* 2026-08-29 14:30'));
      expect(receipt, contains('✨ *شكراً لتعاملكم معنا.*'));
    });

    test('buildWhatsAppUri builds valid WhatsApp link with 20 prefix and encoded text', () {
      final uri = SmsParser.buildWhatsAppUri(
        phone: '01012345678',
        message: 'إيصال استلام 500 جنيه',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/201012345678');
      expect(uri.queryParameters['text'], 'إيصال استلام 500 جنيه');
    });

    test('buildWhatsAppUri handles empty phone gracefully', () {
      final uri = SmsParser.buildWhatsAppUri(
        phone: null,
        message: 'إيصال عام',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/');
      expect(uri.queryParameters['text'], 'إيصال عام');
    });
  });

  group('Dashboard SMS Flow Integration', () {
    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      int maxPumps = 80,
    }) async {
      for (var i = 0; i < maxPumps; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) {
          return;
        }
      }
      fail('Widget not found in time: $finder');
    }

    testWidgets('SmsReviewScreen displays auto-matched customer name and produces confirmed draft', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = AppDb.instance;
      await tester.runAsync(() async {
        await resetAndActivate();
        await db.addWallet(name: 'فودافون كاش', phone: '01000000001', openingBalance: 5000);
        await db.addRecentNumber(phone: '01011112222', name: 'أحمد سعيد');
      });

      final parsed = SmsParser.parseText('تم استلام 500 جنيه من 01011112222 كود 123456');
      final matched = (await tester.runAsync(() => SmsParser.autoMatchCustomer(parsed.draft, db: db)))!;

      final wallets = (await tester.runAsync(() => db.listWallets()))!;
      final walletOptions = wallets
          .map((w) => SmsReviewWalletOption(id: w.id, name: w.name, phone: w.phone))
          .toList();

      ParsedTransactionDraft? confirmedDraft;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final res = await Navigator.of(context).push<ParsedTransactionDraft>(
                      MaterialPageRoute(
                        builder: (_) => SmsReviewScreen(
                          draft: matched,
                          walletOptions: walletOptions,
                        ),
                      ),
                    );
                    confirmedDraft = res;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await pumpUntilFound(tester, find.byType(SmsReviewScreen));
      expect(find.text('أحمد سعيد'), findsWidgets);

      await tester.tap(find.text('تأكيد'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(confirmedDraft, isNotNull);
      expect(confirmedDraft!.customerName, 'أحمد سعيد');
      expect(confirmedDraft!.amount, 500.0);

      // Verify WhatsApp Receipt formatting and launching
      final receiptText = SmsParser.formatWhatsAppReceipt(confirmedDraft!);
      expect(receiptText.contains('أحمد سعيد'), isTrue);
      expect(receiptText.contains('500'), isTrue);

      final launched = (await tester.runAsync(
        () => SmsParser.launchWhatsAppReceipt(confirmedDraft!, phone: '01011112222'),
      ))!;
      expect(launched, isTrue);
    });

    testWidgets('One-tap save customer persists unknown number to AppDb and auto-matches thereafter', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = AppDb.instance;
      await tester.runAsync(() async {
        await resetAndActivate();
        await db.addWallet(name: 'فودافون كاش', phone: '01000000001', openingBalance: 5000);
      });

      final parsed = SmsParser.parseText('تم تحويل 300 جنيه لرقم 01277778888 كود 654321');
      final matchedBefore = (await tester.runAsync(() => SmsParser.autoMatchCustomer(parsed.draft, db: db)))!;
      expect(matchedBefore.customerName, '01277778888');

      // Save customer via one-tap save
      await tester.runAsync(() async {
        await SmsParser.saveCustomer(phone: '01277778888', name: 'منى خالد', db: db);
      });
      final savedName = (await tester.runAsync(() => SmsParser.lookupCustomerByPhone('01277778888', db: db)))!;
      expect(savedName, 'منى خالد');

      final matchedAfter = (await tester.runAsync(() => SmsParser.autoMatchCustomer(parsed.draft, db: db)))!;
      expect(matchedAfter.customerName, 'منى خالد');

      final receiptText = SmsParser.formatWhatsAppReceipt(matchedAfter);
      expect(receiptText.contains('منى خالد'), isTrue);
      expect(receiptText.contains('300'), isTrue);

      final launched = (await tester.runAsync(
        () => SmsParser.launchWhatsAppReceipt(matchedAfter, phone: '01277778888'),
      ))!;
      expect(launched, isTrue);
    });
  });
}
