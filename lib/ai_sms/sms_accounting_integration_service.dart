import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import '../application/use_cases/create_deferred_receive_use_case.dart';
import '../application/use_cases/create_deferred_transfer_use_case.dart';
import '../application/use_cases/create_receive_use_case.dart';
import '../application/use_cases/create_transfer_use_case.dart';
import '../application/use_cases/use_case_models.dart';
import '../domain/services/snapshot_builder.dart';
import 'ai_parsing_service.dart';
import 'duplicate_detection_service.dart';
import 'number_normalizer.dart';
import 'models/ai_parse_result.dart';
import 'models/duplicate_check_result.dart';
import 'models/incoming_message.dart';
import 'models/message_parse_result.dart';
import 'models/parsed_transaction_draft.dart';
import 'parsed_draft_to_use_case_mapper.dart';
import 'recent_draft_store.dart';
import 'sms_flow_analytics.dart';
import 'sms_parser_service.dart';

enum SmsAccountingExecutionStatus {
  executed,
  failedExecution,
  blockedUserConfirmationMissing,
  blockedLowConfidenceNeedsReview,
  blockedExplicitOperationRequired,
  blockedInvalidAmount,
  blockedWalletRequired,
  blockedPendingCustomerRequired,
  blockedHighConfidenceDuplicate,
  blockedMediumConfidenceDuplicateNeedsOverride,
}

class SmsAccountingExecutionResult {
  const SmsAccountingExecutionResult({
    required this.status,
    required this.draft,
    required this.duplicateResult,
    required this.logs,
    this.accountingResult,
    this.plan,
    this.errorMessage,
    this.persistenceDetails,
  });

  final SmsAccountingExecutionStatus status;
  final ParsedTransactionDraft draft;
  final DuplicateCheckResult duplicateResult;
  final UseCaseResult? accountingResult;
  final ParsedDraftUseCasePlan? plan;
  final List<Map<String, Object?>> logs;
  final String? errorMessage;
  final Map<String, dynamic>? persistenceDetails;

  bool get executed => status == SmsAccountingExecutionStatus.executed;
}

class SmsAccountingIntegrationService {
  SmsAccountingIntegrationService({
    required this.parserService,
    required this.duplicateDetectionService,
    required this.mapper,
    required this.recentDraftStore,
    required this.createTransferUseCase,
    required this.createReceiveUseCase,
    required this.createDeferredTransferUseCase,
    required this.createDeferredReceiveUseCase,
    this.logSink,
    this.aiParsingService,
    SmsFlowAnalyticsTracker? analyticsTracker,
  }) : analyticsTracker = analyticsTracker ?? SmsFlowAnalyticsTracker();

  final SmsParserService parserService;
  final DuplicateDetectionService duplicateDetectionService;
  final ParsedDraftToUseCaseMapper mapper;
  final RecentDraftStore recentDraftStore;
  final CreateTransferUseCase createTransferUseCase;
  final CreateReceiveUseCase createReceiveUseCase;
  final CreateDeferredTransferUseCase createDeferredTransferUseCase;
  final CreateDeferredReceiveUseCase createDeferredReceiveUseCase;
  final void Function(Map<String, Object?> entry)? logSink;
  final AiParsingService? aiParsingService;
  final SmsFlowAnalyticsTracker analyticsTracker;

  MessageParseResult parse(IncomingMessage message) {
    _emitLog({
      'type': 'incoming_sms',
      'source': {
        'sender': message.sender,
        'body': message.body,
        'receivedAt': message.receivedAt?.toIso8601String(),
      },
    });
    final result = parserService.parse(message);
    analyticsTracker.recordParsedMessage();
    _emitLog({
      'type': 'sms_parse_result',
      'confidence': result.draft.confidence.name,
      'source': {
        'sender': message.sender,
        'body': message.body,
        'receivedAt': message.receivedAt?.toIso8601String(),
      },
      'parsed_result': result.toJson(),
    });
    return result;
  }

  Future<MessageParseResult> parseAsync(
    IncomingMessage message, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    late final MessageParseResult deterministicResult;
    try {
      deterministicResult = parse(message);
    } catch (error) {
      _emitLog({
        'type': 'sms_parse_failure',
        'source': {
          'sender': message.sender,
          'body': message.body,
          'receivedAt': message.receivedAt?.toIso8601String(),
        },
        'error': error.toString(),
      });
      rethrow;
    }

    try {
      return await _maybeApplyAiSuggestion(
        message: message,
        deterministicResult: deterministicResult,
      ).timeout(timeout);
    } catch (error) {
      _emitLog({
        'type': 'sms_ai_parse_unavailable',
        'source': {
          'sender': message.sender,
          'receivedAt': message.receivedAt?.toIso8601String(),
        },
        'error': error.toString(),
      });
      return deterministicResult;
    }
  }

  DuplicateCheckResult checkDuplicate(ParsedTransactionDraft draft) {
    final result = duplicateDetectionService.check(draft);
    _emitLog({
      'type': 'sms_duplicate_check',
      'draft': draft.toJson(),
      'duplicate_result': result.toJson(),
    });
    return result;
  }

  Future<SmsAccountingExecutionResult> executeConfirmedDraft({
    required ParsedTransactionDraft draft,
    required bool userConfirmed,
    required bool reviewed,
    bool allowMediumDuplicateOverride = false,
    SmsExecutionMode mode = SmsExecutionMode.immediate,
  }) async {
    final logs = <Map<String, Object?>>[];

    void record(Map<String, Object?> entry) {
      logs.add(entry);
      _emitLog(entry);
    }

    final duplicateResult = duplicateDetectionService.check(draft);
    record({
      'type': 'sms_duplicate_check',
      'draft': draft.toJson(),
      'duplicate_result': duplicateResult.toJson(),
    });

    final requestedMode = draft.transactionMode == TransactionMode.deferred
        ? SmsExecutionMode.pending
        : mode;
    final effectiveMode = requestedMode;
    final blockingStatus = _validate(
      draft: draft,
      duplicateResult: duplicateResult,
      userConfirmed: userConfirmed,
      reviewed: reviewed,
      allowMediumDuplicateOverride: allowMediumDuplicateOverride,
      mode: effectiveMode,
      requireWalletSelection: true,
    );
    if (blockingStatus != null) {
      if (blockingStatus ==
          SmsAccountingExecutionStatus.blockedHighConfidenceDuplicate) {
        analyticsTracker.recordDuplicateBlock();
      } else if (blockingStatus ==
          SmsAccountingExecutionStatus
              .blockedMediumConfidenceDuplicateNeedsOverride) {
        analyticsTracker.recordDuplicateWarning();
      }
      record({
        'type': 'sms_accounting_blocked',
        'status': blockingStatus.name,
        'mode': effectiveMode.name,
      });
      return SmsAccountingExecutionResult(
        status: blockingStatus,
        draft: draft,
        duplicateResult: duplicateResult,
        logs: logs,
      );
    }

    final plan = mapper.map(draft: draft, mode: effectiveMode);
    record({
      'type': 'sms_accounting_plan',
      'use_case': plan.useCaseName,
      'transaction_id': plan.transactionId,
      'mode': effectiveMode.name,
      'selected_wallet_id': draft.walletId,
      'selected_wallet_name': draft.walletName,
      'draft': draft.toJson(),
    });
    _emitLog({
        'type': 'execution_started',
        'draft_id': draft.hashCode,
        'repository': 'UseCaseEventStore',
        'mode': effectiveMode.name,
        'selected_wallet_id': draft.walletId,
        'selected_wallet_name': draft.walletName,
      });

    try {
      final accountingResult = await _executePlan(plan);
      final persistenceDetails = {
        'repositoryType': 'UseCaseEventStore',
        'persistedEventCount': accountingResult.events.length,
        'persistedTransactionId': plan.transactionId,
        'snapshotJson': _snapshotToJson(accountingResult.snapshot),
      };
      recentDraftStore.add(draft);
      analyticsTracker.recordSuccessfulExecution(
        usedOverride: allowMediumDuplicateOverride,
      );

      record({
        'type': 'sms_accounting_execution',
        'status': SmsAccountingExecutionStatus.executed.name,
        'transaction_id': plan.transactionId,
        'use_case': plan.useCaseName,
        'repository_type': 'UseCaseEventStore',
        'persisted_event_count': accountingResult.events.length,
        'selected_wallet_id': draft.walletId,
        'selected_wallet_name': draft.walletName,
        'snapshot': _snapshotToJson(accountingResult.snapshot),
        'analytics': analyticsTracker.snapshot().toJson(),
      });

      return SmsAccountingExecutionResult(
        status: SmsAccountingExecutionStatus.executed,
        draft: draft,
        duplicateResult: duplicateResult,
        accountingResult: accountingResult,
        plan: plan,
        logs: logs,
        persistenceDetails: persistenceDetails,
      );
    } catch (e) {
        _emitLog({
          'type': 'execution_error',
          'draft_id': draft.hashCode,
          'repository': 'UseCaseEventStore',
          'error': e.toString(),
        });
      return SmsAccountingExecutionResult(
        status: SmsAccountingExecutionStatus.failedExecution,
        draft: draft,
        duplicateResult: duplicateResult,
        plan: plan,
        logs: logs,
        errorMessage: e.toString(),
      );
    }
  }

  SmsAccountingExecutionStatus? _validate({
    required ParsedTransactionDraft draft,
    required DuplicateCheckResult duplicateResult,
    required bool userConfirmed,
    required bool reviewed,
    required bool allowMediumDuplicateOverride,
    required SmsExecutionMode mode,
    required bool requireWalletSelection,
  }) {
    if (!userConfirmed) {
      return SmsAccountingExecutionStatus.blockedUserConfirmationMissing;
    }
    if (draft.confidence == ParseConfidence.low && !reviewed) {
      return SmsAccountingExecutionStatus.blockedLowConfidenceNeedsReview;
    }
    if (draft.aiSuggested && !reviewed) {
      return SmsAccountingExecutionStatus.blockedLowConfidenceNeedsReview;
    }
    if (draft.operationType == ParsedOperationType.unknown) {
      return SmsAccountingExecutionStatus.blockedExplicitOperationRequired;
    }
    final amount = draft.amount;
    if (amount == null || amount <= 0) {
      return SmsAccountingExecutionStatus.blockedInvalidAmount;
    }
    if (duplicateResult.isDuplicate &&
        duplicateResult.confidence == ParseConfidence.high) {
      return SmsAccountingExecutionStatus.blockedHighConfidenceDuplicate;
    }
    if (duplicateResult.isDuplicate &&
        duplicateResult.confidence == ParseConfidence.medium &&
        !allowMediumDuplicateOverride) {
      return SmsAccountingExecutionStatus
          .blockedMediumConfidenceDuplicateNeedsOverride;
    }
    if (requireWalletSelection &&
        draft.walletId == null &&
        (draft.walletName == null || draft.walletName!.trim().isEmpty)) {
      return SmsAccountingExecutionStatus.blockedWalletRequired;
    }
    if ((mode == SmsExecutionMode.pending ||
            draft.transactionMode == TransactionMode.deferred) &&
        (draft.customerName == null || draft.customerName!.trim().isEmpty)) {
      return SmsAccountingExecutionStatus.blockedPendingCustomerRequired;
    }
    return null;
  }

  Future<UseCaseResult> _executePlan(ParsedDraftUseCasePlan plan) {
    switch (plan.kind) {
      case SmsUseCaseKind.transfer:
        return createTransferUseCase.execute(plan.transferInput!);
      case SmsUseCaseKind.receive:
        return createReceiveUseCase.execute(plan.receiveInput!);
      case SmsUseCaseKind.deferredTransfer:
        return createDeferredTransferUseCase.execute(
          plan.deferredTransferInput!,
        );
      case SmsUseCaseKind.deferredReceive:
        return createDeferredReceiveUseCase.execute(plan.deferredReceiveInput!);
    }
  }

  SmsFlowAnalyticsSnapshot analyticsSnapshot() => analyticsTracker.snapshot();

  Future<MessageParseResult> _maybeApplyAiSuggestion({
    required IncomingMessage message,
    required MessageParseResult deterministicResult,
  }) async {
    if (!enableAi) return deterministicResult;
    final service = aiParsingService;
    if (service == null) return deterministicResult;
    if (!_shouldUseAi(message, deterministicResult)) {
      return deterministicResult;
    }

    _emitLog({
      'type': 'sms_ai_parse_start',
      'confidence': deterministicResult.draft.confidence.name,
      'matchedRuleId': deterministicResult.matchedRuleId,
    });

    final aiResult = await service.suggest(message);
    if (aiResult == null) {
      _emitLog({'type': 'sms_ai_parse_unavailable'});
      return deterministicResult;
    }

    final merged = _mergeAiSuggestion(
      deterministicResult: deterministicResult,
      aiResult: aiResult,
    );
    _emitLog({
      'type': 'sms_ai_parse_result',
      'confidence': aiResult.confidence.name,
      'explanation': aiResult.explanation,
      'extracted_fields': aiResult.extractedFields,
    });
    return merged;
  }

  bool _shouldUseAi(
    IncomingMessage message,
    MessageParseResult deterministicResult,
  ) {
    if (deterministicResult.draft.confidence == ParseConfidence.low) {
      return true;
    }
    return deterministicResult.matchedRuleId == null &&
        _looksFinancial(message.body);
  }

  bool _looksFinancial(String body) {
    final normalized = NumberNormalizer.normalizeText(body).toLowerCase();
    final hasAmount = RegExp(r'\d+(?:[.,]\d+)?').hasMatch(normalized);
    if (!hasAmount) return false;
    const markers = [
      'egp',
      'le',
      'cash',
      'wallet',
      'txn',
      'ref',
      'reference',
      'transfer',
      'transferred',
      'receive',
      'received',
      'debit',
      'debited',
      'credit',
      'credited',
      'جنيه',
      'محفظ',
      'عملية',
      'مرجع',
      'تحويل',
      'استلام',
      'خصم',
      'إضافة',
      'اضافة',
      'رصيد',
    ];
    return markers.any(normalized.contains);
  }

  MessageParseResult _mergeAiSuggestion({
    required MessageParseResult deterministicResult,
    required AiParseResult aiResult,
  }) {
    final deterministic = deterministicResult.draft;
    final suggestion = aiResult.suggestion;
    final operationType =
        deterministic.operationType != ParsedOperationType.unknown
        ? deterministic.operationType
        : suggestion.operationType;
    final confidence = _strongestConfidence(
      deterministic.confidence,
      aiResult.confidence,
    );
    final warnings = <String>[
      ...deterministic.warnings,
      'اقتراح AI: ${aiResult.explanation}',
    ];

    final draft = deterministic.copyWith(
      operationType: operationType,
      amount: deterministic.amount ?? suggestion.amount,
      reference: deterministic.reference ?? suggestion.reference,
      provider: deterministic.provider ?? suggestion.provider,
      confidence: confidence,
      warnings: warnings,
      aiSuggested: true,
    );

    return MessageParseResult(
      draft: draft,
      matchedRuleId: deterministicResult.matchedRuleId,
      reasons: [...deterministicResult.reasons, 'ai_participated'],
      requiresManualReview: true,
      aiParseResult: aiResult,
    );
  }

  ParseConfidence _strongestConfidence(
    ParseConfidence deterministic,
    ParseConfidence ai,
  ) {
    if (deterministic == ParseConfidence.high || ai == ParseConfidence.high) {
      return ParseConfidence.high;
    }
    if (deterministic == ParseConfidence.medium ||
        ai == ParseConfidence.medium) {
      return ParseConfidence.medium;
    }
    return ParseConfidence.low;
  }

  Map<String, Object?> _snapshotToJson(AccountingSnapshot snapshot) {
    return {
      'drawer': snapshot.drawer,
      'wallets': snapshot.wallets,
      'pendingReceivable': snapshot.pendingReceivable,
      'pendingPayable': snapshot.pendingPayable,
      'openClaimsReceivable': snapshot.openClaimsReceivable,
      'openClaimsPayable': snapshot.openClaimsPayable,
      'profitFromClientFees': snapshot.profitFromClientFees,
      'networkFeesTotal': snapshot.networkFeesTotal,
      'availableLiquidityNow': snapshot.availableLiquidityNow,
      'realCapitalApproved': snapshot.realCapitalApproved,
    };
  }

  void _emitLog(Map<String, Object?> entry) {
    logSink?.call(entry);
    if (kDebugMode) {
      debugPrint('[SMS DIAGNOSTIC] ${jsonEncode(_sanitizeBuildLog(entry))}');
    }
  }

  Map<String, Object?> _sanitizeBuildLog(Map<String, Object?> entry) {
    final type = entry['type'];
    switch (type) {
      case 'incoming_sms':
        final source = (entry['source'] as Map?)?.cast<Object?, Object?>();
        return {
          'type': type,
          'source': {
            'sender': source?['sender'],
            'receivedAt': source?['receivedAt'],
            'bodyLength': (source?['body'] as String?)?.length ?? 0,
          },
        };
      case 'sms_parse_result':
        return {
          'type': type,
          'confidence': entry['confidence'],
          'source': _sanitizeSource(entry['source']),
          'parsed_result': _sanitizeParsedResult(entry['parsed_result']),
        };
      case 'sms_parse_failure':
        return {
          'type': type,
          'source': _sanitizeSource(entry['source']),
          'error': entry['error'],
        };
      case 'sms_duplicate_check':
        return {
          'type': type,
          'draft': _sanitizeDraft(entry['draft']),
          'duplicate_result': _sanitizeDuplicateResult(
            entry['duplicate_result'],
          ),
        };
      case 'sms_accounting_plan':
        return {
          'type': type,
          'use_case': entry['use_case'],
          'transaction_id': entry['transaction_id'],
          'mode': entry['mode'],
          'draft': _sanitizeDraft(entry['draft']),
        };
      case 'sms_accounting_execution':
      case 'sms_accounting_execution_failure':
      case 'sms_accounting_blocked':
        return Map<String, Object?>.from(entry);
      default:
        return entry;
    }
  }

  Map<String, Object?> _sanitizeSource(Object? raw) {
    final source = (raw as Map?)?.cast<Object?, Object?>();
    return {
      'sender': source?['sender'],
      'receivedAt': source?['receivedAt'],
      'bodyLength': (source?['body'] as String?)?.length ?? 0,
    };
  }

  Map<String, Object?> _sanitizeParsedResult(Object? raw) {
    final parsed = (raw as Map?)?.cast<Object?, Object?>();
    final draft = (parsed?['draft'] as Map?)?.cast<Object?, Object?>();
    return {
      'matched_rule_id': parsed?['matched_rule_id'],
      'requires_manual_review': parsed?['requires_manual_review'],
      'draft': draft == null ? null : _sanitizeDraft(draft),
      'reasons': parsed?['reasons'],
    };
  }

  Map<String, Object?> _sanitizeDraft(Object? raw) {
    final draft = (raw as Map?)?.cast<Object?, Object?>();
    return {
      'operationType': draft?['operationType'],
      'amount': draft?['amount'],
      'sender': draft?['sender'],
      'provider': draft?['provider'],
      'walletId': draft?['walletId'],
      'walletName': draft?['walletName'],
      'effectiveDate': draft?['effectiveDate'],
      'reference': _maskReference(draft?['reference']),
      'confidence': draft?['confidence'],
      'warnings': draft?['warnings'],
    };
  }

  Map<String, Object?> _sanitizeDuplicateResult(Object? raw) {
    final duplicate = (raw as Map?)?.cast<Object?, Object?>();
    return {
      'isDuplicate': duplicate?['isDuplicate'],
      'reason': duplicate?['reason'],
      'matchedReference': _maskReference(duplicate?['matchedReference']),
      'confidence': duplicate?['confidence'],
    };
  }

  String? _maskReference(Object? raw) {
    final value = raw?.toString();
    if (value == null || value.isEmpty) return null;
    if (value.length <= 4) {
      return '*' * value.length;
    }
    return '${'*' * (value.length - 4)}${value.substring(value.length - 4)}';
  }
}
