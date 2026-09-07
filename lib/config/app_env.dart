enum AppEnv { dev, build, prod }

AppEnv currentEnv = AppEnv.dev;

const bool isClientRelease = bool.fromEnvironment('CLIENT_RELEASE', defaultValue: false);

bool get isBuildEnv => currentEnv == AppEnv.build;
bool get isClientFlavor => isClientRelease || currentEnv == AppEnv.prod;

bool get enableSms {
  switch (currentEnv) {
    case AppEnv.dev:
    case AppEnv.build:
    case AppEnv.prod:
      return true;
  }
}

bool get enableAi {
  switch (currentEnv) {
    case AppEnv.dev:
    case AppEnv.prod:
      // AI remains advisory only: it can suggest parsing/customer hints but
      // cannot write accounting or bypass review/duplicate checks.
      return true;
    case AppEnv.build:
      return false;
  }
}

bool get enableAiAdvanced {
  switch (currentEnv) {
    case AppEnv.dev:
      return true;
    case AppEnv.build:
    case AppEnv.prod:
      return false;
  }
}
