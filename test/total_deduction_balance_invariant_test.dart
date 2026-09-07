import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_total_deduction_test_');

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

  group('Total-Deduction Balance Invariant (Amount + Fees <= Available Balance)', () {
    test('wallet balance = 500, transfer = 500, fee = 5 -> MUST BE REJECTED with Arabic error message', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Wallet 1',
        phone: '01000000001',
        openingBalance: 500,
      );

      final availableBefore = await db.getWalletAvailableBalance(walletId);
      expect(availableBefore, equals(500.00));

      expect(
        () => db.addTransfer(
          walletId: walletId,
          amount: 500,
          clientFee: 0,
          networkFee: 5,
          transferType: 'type1',
          isPending: false,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'عفواً، رصيد المحفظة غير كافٍ. المطلوب خصمه (المبلغ: 500.00 + الرسوم: 5.00 = إجمالي: 505.00 ج.م) أكبر من الرصيد المتاح (500.00 ج.م)',
            ),
          ),
        ),
      );

      // Verify wallet balance remained untouched
      final availableAfter = await db.getWalletAvailableBalance(walletId);
      expect(availableAfter, equals(500.00));
      final actualAfter = await db.getWalletBalance(walletId);
      expect(actualAfter, equals(500.00));
    });

    test('wallet balance = 505, transfer = 500, fee = 5 -> MUST PASS with remaining balance = 0.00', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Wallet 2',
        phone: '01000000002',
        openingBalance: 505,
      );

      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 500,
        clientFee: 0,
        networkFee: 5,
        transferType: 'type1',
        isPending: false,
      );

      expect(txnId, greaterThan(0));

      final availableAfter = await db.getWalletAvailableBalance(walletId);
      expect(availableAfter, equals(0.00));
      final actualAfter = await db.getWalletBalance(walletId);
      expect(actualAfter, equals(0.00));
    });

    test('wallet balance = 500, transfer = 500, fee = 0 -> MUST PASS with remaining balance = 0.00', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Wallet 3',
        phone: '01000000003',
        openingBalance: 500,
      );

      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 500,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: false,
      );

      expect(txnId, greaterThan(0));

      final availableAfter = await db.getWalletAvailableBalance(walletId);
      expect(availableAfter, equals(0.00));
      final actualAfter = await db.getWalletBalance(walletId);
      expect(actualAfter, equals(0.00));
    });

    test('type2 transfer: amount = 505, clientFee = 5, networkFee = 5 with balance = 500 -> PASSES with 0.00 balance', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Wallet 4',
        phone: '01000000004',
        openingBalance: 500,
      );

      // In type2: walletSpend = amount - clientFee = 505 - 5 = 500.
      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 505,
        clientFee: 5,
        networkFee: 5,
        transferType: 'type2',
        isPending: false,
      );

      expect(txnId, greaterThan(0));

      final availableAfter = await db.getWalletAvailableBalance(walletId);
      expect(availableAfter, equals(0.00));
    });

    test('type2 transfer: amount = 510, clientFee = 5, networkFee = 5 with balance = 500 -> REJECTED (spend = 505)', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Wallet 5',
        phone: '01000000005',
        openingBalance: 500,
      );

      // In type2: recipient amount = 510 - 5 - 5 = 500, fee = 5, total deduction = 505 > 500
      expect(
        () => db.addTransfer(
          walletId: walletId,
          amount: 510,
          clientFee: 5,
          networkFee: 5,
          transferType: 'type2',
          isPending: false,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'عفواً، رصيد المحفظة غير كافٍ. المطلوب خصمه (المبلغ: 500.00 + الرسوم: 5.00 = إجمالي: 505.00 ج.م) أكبر من الرصيد المتاح (500.00 ج.م)',
            ),
          ),
        ),
      );
    });

    test('fractional edge case: balance = 500.00, transfer = 500.00, fee = 0.01 -> MUST BE REJECTED', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Wallet 6',
        phone: '01000000006',
        openingBalance: 500.00,
      );

      expect(
        () => db.addTransfer(
          walletId: walletId,
          amount: 500.00,
          clientFee: 0,
          networkFee: 0.01,
          transferType: 'type1',
          isPending: false,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'عفواً، رصيد المحفظة غير كافٍ. المطلوب خصمه (المبلغ: 500.00 + الرسوم: 0.01 = إجمالي: 500.01 ج.م) أكبر من الرصيد المتاح (500.00 ج.م)',
            ),
          ),
        ),
      );
    });

    test('fractional edge case: balance = 500.01, transfer = 500.00, fee = 0.01 -> MUST PASS with remaining balance = 0.00', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Wallet 7',
        phone: '01000000007',
        openingBalance: 500.01,
      );

      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 500.00,
        clientFee: 0,
        networkFee: 0.01,
        transferType: 'type1',
        isPending: false,
      );

      expect(txnId, greaterThan(0));
      final availableAfter = await db.getWalletAvailableBalance(walletId);
      expect(availableAfter, equals(0.00));
    });
  });
}
