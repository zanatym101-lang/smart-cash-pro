import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/sms_parser_debug_screen.dart';

void main() {
  testWidgets('SmsParserDebugScreen parses and shows result', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SmsParserDebugScreen()),
    );

    await tester.pumpAndSettle();

    expect(find.text('SMS Parser Debug'), findsOneWidget);
    expect(find.text('تحليل الرسالة'), findsOneWidget);
    expect(find.text('Vodafone Cash'), findsWidgets);
    expect(find.text('500.00'), findsOneWidget);
  });
}
