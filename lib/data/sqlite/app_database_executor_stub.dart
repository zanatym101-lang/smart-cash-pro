import 'package:drift/drift.dart';

QueryExecutor openDatabaseExecutor(String? customPath) {
  throw UnsupportedError(
    'No database executor is configured for this platform.',
  );
}
