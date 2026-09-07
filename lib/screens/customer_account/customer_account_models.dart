enum CustomerLedgerDirection { forUs, againstUs, neutral }

enum CustomerLedgerRowStatus { open, closed, partial, archived }

enum CustomerLedgerSourceType {
  deferredTransfer,
  deferredReceive,
  claimReceivable,
  claimPayable,
  settlement,
  transaction,
  adjustment,
}

class CustomerAccountSummary {
  const CustomerAccountSummary({
    required this.customerName,
    this.phone,
    required this.totalForUs,
    required this.totalAgainstUs,
    required this.netBalance,
    required this.openDeferredForUs,
    required this.openDeferredAgainstUs,
    required this.openClaimsForUs,
    required this.openClaimsAgainstUs,
    required this.openItemsCount,
    required this.archived,
  });

  final String customerName;
  final String? phone;
  final double totalForUs;
  final double totalAgainstUs;
  final double netBalance;
  final double openDeferredForUs;
  final double openDeferredAgainstUs;
  final double openClaimsForUs;
  final double openClaimsAgainstUs;
  final int openItemsCount;
  final bool archived;
}

class CustomerLedgerRow {
  const CustomerLedgerRow({
    required this.id,
    this.storySourceTxnId,
    required this.date,
    required this.title,
    required this.description,
    required this.direction,
    required this.amount,
    required this.remainingBalanceAfterRow,
    required this.status,
    required this.sourceType,
    this.walletId,
    this.walletName,
    this.walletPhone,
  });

  final String id;
  final int? storySourceTxnId;
  final DateTime date;
  final String title;
  final String description;
  final CustomerLedgerDirection direction;
  final double amount;
  final double remainingBalanceAfterRow;
  final CustomerLedgerRowStatus status;
  final CustomerLedgerSourceType sourceType;
  final int? walletId;
  final String? walletName;
  final String? walletPhone;

  CustomerLedgerRow copyWith({
    String? id,
    int? storySourceTxnId,
    DateTime? date,
    String? title,
    String? description,
    CustomerLedgerDirection? direction,
    double? amount,
    double? remainingBalanceAfterRow,
    CustomerLedgerRowStatus? status,
    CustomerLedgerSourceType? sourceType,
    int? walletId,
    String? walletName,
    String? walletPhone,
  }) {
    return CustomerLedgerRow(
      id: id ?? this.id,
      storySourceTxnId: storySourceTxnId ?? this.storySourceTxnId,
      date: date ?? this.date,
      title: title ?? this.title,
      description: description ?? this.description,
      direction: direction ?? this.direction,
      amount: amount ?? this.amount,
      remainingBalanceAfterRow:
          remainingBalanceAfterRow ?? this.remainingBalanceAfterRow,
      status: status ?? this.status,
      sourceType: sourceType ?? this.sourceType,
      walletId: walletId ?? this.walletId,
      walletName: walletName ?? this.walletName,
      walletPhone: walletPhone ?? this.walletPhone,
    );
  }
}

class OpenCustomerItem {
  const OpenCustomerItem({
    required this.itemId,
    required this.sourceType,
    required this.title,
    required this.originalAmount,
    required this.remainingAmount,
    required this.createdAt,
    this.linkedTxnId,
  });

  final String itemId;
  final CustomerLedgerSourceType sourceType;
  final String title;
  final double originalAmount;
  final double remainingAmount;
  final DateTime createdAt;
  final int? linkedTxnId;
}

class CustomerAccount {
  const CustomerAccount({required this.summary, required this.rows});

  final CustomerAccountSummary summary;
  final List<CustomerLedgerRow> rows;
}
