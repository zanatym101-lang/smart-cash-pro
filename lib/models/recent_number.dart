class RecentNumber {
  final String phone;
  final String? name;
  final DateTime lastUsed;

  const RecentNumber({
    required this.phone,
    required this.lastUsed,
    this.name,
  });

  RecentNumber copyWith({String? phone, String? name, DateTime? lastUsed}) {
    return RecentNumber(
      phone: phone ?? this.phone,
      name: name ?? this.name,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'name': name,
        'lastUsed': lastUsed.toIso8601String(),
      };

  static RecentNumber fromJson(Map<String, dynamic> j) => RecentNumber(
        phone: (j['phone'] ?? '').toString(),
        name: (j['name'] as String?)?.trim().isEmpty == true ? null : (j['name'] as String?),
        lastUsed: DateTime.parse(
          (j['lastUsed'] ?? DateTime.now().toIso8601String()).toString(),
        ),
      );
}
