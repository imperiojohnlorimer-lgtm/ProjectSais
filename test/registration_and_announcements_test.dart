import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Stands in for Firestore: records what the app saves, and can be told to
/// refuse a save the way the rules or a dropped connection would.
class _FakeFirestore extends FirestoreService {
  final added = <Map<String, dynamic>>[];
  final savedApplications = <Application>[];
  bool failWrites = false;

  /// What studentIds holds, and every batch of changes written to it.
  Map<String, String> claims = {};
  final claimWrites = <Map<String, String?>>[];

  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};

  StreamController<List<Map<String, dynamic>>> list(String key) =>
      _lists.putIfAbsent(key, StreamController.broadcast);

  List<Map<String, dynamic>> sentTo(String userId) =>
      added.where((n) => n['userId'] == userId).toList();

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
      const Stream.empty();

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => [];

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      added.add(payload);

  @override
  Future<void> setApplication(Application a) async => savedApplications.add(a);

  @override
  Future<void> updateAnnouncement(String id, Map<String, dynamic> data) async {
    if (failWrites) throw Exception('permission-denied');
  }

  @override
  Future<void> deleteAnnouncement(String id) async {
    if (failWrites) throw Exception('permission-denied');
  }

  @override
  Future<void> setOffice(Office office) async {}

  @override
  Future<Map<String, String>> getOfficeAssignments() async => {};

  @override
  Future<void> writeOfficeAssignments(Map<String, String?> changes) async {}

  @override
  Future<Map<String, String>> getStudentIdClaims() async => {...claims};

  @override
  Future<void> writeStudentIdClaims(Map<String, String?> changes) async {
    claimWrites.add(changes);
    for (final MapEntry(key: id, value: uid) in changes.entries) {
      if (uid == null) {
        claims.remove(id);
      } else {
        claims[id] = uid;
      }
    }
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final _head = User(
  id: 'h1',
  name: 'Helen Head',
  email: 'head@example.com',
  role: 'Head',
);

User _person(String id, String name, {String role = 'Student Assistant'}) =>
    User(id: id, name: name, email: '$id@example.com', role: role);

Announcement _posting({String? deadline, bool isOpen = true}) => Announcement(
  id: 'a1',
  title: 'Library Aide',
  body: '',
  postedBy: 'Helen Head',
  postedByRole: 'Head',
  postedAt: '2026-09-01',
  deadline: deadline,
  isOpen: isOpen,
  approvalStatus: 'Approved',
);

void main() {
  late _FakeFirestore fake;
  late AppState state;

  setUp(() {
    fake = _FakeFirestore();
    state = AppState(firestoreService: fake);
  });

  group('application deadlines', () {
    test('reads the deadline however it was written', () {
      expect(_posting(deadline: 'Jun 5, 2026').deadlineDate, DateTime(2026, 6, 5));
      expect(_posting(deadline: 'June 5, 2026').deadlineDate, DateTime(2026, 6, 5));
      expect(_posting(deadline: 'Sept 30, 2026').deadlineDate, DateTime(2026, 9, 30));
      expect(_posting(deadline: 'soon').deadlineDate, isNull);
      expect(_posting().deadlineDate, isNull);
    });

    test('applications are taken through the deadline day', () {
      final posting = _posting(deadline: 'Oct 5, 2026');
      expect(posting.isPastDeadline(DateTime(2026, 10, 5, 23, 59)), isFalse);
      expect(posting.isPastDeadline(DateTime(2026, 10, 6, 0, 1)), isTrue);
      // No deadline, or one that can't be read, never closes it.
      expect(_posting().isPastDeadline(DateTime(2099)), isFalse);
      expect(_posting(deadline: 'soon').isPastDeadline(DateTime(2099)), isFalse);
    });

    test('a late application is refused', () async {
      final student = _person('stu1', 'Sam Student', role: 'Student');
      state
        ..currentUser = student
        ..users = [student]
        ..announcements = [_posting(deadline: 'Jan 5, 2020')];

      final ok = await state.submitApplication(
        Application(
          id: 'app1',
          announcementId: 'a1',
          announcementTitle: 'Library Aide',
          applicantId: 'stu1',
          applicantName: 'Sam Student',
          appliedAt: 'Sep 27, 2026',
        ),
      );

      expect(ok, isFalse);
      expect(fake.savedApplications, isEmpty);
      expect(fake.added, isEmpty);
    });
  });

  group('closing and deleting announcements', () {
    setUp(() {
      state
        ..currentUser = _head
        ..announcements = [_posting()];
    });

    test('a close that fails to save leaves it open', () async {
      fake.failWrites = true;

      expect(await state.closeAnnouncement('a1'), isFalse);
      expect(state.announcements.single.isOpen, isTrue);
    });

    test('a close that saves shows it closed', () async {
      expect(await state.closeAnnouncement('a1'), isTrue);
      expect(state.announcements.single.isOpen, isFalse);
    });

    test('a delete that fails to save keeps it', () async {
      fake.failWrites = true;

      expect(await state.deleteAnnouncement('a1'), isFalse);
      expect(state.announcements, hasLength(1));
    });
  });

  group('office assignment notifications', () {
    final ana = _person('sa1', 'Ana Reyes');
    final ben = _person('sa2', 'Ben Cruz');
    final cara = _person('sa3', 'Cara Lim');
    final sid = _person('sup1', 'Sid Supervisor', role: 'Supervisor');
    final tess = _person('sup2', 'Tess Supervisor', role: 'Supervisor');

    setUp(() {
      state
        ..currentUser = _head
        ..offices = [
          const Office(
            id: 'o1',
            name: 'Library',
            code: 'LIB',
            headIds: ['sup1'],
            headNames: ['Sid Supervisor'],
            assistantIds: ['sa1', 'sa2'],
            assistantNames: ['Ana Reyes', 'Ben Cruz'],
          ),
        ];
    });

    test('only a newly added student is told', () async {
      await state.assignStudentAssistantsToOffice('o1', [ana, ben, cara]);

      expect(fake.sentTo('sa3').single['message'],
          'You have been assigned to Library.');
      expect(fake.sentTo('sa1'), isEmpty);
      expect(fake.sentTo('sa2'), isEmpty);
      expect(fake.sentTo('sup1').single['message'],
          'Cara Lim was assigned to Library.');
    });

    test('saving an unchanged roster tells no one', () async {
      await state.assignStudentAssistantsToOffice('o1', [ana, ben]);

      expect(fake.added, isEmpty);
    });

    test('only a newly added supervisor is told', () async {
      await state.assignSupervisorsToOffice('o1', [sid, tess]);

      expect(fake.sentTo('sup2').single['message'],
          'You have been assigned to supervise Library.');
      expect(fake.sentTo('sup1'), isEmpty);
      expect(fake.sentTo('sa1').single['message'],
          'Tess Supervisor was assigned to supervise Library.');
    });

    test('re-saving the same supervisors tells no one', () async {
      await state.assignSupervisorsToOffice('o1', [sid]);

      expect(fake.added, isEmpty);
    });
  });

  group('Student ID reservations', () {
    test('one ID, however it was typed', () {
      expect(AppState.studentIdKey(' 23b0626 '), '23B0626');
      expect(AppState.studentIdKey(''), isNull);
      expect(AppState.studentIdKey(null), isNull);
      expect(AppState.studentIdKey('23/0626'), isNull);
    });

    test('the Admin session reserves IDs for existing accounts', () async {
      final admin = _person('a1', 'Ana Admin', role: 'Admin');
      fake.claims = {
        // The Admin changed this account's ID to NEW1 since.
        'OLD1': 'u_old',
        // An account the roster doesn't have (deleted, or just registered).
        'KEEP': 'u_other',
      };
      state.currentUser = admin;
      await state.init();

      fake.list('users').add([
        admin.toJson(),
        User(
          id: 'u1',
          name: 'First',
          email: 'first@example.com',
          role: 'Student',
          studentId: '23b0626',
        ).toJson(),
        User(
          id: 'u_old',
          name: 'Edited',
          email: 'edited@example.com',
          role: 'Student',
          studentId: 'new1',
        ).toJson(),
        // An older duplicate: the first account keeps the ID.
        User(
          id: 'u2',
          name: 'Second',
          email: 'second@example.com',
          role: 'Student',
          studentId: '23B0626',
        ).toJson(),
      ]);
      await _settle();
      await _settle();

      expect(fake.claims, {
        '23B0626': 'u1',
        'NEW1': 'u_old',
        'KEEP': 'u_other',
      });
    });

    test("an unchanged roster doesn't re-read the reservations", () async {
      final admin = _person('a1', 'Ana Admin', role: 'Admin');
      state.currentUser = admin;
      await state.init();
      final roster = [
        admin.toJson(),
        User(
          id: 'u1',
          name: 'First',
          email: 'first@example.com',
          role: 'Student',
          studentId: '23B0626',
        ).toJson(),
      ];

      fake.list('users').add(roster);
      await _settle();
      await _settle();
      fake.list('users').add(roster);
      await _settle();
      await _settle();

      expect(fake.claimWrites, hasLength(1));
    });
  });
}
