import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

import 'support/account_writes.dart';

/// A Firestore two sessions can share: what one saves, the other's next
/// transaction reads. Live queries are streams the test feeds by hand.
class _Shared extends FirestoreService with AccountWrites {
  final students = <String, Student>{};
  final notifications = <Map<String, dynamic>>[];
  bool failNotifications = false;
  final deletedStudents = <String>[];

  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};

  StreamController<List<Map<String, dynamic>>> list(String key) =>
      _lists.putIfAbsent(key, StreamController.broadcast);

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
  Future<void> setStudent(Student s) async => students[s.id] = s;

  @override
  Future<void> deleteStudent(String id) async {
    deletedStudents.add(id);
    students.remove(id);
  }

  @override
  Future<void> setOffice(Office office) async => officeDocs[office.id] = office;

  @override
  Future<Map<String, String>> getOfficeAssignments() async => {};

  @override
  Future<void> writeOfficeAssignments(Map<String, String?> changes) async {}

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {
    if (failNotifications) throw Exception('permission-denied');
    notifications.add(payload);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

User _user(String id, String name, String role, {String? saId}) =>
    User(id: id, name: name, email: '$id@example.com', role: role, saId: saId);

final _head = _user('head1', 'Hana Head', 'Head');
final _admin = _user('admin1', 'Ana Admin', 'Admin');

Office _office({
  List<String> ids = const [],
  List<String> names = const [],
  int capacity = 0,
  String id = 'o1',
}) => Office(
  id: id,
  name: 'Library',
  code: 'LIB',
  headIds: const ['sup1'],
  headNames: const ['Sid Supervisor'],
  assistantIds: ids,
  assistantNames: names,
  capacity: capacity,
);

void main() {
  late _Shared store;

  AppState session(User as, {List<User> users = const []}) =>
      AppState(firestoreService: store)
        ..currentUser = as
        ..users = [as, ...users];

  setUp(() => store = _Shared());

  group('Student Assistant numbers', () {
    final stu1 = _user('stu1', 'Sam Student', 'Student');
    final stu2 = _user('stu2', 'Sue Student', 'Student');

    test('two approvals at once get different numbers', () async {
      store.profiles
        ..['stu1'] = stu1
        ..['stu2'] = stu2;
      // Two Heads' sessions, each looking at its own copy of the roster.
      final one = session(_head, users: [stu1, stu2]);
      final two = session(_head, users: [stu1, stu2]);

      final ids = await Future.wait([
        one.ensureStudentAssistantId('stu1'),
        two.ensureStudentAssistantId('stu2'),
      ]);

      expect(ids.toSet(), hasLength(2));
      expect(
        {store.profiles['stu1']!.saId, store.profiles['stu2']!.saId},
        {'SA 001', 'SA 002'},
      );
    });

    test('numbering starts after the highest number any profile holds, '
        'deleted ones included', () async {
      store.profiles
        ..['stu1'] = stu1
        ..['old'] = _user(
          'old',
          'Gone',
          'Student',
          saId: 'SA 007',
        ).copyWith(isDeleted: true);

      final id = await session(
        _head,
        users: [stu1],
      ).ensureStudentAssistantId('stu1');

      expect(id, 'SA 008');
    });

    test('asking again returns the same number and uses none up', () async {
      store.profiles['stu1'] = stu1;
      final state = session(_head, users: [stu1]);

      final first = await state.ensureStudentAssistantId('stu1');
      final again = await state.ensureStudentAssistantId('stu1');

      expect(again, first);
      expect(store.saCounter, 2);
    });

    test('only the saId field is written', () async {
      store.profiles['stu1'] = stu1;

      await session(_head, users: [stu1]).ensureStudentAssistantId('stu1');

      expect(store.profileFieldWrites, isEmpty);
      expect(store.profiles['stu1']!.role, 'Student');
    });

    test('a failed save gives no number and changes nothing here', () async {
      store.profiles['stu1'] = stu1;
      store.failAccountWrites = true;
      final state = session(_head, users: [stu1]);

      await expectLater(
        state.ensureStudentAssistantId('stu1'),
        throwsA(isA<Exception>()),
      );

      expect(state.users.firstWhere((u) => u.id == 'stu1').saId, isNull);
    });
  });

  group('changing an account', () {
    final stu = _user('stu1', 'Sam Student', 'Student');

    test('a refused role change leaves the role as it was', () async {
      store.profiles['stu1'] = stu;
      store.failAccountWrites = true;
      final state = session(_admin, users: [stu]);

      final problem = await state.changeUserRole('stu1', 'Supervisor');

      expect(problem, isNotNull);
      expect(state.users.firstWhere((u) => u.id == 'stu1').role, 'Student');
      expect(store.notifications, isEmpty);
    });

    test('a role change writes only the role', () async {
      store.profiles['stu1'] = stu.copyWith(status: 'Archived');
      final state = session(_admin, users: [stu]);

      expect(await state.changeUserRole('stu1', 'Supervisor'), isNull);

      expect(store.profileFieldWrites.single.fields, {'role': 'Supervisor'});
      // Whatever else changed meanwhile (an archive) is not undone.
      expect(store.profiles['stu1']!.status, 'Archived');
    });

    test(
      'a Head promoting someone saves the roster record with the role',
      () async {
        store.profiles['stu1'] = stu;
        final state = session(_head, users: [stu]);

        expect(await state.changeUserRole('stu1', 'Student Assistant'), isNull);

        expect(store.profiles['stu1']!.role, 'Student Assistant');
        expect(store.students.keys, ['stu1']);
      },
    );

    test('an Admin promoting someone writes the profile only', () async {
      store.profiles['stu1'] = stu;
      final state = session(_admin, users: [stu]);

      expect(await state.changeUserRole('stu1', 'Student Assistant'), isNull);

      expect(store.profiles['stu1']!.role, 'Student Assistant');
      expect(store.students, isEmpty);
    });

    test('a refused archive is reported and changes nothing', () async {
      store.profiles['stu1'] = stu;
      store.failAccountWrites = true;
      final state = session(_admin, users: [stu]);

      expect(await state.archiveUser('stu1'), isFalse);

      expect(state.users.firstWhere((u) => u.id == 'stu1').status, 'Active');
    });

    test('archiving writes only the status', () async {
      store.profiles['stu1'] = stu.copyWith(role: 'Student Assistant');
      final state = session(_admin, users: [stu]);

      expect(await state.archiveUser('stu1'), isTrue);

      expect(store.profileFieldWrites.single.fields, {'status': 'Archived'});
      // The role it has now, not the stale copy's.
      expect(store.profiles['stu1']!.role, 'Student Assistant');
    });

    test('deleting twice is harmless', () async {
      store.profiles['stu1'] = stu;
      final state = session(_admin, users: [stu]);

      expect(await state.deleteManagedUser('stu1'), isTrue);
      expect(await state.deleteManagedUser('stu1'), isTrue);

      expect(store.profiles['stu1']!.isDeleted, isTrue);
      expect(store.profileFieldWrites, hasLength(1));
    });

    test('an Admin\'s delete leaves the roster records for the Head', () async {
      store.profiles['stu1'] = stu;
      store.students['stu1'] = Student(
        id: 'stu1',
        name: stu.name,
        email: stu.email,
        department: 'CICS',
        userId: 'stu1',
      );
      final state = session(_admin, users: [stu])
        ..students = [store.students['stu1']!];

      await state.deleteManagedUser('stu1');

      expect(store.deletedStudents, isEmpty);
    });

    test('a failed delete is reported', () async {
      store.profiles['stu1'] = stu;
      store.failAccountWrites = true;
      final state = session(_admin, users: [stu]);

      expect(await state.deleteManagedUser('stu1'), isFalse);

      expect(state.users.map((u) => u.id), contains('stu1'));
    });
  });

  group('office rosters', () {
    final ana = _user('sa1', 'Ana Reyes', 'Student Assistant');
    final ben = _user('sa2', 'Ben Cruz', 'Student Assistant');
    final cara = _user('sa3', 'Cara Lim', 'Student Assistant');

    test('two Heads adding different people do not erase each other', () async {
      final shown = _office(ids: ['sa1'], names: ['Ana Reyes']);
      store.officeDocs['o1'] = shown;
      final one = session(_head)..offices = [shown];
      final two = session(_head)..offices = [shown];

      // Both started from the roster with Ana alone.
      expect(
        await one.assignStudentAssistantsToOffice('o1', [ana, ben]),
        isTrue,
      );
      expect(
        await two.assignStudentAssistantsToOffice('o1', [ana, cara]),
        isTrue,
      );

      final saved = store.officeDocs['o1']!;
      expect(saved.assistantIds.toSet(), {'sa1', 'sa2', 'sa3'});
      // Ids and names stay paired.
      for (var i = 0; i < saved.assistantIds.length; i++) {
        expect(
          saved.assistantNames[i],
          {
            'sa1': 'Ana Reyes',
            'sa2': 'Ben Cruz',
            'sa3': 'Cara Lim',
          }[saved.assistantIds[i]],
        );
      }
    });

    test('a removal applies to the roster as stored now', () async {
      final shown = _office(
        ids: ['sa1', 'sa2'],
        names: ['Ana Reyes', 'Ben Cruz'],
      );
      store.officeDocs['o1'] = shown.copyWith(
        assistantIds: ['sa1', 'sa2', 'sa3'],
        assistantNames: ['Ana Reyes', 'Ben Cruz', 'Cara Lim'],
      );
      final state = session(_head)..offices = [shown];

      // This Head took Ben off; Cara was added by someone else meanwhile.
      await state.assignStudentAssistantsToOffice('o1', [ana]);

      expect(store.officeDocs['o1']!.assistantIds, ['sa1', 'sa3']);
    });

    test('a full office refuses, using the roster as stored now', () async {
      final shown = _office(ids: ['sa1'], names: ['Ana Reyes'], capacity: 2);
      store.officeDocs['o1'] = shown.copyWith(
        assistantIds: ['sa1', 'sa3'],
        assistantNames: ['Ana Reyes', 'Cara Lim'],
      );
      final state = session(_head)..offices = [shown];

      // It looks like there is room; someone filled it meanwhile.
      expect(
        await state.assignStudentAssistantsToOffice('o1', [ana, ben]),
        isFalse,
      );

      expect(store.officeDocs['o1']!.assistantIds, ['sa1', 'sa3']);
    });

    test(
      'a move leaves the old office and joins the new one together',
      () async {
        final library = _office(ids: ['sa1'], names: ['Ana Reyes']);
        final registrar = _office(id: 'o2').copyWith(name: 'Registrar');
        store.officeDocs['o1'] = library;
        store.officeDocs['o2'] = registrar;
        final state = session(_head)..offices = [library, registrar];

        expect(
          await state.assignStudentAssistantsToOffice('o2', [ana]),
          isTrue,
        );

        expect(store.officeDocs['o1']!.assistantIds, isEmpty);
        expect(store.officeDocs['o2']!.assistantIds, ['sa1']);
      },
    );

    test(
      'two Heads placing one person in different offices leave them in one',
      () async {
        final library = _office(id: 'o1');
        final registrar = _office(id: 'o2').copyWith(name: 'Registrar');
        store.officeDocs['o1'] = library;
        store.officeDocs['o2'] = registrar;
        final one = session(_head)..offices = [library, registrar];
        final two = session(_head)..offices = [library, registrar];

        // Both see Ana unplaced.
        expect(await one.assignStudentAssistantsToOffice('o1', [ana]), isTrue);
        expect(await two.assignStudentAssistantsToOffice('o2', [ana]), isTrue);

        final inLibrary = store.officeDocs['o1']!.assistantIds.contains('sa1');
        final inRegistrar = store.officeDocs['o2']!.assistantIds.contains(
          'sa1',
        );
        expect(inLibrary != inRegistrar, isTrue);
        expect(store.assignmentDocs['sa1'], inRegistrar ? 'o2' : 'o1');
      },
    );

    test('a refused save returns false and shows nothing new', () async {
      final shown = _office();
      store.officeDocs['o1'] = shown;
      store.failAccountWrites = true;
      final state = session(_head)..offices = [shown];

      expect(await state.assignStudentAssistantsToOffice('o1', [ana]), isFalse);

      expect(state.offices.single.assistantIds, isEmpty);
    });

    test('an office that has gone is a refusal, not a crash', () async {
      final state = session(_head);

      expect(
        await state.assignStudentAssistantsToOffice('nope', [ana]),
        isFalse,
      );
      expect(await state.assignSupervisorsToOffice('nope', []), isFalse);
    });

    test('a dialog opened earlier keeps the roster and changes supervisors by '
        'what it changed', () async {
      final opened = _office(ids: ['sa1'], names: ['Ana Reyes']);
      // Meanwhile someone was placed, and a second supervisor added.
      store.officeDocs['o1'] = opened.copyWith(
        assistantIds: ['sa1', 'sa2'],
        assistantNames: ['Ana Reyes', 'Ben Cruz'],
        headIds: ['sup1', 'sup3'],
        headNames: ['Sid Supervisor', 'Tia Supervisor'],
      );
      final state = session(_head)..offices = [opened];

      // The dialog (opened on the old office) adds Tess and drops nobody.
      await state.saveOffice(
        opened.copyWith(
          headIds: ['sup1', 'sup2'],
          headNames: ['Sid Supervisor', 'Tess Supervisor'],
        ),
        basedOn: opened,
      );

      final saved = store.officeDocs['o1']!;
      expect(saved.assistantIds, ['sa1', 'sa2']);
      expect(saved.headIds, ['sup1', 'sup3', 'sup2']);
    });

    test('renaming an office keeps the people stored now', () async {
      final shown = _office(ids: ['sa1'], names: ['Ana Reyes']);
      store.officeDocs['o1'] = shown.copyWith(
        assistantIds: ['sa1', 'sa2'],
        assistantNames: ['Ana Reyes', 'Ben Cruz'],
      );
      final state = session(_head)..offices = [shown];

      await state.saveOffice(shown.copyWith(name: 'Main Library'));

      expect(store.officeDocs['o1']!.name, 'Main Library');
      expect(store.officeDocs['o1']!.assistantIds, ['sa1', 'sa2']);
    });
  });

  group('finishing a promotion', () {
    final stu = _user('stu1', 'Sam Student', 'Student');

    test(
      'saving the approval again repairs a missing students record',
      () async {
        // The role was saved before, the roster record never was.
        final assistant = stu.copyWith(role: 'Student Assistant');
        store.profiles['stu1'] = assistant;
        final state = session(_head, users: [assistant]);

        expect(await state.changeUserRole('stu1', 'Student Assistant'), isNull);

        expect(store.students.keys, ['stu1']);
      },
    );

    test('and brings back an archived one', () async {
      final assistant = stu.copyWith(role: 'Student Assistant');
      store.profiles['stu1'] = assistant;
      final archived = Student(
        id: 'stu1',
        name: stu.name,
        email: stu.email,
        department: 'CICS',
        userId: 'stu1',
        status: 'Archived',
      );
      store.students['stu1'] = archived;
      final state = session(_head, users: [assistant])..students = [archived];

      expect(await state.changeUserRole('stu1', 'Student Assistant'), isNull);

      expect(store.students['stu1']!.status, 'Active');
      expect(store.profileFieldWrites, isEmpty);
    });
  });

  group('a Head clears what a deleted account left', () {
    test('an older office entry that has only a name', () async {
      final gone = _user(
        'gone1',
        'Gina Gone',
        'Student Assistant',
      ).copyWith(isDeleted: true, status: 'Archived');
      // Saved before accounts had ids: a name with no id beside it.
      store.officeDocs['o1'] = _office(ids: [''], names: ['Gina Gone']);
      final state = session(_head);
      await state.init();

      store.list('offices').add([
        {...store.officeDocs['o1']!.toJson(), 'id': 'o1'},
      ]);
      store.list('users').add([_head.toJson(), gone.toJson()]);
      for (var i = 0; i < 6; i++) {
        await _settle();
      }

      expect(store.officeDocs['o1']!.assistantNames, isEmpty);
      state.dispose();
    });

    test('its roster record and office places', () async {
      final gone = _user(
        'gone1',
        'Gina Gone',
        'Student Assistant',
      ).copyWith(isDeleted: true, status: 'Archived');
      store.students['gone1'] = Student(
        id: 'gone1',
        name: gone.name,
        email: gone.email,
        department: 'CICS',
        userId: 'gone1',
      );
      store.officeDocs['o1'] = _office(
        ids: ['gone1', 'sa1'],
        names: ['Gina Gone', 'Ana Reyes'],
      );
      final state = session(_head);
      await state.init();

      store.list('offices').add([
        {...store.officeDocs['o1']!.toJson(), 'id': 'o1'},
      ]);
      store.list('students').add([
        {
          'id': 'gone1',
          'name': gone.name,
          'email': gone.email,
          'department': 'CICS',
          'userId': 'gone1',
        },
      ]);
      store.list('users').add([
        _head.toJson(),
        gone.toJson(),
        _user('sa1', 'Ana Reyes', 'Student Assistant').toJson(),
      ]);
      for (var i = 0; i < 6; i++) {
        await _settle();
      }

      expect(store.deletedStudents, ['gone1']);
      expect(store.officeDocs['o1']!.assistantIds, ['sa1']);
      state.dispose();
    });
  });

  group('a notification that cannot be saved', () {
    test('is taken back and the sender is told', () async {
      store.failNotifications = true;
      final state = session(_head, users: [_user('stu1', 'Sam', 'Student')]);
      final told = <String>[];
      state.problemNotices.listen(told.add);
      state.announcements = [
        Announcement(
          id: '',
          title: 'Need two assistants',
          body: 'Library',
          postedBy: 'Sid',
          postedByRole: 'Supervisor',
          postedAt: 'Oct 1, 2026',
          postedById: 'sup1',
          approvalStatus: 'Pending',
        ),
      ];

      await state.rejectAnnouncement('', reason: 'No budget');
      await _settle();
      await _settle();

      expect(told.single, contains('Announcement Rejected'));
      expect(state.notifications, isEmpty);
    });
  });

  group('signing out', () {
    test('forgets what the account could see', () async {
      final state = session(_admin)
        ..students = [
          Student(id: 's', name: 'A', email: 'a@x.com', department: 'CICS'),
        ]
        ..notifications = [
          AppNotification(
            id: 'n',
            userId: 'admin1',
            title: 't',
            message: 'm',
            type: 'system',
            createdAt: 'Oct 1, 2026',
          ),
        ];

      state.logout();

      expect(state.users, isEmpty);
      expect(state.students, isEmpty);
      expect(state.notifications, isEmpty);
      expect(state.currentUser, isNull);
    });
  });
}
