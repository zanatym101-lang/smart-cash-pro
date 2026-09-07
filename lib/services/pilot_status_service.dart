import '../data/app_db.dart';

enum HealthLevel {
  healthy,
  warning,
  critical,
}

enum HealthReason {
  ok,
  mismatchRateHigh,
  autoDisabled,
  noData,
}

class PilotChannelStatus {
  const PilotChannelStatus({
    required this.enabled,
    required this.runs,
    required this.success,
    required this.mismatch,
    required this.autoDisabledReason,
    required this.threshold,
  });

  final bool enabled;
  final int runs;
  final int success;
  final int mismatch;
  final String? autoDisabledReason;
  final int threshold;

  double get mismatchRate {
    if (runs <= 0) return 0;
    return mismatch / runs;
  }

  double get thresholdRate {
    if (runs <= 0) return 1;
    return threshold / runs;
  }

  bool get isHealthy {
    if (autoDisabledReason != null) return false;
    return mismatchRate < thresholdRate;
  }

  HealthLevel get healthLevel {
    if (autoDisabledReason != null) return HealthLevel.critical;
    final halfThresholdRate = thresholdRate / 2;
    if (mismatchRate < halfThresholdRate) return HealthLevel.healthy;
    if (mismatchRate < thresholdRate) return HealthLevel.warning;
    return HealthLevel.critical;
  }

  HealthReason get healthReason {
    if (autoDisabledReason != null) return HealthReason.autoDisabled;
    if (mismatchRate >= thresholdRate) return HealthReason.mismatchRateHigh;
    if (runs == 0) return HealthReason.noData;
    return HealthReason.ok;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'runs': runs,
      'success': success,
      'mismatch': mismatch,
      'auto_disabled_reason': autoDisabledReason,
      'health_level': healthLevel.name,
      'health_reason': healthReason.name,
    };
  }
}

class PilotStatusSnapshot {
  const PilotStatusSnapshot({
    required this.transfer,
    required this.receive,
    required this.claims,
  });

  final PilotChannelStatus transfer;
  final PilotChannelStatus receive;
  final PilotChannelStatus claims;

  bool get overallHealthy =>
      transfer.isHealthy && receive.isHealthy && claims.isHealthy;

  HealthLevel get overallHealthLevel {
    if (transfer.healthLevel == HealthLevel.critical ||
        receive.healthLevel == HealthLevel.critical ||
        claims.healthLevel == HealthLevel.critical) {
      return HealthLevel.critical;
    }
    if (transfer.healthLevel == HealthLevel.warning ||
        receive.healthLevel == HealthLevel.warning ||
        claims.healthLevel == HealthLevel.warning) {
      return HealthLevel.warning;
    }
    return HealthLevel.healthy;
  }

  HealthReason get overallHealthReason {
    if (transfer.healthReason == HealthReason.autoDisabled ||
        receive.healthReason == HealthReason.autoDisabled ||
        claims.healthReason == HealthReason.autoDisabled) {
      return HealthReason.autoDisabled;
    }
    if (transfer.healthReason == HealthReason.mismatchRateHigh ||
        receive.healthReason == HealthReason.mismatchRateHigh ||
        claims.healthReason == HealthReason.mismatchRateHigh) {
      return HealthReason.mismatchRateHigh;
    }
    if (transfer.healthReason == HealthReason.ok ||
        receive.healthReason == HealthReason.ok ||
        claims.healthReason == HealthReason.ok) {
      return HealthReason.ok;
    }
    return HealthReason.noData;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transfer': transfer.toJson(),
      'receive': receive.toJson(),
      'claims': claims.toJson(),
      'overall_health_level': overallHealthLevel.name,
      'overall_health_reason': overallHealthReason.name,
    };
  }
}

class PilotStatusService {
  PilotStatusService({AppDb? db}) : _db = db ?? AppDb.instance;

  final AppDb _db;

  Future<PilotStatusSnapshot> getSnapshot() async {
    final transferMetrics = await _db.getTransferUseCasePilotMetrics();
    final receiveMetrics = await _db.getReceiveUseCasePilotMetrics();
    final claimsMetrics = await _db.getClaimsUseCasePilotMetrics();

    final transfer = PilotChannelStatus(
      enabled: await _db.getTransferUseCasePilotEnabled(),
      runs: transferMetrics['pilot_runs'] ?? 0,
      success: transferMetrics['pilot_success'] ?? 0,
      mismatch: transferMetrics['pilot_mismatch'] ?? 0,
      autoDisabledReason:
          await _db.getTransferUseCasePilotAutoDisabledReason(),
      threshold: await _db.getTransferUseCasePilotMismatchThreshold(),
    );

    final receive = PilotChannelStatus(
      enabled: await _db.getReceiveUseCasePilotEnabled(),
      runs: receiveMetrics['pilot_runs'] ?? 0,
      success: receiveMetrics['pilot_success'] ?? 0,
      mismatch: receiveMetrics['pilot_mismatch'] ?? 0,
      autoDisabledReason: await _db.getReceiveUseCasePilotAutoDisabledReason(),
      threshold: await _db.getReceiveUseCasePilotMismatchThreshold(),
    );

    final claims = PilotChannelStatus(
      enabled: await _db.getClaimsUseCasePilotEnabled(),
      runs: claimsMetrics['pilot_runs'] ?? 0,
      success: claimsMetrics['pilot_success'] ?? 0,
      mismatch: claimsMetrics['pilot_mismatch'] ?? 0,
      autoDisabledReason: await _db.getClaimsUseCasePilotAutoDisabledReason(),
      threshold: await _db.getClaimsUseCasePilotMismatchThreshold(),
    );

    return PilotStatusSnapshot(
      transfer: transfer,
      receive: receive,
      claims: claims,
    );
  }

  Future<Map<String, dynamic>> getStatus() async {
    return (await getSnapshot()).toJson();
  }

  Future<bool> getOverallHealth() async {
    return (await getSnapshot()).overallHealthy;
  }

  Future<HealthLevel> getOverallHealthLevel() async {
    return (await getSnapshot()).overallHealthLevel;
  }
}
