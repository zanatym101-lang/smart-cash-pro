import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/utils/txn_reference.dart';

void main() {
  test('reference number starts with ZA and is padded', () {
    expect(formatTxnReference(1), 'ZA000001');
    expect(formatTxnReference(15), 'ZA000015');
    expect(formatTxnReference(123), 'ZA000123');
  });

  test('reference number parses ZA format back to txn id', () {
    expect(txnIdFromReference('ZA000001'), 1);
    expect(txnIdFromReference('ZA000123'), 123);
    expect(txnIdFromReference(' ZA999999 '), 999999);
  });

  test('reference parser rejects invalid ZA values', () {
    expect(txnIdFromReference(''), isNull);
    expect(txnIdFromReference('123'), isNull);
    expect(txnIdFromReference('za000123'), isNull);
    expect(txnIdFromReference('ZA12A123'), isNull);
    expect(txnIdFromReference('ZA12345'), isNull);
  });
}
