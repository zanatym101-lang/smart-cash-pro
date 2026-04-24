import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/audit_log_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_audit_hardening_',
  );

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 100,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Widget not found in time: $finder');
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
  });

  setUp(() async {
    await resetAndActivate();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
    'audit screen shows critical pending_settlement entry and chain status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(() async {
        await AppDb.instance.appendAudit(
          type: 'pending_settlement',
          note: 'critical-settlement-marker',
        );
      });

      AppSession.enterAdmin();
      await tester.pumpWidget(const MaterialApp(home: AuditLogScreen()));

      await pumpUntilFound(tester, find.byType(TextField));
      await pumpFrames(tester, count: 12);

      await tester.enterText(
        find.byType(TextField).first,
        'pending_settlement',
      );
      await pumpFrames(tester, count: 8);

      final eventInList = find.descendant(
        of: find.byType(ListTile),
        matching: find.text('pending_settlement'),
      );
      await pumpUntilFound(tester, eventInList);
      expect(eventInList, findsWidgets);

      final listTiles = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(listTiles.length, greaterThanOrEqualTo(2));
    },
  );

  testWidgets(
    'audit screen shows critical txn_rollback entry and chain status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(() async {
        await AppDb.instance.appendAudit(
          type: 'txn_rollback',
          note: 'critical-rollback-marker',
          txnId: 777,
        );
      });

      AppSession.enterAdmin();
      await tester.pumpWidget(const MaterialApp(home: AuditLogScreen()));

      await pumpUntilFound(tester, find.byType(TextField));
      await pumpFrames(tester, count: 12);

      await tester.enterText(find.byType(TextField).first, 'txn_rollback');
      await pumpFrames(tester, count: 8);

      final eventInList = find.descendant(
        of: find.byType(ListTile),
        matching: find.textContaining('Rollback'),
      );
      await pumpUntilFound(tester, eventInList);
      expect(eventInList, findsWidgets);

      final listTiles = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(listTiles.length, greaterThanOrEqualTo(2));
    },
  );

  testWidgets(
    'non-admin cannot clear audit log from audit screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(() async {
        AppSession.enterAdmin();
        await AppDb.instance.appendAudit(
          type: 'pending_settlement',
          note: 'non-admin-clear-guard-marker',
        );
      });

      AppSession.enterUser();
      await tester.pumpWidget(const MaterialApp(home: AuditLogScreen()));

      await pumpUntilFound(tester, find.byType(TextField));
      await pumpFrames(tester, count: 10);

      final markerBefore = find.textContaining('non-admin-clear-guard-marker');
      await pumpUntilFound(tester, markerBefore);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await pumpFrames(tester, count: 8);

      expect(find.byType(AlertDialog), findsNothing);
      expect(markerBefore, findsOneWidget);
    },
  );
}
