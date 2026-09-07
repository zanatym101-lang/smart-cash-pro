// ignore_for_file: deprecated_member_use

import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor openDatabaseExecutor(String? customPath) {
  final name = (customPath == null || customPath.trim().isEmpty)
      ? 'king_wallet_web'
      : customPath.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  return WebDatabase(name);
}
