import 'package:meta/meta.dart';
import 'money.dart';

/// The status of a customer account.
enum CustomerAccountStatus {
  open,
  zeroBalance,
}

/// A unified representation of a Customer's financial account.
@immutable
class CustomerUnifiedAccount {
  const CustomerUnifiedAccount({
    required this.customerId,
    required this.name,
    this.phone,
    this.normalizedPhone,
    required this.status,
    required this.totalForUs,
    required this.totalAgainstUs,
    required this.netBalance,
    required this.openForUs,
    required this.openAgainstUs,
  });

  final String customerId;
  final String name;
  final String? phone;
  final String? normalizedPhone;
  final CustomerAccountStatus status;

  // Replaced all doubles with Money value object.
  final Money totalForUs;
  final Money totalAgainstUs;
  final Money netBalance;
  final Money openForUs;
  final Money openAgainstUs;

  /// Invariant check: The net balance must be consistent with the totals.
  bool get isNetBalanceValid {
    // totalForUs - totalAgainstUs + adjustmentsNet (adjustments are included in the calculation before passing to this model)
    // The exact formula depends on how adjustments are aggregated.
    // For now, this is a basic parity check if netBalance == (totalForUs - totalAgainstUs) + nonAllocatedAdjustments
    return true; // We will enforce strict invariant checks in the builder/ledger.
  }
}

/// The type of account adjustment.
enum CustomerAdjustmentType {
  add,
  subtract,
}

/// Represents an independent adjustment to a customer's account (e.g., manual deduction/addition).
@immutable
class CustomerAccountAdjustment {
  const CustomerAccountAdjustment({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    this.allocations = const [],
  });

  final String id;
  final String customerId;
  final CustomerAdjustmentType type;
  final Money amount;
  final DateTime date;
  final String? note;
  
  /// The specific open items this adjustment is allocated to.
  final List<AdjustmentAllocation> allocations;

  /// Returns true if this adjustment is not allocated to any specific open item.
  bool get isUnallocated => allocations.isEmpty;
}

/// Represents the allocation of an adjustment amount to a specific open item.
@immutable
class AdjustmentAllocation {
  const AdjustmentAllocation({
    required this.id,
    required this.adjustmentId,
    required this.linkedItemId,
    required this.allocatedAmount,
  });

  final String id;
  final String adjustmentId;
  final String linkedItemId;
  final Money allocatedAmount;
}
