class Claim {
  final int id;
  final String type; // receivable | payable
  final String party;
  final double amount;
  final String? note;
  final DateTime entryDate;
  final String status; // open | closed
  final int? settledTxnId;
  final DateTime? settledDate;
  final int? sourceTxnId; // linked txn (e.g., fawry_credit)

  const Claim({
    required this.id,
    required this.type,
    required this.party,
    required this.amount,
    this.note,
    required this.entryDate,
    required this.status,
    this.settledTxnId,
    this.settledDate,
    this.sourceTxnId,
  });

  Claim copyWith({
    int? id,
    String? type,
    String? party,
    double? amount,
    String? note,
    DateTime? entryDate,
    String? status,
    int? settledTxnId,
    DateTime? settledDate,
    int? sourceTxnId,
  }) {
    return Claim(
      id: id ?? this.id,
      type: type ?? this.type,
      party: party ?? this.party,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      entryDate: entryDate ?? this.entryDate,
      status: status ?? this.status,
      settledTxnId: settledTxnId ?? this.settledTxnId,
      settledDate: settledDate ?? this.settledDate,
      sourceTxnId: sourceTxnId ?? this.sourceTxnId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'party': party,
        'amount': amount,
        'note': note,
        'entryDate': entryDate.toIso8601String(),
        'status': status,
        'settledTxnId': settledTxnId,
        'settledDate': settledDate?.toIso8601String(),
        'sourceTxnId': sourceTxnId,
      };

  static Claim fromJson(Map<String, dynamic> j) => Claim(
        id: (j['id'] as num).toInt(),
        type: (j['type'] ?? 'receivable').toString(),
        party: (j['party'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        note: j['note']?.toString(),
        entryDate: DateTime.parse(
          (j['entryDate'] ?? DateTime.now().toIso8601String()).toString(),
        ),
        status: (j['status'] ?? 'open').toString(),
        settledTxnId: j['settledTxnId'] == null ? null : (j['settledTxnId'] as num).toInt(),
        settledDate: j['settledDate'] == null
            ? null
            : DateTime.parse(j['settledDate'].toString()),
        sourceTxnId: j['sourceTxnId'] == null ? null : (j['sourceTxnId'] as num).toInt(),
      );
}
