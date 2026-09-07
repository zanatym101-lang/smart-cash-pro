import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/duplicate_detection_service.dart';
import 'package:king_wallet_accounting/ai_sms/models/incoming_message.dart';
import 'package:king_wallet_accounting/ai_sms/models/message_parse_result.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';
import 'package:king_wallet_accounting/ai_sms/parsed_draft_to_use_case_mapper.dart';
import 'package:king_wallet_accounting/ai_sms/recent_draft_store.dart';
import 'package:king_wallet_accounting/ai_sms/sms_accounting_integration_service.dart';
import 'package:king_wallet_accounting/ai_sms/sms_inbox_screen.dart';
import 'package:king_wallet_accounting/ai_sms/sms_inbox_service.dart';
import 'package:king_wallet_accounting/ai_sms/sms_parser_service.dart';
import 'package:king_wallet_accounting/ai_sms/sms_review_screen.dart';
import 'package:king_wallet_accounting/application/use_cases/create_deferred_receive_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_deferred_transfer_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_receive_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_transfer_use_case.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_event_repository.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_snapshot_repository.dart';

void main() {
  SmsAccountingIntegrationService buildService({RecentDraftStore? store}) {
    final recentDraftStore = store ?? RecentDraftStore();
    final eventRepository = InMemoryEventRepository([
      const OpeningBalancesRecorded(drawer: 1000, wallets: 2000),
    ]);
    final snapshotRepository = InMemorySnapshotRepository();

    return SmsAccountingIntegrationService(
      parserService: SmsParserService(),
      duplicateDetectionService: DuplicateDetectionService(
        store: recentDraftStore,
      ),
      mapper: ParsedDraftToUseCaseMapper(idGenerator: () => 'fixed-id'),
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
    );
  }

  final outgoingVodafoneMessage = [
    IncomingMessage(
      id: 'm1',
      sender: 'VF-Cash',
      body: 'تم تحويل مبلغ 500 جنيه. Txn ID: VOD1001',
      receivedAt: DateTime(2026, 5, 2, 10, 0),
    ),
  ];
  const testWalletOptions = [
    SmsReviewWalletOption(id: 1, name: 'Main Wallet', phone: '01000000000'),
  ];

  testWidgets('permission denied shows permission gate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: buildService(),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.denied,
            grantedMessages: outgoingVodafoneMessage,
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('يجب السماح بقراءة الرسائل'), findsOneWidget);
    expect(find.text('السماح'), findsOneWidget);
  });

  testWidgets('permission granted with empty inbox shows empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: buildService(),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.granted,
            grantedMessages: const [],
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('لا توجد رسائل متاحة'), findsOneWidget);
  });

  testWidgets('VF-Cash transfer message appears and opens review screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: buildService(),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.granted,
            grantedMessages: outgoingVodafoneMessage,
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('VF-Cash'), findsOneWidget);

    await tester.tap(find.text('VF-Cash'));
    await _pumpForRoute(tester);

    expect(find.text('مراجعة الرسالة'), findsOneWidget);
    expect(find.text('Vodafone Cash'), findsOneWidget);
  });

  testWidgets('low-confidence known sender still appears in inbox', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: buildService(),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.granted,
            grantedMessages: const [
              IncomingMessage(
                id: 'low-1',
                sender: 'Vodafone',
                body: 'إشعار خدمة فقط',
                receivedAt: null,
              ),
            ],
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Vodafone'), findsOneWidget);
    expect(find.text('إشعار خدمة فقط'), findsOneWidget);
  });

  testWidgets('refresh reloads messages from inbox service', (tester) async {
    final smsInboxService = FakeSmsInboxService(
      initialStatus: SmsInboxPermissionStatus.granted,
      fetchBatches: const [
        [
          IncomingMessage(
            id: 'old',
            sender: 'Vodafone Cash',
            body: 'رسالة قديمة',
            receivedAt: null,
          ),
        ],
        [
          IncomingMessage(
            id: 'new',
            sender: 'VF-Cash',
            body: 'تم خصم 500 جنيه',
            receivedAt: null,
          ),
        ],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: buildService(),
          smsInboxService: smsInboxService,
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('رسالة قديمة'), findsOneWidget);
    expect(find.text('تم خصم 500 جنيه'), findsNothing);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('رسالة قديمة'), findsNothing);
    expect(find.text('تم خصم 500 جنيه'), findsOneWidget);
    expect(smsInboxService.fetchCallCount, greaterThanOrEqualTo(2));
  });

  testWidgets('valid SMS flow succeeds after review confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: buildService(),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.granted,
            grantedMessages: outgoingVodafoneMessage,
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('VF-Cash'));
    await _pumpForRoute(tester);
    await _tapReviewConfirm(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تم تسجيل العملية'), findsOneWidget);
  });

  testWidgets('duplicate blocked shows duplicate snackbar', (tester) async {
    final store = RecentDraftStore();
    store.add(
      ParsedTransactionDraft(
        operationType: ParsedOperationType.transfer,
        amount: 500,
        sender: 'VF-Cash',
        effectiveDate: DateTime(2026, 5, 2, 9, 59),
        reference: 'VOD1001',
        provider: 'Vodafone Cash',
        confidence: ParseConfidence.high,
        warnings: const [],
        rawMessage: 'old',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: buildService(store: store),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.granted,
            grantedMessages: outgoingVodafoneMessage,
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('VF-Cash'));
    await _pumpForRoute(tester);
    await _tapReviewConfirm(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('عملية مكررة'), findsOneWidget);
  });

  testWidgets('parser failure shows parse error feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: FailingParseIntegrationService(
            base: buildService(),
          ),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.granted,
            grantedMessages: outgoingVodafoneMessage,
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('VF-Cash'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تعذر تحليل الرسالة'), findsOneWidget);
  });

  testWidgets('execution failure allows retry and then succeeds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsInboxScreen(
          integrationService: RetryOnceIntegrationService(base: buildService()),
          smsInboxService: FakeSmsInboxService(
            initialStatus: SmsInboxPermissionStatus.granted,
            grantedMessages: outgoingVodafoneMessage,
          ),
          walletOptions: testWalletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('VF-Cash'));
    await _pumpForRoute(tester);
    await _tapReviewConfirm(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تعذر تنفيذ العملية'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تم تسجيل العملية'), findsOneWidget);
  });
}

Future<void> _pumpForRoute(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapReviewConfirm(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -800));
  await tester.pump();
  await tester.tap(find.byType(ElevatedButton).last);
}

class FakeSmsInboxService implements SmsInboxService {
  FakeSmsInboxService({
    required this.initialStatus,
    this.grantedMessages = const [],
    this.fetchBatches,
    this.requestStatus,
  });

  final SmsInboxPermissionStatus initialStatus;
  final SmsInboxPermissionStatus? requestStatus;
  final List<IncomingMessage> grantedMessages;
  final List<List<IncomingMessage>>? fetchBatches;
  int fetchCallCount = 0;
  SmsInboxFetchStats? _lastFetchStats;

  @override
  Future<List<IncomingMessage>> fetchRecentMessages({int limit = 100}) async {
    fetchCallCount++;
    final source = fetchBatches != null && fetchBatches!.isNotEmpty
        ? fetchBatches![(fetchCallCount - 1).clamp(0, fetchBatches!.length - 1)]
        : grantedMessages;
    final messages = source.take(limit).toList(growable: false);
    _lastFetchStats = SmsInboxFetchStats(
      totalFetched: source.length,
      totalAfterSenderFilter: messages.length,
      ignoredSenderCount: source.length - messages.length,
    );
    return messages;
  }

  @override
  Future<SmsInboxPermissionStatus> getPermissionStatus() async => initialStatus;

  @override
  Future<SmsInboxPermissionStatus> requestPermission() async =>
      requestStatus ?? initialStatus;

  @override
  SmsInboxFetchStats? get lastFetchStats => _lastFetchStats;
}

class FailingParseIntegrationService extends SmsAccountingIntegrationService {
  FailingParseIntegrationService({required this.base})
    : super(
        parserService: base.parserService,
        duplicateDetectionService: base.duplicateDetectionService,
        mapper: base.mapper,
        recentDraftStore: base.recentDraftStore,
        createTransferUseCase: base.createTransferUseCase,
        createReceiveUseCase: base.createReceiveUseCase,
        createDeferredTransferUseCase: base.createDeferredTransferUseCase,
        createDeferredReceiveUseCase: base.createDeferredReceiveUseCase,
        logSink: base.logSink,
        analyticsTracker: base.analyticsTracker,
      );

  final SmsAccountingIntegrationService base;

  @override
  Future<MessageParseResult> parseAsync(
    IncomingMessage message, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    throw Exception('parse failed');
  }
}

class RetryOnceIntegrationService extends SmsAccountingIntegrationService {
  RetryOnceIntegrationService({required this.base})
    : super(
        parserService: base.parserService,
        duplicateDetectionService: base.duplicateDetectionService,
        mapper: base.mapper,
        recentDraftStore: base.recentDraftStore,
        createTransferUseCase: base.createTransferUseCase,
        createReceiveUseCase: base.createReceiveUseCase,
        createDeferredTransferUseCase: base.createDeferredTransferUseCase,
        createDeferredReceiveUseCase: base.createDeferredReceiveUseCase,
        logSink: base.logSink,
        analyticsTracker: base.analyticsTracker,
      );

  final SmsAccountingIntegrationService base;
  var _attempt = 0;

  @override
  Future<SmsAccountingExecutionResult> executeConfirmedDraft({
    required ParsedTransactionDraft draft,
    required bool userConfirmed,
    required bool reviewed,
    bool allowMediumDuplicateOverride = false,
    SmsExecutionMode mode = SmsExecutionMode.immediate,
  }) async {
    _attempt++;
    if (_attempt == 1) {
      return SmsAccountingExecutionResult(
        status: SmsAccountingExecutionStatus.failedExecution,
        draft: draft,
        duplicateResult: base.checkDuplicate(draft),
        logs: const [],
        errorMessage: 'temporary failure',
      );
    }
    return base.executeConfirmedDraft(
      draft: draft,
      userConfirmed: userConfirmed,
      reviewed: reviewed,
      allowMediumDuplicateOverride: allowMediumDuplicateOverride,
      mode: mode,
    );
  }
}
