import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openDatabaseExecutor(String? customPath) {
  return LazyDatabase(() async {
    final file = customPath == null
        ? File(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'king_wallet.db',
            ),
          )
        : File(customPath);
    return NativeDatabase(file);
  });
}
