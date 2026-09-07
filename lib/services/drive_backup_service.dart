import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_env.dart';
import '../config/env_config.dart';
import '../data/app_db.dart';
import 'notification_service.dart';

typedef DriveAuthLogSink = void Function(Map<String, Object?> entry);

enum AutoBackupFrequency { daily, weekly, monthly }

enum AutoBackupPassphraseMode { manualRequired }

class DriveAuthException implements Exception {
  final String userMessage;
  final Object? cause;
  final DriveAuthDiagnostic? diagnostic;

  const DriveAuthException(this.userMessage, {this.cause, this.diagnostic});

  @override
  String toString() => userMessage;
}

class DriveAuthDiagnostic {
  final String phase;
  final String outcome;
  final String? exceptionType;
  final String? errorCode;
  final String? statusCode;
  final String? errorMessage;
  final String applicationId;
  final String buildMode;
  final String appEnv;
  final List<String> requestedScopes;
  final String platform;
  final bool silentSignInFailed;
  final bool interactiveSignInReturnedNull;
  final bool driveApiRequestFailedAfterLogin;

  const DriveAuthDiagnostic({
    required this.phase,
    required this.outcome,
    required this.exceptionType,
    required this.errorCode,
    required this.statusCode,
    required this.errorMessage,
    required this.applicationId,
    required this.buildMode,
    required this.appEnv,
    required this.requestedScopes,
    required this.platform,
    required this.silentSignInFailed,
    required this.interactiveSignInReturnedNull,
    required this.driveApiRequestFailedAfterLogin,
  });

  Map<String, Object?> toLogJson() => <String, Object?>{
    'area': 'google_drive_auth',
    'phase': phase,
    'outcome': outcome,
    'exceptionType': exceptionType,
    'errorCode': errorCode,
    'statusCode': statusCode,
    'errorMessage': errorMessage,
    'applicationId': applicationId,
    'buildMode': buildMode,
    'appEnv': appEnv,
    'requestedScopes': requestedScopes,
    'silentSignInFailed': silentSignInFailed,
    'interactiveSignInReturnedNull': interactiveSignInReturnedNull,
    'driveApiRequestFailedAfterLogin': driveApiRequestFailedAfterLogin,
    'likelyCause': likelyCause,
    'platform': platform,
  };

  String get likelyCause {
    final code = (errorCode ?? '').toLowerCase();
    final message = (errorMessage ?? '').toLowerCase();
    final status = statusCode ?? '';
    if (code.contains('12501') || code.contains('canceled')) {
      return 'User canceled Google sign-in.';
    }
    if (code.contains('10') ||
        code.contains('developer_error') ||
        message.contains('oauth client') ||
        message.contains('package') ||
        message.contains('sha')) {
      return 'Likely OAuth Android client mismatch: package name or signing SHA.';
    }
    if (status == '403' ||
        message.contains('access_not_configured') ||
        message.contains('api has not been used') ||
        message.contains('drive api')) {
      return 'Likely Google Drive API disabled, consent screen/test-user issue, or scope not allowed.';
    }
    if (message.contains('test user') || message.contains('not whitelisted')) {
      return 'Likely OAuth consent screen test user is missing.';
    }
    if (code.contains('network') ||
        code == '7' ||
        message.contains('network') ||
        message.contains('google play services')) {
      return 'Likely network or Google Play Services problem.';
    }
    if (interactiveSignInReturnedNull) {
      return 'Interactive Google sign-in returned no account.';
    }
    if (silentSignInFailed && outcome == 'blocked_not_signed_in') {
      return 'Silent sign-in failed and no interactive account was available.';
    }
    if (driveApiRequestFailedAfterLogin) {
      return 'Google sign-in succeeded, but a Drive API request failed after login.';
    }
    return 'Check Google Drive API, OAuth consent test user, drive.file scope, package name, and signing SHA.';
  }
}

class BackupIntegrityException implements Exception {
  final String message;

  const BackupIntegrityException([
    this.message = 'كلمة المرور غير صحيحة أو النسخة تالفة',
  ]);

  @override
  String toString() => message;
}

class BackupMetadata {
  final String backupId;
  final DateTime createdAt;
  final String appVersion;
  final String buildNumber;
  final String appEnv;
  final String deviceName;
  final int databaseVersion;
  final bool encrypted;
  final String checksum;
  final int sizeBytes;
  final String? note;
  final String? fileName;
  final String? metadataFileId;

  const BackupMetadata({
    required this.backupId,
    required this.createdAt,
    required this.appVersion,
    required this.buildNumber,
    required this.appEnv,
    required this.deviceName,
    required this.databaseVersion,
    required this.encrypted,
    required this.checksum,
    required this.sizeBytes,
    this.note,
    this.fileName,
    this.metadataFileId,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'backupId': backupId,
    'createdAt': createdAt.toIso8601String(),
    'appVersion': appVersion,
    'buildNumber': buildNumber,
    'appEnv': appEnv,
    'deviceName': deviceName,
    'databaseVersion': databaseVersion,
    'encrypted': encrypted,
    'checksum': checksum,
    'sizeBytes': sizeBytes,
    if (note != null && note!.trim().isNotEmpty) 'note': note,
    if (fileName != null && fileName!.trim().isNotEmpty) 'fileName': fileName,
    if (metadataFileId != null && metadataFileId!.trim().isNotEmpty)
      'metadataFileId': metadataFileId,
  };

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      backupId: (json['backupId'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: (json['appVersion'] ?? '').toString(),
      buildNumber: (json['buildNumber'] ?? '').toString(),
      appEnv: (json['appEnv'] ?? '').toString(),
      deviceName: (json['deviceName'] ?? '').toString(),
      databaseVersion:
          int.tryParse((json['databaseVersion'] ?? '').toString()) ?? 0,
      encrypted: json['encrypted'] == true,
      checksum: (json['checksum'] ?? '').toString(),
      sizeBytes: int.tryParse((json['sizeBytes'] ?? '').toString()) ?? 0,
      note: (json['note'] ?? '').toString().trim().isEmpty
          ? null
          : (json['note'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString().trim().isEmpty
          ? null
          : (json['fileName'] ?? '').toString(),
      metadataFileId: (json['metadataFileId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['metadataFileId'] ?? '').toString(),
    );
  }

  BackupMetadata copyWith({String? backupId, String? metadataFileId}) {
    return BackupMetadata(
      backupId: backupId ?? this.backupId,
      createdAt: createdAt,
      appVersion: appVersion,
      buildNumber: buildNumber,
      appEnv: appEnv,
      deviceName: deviceName,
      databaseVersion: databaseVersion,
      encrypted: encrypted,
      checksum: checksum,
      sizeBytes: sizeBytes,
      note: note,
      fileName: fileName,
      metadataFileId: metadataFileId ?? this.metadataFileId,
    );
  }
}

class AutoBackupSettings {
  final bool enabled;
  final AutoBackupFrequency frequency;
  final DateTime? lastRunAt;
  final AutoBackupPassphraseMode passphraseMode;

  const AutoBackupSettings({
    required this.enabled,
    required this.frequency,
    required this.lastRunAt,
    required this.passphraseMode,
  });

  static const defaults = AutoBackupSettings(
    enabled: false,
    frequency: AutoBackupFrequency.weekly,
    lastRunAt: null,
    passphraseMode: AutoBackupPassphraseMode.manualRequired,
  );

  DateTime nextDueAt(DateTime now) {
    final anchor = lastRunAt ?? now;
    switch (frequency) {
      case AutoBackupFrequency.daily:
        return anchor.add(const Duration(days: 1));
      case AutoBackupFrequency.weekly:
        return anchor.add(const Duration(days: 7));
      case AutoBackupFrequency.monthly:
        return DateTime(
          anchor.year,
          anchor.month + 1,
          anchor.day,
          anchor.hour,
          anchor.minute,
          anchor.second,
        );
    }
  }

  bool isDue(DateTime now) => enabled && !now.isBefore(nextDueAt(now));

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'frequency': frequency.name,
    'lastRunAt': lastRunAt?.toIso8601String(),
    'passphraseMode': passphraseMode.name,
  };

  factory AutoBackupSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return AutoBackupSettings(
      enabled: json['enabled'] == true,
      frequency: AutoBackupFrequency.values.firstWhere(
        (f) => f.name == (json['frequency'] ?? '').toString(),
        orElse: () => AutoBackupFrequency.weekly,
      ),
      lastRunAt: DateTime.tryParse((json['lastRunAt'] ?? '').toString()),
      passphraseMode: AutoBackupPassphraseMode.values.firstWhere(
        (m) => m.name == (json['passphraseMode'] ?? '').toString(),
        orElse: () => AutoBackupPassphraseMode.manualRequired,
      ),
    );
  }

  AutoBackupSettings copyWith({
    bool? enabled,
    AutoBackupFrequency? frequency,
    DateTime? lastRunAt,
    bool clearLastRunAt = false,
  }) {
    return AutoBackupSettings(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      lastRunAt: clearLastRunAt ? null : lastRunAt ?? this.lastRunAt,
      passphraseMode: passphraseMode,
    );
  }
}

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

class DriveBackupFileRef {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int? sizeBytes;

  const DriveBackupFileRef({
    required this.id,
    required this.name,
    required this.modifiedTime,
    required this.sizeBytes,
  });
}

abstract class DriveSignInGateway {
  Future<DriveUser?> signIn();
  Future<DriveUser?> signInSilently();
  Future<void> signOut();
}

abstract class DriveApiGateway {
  Future<List<DriveFolderRef>> findFoldersByName(String folderName);

  Future<String> createFolder(String folderName);

  Future<List<DriveBackupFileRef>> listFilesInFolder(String folderId);

  Future<String?> uploadFile({
    required String name,
    required String folderId,
    required Stream<List<int>> stream,
    required int length,
    String? description,
    String? mimeType,
  });

  Future<Stream<List<int>>> downloadFileStream(String fileId);

  void close();
}

typedef DriveApiGatewayFactory =
    DriveApiGateway Function(Map<String, String> headers);

class DriveBackupService {
  DriveBackupService._({
    DriveSignInGateway? signInGateway,
    DriveApiGatewayFactory? apiFactory,
    Future<String> Function()? backupPathProvider,
    Future<String> Function()? safetyBackupProvider,
    Future<void> Function(String path)? restorePathHandler,
    DateTime Function()? nowProvider,
    DriveAuthLogSink? authLogSink,
  }) : _signInGateway = signInGateway ?? _GoogleSignInGateway(),
       _apiFactory = apiFactory ?? _GoogleDriveApiGateway.new,
       _backupPathProvider = backupPathProvider ?? AppDb.instance.exportBackup,
       _safetyBackupProvider =
           safetyBackupProvider ?? _defaultSafetyBackupProvider,
       _restorePathHandler =
           restorePathHandler ?? AppDb.instance.restoreBackupFromPath,
       _nowProvider = nowProvider ?? DateTime.now,
       _authLogSink =
           authLogSink ??
           ((entry) {
             final outcome = entry['outcome']?.toString() ?? '';
             final isBackupEvent = entry['area'] == 'google_drive_backup';
             final isAuthEvent = entry['area'] == 'google_drive_auth';
             final isFailure =
                 outcome.contains('failure') ||
                 outcome.contains('blocked') ||
                 outcome.contains('after_retry');
             if (kDebugMode && (isAuthEvent && isFailure || isBackupEvent)) {
               debugPrint('drive_log=${entry.toString()}');
             }
           });

  static final DriveBackupService instance = DriveBackupService._();

  @visibleForTesting
  factory DriveBackupService.testable({
    required DriveSignInGateway signInGateway,
    required DriveApiGatewayFactory apiFactory,
    required Future<String> Function() backupPathProvider,
    Future<String> Function()? safetyBackupProvider,
    Future<void> Function(String path)? restorePathHandler,
    DateTime Function()? nowProvider,
    DriveAuthLogSink? authLogSink,
  }) {
    return DriveBackupService._(
      signInGateway: signInGateway,
      apiFactory: apiFactory,
      backupPathProvider: backupPathProvider,
      safetyBackupProvider: safetyBackupProvider,
      restorePathHandler: restorePathHandler,
      nowProvider: nowProvider,
      authLogSink: authLogSink,
    );
  }

  static const String _iosClientId =
      '384868879764-7o2gae27cc56m14p273bjnq46ic59f68.apps.googleusercontent.com';
  static const String _backupFolderName = 'Smart Cash Pro Backups';
  static const String _autoBackupSettingsKey = 'googleDriveAutoBackup';
  static const int _databaseVersion = 3;
  static const List<String> driveScopes = <String>[
    drive.DriveApi.driveFileScope,
  ];

  final DriveSignInGateway _signInGateway;
  final DriveApiGatewayFactory _apiFactory;
  final Future<String> Function() _backupPathProvider;
  final Future<String> Function() _safetyBackupProvider;
  final Future<void> Function(String path) _restorePathHandler;
  final DateTime Function() _nowProvider;
  final DriveAuthLogSink _authLogSink;

  DriveUser? _account;
  DriveAuthDiagnostic? _lastAuthDiagnostic;
  bool _silentSignInFailed = false;
  bool _interactiveSignInReturnedNull = false;
  bool _driveApiRequestFailedAfterLogin = false;

  DriveAuthDiagnostic? get lastAuthDiagnostic => _lastAuthDiagnostic;

  static Future<String> _defaultSafetyBackupProvider() async {
    final dir = await getApplicationSupportDirectory();
    return AppDb.instance.exportBackupToPath(dir.path);
  }

  Future<DriveUser?> signIn() async {
    await _logAuth('interactive_sign_in', 'start');
    try {
      _account = await _signInGateway.signIn();
      if (_account == null) _interactiveSignInReturnedNull = true;
      await _logAuth(
        'interactive_sign_in',
        _account == null ? 'no_account' : 'success',
      );
      if (_account != null) return _account;

      await _signInGateway.signOut();
      await _logAuth('interactive_sign_in', 'retry_after_no_account');
      _account = await _signInGateway.signIn();
      if (_account == null) _interactiveSignInReturnedNull = true;
      await _logAuth(
        'interactive_sign_in',
        _account == null ? 'no_account_after_retry' : 'success_after_retry',
      );
      return _account;
    } catch (e) {
      await _logAuth('interactive_sign_in', 'failure', error: e);
      try {
        await _signInGateway.signOut();
        await _logAuth('interactive_sign_in', 'retry_after_failure');
        _account = await _signInGateway.signIn();
        if (_account == null) _interactiveSignInReturnedNull = true;
        await _logAuth(
          'interactive_sign_in',
          _account == null ? 'no_account_after_retry' : 'success_after_retry',
        );
        return _account;
      } catch (retryError) {
        final diagnostic = await _logAuth(
          'interactive_sign_in',
          'retry_failure',
          error: retryError,
        );
        throw DriveAuthException(
          'تعذر تسجيل الدخول إلى Google Drive',
          cause: retryError,
          diagnostic: diagnostic,
        );
      }
    }
  }

  Future<DriveUser?> signInSilently() async {
    await _logAuth('silent_sign_in', 'start');
    try {
      _account = await _signInGateway.signInSilently();
      await _logAuth(
        'silent_sign_in',
        _account == null ? 'no_account' : 'success',
      );
      return _account;
    } catch (e) {
      _silentSignInFailed = true;
      await _logAuth('silent_sign_in', 'failure', error: e);
      _account = null;
      return null;
    }
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
      final diagnostic = await _logAuth('api_auth', 'blocked_not_signed_in');
      throw DriveAuthException(
        'تعذر تسجيل الدخول إلى Google Drive',
        diagnostic: diagnostic,
      );
    }
    try {
      final headers = await acc.authHeaders;
      return _apiFactory(headers);
    } catch (e) {
      _driveApiRequestFailedAfterLogin = true;
      final diagnostic = await _logAuth(
        'api_auth_headers',
        'failure_after_login',
        error: e,
      );
      throw DriveAuthException(
        'تعذر تسجيل الدخول إلى Google Drive',
        cause: e,
        diagnostic: diagnostic,
      );
    }
  }

  Future<DriveAuthDiagnostic> _logAuth(
    String phase,
    String outcome, {
    Object? error,
  }) async {
    final diagnostic = DriveAuthDiagnostic(
      phase: phase,
      outcome: outcome,
      exceptionType: error?.runtimeType.toString(),
      errorCode: _errorCode(error),
      statusCode: _statusCode(error),
      errorMessage: _safeErrorMessage(error),
      applicationId: await _currentApplicationId(),
      buildMode: _buildMode,
      appEnv: EnvConfig.labelFor(currentEnv),
      requestedScopes: driveScopes,
      platform: kIsWeb
          ? 'web'
          : Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : Platform.operatingSystem,
      silentSignInFailed: _silentSignInFailed,
      interactiveSignInReturnedNull: _interactiveSignInReturnedNull,
      driveApiRequestFailedAfterLogin: _driveApiRequestFailedAfterLogin,
    );
    _lastAuthDiagnostic = diagnostic;
    _authLogSink(diagnostic.toLogJson());
    return diagnostic;
  }

  Future<String> _currentApplicationId() async {
    try {
      return (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {
      return 'unknown';
    }
  }

  String get _buildMode {
    if (kDebugMode) return 'debug';
    if (kProfileMode) return 'profile';
    return 'release';
  }

  String? _errorCode(Object? error) {
    if (error == null) return null;
    if (error is PlatformException) return error.code;
    if (error is drive.DetailedApiRequestError) {
      return error.status.toString();
    }
    return error.runtimeType.toString();
  }

  String? _statusCode(Object? error) {
    if (error == null) return null;
    if (error is drive.DetailedApiRequestError) {
      return error.status.toString();
    }
    if (error is PlatformException) {
      final details = error.details;
      if (details is Map) {
        final value =
            details['statusCode'] ?? details['status'] ?? details['errorCode'];
        if (value != null) return value.toString();
      }
    }
    final raw = error.toString();
    final match = RegExp(
      r'(?:status|statusCode|code|HTTP)[^\d]*(\d{3})',
      caseSensitive: false,
    ).firstMatch(raw);
    return match?.group(1);
  }

  String? _safeErrorMessage(Object? error) {
    if (error == null) return null;
    final raw = error is PlatformException
        ? (error.message ?? error.details?.toString() ?? error.code)
        : error.toString();
    return raw
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'),
          'Bearer [redacted]',
        )
        .replaceAll(
          RegExp(r'access[_-]?token[=:]\s*[A-Za-z0-9._~+/=-]+'),
          'access_token=[redacted]',
        )
        .replaceAll(
          RegExp(r'id[_-]?token[=:]\s*[A-Za-z0-9._~+/=-]+'),
          'id_token=[redacted]',
        );
  }

  Future<T> _driveApiCall<T>(String phase, Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      _driveApiRequestFailedAfterLogin = true;
      final diagnostic = await _logAuth(phase, 'failure_after_login', error: e);
      throw DriveAuthException(
        'تعذر تسجيل الدخول إلى Google Drive',
        cause: e,
        diagnostic: diagnostic,
      );
    }
  }

  Future<String> _ensureFolder(DriveApiGateway api, String folderName) async {
    final existing = await _driveApiCall(
      'drive_api_find_folder',
      () => api.findFoldersByName(folderName),
    );
    if (existing.isNotEmpty) {
      return existing.first.id;
    }
    final folderId = await _driveApiCall(
      'drive_api_create_folder',
      () => api.createFolder(folderName),
    );
    if (folderId.trim().isEmpty) {
      throw Exception('تعذر إنشاء مجلد النسخ في Google Drive');
    }
    return folderId;
  }

  Future<String?> _findFolderId(DriveApiGateway api, String folderName) async {
    final existing = await _driveApiCall(
      'drive_api_find_folder',
      () => api.findFoldersByName(folderName),
    );
    if (existing.isEmpty) return null;
    return existing.first.id;
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

  @visibleForTesting
  String encryptedBackupName(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return 'smart_cash_pro_backup_$y-$m-${d}_$h-$min.enc';
  }

  String _metadataNameFor(String encryptedName) {
    return encryptedName.endsWith('.enc')
        ? '${encryptedName.substring(0, encryptedName.length - 4)}.json'
        : '$encryptedName.json';
  }

  Future<BackupMetadata> createEncryptedDriveBackup(
    String passphrase, {
    String? note,
  }) async {
    _logBackup('backup_started', {'encrypted': true, 'target': 'drive'});
    final api = await _api();
    try {
      final prepared = await _prepareEncryptedBackup(
        passphrase: passphrase,
        note: note,
      );
      final folderId = await _ensureFolder(api, _backupFolderName);
      final encryptedId = await _driveApiCall(
        'drive_api_upload_backup',
        () => api.uploadFile(
          name: prepared.fileName,
          folderId: folderId,
          stream: Stream<List<int>>.value(prepared.encryptedBytes),
          length: prepared.encryptedBytes.length,
          description: jsonEncode(prepared.metadata.toJson()),
          mimeType: 'application/octet-stream',
        ),
      );
      if (encryptedId == null || encryptedId.trim().isEmpty) {
        throw Exception('فشل رفع النسخة على Google Drive');
      }
      final metadata = prepared.metadata.copyWith(backupId: encryptedId);
      final metadataBytes = utf8.encode(jsonEncode(metadata.toJson()));
      final metadataId = await _driveApiCall(
        'drive_api_upload_metadata',
        () => api.uploadFile(
          name: _metadataNameFor(prepared.fileName),
          folderId: folderId,
          stream: Stream<List<int>>.value(metadataBytes),
          length: metadataBytes.length,
          description: 'Smart Cash Pro encrypted backup metadata',
          mimeType: 'application/json',
        ),
      );
      final finalMetadata = metadata.copyWith(metadataFileId: metadataId);
      await _markAutoBackupRunIfEnabled(finalMetadata.createdAt);
      _logBackup('backup_success', {
        'encrypted': true,
        'target': 'drive',
        'backupId': finalMetadata.backupId,
        'sizeBytes': finalMetadata.sizeBytes,
      });
      return finalMetadata;
    } catch (e) {
      _logBackup('backup_failed', {
        'encrypted': true,
        'target': 'drive',
        'error': _safeErrorMessage(e),
      });
      rethrow;
    } finally {
      api.close();
    }
  }

  Future<String> createEncryptedLocalBackup(
    String passphrase, {
    String? note,
  }) async {
    _logBackup('backup_started', {'encrypted': true, 'target': 'local'});
    try {
      final prepared = await _prepareEncryptedBackup(
        passphrase: passphrase,
        note: note,
      );
      final dir = await getApplicationSupportDirectory();
      final encryptedPath = '${dir.path}/${prepared.fileName}';
      final encryptedFile = File(encryptedPath);
      await encryptedFile.writeAsBytes(prepared.encryptedBytes, flush: true);
      final metadataPath = '${dir.path}/${_metadataNameFor(prepared.fileName)}';
      await File(
        metadataPath,
      ).writeAsString(jsonEncode(prepared.metadata.toJson()), flush: true);
      _logBackup('backup_success', {
        'encrypted': true,
        'target': 'local',
        'path': encryptedPath,
        'sizeBytes': prepared.metadata.sizeBytes,
      });
      return encryptedPath;
    } catch (e) {
      _logBackup('backup_failed', {
        'encrypted': true,
        'target': 'local',
        'error': _safeErrorMessage(e),
      });
      rethrow;
    }
  }

  Future<List<BackupMetadata>> listDriveBackups() async {
    final api = await _api();
    try {
      final folderId = await _findFolderId(api, _backupFolderName);
      if (folderId == null || folderId.trim().isEmpty) return const [];
      final files = await _driveApiCall(
        'drive_api_list_backups',
        () => api.listFilesInFolder(folderId),
      );
      final metadataFiles = files
          .where((file) => file.name.endsWith('.json'))
          .toList(growable: false);
      final backups = <BackupMetadata>[];
      for (final file in metadataFiles) {
        try {
          final raw = await _downloadFileAsString(api, file.id);
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;
          final metadata = BackupMetadata.fromJson(decoded);
          if (!metadata.encrypted || metadata.backupId.trim().isEmpty) {
            continue;
          }
          backups.add(metadata.copyWith(metadataFileId: file.id));
        } catch (_) {
          continue;
        }
      }
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return backups;
    } finally {
      api.close();
    }
  }

  Future<void> restoreEncryptedDriveBackup({
    required String backupId,
    required String passphrase,
  }) async {
    _logBackup('restore_started', {'encrypted': true, 'backupId': backupId});
    final api = await _api();
    String? tempPath;
    try {
      final encryptedBytes = await _downloadFileAsBytes(api, backupId);
      final decoded = await _decryptDriveBackup(
        encryptedBytes: encryptedBytes,
        passphrase: passphrase,
      );
      final dbBytes = decoded.databaseBytes;
      final checksum = sha256.convert(dbBytes).toString().toLowerCase();
      if (checksum != decoded.metadata.checksum.toLowerCase()) {
        throw const BackupIntegrityException();
      }

      await _safetyBackupProvider();
      Directory dir;
      try {
        dir = await getTemporaryDirectory();
      } catch (_) {
        dir = Directory.systemTemp;
      }
      tempPath =
          '${dir.path}/drive_restore_${DateTime.now().millisecondsSinceEpoch}.db';
      await File(tempPath).writeAsBytes(dbBytes, flush: true);
      await _restorePathHandler(tempPath);
      _logBackup('restore_success', {
        'encrypted': true,
        'backupId': backupId,
        'safetyBackupCreated': true,
      });
    } on crypt.SecretBoxAuthenticationError {
      _logBackup('restore_failed', {
        'encrypted': true,
        'backupId': backupId,
        'error': 'auth_failed',
      });
      throw const BackupIntegrityException();
    } on BackupIntegrityException {
      _logBackup('restore_failed', {
        'encrypted': true,
        'backupId': backupId,
        'error': 'integrity_failed',
      });
      rethrow;
    } catch (e) {
      _logBackup('restore_failed', {
        'encrypted': true,
        'backupId': backupId,
        'error': _safeErrorMessage(e),
      });
      rethrow;
    } finally {
      if (tempPath != null) {
        try {
          final file = File(tempPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      api.close();
    }
  }

  Future<AutoBackupSettings> getAutoBackupSettings() async {
    final raw = await AppDb.instance.readRawSettingsMap();
    final value = raw[_autoBackupSettingsKey];
    return AutoBackupSettings.fromJson(
      value is Map
          ? value.map((key, value) => MapEntry(key.toString(), value))
          : null,
    );
  }

  Future<void> setAutoBackupSettings(AutoBackupSettings settings) async {
    final raw = await AppDb.instance.readRawSettingsMap();
    raw[_autoBackupSettingsKey] = settings.toJson();
    await AppDb.instance.writeRawSettingsMap(raw);
  }

  Future<bool> isAutoBackupDue() async {
    final settings = await getAutoBackupSettings();
    return settings.isDue(_nowProvider());
  }

  Future<void> showAutoBackupReminderIfDue() async {
    final due = await isAutoBackupDue();
    if (!due) return;
    _logBackup('auto_backup_due', {'passphraseMode': 'manualRequired'});
    await NotificationService.show(
      title: 'حان وقت النسخ الاحتياطي',
      body: 'افتح النسخ الاحتياطي وأدخل كلمة المرور لإنشاء نسخة مشفرة.',
    );
  }

  Future<void> _markAutoBackupRunIfEnabled(DateTime ranAt) async {
    try {
      final settings = await getAutoBackupSettings();
      if (!settings.enabled) return;
      await setAutoBackupSettings(settings.copyWith(lastRunAt: ranAt));
    } catch (_) {
      // Backup creation should not fail just because reminder settings
      // cannot be read or written.
    }
  }

  Future<_PreparedDriveBackup> _prepareEncryptedBackup({
    required String passphrase,
    String? note,
  }) async {
    _validatePassphrase(passphrase);
    final exportedPath = await _backupPathProvider();
    final dbBytes = await File(exportedPath).readAsBytes();
    final checksum = sha256.convert(dbBytes).toString().toLowerCase();
    final now = _nowProvider();
    final fileName = encryptedBackupName(now);
    final packageInfo = await _packageInfo();
    final metadata = BackupMetadata(
      backupId: 'pending',
      createdAt: now,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      appEnv: EnvConfig.labelFor(currentEnv),
      deviceName: await _deviceName(),
      databaseVersion: _databaseVersion,
      encrypted: true,
      checksum: checksum,
      sizeBytes: dbBytes.length,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      fileName: fileName,
    );
    Map<String, dynamic> safeSettings = const <String, dynamic>{};
    try {
      safeSettings = _safeSettingsForBackup(
        await AppDb.instance.readRawSettingsMap(),
      );
    } catch (_) {
      safeSettings = const <String, dynamic>{};
    }

    final payload = <String, dynamic>{
      'format': 'smart_cash_pro_drive_backup_payload_v1',
      'metadata': metadata.toJson(),
      'checksum': checksum,
      'databaseBase64': base64Encode(dbBytes),
      'settings': safeSettings,
    };
    final encryptedBytes = await _encryptPayload(
      payload: utf8.encode(jsonEncode(payload)),
      passphrase: passphrase,
    );
    return _PreparedDriveBackup(
      fileName: fileName,
      encryptedBytes: encryptedBytes,
      metadata: metadata,
    );
  }

  Future<List<int>> _encryptPayload({
    required List<int> payload,
    required String passphrase,
  }) async {
    const iterations = 150000;
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final key = await _deriveKey(
      passphrase: passphrase,
      salt: salt,
      iterations: iterations,
    );
    final box = await crypt.AesGcm.with256bits().encrypt(
      payload,
      secretKey: key,
      nonce: nonce,
    );
    final envelope = <String, dynamic>{
      'format': 'smart_cash_pro_drive_backup_v1',
      'cipher': 'aes_gcm_256',
      'kdf': 'pbkdf2_hmac_sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    return utf8.encode(jsonEncode(envelope));
  }

  Future<_DecryptedDriveBackup> _decryptDriveBackup({
    required List<int> encryptedBytes,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    try {
      final envelope = jsonDecode(utf8.decode(encryptedBytes));
      if (envelope is! Map<String, dynamic> ||
          envelope['format'] != 'smart_cash_pro_drive_backup_v1') {
        throw const BackupIntegrityException();
      }
      final iterations =
          int.tryParse((envelope['iterations'] ?? '').toString()) ?? 150000;
      final salt = base64Decode((envelope['salt'] ?? '').toString());
      final nonce = base64Decode((envelope['nonce'] ?? '').toString());
      final cipherText = base64Decode(
        (envelope['cipherText'] ?? '').toString(),
      );
      final mac = base64Decode((envelope['mac'] ?? '').toString());
      final key = await _deriveKey(
        passphrase: passphrase,
        salt: salt,
        iterations: iterations,
      );
      final clear = await crypt.AesGcm.with256bits().decrypt(
        crypt.SecretBox(cipherText, nonce: nonce, mac: crypt.Mac(mac)),
        secretKey: key,
      );
      final payload = jsonDecode(utf8.decode(clear));
      if (payload is! Map<String, dynamic>) {
        throw const BackupIntegrityException();
      }
      final metadataRaw = payload['metadata'];
      if (metadataRaw is! Map<String, dynamic>) {
        throw const BackupIntegrityException();
      }
      final dbBase64 = (payload['databaseBase64'] ?? '').toString();
      final databaseBytes = base64Decode(dbBase64);
      final metadata = BackupMetadata.fromJson(metadataRaw);
      final checksum = (payload['checksum'] ?? '').toString().toLowerCase();
      if (checksum.isEmpty ||
          checksum != sha256.convert(databaseBytes).toString().toLowerCase()) {
        throw const BackupIntegrityException();
      }
      return _DecryptedDriveBackup(
        metadata: metadata,
        databaseBytes: databaseBytes,
      );
    } on crypt.SecretBoxAuthenticationError {
      throw const BackupIntegrityException();
    } on FormatException {
      throw const BackupIntegrityException();
    }
  }

  Future<crypt.SecretKey> _deriveKey({
    required String passphrase,
    required List<int> salt,
    required int iterations,
  }) {
    return crypt.Pbkdf2(
      macAlgorithm: crypt.Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(
      secretKey: crypt.SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  void _validatePassphrase(String passphrase) {
    if (passphrase.trim().length < 8) {
      throw Exception('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
    }
  }

  Future<String> _downloadFileAsString(
    DriveApiGateway api,
    String fileId,
  ) async {
    return utf8.decode(await _downloadFileAsBytes(api, fileId));
  }

  Future<List<int>> _downloadFileAsBytes(
    DriveApiGateway api,
    String fileId,
  ) async {
    final stream = await _driveApiCall(
      'drive_api_download_backup',
      () => api.downloadFileStream(fileId),
    );
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return chunks;
  }

  Future<PackageInfo> _packageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return PackageInfo(
        appName: 'Smart Cash Pro',
        packageName: 'unknown',
        version: 'unknown',
        buildNumber: 'unknown',
      );
    }
  }

  Future<String> _deviceName() async {
    try {
      return Platform.localHostname.trim().isEmpty
          ? Platform.operatingSystem
          : Platform.localHostname;
    } catch (_) {
      return 'unknown';
    }
  }

  Map<String, dynamic> _safeSettingsForBackup(Map<String, dynamic> settings) {
    final copy = Map<String, dynamic>.from(settings);
    copy.remove('backupMeta');
    copy.remove('secureRestoreGuard');
    copy.remove('adminPinGuard');
    copy.remove(_autoBackupSettingsKey);
    final licenseRaw = copy['license'];
    if (licenseRaw is Map) {
      final license = Map<String, dynamic>.from(
        licenseRaw.map((key, value) => MapEntry(key.toString(), value)),
      );
      for (final key in List<String>.from(license.keys)) {
        if (key.toLowerCase().contains('token') ||
            key.toLowerCase().contains('auth') ||
            key == 'activationCode' ||
            key == 'cloudDeviceId') {
          license.remove(key);
        }
      }
      copy['license'] = license;
    }
    return copy;
  }

  void _logBackup(String event, Map<String, Object?> fields) {
    final sanitized = Map<String, Object?>.from(fields)
      ..remove('passphrase')
      ..remove('key')
      ..remove('token');
    _authLogSink({'area': 'google_drive_backup', 'event': event, ...sanitized});
  }

  Future<String> uploadLatestBackup() async {
    final api = await _api();
    try {
      final path = await _backupPathProvider();
      final file = File(path);
      if (!await file.exists()) throw Exception('ملف النسخة غير موجود');

      final folderId = await _ensureFolder(api, _backupFolderName);
      final name = backupName(_nowProvider());
      final createdId = await _driveApiCall(
        'drive_api_upload_backup',
        () => api.uploadFile(
          name: name,
          folderId: folderId,
          stream: file.openRead(),
          length: file.lengthSync(),
        ),
      );
      if (createdId == null || createdId.trim().isEmpty) {
        throw Exception('فشل رفع النسخة على Google Drive');
      }
      return createdId;
    } finally {
      api.close();
    }
  }

  Future<List<DriveBackupFileRef>> listBackups() async {
    final api = await _api();
    try {
      final folderId = await _findFolderId(api, _backupFolderName);
      if (folderId == null || folderId.trim().isEmpty) return const [];
      final files = <DriveBackupFileRef>[
        ...await _driveApiCall(
          'drive_api_list_backups',
          () => api.listFilesInFolder(folderId),
        ),
      ];
      files.removeWhere(
        (file) =>
            file.name.toLowerCase().endsWith('.enc') ||
            file.name.toLowerCase().endsWith('.json'),
      );
      files.sort((a, b) {
        final am = a.modifiedTime;
        final bm = b.modifiedTime;
        if (am == null && bm == null) return b.name.compareTo(a.name);
        if (am == null) return 1;
        if (bm == null) return -1;
        return bm.compareTo(am);
      });
      return files;
    } finally {
      api.close();
    }
  }

  Future<String> downloadBackupToTemporary({
    required String fileId,
    required String fileName,
  }) async {
    final api = await _api();
    IOSink? sink;
    try {
      final stream = await _driveApiCall(
        'drive_api_download_backup',
        () => api.downloadFileStream(fileId),
      );
      Directory tmpDir;
      try {
        tmpDir = await getTemporaryDirectory();
      } catch (_) {
        tmpDir = Directory.systemTemp;
      }
      final cleanName = (fileName.trim().isEmpty ? 'backup.db' : fileName)
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final safeName = cleanName.toLowerCase().endsWith('.db')
          ? cleanName
          : '$cleanName.db';
      final out = File(
        '${tmpDir.path}/drive_restore_${DateTime.now().millisecondsSinceEpoch}_$safeName',
      );
      sink = out.openWrite();
      await sink.addStream(stream);
      await sink.flush();
      await sink.close();
      return out.path;
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      api.close();
    }
  }
}

class _PreparedDriveBackup {
  final String fileName;
  final List<int> encryptedBytes;
  final BackupMetadata metadata;

  const _PreparedDriveBackup({
    required this.fileName,
    required this.encryptedBytes,
    required this.metadata,
  });
}

class _DecryptedDriveBackup {
  final BackupMetadata metadata;
  final List<int> databaseBytes;

  const _DecryptedDriveBackup({
    required this.metadata,
    required this.databaseBytes,
  });
}

class _GoogleSignInGateway implements DriveSignInGateway {
  _GoogleSignInGateway({GoogleSignIn? signIn})
    : _signIn =
          signIn ??
          GoogleSignIn(
            scopes: DriveBackupService.driveScopes,
            clientId: !kIsWeb && Platform.isIOS
                ? DriveBackupService._iosClientId
                : null,
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
  Future<List<DriveBackupFileRef>> listFilesInFolder(String folderId) async {
    final res = await _api.files.list(
      q: "'$folderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime, size)',
      orderBy: 'modifiedTime desc,name',
    );
    final files = res.files ?? <drive.File>[];
    return files
        .where((f) => f.id != null && f.name != null)
        .map(
          (f) => DriveBackupFileRef(
            id: f.id!,
            name: f.name!,
            modifiedTime: f.modifiedTime,
            sizeBytes: f.size == null ? null : int.tryParse(f.size!),
          ),
        )
        .toList();
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
    final media = drive.Media(stream, length);
    final driveFile = drive.File()
      ..name = name
      ..parents = <String>[folderId]
      ..description = description
      ..mimeType = mimeType;
    final created = await _api.files.create(driveFile, uploadMedia: media);
    return created.id;
  }

  @override
  Future<Stream<List<int>>> downloadFileStream(String fileId) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (media is! drive.Media) {
      throw Exception('تعذر تنزيل الملف من Google Drive');
    }
    return media.stream;
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
