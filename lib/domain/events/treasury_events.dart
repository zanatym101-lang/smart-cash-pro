import 'package:meta/meta.dart';
import '../models/money.dart';
import '../models/treasury_ledger.dart';

/// Base class for all treasury-related accounting events.
@immutable
abstract class TreasuryAccountingEvent {
  const TreasuryAccountingEvent();
}

/// Emitted when a transaction is recorded against the treasury.
@immutable
class TreasuryTransactionRecordedEvent extends TreasuryAccountingEvent {
  const TreasuryTransactionRecordedEvent({
    required this.eventId,
    required this.type,
    required this.amount,
    required this.timestamp,
    required this.description,
    this.reference,
  });

  final String eventId;
  final TreasuryEventType type;
  final Money amount;
  final DateTime timestamp;
  final String description;
  final String? reference;
}
