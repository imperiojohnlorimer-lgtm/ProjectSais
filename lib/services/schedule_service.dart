import 'dart:async';

import 'package:flutter/material.dart';
import '../models/schedule_event.dart';
import 'schedule_repository.dart';

/// Bridges the UI and the [ScheduleRepository].
///
/// The UI only ever talks to this class — it doesn't know or care whether
/// events come from memory, a REST API, or a database. Caches loaded
/// results per owner so switching between viewed schedules doesn't refetch
/// unnecessarily; call [refresh] to force a reload (useful once a real
/// backend is in play).
class ScheduleService extends ChangeNotifier {
  ScheduleService(this._repository);

  final ScheduleRepository _repository;
  String? activeAcademicYear;

  final Map<String, List<ScheduleEvent>> _cache = {};
  final Set<String> _loading = {};
  final Map<String, StreamSubscription<List<ScheduleEvent>>> _watches = {};

  bool isLoading(String ownerId) => _loading.contains(ownerId);

  List<ScheduleEvent> eventsFor(String ownerId) {
    final events = _cache[ownerId] ?? const <ScheduleEvent>[];
    final year = activeAcademicYear;
    if (year == null) return events;
    return events
        .where(
          (event) => event.academicYear == null || event.academicYear == year,
        )
        .toList();
  }

  List<ScheduleEvent> eventsForDay(String ownerId, DateTime day) {
    final key = DateTime.utc(day.year, day.month, day.day);
    return eventsFor(ownerId).where((e) => e.dayKey == key).toList();
  }

  Set<DateTime> markedDaysFor(String ownerId) =>
      eventsFor(ownerId).map((e) => e.dayKey).toSet();

  /// Loads (or reuses the cached) events for the account [ownerId].
  Future<void> ensureLoaded(String ownerId) async {
    if (_cache.containsKey(ownerId) || _loading.contains(ownerId)) return;
    await refresh(ownerId);
    _watch(ownerId);
  }

  /// Keeps [ownerId]'s events live after the first load, so a subject a
  /// student adds shows on their supervisor's calendar without a refresh.
  void _watch(String ownerId) {
    if (_watches.containsKey(ownerId)) return;
    _watches[ownerId] = _repository
        .watchEventsFor(ownerId)
        .listen(
          (events) {
            _cache[ownerId] = events;
            notifyListeners();
          },
          onError: (Object error) {
            // Typically signing out. Drop the stale copy so the next
            // ensureLoaded fetches afresh and starts watching again.
            debugPrint('Schedule stream error for "$ownerId": $error');
            _watches.remove(ownerId)?.cancel();
            _cache.remove(ownerId);
          },
        );
  }

  @override
  void dispose() {
    for (final watch in _watches.values) {
      watch.cancel();
    }
    super.dispose();
  }

  Future<void> refresh(String ownerId) async {
    _loading.add(ownerId);
    notifyListeners();
    try {
      final events = await _repository.getEventsFor(ownerId);
      _cache[ownerId] = events;
    } catch (error) {
      // Usually the Firestore rules refusing a schedule this user may not
      // see. Callers such as the DTR report go on to load the rest of
      // their data, so an error here mustn't stop them; nothing is cached,
      // so the next load tries again.
      debugPrint('Could not load schedule for "$ownerId": $error');
    } finally {
      _loading.remove(ownerId);
      notifyListeners();
    }
  }

  Future<void> addEvent(ScheduleEvent event) async {
    final saved = await _repository.addEvent(event);
    final ownerId = event.ownerId ?? '';
    final list = List<ScheduleEvent>.from(_cache[ownerId] ?? []);
    list.add(saved);
    _cache[ownerId] = list;
    notifyListeners();
  }

  Future<void> deleteEvent(String ownerId, String id) async {
    await _repository.deleteEvent(id);
    _cache[ownerId] = eventsFor(ownerId).where((e) => e.id != id).toList();
    notifyListeners();
  }
}
