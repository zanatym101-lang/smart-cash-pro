class LicenseInfo {
  final bool isActivated;
  final String deviceCode;
  final int trialDays;
  final int daysUsed;
  final int daysLeft;
  final int maxOperations;
  final int operationsUsed;
  final int operationsLeft;
  final int maxWallets;
  final int maxReports;
  final int reportsUsed;
  final int reportsLeft;

  const LicenseInfo({
    required this.isActivated,
    required this.deviceCode,
    required this.trialDays,
    required this.daysUsed,
    required this.daysLeft,
    required this.maxOperations,
    required this.operationsUsed,
    required this.operationsLeft,
    required this.maxWallets,
    required this.maxReports,
    required this.reportsUsed,
    required this.reportsLeft,
  });
}
