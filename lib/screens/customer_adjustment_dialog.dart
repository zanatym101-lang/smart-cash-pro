import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/app_db.dart';
import '../data/sqlite/customer_adjustments_repository.dart';
import '../domain/models/customer_account.dart';
import '../domain/models/money.dart';
import '../domain/services/customer_validation_service.dart';

class CustomerAdjustmentDialog extends StatefulWidget {
  final String customerName;
  final String? customerPhone;
  final CustomerAdjustmentsRepository repository;
  final CustomerValidationService validationService;

  const CustomerAdjustmentDialog({
    super.key,
    required this.customerName,
    this.customerPhone,
    required this.repository,
    required this.validationService,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String customerName,
    String? customerPhone,
  }) async {
    final repository = CustomerAdjustmentsRepository(AppDb.instance.sqlite);
    final validationService = const CustomerValidationService();
    return showDialog<bool>(
      context: context,
      builder: (context) => CustomerAdjustmentDialog(
        customerName: customerName,
        customerPhone: customerPhone,
        repository: repository,
        validationService: validationService,
      ),
    );
  }

  @override
  State<CustomerAdjustmentDialog> createState() =>
      _CustomerAdjustmentDialogState();
}

class _CustomerAdjustmentDialogState extends State<CustomerAdjustmentDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  
  CustomerAdjustmentType _type = CustomerAdjustmentType.add;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() => _error = 'يرجى إدخال المبلغ');
      return;
    }

    final amountDouble = double.tryParse(amountText);
    if (amountDouble == null || amountDouble <= 0) {
      setState(() => _error = 'المبلغ غير صحيح');
      return;
    }

    final amountMoney = Money.fromDouble(amountDouble);
    final note = _noteController.text.trim();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final adjNote = widget.customerPhone != null && widget.customerPhone!.isNotEmpty
          ? (note.isEmpty ? widget.customerPhone : '$note - ${widget.customerPhone}')
          : (note.isEmpty ? null : note);
          
      final validationResult = widget.validationService.validateCustomer(
        name: widget.customerName,
        note: adjNote,
        existingCustomers: await AppDb.instance.listCustomerCandidates(),
      );

      if (validationResult.isError) {
        setState(() {
          _error = validationResult.message;
          _isLoading = false;
        });
        return;
      }

      final adjustment = CustomerAccountAdjustment(
        id: const Uuid().v4(),
        customerId: widget.customerName,
        type: _type,
        amount: amountMoney,
        date: DateTime.now(),
        note: adjNote,
      );

      await widget.repository.saveAdjustment(adjustment);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _error = 'حدث خطأ: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تسوية حساب لـ ${widget.customerName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.red.withValues(alpha: 0.1),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            SegmentedButton<CustomerAdjustmentType>(
              segments: const [
                ButtonSegment(
                  value: CustomerAdjustmentType.add,
                  label: Text('إضافة مستحق لنا'),
                  icon: Icon(Icons.add_circle_outline),
                ),
                ButtonSegment(
                  value: CustomerAdjustmentType.subtract,
                  label: Text('خصم (مستحق علينا)'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (Set<CustomerAdjustmentType> newSelection) {
                setState(() {
                  _type = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ التسوية'),
        ),
      ],
    );
  }
}
