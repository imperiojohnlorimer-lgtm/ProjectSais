import 'dart:async';

import 'package:flutter/material.dart';
import '../models/class_schedule.dart';
import '../models/schedule_event.dart';
import 'schedule_repository.dart';

/// Bridges the UI and the [ScheduleRepository].
///
/// The UI only ever talks to this class — it doesn't know or care whether
/// events come from memory, a REST API, or a database. Caches loaded
/// results per owner so switching between viewed schedules doesn't refetch
/// unnecessarily; call [refresh] to force a reload (useful once a real
/// backend is in play).
///
/// An owner's approved class schedule ([OwnerSchedule.versions]) is not
/// stored day by day: its classes are worked out here for every day of the
/// calendar's range ([setCalendarRange]), from the version in effect that
/// day, and come back flagged [ScheduleEvent.computed]. Once a class
/// schedule is approved, the stored days of subjects typed in the old way
/// are hidden.
class ScheduleService extends ChangeNotifier {
  ScheduleService(this._repository, {this.scheduleWatcher});

  final ScheduleRepository _repository;

  /// Each owner's `recurringSchedules` document, live. Null in tests that
  /// don't need class schedules.
  final Stream<OwnerSchedule> Function(String ownerId)? scheduleWatcher;

  /// Only events of this academic year (or with none) are shown.
  String? get activeAcademicYear => _year;
  set activeAcademicYear(String? year) {
    if (year == _year) return;
    _year = year;
    _computed.clear();
    _forgetViews();
  }

  String? _year;

  /// Bumped by [reset]: a load started before it is dropped.
  int _generation = 0;
  bool _disposed = false;

  /// What [eventsFor] and [eventsForDay] worked out, per owner, until the
  /// data changes. The calendar asks for every day cell on each build.
  final Map<String, List<ScheduleEvent>> _shown = {};
  final Map<String, Map<DateTime, List<ScheduleEvent>>> _byDay = {};

  void _forgetViews([String? ownerId]) {
    if (ownerId == null) {
      _shown.clear();
      _byDay.clear();
    } else {
      _shown.remove(ownerId);
      _byDay.remove(ownerId);
    }
  }

  final Map<String, List<ScheduleEvent>> _cache = {};
  final Set<String> _loading = {};
  final Map<String, StreamSubscription<List<ScheduleEvent>>> _watches = {};
  final Map<String, OwnerSchedule> _owners = {};
  final Map<String, StreamSubscription<OwnerSchedule>> _ownerWatches = {};
  final Map<String, List<ScheduleEvent>> _computed = {};

  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool Function(DateTime day)? _isHoliday;

  /// The holidays in the range when the class days were worked out, so a
  /// holiday added later is taken into account.
  String _holidays = '';

  bool isLoading(String ownerId) => _loading.contains(ownerId);

  /// The days class schedules are drawn on (the academic year) and the
  /// holidays they skip. Cheap to call on every build: only a change of
  /// range clears what was worked out.
  void setCalendarRange(
    DateTime start,
    DateTime end,
    bool Function(DateTime day) isHoliday,
  ) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    _isHoliday = isHoliday;
    final holidays = StringBuffer();
    for (
      var day = s;
      !day.isAfter(e);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (isHoliday(day)) holidays.write('${day.year}/${day.month}/${day.day} ');
    }
    final key = holidays.toString();
    if (s == _rangeStart && e == _rangeEnd && key == _holidays) return;
    _rangeStart = s;
    _rangeEnd = e;
    _holidays = key;
    _computed.clear();
    _forgetViews();
  }

  /// [ownerId]'s weekly rules and approved class schedules, once loaded.
  OwnerSchedule? scheduleOf(String ownerId) => _owners[ownerId];

  List<ScheduleEvent> eventsFor(String ownerId) =>
      _shown[ownerId] ??= _eventsFor(ownerId);

  List<ScheduleEvent> _eventsFor(String ownerId) {
    var events = _cache[ownerId] ?? const <ScheduleEvent>[];
    final year = activeAcademicYear;
    if (year != null) {
      events = events
          .where(
            (event) => event.academicYear == null || event.academicYear == year,
          )
          .toList();
    }
    final owner = _owners[ownerId];
    if (owner == null || owner.versions.isEmpty) return events;
    // The days filled in by subjects typed the old way no longer count.
    final kept = {
      for (final r in owner.rules)
        if (!r.isSubject) r.id,
    };
    return [
      for (final e in events)
        if (!e.id.startsWith('rule_') || kept.contains(ruleIdOf(e.id))) e,
      ..._classDays(ownerId, owner),
    ];
  }

  /// The rule an "Add Schedule" day came from (`rule_<rule id>_<yyyymmdd>`).
  static String? ruleIdOf(String eventId) {
    if (!eventId.startsWith('rule_')) return null;
    final rest = eventId.substring('rule_'.length);
    final cut = rest.lastIndexOf('_');
    return cut < 0 ? null : rest.substring(0, cut);
  }

  List<ScheduleEvent> _classDays(String ownerId, OwnerSchedule owner) {
    final start = _rangeStart;
    final end = _rangeEnd;
    if (start == null || end == null) return const [];
    return _computed[ownerId] ??= () {
      final out = <ScheduleEvent>[];
      for (
        var day = start;
        !day.isAfter(end);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        if (day.weekday == DateTime.sunday) continue;
        if (_isHoliday?.call(day) ?? false) continue;
        final version = ClassScheduleVersion.inEffect(
          owner.versions,
          day,
          academicYear: activeAcademicYear,
        );
        if (version == null) continue;
        final key = ClassScheduleVersion.dayKey(day).replaceAll('-', '');
        for (final subject in version.subjects) {
          if (subject.weekday != day.weekday) continue;
          out.add(
            ScheduleEvent(
              id: 'class_${version.id}_${subject.id}_$key',
              ownerId: ownerId,
              ownerName: subject.ownerName,
              title: subject.label,
              details: [
                subject.timeRange,
                subject.mode,
                if (subject.room.isNotEmpty) subject.room,
              ].join(' · '),
              date: day,
              color: subject.color,
              icon: Icons.school_outlined,
              academicYear: version.academicYear,
              computed: true,
            ),
          );
        }
      }
      return out;
    }();
  }

  List<ScheduleEvent> eventsForDay(String ownerId, DateTime day) {
    final index = _byDay[ownerId] ??= () {
      final map = <DateTime, List<ScheduleEvent>>{};
      for (final e in eventsFor(ownerId)) {
        (map[e.dayKey] ??= []).add(e);
      }
      return map;
    }();
    return List.of(
      index[DateTime.utc(day.year, day.month, day.day)] ?? const [],
    );
  }

  Set<DateTime> markedDaysFor(String ownerId) =>
      eventsFor(ownerId).map((e) => e.dayKey).toSet();

  /// Loads (or reuses the cached) events for the account [ownerId].
  Future<void> ensureLoaded(String ownerId) async {
    _watchOwner(ownerId);
    if (_cache.containsKey(ownerId) || _loading.contains(ownerId)) return;
    final generation = _generation;
    await refresh(ownerId);
    // Signed out (or closed) meanwhile: don't start watching for the old
    // account.
    if (generation != _generation || _disposed) return;
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
            if (_disposed) return;
            _cache[ownerId] = events;
            _forgetViews(ownerId);
            notifyListeners();
          },
          onError: (Object error) {
            // Typically signing out. Drop the stale copy so the next
            // ensureLoaded fetches afresh and starts watching again.
            debugPrint('Schedule stream error for "$ownerId": $error');
            _watches.remove(ownerId)?.cancel();
            _cache.remove(ownerId);
            _forgetViews(ownerId);
          },
        );
  }

  void _watchOwner(String ownerId) {
    final watcher = scheduleWatcher;
    if (watcher == null || ownerId.isEmpty) return;
    if (_ownerWatches.containsKey(ownerId)) return;
    _ownerWatches[ownerId] = watcher(ownerId).listen(
      (schedule) {
        if (_disposed) return;
        _owners[ownerId] = schedule;
        _computed.remove(ownerId);
        _forgetViews(ownerId);
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('Class schedule stream error for "$ownerId": $error');
        _ownerWatches.remove(ownerId)?.cancel();
        _owners.remove(ownerId);
        _computed.remove(ownerId);
        _forgetViews(ownerId);
      },
    );
  }

  /// Forgets everything loaded: the next account starts afresh.
  void reset() {
    _generation++;
    _forgetViews();
    for (final watch in _watches.values) {
      watch.cancel();
    }
    for (final watch in _ownerWatches.values) {
      watch.cancel();
    }
    _watches.clear();
    _ownerWatches.clear();
    _cache.clear();
    _owners.clear();
    _computed.clear();
    _loading.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final watch in _watches.values) {
      watch.cancel();
    }
    for (final watch in _ownerWatches.values) {
      watch.cancel();
    }
    super.dispose();
  }

  Future<void> refresh(String ownerId) async {
    final generation = _generation;
    _loading.add(ownerId);
    notifyListeners();
    try {
      final events = await _repository.getEventsFor(ownerId);
      // A load for the account signed out meanwhile is dropped.
      if (generation != _generation || _disposed) return;
      _cache[ownerId] = events;
      _forgetViews(ownerId);
    } catch (error) {
      // Usually the Firestore rules refusing a schedule this user may not
      // see. Callers such as the DTR report go on to load the rest of
      // their data, so an error here mustn't stop them; nothing is cached,
      // so the next load tries again.
      debugPrint('Could not load schedule for "$ownerId": $error');
    } finally {
      if (generation == _generation && !_disposed) {
        _loading.remove(ownerId);
        notifyListeners();
      }
    }
  }

  Future<void> addEvent(ScheduleEvent event) async {
    final generation = _generation;
    final saved = await _repository.addEvent(event);
    // Signed out meanwhile: the next account's copy isn't this one's.
    if (_disposed || generation != _generation) return;
    final ownerId = event.ownerId ?? '';
    final list = List<ScheduleEvent>.from(_cache[ownerId] ?? []);
    list.removeWhere((e) => e.id == saved.id);
    list.add(saved);
    _cache[ownerId] = list;
    _forgetViews(ownerId);
    notifyListeners();
  }

  /// Deletes a stored entry. A class worked out from an approved class
  /// schedule isn't stored, so there is nothing to delete.
  Future<void> deleteEvent(String ownerId, String id) async {
    if (id.startsWith('class_')) return;
    final generation = _generation;
    await _repository.deleteEvent(id);
    if (_disposed || generation != _generation) return;
    // Nothing loaded for this owner: leave it to the next load (an empty
    // list here would pass for a loaded one).
    if (!_cache.containsKey(ownerId)) return;
    _cache[ownerId] = (_cache[ownerId] ?? const <ScheduleEvent>[])
        .where((e) => e.id != id)
        .toList();
    _forgetViews(ownerId);
    notifyListeners();
  }
}
