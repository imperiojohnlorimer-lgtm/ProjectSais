import '../models/schedule_event.dart';

/// Contract for reading/writing schedule events.
///
/// Swap [InMemoryScheduleRepository] for a real implementation (REST,
/// Firestore, SQLite, etc.) once a database is wired up — nothing in the
/// UI layer needs to change as long as it implements this interface.
abstract class ScheduleRepository {
  /// All events belonging to the account [ownerId], most recent first.
  Future<List<ScheduleEvent>> getEventsFor(String ownerId);

  /// [ownerId]'s events, emitted again whenever they change.
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerId);

  Future<ScheduleEvent> addEvent(ScheduleEvent event);

  Future<void> deleteEvent(String id);
}
