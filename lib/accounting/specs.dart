import 'engine.dart';

/// Transfer rules (fixed):
/// - Wallet ALWAYS pays (amount + nf)
/// - Drawer increases:
///   - Type1 (cash commission): amount + cf
///   - Type2 (commission deducted): amount
class TransferTxSpec extends TxSpec {
  final String fromWalletId;
  final int amountQirsh;
  final int nfQirsh;
  final int cfQirsh;
  final CommissionMode mode;

  TransferTxSpec({
    required this.fromWalletId,
    required this.amountQirsh,
    required this.nfQirsh,
    required this.cfQirsh,
    required this.mode,
  });

  @override
  TxType get type => TxType.transfer;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    final entries = <LedgerEntry>[];

    // Wallet: -(amount + nf)
    entries.add(LedgerEntry(
      accountKey: "wallet:$fromWalletId",
      deltaQirsh: -(amountQirsh + nfQirsh),
      ts: now,
      txId: txId,
      meta: {
        "kind": "transfer",
        "amountQirsh": amountQirsh,
        "nfQirsh": nfQirsh,
        "cfQirsh": cfQirsh,
        "mode": mode.name,
      },
    ));

    // Drawer:
    final drawerDelta = (mode == CommissionMode.cash)
        ? (amountQirsh + cfQirsh)
        : amountQirsh;

    entries.add(LedgerEntry(
      accountKey: "drawer",
      deltaQirsh: drawerDelta,
      ts: now,
      txId: txId,
      meta: {"kind": "drawer_in_from_transfer", "mode": mode.name},
    ));

    return entries;
  }
}

/// External funding to wallet:
/// - Wallet: +amount
/// - Drawer: no effect
class WalletFundingTxSpec extends TxSpec {
  final String walletId;
  final int amountQirsh;
  final String? note;

  WalletFundingTxSpec({
    required this.walletId,
    required this.amountQirsh,
    this.note,
  });

  @override
  TxType get type => TxType.walletFunding;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    return [
      LedgerEntry(
        accountKey: "wallet:$walletId",
        deltaQirsh: amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "wallet_external_funding", "note": note},
      ),
    ];
  }
}

/// External funding to drawer:
/// - Drawer: +amount (can be negative overall, but funding is positive delta)
class DrawerFundingTxSpec extends TxSpec {
  final int amountQirsh;
  final String? note;

  DrawerFundingTxSpec({
    required this.amountQirsh,
    this.note,
  });

  @override
  TxType get type => TxType.drawerFunding;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    return [
      LedgerEntry(
        accountKey: "drawer",
        deltaQirsh: amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "drawer_external_funding", "note": note},
      ),
    ];
  }
}


/// Receive (استلام) operations - 3 modes:
/// 1) cashCommission: wallet +amount, drawer -amount, profit recorded as cf
/// 2) deductFromAmount: wallet +amount, drawer -(amount - cf), profit recorded as cf
/// 3) electronic: wallet +(amount + cf), drawer 0, profit recorded as cf
enum ReceiveMode { cashCommission, deductFromAmount, electronic }

class ReceiveTxSpec extends TxSpec {
  final String walletId;
  final int amountQirsh;
  final int cfQirsh;
  final ReceiveMode mode;

  ReceiveTxSpec({
    required this.walletId,
    required this.amountQirsh,
    required this.cfQirsh,
    required this.mode,
  });

  @override
  TxType get type => TxType.transfer;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    final entries = <LedgerEntry>[];

    if (mode == ReceiveMode.cashCommission) {
      entries.add(LedgerEntry(
        accountKey: "wallet:$walletId",
        deltaQirsh: amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "receive_cash", "cfQirsh": cfQirsh},
      ));
      entries.add(LedgerEntry(
        accountKey: "drawer",
        deltaQirsh: -amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "receive_cash"},
      ));
    } else if (mode == ReceiveMode.deductFromAmount) {
      entries.add(LedgerEntry(
        accountKey: "wallet:$walletId",
        deltaQirsh: amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "receive_deduct", "cfQirsh": cfQirsh},
      ));
      entries.add(LedgerEntry(
        accountKey: "drawer",
        deltaQirsh: -(amountQirsh - cfQirsh),
        ts: now,
        txId: txId,
        meta: {"kind": "receive_deduct"},
      ));
    } else {
      entries.add(LedgerEntry(
        accountKey: "wallet:$walletId",
        deltaQirsh: amountQirsh + cfQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "receive_electronic", "cfQirsh": cfQirsh},
      ));
    }

    return entries;
  }
}

