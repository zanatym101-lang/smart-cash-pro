import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_pending_partial_collection_test_',
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
    'pending transfer partial collection changes treasury by exactly 500 and confirm does not double credit',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Pending Partial Wallet',
        phone: '01000000055',
        openingBalance: 1000,
      );

      final pendingTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 1000,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Pending Partial Customer',
      );

      final beforeSettlement = await db.getTreasurySnapshot();

      final settlementTxnId = await db.addPendingSettlementForTxn(
        pendingTxnId: pendingTxnId,
        amount: 500,
      );

      final afterSettlement = await db.getTreasurySnapshot();
      final txnsAfterSettlement = await db.listTxns();
      final pendingAfterSettlement = txnsAfterSettlement.firstWhere(
        (t) => t.id == pendingTxnId,
      );
      final settlement = txnsAfterSettlement.firstWhere(
        (t) => t.id == settlementTxnId,
      );

      expect(
        afterSettlement.drawerActualBalance -
            beforeSettlement.drawerActualBalance,
        closeTo(500, 0.0001),
      );
      expect(pendingAfterSettlement.amount, equals(1000));
      expect(pendingAfterSettlement.status, equals('pending'));
      expect(settlement.kind, equals('claim_collect'));
      expect(settlement.amount, equals(500));
      expect(settlement.status, equals('posted'));
      expect(settlement.note, contains('pending_txn:$pendingTxnId'));
      expect(settlement.note, contains('500.00'));

      await db.confirmPending(pendingTxnId);

      final afterConfirm = await db.getTreasurySnapshot();
      final txnsAfterConfirm = await db.listTxns();
      final confirmedPending = txnsAfterConfirm.firstWhere(
        (t) => t.id == pendingTxnId,
      );

      expect(
        afterConfirm.drawerActualBalance,
        closeTo(afterSettlement.drawerActualBalance, 0.0001),
      );
      expect(confirmedPending.amount, equals(1000));
      expect(confirmedPending.status, equals('posted'));
    },
  );
}
