import '../../models/transaction.dart';
import '../../models/wallet.dart';
import '../../domain/models/money.dart';
import '../../domain/models/wallet_ledger.dart';

class WalletLedgerBuilder {
  static List<WalletAccount> build({
    required List<Txn> txns,
    required List<Wallet> wallets,
  }) {
    final Map<int, Wallet> walletById = {
      for (final w in wallets) w.id: w,
    };

    final Map<int, List<WalletLedgerRow>> rowsByWalletId = {
      for (final w in wallets) w.id: [],
    };

    for (final txn in txns) {
      if (txn.status == 'rolled_back' ||
          txn.status == 'canceled' ||
          txn.status == 'reversed' ||
          txn.isReversed ||
          txn.status == 'reverse_entry') {
        continue;
      }

      // Wallet From -> Transfer Out
      if (txn.walletFromId != null && walletById.containsKey(txn.walletFromId)) {
        final wId = txn.walletFromId!;
        final spend = txn.amount;
        final fee = txn.networkFee;
        final principal = (spend - fee).clamp(0, 1e18).toDouble();

        rowsByWalletId[wId]!.add(
          WalletLedgerRow(
            id: 'out-${txn.id}',
            date: txn.entryDate,
            transactionId: txn.id.toString(),
            transactionType: WalletTransactionType.transferOut,
            amount: Money.fromDouble(-principal),
            fee: Money.fromDouble(-fee),
            balanceAfter: Money.zero, // Will be computed after sorting
            customerId: txn.party,
            reference: txn.reference,
          ),
        );
      }

      // Wallet To -> Receive In or Fund
      if (txn.walletToId != null && walletById.containsKey(txn.walletToId)) {
        final wId = txn.walletToId!;
        final amount = txn.amount;
        
        WalletTransactionType type = WalletTransactionType.receiveIn;
        if (txn.kind == 'wallet_fund') {
          // Funding is a deposit
        }

        rowsByWalletId[wId]!.add(
          WalletLedgerRow(
            id: 'in-${txn.id}',
            date: txn.entryDate,
            transactionId: txn.id.toString(),
            transactionType: type,
            amount: Money.fromDouble(amount),
            fee: Money.zero,
            balanceAfter: Money.zero, // Computed later
            customerId: txn.party,
            reference: txn.reference,
          ),
        );
      }
    }

    final accounts = <WalletAccount>[];

    for (final wallet in wallets) {
      final rows = rowsByWalletId[wallet.id]!;
      // Sort older first to calculate running balance
      rows.sort((a, b) {
        final date = a.date.compareTo(b.date);
        if (date != 0) return date;
        return a.transactionId.compareTo(b.transactionId);
      });

      var currentBalance = 0.0;
      var totalReceived = 0.0;
      var totalTransferred = 0.0;
      var totalFees = 0.0;

      final updatedRows = <WalletLedgerRow>[];

      for (final row in rows) {
        final amount = row.amount.toDouble();
        final fee = row.fee.toDouble();
        
        if (amount > 0) {
          totalReceived += amount;
        } else if (amount < 0) {
          totalTransferred += amount.abs();
        }
        totalFees += fee.abs();

        currentBalance += (amount + fee);

        updatedRows.add(
          WalletLedgerRow(
            id: row.id,
            date: row.date,
            transactionId: row.transactionId,
            transactionType: row.transactionType,
            amount: row.amount,
            fee: row.fee,
            balanceAfter: Money.fromDouble(currentBalance),
            customerId: row.customerId,
            reference: row.reference,
          ),
        );
      }

      // Reverse so newest is on top for UI
      updatedRows.reversed.toList();

      accounts.add(
        WalletAccount(
          walletId: wallet.id.toString(),
          walletName: wallet.name,
          walletNumber: wallet.phone,
          currentBalance: Money.fromDouble(currentBalance),
          totalReceived: Money.fromDouble(totalReceived),
          totalTransferred: Money.fromDouble(totalTransferred),
          totalFees: Money.fromDouble(totalFees),
          netMovement: Money.fromDouble(totalReceived - (totalTransferred + totalFees)),
          rows: updatedRows,
        ),
      );
    }

    return accounts;
  }
}
