import 'package:drift/drift.dart';

import '../../domain/models/customer_account.dart';
import '../../domain/models/money.dart';
import 'app_database.dart';

class CustomerAdjustmentsRepository {
  final AppDatabase _db;

  CustomerAdjustmentsRepository(this._db);

  Future<void> saveAdjustment(CustomerAccountAdjustment adjustment) async {
    await _db.transaction(() async {
      await _db.into(_db.customerAdjustments).insert(
        CustomerAdjustmentsCompanion.insert(
          id: adjustment.id,
          customerId: adjustment.customerId,
          type: adjustment.type == CustomerAdjustmentType.add ? 'add' : 'subtract',
          amountPiastres: adjustment.amount.piastres,
          date: adjustment.date,
          note: Value(adjustment.note),
        ),
      );

      if (adjustment.allocations.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.adjustmentAllocations,
            adjustment.allocations.map((a) => AdjustmentAllocationsCompanion.insert(
              id: a.id,
              adjustmentId: a.adjustmentId,
              linkedItemId: a.linkedItemId,
              allocatedAmountPiastres: a.allocatedAmount.piastres,
            )),
          );
        });
      }
    });
  }

  Future<List<CustomerAccountAdjustment>> getAdjustmentsForCustomer(String customerId) async {
    final adjRows = await (_db.select(_db.customerAdjustments)
      ..where((t) => t.customerId.equals(customerId))
      ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
      .get();

    final results = <CustomerAccountAdjustment>[];
    for (final row in adjRows) {
      final allocRows = await (_db.select(_db.adjustmentAllocations)
        ..where((t) => t.adjustmentId.equals(row.id)))
        .get();
        
      final allocations = allocRows.map((a) => AdjustmentAllocation(
        id: a.id,
        adjustmentId: a.adjustmentId,
        linkedItemId: a.linkedItemId,
        allocatedAmount: Money.fromPiastres(a.allocatedAmountPiastres),
      )).toList();

      results.add(CustomerAccountAdjustment(
        id: row.id,
        customerId: row.customerId,
        type: row.type == 'add' ? CustomerAdjustmentType.add : CustomerAdjustmentType.subtract,
        amount: Money.fromPiastres(row.amountPiastres),
        date: row.date,
        note: row.note,
        allocations: allocations,
      ));
    }
    return results;
  }

  Future<List<CustomerAccountAdjustment>> getAllAdjustments() async {
    final adjRows = await (_db.select(_db.customerAdjustments)
      ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
      .get();

    final allAllocRows = await _db.select(_db.adjustmentAllocations).get();
    
    // Group allocations by adjustmentId for faster processing
    final allocByAdjId = <String, List<AdjustmentAllocation>>{};
    for (final a in allAllocRows) {
      final alloc = AdjustmentAllocation(
        id: a.id,
        adjustmentId: a.adjustmentId,
        linkedItemId: a.linkedItemId,
        allocatedAmount: Money.fromPiastres(a.allocatedAmountPiastres),
      );
      allocByAdjId.putIfAbsent(a.adjustmentId, () => []).add(alloc);
    }

    final results = <CustomerAccountAdjustment>[];
    for (final row in adjRows) {
      results.add(CustomerAccountAdjustment(
        id: row.id,
        customerId: row.customerId,
        type: row.type == 'add' ? CustomerAdjustmentType.add : CustomerAdjustmentType.subtract,
        amount: Money.fromPiastres(row.amountPiastres),
        date: row.date,
        note: row.note,
        allocations: allocByAdjId[row.id] ?? const [],
      ));
    }
    return results;
  }
}
