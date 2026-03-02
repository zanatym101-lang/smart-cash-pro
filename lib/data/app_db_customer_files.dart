part of 'app_db.dart';

extension AppDbCustomerFiles on AppDb {
  Future<Directory> _customerAttachmentsDir() async {
    final dir = await getApplicationSupportDirectory();
    final target = Directory(p.join(dir.path, 'customer_attachments'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  String _sanitizeFileToken(String input) {
    final buf = StringBuffer();
    for (final r in input.runes) {
      final ch = String.fromCharCode(r);
      final code = ch.codeUnitAt(0);
      final isAlpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      final isDigit = code >= 48 && code <= 57;
      if (isAlpha || isDigit) {
        buf.write(ch);
      } else {
        buf.write('_');
      }
    }
    final v = buf.toString();
    return v.isEmpty ? 'customer' : v;
  }

  Future<List<CustomerAttachment>> listCustomerAttachments({
    required String customerKey,
  }) async {
    await _ensureLoaded();
    final key = customerKey.trim();
    return _customerAttachments.where((a) => a.customerKey == key).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<CustomerAttachment> addCustomerAttachment({
    required String customerKey,
    required String customerName,
    String? customerPhone,
    required String sourcePath,
    required String displayName,
  }) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('الملف غير موجود');
    }
    final key = customerKey.trim();
    if (key.isEmpty) {
      throw Exception('المفتاح غير صالح');
    }
    final now = DateTime.now();
    final id = _nextAttachmentId++;
    final dir = await _customerAttachmentsDir();
    final ext = p.extension(sourcePath);
    final token = _sanitizeFileToken(key);
    final fileName = 'cust_${token}_$id$ext';
    final destPath = p.join(dir.path, fileName);
    await src.copy(destPath);

    final attachment = CustomerAttachment(
      id: id,
      customerKey: key,
      customerName: customerName.trim().isEmpty
          ? 'عميل بدون اسم'
          : customerName.trim(),
      customerPhone: (customerPhone ?? '').trim().isEmpty
          ? null
          : customerPhone!.trim(),
      fileName: displayName.trim().isEmpty
          ? p.basename(sourcePath)
          : displayName.trim(),
      filePath: destPath,
      createdAt: now,
    );
    _customerAttachments.add(attachment);
    await _save();
    await enqueueOutbox(
      entity: 'customer_attachment',
      entityId: attachment.id.toString(),
      action: 'create',
      payload: attachment.toJson(),
    );
    await appendAudit(
      type: 'customer_attachment_add',
      note: '${attachment.customerName} | ${attachment.fileName}',
    );
    return attachment;
  }

  Future<void> deleteCustomerAttachment(int id) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final idx = _customerAttachments.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final att = _customerAttachments.removeAt(idx);
    try {
      final f = File(att.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
    await _save();
    await enqueueOutbox(
      entity: 'customer_attachment',
      entityId: att.id.toString(),
      action: 'delete',
      payload: att.toJson(),
    );
    await appendAudit(
      type: 'customer_attachment_delete',
      note: '${att.customerName} | ${att.fileName}',
    );
  }
}
