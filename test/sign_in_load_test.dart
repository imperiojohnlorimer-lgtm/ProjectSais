import 'dart:async';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Answers the sign-in reads by hand: records when each starts and ends, can
/// hold any of them until released, and can make any of them fail.
class _LoadStore extends FirestoreService {
  final log = <String>[];
  final _holds = <String, Completer<void>>{};
  final failing = <String>{};

  List<User> userProfiles = [];
  List<Student> studentRecords = [];
  List<Task> tasksOfUser = [];
  List<Task> tasksOfAssignee = [];
  List<Application> applicationRecords = [];
  List<Document> documentRecords = [];

  void hold(String name) => _holds[name] = Completer<void>();
  void release(String name) => _holds[name]?.complete();
  void releaseAll() {
    for (final gate in _holds.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  bool started(String name) => log.contains('start:$name');
  int at(String entry) => log.indexOf(entry);

  Future<T> _read<T>(String name, T answer) async {
    log.add('start:$name');
    await _holds[name]?.future;
    log.add('end:$name');
    if (failing.contains(name)) throw Exception('$name failed');
    return answer;
  }

  @override
  Future<List<User>> getAllUserProfiles() => _read('users', userProfiles);
  @override
  Future<Map<String, dynamic>?> getAcademicYearSettings() =>
      _read<Map<String, dynamic>?>('settings', null);
  @override
  Future<List<Map<String, dynamic>>> getAcademicYearArchives() =>
      _read('archives', <Map<String, dynamic>>[]);
  @override
  Future<List<Office>> getAllOffices() => _read('offices', <Office>[]);
  @override
  Future<List<String>> getAllDepartments() =>
      _read('departments', <String>['Computing']);
  @override
  Future<Map<String, String>> getDepartmentCodes() =>
      _read('codes', <String, String>{});
  @override
  Future<List<Program>> getAllPrograms() => _read('programs', <Program>[]);
  @override
  Future<List<String>> getAllSkills() => _read('skills', <String>[]);
  @override
  Future<List<ScreeningRecord>> getAllScreeningRecords() =>
      _read('screening', <ScreeningRecord>[]);
  @override
  Future<List<Student>> getAllStudents() => _read('students', studentRecords);
  @override
  Future<List<Map<String, dynamic>>> getAllAttendance() =>
      _read('attendance', <Map<String, dynamic>>[]);
  @override
  Future<List<Map<String, dynamic>>> getAttendanceForStudent(String uid) =>
      _read('attendance', <Map<String, dynamic>>[]);
  @override
  Future<List<ClassScheduleEntry>> getAllClassSchedules() =>
      _read('schedules', <ClassScheduleEntry>[]);
  @override
  Future<List<ClassScheduleEntry>> getClassSchedulesForStudent(String uid) =>
      _read('schedules', <ClassScheduleEntry>[]);
  @override
  Future<List<HeadForward>> getAllHeadForwards() =>
      _read('forwards', <HeadForward>[]);
  @override
  Future<List<Document>> getAllDocuments() =>
      _read('documents', documentRecords);
  @override
  Future<List<Task>> getAllTasks() => _read('tasks', tasksOfUser);
  @override
  Future<List<Task>> getTasksForUser(String uid) =>
      _read('tasksByUser', tasksOfUser);
  @override
  Future<List<String>> getStudentIdsForUser(String uid) =>
      _read('studentIds', <String>['rec1']);
  @override
  Future<List<Task>> getTasksForAssigneeIds(List<String> ids) =>
      _read('tasksByAssignee', tasksOfAssignee);
  @override
  Future<List<Report>> getAllReports() => _read('reports', <Report>[]);
  @override
  Future<List<Report>> getReportsForApplicant(String uid) =>
      _read('reports', <Report>[]);
  @override
  Future<List<Evaluation>> getAllEvaluations() =>
      _read('evaluations', <Evaluation>[]);
  @override
  Future<List<Application>> getAllApplications() =>
      _read('applications', applicationRecords);
  @override
  Future<List<RehireRecord>> getAllRehireRecords() =>
      _read('rehire', <RehireRecord>[]);
  @override
  Future<void> setSkill(String name) => _read('setSkill', null);
  @override
  Future<int> pingAnnouncements() => _read('pingAnnouncements', 42);
  @override
  Future<int> pingReports() => _read('pingReports', 7);

  @override
  Future<List<Map<String, dynamic>>> getNotificationsForUser(
    String userId,
  ) async => const [];

  // The live listeners never answer here; these tests are about the load.
  final _streams = <String, StreamController<List<Map<String, dynamic>>>>{};
  StreamController<List<Map<String, dynamic>>> _stream(String key) =>
      _streams.putIfAbsent(key, StreamController.broadcast);

  @override
  Stream<List<Map<String, dynamic>>> collectionStream(
    String collection, {
    bool newestFirst = false,
  }) => _stream(collection).stream;

  @override
  Stream<List<Map<String, dynamic>>> whereStream(
    String collection,
    String field,
    Object value, {
    bool newestFirst = false,
  }) => _stream('$collection.$field=$value').stream;

  @override
  Stream<List<Map<String, dynamic>>> whereInStream(
    String collection,
    String field,
    List<Object> values,
  ) => _stream('$collection.$field in $values').stream;

  @override
  Stream<Map<String, dynamic>?> docStream(String collection, String id) =>
      StreamController<Map<String, dynamic>?>.broadcast().stream;
}

const _wave1 = [
  'users',
  'settings',
  'archives',
  'offices',
  'departments',
  'codes',
  'programs',
  'skills',
  'screening',
  'students',
  'attendance',
  'schedules',
  'forwards',
  'documents',
];

final _supervisor = User(
  id: 'sv1',
  name: 'Sue Supervisor',
  email: 'sue@example.com',
  role: 'Supervisor',
);
final _head = User(
  id: 'head1',
  name: 'Hana Head',
  email: 'hana@example.com',
  role: 'Head',
);
final _assistant = User(
  id: 'sa1',
  name: 'Sam Assistant',
  email: 'sam@example.com',
  role: 'Student Assistant',
);

Task _task(String id, String title) => Task(
  id: id,
  title: title,
  description: '',
  status: 'Not Started',
  priority: 'Medium',
  dueDate: 'Oct 30, 2026',
);

Document _document() => Document(
  id: 'd1',
  name: 'Form',
  fileName: 'form.pdf',
  uploadedBy: 'Hana Head',
  uploadedAt: 'Oct 1, 2026',
  documentType: 'Other',
);

/// Lets everything that can run without a held answer run.
Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppState, _LoadStore)> start() async {
    final store = _LoadStore();
    final state = AppState(firestoreService: store);
    await state.init();
    store.log.clear();
    return (state, store);
  }

  group('Sign-in load', () {
    test('independent reads start together, not one after another', () async {
      final (state, store) = await start();
      store._holds.clear();
      for (final name in _wave1) {
        store.hold(name);
      }

      final signIn = state.login(_supervisor);
      await _settle();

      for (final name in _wave1) {
        expect(
          store.started(name),
          isTrue,
          reason: '$name should have started',
        );
      }
      expect(
        store.log.where((entry) => entry.startsWith('end:')),
        isEmpty,
        reason: 'nothing has been answered yet',
      );
      expect(store.started('tasks'), isFalse);

      store.releaseAll();
      expect(await signIn, isTrue);
    });

    test('tasks, reports and evaluations wait for the earlier steps', () async {
      final (state, store) = await start();
      store.hold('schedules');

      final signIn = state.login(_supervisor);
      await _settle();

      expect(store.started('schedules'), isTrue);
      expect(store.started('tasks'), isFalse);
      expect(store.started('reports'), isFalse);
      expect(store.started('evaluations'), isFalse);

      store.release('schedules');
      await signIn;
      expect(store.at('end:schedules'), lessThan(store.at('start:tasks')));
      expect(store.at('end:schedules'), lessThan(store.at('start:reports')));
      expect(
        store.at('end:schedules'),
        lessThan(store.at('start:evaluations')),
      );
    });

    test('everything is loaded and applied as before', () async {
      final (state, store) = await start();
      store.userProfiles = [_supervisor];
      store.studentRecords = [
        Student(
          id: 'rec1',
          name: 'Sam Assistant',
          email: 'sam@example.com',
          department: 'Computing',
        ),
      ];
      store.tasksOfUser = [_task('t1', 'Sort files')];

      await state.login(_supervisor);

      expect(state.students.map((s) => s.id), ['rec1']);
      expect(state.users.map((u) => u.id), contains('sv1'));
      expect(state.tasks.map((t) => t.id), ['t1']);
      expect(state.departments, ['Computing']);
    });

    test('a read that fails leaves only its own list empty', () async {
      final (state, store) = await start();
      store.studentRecords = [
        Student(
          id: 'rec1',
          name: 'Sam Assistant',
          email: 'sam@example.com',
          department: 'Computing',
        ),
      ];
      store.tasksOfUser = [_task('t1', 'Sort files')];
      store.failing.addAll(['attendance', 'reports', 'codes']);

      await state.login(_supervisor);

      expect(state.attendance, isEmpty);
      expect(state.reports, isEmpty);
      expect(state.students.map((s) => s.id), ['rec1']);
      expect(state.tasks.map((t) => t.id), ['t1']);
      // The departments are taken only when both of their reads answered.
      expect(state.departments, isNot(contains('Computing')));
    });

    test('a student assistant\'s two task lookups run together', () async {
      final (state, store) = await start();
      store.tasksOfUser = [_task('t1', 'Own title'), _task('t2', 'Mine')];
      store.tasksOfAssignee = [_task('t1', 'Assigned title')];
      store.hold('tasksByUser');
      store.hold('studentIds');

      final signIn = state.login(_assistant);
      await _settle();

      expect(store.started('tasksByUser'), isTrue);
      expect(store.started('studentIds'), isTrue);
      expect(store.started('tasksByAssignee'), isFalse);

      store.release('studentIds');
      await _settle();
      expect(store.started('tasksByAssignee'), isTrue);

      store.release('tasksByUser');
      await signIn;
      // The same task found both ways is kept once, as the assignee's copy.
      final byId = {for (final t in state.tasks) t.id: t.title};
      expect(byId, {'t1': 'Assigned title', 't2': 'Mine'});
    });

    test('signing out mid-load leaves none of the answers behind', () async {
      final (state, store) = await start();
      store.studentRecords = [
        Student(
          id: 'rec1',
          name: 'Sam Assistant',
          email: 'sam@example.com',
          department: 'Computing',
        ),
      ];
      store.tasksOfUser = [_task('t1', 'Sort files')];
      store.hold('students');

      final signIn = state.login(_supervisor);
      await _settle();
      state.logout();
      store.release('students');
      await signIn;

      expect(state.students, isEmpty);
      expect(state.tasks, isEmpty);
      expect(store.started('tasks'), isFalse);
    });
  });

  group('Sign-in load: other cases', () {
    test('nobody signed in: no reads are made', () async {
      final store = _LoadStore();
      final state = AppState(firestoreService: store);
      await state.init();
      await _settle();

      expect(store.log, isEmpty);
    });

    test('the Head applications are read after the rehire step', () async {
      final (state, store) = await start();
      store.documentRecords = [_document()];
      store.hold('rehire');

      final signIn = state.login(_head);
      await _settle();

      expect(store.started('rehire'), isTrue);
      expect(store.started('applications'), isFalse);

      store.release('rehire');
      await signIn;
      expect(store.at('end:rehire'), lessThan(store.at('start:applications')));
      expect(state.documents.map((d) => d.id), ['d1']);
    });

    test(
      'a student assistant reads applications with the other records',
      () async {
        final (state, store) = await start();
        store.hold('schedules');

        final signIn = state.login(_assistant);
        await _settle();
        store.release('schedules');
        await signIn;

        expect(store.started('applications'), isTrue);
        expect(store.started('rehire'), isFalse);
        expect(store.started('forwards'), isFalse);
      },
    );

    test('a failed read replaces what an earlier load left', () async {
      final (state, store) = await start();
      store.studentRecords = [
        Student(
          id: 'rec1',
          name: 'Sam Assistant',
          email: 'sam@example.com',
          department: 'Computing',
        ),
      ];
      store.tasksOfUser = [_task('t1', 'Sort files')];
      await state.login(_supervisor);
      expect(state.students, isNotEmpty);
      expect(state.tasks, isNotEmpty);

      store.failing.addAll(['students', 'tasks']);
      await state.login(_supervisor);

      expect(state.students, isEmpty);
      expect(state.tasks, isEmpty);
    });

    test(
      'signing out while the skills are saved keeps the files out',
      () async {
        final (state, store) = await start();
        store.documentRecords = [_document()];
        store.applicationRecords = [
          Application(
            id: 'app1',
            announcementId: 'a1',
            announcementTitle: Application.generalTitle,
            applicantId: 'stu9',
            applicantName: 'Stu Nine',
            appliedAt: 'Oct 1, 2026',
            status: 'Approved',
            skills: const ['Typing'],
          ),
        ];
        store.hold('setSkill');

        final signIn = state.login(_supervisor);
        await _settle();
        expect(store.started('setSkill'), isTrue);

        state.logout();
        store.release('setSkill');
        await signIn;

        expect(state.documents, isEmpty);
        expect(state.applications, isEmpty);
      },
    );
  });

  group('Health check after sign-in', () {
    test(
      'sign-in does not wait for it, and its pings go out together',
      () async {
        final (state, store) = await start();
        store.hold('pingAnnouncements');

        final signedIn = await state.login(_supervisor);
        await _settle();

        expect(signedIn, isTrue);
        expect(store.started('pingAnnouncements'), isTrue);
        expect(store.started('pingReports'), isTrue);
        expect(state.responseTimeMs, 0);

        store.release('pingAnnouncements');
        await _settle();
        expect(state.responseTimeMs, 42);
      },
    );

    test('an answer after the account signed out is dropped', () async {
      final (state, store) = await start();
      store.hold('pingAnnouncements');
      await state.login(_supervisor);
      await _settle();

      state.logout();
      store.release('pingAnnouncements');
      await _settle();

      expect(state.responseTimeMs, 0);
    });
  });
}
