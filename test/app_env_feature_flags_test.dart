import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/config/app_env.dart';
import 'package:king_wallet_accounting/screens/dashboard_screen.dart'
    show shouldShowSmsImportAction;

void main() {
  tearDown(() {
    currentEnv = AppEnv.dev;
  });

  test('feature flags match requested environments', () {
    currentEnv = AppEnv.dev;
    expect(enableSms, isTrue);
    expect(enableAi, isTrue);
    expect(enableAiAdvanced, isTrue);

    currentEnv = AppEnv.build;
    expect(enableSms, isTrue);
    expect(enableAi, isFalse);
    expect(enableAiAdvanced, isFalse);

    currentEnv = AppEnv.prod;
    expect(enableSms, isTrue);
    expect(enableAi, isTrue);
    expect(enableAiAdvanced, isFalse);
  });

  test('dashboard UI contract shows SMS quick action when SMS is enabled', () {
    currentEnv = AppEnv.build;
    expect(shouldShowSmsImportAction(), isTrue);
  });

  test('dashboard UI contract shows SMS quick action in production', () {
    currentEnv = AppEnv.prod;
    expect(shouldShowSmsImportAction(), isTrue);
  });
}
