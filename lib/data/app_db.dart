import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart' as crypt;
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
import '../models/customer_attachment.dart';
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
part 'app_db_health.dart';
part 'app_db_customer_files.dart';

class TreasurySnapshot {
  final double drawerBalance; // Projected EGP for UI
  final double walletsTotal; // Projected EGP for UI
  final double fawryBalance; // Projected/available fawry float
  final double drawerActualBalance; // Posted-only EGP
  final double walletsActualTotal; // Posted-only EGP
  final double fawryActualBalance; // Posted-only fawry float
  final int pendingCount;
  final double pendingInflow; // Pending receive impact on wallets
  final double pendingOutflow; // Pending transfer impact on wallets
  final double claimsReceivableOpen; // Open "mabalegh lana"
  final double claimsPayableOpen; // Open "mabalegh alayna"
  final double profitApprovedTotal; // Posted-only cumulative profit

  // Profits (EGP) derived from posted txns
  final double dailyProfit;
  final double monthlyProfit;

  const TreasurySnapshot({
    required this.drawerBalance,
    required this.walletsTotal,
    this.fawryBalance = 0,
    required this.drawerActualBalance,
    required this.walletsActualTotal,
    this.fawryActualBalance = 0,
    required this.pendingCount,
    required this.pendingInflow,
    required this.pendingOutflow,
    required this.claimsReceivableOpen,
    required this.claimsPayableOpen,
    required this.profitApprovedTotal,
    required this.dailyProfit,
    required this.monthlyProfit,
  });

  double get pendingNet => pendingInflow - pendingOutflow;
  double get pendingTotal => pendingInflow + pendingOutflow;

  double get claimsNet => claimsReceivableOpen - claimsPayableOpen;

  // Confirmed treasury: actual cash drawer + actual wallets + actual fawry float.
  // Profit is reported separately and must not be added again to avoid double counting.
  double get actualTreasuryApproved =>
      drawerActualBalance + walletsActualTotal + fawryActualBalance;

  // Available liquidity = confirmed treasury + pending receive - pending transfer.
  double get availableLiquidityNow => actualTreasuryApproved + pendingNet;

  // Approved real capital = confirmed treasury +/- open claims.
  double get realCapitalApproved => actualTreasuryApproved + claimsNet;

  // Backward-compatible projected helper used by some reports.
  double get expectedLiquidity => availableLiquidityNow;
}

class WalletLimitUsage {
  final int walletId;
  final double dailyUsed;
  final double dailyLimit;
  final double monthlyUsed;
  final double monthlyLimit;

  const WalletLimitUsage({
    required this.walletId,
    required this.dailyUsed,
    required this.dailyLimit,
    required this.monthlyUsed,
    required this.monthlyLimit,
  });

  double get dailyRemaining => max(0, dailyLimit - dailyUsed);
  double get monthlyRemaining => max(0, monthlyLimit - monthlyUsed);

  double get dailyPercent =>
      dailyLimit <= 0 ? 0 : (dailyUsed / dailyLimit).clamp(0, 1).toDouble();
  double get monthlyPercent => monthlyLimit <= 0
      ? 0
      : (monthlyUsed / monthlyLimit).clamp(0, 1).toDouble();
}

class IntegrityIssue {
  final String code;
  final String message;

  const IntegrityIssue({required this.code, required this.message});
}

class AuditChainStatus {
  final bool ok;
  final int count;
  final String? headHash;
  final String? tailHash;
  final String? error;
  final int? brokenIndex;

  const AuditChainStatus({
    required this.ok,
    required this.count,
    required this.headHash,
    required this.tailHash,
    required this.error,
    required this.brokenIndex,
  });
}

class SecureBackupAuthException implements Exception {
  final String message;

  const SecureBackupAuthException(this.message);

  @override
  String toString() => message;
}

class SecureRestoreStatus {
  final int failedAttempts;
  final int maxAttempts;
  final int remainingAttempts;
  final DateTime? lockedUntil;
  final bool locked;

  const SecureRestoreStatus({
    required this.failedAttempts,
    required this.maxAttempts,
    required this.remainingAttempts,
    required this.lockedUntil,
    required this.locked,
  });
}

class IntegrityCheckResult {
  final bool ok;
  final DateTime checkedAt;
  final List<IntegrityIssue> issues;
  final int auditEntries;
  final bool auditChainOk;
  final String? auditHeadHash;
  final String? auditTailHash;

  const IntegrityCheckResult({
    required this.ok,
    required this.checkedAt,
    required this.issues,
    required this.auditEntries,
    required this.auditChainOk,
    required this.auditHeadHash,
    required this.auditTailHash,
  });
}

class IntegrityRepairResult {
  final bool changed;
  final String? backupPath;
  final int walletsFixed;
  final int txnsFixed;
  final int claimsFixed;
  final int dailyClosesFixed;
  final IntegrityCheckResult before;
  final IntegrityCheckResult after;

  const IntegrityRepairResult({
    required this.changed,
    required this.backupPath,
    required this.walletsFixed,
    required this.txnsFixed,
    required this.claimsFixed,
    required this.dailyClosesFixed,
    required this.before,
    required this.after,
  });
}

class SystemHealthSummary {
  final DateTime? lastBackupAt;
  final String? lastBackupType;
  final int databaseSizeBytes;
  final int pendingCount;
  final DateTime? lastIntegrityAt;
  final bool? lastIntegrityOk;
  final int lastIntegrityIssues;
  final String? lastIntegrityError;
  final String? auditTailHash;

  const SystemHealthSummary({
    required this.lastBackupAt,
    required this.lastBackupType,
    required this.databaseSizeBytes,
    required this.pendingCount,
    required this.lastIntegrityAt,
    required this.lastIntegrityOk,
    required this.lastIntegrityIssues,
    required this.lastIntegrityError,
    required this.auditTailHash,
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
  Future<void>? _loadingFuture;
  int _nextWalletId = 1;
  int _nextTxnId = 1;
  int _nextClaimId = 1;
  int _nextCloseId = 1;
  int _nextAttachmentId = 1;

  final List<Wallet> _wallets = [];
  final List<Txn> _txns = [];
  final List<Claim> _claims = [];
  final List<DailyClose> _dailyCloses = [];
  final List<RecentNumber> _recentNumbers = [];
  final List<CustomerAttachment> _customerAttachments = [];

  String? _lastPendingAlertDate; // yyyy-MM-dd
  final Map<int, String> _lowBalanceAlertDate = {};
  final Map<int, DateTime> _dailyUsageResetAt = {};
  final Map<int, DateTime> _monthlyUsageResetAt = {};
  int? _cachedDayStartHour;

  late AppDatabase _sqlite = AppDatabase();

  late final AccountingState _state = AccountingState(
    walletBalancesQirsh: <String, int>{},
    drawerBalanceQirsh: 0,
    fawryBalanceQirsh: 0,
    ledger: <LedgerEntry>[],
    transactions: <String, TransactionRecord>{},
  );

  late final AccountingEngine _engine = AccountingEngine(_state);

  String _actorName() => AppSession.actorName;
  String _actorRole() => AppSession.actorRole;
}
