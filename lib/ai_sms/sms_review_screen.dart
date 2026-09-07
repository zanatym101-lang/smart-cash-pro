import 'package:flutter/material.dart';

import 'customer_matching_service.dart';
import 'models/ai_parse_result.dart';
import 'models/parsed_transaction_draft.dart';
import 'transaction_anomaly_service.dart';

class SmsReviewWalletOption {
  const SmsReviewWalletOption({
    required this.id,
    required this.name,
    this.phone,
    this.label,
  });

  final int id;
  final String name;
  final String? phone;
  final String? label;

  String get displayLabel {
    final custom = label?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final trimmedPhone = phone?.trim();
    if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
      return '$name - $trimmedPhone';
    }
    return name;
  }
}

class SmsReviewScreen extends StatefulWidget {
  final ParsedTransactionDraft draft;
  final AiParseResult? aiParseResult;
  final CustomerMatchSuggestion? customerMatchSuggestion;
  final AnomalyResult? anomalyResult;
  final List<SmsReviewWalletOption> walletOptions;

  const SmsReviewScreen({
    super.key,
    required this.draft,
    this.aiParseResult,
    this.customerMatchSuggestion,
    this.anomalyResult,
    this.walletOptions = const [],
  });

  @override
  State<SmsReviewScreen> createState() => _SmsReviewScreenState();
}

class _SmsReviewScreenState extends State<SmsReviewScreen> {
  late ParsedOperationType _operationType;
  late TransactionMode _transactionMode;
  late TextEditingController _amountController;
  late TextEditingController _customerController;
  late TextEditingController _noteController;
  int? _selectedWalletId;
  String? _customerValidationMessage;
  String? _walletValidationMessage;

  @override
  void initState() {
    super.initState();
    _operationType = widget.draft.operationType;
    _transactionMode = widget.draft.transactionMode;
    _amountController = TextEditingController(
      text: widget.draft.amount?.toStringAsFixed(2) ?? '',
    );
    _customerController = TextEditingController(
      text: widget.draft.customerName ?? '',
    );
    _noteController = TextEditingController(text: widget.draft.note ?? '');
    _selectedWalletId = _initialWalletId();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _customerController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confidenceStyle = _confidenceStyle(widget.draft.confidence);

    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة الرسالة')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _confirm,
                  child: const Text('تأكيد'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: confidenceStyle.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: confidenceStyle.color),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: confidenceStyle.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    confidenceStyle.label,
                    style: TextStyle(
                      color: confidenceStyle.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (widget.aiParseResult != null || widget.draft.aiSuggested) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2563EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFF2563EB)),
                      SizedBox(width: 8),
                      Text(
                        'اقتراح AI',
                        style: TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (widget.aiParseResult?.explanation.trim().isNotEmpty ??
                      false) ...[
                    const SizedBox(height: 8),
                    Text(widget.aiParseResult!.explanation),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.customerMatchSuggestion != null) ...[
            _AdvisoryPanel(
              icon: Icons.person_search,
              title: 'اقتراح عميل',
              color: const Color(0xFF0F766E),
              background: const Color(0xFFE6FFFB),
              body:
                  '${widget.customerMatchSuggestion!.matchedCustomer} - ${widget.customerMatchSuggestion!.reason}',
              actionLabel: 'استخدام الاقتراح',
              onAction: () {
                setState(() {
                  _customerController.text =
                      widget.customerMatchSuggestion!.matchedCustomer;
                });
              },
            ),
            const SizedBox(height: 16),
          ],
          if (widget.anomalyResult != null &&
              widget.anomalyResult!.level != AnomalyLevel.low) ...[
            _AdvisoryPanel(
              icon: Icons.warning_amber,
              title: 'تحذير ذكي',
              color: _anomalyColor(widget.anomalyResult!.level),
              background: _anomalyBackground(widget.anomalyResult!.level),
              body:
                  '${widget.anomalyResult!.explanation}\n${widget.anomalyResult!.suggestedAction}',
            ),
            const SizedBox(height: 16),
          ],
          _ReadOnlyRow(
            label: 'المرسل',
            value: widget.draft.provider ?? widget.draft.sender,
          ),
          _ReadOnlyRow(
            label: 'التاريخ',
            value: _formatDate(widget.draft.effectiveDate),
          ),
          _ReadOnlyRow(
            label: 'المرجع',
            value: widget.draft.reference ?? 'غير موجود',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ParsedOperationType>(
            initialValue: _operationType,
            decoration: const InputDecoration(labelText: 'نوع العملية'),
            items: const [
              DropdownMenuItem(
                value: ParsedOperationType.transfer,
                child: Text('تحويل'),
              ),
              DropdownMenuItem(
                value: ParsedOperationType.receive,
                child: Text('استلام'),
              ),
              DropdownMenuItem(
                value: ParsedOperationType.unknown,
                child: Text('غير واضح'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _operationType = value);
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<TransactionMode>(
            segments: const [
              ButtonSegment(
                value: TransactionMode.instant,
                label: Text('فوري'),
                icon: Icon(Icons.flash_on),
              ),
              ButtonSegment(
                value: TransactionMode.deferred,
                label: Text('آجل'),
                icon: Icon(Icons.schedule),
              ),
            ],
            selected: {_transactionMode},
            onSelectionChanged: (values) {
              setState(() {
                _transactionMode = values.single;
                _customerValidationMessage = null;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedWalletId,
            decoration: InputDecoration(
              labelText: 'المحفظة',
              errorText: _walletValidationMessage,
            ),
            hint: const Text('اختر المحفظة'),
            items: widget.walletOptions
                .map(
                  (wallet) => DropdownMenuItem<int>(
                    value: wallet.id,
                    child: Text(wallet.displayLabel),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.walletOptions.isEmpty
                ? null
                : (value) {
                    setState(() {
                      _selectedWalletId = value;
                      _walletValidationMessage = null;
                    });
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ'),
          ),
          const SizedBox(height: 12),
          if (_transactionMode == TransactionMode.deferred) ...[
            TextField(
              controller: _customerController,
              decoration: InputDecoration(
                labelText: 'العميل',
                hintText: 'اختيار/إدخال اسم العميل',
                errorText: _customerValidationMessage,
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            TextField(
              controller: _customerController,
              decoration: const InputDecoration(
                labelText: 'العميل',
                hintText: 'اختياري',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظة'),
          ),
          if (widget.draft.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'تحذيرات: ${widget.draft.warnings.join(' | ')}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _confirm() {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    final customerName = _customerController.text.trim().isEmpty
        ? null
        : _customerController.text.trim();
    final selectedWallet = _selectedWallet();
    if (selectedWallet == null) {
      setState(() {
        _walletValidationMessage = 'يجب اختيار المحفظة';
      });
      return;
    }
    if (_transactionMode == TransactionMode.deferred && customerName == null) {
      setState(() {
        _customerValidationMessage = 'يجب اختيار العميل في العمليات الآجلة';
      });
      return;
    }
    final result = widget.draft.copyWith(
      operationType: _operationType,
      transactionMode: _transactionMode,
      amount: amount,
      customerName: customerName,
      walletId: selectedWallet.id,
      walletName: selectedWallet.name,
      walletLabel: selectedWallet.displayLabel,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    Navigator.of(context).pop(result);
  }

  int? _initialWalletId() {
    final requested = widget.draft.walletId;
    if (requested != null &&
        widget.walletOptions.any((wallet) => wallet.id == requested)) {
      return requested;
    }
    final walletName = widget.draft.walletName?.trim();
    if (walletName != null && walletName.isNotEmpty) {
      for (final wallet in widget.walletOptions) {
        if (wallet.name.trim() == walletName) return wallet.id;
      }
    }
    if (widget.walletOptions.isNotEmpty) return widget.walletOptions.first.id;
    return null;
  }

  SmsReviewWalletOption? _selectedWallet() {
    final selectedId = _selectedWalletId;
    if (selectedId == null) return null;
    for (final wallet in widget.walletOptions) {
      if (wallet.id == selectedId) return wallet;
    }
    return null;
  }

  String _formatDate(DateTime value) {
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$min';
  }

  _ConfidenceStyle _confidenceStyle(ParseConfidence confidence) {
    switch (confidence) {
      case ParseConfidence.high:
        return const _ConfidenceStyle(
          label: 'ثقة عالية',
          color: Color(0xFF15803D),
          background: Color(0xFFE8F5E9),
        );
      case ParseConfidence.medium:
        return const _ConfidenceStyle(
          label: 'ثقة متوسطة',
          color: Color(0xFFC2410C),
          background: Color(0xFFFFF3E0),
        );
      case ParseConfidence.low:
        return const _ConfidenceStyle(
          label: 'ثقة منخفضة - needs review',
          color: Color(0xFFB91C1C),
          background: Color(0xFFFEE2E2),
        );
    }
  }

  Color _anomalyColor(AnomalyLevel level) {
    switch (level) {
      case AnomalyLevel.high:
        return const Color(0xFFB91C1C);
      case AnomalyLevel.medium:
        return const Color(0xFFC2410C);
      case AnomalyLevel.low:
        return const Color(0xFF15803D);
    }
  }

  Color _anomalyBackground(AnomalyLevel level) {
    switch (level) {
      case AnomalyLevel.high:
        return const Color(0xFFFEE2E2);
      case AnomalyLevel.medium:
        return const Color(0xFFFFF7ED);
      case AnomalyLevel.low:
        return const Color(0xFFE8F5E9);
    }
  }
}

class _AdvisoryPanel extends StatelessWidget {
  const _AdvisoryPanel({
    required this.icon,
    required this.title,
    required this.color,
    required this.background,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Color background;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ConfidenceStyle {
  final String label;
  final Color color;
  final Color background;

  const _ConfidenceStyle({
    required this.label,
    required this.color,
    required this.background,
  });
}
