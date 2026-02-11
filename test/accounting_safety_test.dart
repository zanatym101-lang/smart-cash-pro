import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_accounting_test_');
  String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> seedCleanDb() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final activationCode = db.generateActivationCodeForDeviceCode(
      info.deviceCode,
    );
    await db.activateWithCode(activationCode);
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
    await seedCleanDb();
  });

  setUp(() async {
    await seedCleanDb();
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

  test(
    'pending transfer approval applies once and does not double-impact balances',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Main Wallet',
        phone: '01012345678',
        openingBalance: 1000,
      );

      expect(await db.getWalletBalance(walletId), closeTo(1000, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(1000, 0.0001),
      );

      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 2,
        transferType: 'type1',
        isPending: true,
        note: 'pending transfer',
      );

      expect(await db.getWalletBalance(walletId), closeTo(1000, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(898, 0.0001),
      );

      final beforeConfirm = await db.getTreasurySnapshot();
      expect(beforeConfirm.drawerActualBalance, closeTo(0, 0.0001));
      expect(beforeConfirm.drawerBalance, closeTo(110, 0.0001));

      await db.confirmPending(txnId);

      expect(await db.getWalletBalance(walletId), closeTo(898, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(898, 0.0001),
      );

      final afterConfirm = await db.getTreasurySnapshot();
      expect(afterConfirm.drawerActualBalance, closeTo(110, 0.0001));
      expect(afterConfirm.drawerBalance, closeTo(110, 0.0001));

      expect(() => db.confirmPending(txnId), throwsException);
    },
  );

  test(
    'fawry credit creates claim, settlement closes claim, and profit is not duplicated',
    () async {
      final db = AppDb.instance;

      await db.addFawry(
        serviceName: 'Electricity',
        reference: '555999',
        amount: 1000,
        fee: 10,
        collectionMethod: 'credit',
        party: 'Client A',
        isPending: false,
        note: 'test fawry credit',
      );

      final openClaims = await db.listClaims(
        type: 'receivable',
        status: 'open',
      );
      expect(openClaims.length, 1);
      expect(openClaims.first.amount, closeTo(1010, 0.0001));

      final beforeSettlement = await db.getTreasurySnapshot();
      expect(beforeSettlement.drawerActualBalance, closeTo(-1000, 0.0001));
      expect(beforeSettlement.dailyProfit, closeTo(10, 0.0001));

      await db.settleClaim(claimId: openClaims.first.id);

      final openAfterSettlement = await db.listClaims(
        type: 'receivable',
        status: 'open',
      );
      final closedAfterSettlement = await db.listClaims(
        type: 'receivable',
        status: 'closed',
      );
      expect(openAfterSettlement, isEmpty);
      expect(closedAfterSettlement.length, 1);
      expect(closedAfterSettlement.first.settledTxnId, isNotNull);

      final afterSettlement = await db.getTreasurySnapshot();
      expect(afterSettlement.drawerActualBalance, closeTo(10, 0.0001));
      expect(afterSettlement.dailyProfit, closeTo(10, 0.0001));
    },
  );

  test(
    'wallet balance never goes negative for pending or posted transfers',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Protected Wallet',
        phone: '01112345678',
        openingBalance: 50,
      );

      expect(
        () => db.addTransfer(
          walletId: walletId,
          amount: 50,
          clientFee: 0,
          networkFee: 1,
          transferType: 'type1',
          isPending: true,
          note: 'should fail pending',
        ),
        throwsException,
      );

      expect(
        () => db.addTransfer(
          walletId: walletId,
          amount: 50,
          clientFee: 0,
          networkFee: 1,
          transferType: 'type1',
          isPending: false,
          note: 'should fail posted',
        ),
        throwsException,
      );

      expect(await db.getWalletBalance(walletId), closeTo(50, 0.0001));
      expect(await db.getWalletAvailableBalance(walletId), closeTo(50, 0.0001));
    },
  );

  test(
    'pending receive impacts available balances and posts once after confirm',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Receive Wallet',
        phone: '01212345678',
        openingBalance: 500,
      );

      final txnId = await db.addReceive(
        walletId: walletId,
        amount: 100,
        commission: 10,
        receiveType: 'cash',
        isPending: true,
        note: 'pending receive',
      );

      expect(await db.getWalletBalance(walletId), closeTo(500, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(600, 0.0001),
      );

      final beforeConfirm = await db.getTreasurySnapshot();
      expect(beforeConfirm.drawerActualBalance, closeTo(0, 0.0001));
      expect(beforeConfirm.drawerBalance, closeTo(-100, 0.0001));

      await db.confirmPending(txnId);

      expect(await db.getWalletBalance(walletId), closeTo(600, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(600, 0.0001),
      );

      final afterConfirm = await db.getTreasurySnapshot();
      expect(afterConfirm.drawerActualBalance, closeTo(-100, 0.0001));
      expect(afterConfirm.drawerBalance, closeTo(-100, 0.0001));
      expect(afterConfirm.dailyProfit, closeTo(10, 0.0001));
    },
  );

  test(
    'daily close is single-use per date and new transactions move to next day',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Close Wallet',
        phone: '01512345678',
        openingBalance: 0,
      );

      final close = await db.closeDaily(DateTime.now());
      final closes = await db.listDailyCloses();
      expect(closes.length, 1);
      expect(closes.first.dateKey, close.dateKey);

      expect(() => db.closeDaily(DateTime.now()), throwsException);

      await db.addExternalFunding(
        walletId: walletId,
        amount: 100,
        note: 'after close',
      );

      final fundingTxns = await db.listTxns(
        kind: 'external_funding',
        status: 'posted',
      );
      expect(fundingTxns.length, 1);
      final fundingKey = dateKey(fundingTxns.first.entryDate);
      expect(fundingKey, isNot(close.dateKey));
    },
  );

  test(
    'confirming pending created before daily close posts on next open day',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Pending Before Close',
        phone: '01077777777',
        openingBalance: 500,
      );

      final pendingTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        note: 'before close pending',
      );

      final close = await db.closeDaily(DateTime.now());
      await db.confirmPending(pendingTxnId);

      final postedTransfers = await db.listTxns(
        kind: 'transfer',
        status: 'posted',
      );
      expect(postedTransfers.length, 1);
      expect(postedTransfers.first.id, pendingTxnId);

      final postedKey = dateKey(postedTransfers.first.entryDate);
      expect(postedKey, isNot(close.dateKey));

      expect(await db.getWalletBalance(walletId), closeTo(400, 0.0001));
      final snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(110, 0.0001));
    },
  );

  test('rollback of fawry credit is blocked after claim settlement', () async {
    final db = AppDb.instance;

    final fawryTxnId = await db.addFawry(
      serviceName: 'Internet',
      reference: 'A-100',
      amount: 300,
      fee: 15,
      collectionMethod: 'credit',
      party: 'Client Rollback Guard',
      isPending: false,
      note: 'rollback guard',
    );

    final openClaims = await db.listClaims(type: 'receivable', status: 'open');
    expect(openClaims.length, 1);

    await db.settleClaim(claimId: openClaims.first.id);

    expect(() => db.rollbackPosted(fawryTxnId), throwsException);
  });
}
