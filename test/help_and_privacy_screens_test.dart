import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/screens/help_screen.dart';
import 'package:king_wallet_accounting/screens/privacy_policy_screen.dart';

void main() {

  testWidgets('HelpScreen loads without crash', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HelpScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets('PrivacyPolicyScreen loads without crash', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PrivacyPolicyScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
  });

}