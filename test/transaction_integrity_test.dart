import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_transaction_integrity_test_',
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

  test('لا يمكن اعتماد نفس العملية المعلقة مرتين', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'محفظة اختبار',
      phone: '01000000001',
      openingBalance: 1000,
    );

    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 5,
      networkFee: 2,
      transferType: 'type1',
      isPending: true,
      party: 'عميل اختبار',
    );

    await db.confirmPending(txnId);

    await expectLater(() => db.confirmPending(txnId), throwsException);
  });

  test('إلغاء العملية المنفذة يعكس رصيد المحفظة بالكامل', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'محفظة اختبار',
      phone: '01000000002',
      openingBalance: 1000,
    );

    final before = await db.getWalletBalance(walletId);

    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 5,
      networkFee: 2,
      transferType: 'type1',
      isPending: false,
      party: 'عميل اختبار',
    );

    await db.rollbackPosted(txnId);

    final after = await db.getWalletBalance(walletId);

    expect(after, equals(before));
  });

  test('لا يمكن تسوية أكثر من المتبقي في المستحق', () async {
    final db = AppDb.instance;

    final claimId = await db.addClaim(
      type: 'receivable',
      party: 'عميل اختبار',
      amount: 100,
    );

    await db.settleClaim(claimId: claimId, amount: 80);

    await expectLater(
      () => db.settleClaim(claimId: claimId, amount: 50),
      throwsException,
    );
  });

  test('لا يمكن تسوية pending بأكثر من المتبقي', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'محفظة اختبار',
      phone: '01000000003',
      openingBalance: 1000,
    );

    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 0,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: 'عميل اختبار',
    );

    await db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 40);

    await expectLater(
      () => db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 70),
      throwsException,
    );
  });

  test('إلغاء العملية المعلقة يغير حالتها إلى canceled', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'محفظة اختبار',
      phone: '01000000004',
      openingBalance: 1000,
    );

    final txnId = await db.addReceive(
      walletId: walletId,
      amount: 200,
      commission: 10,
      receiveType: 'cash',
      isPending: true,
      party: 'عميل اختبار',
    );

    await db.cancelPending(txnId);

    final txns = await db.listTxns();
    final txn = txns.firstWhere((t) => t.id == txnId);
    expect(txn.status, equals('canceled'));
  });

  test('تحصيل pending ينشئ حركة claim_collect بالمبلغ الصحيح', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'محفظة اختبار',
      phone: '01000000005',
      openingBalance: 1000,
    );

    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 0,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: 'عميل اختبار',
    );

    final settlementTxnId = await db.addPendingSettlementForTxn(
      pendingTxnId: txnId,
      amount: 40,
    );

    final txns = await db.listTxns();
    final settlement = txns.firstWhere((t) => t.id == settlementTxnId);

    expect(settlement.kind, equals('claim_collect'));
    expect(settlement.amount, equals(40));
    expect(settlement.status, equals('posted'));
  });

  test(
    'إلغاء العملية المعلقة يمنع اعتمادها لاحقًا ويحافظ على عكس الرصيد',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'محفظة اختبار',
        phone: '01000000006',
        openingBalance: 1000,
      );

      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 5,
        networkFee: 2,
        transferType: 'type1',
        isPending: true,
        party: 'عميل اختبار',
      );

      expect(await db.getWalletBalance(walletId), closeTo(898, 0.0001));

      await db.cancelPending(txnId);

      expect(await db.getWalletBalance(walletId), closeTo(1000, 0.0001));
      await expectLater(() => db.confirmPending(txnId), throwsException);
    },
  );

  test('rollback تسوية pending يعيد فتح المتبقي ويسمح بتسوية جديدة', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'محفظة اختبار',
      phone: '01000000007',
      openingBalance: 1000,
    );

    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 0,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: 'عميل اختبار',
    );

    final firstSettlementId = await db.addPendingSettlementForTxn(
      pendingTxnId: txnId,
      amount: 40,
    );

    await db.rollbackPendingSettlement(firstSettlementId);

    final secondSettlementId = await db.addPendingSettlementForTxn(
      pendingTxnId: txnId,
      amount: 100,
    );
    final txns = await db.listTxns();
    final firstSettlement = txns.firstWhere((t) => t.id == firstSettlementId);
    final secondSettlement = txns.firstWhere((t) => t.id == secondSettlementId);

    expect(firstSettlement.status, equals('rolled_back'));
    expect(secondSettlement.status, equals('posted'));
    expect(secondSettlement.amount, equals(100));
  });

  test('لا يمكن rollback تسوية مستحق ليست الأخيرة', () async {
    final db = AppDb.instance;

    final claimId = await db.addClaim(
      type: 'receivable',
      party: 'عميل اختبار',
      amount: 300,
    );

    final firstSettlementId = await db.settleClaim(
      claimId: claimId,
      amount: 100,
    );
    await db.settleClaim(claimId: claimId, amount: 50);

    await expectLater(
      () => db.rollbackClaimSettlement(firstSettlementId),
      throwsException,
    );
  });

  test(
    'concurrent confirmPending approves the same pending transaction once only',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Concurrent Confirm Wallet',
        phone: '01000000008',
        openingBalance: 1000,
      );

      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 5,
        networkFee: 2,
        transferType: 'type1',
        isPending: true,
        party: 'Concurrent Customer',
      );

      final results = await Future.wait([
        db.confirmPending(txnId).then((_) => true).catchError((_) => false),
        db.confirmPending(txnId).then((_) => true).catchError((_) => false),
      ]);

      final txns = await db.listTxns();
      final txn = txns.firstWhere((t) => t.id == txnId);

      expect(results.where((success) => success).length, equals(1));
      expect(txn.status, equals('posted'));
      expect(await db.getWalletBalance(walletId), closeTo(898, 0.0001));
    },
  );

  test(
    'bulk-style approve and cancel loops keep wallet balances consistent',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Bulk Flow Wallet',
        phone: '01000000009',
        openingBalance: 1000,
      );

      final approveIds = <int>[
        await db.addTransfer(
          walletId: walletId,
          amount: 100,
          clientFee: 0,
          networkFee: 2,
          transferType: 'type1',
          isPending: true,
          party: 'Bulk Customer A',
        ),
        await db.addTransfer(
          walletId: walletId,
          amount: 50,
          clientFee: 0,
          networkFee: 1,
          transferType: 'type1',
          isPending: true,
          party: 'Bulk Customer B',
        ),
      ];

      expect(await db.getWalletBalance(walletId), closeTo(847, 0.0001));

      for (final id in approveIds) {
        await db.confirmPending(id);
      }

      expect(await db.getWalletBalance(walletId), closeTo(847, 0.0001));

      final cancelIds = <int>[
        await db.addTransfer(
          walletId: walletId,
          amount: 20,
          clientFee: 0,
          networkFee: 1,
          transferType: 'type1',
          isPending: true,
          party: 'Bulk Customer C',
        ),
        await db.addTransfer(
          walletId: walletId,
          amount: 30,
          clientFee: 0,
          networkFee: 1,
          transferType: 'type1',
          isPending: true,
          party: 'Bulk Customer D',
        ),
      ];

      expect(await db.getWalletBalance(walletId), closeTo(795, 0.0001));

      for (final id in cancelIds) {
        await db.cancelPending(id);
      }

      final txns = await db.listTxns();
      expect(await db.getWalletBalance(walletId), closeTo(847, 0.0001));
      for (final id in approveIds) {
        expect(txns.firstWhere((t) => t.id == id).status, equals('posted'));
      }
      for (final id in cancelIds) {
        expect(txns.firstWhere((t) => t.id == id).status, equals('canceled'));
      }
    },
  );

  test('cannot rollback a non-latest pending settlement', () async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Pending Settlement Wallet',
      phone: '01000000010',
      openingBalance: 1000,
    );

    final pendingTxnId = await db.addTransfer(
      walletId: walletId,
      amount: 100,
      clientFee: 0,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: 'Settlement Customer',
    );

    final firstSettlementId = await db.addPendingSettlementForTxn(
      pendingTxnId: pendingTxnId,
      amount: 30,
    );
    await db.addPendingSettlementForTxn(pendingTxnId: pendingTxnId, amount: 20);

    await expectLater(
      () => db.rollbackPendingSettlement(firstSettlementId),
      throwsException,
    );
  });

  test(
    'rolled back pending settlement does not create adjust on confirm',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Pending Adjust Wallet',
        phone: '01000000011',
        openingBalance: 1000,
      );

      final pendingTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Adjust Customer',
      );

      final settlementId = await db.addPendingSettlementForTxn(
        pendingTxnId: pendingTxnId,
        amount: 40,
      );

      await db.rollbackPendingSettlement(settlementId);
      await db.confirmPending(pendingTxnId);

      final adjustTxns = await db.listTxns(kind: 'pending_settlement_adjust');
      final txns = await db.listTxns();
      final settlement = txns.firstWhere((t) => t.id == settlementId);
      final pendingTxn = txns.firstWhere((t) => t.id == pendingTxnId);

      expect(adjustTxns, isEmpty);
      expect(settlement.status, equals('rolled_back'));
      expect(pendingTxn.status, equals('posted'));
    },
  );
}
