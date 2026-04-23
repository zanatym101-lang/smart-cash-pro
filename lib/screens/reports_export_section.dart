part of 'reports_screen.dart';

extension _ReportsExportSection on _ReportsScreenState {
  Future<void> _exportPdf() async {
    final report = _report;
    final treasury = _treasury;
    if (report == null || treasury == null) return;
    try {
      final path = await ReportExporter.exportPdf(
        data: report,
        treasury: treasury,
        range: _activeRange(),
      );
      if (!mounted) return;
      await _openExportedFile(path: path, typeLabel: 'PDF');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u0641\u0634\u0644 \u0627\u0644\u062a\u0635\u062f\u064a\u0631: $e',
          ),
        ),
      );
    }
  }

  Future<void> _exportExcel() async {
    final report = _report;
    final treasury = _treasury;
    if (report == null || treasury == null) return;
    try {
      final path = await ReportExporter.exportExcel(
        data: report,
        treasury: treasury,
        range: _activeRange(),
      );
      if (!mounted) return;
      await _openExportedFile(path: path, typeLabel: 'Excel');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u0641\u0634\u0644 \u0627\u0644\u062a\u0635\u062f\u064a\u0631: $e',
          ),
        ),
      );
    }
  }

  Future<void> _openExportedFile({
    required String path,
    required String typeLabel,
  }) async {
    final ok = await _openFileViaSystem(path);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '\u062a\u0645 \u062a\u0635\u062f\u064a\u0631 $typeLabel \u0648\u0641\u062a\u062d \u0627\u0644\u0645\u0644\u0641 \u0645\u0628\u0627\u0634\u0631\u0629',
          ),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '\u062a\u0645 \u0627\u0644\u062a\u0635\u062f\u064a\u0631: $path',
        ),
      ),
    );
  }

  Future<bool> _openFileViaSystem(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }

  Future<List<File>> _listExportedFiles() async {
    final dir = await ReportExporter.exportDirectory();
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final path = entity.path.toLowerCase();
      if (path.endsWith('.pdf') ||
          path.endsWith('.xlsx') ||
          path.endsWith('.csv')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> _showExportsSheet() async {
    final dir = await ReportExporter.exportDirectory();
    final files = await _listExportedFiles();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ملفات التقارير',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              SelectableText(
                dir.path,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: dir.path));
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('تم نسخ المسار')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('نسخ المسار'),
                ),
              ),
              const Divider(),
              if (files.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('لا توجد ملفات تقارير بعد.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (_, i) {
                      final f = files[i];
                      final name = f.uri.pathSegments.isNotEmpty
                          ? f.uri.pathSegments.last
                          : f.path;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          f.lastModifiedSync().toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          final ok = await _openFileViaSystem(f.path);
                          if (!ok && ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('تعذر فتح الملف من النظام'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExportsFolder() async {
    try {
      final dir = await ReportExporter.exportDirectory();
      final ok = await launchUrl(
        Uri.directory(dir.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await _showExportsSheet();
      }
    } catch (_) {
      await _showExportsSheet();
    }
  }

  Future<void> _printLatestPdf() async {
    try {
      final files = await _listExportedFiles();
      final pdfs = files
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList();
      if (pdfs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد PDF للطباعة بعد')),
        );
        return;
      }
      final latest = pdfs.first;
      final bytes = await latest.readAsBytes();
      await Printing.layoutPdf(
        name: latest.uri.pathSegments.isNotEmpty
            ? latest.uri.pathSegments.last
            : 'report.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الطباعة: $e')));
    }
  }
}
