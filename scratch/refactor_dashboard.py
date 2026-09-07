import re
import os

def refactor_dashboard(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # We need to import the builders
    imports = """
import '../screens/wallet_ledger/wallet_ledger_builder.dart';
import '../screens/treasury_ledger/treasury_ledger_builder.dart';
import '../screens/customer_account/customer_account_builder.dart';
import '../data/app_db.dart' show AppDb; // already imported probably
"""
    if 'wallet_ledger_builder.dart' not in content:
        content = re.sub(r"import '../data/app_db.dart';", "import '../data/app_db.dart';\nimport 'wallet_ledger/wallet_ledger_builder.dart';\nimport 'treasury_ledger/treasury_ledger_builder.dart';\nimport 'customer_account/customer_account_builder.dart';", content)

    # Change _snap type from TreasurySnapshot? to something else?
    # Actually, if we just keep TreasurySnapshot as a data class in app_db.dart, we can just instantiate it here!
    # That means we don't need to change _snap type.
    
    # Let's replace the Future.wait call
    old_wait = """      final results = await Future.wait([
        AppDb.instance.getTreasurySnapshot(),
        AppDb.instance.getLicenseInfo(),
        AppDb.instance.getQuickActionsOrder(),
        AppDb.instance.getWalletLimitUsage(),
        AppDb.instance.getAppSettings(),
        AppDb.instance.listTxns(),
        AppDb.instance.listClaims(),
      ]);
      final s = results[0] as TreasurySnapshot;
      final license = results[1] as LicenseInfo;
      final order = (results[2] as List).map((e) => e.toString()).toList();
      final usage = results[3] as Map<int, WalletLimitUsage>;
      final settings = results[4] as AppSettings;
      final txns = results[5] as List<Txn>;
      final claims = results[6] as List<Claim>;"""

    new_wait = """      final results = await Future.wait([
        AppDb.instance.listWallets(),
        AppDb.instance.getLicenseInfo(),
        AppDb.instance.getQuickActionsOrder(),
        AppDb.instance.getWalletLimitUsage(),
        AppDb.instance.getAppSettings(),
        AppDb.instance.listTxns(),
        AppDb.instance.listClaims(),
      ]);
      final wallets = results[0] as List<Wallet>;
      final license = results[1] as LicenseInfo;
      final order = (results[2] as List).map((e) => e.toString()).toList();
      final usage = results[3] as Map<int, WalletLimitUsage>;
      final settings = results[4] as AppSettings;
      final txns = results[5] as List<Txn>;
      final claims = results[6] as List<Claim>;

      // Build TreasurySnapshot from Builders
      final walletAccounts = WalletLedgerBuilder.build(txns: txns, wallets: wallets);
      final walletsTotal = walletAccounts.fold<double>(0, (sum, w) => sum + w.currentBalance.asEgpDouble);
      
      final drawerEntries = AppDb.instance.ledgerEntries.where((e) => e.accountKey == 'drawer').toList();
      final txnsMap = {for (var t in txns) t.id.toString(): t};
      final treasuryAccount = TreasuryLedgerBuilder.build(
        drawerEntries: drawerEntries,
        txnsMap: txnsMap,
      );
      final drawerBalance = treasuryAccount.closingBalance.asEgpDouble;

      final customerAccounts = CustomerAccountBuilder.fromAppDbData(
        txns: txns,
        claims: claims,
      );
      double claimsReceivableOpen = 0;
      double claimsPayableOpen = 0;
      double pendingReceivableOpen = 0;
      double pendingPayableOpen = 0;

      for (final c in customerAccounts) {
         claimsReceivableOpen += c.summary.openClaimsForUs;
         claimsPayableOpen += c.summary.openClaimsAgainstUs;
         pendingReceivableOpen += c.summary.openDeferredForUs;
         pendingPayableOpen += c.summary.openDeferredAgainstUs;
      }

      final fawryBalance = AppDb.instance.actualTreasuryApproved - AppDb.instance.drawerActualBalance - AppDb.instance.walletsActualTotal; // roughly

      final pendingCount = txns.where((t) => t.status == 'pending').length;

      // Note: we just compute a dummy or reuse the properties that were available on AppDb
      final s = TreasurySnapshot(
        drawerBalance: drawerBalance,
        walletsTotal: walletsTotal,
        fawryBalance: AppDb.instance.fawryActualBalance,
        drawerActualBalance: AppDb.instance.drawerActualBalance,
        walletsActualTotal: walletsTotal,
        fawryActualBalance: AppDb.instance.fawryActualBalance,
        pendingCount: pendingCount,
        pendingInflow: AppDb.instance.pendingInflow,
        pendingOutflow: AppDb.instance.pendingOutflow,
        claimsReceivableOpen: claimsReceivableOpen,
        claimsPayableOpen: claimsPayableOpen,
        pendingReceivableOpen: pendingReceivableOpen,
        pendingPayableOpen: pendingPayableOpen,
        profitApprovedTotal: AppDb.instance.profitApprovedTotal,
        dailyProfit: AppDb.instance.dailyProfit,
        monthlyProfit: AppDb.instance.monthlyProfit,
      );
"""

    content = content.replace(old_wait, new_wait)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

refactor_dashboard('lib/screens/dashboard_screen.dart')
