import re

def refactor_app_db():
    file_path = 'lib/data/app_db_wallets.dart'
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove the old getTreasurySnapshot method entirely
    content = re.sub(r"(?s)  Future<TreasurySnapshot> getTreasurySnapshot\(\) async \{.*?    \);\n  \}\n", '', content)
    
    # Remove _projectedBalances
    content = re.sub(r"(?s)  \(\{int drawerQirsh, int fawryQirsh, Map<String, int> walletsQirsh\}\) _projectedBalances\(\) \{.*?\n  \}\n", '', content)

    # Remove _pendingLiquidityFlowQirsh
    content = re.sub(r"(?s)  \(\{int inflowQirsh, int outflowQirsh\}\) _pendingLiquidityFlowQirsh\(\) \{.*?\n  \}\n", '', content)

    new_get_treasury = """  Future<TreasurySnapshot> getTreasurySnapshot() async {
    await _ensureLoaded();

    // Promote Builders as Source of Truth
    final walletAccounts = WalletLedgerBuilder.build(txns: _txns, wallets: _wallets);
    final walletsTotal = walletAccounts.fold<double>(0, (sum, w) => sum + w.currentBalance.asEgpDouble);
    final walletsActualTotal = walletsTotal; 

    final drawerEntries = _state.ledger.where((e) => e.accountKey == 'drawer').toList();
    final txnsMap = {for (var t in _txns) t.id.toString(): t};
    final treasuryAccount = TreasuryLedgerBuilder.build(
      drawerEntries: drawerEntries,
      txnsMap: txnsMap,
    );
    final drawerBalance = treasuryAccount.closingBalance.asEgpDouble;
    final drawerActualBalance = drawerBalance;

    final customerAccounts = CustomerAccountBuilder.fromAppDbData(
      txns: _txns,
      claims: _claims,
    );
    
    double claimsReceivableOpen = 0;
    double claimsPayableOpen = 0;
    double pendingReceivableOpen = 0;
    double pendingPayableOpen = 0;

    for (final c in customerAccounts) {
      claimsReceivableOpen += c.summary.openClaimsForUs;
      claimsPayableOpen += c.summary.openClaimsAgainstUs;
      pendingReceivableOpen += c.summary.openDeferredForUs;
      pendingPayableOpen += c.summary.openDeferredAgainstUs;
    }

    final fawryActualBalance = Money.toEgpDouble(_state.fawryBalanceQirsh);
    final fawryBalance = fawryActualBalance;

    final pendingCount = _txns.where((t) => _hasStatus(t, 'pending')).length;
    final pendingInflow = 0.0;
    final pendingOutflow = 0.0;
    await _maybeNotifyPending();

    final now = DateTime.now();
    final nowDayKey = _businessDateKeyFromDateTime(now);
    final nowShifted = _businessShift(now);
    double dailyProfit = 0;
    double monthlyProfit = 0;
    double profitApprovedTotal = 0;

    for (final t in _txns) {
      if (t.status != 'posted') continue;
      if (t.kind == 'rollback') continue;

      final fee = t.clientFee;
      if (fee <= 0) continue;
      profitApprovedTotal += fee;

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
      fawryBalance: fawryBalance,
      drawerActualBalance: drawerActualBalance,
      walletsActualTotal: walletsActualTotal,
      fawryActualBalance: fawryActualBalance,
      pendingCount: pendingCount,
      pendingInflow: pendingInflow,
      pendingOutflow: pendingOutflow,
      claimsReceivableOpen: claimsReceivableOpen,
      claimsPayableOpen: claimsPayableOpen,
      pendingReceivableOpen: pendingReceivableOpen,
      pendingPayableOpen: pendingPayableOpen,
      profitApprovedTotal: profitApprovedTotal,
      dailyProfit: dailyProfit,
      monthlyProfit: monthlyProfit,
    );
  }
"""
    content = content.replace("  Future<void> _maybeNotifyPending() async {", new_get_treasury + "\n  Future<void> _maybeNotifyPending() async {")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

refactor_app_db()
