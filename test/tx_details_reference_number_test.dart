import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/utils/txn_reference.dart';

void main() {
  test('tx details reference number uses ZA prefix for screen display', () {
    expect(formatTxnReference(1), startsWith('ZA'));
    expect(formatTxnReference(1), 'ZA000001');
    expect(formatTxnReference(999999), 'ZA999999');
  });
}
