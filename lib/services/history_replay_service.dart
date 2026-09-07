import 'dart:developer' as developer;

import '../data/app_db.dart';
import '../domain/services/accounting_engine.dart';
import '../domain/services/accounting_replay_engine.dart';
import '../domain/services/snapshot_builder.dart';
import 'legacy_history_bridge_service.dart';

class HistoryReplayResult {
  const HistoryReplayResult({
    required this.events,
    required this.snapshot,
    required this.replaySnapshot,
  });

  final List<AccountingEvent> events;
  final AccountingSnapshot snapshot;
  final AccountingReplaySnapshot replaySnapshot;
}

class ReplayDrift {
  const ReplayDrift({
    required this.field,
    required this.legacyValue,
    required this.replayValue,
    required this.delta,
  });

  final String field;
  final double legacyValue;
  final double replayValue;
  final double delta;

  Map<String, Object?> toJson() => {
    'field': field,
    'legacyValue': legacyValue,
    'replayValue': replayValue,
    'delta': delta,
  };
}

class HistoryReplayParityReport {
  const HistoryReplayParityReport({
    required this.replay,
    required this.drifts,
    required this.generatedAt,
  });

  final HistoryReplayResult replay;
  final List<ReplayDrift> drifts;
  final DateTime generatedAt;

  bool get hasDrift => drifts.isNotEmpty;
}

class HistoryReplayService {
  const HistoryReplayService({
    AccountingReplayEngine replayEngine = const AccountingReplayEngine(),
  }) : _replayEngine = replayEngine;

  final AccountingReplayEngine _replayEngine;

  HistoryReplayResult replay(List<BridgedAccountingEvent> bridgedEvents) {
    final events = bridgedEvents
        .map((bridgedEvent) => bridgedEvent.event)
        .toList(growable: false);
    final replaySnapshot = _replayEngine.replay(events);
    return HistoryReplayResult(
      events: events,
      snapshot: replaySnapshot.accounting,
      replaySnapshot: replaySnapshot,
    );
  }

  Future<HistoryReplayResult> replayLegacyAppDb(AppDb db) async {
    final bridge = await const LegacyHistoryBridgeService().bridgeFromAppDb(db);
    return replay(bridge.events);
  }

  Future<HistoryReplayParityReport> verifyLegacyParity(
    AppDb db, {
    double tolerance = 0.0001,
  }) async {
    final legacy = await db.getTreasurySnapshot();
    final replayResult = await replayLegacyAppDb(db);
    final snapshot = replayResult.snapshot;
    final drifts = <ReplayDrift?>[
      _drift(
        'treasury.drawer',
        legacy.drawerActualBalance,
        snapshot.drawer,
        tolerance,
      ),
      _drift(
        'treasury.wallets',
        legacy.walletsActualTotal,
        snapshot.wallets,
        tolerance,
      ),
      _drift(
        'treasury.fawry',
        legacy.fawryActualBalance,
        snapshot.fawry,
        tolerance,
      ),
      _drift(
        'customers.pendingReceivable',
        legacy.pendingReceivableOpen,
        snapshot.pendingReceivable,
        tolerance,
      ),
      _drift(
        'customers.pendingPayable',
        legacy.pendingPayableOpen,
        snapshot.pendingPayable,
        tolerance,
      ),
      _drift(
        'claims.receivable',
        legacy.claimsReceivableOpen,
        snapshot.openClaimsReceivable,
        tolerance,
      ),
      _drift(
        'claims.payable',
        legacy.claimsPayableOpen,
        snapshot.openClaimsPayable,
        tolerance,
      ),
      _drift(
        'treasury.availableLiquidityNow',
        legacy.availableLiquidityNow,
        snapshot.availableLiquidityNow,
        tolerance,
      ),
      _drift(
        'treasury.realCapitalApproved',
        legacy.realCapitalApproved,
        snapshot.realCapitalApproved,
        tolerance,
      ),
      _drift(
        'profit.clientFees',
        legacy.profitApprovedTotal,
        snapshot.profitFromClientFees,
        tolerance,
      ),
    ].whereType<ReplayDrift>().toList(growable: false);

    final report = HistoryReplayParityReport(
      replay: replayResult,
      drifts: drifts,
      generatedAt: DateTime.now().toUtc(),
    );
    if (report.hasDrift) {
      developer.log(
        {
          'event': 'event_replay_drift_detected',
          'drifts': drifts.map((drift) => drift.toJson()).toList(),
        }.toString(),
        name: 'accounting_replay_parity',
      );
    }
    return report;
  }

  ReplayDrift? _drift(
    String field,
    double legacyValue,
    double replayValue,
    double tolerance,
  ) {
    final delta = replayValue - legacyValue;
    if (delta.abs() <= tolerance) return null;
    return ReplayDrift(
      field: field,
      legacyValue: legacyValue,
      replayValue: replayValue,
      delta: delta,
    );
  }
}
