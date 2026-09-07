import 'models/incoming_message.dart';
import 'sms_inbox_service.dart';

class _UnsupportedSmsInboxService implements SmsInboxService {
  @override
  Future<List<IncomingMessage>> fetchRecentMessages({int limit = 100}) async =>
      const [];

  @override
  Future<SmsInboxPermissionStatus> getPermissionStatus() async =>
      SmsInboxPermissionStatus.unsupported;

  @override
  Future<SmsInboxPermissionStatus> requestPermission() async =>
      SmsInboxPermissionStatus.unsupported;

  @override
  SmsInboxFetchStats get lastFetchStats => const SmsInboxFetchStats(
    totalFetched: 0,
    totalAfterSenderFilter: 0,
    ignoredSenderCount: 0,
  );
}

SmsInboxService createSmsInboxService() => _UnsupportedSmsInboxService();
