import 'package:flutter/material.dart';
import '../models/schedule_event.dart';
import '../theme/app_theme.dart';
import 'schedule_repository.dart';

/// Temporary in-memory storage, standing in for a real database.
///
/// Data lives only for the app session. Replace this class with e.g.
/// `ApiScheduleRepository` or `FirestoreScheduleRepository` — both would
/// implement [ScheduleRepository] with the same method signatures, so
/// only the `Provider` wiring in `main.dart` needs to change.
class InMemoryScheduleRepository implements ScheduleRepository {
  final List<ScheduleEvent> _events = [..._seedEvents];
  int _nextId = _seedEvents.length;

  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerName) async {
    return _events.where((e) => e.ownerName == ownerName).toList();
  }

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async {
    final withId = event.id.isEmpty
        ? ScheduleEvent(
            id: 'evt_${_nextId++}',
            ownerName: event.ownerName,
            title: event.title,
            details: event.details,
            date: event.date,
            color: event.color,
            icon: event.icon,
          )
        : event;
    _events.add(withId);
    return withId;
  }

  @override
  Future<void> deleteEvent(String id) async {
    _events.removeWhere((e) => e.id == id);
  }

  static final List<ScheduleEvent> _seedEvents = [
    ScheduleEvent(
      id: 'seed_1',
      ownerName: 'Carlos Dela Cruz',
      title: 'Faculty Meeting',
      details: 'Room 201 · 9:00 AM',
      date: DateTime.utc(2026, 5, 19),
      color: AppTheme.maroon,
      icon: Icons.groups_outlined,
    ),
    ScheduleEvent(
      id: 'seed_2',
      ownerName: 'Carlos Dela Cruz',
      title: 'Student Orientation',
      details: 'Main Hall · 2:00 PM',
      date: DateTime.utc(2026, 5, 19),
      color: AppTheme.gold400,
      icon: Icons.school_outlined,
    ),
    ScheduleEvent(
      id: 'seed_3',
      ownerName: 'Carlos Dela Cruz',
      title: 'Attendance Submission',
      details: 'Online Portal · 5:00 PM',
      date: DateTime.utc(2026, 5, 20),
      color: AppTheme.emerald500,
      icon: Icons.task_alt_outlined,
    ),
    ScheduleEvent(
      id: 'seed_4',
      ownerName: 'Carlos Dela Cruz',
      title: 'Report Deadline',
      details: 'Submit via portal',
      date: DateTime.utc(2026, 5, 22),
      color: AppTheme.red500,
      icon: Icons.description_outlined,
    ),
    ScheduleEvent(
      id: 'seed_5',
      ownerName: 'Carlos Dela Cruz',
      title: 'Department Meeting',
      details: 'Conference Room · 10:00 AM',
      date: DateTime.utc(2026, 5, 26),
      color: AppTheme.blue500,
      icon: Icons.business_center_outlined,
    ),
  ];
}
