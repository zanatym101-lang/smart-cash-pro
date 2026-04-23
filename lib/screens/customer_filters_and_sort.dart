part of 'customers_screen.dart';

extension _CustomersScreenFiltersAndSort on _CustomersScreenState {
  int _compareCustomerLinesDesc(_CustomerLine a, _CustomerLine b) {
    final dateCompare = b.date.compareTo(a.date);
    if (dateCompare != 0) return dateCompare;

    if (a.lineType != b.lineType) {
      return a.lineType == _CustomerLineType.txn ? -1 : 1;
    }

    if (a.lineType == _CustomerLineType.txn) {
      return (b.txnId ?? 0).compareTo(a.txnId ?? 0);
    }

    return (b.claimId ?? 0).compareTo(a.claimId ?? 0);
  }

  List<_CustomerBucket> get _filtered {
    final q = _query.trim().toLowerCase();
    Iterable<_CustomerBucket> base = _customers;

    switch (_listFilter) {
      case _CustomerListFilter.archived:
        base = base.where((c) => c.isArchived);
        break;
      case _CustomerListFilter.receivable:
        base = base.where((c) => !c.isArchived && c.receivableTotal > 0);
        break;
      case _CustomerListFilter.payable:
        base = base.where((c) => !c.isArchived && c.payableTotal > 0);
        break;
      case _CustomerListFilter.pending:
        base = base.where(
          (c) =>
              !c.isArchived &&
              (c.receivablePending > 0 || c.payablePending > 0),
        );
        break;
      case _CustomerListFilter.all:
        base = base.where((c) => !c.isArchived);
        break;
    }

    if (q.isNotEmpty) {
      base = base.where((c) {
        final name = c.name.toLowerCase();
        final phone = (c.phone ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q);
      });
    }

    final list = base.toList();
    list.sort((a, b) {
      final aPinned = _pinnedCustomers.contains(_customerKeyFor(a));
      final bPinned = _pinnedCustomers.contains(_customerKeyFor(b));
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      final aDate = a.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return list;
  }
}
