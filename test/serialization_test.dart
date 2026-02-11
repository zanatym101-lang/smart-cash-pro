import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/models/claim.dart';

void main() {
  test('Txn serialization round-trip', () {
    final txn = Txn(
      id: 7,
      kind: 'fawry_credit',
      status: 'posted',
      entryDate: DateTime.parse('2026-02-10T12:30:00Z'),
      walletFromId: 1,
      walletToId: 2,
      amount: 1000.0,
      clientFee: 10.0,
      networkFee: 0,
      mode: 'fawry',
      note: 'note',
      serviceName: 'Electricity',
      reference: '123456',
      party: 'Client A',
      createdBy: 'أدمن',
      createdRole: 'admin',
      createdAt: DateTime.parse('2026-02-10T12:00:00Z'),
    );

    final json = txn.toJson();
    final back = Txn.fromJson(json);

    expect(back.id, txn.id);
    expect(back.kind, txn.kind);
    expect(back.status, txn.status);
    expect(back.amount, txn.amount);
    expect(back.clientFee, txn.clientFee);
    expect(back.networkFee, txn.networkFee);
    expect(back.mode, txn.mode);
    expect(back.note, txn.note);
    expect(back.serviceName, txn.serviceName);
    expect(back.reference, txn.reference);
    expect(back.party, txn.party);
    expect(back.createdBy, txn.createdBy);
    expect(back.createdRole, txn.createdRole);
    expect(back.createdAt, txn.createdAt);
  });

  test('Claim serialization round-trip', () {
    final claim = Claim(
      id: 3,
      type: 'receivable',
      party: 'Client B',
      amount: 1010,
      note: 'fawry',
      entryDate: DateTime.parse('2026-02-10T10:00:00Z'),
      status: 'open',
      settledTxnId: null,
      settledDate: null,
      sourceTxnId: 9,
    );

    final json = claim.toJson();
    final back = Claim.fromJson(json);

    expect(back.id, claim.id);
    expect(back.type, claim.type);
    expect(back.party, claim.party);
    expect(back.amount, claim.amount);
    expect(back.note, claim.note);
    expect(back.status, claim.status);
    expect(back.settledTxnId, claim.settledTxnId);
    expect(back.sourceTxnId, claim.sourceTxnId);
  });
}
