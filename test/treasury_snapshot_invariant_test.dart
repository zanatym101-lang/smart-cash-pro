import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_treasury_invariant_test_',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
  });

  setUp(() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final activationCode = db.generateActivationCodeForDeviceCode(
      info.deviceCode,
    );
    await db.activateWithCode(activationCode);
    await db.resetDatabaseEmpty();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'treasury snapshot invariants keep liquidity and real capital formulas aligned',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Invariant Wallet',
        phone: '01000000123',
        openingBalance: 1000,
      );

      await db.addClaim(
        type: 'receivable',
        party: 'Receivable Party',
        amount: 300,
      );
      await db.addClaim(
        type: 'payable',
        party: 'Payable Party',
        amount: 80,
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 2,
        transferType: 'type1',
        isPending: true,
        party: 'Invariant Pending Receivable',
      );
      await db.addReceive(
        walletId: walletId,
        amount: 40,
        commission: 4,
        receiveType: 'cash',
        isPending: true,
        party: 'Invariant Pending Payable',
      );

      final snap = await db.getTreasurySnapshot();

      expect(
        snap.availableLiquidityNow,
        closeTo(snap.actualTreasuryApproved, 0.0001),
      );
      expect(
        snap.realCapitalApproved,
        closeTo(snap.actualTreasuryApproved + snap.claimsNet, 0.0001),
      );
    },
  );

  test(
    'treasury snapshot treats pending KPIs as informational and keeps liquidity cash-only',
    () async {
      final db = AppDb.instance;

      await db.drawerDeposit(amount: 500, note: 'seed drawer');
      final walletId = await db.addWallet(
        name: 'Cash Only Wallet',
        phone: '01000000456',
        openingBalance: 500,
      );

      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Pending Receivable',
      );
      await db.addReceive(
        walletId: walletId,
        amount: 40,
        commission: 4,
        receiveType: 'cash',
        isPending: true,
        party: 'Pending Payable',
      );

      final snap = await db.getTreasurySnapshot();

      expect(snap.actualTreasuryApproved, closeTo(940, 0.0001));
      expect(snap.availableLiquidityNow, closeTo(940, 0.0001));
      expect(
        snap.availableLiquidityNow,
        isNot(closeTo(snap.actualTreasuryApproved + snap.pendingNet, 0.0001)),
      );
      expect(snap.pendingInflow, closeTo(40, 0.0001));
      expect(snap.pendingOutflow, closeTo(100, 0.0001));
      expect(snap.pendingReceivableOpen, closeTo(110, 0.0001));
      expect(snap.pendingPayableOpen, closeTo(40, 0.0001));
      expect(
        snap.realCapitalApproved,
        closeTo(
          snap.actualTreasuryApproved +
              snap.claimsReceivableOpen +
              snap.pendingReceivableOpen -
              snap.claimsPayableOpen -
              snap.pendingPayableOpen,
          0.0001,
        ),
      );
    },
  );
}
