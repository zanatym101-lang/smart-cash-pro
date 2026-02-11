import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../data/app_db.dart';

class DriveBackupService {
  DriveBackupService._();
  static final DriveBackupService instance = DriveBackupService._();

  static const String _iosClientId =
      '384868879764-7o2gae27cc56m14p273bjnq46ic59f68.apps.googleusercontent.com';

  GoogleSignIn get _signIn => GoogleSignIn(
        scopes: <String>[drive.DriveApi.driveFileScope],
        clientId: Platform.isIOS ? _iosClientId : null,
      );

  GoogleSignInAccount? _account;

  Future<GoogleSignInAccount?> signIn() async {
    _account = await _signIn.signIn();
    return _account;
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    _account = await _signIn.signInSilently();
    return _account;
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    _account = null;
  }

  Future<String?> currentEmail() async {
    if (_account != null) return _account!.email;
    final acc = await signInSilently();
    return acc?.email;
  }

  Future<_DriveClient> _api() async {
    final acc = _account ?? await signInSilently() ?? await signIn();
    if (acc == null) {
      throw Exception('لم يتم تسجيل الدخول إلى Google');
    }
    final headers = await acc.authHeaders;
    final client = _GoogleAuthClient(headers);
    final api = drive.DriveApi(client);
    return _DriveClient(api, client);
  }

  Future<String> _ensureFolder(drive.DriveApi api, String folderName) async {
    final res = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    final existing = res.files ?? [];
    if (existing.isNotEmpty && existing.first.id != null) {
      return existing.first.id!;
    }

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(folder);
    if (created.id == null) {
      throw Exception('تعذر إنشاء مجلد النسخ في Google Drive');
    }
    return created.id!;
  }

  String _backupName(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'smart_cash_backup_$y$m${d}_$h$min$s.db';
  }

  Future<String> uploadLatestBackup() async {
    final driveClient = await _api();
    final api = driveClient.api;
    try {
      final path = await AppDb.instance.exportBackup();
      final file = File(path);
      if (!await file.exists()) throw Exception('ملف النسخة غير موجود');

      final folderId = await _ensureFolder(api, 'Smart Cash Pro Backups');
      final name = _backupName(DateTime.now());
      final media = drive.Media(file.openRead(), await file.length());
      final driveFile = drive.File()
        ..name = name
        ..parents = <String>[folderId];
      final created = await api.files.create(driveFile, uploadMedia: media);
      if (created.id == null) {
        throw Exception('فشل رفع النسخة على Google Drive');
      }
      return created.id!;
    } finally {
      driveClient.client.close();
    }
  }
}

class _DriveClient {
  final drive.DriveApi api;
  final http.Client client;

  _DriveClient(this.api, this.client);
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
