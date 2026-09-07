import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_pending_full_settlement_',
  );

  const transferCustomer = 'Pending Full Collect Customer';
  const receiveCustomer = 'Pending Full Pay Customer';

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

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    await resetAndActivate();
  });

  test(
    'scenario A: pending transfer partial then full collect settles remaining directly with no open claim',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Full Collect Wallet',
        phone: '01090000111',
        openingBalance: 100,
      );
      final pendingTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: transferCustomer,
      );
      await db.addPendingSettlementForTxn(pendingTxnId: pendingTxnId, amount: 50);
      await db.settlePendingTxnFully(pendingTxnId: pendingTxnId);

      final snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(100, 0.0001));
      expect(snap.walletsActualTotal, closeTo(0, 0.0001));
      expect(snap.pendingReceivableOpen, closeTo(0, 0.0001));
      expect(snap.claimsReceivableOpen, closeTo(0, 0.0001));

      final openClaims = await db.listClaims(status: 'open');
      expect(
        openClaims.where((c) => c.sourceTxnId == pendingTxnId),
        isEmpty,
      );

      final txns = await db.listTxns();
      final story = txns.where((t) {
        if (t.status != 'posted') return false;
        if (t.kind == 'transfer' && t.id == pendingTxnId) return true;
        if ((t.kind == 'claim_collect' || t.kind == 'claim_pay') &&
            (t.note ?? '').contains('pending_txn:$pendingTxnId')) {
          return true;
        }
        return false;
      }).toList()
        ..sort((a, b) {
          final date = a.entryDate.compareTo(b.entryDate);
          if (date != 0) return date;
          return a.id.compareTo(b.id);
        });

      expect(story.map((t) => t.kind).toList(), [
        'transfer',
        'claim_collect',
        'claim_collect',
      ]);
      expect(story[0].amount, closeTo(100, 0.0001));
      expect(story[1].amount, closeTo(50, 0.0001));
      expect(story[2].amount, closeTo(50, 0.0001));
    },
  );

  test('scenario B: confirmPending only still creates open claim for remaining', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Confirm Only Wallet',
      phone: '01090000112',
      openingBalance: 100,
    );
    final pendingTxnId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 0,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: transferCustomer,
    );
    await db.addPendingSettlementForTxn(pendingTxnId: pendingTxnId, amount: 50);
    await db.confirmPending(pendingTxnId);

    final snap = await db.getTreasurySnapshot();
    expect(snap.pendingReceivableOpen, closeTo(0, 0.0001));
    expect(snap.claimsReceivableOpen, closeTo(50, 0.0001));

    final claim = (await db.listClaims(status: 'open')).singleWhere(
      (c) => c.sourceTxnId == pendingTxnId,
    );
    expect(claim.amount, closeTo(50, 0.0001));
  });

  test('scenario C: pending receive partial then full pay settles remaining directly with no open claim', () async {
    final db = AppDb.instance;
    await db.drawerDeposit(amount: 100, note: 'seed drawer');
    final walletId = await db.addWallet(
      name: 'Full Pay Wallet',
      phone: '01090000113',
      openingBalance: 0,
    );
    final pendingTxnId = await db.addReceive(
      walletId: walletId,
      amount: 100,
      commission: 0,
      receiveType: 'cash',
      isPending: true,
      party: receiveCustomer,
    );
    await db.addPendingSettlementForTxn(pendingTxnId: pendingTxnId, amount: 50);
    await db.settlePendingTxnFully(pendingTxnId: pendingTxnId);

    final snap = await db.getTreasurySnapshot();
    expect(snap.drawerActualBalance, closeTo(0, 0.0001));
    expect(snap.walletsActualTotal, closeTo(100, 0.0001));
    expect(snap.pendingPayableOpen, closeTo(0, 0.0001));
    expect(snap.claimsPayableOpen, closeTo(0, 0.0001));

    final openClaims = await db.listClaims(status: 'open');
    expect(
      openClaims.where((c) => c.sourceTxnId == pendingTxnId),
      isEmpty,
    );
  });
}
