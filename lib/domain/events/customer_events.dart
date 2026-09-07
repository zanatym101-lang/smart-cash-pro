import 'package:meta/meta.dart';
import '../models/money.dart';
import '../models/customer_account.dart';

/// Base class for all customer-related accounting events.
@immutable
abstract class CustomerAccountingEvent {
  const CustomerAccountingEvent();
}

/// Emitted when a manual adjustment is added or subtracted from a customer's account.
@immutable
class CustomerAdjustmentCreatedEvent extends CustomerAccountingEvent {
  const CustomerAdjustmentCreatedEvent({
    required this.adjustmentId,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.timestamp,
    this.note,
  });

  final String adjustmentId;
  final String customerId;
  final CustomerAdjustmentType type;
  final Money amount;
  final DateTime timestamp;
  final String? note;
}

/// Emitted when an adjustment is allocated to one or more specific open items.
@immutable
class AdjustmentAllocatedEvent extends CustomerAccountingEvent {
  const AdjustmentAllocatedEvent({
    required this.allocationId,
    required this.adjustmentId,
    required this.linkedItemId,
    required this.allocatedAmount,
    required this.timestamp,
  });

  final String allocationId;
  final String adjustmentId;
  final String linkedItemId;
  final Money allocatedAmount;
  final DateTime timestamp;
}
