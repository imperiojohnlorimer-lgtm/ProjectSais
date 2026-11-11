import 'dart:async';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// A store whose saves reach the live queries before they return, the way
/// Firestore reports a document as soon as it's written locally. A save
/// function that then adds its own copy shows the record twice.
class _EchoFirestore extends FirestoreService {
  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};
  final _docs = <String, StreamController<Map<String, dynamic>?>>{};

  final reports = <Map<String, dynamic>>[];
  final evaluations = <Map<String, dynamic>>[];
  final students = <Map<String, dynamic>>[];
  final skills = <Map<String, dynamic>>[];
  final departments = <Map<String, dynamic>>[];

  /// Class schedule saves: each waits for [scheduleGate] when it is set.
  Completer<void>? scheduleGate;
  int scheduleSavesRunning = 0;
  int mostScheduleSavesAtOnce = 0;
  bool failScheduleSave = false;
  final scheduleRows = <ClassScheduleEntry>[];

  StreamController<List<Map<String, dynamic>>> list(String key) =>
      _lists.putIfAbsent(key, StreamController.broadcast);

  @override
  Future<List<Map<String, dynamic>>> getNotificationsForUser(String userId) =>
      Future.value(const []);

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
      _docs.putIfAbsent('$collection/$id', StreamController.broadcast).stream;

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => const [];

  Future<void> _acknowledge() => Future<void>.delayed(Duration.zero);

  @override
  Future<void> setReport(Report r) async {
    reports
      ..removeWhere((m) => m['id'] == r.id)
      ..add({
        'id': r.id,
        'applicantId': r.applicantId,
        'title': r.title,
        'content': r.content,
        'studentName': r.studentName,
        'status': r.status,
        'submittedAt': r.submittedAt,
      });
    list('reports.applicantId=${r.applicantId}').add([...reports]);
    await _acknowledge();
  }

  @override
  Future<void> setEvaluation(Evaluation e) async {
    // Firestore names a document saved without an id.
    final id = e.id.isEmpty ? 'auto_${evaluations.length + 1}' : e.id;
    evaluations
      ..removeWhere((m) => m['id'] == id)
      ..add({...e.toJson(), 'id': id});
    list('evaluations').add([...evaluations]);
    await _acknowledge();
  }

  @override
  Future<void> updateUserFieldsWithStudent(
    String id,
    Map<String, dynamic> fields,
    Student student,
  ) async {
    students.add({
      'id': student.id,
      'name': student.name,
      'email': student.email,
      'department': student.department,
      'userId': student.userId,
      'status': student.status,
    });
    list('students').add([...students]);
    await _acknowledge();
  }

  @override
  Future<void> setSkill(String name) async {
    skills.add({'id': name, 'name': name});
    list('skills').add([...skills]);
    await _acknowledge();
  }

  @override
  Future<void> setDepartment(String name, {String code = ''}) async {
    departments
      ..removeWhere((m) => m['name'] == name)
      ..add({'id': name, 'name': name, 'code': code});
    list('departments').add([...departments]);
    await _acknowledge();
  }

  @override
  Future<void> updateDepartment(String oldName, String newName) async {
    final at = departments.indexWhere((m) => m['name'] == oldName);
    if (at >= 0) departments[at] = {'id': newName, 'name': newName};
    list('departments').add([...departments]);
    await _acknowledge();
  }

  @override
  Future<List<ClassScheduleEntry>> replaceClassSchedule(
    String studentId,
    String studentName,
    List<ClassScheduleEntry> rows,
  ) async {
    scheduleSavesRunning++;
    if (scheduleSavesRunning > mostScheduleSavesAtOnce) {
      mostScheduleSavesAtOnce = scheduleSavesRunning;
    }
    try {
      await (scheduleGate?.future ?? _acknowledge());
      if (failScheduleSave) throw StateError('offline');
      final saved = [
        for (var i = 0; i < rows.length; i++)
          ClassScheduleEntry.fromJson({
            ...rows[i].toJson(),
            'id': 'saved_${scheduleRows.length + i}',
          }),
      ];
      scheduleRows
        ..removeWhere(
          (c) => FirestoreService.isClassScheduleOf(
            rowStudentId: c.studentId,
            rowStudentName: c.studentName,
            studentId: studentId,
            studentName: studentName,
          ),
        )
        ..addAll(saved);
      return saved;
    } finally {
      scheduleSavesRunning--;
    }
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

User _user(String id, String name, String role) =>
    User(id: id, name: name, email: '$id@example.com', role: role);

Evaluation _evaluation({String id = '', String status = 'Draft'}) => Evaluation(
  id: id,
  studentId: 'sa1',
  studentName: 'Sam Assistant',
  office: 'Library',
  term: 'First Semester',
  periodCovered: 'Aug to Dec 2026',
  dateOfRating: '11/11/2026',
  eligibleForRehire: true,
  ratings: const {},
  overallRating: 4,
  departmentHeadComments: '',
  supervisorId: 'sv1',
  supervisorName: 'Sue Supervisor',
  status: status,
);

ClassScheduleEntry _row(String course, {String studentId = 'sa1'}) =>
    ClassScheduleEntry(
      id: 'cs_$course',
      studentId: studentId,
      studentName: 'Sam Assistant',
      course: course,
    );

void main() {
  late _EchoFirestore fake;
  late AppState state;

  Future<void> signIn(User user) async {
    state = AppState(firestoreService: fake)..currentUser = user;
    await state.init();
    await _settle();
  }

  setUp(() => fake = _EchoFirestore());
  tearDown(() => state.dispose());

  test('a submitted report is listed once', () async {
    await signIn(_user('sa1', 'Sam Assistant', 'Student Assistant'));

    final saved = await state.submitReport(
      Report(
        id: 'r_1',
        applicantId: 'sa1',
        title: 'Week 1',
        content: 'Filed the returned books.',
        studentName: 'Sam Assistant',
        status: 'Pending',
        submittedAt: '11/11/2026',
      ),
    );
    await _settle();

    expect(saved, isTrue);
    expect(state.reports.where((r) => r.id == 'r_1'), hasLength(1));
    expect(state.filteredReports, hasLength(1));
  });

  test('an approved applicant is on the roster once', () async {
    await signIn(_user('head1', 'Hana Head', 'Head'));
    fake.list('users').add([
      {'id': 'head1', 'name': 'Hana Head', 'email': 'h@x.com', 'role': 'Head'},
      {'id': 'st1', 'name': 'Stu Dent', 'email': 'st@x.com', 'role': 'Student'},
    ]);
    fake.list('students').add(const []);
    await _settle();

    expect(await state.changeUserRole('st1', 'Student Assistant'), isNull);
    await _settle();

    expect(state.students.where((s) => s.id == 'st1'), hasLength(1));
    expect(
      state.effectiveStudents.where((s) => (s.userId ?? s.id) == 'st1'),
      hasLength(1),
    );
  });

  test('a new evaluation is one record, also after saving it again', () async {
    await signIn(_user('sv1', 'Sue Supervisor', 'Supervisor'));

    expect(await state.saveEvaluation(_evaluation()), isTrue);
    await _settle();

    expect(state.evaluations, hasLength(1));
    final kept = state.evaluations.single;
    expect(kept.id, isNotEmpty);

    // Reopened from the list and submitted: the same record, not a second.
    expect(
      await state.saveEvaluation(kept.copyWith(status: 'Submitted')),
      isTrue,
    );
    await _settle();

    expect(fake.evaluations, hasLength(1));
    expect(state.evaluations, hasLength(1));
    expect(state.evaluations.single.status, 'Submitted');
  });

  test('an evaluation that was never saved is not sent to the Head', () async {
    await signIn(_user('sv1', 'Sue Supervisor', 'Supervisor'));

    expect(
      await state.sendEvaluationToHead(_evaluation(status: 'Submitted')),
      isFalse,
    );
    expect(fake.evaluations, isEmpty);
  });

  test('a new skill is listed once', () async {
    await signIn(_user('head1', 'Hana Head', 'Head'));

    expect(await state.addSkill('Typing'), isTrue);
    await _settle();

    expect(state.skills.where((s) => s == 'Typing'), hasLength(1));
  });

  group('departments', () {
    test('a new one is listed once', () async {
      await signIn(_user('admin1', 'Ada Admin', 'Admin'));

      expect(await state.addDepartment('CICS', code: 'CICS'), isTrue);
      await _settle();

      expect(state.departments.where((d) => d == 'CICS'), hasLength(1));
    });

    test('a name that differs only in capitals is refused', () async {
      await signIn(_user('admin1', 'Ada Admin', 'Admin'));
      await state.addDepartment('CICS');
      await state.addDepartment('College of Arts');
      await _settle();

      expect(state.findDepartment(' cics '), 'CICS');
      expect(await state.addDepartment('cics'), isFalse);
      expect(await state.updateDepartment('College of Arts', 'CICS'), isFalse);
      expect(fake.departments.map((d) => d['name']), [
        'CICS',
        'College of Arts',
      ]);
    });

    test('its own name may change capitals', () async {
      await signIn(_user('admin1', 'Ada Admin', 'Admin'));
      await state.addDepartment('Cics');
      await _settle();

      expect(await state.updateDepartment('Cics', 'CICS'), isTrue);
      await _settle();

      expect(state.departments, ['CICS']);
    });
  });

  group('class schedule', () {
    test('two saves for one student run one after the other', () async {
      await signIn(_user('sv1', 'Sue Supervisor', 'Supervisor'));
      fake.scheduleGate = Completer<void>();

      final first = state.saveClassScheduleForStudent('sa1', 'Sam Assistant', [
        _row('Math 101'),
      ]);
      final second = state.saveClassScheduleForStudent('sa1', 'Sam Assistant', [
        _row('Math 101'),
      ]);
      await _settle();
      expect(fake.scheduleSavesRunning, 1);

      fake.scheduleGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);

      expect(fake.mostScheduleSavesAtOnce, 1);
      expect(fake.scheduleRows, hasLength(1));
      expect(
        state.classSchedules.where((c) => c.studentId == 'sa1'),
        hasLength(1),
      );
    });

    test('a failed save says so and keeps the rows for this session', () async {
      await signIn(_user('sv1', 'Sue Supervisor', 'Supervisor'));
      fake.failScheduleSave = true;

      final saved = await state.saveClassScheduleForStudent(
        'sa1',
        'Sam Assistant',
        [_row('Math 101')],
      );

      expect(saved, isFalse);
      expect(state.classSchedules.map((c) => c.course), ['Math 101']);
    });

    test('a namesake keeps their own rows', () async {
      await signIn(_user('head1', 'Hana Head', 'Head'));
      await state.saveClassScheduleForStudent('sa2', 'Sam Assistant', [
        _row('History 2', studentId: 'sa2'),
      ]);
      await state.saveClassScheduleForStudent('sa1', 'Sam Assistant', [
        _row('Math 101'),
      ]);

      expect(
        state
            .classScheduleForStudent('Sam Assistant', studentId: 'sa1')
            .map((c) => c.course),
        ['Math 101'],
      );
      expect(
        state
            .classScheduleForStudent('Sam Assistant', studentId: 'sa2')
            .map((c) => c.course),
        ['History 2'],
      );
      expect(fake.scheduleRows, hasLength(2));
    });
  });
}
