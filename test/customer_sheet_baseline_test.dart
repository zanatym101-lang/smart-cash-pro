import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/customers_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_customer_sheet_baseline_',
  );

  const customerName = 'Baseline Customer';
  const customerPhone = '01011112222';

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  }

  Future<void> seedCustomerLines() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Baseline Wallet',
      phone: '01010000009',
      openingBalance: 5000,
    );

    await db.addTransfer(
      walletId: walletId,
      amount: 120,
      clientFee: 4,
      networkFee: 1,
      transferType: 'type1',
      isPending: true,
      party: customerName,
      note: customerPhone,
    );

    await db.addReceive(
      walletId: walletId,
      amount: 80,
      commission: 3,
      receiveType: 'cash',
      isPending: false,
      party: customerName,
      note: customerPhone,
    );

    await db.addClaim(
      type: 'receivable',
      party: customerName,
      amount: 55,
      note: 'baseline claim',
      phone: customerPhone,
    );
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 120,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Widget not found in time: $finder');
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder sheetScope(Finder child) {
    return find.descendant(of: find.byType(BottomSheet), matching: child);
  }

  Future<void> openCustomerSheet(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
    await pumpUntilFound(tester, find.text(customerName));
    await tester.tap(find.text(customerName).first);
    await pumpFrames(tester);
    await pumpUntilFound(tester, find.byType(BottomSheet));
    await pumpUntilFound(tester, sheetScope(find.byType(ChoiceChip)));
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
  });

  setUp(() async {
    await resetAndActivate();
    await seedCustomerLines();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
    'customer sheet baseline shows name, summary, filters, and quick actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openCustomerSheet(tester);

      expect(sheetScope(find.text(customerName)), findsOneWidget);
      expect(sheetScope(find.text('الهاتف: $customerPhone')), findsOneWidget);

      expect(sheetScope(find.text('له')), findsOneWidget);
      expect(sheetScope(find.text('عليه')), findsOneWidget);
      expect(
        sheetScope(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data?.contains('الصافي') ?? false),
          ),
        ),
        findsOneWidget,
      );

      expect(sheetScope(find.byType(ChoiceChip)), findsNWidgets(5));
      expect(sheetScope(find.text('الكل')), findsOneWidget);
      expect(sheetScope(find.text('المستحقات')), findsOneWidget);
      expect(sheetScope(find.text('التحصيل/السداد')), findsOneWidget);
      expect(sheetScope(find.text('المعلّق')), findsOneWidget);
      expect(sheetScope(find.text('المعتمد')), findsOneWidget);

      await tester.tap(sheetScope(find.byIcon(Icons.expand_more)).first);
      await pumpFrames(tester);

      expect(sheetScope(find.byIcon(Icons.add_circle_outline)), findsOneWidget);
      expect(sheetScope(find.byIcon(Icons.done_all)), findsOneWidget);
      expect(sheetScope(find.byIcon(Icons.tune)), findsOneWidget);
      expect(sheetScope(find.byIcon(Icons.assessment_outlined)), findsOneWidget);
      expect(sheetScope(find.byIcon(Icons.attach_file)), findsOneWidget);
    },
  );

  testWidgets('pending transaction menu shows confirm action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await openCustomerSheet(tester);

    await tester.tap(sheetScope(find.text('المعلّق')).first);
    await pumpFrames(tester, count: 8);

    final pendingMenuButton = sheetScope(
      find.byWidgetPredicate((w) => w is PopupMenuButton),
    );
    expect(pendingMenuButton, findsWidgets);
    await tester.ensureVisible(pendingMenuButton.first);
    await tester.tap(pendingMenuButton.first, warnIfMissed: false);
    await pumpFrames(tester, count: 8);

    final confirmPendingFinder = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data?.contains('تنفيذ') ?? false) &&
          (w.data?.contains('معل') ?? false),
    );
    expect(confirmPendingFinder, findsOneWidget);
  });

  testWidgets('posted transaction menu does not show confirm action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await openCustomerSheet(tester);

    await tester.tap(sheetScope(find.text('المعتمد')).first);
    await pumpFrames(tester, count: 8);

    final postedMenuButton = sheetScope(
      find.byWidgetPredicate((w) => w is PopupMenuButton),
    );
    expect(postedMenuButton, findsWidgets);
    await tester.ensureVisible(postedMenuButton.first);
    await tester.tap(postedMenuButton.first, warnIfMissed: false);
    await pumpFrames(tester, count: 8);

    expect(find.text('إلغاء العملية'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data?.contains('تنفيذ') ?? false) &&
            (w.data?.contains('معل') ?? false),
      ),
      findsNothing,
    );
  });

  testWidgets('customer add-operation menu hides fawry creation options', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await openCustomerSheet(tester);

    await tester.tap(
      sheetScope(find.byIcon(Icons.add_circle_outline)).first,
      warnIfMissed: false,
    );
    await pumpFrames(tester, count: 8);

    expect(find.text('فوري نقدي'), findsNothing);
    expect(find.text('فوري آجل'), findsNothing);
  });
}
