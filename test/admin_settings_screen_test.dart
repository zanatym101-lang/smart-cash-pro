import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/screens/admin_settings_screen.dart';

void main() {
  testWidgets('AdminSettingsScreen loads without crash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSettingsScreen(),
      ),
    );

    // Avoid unbounded settling on CI where background async work can keep
    // the frame pipeline active longer than expected.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AdminSettingsScreen), findsOneWidget);
  });
}
