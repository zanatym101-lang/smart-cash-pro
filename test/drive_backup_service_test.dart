import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/drive_backup_service.dart';

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
  _FakeSignInGateway({required this.signInResult, required this.silentResult});

  final DriveUser? signInResult;
  final DriveUser? silentResult;

  int signInCalls = 0;
  int signInSilentlyCalls = 0;
  int signOutCalls = 0;

  @override
  Future<DriveUser?> signIn() async {
    signInCalls += 1;
    return signInResult;
  }

  @override
  Future<DriveUser?> signInSilently() async {
    signInSilentlyCalls += 1;
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
    this.createdFolderId = 'created-folder',
    this.uploadedFileId = 'uploaded-file',
  });

  final List<DriveFolderRef> folders;
  final String createdFolderId;
  final String? uploadedFileId;

  int findFoldersCalls = 0;
  int createFolderCalls = 0;
  int uploadCalls = 0;

  String? lastCreatedFolderName;
  String? lastUploadName;
  String? lastUploadFolderId;
  int? lastUploadLength;
  int lastUploadedBytes = 0;
  bool closed = false;

  @override
  Future<List<DriveFolderRef>> findFoldersByName(String folderName) async {
    findFoldersCalls += 1;
    return folders;
  }

  @override
  Future<String> createFolder(String folderName) async {
    createFolderCalls += 1;
    lastCreatedFolderName = folderName;
    return createdFolderId;
  }

  @override
  Future<String?> uploadFile({
    required String name,
    required String folderId,
    required Stream<List<int>> stream,
    required int length,
  }) async {
    uploadCalls += 1;
    lastUploadName = name;
    lastUploadFolderId = folderId;
    lastUploadLength = length;
    lastUploadedBytes = await stream.fold<int>(
      0,
      (sum, chunk) => sum + chunk.length,
    );
    return uploadedFileId;
  }

  @override
  void close() {
    closed = true;
  }
}
