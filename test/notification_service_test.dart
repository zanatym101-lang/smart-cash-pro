// ignore_for_file: depend_on_referenced_packages, override_on_non_overriding_member
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/notification_service.dart';

class _FakeNotificationsPlatform extends FlutterLocalNotificationsPlatform {
  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
    void Function(NotificationResponse)? onDidReceiveBackgroundNotificationResponse,
  }) async {
    return true;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body, {
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterLocalNotificationsPlatform.instance = _FakeNotificationsPlatform();
  });

  test('NotificationService init and show execute safely without errors', () async {
    await expectLater(NotificationService.init(), completes);
    await expectLater(
      NotificationService.show(
        title: 'تنبيه',
        body: 'تم استلام تحويل 500',
      ),
      completes,
    );
  });
}
