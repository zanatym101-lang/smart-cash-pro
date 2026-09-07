import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/ai_parsing_service.dart';
import 'package:king_wallet_accounting/ai_sms/customer_matching_service.dart';
import 'package:king_wallet_accounting/ai_sms/duplicate_detection_service.dart';
import 'package:king_wallet_accounting/ai_sms/sms_flow_analytics.dart';
import 'package:king_wallet_accounting/ai_sms/models/ai_parse_result.dart';
import 'package:king_wallet_accounting/ai_sms/models/incoming_message.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';
import 'package:king_wallet_accounting/ai_sms/parsed_draft_to_use_case_mapper.dart';
import 'package:king_wallet_accounting/ai_sms/recent_draft_store.dart';
import 'package:king_wallet_accounting/ai_sms/sms_accounting_integration_service.dart';
import 'package:king_wallet_accounting/ai_sms/sms_parser_service.dart';
import 'package:king_wallet_accounting/ai_sms/sms_review_screen.dart';
import 'package:king_wallet_accounting/ai_sms/transaction_anomaly_service.dart';
import 'package:king_wallet_accounting/application/use_cases/create_deferred_receive_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_deferred_transfer_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_receive_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_transfer_use_case.dart';
import 'package:king_wallet_accounting/config/app_env.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_event_repository.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_snapshot_repository.dart';

void main() {
  group('SmsAccountingIntegrationService', () {
    late InMemoryEventRepository eventRepository;
    late InMemorySnapshotRepository snapshotRepository;
    late RecentDraftStore recentDraftStore;
    late List<Map<String, Object?>> logs;
    late SmsAccountingIntegrationService service;
    late SmsFlowAnalyticsTracker analyticsTracker;
    var idCounter = 0;
    DebugPrintCallback? originalDebugPrint;

    setUp(() {
      idCounter = 0;
      currentEnv = AppEnv.dev;
      eventRepository = InMemoryEventRepository([
        const OpeningBalancesRecorded(drawer: 0, wallets: 1000),
      ]);
      snapshotRepository = InMemorySnapshotRepository();
      recentDraftStore = RecentDraftStore();
      logs = [];
      analyticsTracker = SmsFlowAnalyticsTracker();
      service = SmsAccountingIntegrationService(
        parserService: SmsParserService(),
        duplicateDetectionService: DuplicateDetectionService(
          store: recentDraftStore,
        ),
        mapper: ParsedDraftToUseCaseMapper(
          idGenerator: () => 'id-${++idCounter}',
        ),
        recentDraftStore: recentDraftStore,
        createTransferUseCase: CreateTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        createReceiveUseCase: CreateReceiveUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        createDeferredTransferUseCase: CreateDeferredTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        createDeferredReceiveUseCase: CreateDeferredReceiveUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        logSink: logs.add,
        analyticsTracker: analyticsTracker,
      );
    });

    tearDown(() {
      currentEnv = AppEnv.dev;
      if (originalDebugPrint != null) {
        debugPrint = originalDebugPrint!;
      }
    });

    testWidgets(
      'full flow parses message then review then confirm then executes accounting',
      (tester) async {
        final parseResult = service.parse(
          IncomingMessage(
            sender: 'Vodafone Cash',
            body: 'تم تحويل مبلغ 500 جنيه. رقم العملية VOD1001',
            receivedAt: DateTime(2026, 5, 2, 10, 0),
          ),
        );

        final reviewedDraft = await _reviewDraft(tester, parseResult.draft);

        expect(reviewedDraft, isNotNull);

        final result = await service.executeConfirmedDraft(
          draft: reviewedDraft!,
          userConfirmed: true,
          reviewed: true,
        );

        expect(result.executed, isTrue);
        expect(result.status, SmsAccountingExecutionStatus.executed);
        expect(result.accountingResult, isNotNull);
        expect(result.accountingResult!.snapshot.drawer, closeTo(500, 0.0001));
        expect(result.accountingResult!.snapshot.wallets, closeTo(500, 0.0001));
        expect(
          result.accountingResult!.snapshot.availableLiquidityNow,
          closeTo(1000, 0.0001),
        );
        expect(
          result.accountingResult!.snapshot.realCapitalApproved,
          closeTo(1000, 0.0001),
        );
        expect(recentDraftStore.getAll(), hasLength(1));
        expect(
          logs.map((entry) => entry['type']),
          containsAll([
            'incoming_sms',
            'sms_parse_result',
            'sms_duplicate_check',
            'sms_accounting_plan',
            'sms_accounting_execution',
          ]),
        );
        expect(analyticsTracker.snapshot().parsedMessages, 1);
        expect(analyticsTracker.snapshot().successfulExecutions, 1);
      },
    );

    test('duplicate high confidence blocks execution', () async {
      recentDraftStore.add(
        ParsedTransactionDraft(
          operationType: ParsedOperationType.transfer,
          amount: 500,
          sender: 'Vodafone Cash',
          effectiveDate: DateTime(2026, 5, 2, 10, 0),
          reference: 'SAME-REF',
          provider: 'Vodafone Cash',
          confidence: ParseConfidence.high,
          warnings: const [],
          rawMessage: 'raw-old',
        ),
      );

      final result = await service.executeConfirmedDraft(
        draft: ParsedTransactionDraft(
          operationType: ParsedOperationType.transfer,
          amount: 500,
          sender: 'Vodafone Cash',
          effectiveDate: DateTime(2026, 5, 2, 10, 1),
          reference: 'same-ref',
          provider: 'Vodafone Cash',
          confidence: ParseConfidence.high,
          warnings: const [],
          rawMessage: 'raw-new',
        ),
        userConfirmed: true,
        reviewed: true,
      );

      expect(result.executed, isFalse);
      expect(
        result.status,
        SmsAccountingExecutionStatus.blockedHighConfidenceDuplicate,
      );
      expect(await eventRepository.loadEvents(), hasLength(1));
      expect(analyticsTracker.snapshot().duplicateBlocks, 1);
    });

    test('medium confidence duplicate allows override', () async {
      recentDraftStore.add(
        ParsedTransactionDraft(
          operationType: ParsedOperationType.transfer,
          amount: 500,
          sender: 'Etisalat Cash',
          effectiveDate: DateTime(2026, 5, 2, 10, 0),
          reference: null,
          provider: 'Etisalat Cash',
          confidence: ParseConfidence.medium,
          warnings: const [],
          rawMessage: 'raw-old',
        ),
      );

      final incomingDraft = ParsedTransactionDraft(
        operationType: ParsedOperationType.transfer,
        amount: 500,
        sender: 'Etisalat Cash',
        effectiveDate: DateTime(2026, 5, 2, 10, 3),
        reference: null,
        provider: 'Etisalat Cash',
        walletId: 1,
        walletName: 'Main Wallet',
        confidence: ParseConfidence.medium,
        warnings: const [],
        rawMessage: 'raw-new',
      );

      final blocked = await service.executeConfirmedDraft(
        draft: incomingDraft,
        userConfirmed: true,
        reviewed: true,
      );
      expect(
        blocked.status,
        SmsAccountingExecutionStatus
            .blockedMediumConfidenceDuplicateNeedsOverride,
      );

      final executed = await service.executeConfirmedDraft(
        draft: incomingDraft,
        userConfirmed: true,
        reviewed: true,
        allowMediumDuplicateOverride: true,
      );

      expect(executed.executed, isTrue);
      expect(executed.accountingResult, isNotNull);
      expect(executed.accountingResult!.snapshot.drawer, closeTo(500, 0.0001));
      expect(executed.accountingResult!.snapshot.wallets, closeTo(500, 0.0001));
      final snapshot = analyticsTracker.snapshot();
      expect(snapshot.duplicateWarnings, 1);
      expect(snapshot.overrideExecutions, 1);
      expect(snapshot.successfulExecutions, 1);
    });

    test(
      'AI suggestion fills low-confidence financial SMS for review only',
      () async {
        var aiCalls = 0;
        service = SmsAccountingIntegrationService(
          parserService: SmsParserService(),
          duplicateDetectionService: DuplicateDetectionService(
            store: recentDraftStore,
          ),
          mapper: ParsedDraftToUseCaseMapper(
            idGenerator: () => 'id-${++idCounter}',
          ),
          recentDraftStore: recentDraftStore,
          createTransferUseCase: CreateTransferUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          createReceiveUseCase: CreateReceiveUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          createDeferredTransferUseCase: CreateDeferredTransferUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          createDeferredReceiveUseCase: CreateDeferredReceiveUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          aiParsingService: AiParsingService(
            suggestionProvider: (message) async {
              aiCalls++;
              return AiParseResult(
                suggestion: ParsedTransactionDraft(
                  operationType: ParsedOperationType.receive,
                  amount: 450,
                  sender: message.sender,
                  effectiveDate: message.receivedAt ?? DateTime(2026, 5, 2),
                  reference: 'AI450',
                  provider: 'Vodafone Cash',
                  confidence: ParseConfidence.medium,
                  warnings: const [],
                  rawMessage: message.body,
                ),
                confidence: ParseConfidence.medium,
                explanation:
                    'AI extracted amount, operation, reference, provider.',
                extractedFields: const {
                  'amount': 450.0,
                  'operationType': 'receive',
                  'reference': 'AI450',
                  'provider': 'Vodafone Cash',
                },
              );
            },
          ),
        );

        final result = await service.parseAsync(
          const IncomingMessage(
            sender: 'Unknown Sender',
            body: 'Wallet notice amount 450 EGP ref AI450 credited',
          ),
        );

        expect(aiCalls, 1);
        expect(result.aiParseResult, isNotNull);
        expect(result.draft.aiSuggested, isTrue);
        expect(result.draft.operationType, ParsedOperationType.receive);
        expect(result.draft.amount, closeTo(450, 0.0001));
        expect(result.draft.reference, 'AI450');
        expect(result.draft.provider, 'Vodafone Cash');
        expect(result.requiresManualReview, isTrue);
        expect(recentDraftStore.getAll(), isEmpty);
        expect(await eventRepository.loadEvents(), hasLength(1));
      },
    );

    test(
      'deterministic parser stays primary and does not call AI on high confidence',
      () async {
        var aiCalls = 0;
        service = SmsAccountingIntegrationService(
          parserService: SmsParserService(),
          duplicateDetectionService: DuplicateDetectionService(
            store: recentDraftStore,
          ),
          mapper: ParsedDraftToUseCaseMapper(),
          recentDraftStore: recentDraftStore,
          createTransferUseCase: CreateTransferUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          createReceiveUseCase: CreateReceiveUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          createDeferredTransferUseCase: CreateDeferredTransferUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          createDeferredReceiveUseCase: CreateDeferredReceiveUseCase(
            eventRepository: eventRepository,
            snapshotRepository: snapshotRepository,
          ),
          aiParsingService: AiParsingService(
            suggestionProvider: (message) async {
              aiCalls++;
              return null;
            },
          ),
        );

        final result = await service.parseAsync(
          IncomingMessage(
            sender: 'VF-Cash',
            body: 'تم تحويل مبلغ 500 جنيه. Txn ID: VOD1001',
            receivedAt: DateTime(2026, 5, 2, 10, 0),
          ),
        );

        expect(aiCalls, 0);
        expect(result.aiParseResult, isNull);
        expect(result.draft.aiSuggested, isFalse);
        expect(result.draft.provider, 'Vodafone Cash');
        expect(result.draft.amount, closeTo(500, 0.0001));
        expect(result.draft.reference, 'VOD1001');
      },
    );

    test('AI unavailable falls back to deterministic parser only', () async {
      service = SmsAccountingIntegrationService(
        parserService: SmsParserService(),
        duplicateDetectionService: DuplicateDetectionService(
          store: recentDraftStore,
        ),
        mapper: ParsedDraftToUseCaseMapper(),
        recentDraftStore: recentDraftStore,
        createTransferUseCase: CreateTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        createReceiveUseCase: CreateReceiveUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        createDeferredTransferUseCase: CreateDeferredTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        createDeferredReceiveUseCase: CreateDeferredReceiveUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ),
        aiParsingService: const AiParsingService(),
      );

      final result = await service.parseAsync(
        const IncomingMessage(
          sender: 'Unknown Sender',
          body: 'Wallet notice amount 450 EGP ref AI450 credited',
        ),
      );

      expect(result.aiParseResult, isNull);
      expect(result.draft.aiSuggested, isFalse);
      expect(result.draft.amount, closeTo(450, 0.0001));
      expect(result.draft.operationType, ParsedOperationType.receive);
    });

    test('AI suggestions cannot execute without user review', () async {
      final draft = ParsedTransactionDraft(
        operationType: ParsedOperationType.receive,
        amount: 450,
        sender: 'Unknown Sender',
        effectiveDate: DateTime(2026, 5, 2, 10),
        reference: 'AI450',
        provider: 'Vodafone Cash',
        confidence: ParseConfidence.medium,
        warnings: const [],
        rawMessage: 'Wallet notice amount 450 EGP ref AI450 credited',
        aiSuggested: true,
      );

      final result = await service.executeConfirmedDraft(
        draft: draft,
        userConfirmed: true,
        reviewed: false,
      );

      expect(result.executed, isFalse);
      expect(
        result.status,
        SmsAccountingExecutionStatus.blockedLowConfidenceNeedsReview,
      );
      expect(await eventRepository.loadEvents(), hasLength(1));
      expect(recentDraftStore.getAll(), isEmpty);
    });

    test(
      'advanced AI suggestions are advisory and do not execute accounting',
      () async {
        final draft = ParsedTransactionDraft(
          operationType: ParsedOperationType.receive,
          amount: 12000,
          sender: 'Unknown Sender',
          effectiveDate: DateTime(2026, 5, 2, 10),
          reference: 'ADV12000',
          provider: 'Vodafone Cash',
          confidence: ParseConfidence.medium,
          warnings: const [],
          rawMessage: 'credited 12000 EGP phone 01012345678 ref ADV12000',
          aiSuggested: true,
        );

        final customerSuggestion = const CustomerMatchingService().suggest(
          draft: draft,
          existingCustomers: const [
            CustomerMatchCandidate(
              customerName: 'Ahmed Ali',
              phone: '01012345678',
            ),
          ],
        );
        final anomaly = const TransactionAnomalyService().analyze(
          draft: draft,
          recentDrafts: const [],
        );

        expect(customerSuggestion, isNotNull);
        expect(customerSuggestion!.matchedCustomer, 'Ahmed Ali');
        expect(anomaly.level, AnomalyLevel.high);
        expect(await eventRepository.loadEvents(), hasLength(1));
        expect(recentDraftStore.getAll(), isEmpty);
      },
    );

    test(
      'SMS transfer marked deferred with customer creates deferred transfer',
      () async {
        final result = await service.executeConfirmedDraft(
          draft: ParsedTransactionDraft(
            operationType: ParsedOperationType.transfer,
            amount: 700,
            sender: 'Vodafone Cash',
            effectiveDate: DateTime(2026, 5, 2, 10),
            reference: 'DEF-TX',
            provider: 'Vodafone Cash',
            walletId: 1,
            walletName: 'Main Wallet',
            customerName: 'Deferred Customer',
            confidence: ParseConfidence.high,
            warnings: const [],
            rawMessage: 'transfer 700 ref DEF-TX',
            transactionMode: TransactionMode.deferred,
          ),
          userConfirmed: true,
          reviewed: true,
        );

        expect(result.executed, isTrue);
        expect(result.plan!.kind, SmsUseCaseKind.deferredTransfer);
        expect(result.plan!.mode, SmsExecutionMode.pending);
        expect(
          result.accountingResult!.snapshot.pendingReceivable,
          closeTo(700, 0.0001),
        );
        expect(result.accountingResult!.snapshot.drawer, closeTo(0, 0.0001));
      },
    );

    test(
      'SMS receive marked deferred with customer creates deferred receive',
      () async {
        final result = await service.executeConfirmedDraft(
          draft: ParsedTransactionDraft(
            operationType: ParsedOperationType.receive,
            amount: 350,
            sender: 'Vodafone Cash',
            effectiveDate: DateTime(2026, 5, 2, 10),
            reference: 'DEF-RX',
            provider: 'Vodafone Cash',
            walletId: 1,
            walletName: 'Main Wallet',
            customerName: 'Deferred Customer',
            confidence: ParseConfidence.high,
            warnings: const [],
            rawMessage: 'receive 350 ref DEF-RX',
            transactionMode: TransactionMode.deferred,
          ),
          userConfirmed: true,
          reviewed: true,
        );

        expect(result.executed, isTrue);
        expect(result.plan!.kind, SmsUseCaseKind.deferredReceive);
        expect(result.plan!.mode, SmsExecutionMode.pending);
        expect(
          result.accountingResult!.snapshot.pendingPayable,
          closeTo(350, 0.0001),
        );
        expect(result.accountingResult!.snapshot.drawer, closeTo(0, 0.0001));
      },
    );

    test('deferred SMS without customer fails validation', () async {
      final result = await service.executeConfirmedDraft(
        draft: ParsedTransactionDraft(
          operationType: ParsedOperationType.transfer,
          amount: 700,
          sender: 'Vodafone Cash',
          effectiveDate: DateTime(2026, 5, 2, 10),
          reference: 'NO-CUSTOMER',
          provider: 'Vodafone Cash',
          walletId: 1,
          walletName: 'Main Wallet',
          confidence: ParseConfidence.high,
          warnings: const [],
          rawMessage: 'transfer 700',
          transactionMode: TransactionMode.deferred,
        ),
        userConfirmed: true,
        reviewed: true,
      );

      expect(result.executed, isFalse);
      expect(
        result.status,
        SmsAccountingExecutionStatus.blockedPendingCustomerRequired,
      );
      expect(await eventRepository.loadEvents(), hasLength(1));
    });

    test('SMS without selected wallet fails validation', () async {
      final result = await service.executeConfirmedDraft(
        draft: ParsedTransactionDraft(
          operationType: ParsedOperationType.transfer,
          amount: 700,
          sender: 'Vodafone Cash',
          effectiveDate: DateTime(2026, 5, 2, 10),
          reference: 'NO-WALLET',
          provider: 'Vodafone Cash',
          confidence: ParseConfidence.high,
          warnings: const [],
          rawMessage: 'transfer 700',
        ),
        userConfirmed: true,
        reviewed: true,
      );

      expect(result.executed, isFalse);
      expect(result.status, SmsAccountingExecutionStatus.blockedWalletRequired);
      expect(await eventRepository.loadEvents(), hasLength(1));
    });

    test('duplicate blocking still applies to deferred SMS', () async {
      recentDraftStore.add(
        ParsedTransactionDraft(
          operationType: ParsedOperationType.transfer,
          amount: 700,
          sender: 'Vodafone Cash',
          effectiveDate: DateTime(2026, 5, 2, 10),
          reference: 'DUP-DEF',
          provider: 'Vodafone Cash',
          walletId: 1,
          walletName: 'Main Wallet',
          customerName: 'Deferred Customer',
          confidence: ParseConfidence.high,
          warnings: const [],
          rawMessage: 'old deferred',
          transactionMode: TransactionMode.deferred,
        ),
      );

      final result = await service.executeConfirmedDraft(
        draft: ParsedTransactionDraft(
          operationType: ParsedOperationType.transfer,
          amount: 700,
          sender: 'Vodafone Cash',
          effectiveDate: DateTime(2026, 5, 2, 10, 1),
          reference: 'DUP-DEF',
          provider: 'Vodafone Cash',
          walletId: 1,
          walletName: 'Main Wallet',
          customerName: 'Deferred Customer',
          confidence: ParseConfidence.high,
          warnings: const [],
          rawMessage: 'new deferred',
          transactionMode: TransactionMode.deferred,
        ),
        userConfirmed: true,
        reviewed: true,
      );

      expect(result.executed, isFalse);
      expect(
        result.status,
        SmsAccountingExecutionStatus.blockedHighConfidenceDuplicate,
      );
      expect(await eventRepository.loadEvents(), hasLength(1));
    });

    test('debug mode prints sanitized prefixed logs', () {
      currentEnv = AppEnv.build;
      final printed = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          printed.add(message);
        }
      };

      service.parse(
        IncomingMessage(
          sender: 'Vodafone Cash',
          body: 'تم تحويل مبلغ 500 جنيه. Txn ID: ABC12345',
          receivedAt: DateTime(2026, 5, 2, 10, 0),
        ),
      );

      expect(printed, isNotEmpty);
      final diagnosticLine = printed.firstWhere(
        (line) => line.startsWith('[SMS DIAGNOSTIC] '),
      );
      expect(diagnosticLine, isNot(contains('تم تحويل مبلغ')));
      final payload =
          jsonDecode(diagnosticLine.substring('[SMS DIAGNOSTIC] '.length))
              as Map<String, dynamic>;
      expect(payload['type'], 'incoming_sms');
      final source = payload['source'] as Map<String, dynamic>;
      expect(source['sender'], 'Vodafone Cash');
      expect(source.containsKey('body'), isFalse);
      expect(source['bodyLength'], greaterThan(0));
    });
  });
}

Future<ParsedTransactionDraft?> _reviewDraft(
  WidgetTester tester,
  ParsedTransactionDraft draft,
) async {
  ParsedTransactionDraft? reviewed;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                reviewed = await Navigator.of(context)
                    .push<ParsedTransactionDraft>(
                      MaterialPageRoute(
                        builder: (_) => SmsReviewScreen(
                          draft: draft,
                          walletOptions: const [
                            SmsReviewWalletOption(
                              id: 1,
                              name: 'Main Wallet',
                              phone: '01000000001',
                            ),
                          ],
                        ),
                      ),
                    );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ElevatedButton).last);
  await tester.pumpAndSettle();

  return reviewed;
}
