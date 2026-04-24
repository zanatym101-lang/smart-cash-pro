import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_license_backup_test_',
  );

  Future<void> seedCleanDb() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final activationCode = db.generateActivationCodeForDeviceCode(
      info.deviceCode,
    );
    await db.activateWithCode(activationCode);
    await db.resetDatabaseEmpty();
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
    await seedCleanDb();
  });

  setUp(() async {
    await seedCleanDb();
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

  test('json backup excludes sensitive license tokens and bindings', () async {
    final db = AppDb.instance;
    final settings = await db.readRawSettingsMap();
    settings['license'] = <String, dynamic>{
      'trialDays': 7,
      'maxOperations': 20,
      'cloudToken': 'access-secret',
      'cloudTokenExpiresAt': '2030-01-01T00:00:00Z',
      'serverAuthRefreshToken': 'refresh-secret',
      'serverAuthRefreshTokenExpiresAt': '2030-02-01T00:00:00Z',
      'activationCode': 'ABCD-EFGH-IJKL',
      'cloudDeviceId': 'device-xyz',
      'serverAuthDiagLastError': 'internal',
    };
    await db.writeRawSettingsMap(settings);

    final backupPath = await db.exportJsonBackupToPath(supportDir.path);
    final backupRaw = await File(backupPath).readAsString();
    final backupJson = jsonDecode(backupRaw) as Map<String, dynamic>;
    final backupSettings =
        Map<String, dynamic>.from(backupJson['settings'] as Map);
    final backupLicense =
        Map<String, dynamic>.from(backupSettings['license'] as Map);

    expect(backupLicense['trialDays'], 7);
    expect(backupLicense['maxOperations'], 20);
    expect(backupLicense.containsKey('cloudToken'), isFalse);
    expect(backupLicense.containsKey('cloudTokenExpiresAt'), isFalse);
    expect(backupLicense.containsKey('serverAuthRefreshToken'), isFalse);
    expect(
      backupLicense.containsKey('serverAuthRefreshTokenExpiresAt'),
      isFalse,
    );
    expect(backupLicense.containsKey('activationCode'), isFalse);
    expect(backupLicense.containsKey('cloudDeviceId'), isFalse);
    expect(
      backupLicense.keys.any((k) => k.toString().startsWith('serverAuthDiag')),
      isFalse,
    );
  });

  test('restore sanitizes sensitive license keys from old backup snapshot', () async {
    final db = AppDb.instance;

    final backupPath = await db.exportJsonBackupToPath(supportDir.path);
    final backupRaw = await File(backupPath).readAsString();
    final backupJson = jsonDecode(backupRaw) as Map<String, dynamic>;
    final backupSettings =
        Map<String, dynamic>.from(backupJson['settings'] as Map);
    final oldLicense = Map<String, dynamic>.from(
      (backupSettings['license'] as Map?) ?? <String, dynamic>{},
    );
    oldLicense['trialDays'] = 9;
    oldLicense['cloudToken'] = 'legacy-access-token';
    oldLicense['serverAuthRefreshToken'] = 'legacy-refresh-token';
    oldLicense['activationCode'] = 'LEGACY-CODE';
    oldLicense['cloudDeviceId'] = 'legacy-device';
    oldLicense['serverAuthDiagLastError'] = 'legacy-diagnostic';
    backupSettings['license'] = oldLicense;
    backupJson['settings'] = backupSettings;
    await File(backupPath).writeAsString(jsonEncode(backupJson), flush: true);
    final checksumSidecar = File('$backupPath.sha256');
    if (await checksumSidecar.exists()) {
      await checksumSidecar.delete();
    }

    final current = await db.readRawSettingsMap();
    final currentLicense = Map<String, dynamic>.from(
      (current['license'] as Map?) ?? <String, dynamic>{},
    );
    currentLicense.removeWhere(
      (key, _) =>
          key == 'cloudToken' ||
          key == 'cloudTokenExpiresAt' ||
          key == 'serverAuthRefreshToken' ||
          key == 'serverAuthRefreshTokenExpiresAt' ||
          key == 'activationCode' ||
          key == 'cloudDeviceId' ||
          key.toString().startsWith('serverAuthDiag'),
    );
    current['license'] = currentLicense;
    await db.writeRawSettingsMap(current);

    await db.restoreJsonBackupFromPath(backupPath);

    final restored = await db.readRawSettingsMap();
    final restoredLicense = Map<String, dynamic>.from(
      (restored['license'] as Map?) ?? <String, dynamic>{},
    );

    expect(restoredLicense['trialDays'], 9);
    expect(restoredLicense.containsKey('cloudToken'), isFalse);
    expect(restoredLicense.containsKey('serverAuthRefreshToken'), isFalse);
    expect(restoredLicense.containsKey('activationCode'), isFalse);
    expect(restoredLicense.containsKey('cloudDeviceId'), isFalse);
    expect(
      restoredLicense.keys.any(
        (k) => k.toString().startsWith('serverAuthDiag'),
      ),
      isFalse,
    );
  });
}
