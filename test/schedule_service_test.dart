import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/schedule_event.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';

ScheduleEvent _event(String ownerId) => ScheduleEvent(
  id: '',
  ownerId: ownerId,
  ownerName: 'Ana Cruz',
  title: 'Math 101',
  details: '8:00 AM',
  date: DateTime(2026, 9, 21),
  color: Colors.blue,
  icon: Icons.book,
);

void main() {
  // Schedules are stored per account, so two people who happen to share a
  // name never see (or overwrite) each other's calendar.
  test('two accounts with the same name keep separate schedules', () async {
    final service = ScheduleService(InMemoryScheduleRepository());

    await service.addEvent(_event('u_ana'));
    await service.addEvent(_event('u_ana'));
    await service.addEvent(_event('u_other_ana'));

    expect(service.eventsFor('u_ana'), hasLength(2));
    expect(service.eventsFor('u_other_ana'), hasLength(1));

    // Reloading from storage gives the same split.
    await service.refresh('u_ana');
    await service.refresh('u_other_ana');
    expect(service.eventsFor('u_ana'), hasLength(2));
    expect(service.eventsFor('u_other_ana'), hasLength(1));
    service.dispose();
  });

  // The DTR report loads a student's schedule and then the rest of its
  // data; a schedule the rules refuse must not stop the rest.
  test('a refused schedule load does not throw', () async {
    final service = ScheduleService(_RefusingRepository());
    await service.refresh('u_other_office');
    expect(service.eventsFor('u_other_office'), isEmpty);
    expect(service.isLoading('u_other_office'), isFalse);
    service.dispose();
  });
}

class _RefusingRepository implements ScheduleRepository {
  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerId) =>
      Future.error(StateError('permission-denied'));

  @override
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerId) =>
      Stream.error(StateError('permission-denied'));

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async => event;

  @override
  Future<void> deleteEvent(String id) async {}
}
