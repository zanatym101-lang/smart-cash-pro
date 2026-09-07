import 'package:flutter/material.dart';

import 'models/incoming_message.dart';
import 'models/message_parse_result.dart';
import 'models/parsed_transaction_draft.dart';
import 'sms_parser_service.dart';

class SmsParserDebugScreen extends StatefulWidget {
  const SmsParserDebugScreen({super.key});

  @override
  State<SmsParserDebugScreen> createState() => _SmsParserDebugScreenState();
}

class _SmsParserDebugScreenState extends State<SmsParserDebugScreen> {
  final _senderController = TextEditingController(text: 'Vodafone Cash');
  final _messageController = TextEditingController(
    text:
        'تم استلام مبلغ 500 جنيه من محفظة رقم 01012345678. رقم العملية 123456.',
  );
  final _parser = SmsParserService();
  MessageParseResult? _result;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _senderController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _parse() {
    final result = _parser.parse(
      IncomingMessage(
        sender: _senderController.text,
        body: _messageController.text,
      ),
    );
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final draft = result?.draft;

    return Scaffold(
      appBar: AppBar(title: const Text('SMS Parser Debug')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _senderController,
              decoration: const InputDecoration(labelText: 'المرسل'),
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'نص الرسالة'),
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _parse,
              child: const Text('تحليل الرسالة'),
            ),
            const SizedBox(height: 16),
            if (draft != null) ...[
              _InfoRow(label: 'النوع', value: _operationLabel(draft.operationType)),
              _InfoRow(
                label: 'المبلغ',
                value: draft.amount?.toStringAsFixed(2) ?? 'غير معروف',
              ),
              _InfoRow(label: 'المزوّد', value: draft.provider ?? 'غير معروف'),
              _InfoRow(label: 'المرجع', value: draft.reference ?? 'غير موجود'),
              _InfoRow(label: 'الثقة', value: draft.confidence.name),
              _InfoRow(
                label: 'مراجعة يدوية',
                value: result!.requiresManualReview ? 'نعم' : 'لا',
              ),
              if (draft.warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'تحذيرات: ${draft.warnings.join(' | ')}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              if (result.reasons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('أسباب التحليل: ${result.reasons.join(' | ')}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _operationLabel(ParsedOperationType type) {
    switch (type) {
      case ParsedOperationType.transfer:
        return 'تحويل';
      case ParsedOperationType.receive:
        return 'استلام';
      case ParsedOperationType.unknown:
        return 'غير واضح';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
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
