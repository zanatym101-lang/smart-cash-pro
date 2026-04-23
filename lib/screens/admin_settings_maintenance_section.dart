part of 'admin_settings_screen.dart';

extension _AdminSettingsMaintenanceSection on _AdminSettingsScreenState {
  String _fmtDateTime(DateTime? d) {
    if (d == null) return 'غير متوفر';
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $h:$min';
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _runIntegrityNow() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    _setMountedState(() => _healthWorking = true);
    try {
      final result = await AppDb.instance.runIntegrityCheck(force: true);
      await _loadHealth();
      if (!mounted) return;
      if (result.ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فحص السلامة: سليم ✅')));
      } else {
        final first = result.issues.isEmpty
            ? 'تم اكتشاف مشاكل'
            : result.issues.first.message;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فحص السلامة: $first')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل فحص السلامة: $e')));
    } finally {
      if (mounted) _setMountedState(() => _healthWorking = false);
    }
  }

  Future<void> _repairIntegrityNow() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final ok = await _confirmDialog(
      title: 'إصلاح تلقائي',
      body:
          'سيتم إنشاء نسخة JSON احتياطية أولًا، ثم محاولة إصلاح مشاكل التكرار في المعرفات.',
      okText: 'ابدأ الإصلاح',
    );
    if (!ok) return;

    _setMountedState(() => _healthWorking = true);
    try {
      final result = await AppDb.instance.repairDuplicateIntegrityIssues(
        createJsonBackup: true,
      );
      await _loadHealth();
      if (!mounted) return;
      if (!result.changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد مشاكل تكرار تحتاج إصلاحًا')),
        );
        return;
      }
      final totalFixed =
          result.walletsFixed +
          result.txnsFixed +
          result.claimsFixed +
          result.dailyClosesFixed;
      final status = result.after.ok
          ? 'والفحص بعد الإصلاح سليم ✅'
          : 'ولا تزال هناك مشاكل أخرى';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الإصلاح ($totalFixed) $status')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الإصلاح: $e')));
    } finally {
      if (mounted) _setMountedState(() => _healthWorking = false);
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String body,
    required String okText,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _resetDatabase() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    final ok = await _confirmDialog(
      title: 'تصفير البيانات (مع بيانات البداية)؟',
      body: 'سيتم حذف قاعدة البيانات ثم إنشاء بيانات بداية افتراضية.',
      okText: 'تصفير',
    );
    if (!ok) return;

    _setMountedState(() => _saving = true);
    try {
      await AppDb.instance.resetDatabase();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تصفير البيانات ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) _setMountedState(() => _saving = false);
    }
  }

  Future<void> _resetDatabaseEmpty() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    final ok = await _confirmDialog(
      title: 'تصفير كامل بدون بيانات؟',
      body: 'سيتم حذف قاعدة البيانات بدون إنشاء أي بيانات بداية.',
      okText: 'تصفير كامل',
    );
    if (!ok) return;

    _setMountedState(() => _saving = true);
    try {
      await AppDb.instance.resetDatabaseEmpty();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم التصفير الكامل ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) _setMountedState(() => _saving = false);
    }
  }
}
