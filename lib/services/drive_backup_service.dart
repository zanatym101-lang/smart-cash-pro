import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../data/app_db.dart';

class DriveUser {
  final String email;
  final Future<Map<String, String>> Function() _headersProvider;

  DriveUser({
    required this.email,
    required Future<Map<String, String>> Function() headersProvider,
  }) : _headersProvider = headersProvider;

  Future<Map<String, String>> get authHeaders => _headersProvider();
}

class DriveFolderRef {
  final String id;
  final String name;

  const DriveFolderRef({required this.id, required this.name});
}

abstract class DriveSignInGateway {
  Future<DriveUser?> signIn();
  Future<DriveUser?> signInSilently();
  Future<void> signOut();
}

abstract class DriveApiGateway {
  Future<List<DriveFolderRef>> findFoldersByName(String folderName);

  Future<String> createFolder(String folderName);

  Future<String?> uploadFile({
    required String name,
    required String folderId,
    required Stream<List<int>> stream,
    required int length,
  });

  void close();
}

typedef DriveApiGatewayFactory =
    DriveApiGateway Function(Map<String, String> headers);

class DriveBackupService {
  DriveBackupService._({
    DriveSignInGateway? signInGateway,
    DriveApiGatewayFactory? apiFactory,
    Future<String> Function()? backupPathProvider,
    DateTime Function()? nowProvider,
  }) : _signInGateway = signInGateway ?? _GoogleSignInGateway(),
       _apiFactory = apiFactory ?? _GoogleDriveApiGateway.new,
       _backupPathProvider = backupPathProvider ?? AppDb.instance.exportBackup,
       _nowProvider = nowProvider ?? DateTime.now;

  static final DriveBackupService instance = DriveBackupService._();

  @visibleForTesting
  factory DriveBackupService.testable({
    required DriveSignInGateway signInGateway,
    required DriveApiGatewayFactory apiFactory,
    required Future<String> Function() backupPathProvider,
    DateTime Function()? nowProvider,
  }) {
    return DriveBackupService._(
      signInGateway: signInGateway,
      apiFactory: apiFactory,
      backupPathProvider: backupPathProvider,
      nowProvider: nowProvider,
    );
  }

  static const String _iosClientId =
      '384868879764-7o2gae27cc56m14p273bjnq46ic59f68.apps.googleusercontent.com';

  final DriveSignInGateway _signInGateway;
  final DriveApiGatewayFactory _apiFactory;
  final Future<String> Function() _backupPathProvider;
  final DateTime Function() _nowProvider;

  DriveUser? _account;

  Future<DriveUser?> signIn() async {
    _account = await _signInGateway.signIn();
    return _account;
  }

  Future<DriveUser?> signInSilently() async {
    _account = await _signInGateway.signInSilently();
    return _account;
  }

  Future<void> signOut() async {
    await _signInGateway.signOut();
    _account = null;
  }

  Future<String?> currentEmail() async {
    if (_account != null) return _account!.email;
    final acc = await signInSilently();
    return acc?.email;
  }

  Future<DriveApiGateway> _api() async {
    final acc = _account ?? await signInSilently() ?? await signIn();
    if (acc == null) {
      throw Exception('لم يتم تسجيل الدخول إلى Google');
    }
    final headers = await acc.authHeaders;
    return _apiFactory(headers);
  }

  Future<String> _ensureFolder(DriveApiGateway api, String folderName) async {
    final existing = await api.findFoldersByName(folderName);
    if (existing.isNotEmpty) {
      return existing.first.id;
    }
    final folderId = await api.createFolder(folderName);
    if (folderId.trim().isEmpty) {
      throw Exception('تعذر إنشاء مجلد النسخ في Google Drive');
    }
    return folderId;
  }

  @visibleForTesting
  String backupName(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'smart_cash_backup_$y$m${d}_$h$min$s.db';
  }

  Future<String> uploadLatestBackup() async {
    final api = await _api();
    try {
      final path = await _backupPathProvider();
      final file = File(path);
      if (!await file.exists()) throw Exception('ملف النسخة غير موجود');

      final folderId = await _ensureFolder(api, 'Smart Cash Pro Backups');
      final name = backupName(_nowProvider());
      final createdId = await api.uploadFile(
        name: name,
        folderId: folderId,
        stream: file.openRead(),
        length: await file.length(),
      );
      if (createdId == null || createdId.trim().isEmpty) {
        throw Exception('فشل رفع النسخة على Google Drive');
      }
      return createdId;
    } finally {
      api.close();
    }
  }
}

class _GoogleSignInGateway implements DriveSignInGateway {
  _GoogleSignInGateway({GoogleSignIn? signIn})
    : _signIn =
          signIn ??
          GoogleSignIn(
            scopes: <String>[drive.DriveApi.driveFileScope],
            clientId: Platform.isIOS ? DriveBackupService._iosClientId : null,
          );

  final GoogleSignIn _signIn;

  @override
  Future<DriveUser?> signIn() async {
    final account = await _signIn.signIn();
    return _toUser(account);
  }

  @override
  Future<DriveUser?> signInSilently() async {
    final account = await _signIn.signInSilently();
    return _toUser(account);
  }

  @override
  Future<void> signOut() => _signIn.signOut();

  DriveUser? _toUser(GoogleSignInAccount? account) {
    if (account == null) return null;
    return DriveUser(
      email: account.email,
      headersProvider: () => account.authHeaders,
    );
  }
}

class _GoogleDriveApiGateway implements DriveApiGateway {
  _GoogleDriveApiGateway(Map<String, String> headers) {
    _client = _GoogleAuthClient(headers);
    _api = drive.DriveApi(_client);
  }

  late final _GoogleAuthClient _client;
  late final drive.DriveApi _api;

  @override
  Future<List<DriveFolderRef>> findFoldersByName(String folderName) async {
    final res = await _api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    final files = res.files ?? <drive.File>[];
    return files
        .where((f) => f.id != null && f.name != null)
        .map((f) => DriveFolderRef(id: f.id!, name: f.name!))
        .toList();
  }

  @override
  Future<String> createFolder(String folderName) async {
    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await _api.files.create(folder);
    return created.id ?? '';
  }

  @override
  Future<String?> uploadFile({
    required String name,
    required String folderId,
    required Stream<List<int>> stream,
    required int length,
  }) async {
    final media = drive.Media(stream, length);
    final driveFile = drive.File()
      ..name = name
      ..parents = <String>[folderId];
    final created = await _api.files.create(driveFile, uploadMedia: media);
    return created.id;
  }

  @override
  void close() {
    _client.close();
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
