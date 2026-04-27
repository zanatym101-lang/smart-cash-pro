import 'engine.dart';

/// Transfer rules:
/// - `amountQirsh` here means actual transferred amount to receiver.
/// - Wallet ALWAYS pays: amount + nf
/// - Drawer increases:
///   - Type1 (cash commission): amount + cf
///   - Type2 (commission + network deducted): amount + cf + nf
class TransferTxSpec extends TxSpec {
  final String fromWalletId;
  final int amountQirsh;
  final int nfQirsh;
  final int cfQirsh;
  final CommissionMode mode;
  final bool affectDrawer;

  TransferTxSpec({
    required this.fromWalletId,
    required this.amountQirsh,
    required this.nfQirsh,
    required this.cfQirsh,
    required this.mode,
    this.affectDrawer = true,
  });

  @override
  TxType get type => TxType.transfer;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    final entries = <LedgerEntry>[];

    // Wallet: -(amount + nf)
    entries.add(
      LedgerEntry(
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
      ),
    );

    if (affectDrawer) {
      final drawerDelta = (mode == CommissionMode.cash)
          ? (amountQirsh + cfQirsh)
          : (amountQirsh + cfQirsh + nfQirsh);

      entries.add(
        LedgerEntry(
          accountKey: "drawer",
          deltaQirsh: drawerDelta,
          ts: now,
          txId: txId,
          meta: {"kind": "drawer_in_from_transfer", "mode": mode.name},
        ),
      );
    }

    return entries;
  }
}

/// Legacy Transfer Type2 behavior (kept for backward compatibility):
/// - Wallet: -storedSpend
/// - Drawer: +(storedSpend - nf)
class TransferLegacyType2TxSpec extends TxSpec {
  final String fromWalletId;
  final int spendQirsh;
  final int nfQirsh;
  final int cfQirsh;

  TransferLegacyType2TxSpec({
    required this.fromWalletId,
    required this.spendQirsh,
    required this.nfQirsh,
    required this.cfQirsh,
  });

  @override
  TxType get type => TxType.transfer;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    return [
      LedgerEntry(
        accountKey: "wallet:$fromWalletId",
        deltaQirsh: -spendQirsh,
        ts: now,
        txId: txId,
        meta: {
          "kind": "transfer_legacy_type2",
          "nfQirsh": nfQirsh,
          "cfQirsh": cfQirsh,
        },
      ),
      LedgerEntry(
        accountKey: "drawer",
        deltaQirsh: spendQirsh - nfQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "drawer_in_from_transfer_legacy_type2"},
      ),
    ];
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

  DrawerFundingTxSpec({required this.amountQirsh, this.note});

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
/// 1) cashCommission: wallet +amount, drawer -(amount - cf), profit recorded as cf
/// 2) deductFromAmount: wallet +amount, drawer -(amount - cf), profit recorded as cf
/// 3) electronic: wallet +(amount + cf), drawer 0, profit recorded as cf

/// Top-up fawry float from drawer:
/// - Drawer: -amount
/// - Fawry float: +amount
class FawryDrawerTopupTxSpec extends TxSpec {
  final int amountQirsh;
  final String? note;

  FawryDrawerTopupTxSpec({required this.amountQirsh, this.note});

  @override
  TxType get type => TxType.drawerFunding;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    return [
      LedgerEntry(
        accountKey: "drawer",
        deltaQirsh: -amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "fawry_drawer_topup_out", "note": note},
      ),
      LedgerEntry(
        accountKey: "fawry",
        deltaQirsh: amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "fawry_drawer_topup_in", "note": note},
      ),
    ];
  }
}

/// Fawry cash:
/// - Drawer receives from customer: +(amount + fee)
/// - Fawry float settles service base amount: -amount
class FawryCashTxSpec extends TxSpec {
  final int amountQirsh;
  final int feeQirsh;
  final String? note;

  FawryCashTxSpec({
    required this.amountQirsh,
    required this.feeQirsh,
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
        deltaQirsh: amountQirsh + feeQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "fawry_cash_collect", "note": note},
      ),
      LedgerEntry(
        accountKey: "fawry",
        deltaQirsh: -amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "fawry_cash_settle", "note": note},
      ),
    ];
  }
}

/// Fawry credit:
/// - Fawry float settles service base amount now: -amount
/// - Drawer is unaffected at execution time
class FawryCreditTxSpec extends TxSpec {
  final int amountQirsh;
  final String? note;

  FawryCreditTxSpec({required this.amountQirsh, this.note});

  @override
  TxType get type => TxType.drawerFunding;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    return [
      LedgerEntry(
        accountKey: "fawry",
        deltaQirsh: -amountQirsh,
        ts: now,
        txId: txId,
        meta: {"kind": "fawry_credit_settle", "note": note},
      ),
    ];
  }
}
enum ReceiveMode { cashCommission, deductFromAmount, electronic }

class ReceiveTxSpec extends TxSpec {
  final String walletId;
  final int amountQirsh;
  final int cfQirsh;
  final ReceiveMode mode;
  final bool affectDrawer;

  ReceiveTxSpec({
    required this.walletId,
    required this.amountQirsh,
    required this.cfQirsh,
    required this.mode,
    this.affectDrawer = true,
  });

  @override
  TxType get type => TxType.transfer;

  @override
  List<LedgerEntry> buildEntries(String txId) {
    final now = DateTime.now();
    final entries = <LedgerEntry>[];

    if (mode == ReceiveMode.cashCommission) {
      entries.add(
        LedgerEntry(
          accountKey: "wallet:$walletId",
          deltaQirsh: amountQirsh,
          ts: now,
          txId: txId,
          meta: {"kind": "receive_cash", "cfQirsh": cfQirsh},
        ),
      );
      if (affectDrawer) {
        entries.add(
          LedgerEntry(
            accountKey: "drawer",
            // Customer pays commission cash at receive time:
            // drawer net = +cf - amount = -(amount - cf)
            deltaQirsh: -(amountQirsh - cfQirsh),
            ts: now,
            txId: txId,
            meta: {"kind": "receive_cash", "cfQirsh": cfQirsh},
          ),
        );
      }
    } else if (mode == ReceiveMode.deductFromAmount) {
      entries.add(
        LedgerEntry(
          accountKey: "wallet:$walletId",
          deltaQirsh: amountQirsh,
          ts: now,
          txId: txId,
          meta: {"kind": "receive_deduct", "cfQirsh": cfQirsh},
        ),
      );
      if (affectDrawer) {
        entries.add(
          LedgerEntry(
            accountKey: "drawer",
            deltaQirsh: -(amountQirsh - cfQirsh),
            ts: now,
            txId: txId,
            meta: {"kind": "receive_deduct"},
          ),
        );
      }
    } else {
      entries.add(
        LedgerEntry(
          accountKey: "wallet:$walletId",
          deltaQirsh: amountQirsh + cfQirsh,
          ts: now,
          txId: txId,
          meta: {"kind": "receive_electronic", "cfQirsh": cfQirsh},
        ),
      );
    }

    return entries;
  }
}

