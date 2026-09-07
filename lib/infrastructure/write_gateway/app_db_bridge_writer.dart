import '../../application/write_gateway/write_intents.dart';
import '../../data/app_db.dart';

class AppDbBridgeWriteResult {
  const AppDbBridgeWriteResult({this.legacyId, this.snapshot});

  final int? legacyId;
  final TreasurySnapshot? snapshot;
}

class AppDbBridgeWriter {
  const AppDbBridgeWriter({AppDb? db}) : _db = db;

  final AppDb? _db;

  AppDb get db => _db ?? AppDb.instance;

  Future<TreasurySnapshot> currentTreasurySnapshot() =>
      db.getTreasurySnapshot();

  Future<AppDbBridgeWriteResult> mirror(WriteIntent intent) async {
    final legacyId = switch (intent) {
      CreateTransferIntent() => await db.addTransfer(
        walletId: intent.walletId,
        amount: intent.amount,
        clientFee: intent.clientFee,
        networkFee: intent.networkFee,
        transferType: intent.transferType,
        isPending: false,
        note: intent.note,
        party: intent.party,
      ),
      CreateDeferredTransferIntent() => await db.addTransfer(
        walletId: intent.walletId,
        amount: intent.amount,
        clientFee: intent.clientFee,
        networkFee: intent.networkFee,
        transferType: intent.transferType,
        isPending: true,
        note: intent.note,
        party: intent.party,
      ),
      CreateReceiveIntent() => await db.addReceive(
        walletId: intent.walletId,
        amount: intent.amount,
        commission: intent.commission,
        receiveType: intent.receiveType,
        isPending: false,
        note: intent.note,
        party: intent.party,
      ),
      CreateDeferredReceiveIntent() => await db.addReceive(
        walletId: intent.walletId,
        amount: intent.amount,
        commission: intent.commission,
        receiveType: intent.receiveType,
        isPending: true,
        note: intent.note,
        party: intent.party,
      ),
      CreateClaimIntent() => await db.addClaim(
        type: _claimDirectionToLegacy(intent.type),
        party: intent.party,
        amount: intent.amount,
        note: intent.note,
        phone: intent.phone,
        sourceTxnId: intent.sourceTxnId,
        applyDrawerEffect: intent.applyDrawerEffect,
      ),
      CreateSettlementIntent() => await _mirrorSettlement(intent),
      SettleClaimIntent() => await db.settleClaim(
        claimId: _parseLegacyId(intent.claimId, 'claimId'),
        amount: intent.amount,
        note: intent.note,
      ),
      ConfirmPendingIntent() => await _mirrorConfirmPending(intent),
      CancelPendingIntent() => await _mirrorCancelPending(intent),
      RollbackTransactionIntent() => await _mirrorRollback(intent),
      DrawerDepositIntent() => await db.drawerDeposit(
        amount: intent.amount,
        note: intent.note,
      ),
      DrawerWithdrawIntent() => await db.drawerDeposit(
        amount: -intent.amount.abs(),
        note: intent.note,
      ),
      WalletFundingIntent() => await db.addExternalFunding(
        walletId: intent.walletId,
        amount: intent.amount,
        note: intent.note,
      ),
      WalletAdjustmentIntent() => await _mirrorWalletAdjustment(intent),
      ExpenseIntent() => await _mirrorExpense(intent),
      FawryIntent() => await db.addFawry(
        serviceName: intent.serviceName,
        reference: intent.reference,
        amount: intent.amount,
        fee: intent.fee,
        collectionMethod: intent.collectionMethod,
        party: intent.party,
        note: intent.note,
        isPending: intent.isPending,
      ),
      DailyCloseIntent() => await _mirrorDailyClose(intent),
    };

    return AppDbBridgeWriteResult(
      legacyId: legacyId,
      snapshot: await db.getTreasurySnapshot(),
    );
  }

  Future<int?> _mirrorSettlement(CreateSettlementIntent intent) async {
    final pendingTxnId = _parseLegacyId(intent.itemId, 'itemId');
    if (intent.fullSettlement) {
      await db.settlePendingTxnFully(
        pendingTxnId: pendingTxnId,
        note: intent.note,
      );
      return null;
    }
    return db.addPendingSettlementForTxn(
      pendingTxnId: pendingTxnId,
      amount: intent.amount,
      note: intent.note,
    );
  }

  int _parseLegacyId(String value, String field) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw ArgumentError.value(value, field, 'Expected a legacy numeric id.');
    }
    return parsed;
  }

  String _claimDirectionToLegacy(ClaimDirection type) => switch (type) {
    ClaimDirection.receivable => 'receivable',
    ClaimDirection.payable => 'payable',
  };

  Future<int?> _mirrorConfirmPending(ConfirmPendingIntent intent) async {
    await db.confirmPending(
      _parseLegacyId(intent.pendingTxnId, 'pendingTxnId'),
    );
    return null;
  }

  Future<int?> _mirrorCancelPending(CancelPendingIntent intent) async {
    await db.cancelPending(_parseLegacyId(intent.pendingTxnId, 'pendingTxnId'));
    return null;
  }

  Future<int?> _mirrorRollback(RollbackTransactionIntent intent) async {
    final id = _parseLegacyId(intent.transactionId, 'transactionId');
    switch (intent.rollbackType) {
      case RollbackTransactionType.posted:
        await db.rollbackPosted(id);
      case RollbackTransactionType.pendingSettlement:
        await db.rollbackPendingSettlement(id);
      case RollbackTransactionType.claimSettlement:
        await db.rollbackClaimSettlement(id);
    }
    return null;
  }

  Future<int?> _mirrorWalletAdjustment(WalletAdjustmentIntent intent) async {
    switch (intent.adjustmentType) {
      case WalletAdjustmentType.createWallet:
        return db.addWallet(
          name: _requiredString(intent.name, 'name'),
          phone: _requiredString(intent.phone, 'phone'),
          openingBalance: intent.openingBalance,
          dailyLimit: intent.dailyLimit,
          monthlyLimit: intent.monthlyLimit,
          lowBalanceThreshold: intent.lowBalanceThreshold,
          allowNegative: intent.allowNegative,
        );
      case WalletAdjustmentType.updateWallet:
        await db.updateWallet(
          walletId: _requiredInt(intent.walletId, 'walletId'),
          name: _requiredString(intent.name, 'name'),
          phone: _requiredString(intent.phone, 'phone'),
          dailyLimit: intent.dailyLimit,
          monthlyLimit: intent.monthlyLimit,
          lowBalanceThreshold: intent.lowBalanceThreshold,
        );
      case WalletAdjustmentType.resetDailyUsage:
        await db.resetWalletDailyUsage(
          _requiredInt(intent.walletId, 'walletId'),
        );
      case WalletAdjustmentType.resetMonthlyUsage:
        await db.resetWalletMonthlyUsage(
          _requiredInt(intent.walletId, 'walletId'),
        );
      case WalletAdjustmentType.resetAllDailyUsage:
        await db.resetAllWalletDailyUsage();
      case WalletAdjustmentType.resetAllMonthlyUsage:
        await db.resetAllWalletMonthlyUsage();
    }
    return null;
  }

  Future<int?> _mirrorExpense(ExpenseIntent intent) async {
    switch (intent.action) {
      case ExpenseIntentAction.create:
        return db.addExpense(
          amount: _requiredDouble(intent.amount, 'amount'),
          category: _requiredString(intent.category, 'category'),
          note: intent.note,
          party: intent.party,
          isPending: intent.isPending,
        );
      case ExpenseIntentAction.update:
        await db.updateExpense(
          txnId: _requiredInt(intent.txnId, 'txnId'),
          amount: _requiredDouble(intent.amount, 'amount'),
          category: _requiredString(intent.category, 'category'),
          note: intent.note,
          party: intent.party,
        );
      case ExpenseIntentAction.delete:
        await db.deleteExpense(_requiredInt(intent.txnId, 'txnId'));
    }
    return null;
  }

  Future<int?> _mirrorDailyClose(DailyCloseIntent intent) async {
    switch (intent.action) {
      case DailyCloseAction.close:
        final close = await db.closeDaily(intent.date);
        return close.id;
      case DailyCloseAction.reopen:
        await db.reopenDaily(intent.date);
        return null;
    }
  }

  int _requiredInt(int? value, String field) {
    if (value == null) {
      throw ArgumentError.notNull(field);
    }
    return value;
  }

  double _requiredDouble(double? value, String field) {
    if (value == null) {
      throw ArgumentError.notNull(field);
    }
    return value;
  }

  String _requiredString(String? value, String field) {
    if (value == null) {
      throw ArgumentError.notNull(field);
    }
    return value;
  }
}
