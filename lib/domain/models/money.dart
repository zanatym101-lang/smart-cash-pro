import 'package:meta/meta.dart';

/// A value object representing an amount of money.
/// This strictly uses [int] representing the smallest currency unit (e.g., Piastres/Cents)
/// to avoid any floating-point (double) inaccuracies.
@immutable
class Money implements Comparable<Money> {
  const Money(this.inSmallestUnit);

  /// The amount in the smallest unit (e.g., Piastres/Cents).
  /// For example, 10.50 EGP is stored as 1050.
  final int inSmallestUnit;

  static const Money zero = Money(0);

  Money operator +(Money other) {
    return Money(inSmallestUnit + other.inSmallestUnit);
  }

  Money operator -(Money other) {
    return Money(inSmallestUnit - other.inSmallestUnit);
  }

  Money operator *(int multiplier) {
    return Money(inSmallestUnit * multiplier);
  }

  /// Helper to create Money from a double (only for legacy/migration purposes).
  /// Should be avoided in new business logic to prevent rounding errors.
  factory Money.fromDouble(double amount) {
    return Money((amount * 100).round());
  }

  /// Converts the money back to a double representation (e.g., 10.50)
  /// Useful for display purposes or legacy interoperability.
  double toDouble() {
    return inSmallestUnit / 100.0;
  }

  /// Formatted string representation (e.g., "10.50")
  String get formatted => toDouble().toStringAsFixed(2);

  /// Backwards compatibility getter, same as inSmallestUnit
  int get qirsh => inSmallestUnit;
  int get piastres => inSmallestUnit;

  /// Backwards compatibility factories
  factory Money.fromPiastres(int p) => Money(p);
  factory Money.fromQirsh(int q) => Money(q);

  bool get isZero => inSmallestUnit == 0;
  bool get isPositive => inSmallestUnit > 0;
  bool get isNegative => inSmallestUnit < 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          runtimeType == other.runtimeType &&
          inSmallestUnit == other.inSmallestUnit;

  @override
  int get hashCode => inSmallestUnit.hashCode;

  @override
  int compareTo(Money other) {
    return inSmallestUnit.compareTo(other.inSmallestUnit);
  }

  bool operator >(Money other) => inSmallestUnit > other.inSmallestUnit;
  bool operator <(Money other) => inSmallestUnit < other.inSmallestUnit;
  bool operator >=(Money other) => inSmallestUnit >= other.inSmallestUnit;
  bool operator <=(Money other) => inSmallestUnit <= other.inSmallestUnit;

  @override
  String toString() {
    return toDouble().toStringAsFixed(2);
  }
}
