import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/screens/ledger_screen.dart';

void main() {
  final txn = Txn(
    id: 123,
    kind: 'transfer',
    status: 'posted',
    entryDate: DateTime(2026, 3, 20, 12),
    amount: 100,
    clientFee: 0,
    networkFee: 0,
    mode: 'type1',
    createdBy: 'tester',
    createdRole: 'admin',
    createdAt: DateTime(2026, 3, 20, 12),
  );

  test('ledger search matches txn id and ZA reference', () {
    expect(matchesLedgerTxnSearch(txn, '123'), isTrue);
    expect(matchesLedgerTxnSearch(txn, 'ZA000123'), isTrue);
    expect(matchesLedgerTxnSearch(txn, ' ZA000123 '), isTrue);
  });

  test('ledger search rejects invalid or different references', () {
    expect(matchesLedgerTxnSearch(txn, 'ZA000124'), isFalse);
    expect(matchesLedgerTxnSearch(txn, 'ZA12A123'), isFalse);
    expect(matchesLedgerTxnSearch(txn, 'note'), isFalse);
  });

  test('ledger empty state message is clearer during search', () {
    expect(
      ledgerEmptyStateMessage('ZA000999'),
      'لا توجد عملية مطابقة لرقم العملية أو مرجع ZA.',
    );
    expect(ledgerEmptyStateMessage(''), 'لا توجد عمليات حسب الفلاتر الحالية');
  });
  test('ZA search still respects period type and status filters', () {
    final now = DateTime(2026, 3, 20, 18);

    expect(
      matchesLedgerTxnFilters(
        txn: txn,
        period: 'today',
        type: 'transfer',
        status: 'posted',
        query: 'ZA000123',
        now: now,
      ),
      isTrue,
    );

    expect(
      matchesLedgerTxnFilters(
        txn: txn,
        period: 'today',
        type: 'receive',
        status: 'posted',
        query: 'ZA000123',
        now: now,
      ),
      isFalse,
    );

    expect(
      matchesLedgerTxnFilters(
        txn: txn,
        period: 'today',
        type: 'transfer',
        status: 'pending',
        query: 'ZA000123',
        now: now,
      ),
      isFalse,
    );

    expect(
      matchesLedgerTxnFilters(
        txn: txn.copyWith(entryDate: DateTime(2026, 2, 20, 12)),
        period: 'today',
        type: 'transfer',
        status: 'posted',
        query: 'ZA000123',
        now: now,
      ),
      isFalse,
    );
  });
}
