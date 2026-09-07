import '../../application/ports/snapshot_repository.dart';
import '../../domain/services/snapshot_builder.dart';

class InMemorySnapshotRepository implements SnapshotRepository {
  InMemorySnapshotRepository([AccountingSnapshot? initialSnapshot])
    : _snapshot = initialSnapshot;

  AccountingSnapshot? _snapshot;

  @override
  Future<AccountingSnapshot?> loadSnapshot() async => _snapshot;

  @override
  Future<void> saveSnapshot(AccountingSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
