import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/customer_matching_service.dart';
import 'package:king_wallet_accounting/ai_sms/models/ai_parse_result.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';
import 'package:king_wallet_accounting/ai_sms/sms_review_screen.dart';
import 'package:king_wallet_accounting/ai_sms/transaction_anomaly_service.dart';

void main() {
  const walletOptions = [
    SmsReviewWalletOption(id: 1, name: 'Main Wallet', phone: '01000000001'),
    SmsReviewWalletOption(id: 2, name: 'Second Wallet', phone: '01000000002'),
  ];

  ParsedTransactionDraft sampleDraft({
    ParseConfidence confidence = ParseConfidence.high,
  }) {
    return ParsedTransactionDraft(
      operationType: ParsedOperationType.receive,
      amount: 500,
      sender: 'Vodafone Cash',
      effectiveDate: DateTime(2026, 5, 2, 10, 30),
      reference: '123456',
      provider: 'Vodafone Cash',
      confidence: confidence,
      warnings: confidence == ParseConfidence.low
          ? const ['Operation type is unclear.']
          : const [],
      rawMessage: 'Received 500 EGP. Transaction reference 123456.',
    );
  }

  testWidgets('SmsReviewScreen renders parsed fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsReviewScreen(
          draft: sampleDraft(),
          walletOptions: walletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
    expect(find.text('Vodafone Cash'), findsWidgets);
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('500.00'), findsOneWidget);
  });

  testWidgets(
    'SmsReviewScreen editing works and confirm returns modified draft',
    (tester) async {
      ParsedTransactionDraft? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<ParsedTransactionDraft>(
                          MaterialPageRoute(
                            builder: (_) => SmsReviewScreen(
                              draft: sampleDraft(),
                              walletOptions: walletOptions,
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

      await tester.enterText(find.byType(TextField).at(0), '625');
      await tester.enterText(find.byType(TextField).at(1), 'Ahmed Mohamed');
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Known customer');
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.amount, closeTo(625, 0.0001));
      expect(result!.operationType, ParsedOperationType.receive);
      expect(result!.customerName, 'Ahmed Mohamed');
      expect(result!.note, 'Known customer');
    },
  );

  testWidgets('SmsReviewScreen requires customer for deferred mode', (
    tester,
  ) async {
    ParsedTransactionDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<ParsedTransactionDraft>(
                        MaterialPageRoute(
                          builder: (_) => SmsReviewScreen(
                            draft: sampleDraft(),
                            walletOptions: walletOptions,
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
    await tester.tap(find.text('آجل'));
    await tester.pump();
    await _scrollToActions(tester);
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pump();

    expect(result, isNull);
    expect(find.text('يجب اختيار العميل في العمليات الآجلة'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'Deferred Customer');
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.transactionMode, TransactionMode.deferred);
    expect(result!.customerName, 'Deferred Customer');
  });

  testWidgets('SmsReviewScreen requires wallet before confirmation', (
    tester,
  ) async {
    ParsedTransactionDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<ParsedTransactionDraft>(
                        MaterialPageRoute(
                          builder: (_) => SmsReviewScreen(
                            draft: sampleDraft(),
                            walletOptions: const [],
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
    await tester.pump();

    expect(result, isNull);
    expect(find.text('يجب اختيار المحفظة'), findsOneWidget);
  });

  testWidgets('SmsReviewScreen can select second wallet', (tester) async {
    ParsedTransactionDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<ParsedTransactionDraft>(
                        MaterialPageRoute(
                          builder: (_) => SmsReviewScreen(
                            draft: sampleDraft(),
                            walletOptions: walletOptions,
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
    await tester.tap(find.textContaining('Main Wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Second Wallet').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.walletId, 2);
    expect(result!.walletName, 'Second Wallet');
  });

  testWidgets('SmsReviewScreen shows low confidence warning clearly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SmsReviewScreen(
          draft: sampleDraft(confidence: ParseConfidence.low),
          walletOptions: walletOptions,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('needs review'), findsOneWidget);
  });

  testWidgets(
    'SmsReviewScreen shows AI suggestion banner when AI participated',
    (tester) async {
      final draft = sampleDraft(
        confidence: ParseConfidence.medium,
      ).copyWith(aiSuggested: true);
      final aiResult = AiParseResult(
        suggestion: draft,
        confidence: ParseConfidence.medium,
        explanation: 'AI suggested amount and operation.',
        extractedFields: const {'amount': 500.0, 'operationType': 'receive'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SmsReviewScreen(
            draft: draft,
            walletOptions: walletOptions,
            aiParseResult: aiResult,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.text('AI suggested amount and operation.'), findsOneWidget);
    },
  );

  testWidgets(
    'SmsReviewScreen shows customer suggestion but user can ignore it',
    (tester) async {
      ParsedTransactionDraft? result;
      const suggestion = CustomerMatchSuggestion(
        matchedCustomer: 'Ahmed Ali',
        phone: '01012345678',
        confidence: ParseConfidence.high,
        reason: 'same phone',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<ParsedTransactionDraft>(
                          MaterialPageRoute(
                            builder: (_) => SmsReviewScreen(
                              draft: sampleDraft(),
                              walletOptions: walletOptions,
                              customerMatchSuggestion: suggestion,
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

      expect(find.byIcon(Icons.person_search), findsOneWidget);
      expect(find.textContaining('Ahmed Ali'), findsOneWidget);

      await _scrollToActions(tester);
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.customerName, isNull);
    },
  );

  testWidgets(
    'SmsReviewScreen applies customer suggestion only after user taps it',
    (tester) async {
      ParsedTransactionDraft? result;
      const suggestion = CustomerMatchSuggestion(
        matchedCustomer: 'Ahmed Ali',
        phone: '01012345678',
        confidence: ParseConfidence.high,
        reason: 'same phone',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<ParsedTransactionDraft>(
                          MaterialPageRoute(
                            builder: (_) => SmsReviewScreen(
                              draft: sampleDraft(),
                              walletOptions: walletOptions,
                              customerMatchSuggestion: suggestion,
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
      await tester.tap(find.byType(OutlinedButton).first);
      await tester.pump();
      await _scrollToActions(tester);
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.customerName, 'Ahmed Ali');
    },
  );

  testWidgets('SmsReviewScreen shows smart anomaly warning', (tester) async {
    const anomaly = AnomalyResult(
      level: AnomalyLevel.high,
      explanation: 'unusually large amount',
      suggestedAction:
          'Verify message, amount, direction, and customer before confirming.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SmsReviewScreen(
          draft: sampleDraft(),
          walletOptions: walletOptions,
          anomalyResult: anomaly,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(find.textContaining('unusually large amount'), findsOneWidget);
  });
}

Future<void> _scrollToActions(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -800));
  await tester.pumpAndSettle();
}
