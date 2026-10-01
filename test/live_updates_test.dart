import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/schedule_event.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';

/// Stands in for Firestore's live queries: every query gets a controller
/// the test pushes documents into, the way another browser's writes would
/// arrive. Anything not faked here fails like Firestore does when there's
/// no Firebase app, which the app already tolerates.
class _FakeLiveFirestore extends FirestoreService {
  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};
  final _docs = <String, StreamController<Map<String, dynamic>?>>{};

  StreamController<List<Map<String, dynamic>>> list(String key) =>
      _lists.putIfAbsent(key, StreamController.broadcast);

  StreamController<Map<String, dynamic>?> doc(String key) =>
      _docs.putIfAbsent(key, StreamController.broadcast);

  @override
  Stream<List<Map<String, dynamic>>> collectionStream(
    String collection, {
    bool newestFirst = false,
  }) => list(collection).stream;

  @override
  Stream<List<Map<String, dynamic>>> whereStream(
    String collection,
    String field,
    Object value, {
    bool newestFirst = false,
  }) => list('$collection.$field=$value').stream;

  @override
  Stream<List<Map<String, dynamic>>> whereInStream(
    String collection,
    String field,
    List<Object> values,
  ) => list('$collection.$field in $values').stream;

  @override
  Stream<Map<String, dynamic>?> docStream(String collection, String id) =>
      doc('$collection/$id').stream;

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => [];

  /// Like Firestore, reports the new folder to the live query before the
  /// save returns.
  final folders = <Map<String, dynamic>>[];

  @override
  Future<String> addDocumentFolder(DocumentFolder folder) async {
    final id = 'folder${folders.length + 1}';
    folders.add({...folder.toJson(), 'id': id});
    list('documentFolders').add(List.of(folders));
    await _settle();
    return id;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<(AppState, _FakeLiveFirestore)> _signedIn(User user) async {
  final fake = _FakeLiveFirestore();
  final state = AppState(firestoreService: fake)..currentUser = user;
  await state.init();
  return (state, fake);
}

void main() {
  final admin = User(
    id: 'admin1',
    name: 'Ana Admin',
    email: 'admin@example.com',
    role: 'Admin',
  );
  final student = User(
    id: 'stu1',
    name: 'Sam Student',
    email: 'sam@example.com',
    role: 'Student',
  );

  test('the Accounts list picks up a new registration live', () async {
    final (state, fake) = await _signedIn(admin);

    fake.list('users').add([
      admin.toJson(),
      student.toJson(),
    ]);
    await _settle();

    expect(
      state.users.map((u) => u.email),
      containsAll(['admin@example.com', 'sam@example.com']),
    );
  });

  test('a role changed elsewhere applies without signing in again', () async {
    final (state, fake) = await _signedIn(student);

    fake
        .doc('users/stu1')
        .add(student.copyWith(role: 'Student Assistant').toJson());
    await _settle();

    expect(state.role, 'Student Assistant');
  });

  test('an archived account is signed out', () async {
    final (state, fake) = await _signedIn(student);

    fake.doc('users/stu1').add(student.copyWith(status: 'Archived').toJson());
    await _settle();

    expect(state.isAuthenticated, isFalse);
  });

  test('new notifications arrive live', () async {
    final (state, fake) = await _signedIn(student);

    fake.list('notifications.userId=stu1').add([
      {
        'id': 'n1',
        'userId': 'stu1',
        'title': 'Application Approved',
        'message': 'Your application was approved.',
        'type': 'application',
        'isRead': false,
      },
    ]);
    await _settle();

    expect(state.unreadNotificationCount, 1);
  });

  test('a new term set by the Admin reaches everyone live', () async {
    final (state, fake) = await _signedIn(student);

    fake.doc('meta/academic_year_settings').add({
      'academicYear': '2026-2027',
      'semester': '2nd Semester',
    });
    await _settle();

    expect(state.academicSemester, '2nd Semester');
  });

  test('signing out stops the live listeners', () async {
    final (state, fake) = await _signedIn(admin);
    state.logout();

    fake.list('users').add([student.toJson()]);
    await _settle();

    expect(state.users.any((u) => u.email == 'sam@example.com'), isFalse);
  });

  test('a new document folder is listed once, newest first', () async {
    final head = User(
      id: 'head1',
      name: 'Hana Head',
      email: 'head@example.com',
      role: 'Head',
    );
    final (state, fake) = await _signedIn(head);
    fake.folders.addAll([
      {'id': 'old', 'name': 'Memos', 'createdAt': '2020-09-01T08:00:00.000'},
      {'id': 'new', 'name': 'MOAs', 'createdAt': '2020-09-20T08:00:00.000'},
    ]);
    fake.list('documentFolders').add(List.of(fake.folders));
    await _settle();
    expect(state.documentFolders.map((f) => f.name), ['MOAs', 'Memos']);

    await state.createDocumentFolder('Office Orders');

    expect(state.documentFolders.map((f) => f.name), [
      'Office Orders',
      'MOAs',
      'Memos',
    ]);
  });

  test('calendar events update live', () async {
    final repo = _FakeScheduleRepository();
    final service = ScheduleService(repo);
    await service.ensureLoaded('Sam Student');

    repo.events.add([
      ScheduleEvent(
        id: 'e1',
        ownerName: 'Sam Student',
        title: 'Math 101',
        details: '8:00 AM',
        date: DateTime(2026, 9, 21),
        color: Colors.blue,
        icon: Icons.book,
      ),
    ]);
    await _settle();

    expect(service.eventsFor('Sam Student').map((e) => e.title), [
      'Math 101',
    ]);
    service.dispose();
  });
}

class _FakeScheduleRepository implements ScheduleRepository {
  final events = StreamController<List<ScheduleEvent>>.broadcast();

  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerName) async => [];

  @override
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerName) => events.stream;

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async => event;

  @override
  Future<void> deleteEvent(String id) async {}
}
