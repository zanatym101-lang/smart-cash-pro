import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/screens/admin_settings_screen.dart';

void main() {
  testWidgets('AdminSettingsScreen loads without crash', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSettingsScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AdminSettingsScreen), findsOneWidget);
  });
}
