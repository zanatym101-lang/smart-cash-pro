import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/accounting/money.dart';

void main() {
  test('Money conversion round-trip', () {
    final egp = 123.45;
    final qirsh = Money.fromEgpDouble(egp);
    final back = Money.toEgpDouble(qirsh);
    expect(qirsh, 12345);
    expect(back, closeTo(egp, 0.01));
  });

  test('Money format', () {
    expect(Money.formatEgp(0), '0.00');
    expect(Money.formatEgp(5), '0.05');
    expect(Money.formatEgp(150), '1.50');
  });
}
