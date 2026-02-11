import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'phone_provider.dart';

class PickedContact {
  final String name;
  final String phone;

  const PickedContact({required this.name, required this.phone});
}

Future<PickedContact?> pickContact(BuildContext context) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اختيار الأسماء متاح على الهاتف فقط')),
    );
    return null;
  }

  final ok = await FlutterContacts.requestPermission(readonly: true);
  if (!ok) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم رفض إذن جهات الاتصال')));
    return null;
  }

  try {
    final picked = await FlutterContacts.openExternalPick();
    if (picked == null) return null;

    Contact candidate = picked;
    if (candidate.phones.isEmpty && picked.id.isNotEmpty) {
      final full = await FlutterContacts.getContact(
        picked.id,
        withProperties: true,
        withThumbnail: false,
        withPhoto: false,
        deduplicateProperties: true,
      );
      if (full != null) {
        candidate = full;
      }
    }

    String phone = '';
    for (final p in candidate.phones) {
      final raw = p.normalizedNumber.trim().isNotEmpty
          ? p.normalizedNumber
          : p.number;
      final normalized = normalizePhone(raw);
      if (normalized.isNotEmpty) {
        phone = normalized;
        break;
      }
    }

    if (phone.isEmpty) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جهة الاتصال المختارة لا تحتوي رقم هاتف صالح'),
        ),
      );
      return null;
    }

    final pickedName = candidate.displayName.trim();
    return PickedContact(
      name: pickedName.isEmpty ? phone : pickedName,
      phone: phone,
    );
  } catch (_) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح جهات الاتصال على هذا الجهاز')),
    );
    return null;
  }
}
