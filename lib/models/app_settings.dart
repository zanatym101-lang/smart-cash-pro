class AppSettings {
  final String businessName;
  final String currency;
  final int dayStartHour; // 0-23
  final List<String> quickActionsOrder;
  final List<String> pinnedCustomers;
  final double customerAlertThreshold;

  const AppSettings({
    required this.businessName,
    required this.currency,
    required this.dayStartHour,
    required this.quickActionsOrder,
    required this.pinnedCustomers,
    required this.customerAlertThreshold,
  });

  AppSettings copyWith({
    String? businessName,
    String? currency,
    int? dayStartHour,
    List<String>? quickActionsOrder,
    List<String>? pinnedCustomers,
    double? customerAlertThreshold,
  }) {
    return AppSettings(
      businessName: businessName ?? this.businessName,
      currency: currency ?? this.currency,
      dayStartHour: dayStartHour ?? this.dayStartHour,
      quickActionsOrder: quickActionsOrder ?? this.quickActionsOrder,
      pinnedCustomers: pinnedCustomers ?? this.pinnedCustomers,
      customerAlertThreshold:
          customerAlertThreshold ?? this.customerAlertThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'currency': currency,
        'dayStartHour': dayStartHour,
        'quickActionsOrder': quickActionsOrder,
        'pinnedCustomers': pinnedCustomers,
        'customerAlertThreshold': customerAlertThreshold,
      };
}
