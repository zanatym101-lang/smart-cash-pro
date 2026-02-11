part of 'app_db.dart';

extension AppDbWallets on AppDb {
  String _normalizeDigit(String ch) {
    switch (ch) {
      case 'ط·آ¸ط¢آ ':
      case 'ط·ط›ط¢آ°':
        return '0';
      case 'ط·آ¸ط·إ’':
      case 'ط·ط›ط¢آ±':
        return '1';
      case 'ط·آ¸ط¢آ¢':
      case 'ط·ط›ط¢آ²':
        return '2';
      case 'ط·آ¸ط¢آ£':
      case 'ط·ط›ط¢آ³':
        return '3';
      case 'ط·آ¸ط¢آ¤':
      case 'ط·ط›ط¢آ´':
        return '4';
      case 'ط·آ¸ط¢آ¥':
      case 'ط·ط›ط¢آµ':
        return '5';
      case 'ط·آ¸ط¢آ¦':
      case 'ط·ط›ط¢آ¶':
        return '6';
      case 'ط·آ¸ط¢آ§':
      case 'ط·ط›ط¢آ·':
        return '7';
      case 'ط·آ¸ط¢آ¨':
      case 'ط·ط›ط¢آ¸':
        return '8';
      case 'ط·آ¸ط¢آ©':
      case 'ط·ط›ط¢آ¹':
        return '9';
      default:
        return ch;
    }
  }

  String _normalizePhone(String input) {
    final buf = StringBuffer();
    for (final r in input.runes) {
      final raw = String.fromCharCode(r);
      final ch = _normalizeDigit(raw);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  Future<void> resetDatabase() async {
    if (!AppSession.isAdmin) {
      throw Exception(
        'ط·آ¸أ¢â‚¬طŒط·آ·ط¢آ°ط·آ·ط¢آ§ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ¥ط·آ·ط¢آ¬ط·آ·ط¢آ±ط·آ·ط¢آ§ط·آ·ط·إ’ ط·آ¸أ¢â‚¬آ¦ط·آ·ط¹آ¾ط·آ·ط¢آ§ط·آ·ط¢آ­ ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬â€چط·آ·ط¢آ£ط·آ·ط¢آ¯ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¾ط·آ¸أ¢â‚¬ع‘ط·آ·ط¢آ·',
      );
    }
    await _closeSqlite();
    final file = await _sqliteFile();
    if (await file.exists()) await file.delete();
    final legacy = await _dataFile();
    if (await legacy.exists()) await legacy.delete();
    await _reopenSqlite();
    _loaded = false;
    await _ensureLoaded();
  }

  Future<void> resetDatabaseEmpty() async {
    if (!AppSession.isAdmin) {
      throw Exception(
        'ط·آ¸أ¢â‚¬طŒط·آ·ط¢آ°ط·آ·ط¢آ§ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ¥ط·آ·ط¢آ¬ط·آ·ط¢آ±ط·آ·ط¢آ§ط·آ·ط·إ’ ط·آ¸أ¢â‚¬آ¦ط·آ·ط¹آ¾ط·آ·ط¢آ§ط·آ·ط¢آ­ ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬â€چط·آ·ط¢آ£ط·آ·ط¢آ¯ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¾ط·آ¸أ¢â‚¬ع‘ط·آ·ط¢آ·',
      );
    }
    await _resetEmpty();
  }

  Future<List<Wallet>> listWallets() async {
    await _ensureLoaded();
    return List.unmodifiable(_wallets);
  }

  Future<int> addWallet({
    required String name,
    required String phone,
    double openingBalance = 0,
    double dailyLimit = 60000,
    double monthlyLimit = 200000,
    double lowBalanceThreshold = 0,
    bool allowNegative = false,
  }) async {
    await _ensureLoaded();
    await _ensureWalletAllowed();
    final n = name.trim();
    if (n.isEmpty) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ·ط¢آ³ط·آ¸أ¢â‚¬آ¦ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ·ط·آ¸أ¢â‚¬â€چط·آ¸ط«â€ ط·آ·ط¢آ¨',
      );
    }
    final p = _normalizePhone(phone);
    if (p.isEmpty) {
      throw Exception(
        'ط·آ·ط¢آ±ط·آ¸أ¢â‚¬ع‘ط·آ¸أ¢â‚¬آ¦ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ·ط·آ¸أ¢â‚¬â€چط·آ¸ط«â€ ط·آ·ط¢آ¨',
      );
    }
    if (dailyLimit <= 0) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦ط·آ¸ط¸آ¹ ط·آ¸ط¸آ¹ط·آ·ط¢آ¬ط·آ·ط¢آ¨ ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط¦â€™ط·آ·ط¢آ¨ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آµط·آ¸ط¸آ¾ط·آ·ط¢آ±',
      );
    }
    if (monthlyLimit <= 0) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ´ط·آ¸أ¢â‚¬طŒط·آ·ط¢آ±ط·آ¸ط¸آ¹ ط·آ¸ط¸آ¹ط·آ·ط¢آ¬ط·آ·ط¢آ¨ ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط¦â€™ط·آ·ط¢آ¨ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آµط·آ¸ط¸آ¾ط·آ·ط¢آ±',
      );
    }
    if (monthlyLimit < dailyLimit) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ´ط·آ¸أ¢â‚¬طŒط·آ·ط¢آ±ط·آ¸ط¸آ¹ ط·آ¸ط¸آ¹ط·آ·ط¢آ¬ط·آ·ط¢آ¨ ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط¦â€™ط·آ·ط¢آ¨ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط«â€  ط·آ¸ط¸آ¹ط·آ·ط¢آ³ط·آ·ط¢آ§ط·آ¸ط«â€ ط·آ¸ط¸آ¹ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦ط·آ¸ط¸آ¹',
      );
    }
    if (openingBalance < 0) {
      throw Exception(
        'ط·آ·ط¢آ±ط·آ·ط¢آµط·آ¸ط¸آ¹ط·آ·ط¢آ¯ ط·آ·ط¢آ£ط·آ¸ط«â€ ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¯ط·آ·ط¢آ© ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸ط¦â€™ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ³ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ¨',
      );
    }
    if (lowBalanceThreshold < 0) {
      throw Exception(
        'ط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¹آ¾ط·آ¸أ¢â‚¬آ ط·آ·ط¢آ¨ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬طŒ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ±ط·آ·ط¢آµط·آ¸ط¸آ¹ط·آ·ط¢آ¯ ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸ط¦â€™ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ³ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ¨',
      );
    }
    final w = Wallet(
      id: _nextWalletId++,
      name: n,
      allowNegative: allowNegative,
      phone: p,
      dailyLimit: dailyLimit,
      monthlyLimit: monthlyLimit,
      lowBalanceThreshold: lowBalanceThreshold,
    );
    _wallets.add(w);

    if (openingBalance > 0) {
      final now = DateTime.now();
      final entryDate = _nextOpenDate(now);
      final txn = Txn(
        id: _nextTxnId++,
        kind: 'external_funding',
        status: 'posted',
        entryDate: entryDate,
        walletToId: w.id,
        amount: openingBalance,
        clientFee: 0,
        networkFee: 0,
        mode: 'opening_balance',
        note:
            'ط·آ·ط¢آ±ط·آ·ط¢آµط·آ¸ط¸آ¹ط·آ·ط¢آ¯ ط·آ·ط¢آ£ط·آ¸ط«â€ ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¯ط·آ·ط¢آ©',
        createdBy: _actorName(),
        createdRole: _actorRole(),
        createdAt: now,
      );
      final spec = WalletFundingTxSpec(
        walletId: w.id.toString(),
        amountQirsh: Money.fromEgpDouble(openingBalance),
        note:
            'ط·آ·ط¢آ±ط·آ·ط¢آµط·آ¸ط¸آ¹ط·آ·ط¢آ¯ ط·آ·ط¢آ£ط·آ¸ط«â€ ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¯ط·آ·ط¢آ©',
      );
      _engine.createPending(
        txId: _txId(txn.id),
        spec: spec,
        payload: txn.toJson(),
      );
      _engine.approve(txId: _txId(txn.id), spec: spec);
      _txns.add(txn);
      await enqueueOutbox(
        entity: 'txn',
        entityId: txn.id.toString(),
        action: 'create',
        payload: txn.toJson(),
      );
      await appendAudit(
        type: 'wallet_opening_balance',
        txnId: txn.id,
        walletId: w.id,
        amount: openingBalance,
        note:
            'ط·آ·ط¢آ±ط·آ·ط¢آµط·آ¸ط¸آ¹ط·آ·ط¢آ¯ ط·آ·ط¢آ£ط·آ¸ط«â€ ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¯ط·آ·ط¢آ©',
      );
    }

    await _save();
    await enqueueOutbox(
      entity: 'wallet',
      entityId: w.id.toString(),
      action: 'create',
      payload: w.toJson(),
    );
    await appendAudit(type: 'wallet_add', walletId: w.id, note: w.name);
    return w.id;
  }

  Future<void> updateWallet({
    required int walletId,
    required String name,
    required String phone,
    required double dailyLimit,
    required double monthlyLimit,
    required double lowBalanceThreshold,
  }) async {
    await _ensureLoaded();
    final n = name.trim();
    if (n.isEmpty) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ·ط¢آ³ط·آ¸أ¢â‚¬آ¦ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ·ط·آ¸أ¢â‚¬â€چط·آ¸ط«â€ ط·آ·ط¢آ¨',
      );
    }
    final p = _normalizePhone(phone);
    if (p.isEmpty) {
      throw Exception(
        'ط·آ·ط¢آ±ط·آ¸أ¢â‚¬ع‘ط·آ¸أ¢â‚¬آ¦ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ·ط·آ¸أ¢â‚¬â€چط·آ¸ط«â€ ط·آ·ط¢آ¨',
      );
    }
    if (dailyLimit <= 0) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦ط·آ¸ط¸آ¹ ط·آ¸ط¸آ¹ط·آ·ط¢آ¬ط·آ·ط¢آ¨ ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط¦â€™ط·آ·ط¢آ¨ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آµط·آ¸ط¸آ¾ط·آ·ط¢آ±',
      );
    }
    if (monthlyLimit <= 0) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ´ط·آ¸أ¢â‚¬طŒط·آ·ط¢آ±ط·آ¸ط¸آ¹ ط·آ¸ط¸آ¹ط·آ·ط¢آ¬ط·آ·ط¢آ¨ ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط¦â€™ط·آ·ط¢آ¨ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آµط·آ¸ط¸آ¾ط·آ·ط¢آ±',
      );
    }
    if (monthlyLimit < dailyLimit) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ´ط·آ¸أ¢â‚¬طŒط·آ·ط¢آ±ط·آ¸ط¸آ¹ ط·آ¸ط¸آ¹ط·آ·ط¢آ¬ط·آ·ط¢آ¨ ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط¦â€™ط·آ·ط¢آ¨ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸ط«â€  ط·آ¸ط¸آ¹ط·آ·ط¢آ³ط·آ·ط¢آ§ط·آ¸ط«â€ ط·آ¸ط¸آ¹ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦ط·آ¸ط¸آ¹',
      );
    }
    if (lowBalanceThreshold < 0) {
      throw Exception(
        'ط·آ·ط¢آ­ط·آ·ط¢آ¯ ط·آ·ط¹آ¾ط·آ¸أ¢â‚¬آ ط·آ·ط¢آ¨ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬طŒ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ±ط·آ·ط¢آµط·آ¸ط¸آ¹ط·آ·ط¢آ¯ ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸ط¦â€™ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ£ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ  ط·آ·ط¢آ³ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ¨',
      );
    }
    final idx = _wallets.indexWhere((w) => w.id == walletId);
    if (idx == -1) {
      throw Exception(
        'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ© ط·آ·ط·â€؛ط·آ¸ط¸آ¹ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸ط«â€ ط·آ·ط¢آ¬ط·آ¸ط«â€ ط·آ·ط¢آ¯ط·آ·ط¢آ©',
      );
    }
    _wallets[idx] = _wallets[idx].copyWith(
      name: n,
      phone: p,
      dailyLimit: dailyLimit,
      monthlyLimit: monthlyLimit,
      lowBalanceThreshold: lowBalanceThreshold,
    );
    await _save();
    await enqueueOutbox(
      entity: 'wallet',
      entityId: walletId.toString(),
      action: 'update',
      payload: _wallets[idx].toJson(),
    );
    await appendAudit(type: 'wallet_update', walletId: walletId, note: n);
  }

  Future<double> getWalletBalance(int walletId) async {
    await _ensureLoaded();
    final q = _state.getWalletQirsh(walletId.toString());
    return Money.toEgpDouble(q);
  }

  Future<double> getWalletAvailableBalance(int walletId) async {
    await _ensureLoaded();
    final projected = _projectedBalances();
    final q = projected.walletsQirsh[walletId.toString()] ?? 0;
    return Money.toEgpDouble(q);
  }

  Future<TreasurySnapshot> getTreasurySnapshot() async {
    await _ensureLoaded();

    // Posted/actual balances from engine state (qirsh -> EGP)
    final drawerActualBalance = Money.toEgpDouble(_state.drawerBalanceQirsh);
    int walletsActualQ = 0;
    for (final w in _wallets) {
      walletsActualQ += _state.getWalletQirsh(w.id.toString());
    }
    final walletsActualTotal = Money.toEgpDouble(walletsActualQ);

    // Available/projected balances (posted + pending)
    final projected = _projectedBalances();
    final drawerBalance = Money.toEgpDouble(projected.drawerQirsh);
    int walletsAvailableQ = 0;
    for (final w in _wallets) {
      walletsAvailableQ += projected.walletsQirsh[w.id.toString()] ?? 0;
    }
    final walletsTotal = Money.toEgpDouble(walletsAvailableQ);

    // Pending txns count
    final pendingCount = _txns.where((t) => t.status == 'pending').length;
    await _maybeNotifyPending();

    // Profits derived from posted txns (CF). Rolled-back originals are excluded by status.
    final now = DateTime.now();
    final nowDayKey = _businessDateKeyFromDateTime(now);
    final nowShifted = _businessShift(now);
    double dailyProfit = 0;
    double monthlyProfit = 0;

    for (final t in _txns) {
      if (t.status != 'posted') continue;
      if (t.kind == 'rollback') continue;

      final fee = t.clientFee;
      if (fee <= 0) continue;

      if (_businessDateKeyFromDateTime(t.entryDate) == nowDayKey) {
        dailyProfit += fee;
      }
      final tShifted = _businessShift(t.entryDate);
      if (tShifted.year == nowShifted.year &&
          tShifted.month == nowShifted.month) {
        monthlyProfit += fee;
      }
    }

    return TreasurySnapshot(
      drawerBalance: drawerBalance,
      walletsTotal: walletsTotal,
      drawerActualBalance: drawerActualBalance,
      walletsActualTotal: walletsActualTotal,
      pendingCount: pendingCount,
      dailyProfit: dailyProfit,
      monthlyProfit: monthlyProfit,
    );
  }

  Future<void> _maybeNotifyPending() async {
    final now = DateTime.now();
    final todayKey = _businessDateKeyFromDateTime(now);
    if (_lastPendingAlertDate == todayKey) return;

    final cutoff = now.subtract(const Duration(days: 1));
    final oldPending = _txns
        .where((t) => t.status == 'pending' && t.entryDate.isBefore(cutoff))
        .length;
    if (oldPending <= 0) return;

    await NotificationService.show(
      title:
          'ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ·ط¢آ§ط·آ·ط¹آ¾ ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬ع©ط·آ¸أ¢â‚¬ع‘ط·آ·ط¢آ©',
      body:
          'ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ¯ط·آ¸ط¸آ¹ط·آ¸ط¦â€™ $oldPending ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬ع©ط·آ¸أ¢â‚¬ع‘ط·آ·ط¢آ© ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ£ط·آ¸ط¦â€™ط·آ·ط¢آ«ط·آ·ط¢آ± ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬آ  ط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦.',
    );

    _lastPendingAlertDate = todayKey;
    await _save();
  }
}
