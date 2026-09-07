import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'financial_sender_rules.dart';
import 'models/incoming_message.dart';
import 'sms_inbox_service.dart';

class MethodChannelSmsInboxService implements SmsInboxService {
  static const MethodChannel _channel = MethodChannel(
    'com.smartcashpro.app/sms_inbox',
  );

  SmsInboxFetchStats? _lastFetchStats;

  @override
  Future<List<IncomingMessage>> fetchRecentMessages({int limit = 100}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      _lastFetchStats = const SmsInboxFetchStats(
        totalFetched: 0,
        totalAfterSenderFilter: 0,
        ignoredSenderCount: 0,
      );
      return const [];
    }
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'fetchRecentMessages',
      {'limit': limit},
    );
    if (raw == null) {
      _lastFetchStats = const SmsInboxFetchStats(
        totalFetched: 0,
        totalAfterSenderFilter: 0,
        ignoredSenderCount: 0,
      );
      return const [];
    }

    final totalFetched = raw.length;
    final messages = <IncomingMessage>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = (item['id'] ?? item['_id'])?.toString();
      final sender = (item['sender'] ?? item['address'] ?? '').toString();
      final body = (item['body'] ?? '').toString();
      final millisRaw = item['receivedAt'];
      final millis = millisRaw is int
          ? millisRaw
          : int.tryParse(millisRaw?.toString() ?? '');
      if (!isKnownFinancialSender(sender)) continue;
      messages.add(
        IncomingMessage(
          id: id,
          sender: sender,
          body: body,
          receivedAt: millis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(millis),
        ),
      );
    }
    _lastFetchStats = SmsInboxFetchStats(
      totalFetched: totalFetched,
      totalAfterSenderFilter: messages.length,
      ignoredSenderCount: totalFetched - messages.length,
    );
    return messages;
  }

  @override
  Future<SmsInboxPermissionStatus> getPermissionStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return SmsInboxPermissionStatus.unsupported;
    }
    final status = await _channel.invokeMethod<String>('getPermissionStatus');
    return _mapStatus(status);
  }

  @override
  Future<SmsInboxPermissionStatus> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return SmsInboxPermissionStatus.unsupported;
    }
    final status = await _channel.invokeMethod<String>('requestPermission');
    return _mapStatus(status);
  }

  SmsInboxPermissionStatus _mapStatus(String? value) {
    switch (value) {
      case 'granted':
        return SmsInboxPermissionStatus.granted;
      case 'denied':
        return SmsInboxPermissionStatus.denied;
      default:
        return SmsInboxPermissionStatus.unsupported;
    }
  }

  @override
  SmsInboxFetchStats? get lastFetchStats => _lastFetchStats;
}

SmsInboxService createSmsInboxService() => MethodChannelSmsInboxService();
