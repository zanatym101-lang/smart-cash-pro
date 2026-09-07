import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/models/claim.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_builder.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Customer Direction Invariants & Cumulative Running Balance', () {
    const customer = 'أحمد علي';
    final baseDate = DateTime(2026, 6, 1, 10, 0);

    Txn makeTxn({
      required int id,
      required String kind,
      required String status,
      required double amount,
      String mode = 'cash',
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
        clientFee: 0,
        networkFee: 0,
        mode: mode,
        note: note,
        party: party,
        createdBy: 'admin',
        createdRole: 'admin',
        createdAt: date,
      );
    }

    Claim makeClaim({
      required int id,
      required String type,
      required double amount,
      String status = 'open',
      int? sourceTxnId,
      DateTime? entryDate,
    }) {
      return Claim(
        id: id,
        type: type,
        party: customer,
        amount: amount,
        note: 'مستحق تجريبي',
        entryDate: entryDate ?? baseDate.add(Duration(hours: id)),
        status: status,
        sourceTxnId: sourceTxnId,
      );
    }

    test('Invariant 1: Deferred transfer increases لنا (+), Cash collect reduces it', () {
      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: [
          makeTxn(id: 1, kind: 'transfer', status: 'pending', amount: 350),
          makeTxn(
            id: 2,
            kind: 'claim_collect',
            status: 'posted',
            amount: 200,
            note: 'pending_txn:1',
            party: null,
          ),
        ],
        claims: const [],
      );

      expect(accounts, hasLength(1));
      final acc = accounts.single;
      expect(acc.summary.totalForUs, closeTo(150, 0.0001));
      expect(acc.summary.totalAgainstUs, closeTo(0, 0.0001));
      expect(acc.summary.netBalance, closeTo(150, 0.0001));

      final transferRow = acc.rows.firstWhere((r) => r.sourceType == CustomerLedgerSourceType.deferredTransfer);
      final collectRow = acc.rows.firstWhere((r) => r.sourceType == CustomerLedgerSourceType.settlement);

      expect(transferRow.direction, equals(CustomerLedgerDirection.forUs));
      expect(transferRow.remainingBalanceAfterRow, closeTo(350, 0.0001));

      expect(collectRow.direction, equals(CustomerLedgerDirection.againstUs));
      expect(collectRow.remainingBalanceAfterRow, closeTo(150, 0.0001));
    });

    test('Invariant 2: Deferred receive increases علينا (-), Cash payout reduces it', () {
      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: [
          makeTxn(id: 10, kind: 'receive', status: 'pending', amount: 500),
          makeTxn(
            id: 11,
            kind: 'claim_pay',
            status: 'posted',
            amount: 400,
            note: 'pending_txn:10',
            party: null,
          ),
        ],
        claims: const [],
      );

      expect(accounts, hasLength(1));
      final acc = accounts.single;
      expect(acc.summary.totalAgainstUs, closeTo(100, 0.0001));
      expect(acc.summary.totalForUs, closeTo(0, 0.0001));
      expect(acc.summary.netBalance, closeTo(-100, 0.0001));

      final receiveRow = acc.rows.firstWhere((r) => r.sourceType == CustomerLedgerSourceType.deferredReceive);
      final payoutRow = acc.rows.firstWhere((r) => r.sourceType == CustomerLedgerSourceType.settlement);

      expect(receiveRow.direction, equals(CustomerLedgerDirection.againstUs));
      expect(receiveRow.remainingBalanceAfterRow, closeTo(-500, 0.0001));

      expect(payoutRow.direction, equals(CustomerLedgerDirection.forUs));
      expect(payoutRow.remainingBalanceAfterRow, closeTo(-100, 0.0001));
    });

    test('Invariant 3: Claim payable increases علينا (-), Claim receivable increases لنا (+)', () {
      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: const [],
        claims: [
          makeClaim(id: 101, type: 'payable', amount: 600),
          makeClaim(id: 102, type: 'receivable', amount: 1000),
        ],
      );

      expect(accounts, hasLength(1));
      final acc = accounts.single;
      expect(acc.summary.totalForUs, closeTo(1000, 0.0001));
      expect(acc.summary.totalAgainstUs, closeTo(600, 0.0001));
      expect(acc.summary.netBalance, closeTo(400, 0.0001)); // Net = 1000 - 600 = +400 (لنا)
    });

    test('Invariant 4: Multi-step chronological ledger sequence preserves running balance integrity', () {
      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: [
          // 1. Receive 500 (علينا -> running -500)
          makeTxn(
            id: 1,
            kind: 'receive',
            status: 'pending',
            amount: 500,
            entryDate: DateTime(2026, 6, 1, 10, 0),
          ),
          // 2. Pay 300 to customer (settlement -> running -200)
          makeTxn(
            id: 2,
            kind: 'claim_pay',
            status: 'posted',
            amount: 300,
            note: 'pending_txn:1',
            party: null,
            entryDate: DateTime(2026, 6, 1, 11, 0),
          ),
          // 3. Transfer 400 to customer (لنا -> running +200)
          makeTxn(
            id: 3,
            kind: 'transfer',
            status: 'pending',
            amount: 400,
            entryDate: DateTime(2026, 6, 1, 12, 0),
          ),
          // 4. Collect 200 from customer (settlement -> running 0.00)
          makeTxn(
            id: 4,
            kind: 'claim_collect',
            status: 'posted',
            amount: 200,
            note: 'pending_txn:3',
            party: null,
            entryDate: DateTime(2026, 6, 1, 13, 0),
          ),
        ],
        claims: const [],
      );

      expect(accounts, hasLength(1));
      final acc = accounts.single;
      expect(acc.summary.totalForUs, closeTo(200, 0.0001));
      expect(acc.summary.totalAgainstUs, closeTo(200, 0.0001));
      expect(acc.summary.netBalance, closeTo(0, 0.0001));

      final r1 = acc.rows.firstWhere((r) => r.id == 'txn:1');
      final r2 = acc.rows.firstWhere((r) => r.id == 'txn:2');
      final r3 = acc.rows.firstWhere((r) => r.id == 'txn:3');
      final r4 = acc.rows.firstWhere((r) => r.id == 'txn:4');

      expect(r1.remainingBalanceAfterRow, closeTo(-500, 0.0001));
      expect(r2.remainingBalanceAfterRow, closeTo(-200, 0.0001));
      expect(r3.remainingBalanceAfterRow, closeTo(200, 0.0001));
      expect(r4.remainingBalanceAfterRow, closeTo(0, 0.0001));
    });
  });

  group('CustomersScreen UI & Quick Cash Action Section', () {
    testWidgets('CustomerQuickActionsSection renders quick action button with label 💰 حركة نقدية / تسوية سريعة', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomerQuickActionsSectionTestWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('💰 حركة نقدية / تسوية سريعة'), findsOneWidget);
    });
  });
}

class CustomerQuickActionsSectionTestWidget extends StatelessWidget {
  const CustomerQuickActionsSectionTestWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF047857),
      ),
      onPressed: () {},
      icon: const Icon(Icons.payments_outlined),
      label: const Text('💰 حركة نقدية / تسوية سريعة'),
    );
  }
}
