import '../models/schedule_event.dart';

/// Contract for reading/writing schedule events.
///
/// Swap [InMemoryScheduleRepository] for a real implementation (REST,
/// Firestore, SQLite, etc.) once a database is wired up — nothing in the
/// UI layer needs to change as long as it implements this interface.
abstract class ScheduleRepository {
  /// All events belonging to [ownerName], most recent first.
  Future<List<ScheduleEvent>> getEventsFor(String ownerName);

  /// [ownerName]'s events, emitted again whenever they change.
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerName);

  Future<ScheduleEvent> addEvent(ScheduleEvent event);

  Future<void> deleteEvent(String id);
}
