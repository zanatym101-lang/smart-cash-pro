import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/drive_backup_service.dart';

const driveFileScopeForTest = 'https://www.googleapis.com/auth/drive.file';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kw_drive_backup_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'currentEmail uses silent sign-in and signOut clears cached account',
    () async {
      final signIn = _FakeSignInGateway(
        signInResult: _testUser('active@example.com'),
        silentResult: _testUser('silent@example.com'),
      );
      final api = _FakeDriveApiGateway();

      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) => api,
        backupPathProvider: () async => '${tempDir.path}/unused.db',
      );

      expect(await service.currentEmail(), 'silent@example.com');
      expect(signIn.signInSilentlyCalls, 1);
      expect(signIn.signInCalls, 0);

      final signedIn = await service.signIn();
      expect(signedIn?.email, 'active@example.com');
      expect(signIn.signInCalls, 1);

      await service.signOut();
      expect(signIn.signOutCalls, 1);

      expect(await service.currentEmail(), 'silent@example.com');
      expect(signIn.signInSilentlyCalls, 2);
    },
  );

  test(
    'uploadLatestBackup uploads into existing folder and closes API client',
    () async {
      final backupFile = File('${tempDir.path}/backup.db');
      await backupFile.writeAsBytes(
        List<int>.generate(256, (i) => i % 200),
        flush: true,
      );

      final signIn = _FakeSignInGateway(
        signInResult: null,
        silentResult: _testUser('backup@example.com'),
      );
      final api = _FakeDriveApiGateway(
        folders: const [
          DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
        ],
        uploadedFileId: 'file-123',
      );

      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) => api,
        backupPathProvider: () async => backupFile.path,
        nowProvider: () => DateTime(2026, 2, 16, 10, 20, 30),
      );

      final uploadedId = await service.uploadLatestBackup();

      expect(uploadedId, 'file-123');
      expect(api.findFoldersCalls, 1);
      expect(api.createFolderCalls, 0);
      expect(api.uploadCalls, 1);
      expect(api.lastUploadFolderId, 'folder-1');
      expect(api.lastUploadName, 'smart_cash_backup_20260216_102030.db');
      expect(api.lastUploadLength, 256);
      expect(api.lastUploadedBytes, 256);
      expect(api.closed, isTrue);
    },
  );

  test(
    'listBackups returns files from drive folder and closes API client',
    () async {
      final signIn = _FakeSignInGateway(
        signInResult: _testUser('list@example.com'),
        silentResult: null,
      );
      final api = _FakeDriveApiGateway(
        folders: const [
          DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
        ],
        listedFiles: const [
          DriveBackupFileRef(
            id: 'f2',
            name: 'smart_cash_backup_2.db',
            modifiedTime: null,
            sizeBytes: 12,
          ),
          DriveBackupFileRef(
            id: 'f1',
            name: 'smart_cash_backup_1.db',
            modifiedTime: null,
            sizeBytes: 10,
          ),
          DriveBackupFileRef(
            id: 'enc',
            name: 'smart_cash_pro_backup_2026-01-01_10-00.enc',
            modifiedTime: null,
            sizeBytes: 20,
          ),
          DriveBackupFileRef(
            id: 'json',
            name: 'smart_cash_pro_backup_2026-01-01_10-00.json',
            modifiedTime: null,
            sizeBytes: 21,
          ),
        ],
      );
      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) => api,
        backupPathProvider: () async => '${tempDir.path}/unused.db',
      );

      final files = await service.listBackups();
      expect(files.length, 2);
      expect(files.any((file) => file.name.endsWith('.enc')), isFalse);
      expect(files.any((file) => file.name.endsWith('.json')), isFalse);
      expect(api.listFilesCalls, 1);
      expect(api.lastListFolderId, 'folder-1');
      expect(api.closed, isTrue);
    },
  );

  test(
    'downloadBackupToTemporary writes downloaded bytes to a temp file',
    () async {
      final signIn = _FakeSignInGateway(
        signInResult: _testUser('download@example.com'),
        silentResult: null,
      );
      final api = _FakeDriveApiGateway(
        downloadPayloadById: const {
          'file-1': [1, 2, 3, 4, 5],
        },
      );
      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) => api,
        backupPathProvider: () async => '${tempDir.path}/unused.db',
      );

      final path = await service.downloadBackupToTemporary(
        fileId: 'file-1',
        fileName: 'test_backup.db',
      );
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), equals(const <int>[1, 2, 3, 4, 5]));
      expect(api.downloadCalls, 1);
      expect(api.lastDownloadFileId, 'file-1');
      expect(api.closed, isTrue);
      await file.delete();
    },
  );

  test(
    'uploadLatestBackup creates folder when folder does not exist',
    () async {
      final backupFile = File('${tempDir.path}/backup2.db');
      await backupFile.writeAsString('demo', flush: true);

      final signIn = _FakeSignInGateway(
        signInResult: _testUser('user@example.com'),
        silentResult: null,
      );
      final api = _FakeDriveApiGateway(
        folders: const [],
        createdFolderId: 'new-folder',
        uploadedFileId: 'new-file',
      );

      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) => api,
        backupPathProvider: () async => backupFile.path,
      );

      final uploadedId = await service.uploadLatestBackup();
      expect(uploadedId, 'new-file');
      expect(api.createFolderCalls, 1);
      expect(api.lastCreatedFolderName, 'Smart Cash Pro Backups');
      expect(api.lastUploadFolderId, 'new-folder');
    },
  );

  test('uploadLatestBackup throws when user is not authenticated', () async {
    final signIn = _FakeSignInGateway(signInResult: null, silentResult: null);
    var apiFactoryCalls = 0;

    final service = DriveBackupService.testable(
      signInGateway: signIn,
      apiFactory: (_) {
        apiFactoryCalls += 1;
        return _FakeDriveApiGateway();
      },
      backupPathProvider: () async => '${tempDir.path}/backup.db',
    );

    await expectLater(service.uploadLatestBackup(), throwsA(isA<Exception>()));
    expect(apiFactoryCalls, 0);
  });

  test(
    'encrypted backup creates metadata and restores decrypted database',
    () async {
      final backupFile = File('${tempDir.path}/encrypted.db');
      final dbBytes = List<int>.generate(512, (i) => (i * 7) % 251);
      await backupFile.writeAsBytes(dbBytes, flush: true);
      final api = _FakeDriveApiGateway(
        folders: const [
          DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
        ],
        autoGenerateUploadIds: true,
      );
      final order = <String>[];
      List<int>? restoredBytes;
      final service = DriveBackupService.testable(
        signInGateway: _FakeSignInGateway(
          signInResult: null,
          silentResult: _testUser('backup@example.com'),
        ),
        apiFactory: (_) => api,
        backupPathProvider: () async => backupFile.path,
        safetyBackupProvider: () async {
          order.add('safety');
          return '${tempDir.path}/safety.db';
        },
        restorePathHandler: (path) async {
          order.add('restore');
          restoredBytes = await File(path).readAsBytes();
        },
        nowProvider: () => DateTime(2026, 5, 7, 11, 12, 13),
      );

      final metadata = await service.createEncryptedDriveBackup(
        'strong-passphrase',
        note: 'manual',
      );

      expect(metadata.encrypted, isTrue);
      expect(metadata.backupId, 'upload-1');
      expect(metadata.metadataFileId, 'upload-2');
      expect(metadata.fileName, 'smart_cash_pro_backup_2026-05-07_11-12.enc');
      expect(metadata.note, 'manual');
      expect(metadata.sizeBytes, dbBytes.length);
      expect(metadata.checksum, sha256.convert(dbBytes).toString());
      expect(api.uploadCalls, 2);
      expect(api.uploads['upload-1']!.mimeType, 'application/octet-stream');
      expect(api.uploads['upload-2']!.mimeType, 'application/json');
      expect(
        utf8.decode(api.uploads['upload-2']!.bytes),
        contains('"backupId":"upload-1"'),
      );

      await service.restoreEncryptedDriveBackup(
        backupId: metadata.backupId,
        passphrase: 'strong-passphrase',
      );

      expect(restoredBytes, dbBytes);
      expect(order, ['safety', 'restore']);
    },
  );

  test('wrong passphrase fails and restore handler is not called', () async {
    final backupFile = File('${tempDir.path}/encrypted_wrong_password.db');
    await backupFile.writeAsString('wallet db', flush: true);
    final api = _FakeDriveApiGateway(
      folders: const [
        DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
      ],
      autoGenerateUploadIds: true,
    );
    var restoreCalls = 0;
    final service = DriveBackupService.testable(
      signInGateway: _FakeSignInGateway(
        signInResult: null,
        silentResult: _testUser('backup@example.com'),
      ),
      apiFactory: (_) => api,
      backupPathProvider: () async => backupFile.path,
      safetyBackupProvider: () async => '${tempDir.path}/safety.db',
      restorePathHandler: (_) async {
        restoreCalls += 1;
      },
    );
    final metadata = await service.createEncryptedDriveBackup(
      'strong-passphrase',
    );

    await expectLater(
      service.restoreEncryptedDriveBackup(
        backupId: metadata.backupId,
        passphrase: 'different-passphrase',
      ),
      throwsA(isA<BackupIntegrityException>()),
    );
    expect(restoreCalls, 0);
  });

  test('corrupted encrypted payload fails integrity checks', () async {
    final backupFile = File('${tempDir.path}/encrypted_corrupt.db');
    await backupFile.writeAsString('wallet db', flush: true);
    final api = _FakeDriveApiGateway(
      folders: const [
        DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
      ],
      autoGenerateUploadIds: true,
    );
    final service = DriveBackupService.testable(
      signInGateway: _FakeSignInGateway(
        signInResult: null,
        silentResult: _testUser('backup@example.com'),
      ),
      apiFactory: (_) => api,
      backupPathProvider: () async => backupFile.path,
      safetyBackupProvider: () async => '${tempDir.path}/safety.db',
      restorePathHandler: (_) async {},
    );
    final metadata = await service.createEncryptedDriveBackup(
      'strong-passphrase',
    );
    api.uploads[metadata.backupId] = api.uploads[metadata.backupId]!.copyWith(
      bytes: List<int>.from(api.uploads[metadata.backupId]!.bytes)..[20] ^= 1,
    );

    await expectLater(
      service.restoreEncryptedDriveBackup(
        backupId: metadata.backupId,
        passphrase: 'strong-passphrase',
      ),
      throwsA(isA<BackupIntegrityException>()),
    );
  });

  test(
    'listDriveBackups returns encrypted metadata sorted newest first',
    () async {
      final older = BackupMetadata(
        backupId: 'old-file',
        createdAt: DateTime(2026, 1, 1, 9),
        appVersion: '1.0.0',
        buildNumber: '10',
        appEnv: 'build',
        deviceName: 'device-a',
        databaseVersion: 3,
        encrypted: true,
        checksum: 'old',
        sizeBytes: 10,
        fileName: 'old.enc',
      );
      final newer = BackupMetadata(
        backupId: 'new-file',
        createdAt: DateTime(2026, 2, 1, 9),
        appVersion: '1.0.1',
        buildNumber: '11',
        appEnv: 'build',
        deviceName: 'device-b',
        databaseVersion: 3,
        encrypted: true,
        checksum: 'new',
        sizeBytes: 20,
        fileName: 'new.enc',
      );
      final api = _FakeDriveApiGateway(
        folders: const [
          DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
        ],
        listedFiles: const [
          DriveBackupFileRef(
            id: 'older-json',
            name: 'old.json',
            modifiedTime: null,
            sizeBytes: 1,
          ),
          DriveBackupFileRef(
            id: 'newer-json',
            name: 'new.json',
            modifiedTime: null,
            sizeBytes: 1,
          ),
        ],
        downloadPayloadById: {
          'older-json': utf8.encode(jsonEncode(older.toJson())),
          'newer-json': utf8.encode(jsonEncode(newer.toJson())),
        },
      );
      final service = DriveBackupService.testable(
        signInGateway: _FakeSignInGateway(
          signInResult: null,
          silentResult: _testUser('list@example.com'),
        ),
        apiFactory: (_) => api,
        backupPathProvider: () async => '${tempDir.path}/unused.db',
      );

      final backups = await service.listDriveBackups();

      expect(backups.map((backup) => backup.backupId), [
        'new-file',
        'old-file',
      ]);
      expect(backups.first.metadataFileId, 'newer-json');
    },
  );

  test('auto backup due calculation and settings do not store passphrase', () {
    final now = DateTime(2026, 5, 7, 12);
    final due = AutoBackupSettings(
      enabled: true,
      frequency: AutoBackupFrequency.daily,
      lastRunAt: now.subtract(const Duration(days: 2)),
      passphraseMode: AutoBackupPassphraseMode.manualRequired,
    );
    final notDue = AutoBackupSettings(
      enabled: true,
      frequency: AutoBackupFrequency.weekly,
      lastRunAt: now.subtract(const Duration(days: 2)),
      passphraseMode: AutoBackupPassphraseMode.manualRequired,
    );

    expect(due.isDue(now), isTrue);
    expect(notDue.isDue(now), isFalse);
    final serialized = jsonEncode(due.toJson()).toLowerCase();
    expect(serialized, isNot(contains('passphrase"')));
    expect(serialized, contains('manualrequired'));
  });

  test('encrypted backup does not start unless Drive is signed in', () async {
    final logs = <Map<String, Object?>>[];
    final backupFile = File('${tempDir.path}/backup.db');
    await backupFile.writeAsString('db', flush: true);
    var apiFactoryCalls = 0;
    final service = DriveBackupService.testable(
      signInGateway: _FakeSignInGateway(signInResult: null, silentResult: null),
      apiFactory: (_) {
        apiFactoryCalls += 1;
        return _FakeDriveApiGateway();
      },
      backupPathProvider: () async => backupFile.path,
      authLogSink: logs.add,
    );

    await expectLater(
      service.createEncryptedDriveBackup('strong-passphrase'),
      throwsA(
        isA<DriveAuthException>().having(
          (e) => e.diagnostic?.interactiveSignInReturnedNull,
          'interactiveSignInReturnedNull',
          isTrue,
        ),
      ),
    );

    expect(apiFactoryCalls, 0);
    expect(logs.toString().toLowerCase(), isNot(contains('strong-passphrase')));
  });

  test(
    'auth failure logs diagnostics without tokens and backup does not start',
    () async {
      final logs = <Map<String, Object?>>[];
      final signIn = _FakeSignInGateway(
        signInResult: null,
        silentResult: null,
        signInError: PlatformException(
          code: 'sign_in_failed',
          message:
              'OAuth client mismatch Bearer secret-token access_token=secret',
        ),
      );
      var apiFactoryCalls = 0;

      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) {
          apiFactoryCalls += 1;
          return _FakeDriveApiGateway();
        },
        backupPathProvider: () async => '${tempDir.path}/backup.db',
        authLogSink: logs.add,
      );

      await expectLater(
        service.uploadLatestBackup(),
        throwsA(isA<DriveAuthException>()),
      );

      expect(apiFactoryCalls, 0);
      expect(
        logs.any(
          (entry) =>
              entry['phase'] == 'interactive_sign_in' &&
              entry['errorCode'] == 'sign_in_failed' &&
              entry['exceptionType'] == 'PlatformException',
        ),
        isTrue,
      );
      final serializedLogs = logs.toString();
      expect(serializedLogs, isNot(contains('secret-token')));
      expect(serializedLogs, isNot(contains('access_token=secret')));
      expect(serializedLogs, contains(driveFileScopeForTest));
      expect(serializedLogs, contains('applicationId'));
      expect(serializedLogs, contains('requestedScopes'));
    },
  );

  test('silent sign-in failure is recorded in auth diagnostics', () async {
    final logs = <Map<String, Object?>>[];
    final service = DriveBackupService.testable(
      signInGateway: _FakeSignInGateway(
        signInResult: _testUser('interactive@example.com'),
        silentResult: null,
        silentError: PlatformException(
          code: 'network_error',
          message: 'Google Play Services network error',
        ),
      ),
      apiFactory: (_) => _FakeDriveApiGateway(),
      backupPathProvider: () async => '${tempDir.path}/unused.db',
      authLogSink: logs.add,
    );

    expect(await service.currentEmail(), isNull);
    expect(service.lastAuthDiagnostic?.silentSignInFailed, isTrue);
    expect(
      logs.any(
        (entry) =>
            entry['phase'] == 'silent_sign_in' &&
            entry['outcome'] == 'failure' &&
            entry['silentSignInFailed'] == true,
      ),
      isTrue,
    );
  });

  test('Drive API failure after login is logged with likely cause', () async {
    final logs = <Map<String, Object?>>[];
    final backupFile = File('${tempDir.path}/api_failure.db');
    await backupFile.writeAsString('payload', flush: true);
    final api = _FakeDriveApiGateway(
      findFoldersError: PlatformException(
        code: '403',
        message: 'Google Drive API has not been used in project',
        details: const {'statusCode': 403},
      ),
    );
    final service = DriveBackupService.testable(
      signInGateway: _FakeSignInGateway(
        signInResult: null,
        silentResult: _testUser('drive@example.com'),
      ),
      apiFactory: (_) => api,
      backupPathProvider: () async => backupFile.path,
      authLogSink: logs.add,
    );

    await expectLater(
      service.uploadLatestBackup(),
      throwsA(
        isA<DriveAuthException>().having(
          (e) => e.diagnostic?.driveApiRequestFailedAfterLogin,
          'driveApiRequestFailedAfterLogin',
          isTrue,
        ),
      ),
    );

    expect(
      logs.any(
        (entry) =>
            entry['phase'] == 'drive_api_find_folder' &&
            entry['outcome'] == 'failure_after_login' &&
            entry['statusCode'] == '403' &&
            entry['driveApiRequestFailedAfterLogin'] == true,
      ),
      isTrue,
    );
    expect(logs.toString(), contains('Google Drive API disabled'));
  });

  test('signIn auth failure exposes friendly Arabic message', () async {
    final service = DriveBackupService.testable(
      signInGateway: _FakeSignInGateway(
        signInResult: null,
        silentResult: null,
        signInError: PlatformException(
          code: 'sign_in_failed',
          message: 'OAuth client mismatch',
        ),
      ),
      apiFactory: (_) => _FakeDriveApiGateway(),
      backupPathProvider: () async => '${tempDir.path}/unused.db',
      authLogSink: (_) {},
    );

    await expectLater(
      service.signIn(),
      throwsA(
        isA<DriveAuthException>().having(
          (e) => e.userMessage,
          'userMessage',
          'تعذر تسجيل الدخول إلى Google Drive',
        ),
      ),
    );
  });

  test(
    'uploadLatestBackup throws when backup file is missing and still closes API',
    () async {
      final signIn = _FakeSignInGateway(
        signInResult: _testUser('user@example.com'),
        silentResult: null,
      );
      final api = _FakeDriveApiGateway(
        folders: const [
          DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
        ],
      );

      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) => api,
        backupPathProvider: () async => '${tempDir.path}/does_not_exist.db',
      );

      await expectLater(
        service.uploadLatestBackup(),
        throwsA(isA<Exception>()),
      );
      expect(api.uploadCalls, 0);
      expect(api.closed, isTrue);
    },
  );

  test('backupName format is deterministic', () {
    final service = DriveBackupService.testable(
      signInGateway: _FakeSignInGateway(signInResult: null, silentResult: null),
      apiFactory: (_) => _FakeDriveApiGateway(),
      backupPathProvider: () async => '${tempDir.path}/unused.db',
    );

    final name = service.backupName(DateTime(2026, 1, 2, 3, 4, 5));
    expect(name, 'smart_cash_backup_20260102_030405.db');
  });

  test('uploadLatestBackup throws when created folder id is empty', () async {
    final backupFile = File('${tempDir.path}/backup3.db');
    await backupFile.writeAsString('x', flush: true);

    final signIn = _FakeSignInGateway(
      signInResult: _testUser('folder@example.com'),
      silentResult: null,
    );
    final api = _FakeDriveApiGateway(folders: const [], createdFolderId: '');

    final service = DriveBackupService.testable(
      signInGateway: signIn,
      apiFactory: (_) => api,
      backupPathProvider: () async => backupFile.path,
    );

    await expectLater(service.uploadLatestBackup(), throwsA(isA<Exception>()));
    expect(api.createFolderCalls, 1);
    expect(api.uploadCalls, 0);
    expect(api.closed, isTrue);
  });

  test(
    'uploadLatestBackup throws when Google Drive upload returns no id',
    () async {
      final backupFile = File('${tempDir.path}/backup4.db');
      await backupFile.writeAsString('payload', flush: true);

      final signIn = _FakeSignInGateway(
        signInResult: _testUser('upload@example.com'),
        silentResult: null,
      );
      final api = _FakeDriveApiGateway(
        folders: const [
          DriveFolderRef(id: 'folder-1', name: 'Smart Cash Pro Backups'),
        ],
        uploadedFileId: null,
      );

      final service = DriveBackupService.testable(
        signInGateway: signIn,
        apiFactory: (_) => api,
        backupPathProvider: () async => backupFile.path,
      );

      await expectLater(
        service.uploadLatestBackup(),
        throwsA(isA<Exception>()),
      );
      expect(api.uploadCalls, 1);
      expect(api.closed, isTrue);
    },
  );
}

DriveUser _testUser(String email) => DriveUser(
  email: email,
  headersProvider: () async => {'Authorization': 'Bearer test-token'},
);

class _FakeSignInGateway implements DriveSignInGateway {
  _FakeSignInGateway({
    required this.signInResult,
    required this.silentResult,
    this.signInError,
    this.silentError,
  });

  final DriveUser? signInResult;
  final DriveUser? silentResult;
  final Object? signInError;
  final Object? silentError;

  int signInCalls = 0;
  int signInSilentlyCalls = 0;
  int signOutCalls = 0;

  @override
  Future<DriveUser?> signIn() async {
    signInCalls += 1;
    final error = signInError;
    if (error != null) throw error;
    return signInResult;
  }

  @override
  Future<DriveUser?> signInSilently() async {
    signInSilentlyCalls += 1;
    final error = silentError;
    if (error != null) throw error;
    return silentResult;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }
}

class _FakeDriveApiGateway implements DriveApiGateway {
  _FakeDriveApiGateway({
    this.folders = const [],
    this.listedFiles = const [],
    this.downloadPayloadById = const {},
    this.createdFolderId = 'created-folder',
    this.uploadedFileId = 'uploaded-file',
    this.autoGenerateUploadIds = false,
    this.findFoldersError,
  });

  final List<DriveFolderRef> folders;
  final List<DriveBackupFileRef> listedFiles;
  final Map<String, List<int>> downloadPayloadById;
  final String createdFolderId;
  final String? uploadedFileId;
  final bool autoGenerateUploadIds;
  final Object? findFoldersError;
  final Map<String, _StoredUpload> uploads = {};

  int findFoldersCalls = 0;
  int createFolderCalls = 0;
  int listFilesCalls = 0;
  int uploadCalls = 0;
  int downloadCalls = 0;

  String? lastCreatedFolderName;
  String? lastListFolderId;
  String? lastUploadName;
  String? lastUploadFolderId;
  int? lastUploadLength;
  int lastUploadedBytes = 0;
  String? lastUploadDescription;
  String? lastUploadMimeType;
  String? lastDownloadFileId;
  bool closed = false;

  @override
  Future<List<DriveFolderRef>> findFoldersByName(String folderName) async {
    findFoldersCalls += 1;
    final error = findFoldersError;
    if (error != null) throw error;
    return folders;
  }

  @override
  Future<String> createFolder(String folderName) async {
    createFolderCalls += 1;
    lastCreatedFolderName = folderName;
    return createdFolderId;
  }

  @override
  Future<List<DriveBackupFileRef>> listFilesInFolder(String folderId) async {
    listFilesCalls += 1;
    lastListFolderId = folderId;
    return [
      ...listedFiles,
      ...uploads.entries.map(
        (entry) => DriveBackupFileRef(
          id: entry.key,
          name: entry.value.name,
          modifiedTime: null,
          sizeBytes: entry.value.bytes.length,
        ),
      ),
    ];
  }

  @override
  Future<String?> uploadFile({
    required String name,
    required String folderId,
    required Stream<List<int>> stream,
    required int length,
    String? description,
    String? mimeType,
  }) async {
    uploadCalls += 1;
    lastUploadName = name;
    lastUploadFolderId = folderId;
    lastUploadLength = length;
    lastUploadDescription = description;
    lastUploadMimeType = mimeType;
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    lastUploadedBytes = bytes.length;
    final id = autoGenerateUploadIds ? 'upload-$uploadCalls' : uploadedFileId;
    if (id != null && id.trim().isNotEmpty) {
      uploads[id] = _StoredUpload(
        name: name,
        folderId: folderId,
        bytes: bytes,
        description: description,
        mimeType: mimeType,
      );
    }
    return id;
  }

  @override
  Future<Stream<List<int>>> downloadFileStream(String fileId) async {
    downloadCalls += 1;
    lastDownloadFileId = fileId;
    final payload =
        downloadPayloadById[fileId] ?? uploads[fileId]?.bytes ?? const <int>[];
    return Stream<List<int>>.value(payload);
  }

  @override
  void close() {
    closed = true;
  }
}

class _StoredUpload {
  const _StoredUpload({
    required this.name,
    required this.folderId,
    required this.bytes,
    this.description,
    this.mimeType,
  });

  final String name;
  final String folderId;
  final List<int> bytes;
  final String? description;
  final String? mimeType;

  _StoredUpload copyWith({List<int>? bytes}) {
    return _StoredUpload(
      name: name,
      folderId: folderId,
      bytes: bytes ?? this.bytes,
      description: description,
      mimeType: mimeType,
    );
  }
}
