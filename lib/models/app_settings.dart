class AppSettings {
  final String businessName;
  final String currency;
  final int dayStartHour; // 0-23
  final List<String> quickActionsOrder;

  const AppSettings({
    required this.businessName,
    required this.currency,
    required this.dayStartHour,
    required this.quickActionsOrder,
  });

  AppSettings copyWith({
    String? businessName,
    String? currency,
    int? dayStartHour,
    List<String>? quickActionsOrder,
  }) {
    return AppSettings(
      businessName: businessName ?? this.businessName,
      currency: currency ?? this.currency,
      dayStartHour: dayStartHour ?? this.dayStartHour,
      quickActionsOrder: quickActionsOrder ?? this.quickActionsOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'currency': currency,
        'dayStartHour': dayStartHour,
        'quickActionsOrder': quickActionsOrder,
      };
}
