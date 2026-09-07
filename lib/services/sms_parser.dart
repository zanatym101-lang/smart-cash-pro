import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai_sms/models/incoming_message.dart';
import '../ai_sms/models/message_parse_result.dart';
import '../ai_sms/models/parsed_transaction_draft.dart';
import '../ai_sms/sms_parser_service.dart';
import '../data/app_db.dart';

class SmsParser {
  static final SmsParserService _service = SmsParserService();

  /// Parse an incoming message or raw text.
  static MessageParseResult parse(IncomingMessage message) {
    return _service.parse(message);
  }

  static MessageParseResult parseText(String text, {String sender = 'Manual'}) {
    return _service.parse(IncomingMessage(body: text, sender: sender));
  }

  /// Extracts Egyptian phone number from text or returns null if not found.
  static String? extractPhone(String text) {
    final normalized = normalizeArabicDigits(text);
    final patterns = [
      RegExp(r'(?:من|إلى|الى|لرقم|لـ|ل|from|to)\s*(01[0125][0-9]{8})', caseSensitive: false),
      RegExp(r'\b(01[0125][0-9]{8})\b'),
      RegExp(r'\+20(1[0125][0-9]{8})'),
      RegExp(r'\b20(1[0125][0-9]{8})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        final raw = match.group(1)?.trim();
        if (raw != null && raw.isNotEmpty) {
          if (raw.startsWith('20') && raw.length == 12) {
            return '0${raw.substring(2)}';
          }
          if (!raw.startsWith('0') && raw.length == 10) {
            return '0$raw';
          }
          return raw;
        }
      }
    }
    return null;
  }

  /// Normalizes Arabic and Persian digits to Latin digits.
  static String normalizeArabicDigits(String input) {
    const map = {
      '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
      '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
      '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
      '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    };
    var result = input;
    map.forEach((ar, en) {
      result = result.replaceAll(ar, en);
    });
    return result;
  }

  /// Normalize phone number to pure digits.
  static String normalizePhone(String input) {
    final latin = normalizeArabicDigits(input);
    final buffer = StringBuffer();
    for (final rune in latin.runes) {
      final ch = String.fromCharCode(rune);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Look up customer name in AppDb by phone number.
  static Future<String?> lookupCustomerByPhone(String phone, {AppDb? db}) async {
    final targetDb = db ?? AppDb.instance;
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return null;

    final targetSuffix = normalized.length >= 10
        ? normalized.substring(normalized.length - 10)
        : normalized;

    // 1. Check recent numbers
    try {
      final recent = await targetDb.listRecentNumbers(limit: 100);
      for (final r in recent) {
        final rPhone = normalizePhone(r.phone);
        if (rPhone == normalized || (rPhone.length >= 10 && rPhone.endsWith(targetSuffix))) {
          if (r.name != null && r.name!.trim().isNotEmpty) {
            return r.name!.trim();
          }
        }
      }
    } catch (_) {}

    // 2. Check customer candidates (transactions & claims)
    try {
      final candidates = await targetDb.listCustomerCandidates();
      for (final c in candidates) {
        final cPhone = normalizePhone(c.phone ?? '');
        if (cPhone.isNotEmpty) {
          if (cPhone == normalized || (cPhone.length >= 10 && cPhone.endsWith(targetSuffix))) {
            if (c.customerName.trim().isNotEmpty) {
              return c.customerName.trim();
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Auto-match customer in draft:
  /// When a phone number is parsed from an incoming SMS, look up the customer in AppDb.
  /// If found, pre-select the customer.
  static Future<ParsedTransactionDraft> autoMatchCustomer(
    ParsedTransactionDraft draft, {
    AppDb? db,
  }) async {
    final phone = extractPhone(
      '${draft.customerName ?? ''} ${draft.note ?? ''} ${draft.rawMessage}',
    );
    if (phone == null || phone.isEmpty) {
      return draft;
    }

    final matchedName = await lookupCustomerByPhone(phone, db: db);
    if (matchedName != null && matchedName.isNotEmpty) {
      return draft.copyWith(
        customerName: matchedName,
        note: draft.note ?? 'رقم العميل: $phone',
      );
    }

    // Customer not found in AppDb; keep phone number in customerName or note
    if (draft.customerName == null || draft.customerName!.isEmpty) {
      return draft.copyWith(
        customerName: phone,
        note: draft.note ?? 'رقم العميل: $phone',
      );
    }
    return draft;
  }

  /// Save customer to AppDb (one-tap save).
  static Future<void> saveCustomer({
    required String phone,
    required String name,
    AppDb? db,
  }) async {
    final targetDb = db ?? AppDb.instance;
    final normalized = normalizePhone(phone);
    final trimmedName = name.trim();
    if (normalized.isEmpty) return;
    await targetDb.addRecentNumber(
      phone: normalized,
      name: trimmedName.isNotEmpty ? trimmedName : null,
    );
  }

  /// Format receipt for WhatsApp sharing.
  static String formatWhatsAppReceipt(
    ParsedTransactionDraft draft, {
    String storeName = 'Smart Cash Pro',
  }) {
    final opType = draft.operationType == ParsedOperationType.receive
        ? 'استلام نقدية / إيداع'
        : 'تحويل رصيد / كاش';
    final amount = draft.amount != null
        ? '${draft.amount!.toStringAsFixed(2)} ج.م'
        : 'غير محدد';
    final provider = draft.provider ?? draft.sender;
    final customer = draft.customerName?.trim();
    final ref = draft.reference?.trim();
    final date = draft.effectiveDate;
    final yyyy = date.year.toString().padLeft(4, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final formattedDate = '$yyyy-$mm-$dd $hh:$min';

    final buffer = StringBuffer();
    buffer.writeln('🧾 *إيصال معاملة مالية - $storeName*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📌 *العملية:* $opType');
    buffer.writeln('💰 *المبلغ:* $amount');
    if (provider.isNotEmpty) {
      buffer.writeln('🏦 *الجهة / المحفظة:* $provider');
    }
    if (customer != null && customer.isNotEmpty) {
      buffer.writeln('👤 *الطرف الآخر / العميل:* $customer');
    }
    if (ref != null && ref.isNotEmpty) {
      buffer.writeln('🔢 *رقم المرجع:* #$ref');
    }
    buffer.writeln('📅 *التاريخ:* $formattedDate');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.write('✨ *شكراً لتعاملكم معنا.*');

    return buffer.toString();
  }

  /// Build WhatsApp Uri for launching.
  static Uri buildWhatsAppUri({
    String? phone,
    required String message,
  }) {
    String? cleanPhone;
    if (phone != null && phone.trim().isNotEmpty) {
      cleanPhone = normalizePhone(phone);
      if (cleanPhone.startsWith('0') && cleanPhone.length == 11) {
        cleanPhone = '2$cleanPhone';
      } else if (!cleanPhone.startsWith('20') && cleanPhone.length == 10) {
        cleanPhone = '20$cleanPhone';
      }
    }

    final encodedMsg = Uri.encodeComponent(message);
    if (cleanPhone != null && cleanPhone.isNotEmpty) {
      return Uri.parse('https://wa.me/$cleanPhone?text=$encodedMsg');
    }
    return Uri.parse('https://wa.me/?text=$encodedMsg');
  }

  /// Launch WhatsApp with formatted receipt.
  static Future<bool> launchWhatsAppReceipt(
    ParsedTransactionDraft draft, {
    String? phone,
    String storeName = 'Smart Cash Pro',
  }) async {
    final effectivePhone = phone ??
        extractPhone(
          '${draft.customerName ?? ''} ${draft.note ?? ''} ${draft.rawMessage}',
        );
    final message = formatWhatsAppReceipt(draft, storeName: storeName);
    final uri = buildWhatsAppUri(phone: effectivePhone, message: message);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching WhatsApp: $e');
      return false;
    }
  }
}
