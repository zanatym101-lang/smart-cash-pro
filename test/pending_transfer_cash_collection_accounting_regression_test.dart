import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_pending_transfer_cash_collection_regression_',
  );

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
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
    'pending transfer cash collection credits drawer only when cash is collected',
    (tester) async {
      final db = AppDb.instance;

      await tester.runAsync(() async {
        await db.drawerDeposit(amount: 500, note: 'initial drawer');
        await db.addWallet(
          name: 'Regression Wallet',
          phone: '01010000061',
          openingBalance: 500,
        );
      });

      final walletId = (await tester.runAsync(
        () async => (await db.listWallets()).single.id,
      ))!;

      final pendingTxnId = (await tester.runAsync(
        () => db.addTransfer(
          walletId: walletId,
          amount: 500,
          clientFee: 5,
          networkFee: 0,
          transferType: 'type1',
          isPending: true,
          party: 'Pending Cash Collection Customer',
        ),
      ))!;

      final afterPending = (await tester.runAsync(
        () => db.getTreasurySnapshot(),
      ))!;
      final walletAfterPending = (await tester.runAsync(
        () => db.getWalletBalance(walletId),
      ))!;

      await tester.runAsync(
        () => db.addPendingSettlementForTxn(
          pendingTxnId: pendingTxnId,
          amount: 400,
        ),
      );
      final afterPartial = (await tester.runAsync(
        () => db.getTreasurySnapshot(),
      ))!;

      await tester.runAsync(
        () => db.addPendingSettlementForTxn(
          pendingTxnId: pendingTxnId,
          amount: 105,
        ),
      );
      final afterFull = (await tester.runAsync(
        () => db.getTreasurySnapshot(),
      ))!;

      expect(afterPending.drawerActualBalance, closeTo(500, 0.0001));
      expect(walletAfterPending, closeTo(0, 0.0001));
      expect(afterPending.availableLiquidityNow, closeTo(500, 0.0001));
      expect(afterPending.realCapitalApproved, closeTo(1005, 0.0001));

      expect(afterPartial.drawerActualBalance, closeTo(900, 0.0001));
      expect(afterPartial.availableLiquidityNow, closeTo(900, 0.0001));
      expect(afterPartial.realCapitalApproved, closeTo(1005, 0.0001));

      expect(afterFull.drawerActualBalance, closeTo(1005, 0.0001));
      expect(afterFull.availableLiquidityNow, closeTo(1005, 0.0001));
      expect(afterFull.realCapitalApproved, closeTo(1005, 0.0001));
    },
  );
}
