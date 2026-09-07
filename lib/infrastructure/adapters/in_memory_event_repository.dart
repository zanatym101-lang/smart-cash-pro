import '../../application/ports/event_repository.dart';
import '../../domain/services/accounting_engine.dart';

class InMemoryEventRepository implements EventRepository {
  InMemoryEventRepository([List<AccountingEvent>? seedEvents])
    : _events = List<AccountingEvent>.from(seedEvents ?? const []);

  final List<AccountingEvent> _events;

  @override
  Future<List<AccountingEvent>> loadEvents() async =>
      List.unmodifiable(_events);

  @override
  Future<void> saveEvents(List<AccountingEvent> events) async {
    _events.addAll(events);
  }
}
