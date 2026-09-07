import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/accounting/specs.dart';
import 'package:king_wallet_accounting/config/app_env.dart';

void main() {
  group('Field Fixes and Licensing QA Invariant Tests', () {
    test('TransferLegacyType2TxSpec drawer intake matches customer cash intake (spendQirsh + cfQirsh)', () {
      final spec = TransferLegacyType2TxSpec(
        fromWalletId: '1',
        spendQirsh: 10000, // 100.00 EGP (e.g. 98 amount + 2 network fee)
        cfQirsh: 500,     // 5.00 EGP client fee
        nfQirsh: 200,     // 2.00 EGP network fee
      );

      final entries = spec.buildEntries('tx-101');
      final drawerEntry = entries.firstWhere((e) => e.accountKey == 'drawer');
      final walletEntry = entries.firstWhere((e) => e.accountKey == 'wallet:1');

      // Customer hands shop: spendQirsh + cfQirsh = 105.00 EGP (10500 qirsh)
      expect(drawerEntry.deltaQirsh, equals(10500));
      // Wallet deduction = spendQirsh = -100.00 EGP (-10000 qirsh)
      expect(walletEntry.deltaQirsh, equals(-10000));
    });

    test('AppEnv client release and flavor detection', () {
      expect(isClientRelease, isA<bool>());
      expect(isClientFlavor, isA<bool>());
    });
  });
}
