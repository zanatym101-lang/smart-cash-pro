import 'package:meta/meta.dart';
import 'money.dart';

/// Represents the summary account for the Treasury.
@immutable
class TreasuryAccount {
  const TreasuryAccount({
    required this.openingBalance,
    required this.totalIn,
    required this.totalOut,
    required this.expenses,
    required this.adjustments,
    required this.closingBalance,
    required this.rows,
  });

  final Money openingBalance;
  final Money totalIn;
  final Money totalOut;
  final Money expenses;
  final Money adjustments;
  final Money closingBalance;
  final List<TreasuryLedgerRow> rows;
}

/// The type of treasury event.
enum TreasuryEventType {
  cashReceived,
  cashTransferred,
  expense,
  funding,
  withdrawal,
  settlement,
  adjustment,
}

/// Represents a single row in the Treasury Ledger.
@immutable
class TreasuryLedgerRow {
  const TreasuryLedgerRow({
    required this.id,
    required this.date,
    required this.eventId,
    required this.eventType,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    this.reference,
  });

  final String id;
  final DateTime date;
  final String eventId;
  final TreasuryEventType eventType;
  
  /// The amount (positive for incoming, negative for outgoing).
  final Money amount;
  
  /// Running balance after this row.
  final Money balanceAfter;
  
  final String description;
  final String? reference;
}
