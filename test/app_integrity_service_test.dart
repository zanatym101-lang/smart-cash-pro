import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/app_integrity_service.dart';

void main() {
  group('AppIntegrityService Signature Verification', () {
    const legitimateFp =
        '83:4B:1E:56:08:21:F1:9F:EC:21:5D:FA:33:46:8F:9A:4D:27:BA:65:C7:4B:A8:4C:EB:10:9E:1B:CF:21:E4:75';
    const illegitimateFp =
        '11:22:33:44:55:66:77:88:99:00:AA:BB:CC:DD:EE:FF:11:22:33:44:55:66:77:88:99:00:AA:BB:CC:DD:EE:FF';

    test('normalizeFingerprint strips colons, spaces and capitalizes', () {
      final raw = ' 83:4b:1e:56:08:21:f1:9f:ec:21:5d:fa:33:46:8f:9a:4d:27:ba:65:c7:4b:a8:4c:eb:10:9e:1b:cf:21:e4:75 ';
      final normalized = AppIntegrityService.normalizeFingerprint(raw);
      expect(
        normalized,
        '834B1E560821F19FEC215DFA33468F9A4D27BA65C74BA84CEB109E1BCF21E475',
      );
    });

    test('non-Android platforms always pass integrity verification', () async {
      final result = await AppIntegrityService.verifyAppIntegrity(
        isAndroidOverride: false,
        isDebugOverride: false,
        testFingerprint: illegitimateFp,
      );
      expect(result, isTrue);
    });

    test('debug mode allows execution without blocking', () async {
      final result = await AppIntegrityService.verifyAppIntegrity(
        isAndroidOverride: true,
        isDebugOverride: true,
        testFingerprint: illegitimateFp,
      );
      expect(result, isTrue);
    });

    test('release mode approves valid release certificate signature', () async {
      final result = await AppIntegrityService.verifyAppIntegrity(
        isAndroidOverride: true,
        isDebugOverride: false,
        testFingerprint: legitimateFp,
      );
      expect(result, isTrue);
    });

    test('release mode approves valid signature without colons and lowercase', () async {
      final raw = legitimateFp.replaceAll(':', '').toLowerCase();
      final result = await AppIntegrityService.verifyAppIntegrity(
        isAndroidOverride: true,
        isDebugOverride: false,
        testFingerprint: raw,
      );
      expect(result, isTrue);
    });

    test('release mode rejects tampered or illegitimate signature', () async {
      final result = await AppIntegrityService.verifyAppIntegrity(
        isAndroidOverride: true,
        isDebugOverride: false,
        testFingerprint: illegitimateFp,
      );
      expect(result, isFalse);
    });

    test('release mode rejects null or empty signature', () async {
      final resultNull = await AppIntegrityService.verifyAppIntegrity(
        isAndroidOverride: true,
        isDebugOverride: false,
        testFingerprint: null,
      );
      expect(resultNull, isFalse);

      final resultEmpty = await AppIntegrityService.verifyAppIntegrity(
        isAndroidOverride: true,
        isDebugOverride: false,
        testFingerprint: '   ',
      );
      expect(resultEmpty, isFalse);
    });
  });

  group('TamperAlertScreen UI', () {
    testWidgets('renders security warning and exit button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TamperAlertScreen(),
        ),
      );

      expect(find.text('تنبيه أمني عالي الخطورة'), findsOneWidget);
      expect(find.text('App Signature Tamper Detected'), findsOneWidget);
      expect(find.text('إغلاق التطبيق'), findsOneWidget);
      expect(find.byIcon(Icons.gpp_bad_rounded), findsOneWidget);
    });
  });
}
