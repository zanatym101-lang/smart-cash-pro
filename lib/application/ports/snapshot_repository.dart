import '../../domain/services/snapshot_builder.dart';

abstract class SnapshotRepository {
  Future<void> saveSnapshot(AccountingSnapshot snapshot);

  Future<AccountingSnapshot?> loadSnapshot();
}
