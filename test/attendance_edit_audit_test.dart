import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

import 'support/account_writes.dart';

class _Fake extends FirestoreService with AccountWrites {
  final notices = <Map<String, dynamic>>[];
  final updates = <String, Map<String, dynamic>>{};
  final deleted = <String>[];
  bool fail = false;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notices.add(payload);

  @override
  Future<void> updateAttendance(String id, Map<String, dynamic> data) async {
    if (fail) throw Exception('permission-denied');
    updates[id] = data;
  }

  @override
  Future<void> deleteAttendance(String id) async {
    if (fail) throw Exception('permission-denied');
    deleted.add(id);
  }
}

final _head = User(
  id: 'h1',
  name: 'Hana Head',
  email: 'h@example.com',
  role: 'Head',
);

AttendanceRecord _record({String? timeOut}) => AttendanceRecord(
  id: 'r1',
  studentId: 'sa1',
  studentName: 'Juan Dela Cruz',
  date: 'Sep 10, 2026',
  timeIn: '8:00 AM',
  timeOut: timeOut,
  totalHours: timeOut == null ? null : 4,
  isInvalid: timeOut == null,
);

void main() {
  late _Fake fake;
  late AppState state;

  setUp(() {
    fake = _Fake();
    state = AppState(firestoreService: fake)
      ..currentUser = _head
      ..attendance = [_record()];
  });

  tearDown(() => state.dispose());

  test(
    'a time-out recorded by hand says who did it, and tells the student',
    () async {
      expect(await state.setManualTimeOut('r1', '11:30 AM'), isTrue);

      final saved = fake.updates['r1']!;
      expect(saved['editedBy'], 'Hana Head');
      expect(saved['editNote'], 'Time-out recorded at 11:30 AM');
      expect(DateTime.tryParse(saved['editedAt'] as String), isNotNull);

      final shown = state.attendance.single;
      expect(
        shown.editSummary,
        startsWith(
          'Time-out recorded at 11:30 AM by '
          'Hana Head on ',
        ),
      );

      expect(fake.notices, hasLength(1));
      expect(fake.notices.single['userId'], 'sa1');
      expect(fake.notices.single['title'], 'Attendance Record Changed');
      expect(fake.notices.single['message'], contains('Sep 10, 2026'));
      expect(fake.notices.single['message'], contains('Hana Head'));
    },
  );

  test('archiving and restoring are recorded too', () async {
    expect(await state.setAttendanceArchived('r1', true), isTrue);
    expect(fake.updates['r1']!['editNote'], 'Archived');
    expect(state.attendance.single.isArchived, isTrue);

    expect(await state.setAttendanceArchived('r1', false), isTrue);
    expect(fake.updates['r1']!['editNote'], 'Restored');
    expect(state.attendance.single.editNote, 'Restored');
    expect(fake.notices, hasLength(2));
  });

  test(
    'a change that is not saved leaves the record and the student alone',
    () async {
      fake.fail = true;

      expect(await state.setManualTimeOut('r1', '11:30 AM'), isFalse);
      expect(await state.setAttendanceArchived('r1', true), isFalse);
      expect(await state.deleteAttendance('r1'), isFalse);

      final shown = state.attendance.single;
      expect(shown.timeOut, isNull);
      expect(shown.isArchived, isFalse);
      expect(shown.editNote, isNull);
      expect(fake.notices, isEmpty);
    },
  );

  test('a deleted record leaves a notice to the student', () async {
    expect(await state.deleteAttendance('r1'), isTrue);

    expect(state.attendance, isEmpty);
    expect(fake.deleted, ['r1']);
    expect(fake.notices.single['message'], startsWith('Deleted: your record'));
  });

  test('later system changes keep the edit note', () async {
    await state.setManualTimeOut('r1', '11:30 AM');
    await state.invalidateMissedTimeOuts();

    expect(state.attendance.single.editNote, startsWith('Time-out recorded'));
  });

  test('a record nobody has changed shows no edit line', () {
    expect(_record().editSummary, isNull);
  });
}
