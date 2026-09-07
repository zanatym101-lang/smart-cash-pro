import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/models/claim.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_builder.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_models.dart';

void main() {
  const customer = 'Customer Account';
  const phone = '01012345678';
  final baseDate = DateTime(2026, 5, 6, 10);

  Txn txn({
    required int id,
    required String kind,
    required String status,
    required double amount,
    String mode = 'type1',
    double clientFee = 0,
    double networkFee = 0,
    String? note,
    String? party = customer,
    DateTime? entryDate,
  }) {
    final date = entryDate ?? baseDate.add(Duration(minutes: id));
    return Txn(
      id: id,
      kind: kind,
      status: status,
      entryDate: date,
      amount: amount,
      clientFee: clientFee,
      networkFee: networkFee,
      mode: mode,
      note: note ?? phone,
      party: party,
      createdBy: 'test',
      createdRole: 'admin',
      createdAt: date,
    );
  }

  Claim claim({
    required int id,
    required String type,
    required double amount,
    String status = 'open',
    int? sourceTxnId,
  }) {
    return Claim(
      id: id,
      type: type,
      party: customer,
      amount: amount,
      note: phone,
      entryDate: baseDate.add(Duration(hours: id)),
      status: status,
      sourceTxnId: sourceTxnId,
    );
  }

  CustomerAccount singleAccount({
    List<Txn> txns = const [],
    List<Claim> claims = const [],
  }) {
    final accounts = CustomerAccountBuilder.fromAppDbData(
      txns: txns,
      claims: claims,
    );
    expect(accounts, hasLength(1));
    return accounts.single;
  }

  test('deferred transfer 100 leaves totalForUs 100 before collection', () {
    final account = singleAccount(
      txns: [txn(id: 1, kind: 'transfer', status: 'pending', amount: 100)],
    );

    expect(account.summary.totalForUs, closeTo(100, 0.0001));
    expect(account.summary.totalAgainstUs, closeTo(0, 0.0001));
    expect(account.summary.openDeferredForUs, closeTo(100, 0.0001));
  });

  test(
    'deferred transfer 100 plus collect 50 keeps history and remaining 50',
    () {
      final account = singleAccount(
        txns: [
          txn(id: 1, kind: 'transfer', status: 'pending', amount: 100),
          txn(
            id: 2,
            kind: 'claim_collect',
            status: 'posted',
            amount: 50,
            note: 'pending_txn:1',
            party: null,
          ),
        ],
      );

      expect(account.summary.totalForUs, closeTo(50, 0.0001));
      expect(account.rows.map((row) => row.amount), containsAll([100, 50]));
      expect(account.rows.any((row) => row.title == 'تحصيل'), isTrue);
    },
  );

  test(
    'deferred transfer 100 plus collect 50 plus full collect closes balance',
    () {
      final account = singleAccount(
        txns: [
          txn(id: 1, kind: 'transfer', status: 'posted', amount: 100),
          txn(
            id: 2,
            kind: 'claim_collect',
            status: 'posted',
            amount: 50,
            note: 'pending_txn:1',
            party: null,
          ),
          txn(
            id: 3,
            kind: 'claim_collect',
            status: 'posted',
            amount: 50,
            note: 'pending_txn:1',
            party: null,
          ),
        ],
      );

      expect(account.summary.totalForUs, closeTo(0, 0.0001));
      expect(account.summary.archived, isTrue);
      expect(account.rows, hasLength(3));
      expect(
        account.rows.where(
          (row) => row.sourceType == CustomerLedgerSourceType.settlement,
        ),
        hasLength(2),
      );
    },
  );

  test('deferred receive 100 leaves totalAgainstUs 100', () {
    final account = singleAccount(
      txns: [
        txn(
          id: 1,
          kind: 'receive',
          status: 'pending',
          amount: 100,
          mode: 'cash',
        ),
      ],
    );

    expect(account.summary.totalAgainstUs, closeTo(100, 0.0001));
    expect(account.summary.openDeferredAgainstUs, closeTo(100, 0.0001));
  });

  test('deferred receive 100 plus pay 100 closes totalAgainstUs', () {
    final account = singleAccount(
      txns: [
        txn(
          id: 1,
          kind: 'receive',
          status: 'posted',
          amount: 100,
          mode: 'cash',
        ),
        txn(
          id: 2,
          kind: 'claim_pay',
          status: 'posted',
          amount: 100,
          note: 'pending_txn:1',
          party: null,
        ),
      ],
    );

    expect(account.summary.totalAgainstUs, closeTo(0, 0.0001));
    expect(account.rows, hasLength(2));
  });

  test('claim receivable 200 leaves totalForUs 200', () {
    final account = singleAccount(
      claims: [claim(id: 1, type: 'receivable', amount: 200)],
    );

    expect(account.summary.totalForUs, closeTo(200, 0.0001));
    expect(account.summary.openClaimsForUs, closeTo(200, 0.0001));
  });

  test('claim payable 150 leaves totalAgainstUs 150', () {
    final account = singleAccount(
      claims: [claim(id: 1, type: 'payable', amount: 150)],
    );

    expect(account.summary.totalAgainstUs, closeTo(150, 0.0001));
    expect(account.summary.openClaimsAgainstUs, closeTo(150, 0.0001));
  });

  test('mixed customer netBalance is positive forUs', () {
    final account = singleAccount(
      claims: [
        claim(id: 1, type: 'receivable', amount: 300),
        claim(id: 2, type: 'payable', amount: 100),
      ],
    );

    expect(account.summary.totalForUs, closeTo(300, 0.0001));
    expect(account.summary.totalAgainstUs, closeTo(100, 0.0001));
    expect(account.summary.netBalance, closeTo(200, 0.0001));
  });

  test('archived zero-balance customer keeps closed history visible', () {
    final account = singleAccount(
      txns: [
        txn(
          id: 11,
          kind: 'claim_collect',
          status: 'posted',
          amount: 200,
          note: 'claim_id:1',
          party: null,
        ),
      ],
      claims: [claim(id: 1, type: 'receivable', amount: 200, status: 'closed')],
    );

    expect(account.summary.totalForUs, closeTo(0, 0.0001));
    expect(account.summary.archived, isTrue);
    expect(account.rows, hasLength(2));
    expect(
      account.rows.any((row) => row.status == CustomerLedgerRowStatus.closed),
      isTrue,
    );
  });

  test('offset settlement / account closure is clearly labeled with distinct title and details', () {
    final account = singleAccount(
      txns: [
        txn(
          id: 10,
          kind: 'transfer',
          status: 'posted',
          amount: 500,
        ),
        txn(
          id: 11,
          kind: 'claim_collect',
          status: 'posted',
          amount: 500,
          note: 'pending_txn:10 🔄 مقاصة تسوية / إغلاق حساب (تسوية داخلية بدون حركة نقدية في الخزينة)',
          party: null,
        ),
      ],
    );

    expect(account.summary.totalForUs, closeTo(0, 0.0001));
    expect(account.summary.archived, isTrue);
    final settlementRow = account.rows.firstWhere((r) => r.sourceType == CustomerLedgerSourceType.settlement);
    expect(settlementRow.title, equals('🔄 مقاصة تسوية / إغلاق حساب'));
    expect(settlementRow.description, contains('مقاصة تسوية'));
    expect(settlementRow.remainingBalanceAfterRow, closeTo(0, 0.0001));
  });

  test('deferred receive 500 followed by cash payout 400 leaves remaining balance 100 againstUs (NOT 895)', () {
    final account = singleAccount(
      txns: [
        txn(
          id: 1,
          kind: 'receive',
          status: 'pending',
          amount: 500,
          mode: 'cash',
          entryDate: DateTime(2026, 5, 1, 10, 0),
        ),
        txn(
          id: 2,
          kind: 'claim_pay',
          status: 'posted',
          amount: 400,
          note: 'pending_txn:1',
          party: null,
          entryDate: DateTime(2026, 5, 1, 11, 0),
        ),
      ],
    );

    expect(account.summary.totalAgainstUs, closeTo(100, 0.0001));
    expect(account.summary.totalForUs, closeTo(0, 0.0001));
    expect(account.summary.netBalance, closeTo(-100, 0.0001));

    // Chronological order verification of running balance
    final receiveRow = account.rows.firstWhere((r) => r.sourceType == CustomerLedgerSourceType.deferredReceive);
    final payoutRow = account.rows.firstWhere((r) => r.sourceType == CustomerLedgerSourceType.settlement);

    // After receive 500 -> net balance is -500 (500 علينا)
    expect(receiveRow.remainingBalanceAfterRow, closeTo(-500, 0.0001));
    // After cash payout 400 -> net balance is -100 (100 علينا)
    expect(payoutRow.remainingBalanceAfterRow, closeTo(-100, 0.0001));
  });

  test('deferred receive 500 followed by payout 400 then payout 100 reaches zero balance', () {
    final account = singleAccount(
      txns: [
        txn(
          id: 1,
          kind: 'receive',
          status: 'posted',
          amount: 500,
          mode: 'cash',
          entryDate: DateTime(2026, 5, 1, 10, 0),
        ),
        txn(
          id: 2,
          kind: 'claim_pay',
          status: 'posted',
          amount: 400,
          note: 'pending_txn:1',
          party: null,
          entryDate: DateTime(2026, 5, 1, 11, 0),
        ),
        txn(
          id: 3,
          kind: 'claim_pay',
          status: 'posted',
          amount: 100,
          note: 'pending_txn:1',
          party: null,
          entryDate: DateTime(2026, 5, 1, 12, 0),
        ),
      ],
    );

    expect(account.summary.netBalance, closeTo(0, 0.0001));
    expect(account.summary.archived, isTrue);

    final finalPayoutRow = account.rows.firstWhere((r) => r.id == 'txn:3');
    expect(finalPayoutRow.remainingBalanceAfterRow, closeTo(0, 0.0001));
  });

  test('claim payable reduces net balance towards علينا and claim settlement shifts it back', () {
    final account = singleAccount(
      claims: [
        claim(
          id: 10,
          type: 'payable',
          amount: 300,
          status: 'open',
        ),
      ],
      txns: [
        txn(
          id: 20,
          kind: 'claim_pay',
          status: 'posted',
          amount: 200,
          note: 'claim_id:10',
          party: null,
          entryDate: baseDate.add(const Duration(hours: 11)),
        ),
      ],
    );

    // Initial claim payable was 300 + 200 settled = 500 original, or 300 open remaining + 200 settled
    expect(account.summary.totalAgainstUs, closeTo(300, 0.0001));
    expect(account.summary.totalForUs, closeTo(0, 0.0001));
    expect(account.summary.netBalance, closeTo(-300, 0.0001));
  });
}
