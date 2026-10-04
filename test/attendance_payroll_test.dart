import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Stands in for Firestore: records what the app saves, and can be told to
/// refuse a save the way the rules or a dropped connection would.
class _FakeFirestore extends FirestoreService {
  final added = <Map<String, dynamic>>[];
  final attendanceUpdates = <String, Map<String, dynamic>>{};
  final profiles = <String, User>{};
  final deletedStudents = <String>[];
  bool failWrites = false;

  /// What meta/current_qr holds.
  Map<String, dynamic>? qrDoc;
  bool failQr = false;

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
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      added.add(payload);

  @override
  Future<void> setTask(Task t) async {
    if (failWrites) throw Exception('permission-denied');
  }

  @override
  Future<void> updateAttendance(String id, Map<String, dynamic> data) async {
    if (failWrites) throw Exception('permission-denied');
    attendanceUpdates[id] = data;
  }

  @override
  Future<void> setUserProfile(User user) async => profiles[user.id] = user;

  /// payrollRecords, by document id.
  final payroll = <String, Map<String, dynamic>>{};

  @override
  Future<bool> createPayrollRecord(PayrollRecord record) async {
    if (payroll.containsKey(record.id)) return false;
    payroll[record.id] = record.toJson();
    return true;
  }

  @override
  Future<void> updatePayrollRecord(
    String id,
    Map<String, dynamic> data,
  ) async => payroll[id] = {...?payroll[id], ...data};

  @override
  Future<void> deleteStudent(String id) async => deletedStudents.add(id);

  @override
  Future<Map<String, dynamic>> claimSessionQrToken(
    String candidate,
    String sessionKey, {
    required String? Function(Map<String, dynamic> doc) sessionOf,
  }) async {
    if (failQr) throw Exception('unavailable');
    final saved = qrDoc;
    if (saved != null && sessionOf(saved) == sessionKey) return saved;
    return qrDoc = {'token': candidate, 'sessionKey': sessionKey};
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

AttendanceRecord _record(
  String id, {
  String? studentId,
  required String studentName,
  String date = 'Sep 10, 2026',
  String timeIn = '8:00 AM',
  String? timeOut = '12:00 PM',
  double? totalHours = 4,
  bool isInvalid = false,
}) => AttendanceRecord(
  id: id,
  studentId: studentId,
  studentName: studentName,
  date: date,
  timeIn: timeIn,
  timeOut: timeOut,
  totalHours: totalHours,
  isInvalid: isInvalid,
);

User _assistant(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  role: 'Student Assistant',
);

void main() {
  late _FakeFirestore fake;
  late AppState state;

  setUp(() {
    fake = _FakeFirestore();
    state = AppState(firestoreService: fake);
  });

  group('payroll', () {
    Map<String, double> hoursPaid() => {
      for (final p in state.buildPayrollPreview(
        start: DateTime(2026, 9, 1),
        endInclusive: DateTime(2026, 9, 30),
        periodLabel: 'September 2026',
      ))
        p.studentId: p.hoursWorked,
    };

    test('never pays a record flagged as a missed time-out', () {
      state
        ..users = [_assistant('sa1', 'Ana Reyes')]
        ..attendance = [
          _record('r1', studentId: 'sa1', studentName: 'Ana Reyes'),
          // Closed at 5 PM after a missed morning time-out: 9 hours on
          // paper, none of them verified.
          _record(
            'r2',
            studentId: 'sa1',
            studentName: 'Ana Reyes',
            date: 'Sep 11, 2026',
            timeIn: '8:00 AM',
            timeOut: '5:00 PM',
            totalHours: 9,
            isInvalid: true,
          ),
        ];

      expect(hoursPaid()['sa1'], 4);
    });

    test("doesn't pay one student for a namesake's hours", () {
      state
        ..users = [
          _assistant('sa1', 'Juan Dela Cruz'),
          _assistant('sa2', 'Juan Dela Cruz'),
        ]
        ..attendance = [
          _record('r1', studentId: 'sa1', studentName: 'Juan Dela Cruz'),
          _record(
            'r2',
            studentId: 'sa2',
            studentName: 'Juan Dela Cruz',
            totalHours: 3,
          ),
        ];

      expect(hoursPaid(), {'sa1': 4, 'sa2': 3});
    });

    test("an approved report only verifies its own author's pay", () {
      state
        ..users = [
          _assistant('sa1', 'Juan Dela Cruz'),
          _assistant('sa2', 'Juan Dela Cruz'),
        ]
        ..reports = [
          Report(
            id: 'rep1',
            applicantId: 'sa1',
            title: 'September',
            content: '',
            studentName: 'Juan Dela Cruz',
            status: 'Approved',
            submittedAt: '9/20/2026',
          ),
        ];

      final preview = state.buildPayrollPreview(
        start: DateTime(2026, 9, 1),
        endInclusive: DateTime(2026, 9, 30),
        periodLabel: 'September 2026',
      );

      expect(
        {for (final p in preview) p.studentId: p.reportVerified},
        {'sa1': true, 'sa2': false},
      );
    });

    test('still counts older records saved with only a name', () {
      state
        ..users = [_assistant('sa3', 'Maria Legacy')]
        ..attendance = [
          _record('r1', studentName: 'maria legacy ', totalHours: 2),
        ];

      expect(hoursPaid()['sa3'], 2);
    });

    test('lists an assistant with no office as unassigned', () {
      const department = 'College of Information and Computing Sciences';
      state
        ..users = [
          User(
            id: 'sa1',
            name: 'Ana Reyes',
            email: 'sa1@example.com',
            role: 'Student Assistant',
            department: department,
          ),
          User(
            id: 'sa2',
            name: 'Ben Cruz',
            email: 'sa2@example.com',
            role: 'Student Assistant',
            department: department,
          ),
        ]
        ..offices = [
          const Office(
            id: 'o1',
            name: 'CICS Office',
            code: 'CICS',
            assistantIds: ['sa2'],
            assistantNames: ['Ben Cruz'],
          ),
        ];

      final preview = state.buildPayrollPreview(
        start: DateTime(2026, 9, 1),
        endInclusive: DateTime(2026, 9, 30),
        periodLabel: 'September 2026',
      );

      // Not under an "office" named after the department.
      expect(
        {for (final p in preview) p.studentId: p.office},
        {'sa1': '', 'sa2': 'CICS Office'},
      );
    });

    test('pays someone no longer an assistant for hours they worked', () {
      state
        ..users = [
          // Not rehired before payroll ran: back to Student.
          User(
            id: 'sa1',
            name: 'Ana Reyes',
            email: 'sa1@example.com',
            role: 'Student',
          ),
          User(
            id: 'st2',
            name: 'Ben Cruz',
            email: 'st2@example.com',
            role: 'Student',
          ),
        ]
        ..attendance = [
          _record('r1', studentId: 'sa1', studentName: 'Ana Reyes'),
        ];

      // A student who never worked isn't listed.
      expect(hoursPaid(), {'sa1': 4});
    });

    test('pays hours archived with their year, not ones archived by hand', () {
      AttendanceRecord archived(String id, {String? withYear}) =>
          AttendanceRecord(
            id: id,
            studentId: 'sa1',
            studentName: 'Ana Reyes',
            date: 'Sep 10, 2026',
            timeIn: '8:00 AM',
            timeOut: '12:00 PM',
            totalHours: 4,
            isArchived: true,
            archivedAcademicYear: withYear,
          );
      state
        ..users = [_assistant('sa1', 'Ana Reyes')]
        ..attendance = [archived('r1', withYear: '2026-2027'), archived('r2')];

      expect(hoursPaid()['sa1'], 4);
    });

    test('a report handed in shortly after the period still counts', () {
      bool verifiedWhenSubmitted(String submittedAt) {
        state
          ..users = [_assistant('sa1', 'Ana Reyes')]
          ..reports = [
            Report(
              id: 'rep1',
              applicantId: 'sa1',
              title: '1st Semester report',
              content: '',
              studentName: 'Ana Reyes',
              status: 'Approved',
              submittedAt: submittedAt,
            ),
          ];
        return state
            .buildPayrollPreview(
              start: DateTime(2026, 9, 1),
              endInclusive: DateTime(2026, 9, 30),
              periodLabel: 'September 2026',
            )
            .single
            .reportVerified;
      }

      expect(verifiedWhenSubmitted('10/30/2026'), isTrue);
      expect(verifiedWhenSubmitted('10/31/2026'), isFalse);
    });

    group('approving and releasing', () {
      PayrollRecord approved(
        String studentId, {
        String start = '2026-09-01',
        String end = '2026-09-30',
      }) => PayrollRecord(
        id: PayrollRecord.idFor(studentId, start, end),
        studentId: studentId,
        studentName: studentId,
        office: '',
        periodStart: start,
        periodEnd: end,
        periodLabel: 'September 2026',
        dtrVerified: true,
        reportVerified: true,
        status: 'Approved',
      );

      setUp(() {
        state
          ..users = [_assistant('sa1', 'Ana Reyes')]
          ..attendance = [
            _record('r1', studentId: 'sa1', studentName: 'Ana Reyes'),
            _record(
              'r2',
              studentId: 'sa1',
              studentName: 'Ana Reyes',
              date: 'Sep 20, 2026',
            ),
          ]
          ..reports = [
            Report(
              id: 'rep1',
              applicantId: 'sa1',
              title: 'September',
              content: '',
              studentName: 'Ana Reyes',
              status: 'Approved',
              submittedAt: '9/20/2026',
            ),
          ];
      });

      List<PayrollRecord> preview({DateTime? start, DateTime? end}) =>
          state.buildPayrollPreview(
            start: start ?? DateTime(2026, 9, 1),
            endInclusive: end ?? DateTime(2026, 9, 30),
            periodLabel: 'September 2026',
          );

      test('days already paid under another period are held back', () {
        state.payrollRecords = [approved('sa1', end: '2026-09-15')];

        final row = preview().single;

        expect(row.status, 'Incomplete');
        expect(row.overlappingPayroll?.periodEnd, '2026-09-15');
        // A period that doesn't share days is fine.
        expect(
          preview(
            start: DateTime(2026, 9, 16),
            end: DateTime(2026, 9, 30),
          ).single.status,
          'Ready',
        );
      });

      test('approving a period twice saves it once', () async {
        final rows = preview();

        expect((await state.approvePayroll(rows)).$1, 1);
        // As if another session approved it first, before this one's
        // records caught up.
        state.payrollRecords = [];
        expect((await state.approvePayroll(rows)).$1, 0);
        expect(fake.payroll.keys, [
          PayrollRecord.idFor('sa1', '2026-09-01', '2026-09-30'),
        ]);
      });

      test('release pays only the records it is given', () async {
        final one = approved('sa1');
        final other = approved('sa2');
        state.payrollRecords = [one, other];

        final (count, _) = await state.releasePayroll([one]);

        expect(count, 1);
        expect(fake.payroll.keys, [one.id]);
        expect(fake.payroll[one.id]?['status'], 'Released');
        expect(
          state.payrollRecords.firstWhere((p) => p.id == other.id).status,
          'Approved',
        );
        expect(fake.added.map((n) => n['userId']), ['sa1']);
      });
    });
  });

  group('verified DTR hours', () {
    final student = Student(
      id: 'roster1',
      name: 'Juan Dela Cruz',
      email: 'sa1@example.com',
      department: 'CICS',
      userId: 'sa1',
    );

    test('counts only the student\'s own verified records', () {
      state
        ..currentUser = User(
          id: 'h1',
          name: 'Helen Head',
          email: 'h@example.com',
          role: 'Head',
        )
        ..attendance = [
          _record('r1', studentId: 'sa1', studentName: 'Juan Dela Cruz'),
          _record(
            'r2',
            studentId: 'sa2',
            studentName: 'Juan Dela Cruz',
            totalHours: 3,
          ),
          _record(
            'r3',
            studentId: 'sa1',
            studentName: 'Juan Dela Cruz',
            totalHours: 5,
            isInvalid: true,
          ),
        ];

      expect(state.verifiedDtrHoursForStudent(student), 4);
    });
  });

  group('offices', () {
    const office = Office(
      id: 'o1',
      name: 'Library',
      code: 'LIB',
      assistantIds: ['sa2', ''],
      assistantNames: ['Juan Dela Cruz', 'Old Entry'],
    );

    test('membership goes by id, not a shared name', () {
      expect(office.hasAssistant('sa2', 'Juan Dela Cruz'), isTrue);
      expect(office.hasAssistant('sa1', 'Juan Dela Cruz'), isFalse);
      // A position saved without an id still matches by name.
      expect(office.hasAssistant('sa9', 'old entry'), isTrue);
    });

    test("removing a student leaves their namesake's place alone", () {
      final updated = office.withoutAssistant('sa1', 'Juan Dela Cruz');
      expect(updated.assistantIds, ['sa2', '']);

      final removed = office.withoutAssistant('sa2', 'Juan Dela Cruz');
      expect(removed.assistantIds, ['']);
      expect(removed.assistantNames, ['Old Entry']);
    });

    test("a student isn't placed in a namesake's office", () {
      state.offices = [office];
      expect(
        state.officesForUser(_assistant('sa1', 'Juan Dela Cruz')),
        isEmpty,
      );
      expect(state.officesForUser(_assistant('sa2', 'Juan Dela Cruz')), [
        office,
      ]);
    });
  });

  group('attendance QR', () {
    final morning = DateTime(2026, 9, 28, 9, 0);

    test('reuses the code already saved for the session', () async {
      fake.qrDoc = {'token': 'POSTED', 'sessionKey': '20260928-AM'};

      expect(await state.generateAttendanceQrToken(morning), 'POSTED');
    });

    test('saves a new code for a new session', () async {
      fake.qrDoc = {'token': 'YESTERDAY', 'sessionKey': '20260927-PM'};

      final token = await state.generateAttendanceQrToken(morning);

      expect(token, startsWith('SAIS-ATT-20260928-AM-'));
      expect(fake.qrDoc?['token'], token);
    });

    test("never shows a code it couldn't save", () async {
      fake.failQr = true;

      await expectLater(
        state.generateAttendanceQrToken(morning),
        throwsException,
      );
      expect(state.currentQrToken, isNull);
    });
  });

  group('deleting an account', () {
    final admin = User(
      id: 'a1',
      name: 'Ana Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );
    final doomed = _assistant('sa1', 'Juan Dela Cruz');

    test('keeps the profile, archived and marked deleted', () async {
      state
        ..currentUser = admin
        ..users = [admin, doomed];

      await state.deleteManagedUser('sa1');

      final saved = fake.profiles['sa1']!;
      expect(saved.status, 'Archived');
      expect(saved.isDeleted, isTrue);
      expect(state.users.map((u) => u.id), ['a1']);
    });

    test('stays hidden when the roster reloads', () async {
      state.currentUser = admin;
      await state.init();

      fake.list('users').add([
        admin.toJson(),
        doomed.copyWith(status: 'Archived', isDeleted: true).toJson(),
      ]);
      await _settle();

      expect(state.users.map((u) => u.id), ['a1']);
    });

    test('the deleted mark survives a save and reload', () {
      final json = doomed.copyWith(isDeleted: true).toJson();
      expect(json['deleted'], isTrue);
      expect(User.fromJson(json).isDeleted, isTrue);
      // Untouched profiles don't gain the field.
      expect(doomed.toJson().containsKey('deleted'), isFalse);
    });
  });

  group('saves that fail', () {
    test('a task status the server refuses is undone', () async {
      fake.failWrites = true;
      state
        ..currentUser = _assistant('sa1', 'Juan Dela Cruz')
        ..tasks = [
          Task(
            id: 't1',
            title: 'File the forms',
            description: '',
            status: 'Not Started',
            priority: 'Medium',
            dueDate: 'Oct 1, 2026',
            assignedTo: 'sa1',
            assignedBy: 'sup1',
          ),
        ];

      final saved = await state.updateTaskStatus('t1', 'Completed');

      expect(saved, isFalse);
      expect(state.tasks.single.status, 'Not Started');
      expect(fake.added, isEmpty);
    });

    test('a manual time-out the server refuses is undone', () async {
      fake.failWrites = true;
      state.attendance = [
        _record(
          'r1',
          studentId: 'sa1',
          studentName: 'Juan Dela Cruz',
          timeOut: null,
          totalHours: null,
          isInvalid: true,
        ),
      ];

      final saved = await state.setManualTimeOut('r1', '11:30 AM');

      expect(saved, isFalse);
      expect(state.attendance.single.timeOut, isNull);
      expect(state.attendance.single.isInvalid, isTrue);
    });

    test('a manual time-out that saves is kept', () async {
      state.attendance = [
        _record(
          'r1',
          studentId: 'sa1',
          studentName: 'Juan Dela Cruz',
          timeOut: null,
          totalHours: null,
          isInvalid: true,
        ),
      ];

      final saved = await state.setManualTimeOut('r1', '11:30 AM');

      expect(saved, isTrue);
      expect(state.attendance.single.totalHours, 3.5);
      expect(fake.attendanceUpdates['r1']?['isInvalid'], isFalse);
    });
  });
}
