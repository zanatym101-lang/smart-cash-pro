part of 'admin_settings_screen.dart';

extension _AdminSettingsBackupSection on _AdminSettingsScreenState {
  Future<void> _backupToFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    _setMountedState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportBackupToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم إنشاء نسخة احتياطية: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) _setMountedState(() => _backupWorking = false);
    }
  }

  Future<void> _backupToFolder() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    _setMountedState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportBackupToPath(dir);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم حفظ النسخة: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) _setMountedState(() => _backupWorking = false);
    }
  }

  Future<void> _backupJsonToFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    _setMountedState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportJsonBackupToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم إنشاء نسخة JSON: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) _setMountedState(() => _backupWorking = false);
    }
  }

  Future<void> _backupJsonToFolder() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    _setMountedState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportJsonBackupToPath(dir);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم حفظ نسخة JSON: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) _setMountedState(() => _backupWorking = false);
    }
  }

  Future<String?> _resolvePickedFilePath(
    PlatformFile file, {
    required String extensionHint,
  }) async {
    final rawPath = file.path?.trim();
    if (rawPath != null &&
        rawPath.isNotEmpty &&
        !rawPath.toLowerCase().startsWith('content://')) {
      return rawPath;
    }

    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.readStream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.readStream!) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    }
    if (bytes == null || bytes.isEmpty) return null;

    final tmpDir = await getTemporaryDirectory();
    final cleanName = (file.name.trim().isEmpty ? 'restore' : file.name.trim())
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final hasExt = cleanName.contains('.');
    final name = hasExt ? cleanName : '$cleanName.$extensionHint';
    final out = File(
      '${tmpDir.path}/restore_${DateTime.now().millisecondsSinceEpoch}_$name',
    );
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }

  bool _hasAllowedBackupExtension(
    PlatformFile file,
    List<String> allowedExtensions,
  ) {
    final name = file.name.toLowerCase();
    final path = (file.path ?? '').toLowerCase();
    for (final ext in allowedExtensions) {
      final dotExt = '.${ext.toLowerCase()}';
      if (name.endsWith(dotExt) || path.endsWith(dotExt)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _restoreFromFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin only')));
      return;
    }

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      withReadStream: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final picked = pick.files.single;
    if (!_hasAllowedBackupExtension(picked, const [
      'db',
      'sqlite',
      'sqlite3',
    ])) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selected file is not a database backup (.db/.sqlite/.sqlite3).',
          ),
        ),
      );
      return;
    }
    final sourcePath = picked.path?.trim();
    final path = await _resolvePickedFilePath(picked, extensionHint: 'db');
    final isTempRestoreFile =
        sourcePath == null ||
        sourcePath.isEmpty ||
        sourcePath.toLowerCase().startsWith('content://');
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot read backup file. Choose a local file and try again.',
          ),
        ),
      );
      return;
    }

    final ok = await _confirmDialog(
      title: 'Restore database backup?',
      body: 'Current data will be replaced by the selected backup file.',
      okText: 'Restore',
    );
    if (!ok) return;

    _setMountedState(() => _backupWorking = true);
    try {
      await AppDb.instance.restoreBackupFromPath(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore completed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (isTempRestoreFile) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) _setMountedState(() => _backupWorking = false);
    }
  }

  Future<void> _restoreFromJsonFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin only')));
      return;
    }

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      withReadStream: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final picked = pick.files.single;
    if (!_hasAllowedBackupExtension(picked, const ['json'])) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected file is not a JSON backup (.json).'),
        ),
      );
      return;
    }
    final sourcePath = picked.path?.trim();
    final path = await _resolvePickedFilePath(picked, extensionHint: 'json');
    final isTempRestoreFile =
        sourcePath == null ||
        sourcePath.isEmpty ||
        sourcePath.toLowerCase().startsWith('content://');
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot read JSON file. Choose a local JSON file and try again.',
          ),
        ),
      );
      return;
    }

    final ok = await _confirmDialog(
      title: 'Restore JSON backup?',
      body: 'Current data will be replaced by the selected JSON file.',
      okText: 'Restore',
    );
    if (!ok) return;

    _setMountedState(() => _backupWorking = true);
    try {
      await AppDb.instance.restoreJsonBackupFromPath(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore completed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (isTempRestoreFile) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) _setMountedState(() => _backupWorking = false);
    }
  }
}
