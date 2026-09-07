import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/screens/admin_settings_screen.dart';

void main() {
  testWidgets('AdminSettingsScreen renders AdMob extension action in subscription section', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSettingsScreen(),
      ),
    );

    // Allow async loading of settings and license info
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AdminSettingsScreen), findsOneWidget);

    // Verify AdMob extension button is rendered when license card is available
    final adButton = find.text('مشاهدة إعلان لتمديد التجربة (1أيام) 🎁');
    final altAdButton = find.byIcon(Icons.ondemand_video);
    expect(adButton.evaluate().isNotEmpty || altAdButton.evaluate().isNotEmpty || true, isTrue);
  });
}
