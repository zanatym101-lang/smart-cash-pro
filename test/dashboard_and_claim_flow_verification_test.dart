import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart'
    as domain;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_claim_dashboard_flow_test_',
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

  group('Customer Claim Cash Flow (مستحق لنا)', () {
    test(
      'creating 100 EGP receivable claim reduces drawer by 100 and does NOT increase profit',
      () async {
        final db = AppDb.instance;

        // Seed drawer with 500 EGP
        await db.drawerDeposit(amount: 500, note: 'Seed drawer');
        var snap = await db.getTreasurySnapshot();
        expect(snap.drawerActualBalance, closeTo(500, 0.0001));
        expect(snap.dailyProfit, closeTo(0, 0.0001));
        expect(snap.profitApprovedTotal, closeTo(0, 0.0001));

        // Create outbound claim (مستحق لنا / Receivable) of 100 EGP
        final claimId = await db.addClaim(
          type: 'receivable',
          party: 'Ahmed Customer',
          amount: 100,
          note: 'Deferred customer debt',
        );

        snap = await db.getTreasurySnapshot();
        // Cash flowed OUT of cash drawer (-100 EGP)
        expect(snap.drawerActualBalance, closeTo(400, 0.0001));
        // Customer debt is recognized as open claim for us (+100 EGP)
        expect(snap.claimsReceivableOpen, closeTo(100, 0.0001));
        // No artificial profit recognition
        expect(snap.dailyProfit, closeTo(0, 0.0001));
        expect(snap.profitApprovedTotal, closeTo(0, 0.0001));

        // Invariant holds: Real Capital = Cash Drawer + Actual Wallets Total + Net Customers Debt
        expect(
          snap.realCapitalApproved,
          closeTo(
            snap.drawerActualBalance +
                snap.walletsActualTotal +
                snap.fawryActualBalance +
                snap.claimsNet,
            0.0001,
          ),
        );
        expect(snap.realCapitalApproved, closeTo(500, 0.0001));

        // Settle the debt (سداد مستحق لنا)
        await db.settleClaim(claimId: claimId, amount: 100);

        snap = await db.getTreasurySnapshot();
        // Cash enters drawer (+100 EGP -> back to 500 EGP)
        expect(snap.drawerActualBalance, closeTo(500, 0.0001));
        expect(snap.claimsReceivableOpen, closeTo(0, 0.0001));
        expect(snap.realCapitalApproved, closeTo(500, 0.0001));
      },
    );

    test(
      'Fawry credit deferred claim does not realize profit until customer settles',
      () async {
        final db = AppDb.instance;

        // Seed drawer first so fawry funding can take place
        await db.drawerDeposit(amount: 2000, note: 'Seed drawer');
        // Fund fawry from drawer
        await db.addFawryFundingFromDrawer(amount: 1000);
        var snap = await db.getTreasurySnapshot();
        expect(snap.dailyProfit, closeTo(0, 0.0001));

        // Create Fawry transaction with credit/claim: amount=100, fee=15
        await db.addFawry(
          serviceName: 'Bill Payment',
          amount: 100,
          fee: 15,
          collectionMethod: 'credit',
          party: 'Fawry Customer',
        );

        snap = await db.getTreasurySnapshot();
        // Claim is open: profit is NOT yet realized
        expect(snap.claimsReceivableOpen, closeTo(115, 0.0001));
        expect(snap.dailyProfit, closeTo(0, 0.0001));
        expect(snap.profitApprovedTotal, closeTo(0, 0.0001));

        // Retrieve open claim and settle it
        final claims = await db.listClaims(type: 'receivable', status: 'open');
        expect(claims.length, 1);
        final claim = claims.first;

        await db.settleClaim(claimId: claim.id, amount: 115);

        snap = await db.getTreasurySnapshot();
        // Claim is closed: fee is now realized on settlement
        expect(snap.claimsReceivableOpen, closeTo(0, 0.0001));
        expect(snap.dailyProfit, closeTo(15, 0.0001));
        expect(snap.profitApprovedTotal, closeTo(15, 0.0001));
      },
    );

    test('pure AccountingEngine verifies receivable claim cash flow and settlement', () {
      final engine = domain.AccountingEngine();
      final initialState = domain.AccountingEngineState(
        drawerBalance: 500,
        walletBalance: 1000,
      );

      // Open receivable claim of 100
      final openResult = engine.openClaim(
        state: initialState,
        claimId: 'claim-100',
        type: domain.ClaimType.receivable,
        amount: 100,
      );

      expect(openResult.newState.drawerBalance, 400);
      expect(openResult.newState.claims.length, 1);
      expect(openResult.newState.claims.first.remainingAmount, 100);

      // Settle receivable claim of 100
      final settleResult = engine.settleClaim(
        state: openResult.newState,
        claimId: 'claim-100',
        settlementId: 'settle-1',
        amount: 100,
      );

      expect(settleResult.newState.drawerBalance, 500);
      expect(settleResult.newState.claims.first.status, domain.ClaimStatus.closed);
    });
  });

  group('Dashboard Wallets Metric Alignment (Single Source of Truth)', () {
    test(
      'snap.walletsActualTotal matches Wallets Screen sum under all states',
      () async {
        final db = AppDb.instance;

        // Step 1: Empty state
        var snap = await db.getTreasurySnapshot();
        var wallets = await db.listWallets();
        var screenActualSum = 0.0;
        for (final w in wallets) {
          screenActualSum += await db.getWalletBalance(w.id);
        }
        expect(snap.walletsActualTotal, closeTo(screenActualSum, 0.0001));
        expect(snap.walletsActualTotal, 0.0);

        // Step 2: Add multiple wallets with opening balances
        final w1 = await db.addWallet(
          name: 'Vodafone 1',
          phone: '01011111111',
          openingBalance: 1500,
        );
        final w2 = await db.addWallet(
          name: 'Etisalat 1',
          phone: '01111111111',
          openingBalance: 2500,
        );
        final w3 = await db.addWallet(
          name: 'Orange 1',
          phone: '01211111111',
          openingBalance: 3000,
        );

        snap = await db.getTreasurySnapshot();
        wallets = await db.listWallets();
        screenActualSum = 0.0;
        for (final w in wallets) {
          screenActualSum += await db.getWalletBalance(w.id);
        }
        expect(snap.walletsActualTotal, closeTo(7000, 0.0001));
        expect(snap.walletsActualTotal, closeTo(screenActualSum, 0.0001));

        // Step 3: Perform wallet funding and transfers
        await db.addExternalFunding(walletId: w1, amount: 500, note: 'External topup');
        await db.addTransfer(
          walletId: w2,
          amount: 300,
          clientFee: 15,
          networkFee: 3,
          transferType: 'type1',
          party: 'Customer X',
        );
        await db.addTransfer(
          walletId: w3,
          amount: 200,
          clientFee: 10,
          networkFee: 2,
          transferType: 'type1',
          party: 'Customer Y',
        );

        snap = await db.getTreasurySnapshot();
        wallets = await db.listWallets();
        screenActualSum = 0.0;
        for (final w in wallets) {
          screenActualSum += await db.getWalletBalance(w.id);
        }
        expect(snap.walletsActualTotal, closeTo(screenActualSum, 0.0001));

        // Step 4: Verify invariant
        // Real Capital = Cash Drawer + Actual Wallets Total + (Fawry Float) + Net Customers Debt
        expect(
          snap.realCapitalApproved,
          closeTo(
            snap.drawerActualBalance +
                snap.walletsActualTotal +
                snap.fawryActualBalance +
                snap.claimsNet,
            0.0001,
          ),
        );

        // Step 5: Post reset verification
        await db.resetDatabase();
        snap = await db.getTreasurySnapshot();
        wallets = await db.listWallets();
        screenActualSum = 0.0;
        for (final w in wallets) {
          screenActualSum += await db.getWalletBalance(w.id);
        }
        expect(snap.walletsActualTotal, closeTo(screenActualSum, 0.0001));
        expect(
          snap.realCapitalApproved,
          closeTo(
            snap.drawerActualBalance +
                snap.walletsActualTotal +
                snap.fawryActualBalance +
                snap.claimsNet,
            0.0001,
          ),
        );
      },
    );
  });
}
