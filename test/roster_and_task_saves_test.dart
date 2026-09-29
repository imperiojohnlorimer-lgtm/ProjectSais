import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Keeps the students records, profiles and tasks the app saves in memory,
/// and refuses every save while [fail] is set.
class _Store extends FirestoreService {
  bool fail = false;
  final students = <String, Student>{};
  final profiles = <String, User>{};
  final tasks = <String, Task>{};
  final notifications = <Map<String, dynamic>>[];

  void _check() {
    if (fail) throw Exception('permission-denied');
  }

  @override
  Future<void> setStudent(Student s) async {
    _check();
    students[s.id] = s;
  }

  @override
  Future<void> setUserProfile(User user) async {
    _check();
    profiles[user.id] = user;
  }

  @override
  Future<void> setStudentWithProfile(Student s, User profile) async {
    _check();
    students[s.id] = s;
    profiles[profile.id] = profile;
  }

  @override
  Future<void> setTask(Task t) async {
    _check();
    tasks[t.id] = t;
  }

  @override
  Future<void> deleteTask(String id) async {
    _check();
    tasks.remove(id);
  }

  final offices = <String, Office>{};

  @override
  Future<void> setOffice(Office office) async {
    _check();
    offices[office.id] = office;
  }

  @override
  Future<Map<String, String>> getOfficeAssignments() async => {};

  @override
  Future<void> writeOfficeAssignments(Map<String, String?> changes) async {}

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);
}

final _head = User(
  id: 'head1',
  name: 'Hannah Head',
  email: 'h@x.com',
  role: 'Head',
);
final _assistant = User(
  id: 'sa1',
  name: 'Sam Assistant',
  email: 'sam@x.com',
  role: 'Student Assistant',
  department: 'CICS',
);
Student _record({String status = 'Active', String department = 'CICS'}) =>
    Student(
      id: 'sa1',
      name: _assistant.name,
      email: _assistant.email,
      department: department,
      status: status,
      userId: 'sa1',
    );
Task _task({bool archived = false}) => Task(
  id: 't1',
  title: 'Shelve returns',
  description: '',
  status: 'Not Started',
  priority: 'Low',
  dueDate: 'Oct 1, 2026',
  assignedTo: 'sa1',
  isArchived: archived,
);

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store();
    state = AppState(firestoreService: store)
      ..currentUser = _head
      ..users = [_head, _assistant];
  });

  group('archiving students', () {
    test(
      'deactivates the account and moves them to the archived list',
      () async {
        state.students = [_record()];

        expect(await state.archiveStudent('sa1'), isNull);

        // The account is the one switch: the record itself is left alone.
        expect(store.profiles['sa1']?.status, 'Archived');
        expect(store.students, isEmpty);
        expect(state.users.firstWhere((u) => u.id == 'sa1').status, 'Archived');
        expect(state.filteredStudents.map((s) => s.id), isNot(contains('sa1')));
        expect(state.archivedStudents.single.status, 'Archived');
      },
    );

    test(
      'an assistant with no record is archived through their account',
      () async {
        // Listed only from their account (no students document).
        expect(state.filteredStudents.map((s) => s.id), contains('sa1'));

        expect(await state.archiveStudent('sa1'), isNull);

        expect(store.profiles['sa1']?.status, 'Archived');
        expect(state.filteredStudents.map((s) => s.id), isNot(contains('sa1')));
        expect(state.archivedStudents.map((s) => s.id), contains('sa1'));
      },
    );

    test('takes them off their office and tells its supervisors', () async {
      state
        ..students = [_record()]
        ..offices = [
          Office(
            id: 'o1',
            name: 'Library',
            code: 'LIB',
            headIds: ['sup1'],
            assistantIds: ['sa1'],
            assistantNames: [_assistant.name],
          ),
        ];

      expect(await state.archiveStudent('sa1'), isNull);

      expect(store.offices['o1']?.assistantIds, isEmpty);
      final told = store.notifications.where((n) => n['userId'] == 'sup1');
      expect(told.single['title'], 'Student Assistant Archived');
    });

    test(
      'a refused save leaves the account active and on the roster',
      () async {
        state.students = [_record()];
        store.fail = true;

        expect(await state.archiveStudent('sa1'), isNotNull);

        expect(state.users.firstWhere((u) => u.id == 'sa1').status, 'Active');
        expect(state.filteredStudents.map((s) => s.id), contains('sa1'));
      },
    );

    test('an account the Admin archived is off the roster too', () async {
      state
        ..users = [_head, _assistant.copyWith(status: 'Archived')]
        ..students = [_record()];

      expect(state.filteredStudents.map((s) => s.id), isNot(contains('sa1')));
      expect(state.archivedStudents.map((s) => s.id), contains('sa1'));
    });

    test(
      'the Admin restoring the account puts them back on the roster',
      () async {
        state
          ..users = [_head, _assistant.copyWith(status: 'Archived')]
          ..students = [_record()];

        await state.restoreUser('sa1');

        expect(state.filteredStudents.map((s) => s.id), contains('sa1'));
        expect(state.archivedStudents, isEmpty);
      },
    );

    test('restoring reactivates the account', () async {
      state
        ..users = [_head, _assistant.copyWith(status: 'Archived')]
        ..students = [_record()];

      expect(await state.restoreStudent('sa1'), isNull);

      expect(store.profiles['sa1']?.status, 'Active');
      expect(state.filteredStudents.map((s) => s.id), contains('sa1'));
      expect(state.archivedStudents, isEmpty);
    });

    test('restoring brings back a record that was itself archived', () async {
      // Older data: the record archived while the account stayed active.
      state.students = [_record(status: 'Archived')];

      expect(await state.restoreStudent('sa1'), isNull);

      expect(store.students['sa1']?.status, 'Active');
      expect(state.filteredStudents.map((s) => s.id), contains('sa1'));
    });

    test(
      'someone who is no longer a Student Assistant is not restored',
      () async {
        state
          ..users = [_head, _assistant.copyWith(role: 'Student')]
          ..students = [_record(status: 'Archived')];

        expect(await state.restoreStudent('sa1'), contains('Rehiring'));

        expect(store.students, isEmpty);
        expect(store.profiles, isEmpty);
      },
    );
  });

  group('changing a student department', () {
    test('saves the record and the account together', () async {
      state.students = [_record()];

      expect(await state.updateStudentDepartment('sa1', 'COE'), isNull);

      expect(store.students['sa1']?.department, 'COE');
      expect(store.profiles['sa1']?.department, 'COE');
      expect(state.users.firstWhere((u) => u.id == 'sa1').department, 'COE');
    });

    test('a refused save puts both back', () async {
      state.students = [_record()];
      store.fail = true;

      expect(await state.updateStudentDepartment('sa1', 'COE'), isNotNull);

      expect(state.students.single.department, 'CICS');
      expect(state.users.firstWhere((u) => u.id == 'sa1').department, 'CICS');
    });
  });

  group('task saves', () {
    test('a refused new task is taken back and nobody is notified', () async {
      store.fail = true;

      expect(await state.addTask(_task()), isFalse);

      expect(state.tasks, isEmpty);
      expect(store.notifications, isEmpty);
    });

    test('a saved new task notifies the student', () async {
      expect(await state.addTask(_task()), isTrue);

      expect(store.tasks, contains('t1'));
      expect(store.notifications.single['userId'], 'sa1');
    });

    test('a refused archive puts the task back as it was', () async {
      state.tasks = [_task()];
      store.fail = true;

      expect(await state.setTaskArchived('t1', true), isFalse);

      expect(state.tasks.single.isArchived, isFalse);
    });

    test('a saved archive is kept', () async {
      state.tasks = [_task()];

      expect(await state.setTaskArchived('t1', true), isTrue);

      expect(store.tasks['t1']?.isArchived, isTrue);
    });

    test('a refused delete puts the task back', () async {
      state.tasks = [_task()];
      store.fail = true;

      expect(await state.deleteTask('t1'), isFalse);

      expect(state.tasks.single.id, 't1');
    });
  });
}
