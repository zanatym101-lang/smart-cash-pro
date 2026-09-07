import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_workspace_reset_test_',
  );

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
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  });

  group('Workspace Reset Epoch & Cloud Sync Guards', () {
    test('recordWorkspaceResetEpoch and getWorkspaceResetEpoch work properly', () async {
      final db = AppDb.instance;
      final nowMs = DateTime(2026, 6, 1, 12, 0).millisecondsSinceEpoch;
      await db.recordWorkspaceResetEpoch(nowMs);

      final fetched = await db.getWorkspaceResetEpoch();
      expect(fetched, equals(nowMs));
    });

    test('applyCloudUpdates reconciles and deduplicates wallets with matching name or phone', () async {
      final db = AppDb.instance;
      // 1. Create a local wallet
      final walletId = await db.addWallet(
        name: 'فودافون كاش رئيسية',
        phone: '01011112222',
        allowNegative: false,
        dailyLimit: 30000,
        monthlyLimit: 100000,
        lowBalanceThreshold: 500,
      );
      expect(walletId, isPositive);

      final walletsBefore = await db.listWallets();
      expect(walletsBefore, hasLength(1));

      // 2. Incoming cloud payload with same name but different remote ID
      final cloudPayload = [
        {
          'id': 999,
          'name': 'فودافون كاش رئيسية',
          'phone': '01011112222',
          'allowNegative': false,
          'dailyLimit': 40000,
          'monthlyLimit': 120000,
          'lowBalanceThreshold': 600,
        }
      ];

      await db.applyCloudUpdates('wallet', cloudPayload);

      final walletsAfter = await db.listWallets();
      // Should not create phantom duplicate wallet!
      expect(walletsAfter, hasLength(1));
      expect(walletsAfter.first.dailyLimit, equals(40000));
    });

    test('applyCloudUpdates rejects ghost transactions and claims preceding reset epoch', () async {
      final db = AppDb.instance;
      final resetTime = DateTime(2026, 6, 1, 12, 0);
      await db.recordWorkspaceResetEpoch(resetTime.millisecondsSinceEpoch);

      // Incoming old transaction from before reset
      final oldTxnPayload = [
        {
          'id': 501,
          'kind': 'transfer',
          'status': 'posted',
          'entryDate': DateTime(2026, 5, 20, 10, 0).toIso8601String(),
          'amount': 500.0,
          'clientFee': 10.0,
          'networkFee': 0.0,
          'mode': 'type1',
          'party': 'عميل قديم',
          'createdBy': 'admin',
          'createdRole': 'admin',
          'createdAt': DateTime(2026, 5, 20, 10, 0).toIso8601String(),
        }
      ];

      // Incoming old claim from before reset
      final oldClaimPayload = [
        {
          'id': 601,
          'type': 'receivable',
          'party': 'عميل قديم',
          'amount': 300.0,
          'note': 'مطالبة قديمة',
          'entryDate': DateTime(2026, 5, 20, 10, 0).toIso8601String(),
          'status': 'open',
        }
      ];

      await db.applyCloudUpdates('txn', oldTxnPayload);
      await db.applyCloudUpdates('claim', oldClaimPayload);

      final txns = await db.listTxns();
      final claims = await db.listClaims();

      expect(txns, isEmpty);
      expect(claims, isEmpty);

      // Create wallet with funds for new transfer
      final wId = await db.addWallet(
        name: 'محفظة الاختبار',
        phone: '01099998888',
        openingBalance: 1000.0,
      );

      // Incoming new transaction AFTER reset
      final newTxnPayload = [
        {
          'id': 502,
          'kind': 'transfer',
          'status': 'posted',
          'walletFromId': wId,
          'entryDate': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
          'amount': 200.0,
          'clientFee': 5.0,
          'networkFee': 0.0,
          'mode': 'type1',
          'party': 'عميل جديد',
          'createdBy': 'admin',
          'createdRole': 'admin',
          'createdAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        }
      ];

      await db.applyCloudUpdates('txn', newTxnPayload);
      final txnsAfter = await db.listTxns();
      expect(txnsAfter.any((t) => t.id == 502), isTrue);
    });
  });

  group('Dashboard Metrics Alignment After Reset', () {
    test('1 wallet with 1000.00 and drawer 0.00 gives exact treasury alignment', () async {
      final db = AppDb.instance;
      await db.resetDatabaseEmpty();

      // Create 1 wallet with 1000.00 opening balance
      await db.addWallet(
        name: 'المحفظة الأساسية',
        phone: '01000000001',
        openingBalance: 1000.0,
        allowNegative: false,
      );

      final snap = await db.getTreasurySnapshot();

      expect(snap.walletsTotal, closeTo(1000.0, 0.0001));
      expect(snap.drawerBalance, closeTo(0.0, 0.0001));
      expect(snap.fawryBalance, closeTo(0.0, 0.0001));
      expect(snap.availableLiquidityNow, closeTo(1000.0, 0.0001));
      expect(snap.realCapitalApproved, closeTo(1000.0, 0.0001));
      expect(snap.dailyProfit, closeTo(0.0, 0.0001));
      expect(snap.profitApprovedTotal, closeTo(0.0, 0.0001));
      expect(snap.claimsReceivableOpen, closeTo(0.0, 0.0001));
      expect(snap.claimsPayableOpen, closeTo(0.0, 0.0001));
    });
  });
}
