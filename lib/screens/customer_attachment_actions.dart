part of 'customers_screen.dart';

class _CustomerAttachmentsSheet extends StatefulWidget {
  final _CustomerBucket customer;
  final String customerKey;

  const _CustomerAttachmentsSheet({
    required this.customer,
    required this.customerKey,
  });

  @override
  State<_CustomerAttachmentsSheet> createState() =>
      _CustomerAttachmentsSheetState();
}

class _CustomerAttachmentsSheetState extends State<_CustomerAttachmentsSheet> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CustomerAttachment> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _CustomerAttachmentActions.list(widget.customerKey);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addAttachment() async {
    if (_busy) return;
    final file = await _CustomerAttachmentActions.pickFile();
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر قراءة مسار الملف')));
      return;
    }
    setState(() => _busy = true);
    try {
      await _CustomerAttachmentActions.add(
        customerKey: widget.customerKey,
        customerName: widget.customer.name,
        customerPhone: widget.customer.phone,
        file: file,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttachment(CustomerAttachment att) async {
    if (!await _CustomerAttachmentActions.exists(att)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('الملف غير موجود')));
      return;
    }
    await _CustomerAttachmentActions.open(att);
  }

  Future<void> _deleteAttachment(CustomerAttachment att) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المرفق'),
        content: Text('حذف ${att.fileName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _CustomerAttachmentActions.delete(att);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.75;
    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'مرفقات العميل',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _addAttachment,
                  icon: const Icon(Icons.add),
                  tooltip: 'إضافة ملف',
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text('العميل: ${widget.customer.name}'),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 8),
            if (!_loading && _items.isEmpty)
              const Center(child: Text('لا توجد مرفقات بعد')),
            if (_items.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  // ignore: unnecessary_underscores
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final item = _items[idx];
                    final date =
                        '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}-${item.createdAt.day.toString().padLeft(2, '0')}';
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(item.fileName),
                      subtitle: Text(date),
                      onTap: () => _openAttachment(item),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'open') {
                            _openAttachment(item);
                          } else if (v == 'delete') {
                            _deleteAttachment(item);
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'open', child: Text('فتح')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PickedCustomerAttachment {
  final String path;
  final String name;

  const _PickedCustomerAttachment({required this.path, required this.name});
}

class _CustomerAttachmentActions {
  const _CustomerAttachmentActions._();

  static Future<List<CustomerAttachment>> list(String customerKey) {
    return AppDb.instance.listCustomerAttachments(customerKey: customerKey);
  }

  static Future<_PickedCustomerAttachment?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final path = file.path;
    if (path == null || path.trim().isEmpty) return null;
    return _PickedCustomerAttachment(path: path, name: file.name);
  }

  static Future<void> add({
    required String customerKey,
    required String customerName,
    required String? customerPhone,
    required _PickedCustomerAttachment file,
  }) {
    return AppDb.instance.addCustomerAttachment(
      customerKey: customerKey,
      customerName: customerName,
      customerPhone: customerPhone,
      sourcePath: file.path,
      displayName: file.name,
    );
  }

  static Future<bool> exists(CustomerAttachment attachment) {
    return File(attachment.filePath).exists();
  }

  static Future<void> open(CustomerAttachment attachment) {
    return OpenFilex.open(attachment.filePath);
  }

  static Future<void> delete(CustomerAttachment attachment) {
    return AppDb.instance.deleteCustomerAttachment(attachment.id);
  }
}
