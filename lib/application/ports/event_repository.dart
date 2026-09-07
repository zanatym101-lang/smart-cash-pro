import '../../domain/services/accounting_engine.dart';

abstract class EventRepository {
  Future<void> saveEvents(List<AccountingEvent> events);

  Future<List<AccountingEvent>> loadEvents();
}
