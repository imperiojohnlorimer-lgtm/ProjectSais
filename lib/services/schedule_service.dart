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

  bool isLoading(String ownerName) => _loading.contains(ownerName);

  List<ScheduleEvent> eventsFor(String ownerName) {
    final events = _cache[ownerName] ?? const <ScheduleEvent>[];
    final year = activeAcademicYear;
    if (year == null) return events;
    return events
        .where(
          (event) => event.academicYear == null || event.academicYear == year,
        )
        .toList();
  }

  List<ScheduleEvent> eventsForDay(String ownerName, DateTime day) {
    final key = DateTime.utc(day.year, day.month, day.day);
    return eventsFor(ownerName).where((e) => e.dayKey == key).toList();
  }

  Set<DateTime> markedDaysFor(String ownerName) =>
      eventsFor(ownerName).map((e) => e.dayKey).toSet();

  /// Loads (or reuses the cached) events for [ownerName].
  Future<void> ensureLoaded(String ownerName) async {
    if (_cache.containsKey(ownerName) || _loading.contains(ownerName)) return;
    await refresh(ownerName);
    _watch(ownerName);
  }

  /// Keeps [ownerName]'s events live after the first load, so a subject a
  /// student adds shows on their supervisor's calendar without a refresh.
  void _watch(String ownerName) {
    if (_watches.containsKey(ownerName)) return;
    _watches[ownerName] = _repository
        .watchEventsFor(ownerName)
        .listen(
          (events) {
            _cache[ownerName] = events;
            notifyListeners();
          },
          onError: (Object error) {
            // Typically signing out. Drop the stale copy so the next
            // ensureLoaded fetches afresh and starts watching again.
            debugPrint('Schedule stream error for "$ownerName": $error');
            _watches.remove(ownerName)?.cancel();
            _cache.remove(ownerName);
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

  Future<void> refresh(String ownerName) async {
    _loading.add(ownerName);
    notifyListeners();
    try {
      final events = await _repository.getEventsFor(ownerName);
      _cache[ownerName] = events;
    } finally {
      _loading.remove(ownerName);
      notifyListeners();
    }
  }

  Future<void> addEvent(ScheduleEvent event) async {
    final saved = await _repository.addEvent(event);
    final list = List<ScheduleEvent>.from(_cache[event.ownerName] ?? []);
    list.add(saved);
    _cache[event.ownerName] = list;
    notifyListeners();
  }

  Future<void> deleteEvent(String ownerName, String id) async {
    await _repository.deleteEvent(id);
    _cache[ownerName] = eventsFor(ownerName).where((e) => e.id != id).toList();
    notifyListeners();
  }
}
