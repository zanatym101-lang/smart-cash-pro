class Txn {
  final int id;
  final String kind; // deposit/receive/transfer/adjustment/drawer_fund
  final String status; // posted/pending/canceled
  final DateTime entryDate;
  final int? walletFromId;
  final int? walletToId;
  final double amount;
  final double clientFee;
  final double networkFee;
  final String mode; // type1/type2/...
  final String? note;
  final String? serviceName; // fawry service
  final String? reference; // ref/meter/mobile
  final String? party; // client/party name
  final String createdBy; // actor name
  final String createdRole; // admin/user/system
  final DateTime createdAt;

  const Txn({
    required this.id,
    required this.kind,
    required this.status,
    required this.entryDate,
    this.walletFromId,
    this.walletToId,
    required this.amount,
    required this.clientFee,
    required this.networkFee,
    required this.mode,
    this.note,
    this.serviceName,
    this.reference,
    this.party,
    required this.createdBy,
    required this.createdRole,
    required this.createdAt,
  });

  Txn copyWith({
    int? id,
    String? kind,
    String? status,
    DateTime? entryDate,
    int? walletFromId,
    int? walletToId,
    double? amount,
    double? clientFee,
    double? networkFee,
    String? mode,
    String? note,
    String? serviceName,
    String? reference,
    String? party,
    String? createdBy,
    String? createdRole,
    DateTime? createdAt,
  }) {
    return Txn(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      entryDate: entryDate ?? this.entryDate,
      walletFromId: walletFromId ?? this.walletFromId,
      walletToId: walletToId ?? this.walletToId,
      amount: amount ?? this.amount,
      clientFee: clientFee ?? this.clientFee,
      networkFee: networkFee ?? this.networkFee,
      mode: mode ?? this.mode,
      note: note ?? this.note,
      serviceName: serviceName ?? this.serviceName,
      reference: reference ?? this.reference,
      party: party ?? this.party,
      createdBy: createdBy ?? this.createdBy,
      createdRole: createdRole ?? this.createdRole,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'status': status,
    'entryDate': entryDate.toIso8601String(),
    'walletFromId': walletFromId,
    'walletToId': walletToId,
    'amount': amount,
    'clientFee': clientFee,
    'networkFee': networkFee,
    'mode': mode,
    'note': note,
    'serviceName': serviceName,
    'reference': reference,
    'party': party,
    'createdBy': createdBy,
    'createdRole': createdRole,
    'createdAt': createdAt.toIso8601String(),
  };

  static Txn fromJson(Map<String, dynamic> j) => Txn(
    id: (j['id'] as num).toInt(),
    kind: (j['kind'] ?? '').toString(),
    status: (j['status'] ?? 'posted').toString(),
    entryDate: DateTime.parse((j['entryDate'] ?? DateTime.now().toIso8601String()).toString()),
    walletFromId: j['walletFromId'] == null ? null : (j['walletFromId'] as num).toInt(),
    walletToId: j['walletToId'] == null ? null : (j['walletToId'] as num).toInt(),
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    clientFee: (j['clientFee'] as num?)?.toDouble() ?? 0,
    networkFee: (j['networkFee'] as num?)?.toDouble() ?? 0,
    mode: (j['mode'] ?? '').toString(),
    note: j['note']?.toString(),
    serviceName: j['serviceName']?.toString(),
    reference: j['reference']?.toString(),
    party: j['party']?.toString(),
    createdBy: (j['createdBy'] ?? 'غير معروف').toString(),
    createdRole: (j['createdRole'] ?? 'user').toString(),
    createdAt: DateTime.parse(
      (j['createdAt'] ?? j['entryDate'] ?? DateTime.now().toIso8601String()).toString(),
    ),
  );
}
