import 'package:meta/meta.dart';
import 'money.dart';

/// Represents a unified Wallet Account containing net balances and totals based on ledger events.
@immutable
class WalletAccount {
  const WalletAccount({
    required this.walletId,
    required this.walletName,
    required this.walletNumber,
    required this.currentBalance,
    required this.totalReceived,
    required this.totalTransferred,
    required this.totalFees,
    required this.netMovement,
    required this.rows,
  });

  final String walletId;
  final String walletName;
  final String walletNumber;
  
  // Strict Money objects instead of double.
  final Money currentBalance;
  final Money totalReceived;
  final Money totalTransferred;
  final Money totalFees;
  final Money netMovement;

  final List<WalletLedgerRow> rows;
}

/// The type of transaction in the wallet ledger.
enum WalletTransactionType {
  transferOut,
  receiveIn,
  feeDeduction,
  adjustment,
}

/// Represents a single row in the Wallet Ledger.
@immutable
class WalletLedgerRow {
  const WalletLedgerRow({
    required this.id,
    required this.date,
    required this.transactionId,
    required this.transactionType,
    required this.amount,
    required this.fee,
    required this.balanceAfter,
    this.customerId,
    this.reference,
  });

  final String id;
  final DateTime date;
  final String transactionId;
  final WalletTransactionType transactionType;
  
  /// The amount moved in or out.
  final Money amount;
  
  /// The fee associated with the transaction (if any).
  final Money fee;
  
  /// The running balance of the wallet after this transaction.
  final Money balanceAfter;
  
  final String? customerId;
  final String? reference;
}
