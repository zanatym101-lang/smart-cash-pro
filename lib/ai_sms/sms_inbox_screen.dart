import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/use_cases/create_deferred_receive_use_case.dart';
import '../application/use_cases/create_deferred_transfer_use_case.dart';
import '../application/use_cases/create_receive_use_case.dart';
import '../application/use_cases/create_transfer_use_case.dart';
import '../config/app_env.dart';
import '../data/app_db.dart';
import '../domain/services/accounting_engine.dart';
import '../infrastructure/adapters/in_memory_event_repository.dart';
import '../infrastructure/adapters/in_memory_snapshot_repository.dart';
import 'ai_parsing_service.dart';
import 'customer_matching_service.dart';
import 'duplicate_detection_service.dart';
import 'models/incoming_message.dart';
import 'models/parsed_transaction_draft.dart';
import 'parsed_draft_to_use_case_mapper.dart';
import 'recent_draft_store.dart';
import 'sms_accounting_integration_service.dart';
import 'sms_inbox_service.dart';
import 'sms_parser_service.dart';
import 'sms_review_screen.dart';
import 'transaction_anomaly_service.dart';

class SmsInboxScreen extends StatefulWidget {
  const SmsInboxScreen({
    super.key,
    required this.integrationService,
    required this.smsInboxService,
    this.fetchTimeout = const Duration(seconds: 5),
    this.parseTimeout = const Duration(seconds: 2),
    this.walletOptions,
  });

  factory SmsInboxScreen.withDefaults({
    Key? key,
    SmsInboxService? smsInboxService,
    SmsAccountingIntegrationService? integrationService,
  }) {
    if (integrationService != null) {
      return SmsInboxScreen(
        key: key,
        integrationService: integrationService,
        smsInboxService: smsInboxService ?? SmsInboxService.platform(),
        fetchTimeout: const Duration(seconds: 5),
        parseTimeout: const Duration(seconds: 2),
      );
    }
    final recentDraftStore = RecentDraftStore();
    final eventRepository = InMemoryEventRepository([
      const OpeningBalancesRecorded(drawer: 1000, wallets: 2000),
    ]);
    final snapshotRepository = InMemorySnapshotRepository();
    final defaultIntegrationService = SmsAccountingIntegrationService(
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
      logSink: kDebugMode ? (entry) => debugPrint(entry.toString()) : null,
      aiParsingService: enableAi ? const AiParsingService() : null,
    );

    return SmsInboxScreen(
      key: key,
      integrationService: defaultIntegrationService,
      smsInboxService: smsInboxService ?? SmsInboxService.platform(),
      fetchTimeout: const Duration(seconds: 5),
      parseTimeout: const Duration(seconds: 2),
    );
  }

  final SmsAccountingIntegrationService integrationService;
  final SmsInboxService smsInboxService;
  final Duration fetchTimeout;
  final Duration parseTimeout;
  final List<SmsReviewWalletOption>? walletOptions;

  @override
  State<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends State<SmsInboxScreen> {
  bool _busy = false;
  bool _loading = true;
  SmsInboxPermissionStatus _permissionStatus = SmsInboxPermissionStatus.denied;
  List<IncomingMessage> _messages = const [];
  String? _error;
  String? _busyMessage;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
      _messages = const [];
    });
    try {
      final permission = await widget.smsInboxService.getPermissionStatus();
      if (!mounted) return;
      if (permission != SmsInboxPermissionStatus.granted) {
        setState(() {
          _permissionStatus = permission;
          _messages = const [];
          _loading = false;
        });
        return;
      }

      final messages = await widget.smsInboxService
          .fetchRecentMessages(limit: 100)
          .timeout(widget.fetchTimeout);
      if (!mounted) return;
      setState(() {
        _permissionStatus = permission;
        _messages = messages;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'انتهت مهلة تحميل الرسائل';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _loading = true);
    final permission = await widget.smsInboxService.requestPermission();
    if (!mounted) return;
    if (permission == SmsInboxPermissionStatus.granted) {
      await _loadMessages();
      return;
    }
    setState(() {
      _permissionStatus = permission;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استيراد من الرسائل'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _busy || _loading ? null : _loadMessages,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(children: [_buildBody(), if (_busy) _buildBusyOverlay()]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        message: 'حدث خطأ أثناء تحميل الرسائل',
        details: _error,
        actionLabel: 'إعادة المحاولة',
        onAction: _loadMessages,
      );
    }
    if (_permissionStatus == SmsInboxPermissionStatus.unsupported) {
      return const _MessageState(
        icon: Icons.sms_failed_outlined,
        message: 'متاح على Android فقط',
      );
    }
    if (_permissionStatus != SmsInboxPermissionStatus.granted) {
      return _MessageState(
        icon: Icons.sms_outlined,
        message: 'يجب السماح بقراءة الرسائل',
        actionLabel: 'السماح',
        onAction: _requestPermission,
      );
    }
    if (_messages.isEmpty) {
      return _MessageState(
        icon: Icons.inbox_outlined,
        message: 'لا توجد رسائل متاحة',
        actionLabel: 'تحديث',
        onAction: _loadMessages,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final message = _messages[index];
        return Card(
          child: ListTile(
            title: Text(message.sender),
            subtitle: Text(
              message.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(_formatDate(message.receivedAt)),
            onTap: _busy ? null : () => _openMessage(message),
          ),
        );
      },
    );
  }

  Future<void> _openMessage(IncomingMessage message) async {
    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ تحليل الرسالة...';
    });
    try {
      final parseResult = await widget.integrationService.parseAsync(
        message,
        timeout: widget.parseTimeout,
      );
      if (!mounted) return;
      final customerMatchSuggestion = enableAiAdvanced
          ? await _customerMatchSuggestion(
              parseResult.draft,
            ).timeout(const Duration(milliseconds: 150), onTimeout: () => null)
          : null;
      final anomalyResult = enableAiAdvanced
          ? TransactionAnomalyService().analyze(
              draft: parseResult.draft,
              recentDrafts: widget.integrationService.recentDraftStore.getAll(),
            )
          : null;
      final walletOptions = widget.walletOptions ?? await _loadWalletOptions();
      if (!mounted) return;
      final reviewedDraft = await Navigator.of(context)
          .push<ParsedTransactionDraft>(
            MaterialPageRoute(
              builder: (_) => SmsReviewScreen(
                draft: parseResult.draft,
                walletOptions: walletOptions,
                aiParseResult: parseResult.aiParseResult,
                customerMatchSuggestion: customerMatchSuggestion,
                anomalyResult: anomalyResult,
              ),
            ),
          );
      if (!mounted || reviewedDraft == null) return;

      final result = await _executeWithRetry(reviewedDraft);

      if (!mounted) return;
      if (result == null) return;

      if (result.status ==
          SmsAccountingExecutionStatus.blockedHighConfidenceDuplicate) {
        _showSnack('عملية مكررة');
        return;
      }

      if (result.status ==
          SmsAccountingExecutionStatus
              .blockedMediumConfidenceDuplicateNeedsOverride) {
        final override = await _showOverrideDialog();
        if (override != true || !mounted) return;
        final overridden = await widget.integrationService
            .executeConfirmedDraft(
              draft: reviewedDraft,
              userConfirmed: true,
              reviewed: true,
              allowMediumDuplicateOverride: true,
            );
        if (!mounted) return;
        if (overridden.executed) {
          await _showSuccessFeedback(overridden.draft);
          if (!mounted) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        } else {
          _showSnack('قد تكون مكررة');
        }
        return;
      }

      if (result.executed) {
        await _showSuccessFeedback(result.draft);
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      _showSnack(_messageForStatus(result.status));
    } on TimeoutException {
      _showSnack('تعذر تحليل الرسالة');
    } catch (_) {
      _showSnack('تعذر تحليل الرسالة');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  Future<CustomerMatchSuggestion?> _customerMatchSuggestion(
    ParsedTransactionDraft draft,
  ) async {
    try {
      final candidates = await _loadCustomerCandidates();
      return const CustomerMatchingService().suggest(
        draft: draft,
        existingCustomers: candidates,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<CustomerMatchCandidate>> _loadCustomerCandidates() async {
    final txns = await AppDb.instance.listTxns();
    final claims = await AppDb.instance.listClaims();
    final byKey = <String, _CustomerCandidateAccumulator>{};

    void add({
      required String name,
      String? phone,
      double? amount,
      DateTime? date,
    }) {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return;
      final normalizedPhone = _normalizePhone(phone ?? '');
      final key = normalizedPhone.isNotEmpty
          ? 'p:$normalizedPhone'
          : 'n:${trimmedName.toLowerCase()}';
      final item = byKey.putIfAbsent(
        key,
        () => _CustomerCandidateAccumulator(
          name: trimmedName,
          phone: normalizedPhone.isEmpty ? null : normalizedPhone,
        ),
      );
      if (amount != null && amount > 0) {
        item.amounts.add(amount);
      }
      if (date != null &&
          (item.lastActivity == null || date.isAfter(item.lastActivity!))) {
        item.lastActivity = date;
      }
    }

    for (final txn in txns) {
      add(
        name: txn.party ?? '',
        phone: _extractPhone(txn.note) ?? _extractPhone(txn.reference),
        amount: txn.amount,
        date: txn.entryDate,
      );
    }
    for (final claim in claims) {
      add(
        name: claim.party,
        phone: _extractPhone(claim.note),
        amount: claim.amount,
        date: claim.entryDate,
      );
    }

    return byKey.values
        .map(
          (item) => CustomerMatchCandidate(
            customerName: item.name,
            phone: item.phone,
            recentAmounts: item.amounts,
            lastActivity: item.lastActivity,
          ),
        )
        .toList(growable: false);
  }

  Future<List<SmsReviewWalletOption>> _loadWalletOptions() async {
    final wallets = await AppDb.instance.listWallets();
    return wallets
        .map(
          (wallet) => SmsReviewWalletOption(
            id: wallet.id,
            name: wallet.name,
            phone: wallet.phone,
          ),
        )
        .toList(growable: false);
  }

  String? _extractPhone(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final normalized = _normalizePhone(text);
    final match = RegExp(r'\d{10,15}').firstMatch(normalized);
    return match?.group(0);
  }

  String _normalizePhone(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  Future<SmsAccountingExecutionResult?> _executeWithRetry(
    ParsedTransactionDraft reviewedDraft,
  ) async {
    while (true) {
      if (!mounted) return null;
      setState(() => _busyMessage = 'جارٍ تنفيذ العملية...');
      final result = await widget.integrationService.executeConfirmedDraft(
        draft: reviewedDraft,
        userConfirmed: true,
        reviewed: true,
      );
      if (result.status != SmsAccountingExecutionStatus.failedExecution) {
        return result;
      }
      final retry = await _showExecutionFailureDialog();
      if (retry != true) {
        return result;
      }
    }
  }

  Future<bool?> _showOverrideDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text('قد تكون مكررة'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showExecutionFailureDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعذر تنفيذ العملية'),
        content: const Text(
          'حدث خطأ أثناء تنفيذ العملية. هل تريد إعادة المحاولة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSuccessFeedback(ParsedTransactionDraft draft) async {
    final message = draft.transactionMode == TransactionMode.deferred
        ? 'تم تسجيل العملية الآجلة'
        : 'تم تسجيل العملية';
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text(message),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageForStatus(SmsAccountingExecutionStatus status) {
    switch (status) {
      case SmsAccountingExecutionStatus.executed:
        return 'تم تسجيل العملية';
      case SmsAccountingExecutionStatus.failedExecution:
        return 'تعذر تنفيذ العملية';
      case SmsAccountingExecutionStatus.blockedHighConfidenceDuplicate:
        return 'عملية مكررة';
      case SmsAccountingExecutionStatus
          .blockedMediumConfidenceDuplicateNeedsOverride:
        return 'قد تكون مكررة';
      case SmsAccountingExecutionStatus.blockedUserConfirmationMissing:
        return 'يجب تأكيد العملية';
      case SmsAccountingExecutionStatus.blockedLowConfidenceNeedsReview:
        return 'تحتاج إلى مراجعة';
      case SmsAccountingExecutionStatus.blockedExplicitOperationRequired:
        return 'نوع العملية غير واضح';
      case SmsAccountingExecutionStatus.blockedInvalidAmount:
        return 'المبلغ غير صالح';
      case SmsAccountingExecutionStatus.blockedWalletRequired:
        return 'يجب اختيار المحفظة';
      case SmsAccountingExecutionStatus.blockedPendingCustomerRequired:
        return 'يجب اختيار العميل في العمليات الآجلة';
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '--:--';
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildBusyOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.18),
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_busyMessage ?? 'جارٍ المعالجة...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerCandidateAccumulator {
  _CustomerCandidateAccumulator({required this.name, this.phone});

  final String name;
  final String? phone;
  final List<double> amounts = [];
  DateTime? lastActivity;
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.details,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? details;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
