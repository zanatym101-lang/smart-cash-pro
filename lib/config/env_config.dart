import 'package:flutter/foundation.dart';

import 'app_env.dart';

class EnvConfig {
  static const String _appEnvKey = 'APP_ENV';

  static AppEnv load() {
    const rawEnv = String.fromEnvironment(_appEnvKey, defaultValue: 'dev');
    currentEnv = _parse(rawEnv);
    return currentEnv;
  }

  static AppEnv _parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'build':
        return AppEnv.build;
      case 'prod':
        return AppEnv.prod;
      case 'dev':
      default:
        return AppEnv.dev;
    }
  }

  static String labelFor(AppEnv env) {
    switch (env) {
      case AppEnv.build:
        return 'BUILD';
      case AppEnv.prod:
        return 'PROD';
      case AppEnv.dev:
        return 'DEV';
    }
  }

  static void debugLogCurrentEnv() {
    if (!kDebugMode) return;
    debugPrint(
      'Running in ${labelFor(currentEnv)} environment '
      '(enableSms=$enableSms, enableAi=$enableAi)',
    );
  }
}
