import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/data/reporting.dart';
import 'package:king_wallet_accounting/services/admin_security_service.dart';

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
    'deferred transfer affects actual balance immediately and approval does not double-impact',
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

      expect(await db.getWalletBalance(walletId), closeTo(898, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(898, 0.0001),
      );

      final beforeConfirm = await db.getTreasurySnapshot();
      expect(beforeConfirm.drawerActualBalance, closeTo(110, 0.0001));
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
      expect(beforeSettlement.drawerActualBalance, closeTo(0, 0.0001));
      expect(beforeSettlement.fawryActualBalance, closeTo(-1000, 0.0001));
      expect(beforeSettlement.dailyProfit, closeTo(10, 0.0001));

      await db.settleClaim(
        claimId: openClaims.first.id,
        amount: openClaims.first.amount,
      );

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
      expect(afterSettlement.drawerActualBalance, closeTo(1010, 0.0001));
      expect(afterSettlement.fawryActualBalance, closeTo(-1000, 0.0001));
      expect(afterSettlement.actualTreasuryApproved, closeTo(10, 0.0001));
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
    'deferred receive affects actual balance immediately and posts once after confirm',
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

      expect(await db.getWalletBalance(walletId), closeTo(600, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(600, 0.0001),
      );

      final beforeConfirm = await db.getTreasurySnapshot();
      expect(beforeConfirm.drawerActualBalance, closeTo(-90, 0.0001));
      expect(beforeConfirm.drawerBalance, closeTo(-90, 0.0001));

      await db.confirmPending(txnId);

      expect(await db.getWalletBalance(walletId), closeTo(600, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(600, 0.0001),
      );

      final afterConfirm = await db.getTreasurySnapshot();
      expect(afterConfirm.drawerActualBalance, closeTo(-90, 0.0001));
      expect(afterConfirm.drawerBalance, closeTo(-90, 0.0001));
      expect(afterConfirm.dailyProfit, closeTo(10, 0.0001));
    },
  );

  test(
    'deferred receive balance can be consumed immediately by transfer',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Pending Flow Wallet',
        phone: '01044445555',
        openingBalance: 0,
      );

      await db.addReceive(
        walletId: walletId,
        amount: 100,
        commission: 0,
        receiveType: 'cash',
        isPending: true,
        note: 'pending receive',
      );

      expect(await db.getWalletBalance(walletId), closeTo(100, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(100, 0.0001),
      );

      final postedRequestId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: false,
        note: 'immediate transfer against pending receive',
      );

      final requestedTxn = (await db.listTxns()).firstWhere(
        (t) => t.id == postedRequestId,
      );
      expect(requestedTxn.status, 'posted');
      expect(await db.getWalletBalance(walletId), closeTo(0, 0.0001));
      expect(await db.getWalletAvailableBalance(walletId), closeTo(0, 0.0001));

      await db.addReceive(
        walletId: walletId,
        amount: 100,
        commission: 0,
        receiveType: 'cash',
        isPending: true,
        note: 'pending receive for pending transfer',
      );

      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        note: 'pending transfer against pending receive',
      );

      expect(await db.getWalletBalance(walletId), closeTo(0, 0.0001));
      expect(await db.getWalletAvailableBalance(walletId), closeTo(0, 0.0001));
    },
  );

  test(
    'canceling deferred transfer or receive reverses actual impact',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Cancel Deferred Wallet',
        phone: '01044445556',
        openingBalance: 500,
      );

      final transferId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 2,
        transferType: 'type1',
        isPending: true,
        note: 'cancel deferred transfer',
      );
      expect(await db.getWalletBalance(walletId), closeTo(398, 0.0001));
      var snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(110, 0.0001));

      await db.cancelPending(transferId);
      expect(await db.getWalletBalance(walletId), closeTo(500, 0.0001));
      snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(0, 0.0001));

      final receiveId = await db.addReceive(
        walletId: walletId,
        amount: 80,
        commission: 5,
        receiveType: 'cash',
        isPending: true,
        note: 'cancel deferred receive',
      );
      expect(await db.getWalletBalance(walletId), closeTo(580, 0.0001));
      snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(-75, 0.0001));

      await db.cancelPending(receiveId);
      expect(await db.getWalletBalance(walletId), closeTo(500, 0.0001));
      snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(0, 0.0001));
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
    'daily close uses business date key when day start hour shifts the day',
    () async {
      final db = AppDb.instance;

      final settings = await db.getAppSettings();
      await db.setAppSettings(settings.copyWith(dayStartHour: 6));

      final close = await db.closeDaily(DateTime(2026, 4, 21, 2));

      expect(close.dateKey, '2026-04-20');
    },
  );

  test(
    'daily close stores balances for the closed business day not current balances',
    () async {
      final db = AppDb.instance;

      await db.addWallet(
        name: 'Business Day Snapshot Wallet',
        phone: '01566667777',
        openingBalance: 1000,
      );

      final historicalDate = DateTime.now().subtract(const Duration(days: 2));
      final close = await db.closeDaily(historicalDate);

      expect(close.walletsTotal, closeTo(0, 0.0001));
      expect(close.drawerBalance, closeTo(0, 0.0001));
      expect(close.treasuryTotal, closeTo(0, 0.0001));
    },
  );

  test(
    'confirming actual-applied deferred transfer after daily close keeps original accounting date',
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

      final pendingTransfers = await db.listTxns(
        kind: 'transfer',
        status: 'pending',
      );
      final pendingTransfer = pendingTransfers.firstWhere(
        (t) => t.id == pendingTxnId,
      );
      final pendingKey = dateKey(pendingTransfer.entryDate);
      final close = await db.closeDaily(pendingTransfer.entryDate);
      await db.confirmPending(pendingTxnId);

      final postedTransfers = await db.listTxns(
        kind: 'transfer',
        status: 'posted',
      );
      expect(postedTransfers.length, 1);
      expect(postedTransfers.first.id, pendingTxnId);

      final postedKey = dateKey(postedTransfers.first.entryDate);
      expect(postedKey, pendingKey);
      expect(close.dateKey, isNotEmpty);

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

    await db.settleClaim(
      claimId: openClaims.first.id,
      amount: openClaims.first.amount,
    );

    expect(() => db.rollbackPosted(fawryTxnId), throwsException);
  });

  test('external funding rejects unknown wallet id', () async {
    final db = AppDb.instance;

    expect(
      () => db.addExternalFunding(walletId: 999999, amount: 10),
      throwsException,
    );
  });

  test('receive rejects unknown wallet id', () async {
    final db = AppDb.instance;

    expect(
      () => db.addReceive(
        walletId: 999999,
        amount: 10,
        commission: 1,
        receiveType: 'cash',
        isPending: true,
      ),
      throwsException,
    );
  });

  test('transfer type2_v2 uses deducted-send math', () async {
    final db = AppDb.instance;

    final walletId = await db.addWallet(
      name: 'Type2 Wallet',
      phone: '01011112222',
      openingBalance: 2000,
    );

    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 1000,
      clientFee: 4,
      networkFee: 1,
      transferType: 'type2',
      isPending: false,
      note: 'type2 new math',
    );
    expect(txnId, greaterThan(0));

    // Wallet spend = amount - CF = 996
    expect(await db.getWalletBalance(walletId), closeTo(1004, 0.0001));
    expect(await db.getWalletAvailableBalance(walletId), closeTo(1004, 0.0001));

    final snap = await db.getTreasurySnapshot();
    // Drawer inflow = customer-paid amount = 1000
    expect(snap.drawerActualBalance, closeTo(1000, 0.0001));
    expect(snap.drawerBalance, closeTo(1000, 0.0001));
    expect(snap.dailyProfit, closeTo(4, 0.0001));
  });

  test('rollback supports posted transfer and receive safely', () async {
    final db = AppDb.instance;

    final walletId = await db.addWallet(
      name: 'Rollback Wallet',
      phone: '01080808080',
      openingBalance: 1000,
    );

    final transferId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 10,
      networkFee: 2,
      transferType: 'type1',
      isPending: false,
      note: 'rollback transfer',
    );
    final receiveId = await db.addReceive(
      walletId: walletId,
      amount: 50,
      commission: 5,
      receiveType: 'cash',
      isPending: false,
      note: 'rollback receive',
    );

    var snap = await db.getTreasurySnapshot();
    expect(await db.getWalletBalance(walletId), closeTo(948, 0.0001));
    expect(snap.drawerActualBalance, closeTo(65, 0.0001));
    expect(snap.profitApprovedTotal, closeTo(15, 0.0001));

    await db.rollbackPosted(receiveId);
    snap = await db.getTreasurySnapshot();
    expect(await db.getWalletBalance(walletId), closeTo(898, 0.0001));
    expect(snap.drawerActualBalance, closeTo(110, 0.0001));
    expect(snap.profitApprovedTotal, closeTo(10, 0.0001));

    await db.rollbackPosted(transferId);
    snap = await db.getTreasurySnapshot();
    expect(await db.getWalletBalance(walletId), closeTo(1000, 0.0001));
    expect(snap.drawerActualBalance, closeTo(0, 0.0001));
    expect(snap.profitApprovedTotal, closeTo(0, 0.0001));

    final txs = await db.listTxns();
    final transferTxn = txs.firstWhere((t) => t.id == transferId);
    final receiveTxn = txs.firstWhere((t) => t.id == receiveId);
    expect(transferTxn.status, 'rolled_back');
    expect(receiveTxn.status, 'rolled_back');
  });

  test('manual daily/monthly usage reset affects limits only', () async {
    final db = AppDb.instance;

    final walletId = await db.addWallet(
      name: 'Usage Reset Wallet',
      phone: '01044445555',
      openingBalance: 5000,
    );

    await db.addTransfer(
      walletId: walletId,
      amount: 1000,
      clientFee: 10,
      networkFee: 0,
      transferType: 'type1',
      isPending: false,
      note: 'usage before reset',
    );

    var usage = await db.getWalletLimitUsage();
    expect(usage[walletId], isNotNull);
    expect(usage[walletId]!.dailyUsed, closeTo(1000, 0.0001));
    expect(usage[walletId]!.monthlyUsed, closeTo(1000, 0.0001));

    final beforeBalance = await db.getWalletBalance(walletId);
    await db.resetWalletDailyUsage(walletId);

    usage = await db.getWalletLimitUsage();
    expect(usage[walletId]!.dailyUsed, closeTo(0, 0.0001));
    expect(usage[walletId]!.monthlyUsed, closeTo(1000, 0.0001));
    expect(await db.getWalletBalance(walletId), closeTo(beforeBalance, 0.0001));

    await db.addTransfer(
      walletId: walletId,
      amount: 300,
      clientFee: 3,
      networkFee: 0,
      transferType: 'type1',
      isPending: false,
      note: 'usage after daily reset',
    );

    usage = await db.getWalletLimitUsage();
    expect(usage[walletId]!.dailyUsed, closeTo(300, 0.0001));
    expect(usage[walletId]!.monthlyUsed, closeTo(1300, 0.0001));

    await db.resetWalletMonthlyUsage(walletId);
    usage = await db.getWalletLimitUsage();
    expect(usage[walletId]!.monthlyUsed, closeTo(0, 0.0001));
    expect(usage[walletId]!.dailyUsed, closeTo(300, 0.0001));
  });

  test('bulk daily/monthly usage reset works for all wallets', () async {
    final db = AppDb.instance;

    final w1 = await db.addWallet(
      name: 'Bulk Reset Wallet 1',
      phone: '01014141414',
      openingBalance: 3000,
    );
    final w2 = await db.addWallet(
      name: 'Bulk Reset Wallet 2',
      phone: '01115151515',
      openingBalance: 3000,
    );

    await db.addTransfer(
      walletId: w1,
      amount: 400,
      clientFee: 4,
      networkFee: 0,
      transferType: 'type1',
      isPending: false,
    );
    await db.addTransfer(
      walletId: w2,
      amount: 700,
      clientFee: 7,
      networkFee: 0,
      transferType: 'type1',
      isPending: false,
    );

    var usage = await db.getWalletLimitUsage();
    expect(usage[w1]!.dailyUsed, closeTo(400, 0.0001));
    expect(usage[w2]!.dailyUsed, closeTo(700, 0.0001));
    expect(usage[w1]!.monthlyUsed, closeTo(400, 0.0001));
    expect(usage[w2]!.monthlyUsed, closeTo(700, 0.0001));

    final bal1 = await db.getWalletBalance(w1);
    final bal2 = await db.getWalletBalance(w2);

    await db.resetAllWalletDailyUsage();
    usage = await db.getWalletLimitUsage();
    expect(usage[w1]!.dailyUsed, closeTo(0, 0.0001));
    expect(usage[w2]!.dailyUsed, closeTo(0, 0.0001));
    expect(usage[w1]!.monthlyUsed, closeTo(400, 0.0001));
    expect(usage[w2]!.monthlyUsed, closeTo(700, 0.0001));
    expect(await db.getWalletBalance(w1), closeTo(bal1, 0.0001));
    expect(await db.getWalletBalance(w2), closeTo(bal2, 0.0001));

    await db.resetAllWalletMonthlyUsage();
    usage = await db.getWalletLimitUsage();
    expect(usage[w1]!.monthlyUsed, closeTo(0, 0.0001));
    expect(usage[w2]!.monthlyUsed, closeTo(0, 0.0001));
  });

  test('reconciliation report equation is balanced', () async {
    final db = AppDb.instance;

    final walletId = await db.addWallet(
      name: 'Recon Wallet',
      phone: '01122225555',
      openingBalance: 1000,
    );
    await db.drawerDeposit(amount: 200, note: 'recon drawer');
    await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 10,
      networkFee: 0,
      transferType: 'type1',
      isPending: false,
    );
    await db.addReceive(
      walletId: walletId,
      amount: 50,
      commission: 5,
      receiveType: 'cash',
      isPending: false,
    );

    final txns = await db.listTxns();
    final claims = await db.listClaims();
    final now = DateTime.now();
    final range = DateRange(
      start: DateTime(now.year, now.month, now.day, 0, 0, 0),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
    );
    final report = ReportCalculator.build(
      txns: txns,
      claims: claims,
      range: range,
    );

    expect(report.reconciliation.drawer.ok, isTrue);
    expect(report.reconciliation.wallets.ok, isTrue);
    expect(report.reconciliation.total.ok, isTrue);
    expect(report.reconciliation.total.diff.abs(), lessThan(0.0001));
  });

  test(
    'treasury formulas separate claims from liquidity and include pending net correctly',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Formula Wallet',
        phone: '01077778888',
        openingBalance: 1000,
      );

      await db.drawerDeposit(amount: 200, note: 'seed drawer');
      await db.addClaim(
        type: 'receivable',
        party: 'Client X',
        amount: 300,
        note: 'open receivable',
      );
      await db.addClaim(
        type: 'payable',
        party: 'Supplier Y',
        amount: 80,
        note: 'open payable',
      );
      await db.addFawry(
        serviceName: 'Utilities',
        reference: 'F-100',
        amount: 500,
        fee: 10,
        collectionMethod: 'cash',
        party: 'Client Cash',
        isPending: false,
      );

      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        note: 'pending out',
      );
      await db.addReceive(
        walletId: walletId,
        amount: 50,
        commission: 5,
        receiveType: 'cash',
        isPending: true,
        note: 'pending in',
      );

      final snap = await db.getTreasurySnapshot();

      expect(snap.drawerActualBalance, closeTo(555, 0.0001));
      expect(snap.walletsActualTotal, closeTo(950, 0.0001));
      expect(snap.fawryActualBalance, closeTo(-500, 0.0001));
      expect(snap.profitApprovedTotal, closeTo(10, 0.0001));
      expect(snap.actualTreasuryApproved, closeTo(1005, 0.0001));

      expect(snap.claimsReceivableOpen, closeTo(300, 0.0001));
      expect(snap.claimsPayableOpen, closeTo(80, 0.0001));
      expect(snap.claimsNet, closeTo(220, 0.0001));
      expect(snap.realCapitalApproved, closeTo(1225, 0.0001));

      expect(snap.pendingInflow, closeTo(50, 0.0001));
      expect(snap.pendingOutflow, closeTo(100, 0.0001));
      expect(snap.pendingNet, closeTo(-50, 0.0001));
      expect(snap.availableLiquidityNow, closeTo(1005, 0.0001));
    },
  );

  test(
    'partial claim settlement updates drawer and remaining amount correctly',
    () async {
      final db = AppDb.instance;

      final claimId = await db.addClaim(
        type: 'receivable',
        party: 'Partial Client',
        amount: 200,
        note: 'partial test',
      );

      var snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(-200, 0.0001));

      await db.settleClaim(claimId: claimId, amount: 75);
      var openClaims = await db.listClaims(type: 'receivable', status: 'open');
      expect(openClaims.length, 1);
      expect(openClaims.first.id, claimId);
      expect(openClaims.first.amount, closeTo(125, 0.0001));

      snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(-125, 0.0001));
      expect(snap.claimsReceivableOpen, closeTo(125, 0.0001));

      await db.settleClaim(claimId: claimId, amount: 125);
      openClaims = await db.listClaims(type: 'receivable', status: 'open');
      final closedClaims = await db.listClaims(
        type: 'receivable',
        status: 'closed',
      );
      expect(openClaims, isEmpty);
      expect(closedClaims.length, 1);
      expect(closedClaims.first.id, claimId);

      snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(0, 0.0001));
      expect(snap.claimsReceivableOpen, closeTo(0, 0.0001));
    },
  );

  test(
    'combined pending transfer and receive affect liquidity now and post once on confirm',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Combo Pending Wallet',
        phone: '01188889999',
        openingBalance: 1000,
      );

      final transferPendingId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 2,
        transferType: 'type1',
        isPending: true,
        note: 'combo pending transfer',
      );
      final receivePendingId = await db.addReceive(
        walletId: walletId,
        amount: 40,
        commission: 4,
        receiveType: 'cash',
        isPending: true,
        note: 'combo pending receive',
      );

      expect(await db.getWalletBalance(walletId), closeTo(938, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(938, 0.0001),
      );

      var snap = await db.getTreasurySnapshot();
      expect(snap.drawerActualBalance, closeTo(74, 0.0001));
      expect(snap.profitApprovedTotal, closeTo(0, 0.0001));
      expect(snap.pendingInflow, closeTo(40, 0.0001));
      expect(snap.pendingOutflow, closeTo(102, 0.0001));
      expect(snap.availableLiquidityNow, closeTo(1012, 0.0001));

      await db.confirmPending(transferPendingId);

      snap = await db.getTreasurySnapshot();
      expect(await db.getWalletBalance(walletId), closeTo(938, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(938, 0.0001),
      );
      expect(snap.drawerActualBalance, closeTo(74, 0.0001));
      expect(snap.profitApprovedTotal, closeTo(10, 0.0001));
      expect(snap.pendingInflow, closeTo(40, 0.0001));
      expect(snap.pendingOutflow, closeTo(0, 0.0001));

      await db.confirmPending(receivePendingId);

      snap = await db.getTreasurySnapshot();
      expect(await db.getWalletBalance(walletId), closeTo(938, 0.0001));
      expect(
        await db.getWalletAvailableBalance(walletId),
        closeTo(938, 0.0001),
      );
      expect(snap.drawerActualBalance, closeTo(74, 0.0001));
      expect(snap.profitApprovedTotal, closeTo(14, 0.0001));
      expect(snap.pendingInflow, closeTo(0, 0.0001));
      expect(snap.pendingOutflow, closeTo(0, 0.0001));
      expect(snap.actualTreasuryApproved, closeTo(1012, 0.0001));
      expect(snap.availableLiquidityNow, closeTo(1012, 0.0001));
    },
  );

  test('audit hash chain is generated and valid', () async {
    final db = AppDb.instance;

    await db.addWallet(
      name: 'Audit Wallet',
      phone: '01033334444',
      openingBalance: 100,
    );
    await db.addExpense(amount: 10, category: 'test', note: 'audit check');

    final chain = await db.verifyAuditChain();
    expect(chain.ok, isTrue);
    expect(chain.count, greaterThan(0));
    expect(chain.tailHash, isNotNull);
  });

  test(
    'audit list recovers from sqlite snapshot when settings audit is missing',
    () async {
      final db = AppDb.instance;

      await db.addExpense(
        amount: 10,
        category: 'audit-recover',
        note: 'marker',
      );

      final settingsFile = File('${supportDir.path}/king_wallet_settings.json');
      final raw = await settingsFile.readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      j.remove('audit');
      await settingsFile.writeAsString(jsonEncode(j), flush: true);

      final audit = await db.listAudit(limit: 50);
      expect(audit.any((e) => e['type'] == 'expense_add'), isTrue);
    },
  );

  test(
    'audit chain verifies from sqlite snapshot when settings audit is stale',
    () async {
      final db = AppDb.instance;

      await db.addExpense(amount: 11, category: 'audit-stale', note: 'marker');
      final latestAudit = await db.listAudit(limit: 50);
      expect(latestAudit, isNotEmpty);

      final settingsFile = File('${supportDir.path}/king_wallet_settings.json');
      final raw = await settingsFile.readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      j['audit'] = <dynamic>[];
      await settingsFile.writeAsString(jsonEncode(j), flush: true);

      final chain = await db.verifyAuditChain();
      expect(chain.ok, isTrue);
      expect(chain.count, greaterThan(0));
    },
  );

  test('encrypted backup export and restore works with passphrase', () async {
    final db = AppDb.instance;

    await db.addWallet(
      name: 'Encrypted Backup Wallet',
      phone: '01055556666',
      openingBalance: 321,
    );

    const passphrase = 'strong-pass-123';
    final backupPath = await db.exportEncryptedJsonBackupToPath(
      directoryPath: supportDir.path,
      passphrase: passphrase,
    );
    expect(File(backupPath).existsSync(), isTrue);

    await db.resetDatabaseEmpty();
    expect(await db.listWallets(), isEmpty);

    await db.restoreEncryptedJsonBackupFromPath(
      path: backupPath,
      passphrase: passphrase,
    );
    final wallets = await db.listWallets();
    expect(wallets.isNotEmpty, isTrue);
    expect(wallets.any((w) => w.name == 'Encrypted Backup Wallet'), isTrue);
  });

  test(
    'encrypted restore locks after three failed passphrase attempts',
    () async {
      final db = AppDb.instance;

      await db.addWallet(
        name: 'Lock Guard Wallet',
        phone: '01099990000',
        openingBalance: 123,
      );

      const passphrase = 'lock-pass-123';
      final backupPath = await db.exportEncryptedJsonBackupToPath(
        directoryPath: supportDir.path,
        passphrase: passphrase,
      );

      Future<void> wrongTry() async {
        await db.restoreEncryptedJsonBackupFromPath(
          path: backupPath,
          passphrase: 'wrong-pass',
        );
      }

      await expectLater(wrongTry(), throwsException);
      await expectLater(wrongTry(), throwsException);
      await expectLater(wrongTry(), throwsException);

      final status = await db.getEncryptedRestoreStatus();
      expect(status.locked, isTrue);
      expect(status.remainingAttempts, 0);
    },
  );

  test(
    'admin PIN locks after repeated failures and resets after success',
    () async {
      final adminSecurity = AdminSecurityService.instance;

      expect(await adminSecurity.requiresPinSetup(), isTrue);
      expect(await adminSecurity.verifyAdminPin('1234'), isFalse);

      await adminSecurity.setAdminPin('2468');
      expect(await adminSecurity.requiresPinSetup(), isFalse);
      for (var i = 0; i < 5; i++) {
        final ok = await adminSecurity.verifyAdminPin('0000');
        expect(ok, isFalse);
      }

      var status = await adminSecurity.getAdminPinStatus();
      expect(status.locked, isTrue);
      expect(status.remainingAttempts, 0);
      expect(await adminSecurity.verifyAdminPin('2468'), isFalse);

      await adminSecurity.setAdminPin('2468');
      status = await adminSecurity.getAdminPinStatus();
      expect(status.locked, isFalse);
      expect(status.remainingAttempts, 5);
      expect(await adminSecurity.verifyAdminPin('2468'), isTrue);
    },
  );

  test(
    'json restore fails when checksum sidecar exists and is mismatched',
    () async {
      final db = AppDb.instance;

      await db.addWallet(
        name: 'Checksum Wallet',
        phone: '01191919191',
        openingBalance: 77,
      );

      final backupPath = await db.exportJsonBackupToPath(supportDir.path);
      final backupFile = File(backupPath);
      await backupFile.writeAsString(
        '${await backupFile.readAsString()}\n',
        flush: true,
      );

      await db.resetDatabaseEmpty();
      expect(() => db.restoreJsonBackupFromPath(backupPath), throwsException);
    },
  );

  test(
    'json restore keeps backward compatibility when checksum sidecar is absent',
    () async {
      final db = AppDb.instance;

      await db.addWallet(
        name: 'Legacy Restore Wallet',
        phone: '01192929292',
        openingBalance: 88,
      );

      final backupPath = await db.exportJsonBackupToPath(supportDir.path);
      final sidecar = File('$backupPath.sha256');
      if (sidecar.existsSync()) {
        sidecar.deleteSync();
      }

      await db.resetDatabaseEmpty();
      await db.restoreJsonBackupFromPath(backupPath);
      final wallets = await db.listWallets();
      expect(wallets.any((w) => w.name == 'Legacy Restore Wallet'), isTrue);
    },
  );

  test('empty reset stays empty after backup restore cycle', () async {
    final db = AppDb.instance;

    await db.resetDatabaseEmpty();
    expect(await db.listWallets(), isEmpty);

    final backupPath = await db.exportBackupToPath(supportDir.path);
    await db.restoreBackupFromPath(backupPath);

    final wallets = await db.listWallets();
    expect(wallets, isEmpty);
  });

  test('db backup restore keeps data after empty reset', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'DB Restore Wallet',
      phone: '01022223333',
      openingBalance: 150,
    );
    await db.addExternalFunding(walletId: walletId, amount: 25, note: 'test');

    final backupPath = await db.exportBackupToPath(supportDir.path);
    await db.resetDatabaseEmpty();
    expect(await db.listWallets(), isEmpty);

    await db.restoreBackupFromPath(backupPath);
    final wallets = await db.listWallets();
    expect(wallets.any((w) => w.name == 'DB Restore Wallet'), isTrue);
    expect(await db.getWalletBalance(walletId), closeTo(175, 0.0001));
  });

  test('db backup restore restores settings and audit state', () async {
    final db = AppDb.instance;
    final adminSecurity = AdminSecurityService.instance;

    final baseSettings = await db.getAppSettings();
    await db.setAppSettings(
      baseSettings.copyWith(
        businessName: 'DB Backup Settings',
        dayStartHour: 6,
      ),
    );
    await adminSecurity.setAdminPin('2468');
    await db.appendAudit(type: 'db_backup_settings_marker', note: 'before_db');

    final backupPath = await db.exportBackupToPath(supportDir.path);

    await db.setAppSettings(
      baseSettings.copyWith(
        businessName: 'Changed After DB Backup',
        dayStartHour: 0,
      ),
    );
    await adminSecurity.setAdminPin('9999');
    await db.clearAudit();

    await db.restoreBackupFromPath(backupPath);

    final restoredSettings = await db.getAppSettings();
    expect(restoredSettings.businessName, 'DB Backup Settings');
    expect(restoredSettings.dayStartHour, 6);
    expect(await adminSecurity.verifyAdminPin('2468'), isTrue);
    expect(await adminSecurity.verifyAdminPin('9999'), isFalse);
    expect(
      (await db.listAudit(
        limit: 50,
      )).any((e) => e['type'] == 'db_backup_settings_marker'),
      isTrue,
    );
  });

  test('db restore clears stale sync outbox from newer local state', () async {
    final db = AppDb.instance;

    await db.addWallet(
      name: 'DB Backup Base Wallet',
      phone: '01012340001',
      openingBalance: 100,
    );
    await db.clearOutbox();

    final backupPath = await db.exportBackupToPath(supportDir.path);

    await db.addWallet(
      name: 'DB Restore Newer Wallet',
      phone: '01012340002',
      openingBalance: 50,
    );
    expect((await db.listOutbox(limit: 100)).isNotEmpty, isTrue);

    await db.restoreBackupFromPath(backupPath);

    final wallets = await db.listWallets();
    expect(wallets.any((w) => w.name == 'DB Backup Base Wallet'), isTrue);
    expect(wallets.any((w) => w.name == 'DB Restore Newer Wallet'), isFalse);
    expect(await db.listOutbox(limit: 100), isEmpty);
  });

  test('json backup restore keeps data after empty reset', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'JSON Restore Wallet',
      phone: '01133334444',
      openingBalance: 200,
    );

    final backupPath = await db.exportJsonBackupToPath(supportDir.path);
    await db.resetDatabaseEmpty();
    expect(await db.listWallets(), isEmpty);

    await db.restoreJsonBackupFromPath(backupPath);
    final wallets = await db.listWallets();
    expect(wallets.any((w) => w.name == 'JSON Restore Wallet'), isTrue);
    expect(await db.getWalletBalance(walletId), closeTo(200, 0.0001));
  });

  test('json backup restore restores settings and audit state', () async {
    final db = AppDb.instance;
    final adminSecurity = AdminSecurityService.instance;

    final baseSettings = await db.getAppSettings();
    await db.setAppSettings(
      baseSettings.copyWith(
        businessName: 'JSON Backup Settings',
        dayStartHour: 7,
      ),
    );
    await adminSecurity.setAdminPin('1357');
    await db.appendAudit(
      type: 'json_backup_settings_marker',
      note: 'before_json',
    );

    final backupPath = await db.exportJsonBackupToPath(supportDir.path);

    await db.setAppSettings(
      baseSettings.copyWith(
        businessName: 'Changed After JSON Backup',
        dayStartHour: 0,
      ),
    );
    await adminSecurity.setAdminPin('8888');
    await db.clearAudit();

    await db.restoreJsonBackupFromPath(backupPath);

    final restoredSettings = await db.getAppSettings();
    expect(restoredSettings.businessName, 'JSON Backup Settings');
    expect(restoredSettings.dayStartHour, 7);
    expect(await adminSecurity.verifyAdminPin('1357'), isTrue);
    expect(await adminSecurity.verifyAdminPin('8888'), isFalse);
    expect(
      (await db.listAudit(
        limit: 50,
      )).any((e) => e['type'] == 'json_backup_settings_marker'),
      isTrue,
    );
  });

  test(
    'json restore clears stale sync outbox from newer local state',
    () async {
      final db = AppDb.instance;

      await db.addWallet(
        name: 'JSON Backup Base Wallet',
        phone: '01112340001',
        openingBalance: 100,
      );
      await db.clearOutbox();

      final backupPath = await db.exportJsonBackupToPath(supportDir.path);

      await db.addWallet(
        name: 'JSON Restore Newer Wallet',
        phone: '01112340002',
        openingBalance: 50,
      );
      expect((await db.listOutbox(limit: 100)).isNotEmpty, isTrue);

      await db.restoreJsonBackupFromPath(backupPath);

      final wallets = await db.listWallets();
      expect(wallets.any((w) => w.name == 'JSON Backup Base Wallet'), isTrue);
      expect(
        wallets.any((w) => w.name == 'JSON Restore Newer Wallet'),
        isFalse,
      );
      expect(await db.listOutbox(limit: 100), isEmpty);
    },
  );

  test('json restore auto-repairs duplicated ids before persisting', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Dup Repair Wallet',
      phone: '01044445555',
      openingBalance: 120,
    );
    await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 4,
      networkFee: 1,
      transferType: 'type1',
    );

    final backupPath = await db.exportJsonBackupToPath(supportDir.path);
    final raw = await File(backupPath).readAsString();
    final j = jsonDecode(raw) as Map<String, dynamic>;

    final wallets = (j['wallets'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final txns = (j['txns'] as List<dynamic>).cast<Map<String, dynamic>>();
    wallets.add(Map<String, dynamic>.from(wallets.first));
    txns.add(Map<String, dynamic>.from(txns.first));

    j['nextWalletId'] = 1;
    j['nextTxnId'] = 1;
    j['nextClaimId'] = 1;
    j['nextCloseId'] = 1;

    final brokenPath =
        '${supportDir.path}${Platform.pathSeparator}dup_ids_restore.json';
    await File(brokenPath).writeAsString(jsonEncode(j));

    await db.resetDatabaseEmpty();
    await db.restoreJsonBackupFromPath(brokenPath);

    final repairedWallets = await db.listWallets();
    expect(
      repairedWallets.map((w) => w.id).toSet().length,
      repairedWallets.length,
    );
    final txnsAfter = await db.listTxns();
    expect(txnsAfter.map((t) => t.id).toSet().length, txnsAfter.length);

    final integrity = await db.runIntegrityCheck(force: true);
    expect(integrity.ok, isTrue);
    expect(integrity.issues, isEmpty);
  });

  test('duplicate repair is a no-op on clean data', () async {
    final db = AppDb.instance;

    await db.addWallet(
      name: 'Repair Clean Wallet',
      phone: '01012349876',
      openingBalance: 100,
    );

    final result = await db.repairDuplicateIntegrityIssues(
      createJsonBackup: false,
    );
    expect(result.changed, isFalse);
    expect(result.after.ok, isTrue);
    expect(result.after.issues, isEmpty);
  });

  test(
    'wallet add persists wallet and opening-balance outbox entries',
    () async {
      final db = AppDb.instance;

      await db.clearOutbox();
      final walletId = await db.addWallet(
        name: 'Outbox Wallet',
        phone: '01012344321',
        openingBalance: 75,
      );

      final outbox = await db.listOutbox(limit: 20);
      expect(
        outbox.any(
          (e) =>
              e.entity == 'wallet' &&
              e.entityId == walletId.toString() &&
              e.action == 'create',
        ),
        isTrue,
      );
      expect(
        outbox.any((e) => e.entity == 'txn' && e.action == 'create'),
        isTrue,
      );
    },
  );

  test('wallet add with opening balance persists both audit entries', () async {
    final db = AppDb.instance;

    final walletId = await db.addWallet(
      name: 'Audit Wallet',
      phone: '01012344322',
      openingBalance: 90,
    );

    final audit = await db.listAudit(limit: 20);
    expect(
      audit.any(
        (e) =>
            e['type'] == 'wallet_opening_balance' &&
            (e['walletId'] as num?)?.toInt() == walletId &&
            ((e['amount'] as num?)?.toDouble() ?? 0) == 90,
      ),
      isTrue,
    );
    expect(
      audit.any(
        (e) =>
            e['type'] == 'wallet_add' &&
            (e['walletId'] as num?)?.toInt() == walletId,
      ),
      isTrue,
    );
  });

  test(
    'confirm pending with prior settlement persists confirm update and adjust outbox entries',
    () async {
      final db = AppDb.instance;

      final walletId = await db.addWallet(
        name: 'Pending Adjust Wallet',
        phone: '01012344322',
        openingBalance: 500,
      );
      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 10,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
      );
      await db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 20);
      await db.clearOutbox();

      await db.confirmPending(txnId);

      final adjustTxn = (await db.listTxns(
        kind: 'pending_settlement_adjust',
        status: 'posted',
      )).single;
      final outbox = await db.listOutbox(limit: 20);
      expect(
        outbox.any(
          (e) =>
              e.entity == 'txn' &&
              e.entityId == txnId.toString() &&
              e.action == 'update',
        ),
        isTrue,
      );
      expect(
        outbox.any(
          (e) =>
              e.entity == 'txn' &&
              e.entityId == adjustTxn.id.toString() &&
              e.action == 'create',
        ),
        isTrue,
      );
    },
  );

  test(
    'json restore blocks unsafe duplicate claim ids when settlement references already exist',
    () async {
      final db = AppDb.instance;

      final claimId = await db.addClaim(
        type: 'receivable',
        party: 'Unsafe Duplicate Claim',
        amount: 100,
        note: 'base claim',
      );
      await db.settleClaim(claimId: claimId, amount: 100);

      final backupPath = await db.exportJsonBackupToPath(supportDir.path);
      final raw = await File(backupPath).readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final claims = (j['claims'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final duplicated = Map<String, dynamic>.from(claims.first);
      duplicated['party'] = 'Unsafe Duplicate Claim Copy';
      duplicated['amount'] = 130.0;
      claims.add(duplicated);

      final brokenPath =
          '${supportDir.path}${Platform.pathSeparator}unsafe_dup_claim_restore.json';
      await File(brokenPath).writeAsString(jsonEncode(j), flush: true);

      await db.resetDatabaseEmpty();
      expect(() => db.restoreJsonBackupFromPath(brokenPath), throwsException);
      expect(await db.listClaims(), isEmpty);
    },
  );

  test('reset with seed stays deterministic across repeated runs', () async {
    final db = AppDb.instance;

    await db.resetDatabase();
    var wallets = await db.listWallets();
    expect(wallets.length, 2);
    expect(wallets.map((w) => w.id).toSet().length, 2);
    expect(wallets.map((w) => w.id).toSet(), {1, 2});

    await db.resetDatabase();
    wallets = await db.listWallets();
    expect(wallets.length, 2);
    expect(wallets.map((w) => w.id).toSet().length, 2);
    expect(wallets.map((w) => w.id).toSet(), {1, 2});

    final integrity = await db.runIntegrityCheck(force: true);
    expect(integrity.ok, isTrue);
    expect(integrity.issues, isEmpty);
  });

  test(
    'json restore with missing next ids still allocates unique ids',
    () async {
      final db = AppDb.instance;

      await db.addWallet(
        name: 'Restore Counter A',
        phone: '01011111111',
        openingBalance: 50,
      );
      await db.addWallet(
        name: 'Restore Counter B',
        phone: '01022222222',
        openingBalance: 75,
      );

      final backupPath = await db.exportJsonBackupToPath(supportDir.path);
      final raw = await File(backupPath).readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      j.remove('nextWalletId');
      j.remove('nextTxnId');
      j.remove('nextClaimId');
      j.remove('nextCloseId');
      final brokenPath =
          '${supportDir.path}${Platform.pathSeparator}broken_restore.json';
      await File(brokenPath).writeAsString(jsonEncode(j));

      await db.resetDatabaseEmpty();
      await db.restoreJsonBackupFromPath(brokenPath);

      final before = await db.listWallets();
      final maxId = before.map((w) => w.id).reduce((a, b) => a > b ? a : b);
      final newId = await db.addWallet(
        name: 'Restore Counter C',
        phone: '01033333333',
        openingBalance: 10,
      );
      expect(newId, greaterThan(maxId));

      final after = await db.listWallets();
      expect(after.map((w) => w.id).toSet().length, after.length);
      final integrity = await db.runIntegrityCheck(force: true);
      expect(integrity.ok, isTrue);
      expect(integrity.issues, isEmpty);
    },
  );
}
