import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_final_isolation_guard_',
  );

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('SMS integration core executes through use case plans', () {
    final service = _read('lib/ai_sms/sms_accounting_integration_service.dart');
    final mapper = _read('lib/ai_sms/parsed_draft_to_use_case_mapper.dart');

    expect(service, isNot(contains("import '../data/app_db.dart'")));
    expect(service, isNot(contains('AppDb.instance')));
    expect(service, contains('ParsedDraftToUseCaseMapper mapper'));
    expect(service, contains('createTransferUseCase.execute'));
    expect(service, contains('createReceiveUseCase.execute'));
    expect(service, contains('createDeferredTransferUseCase.execute'));
    expect(service, contains('createDeferredReceiveUseCase.execute'));

    expect(mapper, contains('CreateTransferUseCase'));
    expect(mapper, contains('CreateReceiveUseCase'));
    expect(mapper, contains('CreateDeferredTransferUseCase'));
    expect(mapper, contains('CreateDeferredReceiveUseCase'));
    expect(mapper, isNot(contains('AppDb.instance')));
  });

  test('AI assistance stays advisory and has no accounting write path', () {
    final aiFiles = [
      'lib/ai_sms/ai_parsing_service.dart',
      'lib/ai_sms/customer_matching_service.dart',
      'lib/ai_sms/transaction_anomaly_service.dart',
    ];

    for (final path in aiFiles) {
      final source = _read(path);
      expect(source, isNot(contains('AppDb.instance')), reason: path);
      expect(source, isNot(contains('/use_cases/')), reason: path);
      expect(source, isNot(contains('.execute(')), reason: path);
      expect(source, isNot(contains('addTransfer(')), reason: path);
      expect(source, isNot(contains('addReceive(')), reason: path);
      expect(source, isNot(contains('settleClaim(')), reason: path);
    }
  });

  test('customer ledger screen is guarded by CustomerAccountBuilder', () {
    final customers = _read('lib/screens/customers_screen.dart');
    expect(
      customers,
      contains("import 'customer_account/customer_account_builder.dart';"),
    );
    expect(customers, contains('CustomerAccountBuilder.fromAppDbData'));
    expect(customers, contains('account?.summary.totalForUs'));
    expect(customers, contains('account?.summary.totalAgainstUs'));
  });

  test('full pending settlement does not create hidden claim', () async {
    await resetAndActivate();
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Guard Wallet',
      phone: '01099990000',
      openingBalance: 5000,
    );
    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 1000,
      clientFee: 0,
      networkFee: 0,
      transferType: 'type2',
      isPending: true,
      party: 'Guard Customer',
      note: '01011112222',
    );

    await db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 400);
    await db.settlePendingTxnFully(pendingTxnId: txnId);

    final txns = await db.listTxns();
    expect(txns.firstWhere((txn) => txn.id == txnId).status, 'posted');
    final claims = await db.listClaims(status: 'open');
    expect(claims.where((claim) => claim.sourceTxnId == txnId), isEmpty);
  });

  test('total settlement implementation creates per-item settlement rows', () {
    final customers = _read('lib/screens/customers_screen.dart');
    expect(customers, contains('تسوية من الإجمالي'));
    expect(customers, contains('for (final line in ordered)'));
    expect(customers, contains('_settleLineFully(line, note: note)'));
    expect(
      customers,
      contains('_settleLinePartially(line, amount: allocation, note: note)'),
    );
    expect(customers, contains('remainingInput -= allocation'));
  });
}
