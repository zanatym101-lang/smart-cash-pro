import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/cloud_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudSyncService Lifecycle Tests', () {
    test('stopSync executes cleanly without active sync', () {
      expect(() => CloudSyncService.stopSync(), returnsNormally);
    });

    test('multiple stopSync calls are safe and idempotent', () {
      CloudSyncService.stopSync();
      CloudSyncService.stopSync();
      expect(() => CloudSyncService.stopSync(), returnsNormally);
    });
  });
}
