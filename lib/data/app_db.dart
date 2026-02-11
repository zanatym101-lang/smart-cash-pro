import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';

import '../models/wallet.dart';
import '../models/transaction.dart';
import '../models/claim.dart';
import '../models/daily_close.dart';
import '../models/recent_number.dart';
import '../models/app_settings.dart';
import '../models/license_info.dart';
import 'sqlite/app_database.dart';
import '../services/notification_service.dart';
import 'app_session.dart';

import '../accounting/engine.dart';
import '../accounting/specs.dart';
import '../accounting/money.dart';
import 'reporting.dart';

part 'app_db_internal.dart';
part 'app_db_wallets.dart';
part 'app_db_transactions.dart';
part 'app_db_claims.dart';
part 'app_db_admin.dart';
part 'app_db_reports.dart';
part 'app_db_contacts.dart';
part 'app_db_audit.dart';
part 'app_db_sync.dart';

class TreasurySnapshot {
  final double drawerBalance; // Available/expected EGP for UI
  final double walletsTotal; // Available/expected EGP for UI
  final double drawerActualBalance; // Posted-only EGP
  final double walletsActualTotal; // Posted-only EGP
  final int pendingCount;

  // Profits (EGP) derived from posted txns
  final double dailyProfit;
  final double monthlyProfit;

  const TreasurySnapshot({
    required this.drawerBalance,
    required this.walletsTotal,
    required this.drawerActualBalance,
    required this.walletsActualTotal,
    required this.pendingCount,
    required this.dailyProfit,
    required this.monthlyProfit,
  });
}

/// AppDb (JSON persistence) + AccountingEngine (qirsh ints).
///
/// Important design:
/// - UI still talks in double EGP for now.
/// - Accounting core stores everything as int qirsh.
/// - Pending txns impact available balances immediately.
/// - Posted balances are still preserved for audit and reports.
/// - Wallets cannot go negative (engine validates on approval).
class AppDb {
  static final AppDb instance = AppDb._();
  AppDb._();

  bool _loaded = false;
  int _nextWalletId = 1;
  int _nextTxnId = 1;
  int _nextClaimId = 1;
  int _nextCloseId = 1;

  final List<Wallet> _wallets = [];
  final List<Txn> _txns = [];
  final List<Claim> _claims = [];
  final List<DailyClose> _dailyCloses = [];
  final List<RecentNumber> _recentNumbers = [];

  String? _lastPendingAlertDate; // yyyy-MM-dd
  final Map<int, String> _lowBalanceAlertDate = {};
  int? _cachedDayStartHour;

  late AppDatabase _sqlite = AppDatabase();

  late final AccountingState _state = AccountingState(
    walletBalancesQirsh: <String, int>{},
    drawerBalanceQirsh: 0,
    ledger: <LedgerEntry>[],
    transactions: <String, TransactionRecord>{},
  );

  late final AccountingEngine _engine = AccountingEngine(_state);

  String _actorName() => AppSession.actorName;
  String _actorRole() => AppSession.actorRole;
}
