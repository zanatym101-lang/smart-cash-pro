import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/wallet_ledger/wallet_ledger_builder.dart';
import 'package:king_wallet_accounting/screens/treasury_ledger/treasury_ledger_builder.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_parity_shadow_builders_');

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

  group('Shadow Parity - Builders vs Legacy Data', () {
    test('Wallet Ledger Parity', () async {
      final db = AppDb.instance;
      
      // 1. Setup Data
      final walletId = await db.addWallet(
        name: 'Parity Wallet',
        phone: '01010001001',
        openingBalance: 1000,
      );
      
      await db.addTransfer(
        walletId: walletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: false,
      );
      
      await db.addReceive(
        walletId: walletId,
        amount: 500,
        commission: 0,
        receiveType: 'cash',
        isPending: false,
      );
      
      // 2. Fetch from AppDb (Legacy method)
      final allWallets = await db.listWallets();
      final legacyBalance = await db.getWalletBalance(walletId);

      // 3. Fetch from new Builder
      final txns = await db.listTxns();
      final builderResult = WalletLedgerBuilder.build(txns: txns, wallets: allWallets);
      final walletAccount = builderResult.firstWhere((w) => w.walletId == walletId.toString());
      
      // 4. Validate Parity
      expect(walletAccount.currentBalance.piastres, closeTo(legacyBalance * 100, 0.0001));
    });

    test('Treasury Ledger Parity', () async {
      final db = AppDb.instance;
      
      // 1. Setup Data
      await db.drawerDeposit(amount: 1000, note: 'seed drawer');
      
      final walletId = await db.addWallet(
        name: 'Treasury Wallet',
        phone: '01010001002',
        openingBalance: 2000, // Wallets contribute to liquidity
      );
      
      await db.addTransfer(
        walletId: walletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: false,
      );
      
      // 2. Fetch from AppDb (Legacy method)
      final oldSnap = await db.getTreasurySnapshot();
      final expectedClosingBalance = oldSnap.drawerActualBalance;
      
      // 3. Fetch from new Builder
      final txnsMap = {
         for (final t in await db.listTxns()) t.id.toString(): t
      };
      
      final builderResult = TreasuryLedgerBuilder.build(
        drawerEntries: db.ledgerEntries.where((e) => e.accountKey == 'drawer').toList(),
        txnsMap: txnsMap,
      );
      
      // 4. Validate Parity
      expect(builderResult.closingBalance.piastres, closeTo(expectedClosingBalance * 100, 0.0001));
    });

    test('Customer Account Parity', () async {
      final db = AppDb.instance;
      
      // 1. Setup Data
      final walletId = await db.addWallet(
        name: 'Customer Wallet',
        phone: '01010001003',
        openingBalance: 2000,
      );
      
      final pendingTxnId1 = await db.addTransfer(
        walletId: walletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Parity Customer',
      );
      
      final pendingTxnId2 = await db.addReceive(
        walletId: walletId,
        amount: 400,
        commission: 0,
        receiveType: 'cash',
        isPending: true,
        party: 'Parity Customer',
      );
      
      await db.addPendingSettlementForTxn(
        pendingTxnId: pendingTxnId1,
        amount: 500,
      );
      
      await db.confirmPending(pendingTxnId1);
      await db.confirmPending(pendingTxnId2);

      // 2. Fetch from AppDb (Legacy method)
      final txns = await db.listTxns();
      final claims = await db.listClaims();
      
      // The builder is the primary source of truth, but let's check its math
      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: txns,
        claims: claims,
      );
      
      final customerAccount = accounts.firstWhere((acc) => acc.summary.customerName == 'Parity Customer');
      
      // 3. Validate math constraints
      // totalForUs = claim remaining from transfer (900 + 5 - 500 = 405)
      // totalAgainstUs = claim from receive (400)
      // collected = 500
      expect(customerAccount.summary.totalForUs, closeTo(405, 0.0001));
      expect(customerAccount.summary.totalAgainstUs, closeTo(400, 0.0001));
      expect(customerAccount.summary.netBalance, closeTo(5, 0.0001)); // 405 - 400
    });

    test('Wallet Ledger & Dashboard Treasury Network Fee Alignment (3004.00 vs 3003.00)', () async {
      final db = AppDb.instance;

      // 1. Setup Drawer (2000) and Wallet (2005)
      await db.drawerDeposit(amount: 2000, note: 'seed drawer 2000');
      final walletId = await db.addWallet(
        name: 'Fee Test Wallet',
        phone: '01010001099',
        openingBalance: 2005,
      );

      // 2. Transfer 1000 with network fee 1 and client fee 5 (posted immediately)
      await db.addTransfer(
        walletId: walletId,
        amount: 1000,
        clientFee: 5,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
      );

      // 3. Verify single wallet balance
      final legacyBalance = await db.getWalletBalance(walletId);
      expect(legacyBalance, closeTo(1004.0, 0.0001)); // 2005 - (1000 + 1) = 1004.0

      // 4. Verify WalletLedgerBuilder
      final allWallets = await db.listWallets();
      final txns = await db.listTxns();
      final builderResult = WalletLedgerBuilder.build(txns: txns, wallets: allWallets);
      final walletAccount = builderResult.firstWhere((w) => w.walletId == walletId.toString());

      expect(walletAccount.currentBalance.toDouble(), closeTo(1004.0, 0.0001));
      expect(walletAccount.totalTransferred.toDouble(), closeTo(1000.0, 0.0001));
      expect(walletAccount.totalFees.toDouble(), closeTo(1.0, 0.0001));

      // 5. Verify Treasury Snapshot (Dashboard numbers)
      final snap = await db.getTreasurySnapshot();
      expect(snap.walletsActualTotal, closeTo(1004.0, 0.0001));
      // Drawer: 2000 (deposit) + 1005 (transfer in) = 3005.
      // Total Actual Treasury = drawer (3005) + wallet (1004) = 4009.
      expect(snap.actualTreasuryApproved, closeTo(snap.drawerActualBalance + snap.walletsActualTotal, 0.0001));
      expect(snap.availableLiquidityNow, closeTo(snap.actualTreasuryApproved, 0.0001));
    });
  });
}
