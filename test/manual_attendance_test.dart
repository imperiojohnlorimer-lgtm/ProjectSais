import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

import 'support/account_writes.dart';

class _Store extends FirestoreService with AccountWrites {
  final savedAttendance = <String, Map<String, dynamic>>{};
  final notes = <Map<String, dynamic>>[];
  final attendanceUpdates = <String, Map<String, dynamic>>{};
  String? failAttendanceWith;

  @override
  Future<DocumentReference> addAttendance(
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final why = failAttendanceWith;
    if (why != null) throw Exception(why);
    savedAttendance[id!] = data;
    return FakeRef();
  }

  @override
  Future<void> updateAttendance(String id, Map<String, dynamic> data) async =>
      attendanceUpdates[id] = data;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notes.add(payload);

  @override
  Future<Map<String, String>> getOfficeAssignments() async =>
      Map.of(assignmentDocs);

  @override
  Future<void> writeOfficeAssignments(Map<String, String?> changes) async {
    for (final entry in changes.entries) {
      if (entry.value == null) {
        assignmentDocs.remove(entry.key);
      } else {
        assignmentDocs[entry.key] = entry.value!;
      }
    }
  }
}

// addAttendance's return value isn't used; any object of the type will do.
// ignore: subtype_of_sealed_class
class FakeRef implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@example.com',
  role: 'Head',
);
final _sid = User(
  id: 'sid',
  name: 'Sid Supervisor',
  email: 'sid@example.com',
  role: 'Supervisor',
);
final _ana = User(
  id: 'ana',
  name: 'Ana Reyes',
  email: 'ana@example.com',
  role: 'Student Assistant',
);
final _ben = User(
  id: 'ben',
  name: 'Ben Cruz',
  email: 'ben@example.com',
  role: 'Student Assistant',
);

const _library = Office(
  id: 'lib',
  name: 'Library',
  code: 'LIB',
  headIds: ['sid'],
  headNames: ['Sid Supervisor'],
  assistantIds: ['ana'],
  assistantNames: ['Ana Reyes'],
);
const _clinic = Office(
  id: 'cln',
  name: 'Clinic',
  code: 'CLN',
  headIds: ['someone'],
  headNames: ['Someone Else'],
  assistantIds: ['ben'],
  assistantNames: ['Ben Cruz'],
);

// Friday Nov 27, 2026, 2:00 PM in the Philippines.
final _now = DateTime.utc(2026, 11, 27, 6, 0);
final _today = DateTime(2026, 11, 27);

AttendanceRecord _record(
  String id, {
  String studentId = 'ana',
  String date = 'Nov 27, 2026',
  String timeIn = '8:00 AM',
  String? timeOut = '9:00 AM',
  double hours = 1,
  bool archived = false,
}) => AttendanceRecord(
  id: id,
  studentName: 'Ana Reyes',
  studentId: studentId,
  date: date,
  timeIn: timeIn,
  timeOut: timeOut,
  totalHours: timeOut == null ? null : hours,
  isArchived: archived,
);

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store();
    state = AppState(firestoreService: store)
      ..currentUser = _sid
      ..users = [_head, _sid, _ana, _ben]
      ..offices = [_library, _clinic];
  });

  group('who staff may record attendance for', () {
    test('a Supervisor gets the student assistants of their offices', () {
      expect(state.manualAttendanceAssistants.map((u) => u.id), ['ana']);
    });

    test('the Head gets every active student assistant', () {
      state.currentUser = _head;
      state.users = [
        ...state.users,
        User(
          id: 'old',
          name: 'Olga Old',
          email: 'olga@example.com',
          role: 'Student Assistant',
          status: 'Archived',
        ),
      ];
      expect(state.manualAttendanceAssistants.map((u) => u.id), [
        'ana',
        'ben',
      ]);
    });

    test('nobody else records attendance', () {
      state.currentUser = _ana;
      expect(state.manualAttendanceAssistants, isEmpty);
    });
  });

  group('which days', () {
    test('today and the 7 days before it, newest first', () {
      final days = state.manualAttendanceDayChoices(now: _now);
      expect(days.length, 8);
      expect(days.first, _today);
      expect(days.last, DateTime(2026, 11, 20));
    });

    test('none before the academic year started', () {
      state.academicYearStart = DateTime(2026, 11, 25);
      expect(
        state.manualAttendanceDayChoices(now: _now),
        [DateTime(2026, 11, 27), DateTime(2026, 11, 26), DateTime(2026, 11, 25)],
      );
    });
  });

  group('what can be recorded', () {
    String? problem({
      DateTime? day,
      String timeIn = '8:00 AM',
      String timeOut = '11:00 AM',
    }) => state.manualAttendanceProblem(
      assistant: _ana,
      day: day ?? _today,
      timeIn: timeIn,
      timeOut: timeOut,
      now: _now,
    );

    test('a finished morning today is fine', () {
      expect(problem(), isNull);
    });

    test('not a day ahead, nor more than 7 days back', () {
      expect(problem(day: DateTime(2026, 11, 28)), contains('ahead'));
      expect(problem(day: DateTime(2026, 11, 19)), contains('last 7 days'));
      expect(problem(day: DateTime(2026, 11, 20)), isNull);
    });

    test('only inside the sessions, one session at a time', () {
      expect(problem(timeIn: '12:10 PM', timeOut: '12:20 PM'), contains('7:30'));
      expect(
        problem(timeIn: '8:00 AM', timeOut: '1:00 PM'),
        contains('same session'),
      );
      expect(problem(timeIn: '10:00 AM', timeOut: '9:00 AM'), contains('after'));
    });

    test("today's time-out can't be later than now", () {
      expect(
        problem(timeIn: '1:00 PM', timeOut: '3:00 PM'),
        contains('later than now'),
      );
      expect(problem(timeIn: '1:00 PM', timeOut: '2:00 PM'), isNull);
    });

    test('never overlapping another record that day', () {
      state.attendance = [_record('a1')];
      expect(
        problem(timeIn: '8:30 AM', timeOut: '10:00 AM'),
        contains('overlaps their record from 8:00 AM to 9:00 AM'),
      );
      // A later stretch of the same session is fine.
      expect(problem(timeIn: '9:00 AM', timeOut: '11:00 AM'), isNull);
      // An archived record doesn't count.
      state.attendance = [_record('a1', archived: true)];
      expect(problem(timeIn: '8:30 AM', timeOut: '10:00 AM'), isNull);
    });

    test('a record still open points to Record time-out', () {
      state.attendance = [_record('a1', timeIn: '9:00 AM', timeOut: null)];
      expect(
        problem(timeIn: '10:00 AM', timeOut: '11:00 AM'),
        contains('Use Record time-out'),
      );
      // Before its time-in is fine.
      expect(problem(timeIn: '7:30 AM', timeOut: '8:30 AM'), isNull);
    });
  });

  group('recording it', () {
    test('saves the record, shows it, and tells the student', () async {
      final result = await state.recordManualAttendance(
        assistant: _ana,
        day: DateTime(2026, 11, 26),
        timeIn: '8:00 AM',
        timeOut: '11:00 AM',
        now: _now,
      );

      expect(result, isNull);
      final id = store.savedAttendance.keys.single;
      expect(id, startsWith('ana_20261126_manual_'));
      final data = store.savedAttendance[id]!;
      expect(data['date'], 'Nov 26, 2026');
      expect(data['timeIn'], '8:00 AM');
      expect(data['timeOut'], '11:00 AM');
      expect(data['totalHours'], 3.0);
      expect(data['officeId'], 'lib');
      expect(data['editNote'], 'Attendance recorded by hand');
      expect(data['editedBy'], 'Sid Supervisor');
      expect(data['isInvalid'], false);
      expect(data.containsKey('hoursBeforeWeeklyCap'), isFalse);
      expect(state.attendance.single.id, id);
      expect(state.attendance.single.officeId, 'lib');
      expect(store.notes.single['userId'], 'ana');
    });

    test('the weekly hours limit applies', () async {
      state.attendance = [
        for (final (i, date) in ['Nov 23, 2026', 'Nov 24, 2026', 'Nov 25, 2026']
            .indexed)
          _record('w$i', date: date, timeOut: '12:00 PM', hours: 6),
        _record('w4', date: 'Nov 26, 2026', timeOut: '9:00 AM', hours: 1),
      ];

      await state.recordManualAttendance(
        assistant: _ana,
        day: _today,
        timeIn: '8:00 AM',
        timeOut: '11:00 AM',
        now: _now,
      );

      final data = store.savedAttendance.values.single;
      expect(data['totalHours'], 1.0);
      expect(data['hoursBeforeWeeklyCap'], 3.0);
    });

    test('a refused save is taken back and explained', () async {
      store.failAttendanceWith = 'permission-denied';
      final result = await state.recordManualAttendance(
        assistant: _ana,
        day: _today,
        timeIn: '8:00 AM',
        timeOut: '11:00 AM',
        now: _now,
      );

      expect(result, contains('may not record attendance'));
      expect(state.attendance, isEmpty);
      expect(store.notes, isEmpty);
    });

    test('a failed connection is taken back too', () async {
      store.failAttendanceWith = 'unavailable';
      final result = await state.recordManualAttendance(
        assistant: _ana,
        day: _today,
        timeIn: '8:00 AM',
        timeOut: '11:00 AM',
        now: _now,
      );

      expect(result, contains('Check your connection'));
      expect(state.attendance, isEmpty);
    });

    test('a problem saves nothing', () async {
      final result = await state.recordManualAttendance(
        assistant: _ana,
        day: _today,
        timeIn: '8:00 AM',
        timeOut: '1:00 PM',
        now: _now,
      );

      expect(result, contains('same session'));
      expect(store.savedAttendance, isEmpty);
    });
  });

  group('missed time-outs', () {
    test('go by Philippine time, whatever the device says', () async {
      state.currentUser = _head;
      state.attendance = [
        _record('m1', timeIn: '8:00 AM', timeOut: null),
        _record('p1', timeIn: '1:00 PM', timeOut: null),
      ];

      // 1:30 PM in the Philippines: the morning is over, the afternoon isn't.
      await state.invalidateMissedTimeOuts(DateTime.utc(2026, 11, 27, 5, 30));

      expect(store.attendanceUpdates.keys, ['m1']);
      expect(
        state.attendance.firstWhere((r) => r.id == 'p1').isInvalid,
        isFalse,
      );
    });
  });

  group('office entries without an account', () {
    test('lists name-only places and the account each matches', () {
      state.offices = [
        const Office(
          id: 'reg',
          name: 'Registrar',
          code: 'REG',
          headIds: [''],
          headNames: ['Sid Supervisor'],
          // An older office: fewer ids than names.
          assistantNames: ['Carla Diaz'],
        ),
      ];
      final carla = User(
        id: 'carla',
        name: 'Carla Diaz',
        email: 'carla@example.com',
        role: 'Student Assistant',
      );
      state.users = [...state.users, carla];

      final people = state.unlinkedOfficePeople;

      expect(people.length, 2);
      expect(people[0].isSupervisor, isTrue);
      expect(people[0].match?.id, 'sid');
      expect(people[1].name, 'Carla Diaz');
      expect(people[1].match?.id, 'carla');
    });

    test('no match when the name fits several accounts, or none', () {
      state.offices = [
        const Office(
          id: 'reg',
          name: 'Registrar',
          code: 'REG',
          assistantIds: ['', ''],
          assistantNames: ['Twin Name', 'Nobody Here'],
        ),
      ];
      state.users = [
        ...state.users,
        for (final id in ['t1', 't2'])
          User(
            id: id,
            name: 'Twin Name',
            email: '$id@example.com',
            role: 'Student Assistant',
          ),
      ];

      final people = state.unlinkedOfficePeople;

      expect(people.map((p) => p.match), [null, null]);
    });

    test('no match for an assistant already placed, or name-only twice', () {
      state.offices = [
        _library,
        const Office(
          id: 'reg',
          name: 'Registrar',
          code: 'REG',
          assistantIds: [''],
          assistantNames: ['Ana Reyes'],
        ),
        const Office(
          id: 'cash',
          name: 'Cashier',
          code: 'CSH',
          assistantIds: ['', ''],
          assistantNames: ['Dan Uy', ''],
        ),
        const Office(
          id: 'gym',
          name: 'Gym',
          code: 'GYM',
          assistantIds: [''],
          assistantNames: ['Dan Uy'],
        ),
      ];
      state.users = [
        ...state.users,
        User(
          id: 'dan',
          name: 'Dan Uy',
          email: 'dan@example.com',
          role: 'Student Assistant',
        ),
      ];

      final people = state.unlinkedOfficePeople;

      expect(people.map((p) => '${p.office.id}:${p.match?.id}'), [
        'reg:null',
        'cash:null',
        'gym:null',
      ]);
    });

    test('nothing to list when every place has its id', () {
      expect(state.unlinkedOfficePeople, isEmpty);
    });

    test('Link puts the id in its place and files the assignment', () async {
      state.currentUser = _head;
      const registrar = Office(
        id: 'reg',
        name: 'Registrar',
        code: 'REG',
        headIds: ['sid'],
        headNames: ['Sid Supervisor'],
        assistantNames: ['Eve Lim'],
      );
      final eve = User(
        id: 'eve',
        name: 'Eve Lim',
        email: 'eve@example.com',
        role: 'Student Assistant',
      );
      state
        ..users = [...state.users, eve]
        ..offices = [registrar];
      store.officeDocs['reg'] = registrar;

      final person = state.unlinkedOfficePeople.single;
      expect(await state.linkOfficePerson(person), isTrue);

      expect(store.officeDocs['reg']!.assistantIds, ['eve']);
      expect(state.offices.single.assistantIds, ['eve']);
      expect(store.assignmentDocs['eve'], 'reg');
      expect(state.unlinkedOfficePeople, isEmpty);
    });

    test('Link refuses an assistant placed in another office meanwhile', () async {
      state.currentUser = _head;
      const registrar = Office(
        id: 'reg',
        name: 'Registrar',
        code: 'REG',
        assistantIds: [''],
        assistantNames: ['Eve Lim'],
      );
      state
        ..users = [
          ...state.users,
          User(
            id: 'eve',
            name: 'Eve Lim',
            email: 'eve@example.com',
            role: 'Student Assistant',
          ),
        ]
        ..offices = [registrar];
      final person = state.unlinkedOfficePeople.single;
      // The Head placed her in the Gym from another tab first.
      store.officeDocs['reg'] = registrar;
      store.officeDocs['gym'] = const Office(
        id: 'gym',
        name: 'Gym',
        code: 'GYM',
        assistantIds: ['eve'],
        assistantNames: ['Eve Lim'],
      );
      store.assignmentDocs['eve'] = 'gym';

      expect(await state.linkOfficePerson(person), isFalse);
      expect(store.officeDocs['reg']!.assistantIds, ['']);
      expect(store.assignmentDocs['eve'], 'gym');
    });

    test('Link leaves a place that changed meanwhile alone', () async {
      state.currentUser = _head;
      const registrar = Office(
        id: 'reg',
        name: 'Registrar',
        code: 'REG',
        assistantIds: [''],
        assistantNames: ['Eve Lim'],
      );
      state
        ..users = [
          ...state.users,
          User(
            id: 'eve',
            name: 'Eve Lim',
            email: 'eve@example.com',
            role: 'Student Assistant',
          ),
        ]
        ..offices = [registrar];
      final person = state.unlinkedOfficePeople.single;
      // Someone else removed her from the office first.
      store.officeDocs['reg'] = registrar.copyWith(
        assistantIds: [],
        assistantNames: [],
      );

      expect(await state.linkOfficePerson(person), isFalse);
      expect(store.assignmentDocs, isEmpty);
    });
  });

  test('a record knows the office whose code was scanned', () {
    final record = AttendanceRecord.fromJson({
      'id': 'r1',
      'studentName': 'Ana Reyes',
      'date': 'Nov 27, 2026',
      'timeIn': '8:00 AM',
      'officeId': 'lib',
    });
    expect(record.officeId, 'lib');
    expect(record.copyWith(isArchived: true).officeId, 'lib');
  });
}
