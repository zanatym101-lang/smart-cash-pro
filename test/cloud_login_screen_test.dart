import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/screens/cloud_login_screen.dart';

void main() {
  testWidgets('CloudLoginScreen renders correctly and toggles auth mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CloudLoginScreen(),
      ),
    );

    // Initial Login mode checks
    expect(find.text('تسجيل الدخول السحابي'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    // Toggle to Sign Up mode
    final toggleButton = find.text('ليس لديك حساب؟ أنشئ مساحة عمل');
    expect(toggleButton, findsOneWidget);
    await tester.tap(toggleButton);
    await tester.pumpAndSettle();

    // Sign Up mode checks
    expect(find.text('إنشاء مساحة عمل جديدة'), findsOneWidget);
    expect(find.text('إنشاء حساب'), findsOneWidget);

    // Enter email & password
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.pump();

    expect(find.text('user@example.com'), findsOneWidget);
  });
}
