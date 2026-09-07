import 'models/incoming_message.dart';
import 'sms_inbox_service_stub.dart'
    if (dart.library.io) 'sms_inbox_service_io.dart';

enum SmsInboxPermissionStatus { granted, denied, unsupported }

class SmsInboxFetchStats {
  const SmsInboxFetchStats({
    required this.totalFetched,
    required this.totalAfterSenderFilter,
    required this.ignoredSenderCount,
  });

  final int totalFetched;
  final int totalAfterSenderFilter;
  final int ignoredSenderCount;
}

abstract class SmsInboxService {
  Future<SmsInboxPermissionStatus> getPermissionStatus();

  Future<SmsInboxPermissionStatus> requestPermission();

  Future<List<IncomingMessage>> fetchRecentMessages({int limit = 100});

  SmsInboxFetchStats? get lastFetchStats => null;

  factory SmsInboxService.platform() => createSmsInboxService();
}
