import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

class _Store extends FirestoreService {}

AttendanceRecord _open(String timeIn, {String date = 'Oct 5, 2026'}) =>
    AttendanceRecord(
      id: 'r1',
      studentName: 'Sara Assistant',
      studentId: 'sa1',
      date: date,
      timeIn: timeIn,
    );

void main() {
  final state = AppState(firestoreService: _Store());
  // Oct 6, 2026, 9:00 AM in the Philippines: Oct 5 is a past day.
  final now = DateTime.utc(2026, 10, 6, 1);

  String? problem(AttendanceRecord r, String out) =>
      state.manualTimeOutProblem(r, out, now: now);

  test('a time-out inside the session is fine', () {
    expect(problem(_open('8:05 AM'), '11:30 AM'), isNull);
    expect(problem(_open('8:05 AM'), '12:00 PM'), isNull);
    expect(problem(_open('1:00 PM'), '5:00 PM'), isNull);
    // A time-in just after noon is the afternoon session.
    expect(problem(_open('12:10 PM'), '3:00 PM'), isNull);
  });

  test('a time-out at or before the time-in is refused', () {
    expect(problem(_open('8:05 AM'), '8:05 AM'), contains('after the time-in'));
    expect(
      problem(_open('1:00 PM'), '11:00 AM'),
      contains('after the time-in'),
    );
  });

  test('a time-out past the session end is refused (no hours over lunch)', () {
    expect(problem(_open('8:05 AM'), '5:00 PM'), contains('12:00 PM'));
    expect(problem(_open('1:00 PM'), '5:30 PM'), contains('5:00 PM'));
  });

  test("today's record can't be timed out later than now", () {
    final today = _open('7:45 AM', date: 'Oct 6, 2026');
    expect(problem(today, '8:30 AM'), isNull);
    expect(problem(today, '10:00 AM'), contains('later than now'));
  });

  test('a closed or archived record is refused', () {
    final closed = AttendanceRecord(
      id: 'r2',
      studentName: 'Sara Assistant',
      studentId: 'sa1',
      date: 'Oct 5, 2026',
      timeIn: '8:00 AM',
      timeOut: '11:00 AM',
    );
    expect(problem(closed, '11:30 AM'), contains('changed meanwhile'));
  });
}
