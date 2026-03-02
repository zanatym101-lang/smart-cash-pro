import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/accounting/engine.dart';
import 'package:king_wallet_accounting/accounting/specs.dart';

AccountingEngine makeEngine({
  Map<String, int>? wallets,
  int drawer = 0,
  int fawry = 0,
}) {
  final state = AccountingState(
    walletBalancesQirsh: {...?wallets},
    drawerBalanceQirsh: drawer,
    fawryBalanceQirsh: fawry,
    ledger: [],
    transactions: {},
  );
  return AccountingEngine(state);
}

void main() {
  test('transfer cash mode affects wallet and drawer correctly', () {
    final engine = makeEngine(wallets: {'w1': 10000}, drawer: 0); // 100 EGP

    final spec = TransferTxSpec(
      fromWalletId: 'w1',
      amountQirsh: 2000, // 20 EGP
      nfQirsh: 100,      // 1 EGP network fee
      cfQirsh: 50,       // 0.5 EGP commission fee
      mode: CommissionMode.cash,
    );

    engine.createPending(txId: 'tx1', spec: spec, payload: {});
    engine.approve(txId: 'tx1', spec: spec);

    // Wallet pays amount + nf => -(2000 + 100) = -2100
    expect(engine.state.getWalletQirsh('w1'), 10000 - 2100);

    // Drawer increases amount + cf (cash mode) => +(2000 + 50) = 2050
    expect(engine.state.drawerBalanceQirsh, 2050);

    // Ledger should have 2 entries (wallet + drawer)
    expect(engine.state.ledger.length, 2);
  });

  test('cannot approve the same tx twice', () {
    final engine = makeEngine(wallets: {'w1': 10000});

    final spec = WalletFundingTxSpec(walletId: 'w1', amountQirsh: 500);

    engine.createPending(txId: 'tx2', spec: spec, payload: {});
    engine.approve(txId: 'tx2', spec: spec);

    expect(
      () => engine.approve(txId: 'tx2', spec: spec),
      throwsException,
    );
  });

  test('wallet never goes negative (approve should throw and not change balances)', () {
    final engine = makeEngine(wallets: {'w1': 1000}, drawer: 0); // 10 EGP

    final spec = TransferTxSpec(
      fromWalletId: 'w1',
      amountQirsh: 2000, // 20 EGP (أكبر من الرصيد)
      nfQirsh: 0,
      cfQirsh: 0,
      mode: CommissionMode.cash,
    );

    engine.createPending(txId: 'tx3', spec: spec, payload: {});

    expect(
      () => engine.approve(txId: 'tx3', spec: spec),
      throwsException,
    );

    // balances should remain unchanged
    expect(engine.state.getWalletQirsh('w1'), 1000);
    expect(engine.state.drawerBalanceQirsh, 0);
    expect(engine.state.ledger.length, 0);
  });
  test('state remains unchanged if approve throws', () {
  final engine = makeEngine(wallets: {'w1': 1000}, drawer: 500);

  final originalWallet = engine.state.getWalletQirsh('w1');
  final originalDrawer = engine.state.drawerBalanceQirsh;

  final spec = TransferTxSpec(
    fromWalletId: 'w1',
    amountQirsh: 5000, // أكبر من الرصيد
    nfQirsh: 0,
    cfQirsh: 0,
    mode: CommissionMode.cash,
  );

  engine.createPending(txId: 'tx4', spec: spec, payload: {});

  try {
    engine.approve(txId: 'tx4', spec: spec);
  } catch (_) {}

  expect(engine.state.getWalletQirsh('w1'), originalWallet);
  expect(engine.state.drawerBalanceQirsh, originalDrawer);
  expect(engine.state.ledger.isEmpty, true);
});
test('deductFromAmount example: gross 100, receiver 95, nf 1, wallet deducts 96', () {
  final engine = makeEngine(wallets: {'w1': 1000}, drawer: 0);

  final net = 95;
  final cf = 5;
  final nf = 1;

  final spec = TransferTxSpec(
    fromWalletId: 'w1',
    amountQirsh: net, // IMPORTANT: ده الصافي للمستلم
    nfQirsh: nf,
    cfQirsh: cf,
    mode: CommissionMode.deductFromAmount,
  );

  engine.createPending(txId: 'tx_demo', spec: spec, payload: {});
  engine.approve(txId: 'tx_demo', spec: spec);

  // wallet pays net + nf = 96
  expect(engine.state.getWalletQirsh('w1'), 1000 - (net + nf));

  // drawer gets net + cf + nf = 101
  expect(engine.state.drawerBalanceQirsh, net + cf + nf);
});
test('reject pending tx does not change balances and blocks approval', () {
  final engine = makeEngine(wallets: {'w1': 1000}, drawer: 500, fawry: 200);

  final originalWallet = engine.state.getWalletQirsh('w1');
  final originalDrawer = engine.state.drawerBalanceQirsh;
  final originalFawry = engine.state.fawryBalanceQirsh;

  final spec = TransferTxSpec(
    fromWalletId: 'w1',
    amountQirsh: 95,
    nfQirsh: 1,
    cfQirsh: 5,
    mode: CommissionMode.deductFromAmount,
  );

  engine.createPending(txId: 'tx_cancel', spec: spec, payload: {});

  // ✅ Cancel / Reject
  engine.reject('tx_cancel');

  // ✅ No balances changed
  expect(engine.state.getWalletQirsh('w1'), originalWallet);
  expect(engine.state.drawerBalanceQirsh, originalDrawer);
  expect(engine.state.fawryBalanceQirsh, originalFawry);

  // ✅ No ledger entries added
  expect(engine.state.ledger.isEmpty, true);

  // ✅ Status updated
  expect(engine.state.transactions['tx_cancel']!.status, TxStatus.rejected);

  // ✅ Approving after reject should fail (not pending anymore)
  expect(
    () => engine.approve(txId: 'tx_cancel', spec: spec),
    throwsException,
  );
});
test('cannot reject an approved tx (approve then reject should fail)', () {
  final engine = makeEngine(wallets: {'w1': 1000}, drawer: 0);

  final spec = TransferTxSpec(
    fromWalletId: 'w1',
    amountQirsh: 95,
    nfQirsh: 1,
    cfQirsh: 5,
    mode: CommissionMode.deductFromAmount,
  );

  engine.createPending(txId: 'tx_ar', spec: spec, payload: {});
  engine.approve(txId: 'tx_ar', spec: spec);

  // Reject after approve should fail
  expect(() => engine.reject('tx_ar'), throwsException);
});

}
