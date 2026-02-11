enum TxStatus { pending, approved, rejected }
enum TxType { transfer, walletFunding, drawerFunding }
enum CommissionMode { cash, deductFromAmount }

class LedgerEntry {
  final String accountKey; // "wallet:<id>" or "drawer"
  final int deltaQirsh;
  final DateTime ts;
  final String txId;
  final Map<String, dynamic> meta;

  LedgerEntry({
    required this.accountKey,
    required this.deltaQirsh,
    required this.ts,
    required this.txId,
    this.meta = const {},
  });
}

class AccountingState {
  final Map<String, int> walletBalancesQirsh; // walletId -> qirsh
  int drawerBalanceQirsh;
  final List<LedgerEntry> ledger;
  final Map<String, TransactionRecord> transactions;

  AccountingState({
    required this.walletBalancesQirsh,
    required this.drawerBalanceQirsh,
    required this.ledger,
    required this.transactions,
  });

  int getWalletQirsh(String id) => walletBalancesQirsh[id] ?? 0;

  void applyEntry(LedgerEntry e) {
    if (e.accountKey == "drawer") {
      drawerBalanceQirsh += e.deltaQirsh; // drawer CAN be negative
      return;
    }

    if (e.accountKey.startsWith("wallet:")) {
      final wid = e.accountKey.split(":")[1];
      walletBalancesQirsh[wid] = (walletBalancesQirsh[wid] ?? 0) + e.deltaQirsh;
      return;
    }

    throw Exception("Unknown accountKey: ${e.accountKey}");
  }
}

class TransactionRecord {
  final String id;
  final TxType type;
  TxStatus status;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  DateTime? decidedAt;

  TransactionRecord({
    required this.id,
    required this.type,
    required this.status,
    required this.payload,
    required this.createdAt,
    this.decidedAt,
  });
}

abstract class TxSpec {
  TxType get type;

  /// Build ledger entries that would be applied on approval.
  List<LedgerEntry> buildEntries(String txId);

  /// Validate by simulating post-apply state:
  /// - Wallets are NOT allowed to go negative
  /// - Drawer is allowed to go negative
  void validateOrThrow(AccountingState state, String txId) {
    final entries = buildEntries(txId);

    final simWallets = Map<String, int>.from(state.walletBalancesQirsh);

    for (final e in entries) {
      if (e.accountKey.startsWith("wallet:")) {
        final wid = e.accountKey.split(":")[1];
        simWallets[wid] = (simWallets[wid] ?? 0) + e.deltaQirsh;
      }
    }

    for (final kv in simWallets.entries) {
      if (kv.value < 0) {
        throw Exception("Wallet ${kv.key} would go negative.");
      }
    }
  }
}

class AccountingEngine {
  final AccountingState state;

  AccountingEngine(this.state);

  /// Create a pending transaction (no balance impact).
  void createPending({
    required String txId,
    required TxSpec spec,
    required Map<String, dynamic> payload,
  }) {
    state.transactions[txId] = TransactionRecord(
      id: txId,
      type: spec.type,
      status: TxStatus.pending,
      payload: payload,
      createdAt: DateTime.now(),
    );
  }

  /// Approve a pending tx: validate then apply entries once.
  void approve({
    required String txId,
    required TxSpec spec,
  }) {
    final rec = state.transactions[txId];
    if (rec == null) throw Exception("Tx not found");
    if (rec.status != TxStatus.pending) throw Exception("Tx is not pending");

    spec.validateOrThrow(state, txId);

    final entries = spec.buildEntries(txId);
    for (final e in entries) {
      state.applyEntry(e);
      state.ledger.add(e);
    }

    rec.status = TxStatus.approved;
    rec.decidedAt = DateTime.now();
  }

  /// Reject a pending tx: no balance impact.
  void reject(String txId) {
    final rec = state.transactions[txId];
    if (rec == null) throw Exception("Tx not found");
    if (rec.status != TxStatus.pending) throw Exception("Tx is not pending");

    rec.status = TxStatus.rejected;
    rec.decidedAt = DateTime.now();
  }
}
