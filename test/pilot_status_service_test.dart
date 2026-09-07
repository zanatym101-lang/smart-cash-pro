import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/services/pilot_status_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_pilot_status_service_',
  );

  Future<void> resetSettings() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    await db.writeRawSettingsMap(<String, dynamic>{});
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
  });

  setUp(() async {
    await resetSettings();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('PilotStatusService aggregates transfer, receive, and claims metrics',
      () async {
    final db = AppDb.instance;
    final service = PilotStatusService(db: db);

    await db.setTransferUseCasePilotEnabled(true);
    await db.setReceiveUseCasePilotEnabled(false);
    await db.setClaimsUseCasePilotEnabled(true);
    await db.writeRawSettingsMap(<String, dynamic>{
      ...await db.readRawSettingsMap(),
      'transferUseCasePilotMetrics': <String, int>{
        'pilot_runs': 5,
        'pilot_success': 4,
        'pilot_mismatch': 1,
      },
      'receiveUseCasePilotMetrics': <String, int>{
        'pilot_runs': 2,
        'pilot_success': 1,
        'pilot_mismatch': 1,
      },
      'claimsUseCasePilotMetrics': <String, int>{
        'pilot_runs': 3,
        'pilot_success': 3,
        'pilot_mismatch': 0,
      },
    });

    final snapshot = await service.getSnapshot();
    final status = await service.getStatus();

    expect(status, <String, dynamic>{
      'transfer': <String, dynamic>{
        'enabled': true,
        'runs': 5,
        'success': 4,
        'mismatch': 1,
        'auto_disabled_reason': null,
        'health_level': 'healthy',
        'health_reason': 'ok',
      },
      'receive': <String, dynamic>{
        'enabled': false,
        'runs': 2,
        'success': 1,
        'mismatch': 1,
        'auto_disabled_reason': null,
        'health_level': 'healthy',
        'health_reason': 'ok',
      },
      'claims': <String, dynamic>{
        'enabled': true,
        'runs': 3,
        'success': 3,
        'mismatch': 0,
        'auto_disabled_reason': null,
        'health_level': 'healthy',
        'health_reason': 'ok',
      },
      'overall_health_level': 'healthy',
      'overall_health_reason': 'ok',
    });

    expect(await service.getOverallHealth(), isTrue);
    expect(await service.getOverallHealthLevel(), HealthLevel.healthy);
    expect(snapshot.transfer.healthReason, HealthReason.ok);
    expect(snapshot.receive.healthReason, HealthReason.ok);
    expect(snapshot.claims.healthReason, HealthReason.ok);
    expect(snapshot.overallHealthReason, HealthReason.ok);
  });

  test('PilotStatusService marks unhealthy when mismatch rate hits threshold',
      () async {
    final db = AppDb.instance;
    final service = PilotStatusService(db: db);

    await db.writeRawSettingsMap(<String, dynamic>{
      ...await db.readRawSettingsMap(),
      'transferUseCasePilotMetrics': <String, int>{
        'pilot_runs': 10,
        'pilot_success': 7,
        'pilot_mismatch': 3,
      },
      'receiveUseCasePilotMetrics': <String, int>{
        'pilot_runs': 1,
        'pilot_success': 1,
        'pilot_mismatch': 0,
      },
      'claimsUseCasePilotMetrics': <String, int>{
        'pilot_runs': 2,
        'pilot_success': 2,
        'pilot_mismatch': 0,
      },
    });

    final snapshot = await service.getSnapshot();

    expect(snapshot.transfer.isHealthy, isFalse);
    expect(snapshot.transfer.healthLevel, HealthLevel.critical);
    expect(snapshot.transfer.healthReason, HealthReason.mismatchRateHigh);
    expect(snapshot.receive.isHealthy, isTrue);
    expect(snapshot.receive.healthLevel, HealthLevel.healthy);
    expect(snapshot.receive.healthReason, HealthReason.ok);
    expect(snapshot.claims.healthLevel, HealthLevel.healthy);
    expect(await service.getOverallHealth(), isFalse);
    expect(await service.getOverallHealthLevel(), HealthLevel.critical);
    expect(snapshot.overallHealthReason, HealthReason.mismatchRateHigh);
  });

  test('PilotStatusService respects auto-disabled reason as unhealthy',
      () async {
    final db = AppDb.instance;
    final service = PilotStatusService(db: db);

    await db.writeRawSettingsMap(<String, dynamic>{
      ...await db.readRawSettingsMap(),
      'transferUseCasePilotMetrics': <String, int>{
        'pilot_runs': 3,
        'pilot_success': 0,
        'pilot_mismatch': 3,
      },
      'transferUseCasePilotAutoDisabledReason': 'too_many_mismatches',
      'claimsUseCasePilotMetrics': <String, int>{
        'pilot_runs': 1,
        'pilot_success': 1,
        'pilot_mismatch': 0,
      },
    });

    final snapshot = await service.getSnapshot();

    expect(snapshot.transfer.autoDisabledReason, 'too_many_mismatches');
    expect(snapshot.transfer.isHealthy, isFalse);
    expect(snapshot.transfer.healthLevel, HealthLevel.critical);
    expect(snapshot.transfer.healthReason, HealthReason.autoDisabled);
    expect(await service.getOverallHealth(), isFalse);
    expect(await service.getOverallHealthLevel(), HealthLevel.critical);
    expect(snapshot.overallHealthReason, HealthReason.autoDisabled);
  });

  test('PilotStatusService returns healthy level below half threshold',
      () async {
    final db = AppDb.instance;
    final service = PilotStatusService(db: db);

    await db.writeRawSettingsMap(<String, dynamic>{
      ...await db.readRawSettingsMap(),
      'transferUseCasePilotMetrics': <String, int>{
        'pilot_runs': 10,
        'pilot_success': 9,
        'pilot_mismatch': 1,
      },
      'receiveUseCasePilotMetrics': <String, int>{
        'pilot_runs': 4,
        'pilot_success': 4,
        'pilot_mismatch': 0,
      },
      'claimsUseCasePilotMetrics': <String, int>{
        'pilot_runs': 6,
        'pilot_success': 6,
        'pilot_mismatch': 0,
      },
    });

    final snapshot = await service.getSnapshot();

    expect(snapshot.transfer.healthLevel, HealthLevel.healthy);
    expect(snapshot.transfer.healthReason, HealthReason.ok);
    expect(snapshot.receive.healthLevel, HealthLevel.healthy);
    expect(snapshot.receive.healthReason, HealthReason.ok);
    expect(snapshot.claims.healthLevel, HealthLevel.healthy);
    expect(snapshot.claims.healthReason, HealthReason.ok);
    expect(await service.getOverallHealthLevel(), HealthLevel.healthy);
    expect(snapshot.overallHealthReason, HealthReason.ok);
  });

  test('PilotStatusService returns warning level between half threshold and threshold',
      () async {
    final db = AppDb.instance;
    final service = PilotStatusService(db: db);

    await db.writeRawSettingsMap(<String, dynamic>{
      ...await db.readRawSettingsMap(),
      'transferUseCasePilotMetrics': <String, int>{
        'pilot_runs': 10,
        'pilot_success': 8,
        'pilot_mismatch': 2,
      },
      'transferUseCasePilotMismatchThreshold': 3,
      'receiveUseCasePilotMetrics': <String, int>{
        'pilot_runs': 5,
        'pilot_success': 5,
        'pilot_mismatch': 0,
      },
      'claimsUseCasePilotMetrics': <String, int>{
        'pilot_runs': 0,
        'pilot_success': 0,
        'pilot_mismatch': 0,
      },
    });

    final snapshot = await service.getSnapshot();

    expect(snapshot.transfer.healthLevel, HealthLevel.warning);
    expect(snapshot.transfer.healthReason, HealthReason.ok);
    expect(snapshot.receive.healthLevel, HealthLevel.healthy);
    expect(snapshot.receive.healthReason, HealthReason.ok);
    expect(snapshot.claims.healthLevel, HealthLevel.healthy);
    expect(snapshot.claims.healthReason, HealthReason.noData);
    expect(await service.getOverallHealthLevel(), HealthLevel.warning);
    expect(snapshot.overallHealthReason, HealthReason.ok);
  });

  test('PilotStatusService returns no_data reason when channel has no runs',
      () async {
    final db = AppDb.instance;
    final service = PilotStatusService(db: db);

    final snapshot = await service.getSnapshot();

    expect(snapshot.transfer.healthLevel, HealthLevel.healthy);
    expect(snapshot.transfer.healthReason, HealthReason.noData);
    expect(snapshot.receive.healthLevel, HealthLevel.healthy);
    expect(snapshot.receive.healthReason, HealthReason.noData);
    expect(snapshot.claims.healthLevel, HealthLevel.healthy);
    expect(snapshot.claims.healthReason, HealthReason.noData);
    expect(snapshot.overallHealthLevel, HealthLevel.healthy);
    expect(snapshot.overallHealthReason, HealthReason.noData);
  });
}
