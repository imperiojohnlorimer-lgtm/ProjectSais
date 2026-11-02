import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

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
  List<Map<String, dynamic>> archiveRecords = [];
  List<RehireRecord> rehireDecisions = [];
  final savedRehire = <RehireRecord>[];

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
      _read('archives', archiveRecords);
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
      _read('rehire', rehireDecisions);
  @override
  Future<void> setRehireRecord(RehireRecord record) async {
    await _read('setRehire', null);
    savedRehire.add(record);
  }

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

  // The live listeners answer only when a test says so.
  final _streams = <String, StreamController<List<Map<String, dynamic>>>>{};
  final _docs = <String, StreamController<Map<String, dynamic>?>>{};

  StreamController<Map<String, dynamic>?> docController(String key) =>
      _docs.putIfAbsent(key, StreamController.broadcast);

  /// One live query answers with [data].
  void push(String key, List<Map<String, dynamic>> data) =>
      _stream(key).add(data);

  /// Every live query answers once, with nothing.
  void pushAll() {
    for (final c in _streams.values) {
      c.add(<Map<String, dynamic>>[]);
    }
    for (final c in _docs.values) {
      c.add(null);
    }
  }

  /// Every live query answers once except [failing], which is refused.
  void pushAllExcept(String failing) {
    for (final e in _streams.entries) {
      if (e.key == failing) {
        e.value.addError(Exception('permission-denied'));
      } else {
        e.value.add(<Map<String, dynamic>>[]);
      }
    }
    for (final c in _docs.values) {
      c.add(null);
    }
  }

  StreamController<List<Map<String, dynamic>>> _stream(String key) =>
      _streams.putIfAbsent(key, StreamController.broadcast);

  // The hand-written queries of the service, one stream each.
  @override
  Stream<List<Map<String, dynamic>>> announcementsStream() =>
      _stream('announcements').stream;
  @override
  Stream<List<Map<String, dynamic>>> attendanceStream() =>
      _stream('attendance').stream;
  @override
  Stream<List<Map<String, dynamic>>> attendanceStreamForStudent(String uid) =>
      _stream('attendance.studentId=$uid').stream;
  @override
  Stream<List<Map<String, dynamic>>> tasksStream() => _stream('tasks').stream;
  @override
  Stream<List<Map<String, dynamic>>> applicationsStream() =>
      _stream('applications').stream;
  @override
  Stream<List<Map<String, dynamic>>> applicationsStreamForApplicant(
    String uid,
  ) => _stream('applications.applicantId=$uid').stream;
  @override
  Stream<List<Map<String, dynamic>>> headForwardsStream() =>
      _stream('headForwards').stream;
  @override
  Stream<List<Map<String, dynamic>>> payrollRecordsStream() =>
      _stream('payrollRecords').stream;
  @override
  Stream<List<Map<String, dynamic>>> payrollSheetsStream() =>
      _stream('payrollSheets').stream;

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
      docController('$collection/$id').stream;
}

/// What the Head's start-up jobs work from: the only things its sign-in reads.
const _jobInputs = [
  'users',
  'settings',
  'archives',
  'offices',
  'departments',
  'codes',
  'skills',
  'students',
  'rehire',
];

/// What the Head's live queries deliver: not read again at sign-in.
const _liveOnly = [
  'attendance',
  'schedules',
  'tasks',
  'tasksByUser',
  'reports',
  'evaluations',
  'forwards',
  'documents',
  'programs',
  'screening',
];

Student _student1() => Student(
  id: 'rec1',
  name: 'Sam Assistant',
  email: 'sam@example.com',
  department: 'Computing',
);

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
final _admin = User(
  id: 'ad1',
  name: 'Ada Admin',
  email: 'ada@example.com',
  role: 'Admin',
);
final _student = User(
  id: 'st1',
  name: 'Stu Student',
  email: 'stu@example.com',
  role: 'Student',
);
final _assistant = User(
  id: 'sa1',
  name: 'Sam Assistant',
  email: 'sam@example.com',
  role: 'Student Assistant',
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
    test('the Head reads what its start-up jobs work from, together', () async {
      final (state, store) = await start();
      store._holds.clear();
      for (final name in _jobInputs) {
        store.hold(name);
      }

      final signIn = state.login(_head);
      await _settle();

      for (final name in _jobInputs) {
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

      store.releaseAll();
      expect(await signIn, isTrue);
    });

    test('the Head does not read what its live queries deliver', () async {
      final (state, store) = await start();

      await state.login(_head);

      for (final name in _liveOnly) {
        expect(
          store.started(name),
          isFalse,
          reason: '$name comes from a live query',
        );
      }
    });

    test('the start-up data is applied, the big lists come live', () async {
      final (state, store) = await start();
      store.userProfiles = [_head];
      store.studentRecords = [_student1()];

      await state.login(_head);
      await _settle();

      expect(state.students.map((s) => s.id), ['rec1']);
      expect(state.users.map((u) => u.id), contains('head1'));
      expect(state.departments, ['Computing']);

      store.push('tasks', [
        {'id': 't1', 'title': 'Sort files'},
      ]);
      store.push('documents', [_document().toJson()]);
      await _settle();

      expect(state.tasks.map((t) => t.id), ['t1']);
      expect(state.documents.map((d) => d.id), ['d1']);
    });

    test('a read that fails leaves only its own list empty', () async {
      final (state, store) = await start();
      store.userProfiles = [_head];
      store.studentRecords = [_student1()];
      store.failing.addAll(['students', 'codes']);

      await state.login(_head);

      expect(state.students, isEmpty);
      expect(state.users.map((u) => u.id), contains('head1'));
      // The departments are taken only when both of their reads answered.
      expect(state.departments, isNot(contains('Computing')));
    });

    test('signing out mid-load leaves none of the answers behind', () async {
      final (state, store) = await start();
      store.studentRecords = [_student1()];
      store.hold('students');

      final signIn = state.login(_head);
      await _settle();
      state.logout();
      store.release('students');
      await signIn;

      expect(state.students, isEmpty);
      expect(store.started('applications'), isFalse);
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

    test(
      'the Head applications are read after a due decision is saved',
      () async {
        final (state, store) = await start();
        // Due (an earlier term), and for someone with no account, so putting it
        // into effect only marks it applied.
        store.rehireDecisions = [
          RehireRecord(
            id: 'r1',
            studentId: 'ghost',
            studentName: 'Gone Student',
            academicYear: '2025-2026',
            semester: '1st Semester',
            decision: 'Rehired',
            decidedById: 'head1',
            decidedByName: 'Hana Head',
            decidedAt: 'Oct 1, 2026',
          ),
        ];
        store.hold('setRehire');

        final signIn = state.login(_head);
        await _settle();

        expect(store.started('setRehire'), isTrue);
        expect(store.started('applications'), isFalse);

        store.release('setRehire');
        await signIn;
        expect(
          store.at('end:setRehire'),
          lessThan(store.at('start:applications')),
        );
        expect(store.savedRehire.single.applied, isTrue);
        expect(state.rehireRecords.single.applied, isTrue);
      },
    );

    test(
      'the Head has a live query for every list the load no longer reads',
      () async {
        final (state, store) = await start();

        await state.login(_head);

        expect(
          store._streams.keys,
          containsAll([
            'attendance',
            'tasks',
            'headForwards',
            'reports',
            'evaluations',
            'documents',
            'classSchedules',
            'programs',
            'screeningRecords',
          ]),
        );
      },
    );

    test('a failed read replaces what an earlier load left', () async {
      final (state, store) = await start();
      store.studentRecords = [_student1()];
      await state.login(_head);
      expect(state.students, isNotEmpty);

      store.failing.add('students');
      await state.login(_head);

      expect(state.students, isEmpty);
    });

    test(
      'signing out while the skills are saved keeps the applications out',
      () async {
        final (state, store) = await start();
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

        final signIn = state.login(_head);
        await _settle();
        expect(store.started('setSkill'), isTrue);

        state.logout();
        store.release('setSkill');
        await signIn;

        expect(state.applications, isEmpty);
      },
    );
  });

  group('Sign-in without the duplicate reads', () {
    const bulk = [
      'students',
      'attendance',
      'schedules',
      'tasks',
      'tasksByUser',
      'reports',
      'evaluations',
      'applications',
      'documents',
      'forwards',
      'rehire',
      'offices',
      'programs',
      'skills',
      'departments',
      'codes',
      'screening',
    ];

    for (final user in [_supervisor, _admin, _assistant, _student]) {
      test(
        '${user.role}: only the settings and archives are read first',
        () async {
          final (state, store) = await start();
          store.archiveRecords = [
            {'id': '2025-2026'},
          ];

          await state.login(user);

          expect(store.started('settings'), isTrue);
          expect(store.started('archives'), isTrue);
          for (final name in bulk) {
            expect(
              store.started(name),
              isFalse,
              reason: '$name is a live query',
            );
          }
          // The Admin's year-end notices need the accounts at once.
          expect(store.started('users'), user.role == 'Admin');
          expect(state.currentUser?.role, user.role);
          expect(state.users.map((u) => u.id), contains(user.id));
          expect(state.academicYearArchives, hasLength(1));
        },
      );
    }

    test('a restored session lists the account', () async {
      final store = _LoadStore();
      final state = AppState(firestoreService: store)..currentUser = _assistant;
      await state.init();

      expect(state.users.map((u) => u.id), contains('sa1'));
      expect(state.currentUser?.role, 'Student Assistant');
    });

    test(
      'a student assistant keeps the role while the live queries are slow',
      () async {
        final (state, store) = await start();

        await state.login(_assistant);
        await _settle();

        expect(state.currentUser?.role, 'Student Assistant');
        expect(state.initialDataReady, isFalse);

        store.pushAll();
        await _settle();

        expect(state.initialDataReady, isTrue);
        expect(state.currentUser?.role, 'Student Assistant');
        expect(state.currentUser?.id, 'sa1');
      },
    );

    test(
      'a live query that is refused still opens the page, with the banner',
      () async {
        final (state, store) = await start();
        await state.login(_assistant);
        await _settle();
        expect(state.initialDataReady, isFalse);

        store.pushAllExcept('attendance.studentId=sa1');
        await _settle();

        expect(state.initialDataReady, isTrue);
        expect(state.hasLoadProblem, isTrue);
      },
    );

    test('the page stays open when the queries are started again', () async {
      final (state, store) = await start();
      await state.login(_assistant);
      await _settle();
      store.pushAll();
      await _settle();
      expect(state.initialDataReady, isTrue);

      final retry = state.retryLoading();
      expect(state.initialDataReady, isTrue);
      await _settle();
      store.pushAll();
      await retry;
    });

    test('Try again reads the archive list again', () async {
      final (state, store) = await start();
      store.archiveRecords = [
        {'id': '2025-2026'},
      ];
      store.failing.add('archives');
      await state.login(_assistant);
      expect(state.academicYearArchives, isEmpty);

      store.failing.clear();
      final retry = state.retryLoading();
      await _settle();
      store.pushAll();
      await retry;
      await _settle();

      expect(state.academicYearArchives, hasLength(1));
    });

    test('a role change drops what the new role does not read', () async {
      final (state, store) = await start();
      store.studentRecords = [_student1()];
      store.applicationRecords = [
        Application(
          id: 'app1',
          announcementId: 'a1',
          announcementTitle: Application.generalTitle,
          applicantId: 'stu9',
          applicantName: 'Stu Nine',
          appliedAt: 'Oct 1, 2026',
        ),
      ];
      await state.login(_head);
      expect(state.applications, isNotEmpty);
      expect(state.students, isNotEmpty);

      store
          .docController('users/head1')
          .add(_head.copyWith(role: 'Supervisor').toJson());
      await _settle();

      expect(state.currentUser?.role, 'Supervisor');
      expect(state.applications, isEmpty);
      expect(state.students, isEmpty);
      expect(state.users.map((u) => u.id), contains('head1'));
    });
  });

  testWidgets('the page waits for the first answers', (tester) async {
    final store = _LoadStore();
    final state = AppState(firestoreService: store);
    await tester.runAsync(() async {
      await state.init();
      await state.login(_assistant);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: InitialDataGate(child: Text('the page'))),
        ),
      ),
    );

    expect(find.byType(LoadingState), findsOneWidget);
    expect(find.text('the page'), findsNothing);

    store.pushAll();
    await tester.pump();
    await tester.pump();

    expect(find.text('the page'), findsOneWidget);
    expect(find.byType(LoadingState), findsNothing);
    state.logout();
    state.dispose();
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
