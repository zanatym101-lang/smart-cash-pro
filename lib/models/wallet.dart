class Wallet {
  final int id;
  final String name;
  final bool allowNegative;
  final String phone;
  final double dailyLimit;
  final double monthlyLimit;
  final double lowBalanceThreshold;

  const Wallet({
    required this.id,
    required this.name,
    this.allowNegative = false,
    this.phone = '',
    this.dailyLimit = 60000,
    this.monthlyLimit = 200000,
    this.lowBalanceThreshold = 0,
  });

  Wallet copyWith({
    int? id,
    String? name,
    bool? allowNegative,
    String? phone,
    double? dailyLimit,
    double? monthlyLimit,
    double? lowBalanceThreshold,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      allowNegative: allowNegative ?? this.allowNegative,
      phone: phone ?? this.phone,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      lowBalanceThreshold: lowBalanceThreshold ?? this.lowBalanceThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'allowNegative': allowNegative,
    'phone': phone,
    'dailyLimit': dailyLimit,
    'monthlyLimit': monthlyLimit,
    'lowBalanceThreshold': lowBalanceThreshold,
  };

  static Wallet fromJson(Map<String, dynamic> j) => Wallet(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    allowNegative: (j['allowNegative'] ?? false) == true,
    phone: (j['phone'] ?? '').toString(),
    dailyLimit: (j['dailyLimit'] as num?)?.toDouble() ?? 60000,
    monthlyLimit: (j['monthlyLimit'] as num?)?.toDouble() ?? 200000,
    lowBalanceThreshold: (j['lowBalanceThreshold'] as num?)?.toDouble() ?? 0,
  );
}
