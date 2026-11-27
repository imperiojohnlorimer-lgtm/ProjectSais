import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/attendance/attendance_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

import 'support/account_writes.dart';

class _Store extends FirestoreService with AccountWrites {
  final updates = <String, Map<String, dynamic>>{};

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {}

  @override
  Future<void> updateAttendance(String id, Map<String, dynamic> data) async =>
      updates[id] = data;
}

final _assistant = User(
  id: 'sa1',
  name: 'Juan Dela Cruz',
  email: 'juan@example.com',
  role: 'Student Assistant',
);

final _head = User(
  id: 'h1',
  name: 'Hana Head',
  email: 'h@example.com',
  role: 'Head',
);

AttendanceRecord _record(
  String id,
  String date, {
  double hours = 4,
  bool open = false,
  bool archived = false,
  bool invalid = false,
}) => AttendanceRecord(
  id: id,
  studentId: 'sa1',
  studentName: 'Juan Dela Cruz',
  date: date,
  timeIn: '8:00 AM',
  timeOut: open ? null : '12:00 PM',
  totalHours: open ? null : hours,
  isArchived: archived,
  isInvalid: invalid,
);

void main() {
  group('this week\'s hours by day', () {
    // Wednesday, 25 November 2026, 10:00 in the Philippines.
    final wednesday = DateTime.utc(2026, 11, 25, 2);

    test('counts only finished, current records of this week', () {
      final state = AppState()
        ..currentUser = _assistant
        ..attendance = [
          _record('mon', 'Nov 23, 2026', hours: 3.5),
          _record('mon2', '11/23/2026', hours: 1), // the other date form
          _record('wed', 'Nov 25, 2026', hours: 4),
          _record('sun', 'Nov 29, 2026', hours: 2),
          _record('lastWeek', 'Nov 20, 2026', hours: 8),
          _record('open', 'Nov 24, 2026', open: true),
          _record('archived', 'Nov 24, 2026', archived: true),
          _record('voided', 'Nov 24, 2026', invalid: true),
          _record('blank', '', hours: 5),
        ];

      expect(state.weekHoursByDay(wednesday), {
        DateTime.monday: 4.5,
        DateTime.wednesday: 4.0,
        DateTime.sunday: 2.0,
      });
    });

    test('a new week starts at midnight in the Philippines', () {
      final state = AppState()
        ..currentUser = _assistant
        ..attendance = [_record('sun', 'Nov 29, 2026', hours: 2)];

      // Sunday 20:00 UTC is already Monday 04:00 in Manila.
      expect(state.weekHoursByDay(DateTime.utc(2026, 11, 29, 20)), isEmpty);
      expect(state.weekHoursByDay(DateTime.utc(2026, 11, 29, 10)), {
        DateTime.sunday: 2.0,
      });
    });
  });

  test('a Sunday has no day in the class week', () {
    expect(todayInWeek(DateTime(2026, 11, 23)), 0); // Monday
    expect(todayInWeek(DateTime(2026, 11, 28)), 5); // Saturday
    expect(todayInWeek(DateTime(2026, 11, 29)), isNull); // Sunday
  });

  group('recording a time-out by hand', () {
    test('only for a record that is still open and not archived', () {
      expect(
        AppState.canSetManualTimeOut(_record('a', 'Nov 24, 2026', open: true)),
        isTrue,
      );
      expect(
        AppState.canSetManualTimeOut(
          _record('a', 'Nov 24, 2026', open: true, invalid: true),
        ),
        isTrue, // a missed time-out is what it is for
      );
      expect(
        AppState.canSetManualTimeOut(
          _record('a', 'Nov 24, 2026', open: true, archived: true),
        ),
        isFalse,
      );
      expect(
        AppState.canSetManualTimeOut(_record('a', 'Nov 24, 2026')),
        isFalse,
      );
      expect(AppState.canSetManualTimeOut(null), isFalse);
    });

    test('refuses an archived record, and one timed out meanwhile', () async {
      final store = _Store();
      final state = AppState(firestoreService: store)
        ..currentUser = _head
        ..attendance = [
          _record('archived', 'Nov 24, 2026', open: true, archived: true),
          _record('done', 'Nov 24, 2026'),
        ];

      expect(await state.setManualTimeOut('archived', '11:30 AM'), isFalse);
      expect(await state.setManualTimeOut('done', '11:30 AM'), isFalse);
      expect(await state.setManualTimeOut('missing', '11:30 AM'), isFalse);
      expect(store.updates, isEmpty);
      expect(
        state.attendance.firstWhere((r) => r.id == 'done').timeOut,
        '12:00 PM',
      );
    });
  });

  group('the Attendance page', () {
    Future<AppState> pumpPage(
      WidgetTester tester,
      List<AttendanceRecord> records,
    ) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final original = FlutterError.onError;
      // The test font draws every glyph as a full square, so wide rows
      // overflow here that fit in the app.
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
      final state = AppState(firestoreService: _Store())
        ..currentUser = _assistant
        ..attendance = records;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: AttendanceScreen()),
          ),
        ),
      );
      await tester.pump();
      return state;
    }

    testWidgets('the weekly summary shows today\'s hours', (tester) async {
      final today = AppState().philippineToday();
      await pumpPage(tester, [_record('today', today, hours: 3.5)]);

      expect(
        find.textContaining('Your hours this week: 3.5 of 20 h'),
        findsOneWidget,
      );
      expect(find.text('3.5h'), findsWidgets); // its bar, and the record
    });

    testWidgets('a record with no date still shows', (tester) async {
      await pumpPage(tester, [_record('blank', '', hours: 2)]);

      expect(tester.takeException(), isNull);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('an unparseable multi-word date splits on whitespace', (
      tester,
    ) async {
      await pumpPage(tester, [_record('weird', 'August 15', hours: 2)]);

      expect(tester.takeException(), isNull);
      expect(find.text('AUG'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
    });
  });
}
