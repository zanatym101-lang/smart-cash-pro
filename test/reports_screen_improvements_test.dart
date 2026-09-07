import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/reports_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  const googleSignInChannel = MethodChannel('plugins.flutter.io/google_sign_in');
  const openFileChannel = MethodChannel('open_file');
  const printingChannel = MethodChannel('net.nfet.printing');
  const filePickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');
  const packageInfoChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
  final supportDir = Directory.systemTemp.createTempSync('kw_reports_screen_test_');

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

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

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return supportDir.path;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async => true);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(googleSignInChannel, (call) async {
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(openFileChannel, (call) async => {'type': 0, 'message': 'done'});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printingChannel, (call) async => 1);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async => null);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (call) async {
          if (call.method == 'isDeviceSupported' || call.method == 'canCheckBiometrics') {
            return true;
          }
          if (call.method == 'getAvailableBiometrics') {
            return <String>['fingerprint'];
          }
          if (call.method == 'authenticate') {
            return true;
          }
          return false;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (call) async {
          if (call.method == 'getAll') {
            return <String, dynamic>{
              'appName': 'Smart Cash Pro',
              'packageName': 'com.smartcash.pro',
              'version': '1.0.0',
              'buildNumber': '1',
            };
          }
          return null;
        });
  });

  tearDownAll(() async {
    if (supportDir.existsSync()) {
      try {
        supportDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  setUp(() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  });

  testWidgets('reports screen renders 8 tabs without standalone treasury tab and shows humanized date for today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'فودافون كاش الرئيسية',
        phone: '01011111111',
        openingBalance: 2000,
      );

      await db.addTransfer(
        walletId: walletId,
        amount: 500,
        clientFee: 15,
        networkFee: 2,
        transferType: 'type1',
        isPending: false,
        party: 'عميل تجريبي',
        note: 'تحويل',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await pumpUntilFound(tester, find.byType(TabBarView));

    // Verify 8 tabs
    final tabFinder = find.byType(Tab);
    expect(tabFinder, findsNWidgets(8));

    final tabTexts = tester.widgetList<Tab>(tabFinder).map((t) => t.text).toList();
    expect(tabTexts, equals([
      'الأرباح',
      'تحليل ذكي',
      'حركة الدرج',
      'ملخص العمليات',
      'المستحقات',
      'مطابقة الأرصدة',
      'إغلاق اليوم',
      'الملخص التنفيذي',
    ]));
    expect(tabTexts.contains('الخزنة'), isFalse);

    // Verify humanized date label for today
    expect(find.textContaining('اليوم:'), findsOneWidget);
  });

  testWidgets('smart analytics tab computes top active wallet, liquidity ratio, and avg ticket size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'محفظة الأورنج',
        phone: '01211111111',
        openingBalance: 3000,
      );

      await db.addTransfer(
        walletId: walletId,
        amount: 400,
        clientFee: 10,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        party: 'عميل 1',
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 600,
        clientFee: 20,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        party: 'عميل 2',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await pumpUntilFound(tester, find.byType(TabBarView));

    // Tap on 'تحليل ذكي' tab (index 1)
    await tester.tap(find.text('تحليل ذكي'));
    await pumpFrames(tester, count: 6);

    // Verify computed metric cards
    expect(find.text('مؤشرات الأداء الذكية'), findsOneWidget);
    expect(find.text('المحفظة الأكثر نشاطاً'), findsOneWidget);
    expect(find.textContaining('محفظة الأورنج'), findsOneWidget);
    expect(find.text('نسبة السيولة (كاش / محافظ)'), findsOneWidget);
    expect(find.text('متوسط حجم العملية'), findsOneWidget);
    expect(find.textContaining('ج.م'), findsWidgets);
  });

  testWidgets('operations summary tab focuses strictly on counts without financial amounts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'محفظة كاش',
        phone: '01111111111',
        openingBalance: 1000,
      );

      await db.addTransfer(
        walletId: walletId,
        amount: 200,
        clientFee: 5,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        party: 'عميل عمليات',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await pumpUntilFound(tester, find.byType(TabBarView));

    // Tap on 'ملخص العمليات' tab (index 3)
    await tester.tap(find.text('ملخص العمليات'));
    await pumpFrames(tester, count: 6);

    // Verify operation counts are present
    expect(find.text('عدد التحويلات'), findsOneWidget);
    expect(find.text('عدد الاستلامات'), findsOneWidget);
    expect(find.text('عدد فوري نقدي'), findsOneWidget);
    expect(find.text('عدد فوري آجل'), findsOneWidget);
    expect(find.text('عدد المصروفات'), findsOneWidget);
    expect(find.text('عدد تحصيل المستحقات'), findsOneWidget);
    expect(find.text('عدد سداد المستحقات'), findsOneWidget);
    expect(find.text('عدد الآجل'), findsOneWidget);

    // Verify financial amount cards are removed
    expect(find.text('إجمالي المصروفات (الفترة)'), findsNothing);
    expect(find.text('أرشيف المصروفات (قبل الفترة)'), findsNothing);
  });

  testWidgets('executive summary tab contains merged treasury breakdown cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDb.instance;
    await tester.runAsync(() async {
      await db.addWallet(
        name: 'محفظة التنفيذي',
        phone: '01511111111',
        openingBalance: 5000,
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await pumpUntilFound(tester, find.byType(TabBarView));

    // Tap on 'الملخص التنفيذي' tab (index 7)
    await tester.tap(find.text('الملخص التنفيذي'));
    await pumpFrames(tester, count: 6);

    // Verify executive KPIs and merged treasury cards
    expect(find.text('السيولة المتاحة'), findsOneWidget);
    expect(find.text('رأس المال الحقيقي (معتمد)'), findsOneWidget);
    expect(find.text('الخزنة الفعلية (معتمد)'), findsOneWidget);
    expect(find.text('صافي الربح بعد المصروفات'), findsOneWidget);
    expect(find.text('أرصدة الخزنة والدرج'), findsOneWidget);
    expect(find.text('رصيد الدرج الحالي'), findsOneWidget);
    expect(find.text('إجمالي المحافظ الحالي'), findsOneWidget);
    expect(find.text('إجمالي الخزنة (درج + محافظ)'), findsOneWidget);
  });
}
