class CustomerAttachment {
  final int id;
  final String customerKey;
  final String customerName;
  final String? customerPhone;
  final String fileName;
  final String filePath;
  final DateTime createdAt;

  const CustomerAttachment({
    required this.id,
    required this.customerKey,
    required this.customerName,
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    this.customerPhone,
  });

  CustomerAttachment copyWith({
    int? id,
    String? customerKey,
    String? customerName,
    String? customerPhone,
    String? fileName,
    String? filePath,
    DateTime? createdAt,
  }) {
    return CustomerAttachment(
      id: id ?? this.id,
      customerKey: customerKey ?? this.customerKey,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customerKey': customerKey,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'fileName': fileName,
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
  };

  static CustomerAttachment fromJson(Map<String, dynamic> j) {
    return CustomerAttachment(
      id: int.tryParse((j['id'] ?? '').toString()) ?? 0,
      customerKey: (j['customerKey'] ?? '').toString(),
      customerName: (j['customerName'] ?? '').toString(),
      customerPhone: (j['customerPhone'] as String?)?.trim().isEmpty == true
          ? null
          : (j['customerPhone'] as String?),
      fileName: (j['fileName'] ?? '').toString(),
      filePath: (j['filePath'] ?? '').toString(),
      createdAt: DateTime.parse(
        (j['createdAt'] ?? DateTime.now().toIso8601String()).toString(),
      ),
    );
  }
}
