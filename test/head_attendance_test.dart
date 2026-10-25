import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/attendance/head_attendance_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

class _Store extends FirestoreService {}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);
final _sam = User(
  id: 'sam',
  name: 'Sam Santos',
  email: 'sam@marsu.edu.ph',
  role: 'Student Assistant',
  department: 'CICS',
);
final _rita = User(
  id: 'rita',
  name: 'Rita Reyes',
  email: 'rita@marsu.edu.ph',
  role: 'Student Assistant',
  department: 'CED',
);
final _former = User(
  id: 'old',
  name: 'Olga Old',
  email: 'olga@marsu.edu.ph',
  role: 'Student',
);

AttendanceRecord _record(
  String id,
  String date, {
  String? studentId,
  String name = 'Sam Santos',
  String? timeOut = '11:00 AM',
  double hours = 3,
  bool archived = false,
  bool invalid = false,
}) => AttendanceRecord(
  id: id,
  studentName: name,
  studentId: studentId,
  date: date,
  timeIn: '8:00 AM',
  timeOut: timeOut,
  totalHours: hours,
  isArchived: archived,
  isInvalid: invalid,
);

void main() {
  late AppState state;

  setUp(() {
    state = AppState(firestoreService: _Store())
      ..currentUser = _head
      ..users = [_head, _sam, _rita, _former]
      ..students = [
        Student(
          id: 'stu-sam',
          name: 'Sam Santos',
          email: 'sam@marsu.edu.ph',
          department: 'CICS',
          userId: 'sam',
          totalHours: 0,
        ),
      ]
      ..offices = const [
        Office(
          id: 'lib',
          name: 'Library',
          code: 'LIB',
          assistantIds: ['sam'],
          assistantNames: ['Sam Santos'],
        ),
      ]
      ..attendance = [
        // By account id, by students-record id, and by name (no id).
        _record('a1', 'Oct 1, 2026', studentId: 'sam'),
        _record('a2', 'Oct 2, 2026', studentId: 'stu-sam'),
        _record('a3', 'Oct 2, 2026'),
        _record(
          'a4',
          'Oct 3, 2026',
          studentId: 'sam',
          invalid: true,
          timeOut: null,
          hours: 0,
        ),
        _record('a5', 'Oct 4, 2026', studentId: 'sam', archived: true),
        _record('a6', 'Sep 20, 2026', studentId: 'sam'),
        // Rita is clocked in "today".
        _record(
          'b1',
          'Oct 11, 2026',
          studentId: 'rita',
          name: 'Rita Reyes',
          timeOut: null,
          hours: 0,
        ),
        // A former assistant's record isn't anyone's here.
        _record('c1', 'Oct 1, 2026', studentId: 'old', name: 'Olga Old'),
      ];
  });

  group('the summary', () {
    // 9 AM in Manila on Oct 11, 2026.
    final now = DateTime.utc(2026, 10, 11, 1);

    test('one row per current Student Assistant, their records found by '
        'account, roster or name', () {
      final rows = state.assistantAttendance(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        now: now,
      );

      expect(rows.map((r) => r.assistant.name), ['Rita Reyes', 'Sam Santos']);
      final sam = rows.last;
      expect(sam.records.map((r) => r.id), ['a4', 'a2', 'a3', 'a1']);
      expect(sam.hours, 9);
      expect(sam.verifiedDays, 2);
      expect(sam.missedTimeOuts, 1);
      expect(sam.officeLabel, 'Library');
      expect(sam.clockedIn, isFalse);

      final rita = rows.first;
      expect(rita.clockedIn, isTrue);
      expect(rita.officeLabel, 'No office yet');
    });

    test('archived records count in no total, and are listed on request', () {
      final shown = state.assistantAttendance(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        includeArchived: true,
        now: now,
      );
      final sam = shown.last;

      expect(sam.records.map((r) => r.id), contains('a5'));
      expect(sam.hours, 9);
    });

    test('a period leaves out the days outside it', () {
      final september = state.assistantAttendance(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        now: now,
      );

      expect(september.last.records.map((r) => r.id), ['a6']);
      expect(september.first.hasAttendance, isFalse);
    });
  });

  group('the Head', () {
    test("no longer has DTR/Accomplishment Report or Document Folders", () {
      final head = AppShell.pagesFor('Head').map((p) => p.id);
      expect(head, isNot(contains('dtr_accomplishment_report')));
      expect(head, isNot(contains('document_folders')));
      expect(head, contains('attendance'));
      // Supervisors still make DTRs.
      expect(
        AppShell.pagesFor('Supervisor').map((p) => p.id),
        contains('dtr_accomplishment_report'),
      );
    });

    Future<void> pump(WidgetTester tester, Widget home, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(theme: AppTheme.theme, home: home),
        ),
      );
      await tester.pump();
    }

    testWidgets('sees the summary on Attendance, with no QR code', (
      tester,
    ) async {
      state.activeTab = 'attendance';
      await pump(tester, const AppShell(), const Size(1440, 1000));

      expect(find.byType(HeadAttendanceScreen), findsOneWidget);
      expect(find.text('Generate QR Code'), findsNothing);
      expect(find.text('Sam Santos'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
    });

    testWidgets('filters the summary', (tester) async {
      await pump(
        tester,
        const Scaffold(body: HeadAttendanceScreen()),
        const Size(1440, 1000),
      );
      await tester.tap(find.text('School year'));
      await tester.pumpAndSettle();
      expect(find.text('Sam Santos'), findsOneWidget);
      expect(find.text('Rita Reyes'), findsOneWidget);

      await tester.tap(find.text('Missed time-outs').last);
      await tester.pumpAndSettle();
      expect(find.text('Sam Santos'), findsOneWidget);
      expect(find.text('Rita Reyes'), findsNothing);

      // Opening a row lists the records.
      await tester.tap(find.text('Sam Santos'));
      await tester.pumpAndSettle();
      expect(find.text('Missed time-out'), findsOneWidget);
      expect(find.text('Oct 2, 2026'), findsNWidgets(2));
    });

    testWidgets('fits a phone', (tester) async {
      await pump(
        tester,
        const Scaffold(body: HeadAttendanceScreen()),
        const Size(390, 844),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sam Santos'), findsOneWidget);
    });
  });

  testWidgets('a Supervisor keeps the attendance page with the QR code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);
    addTearDown(() => FlutterError.onError = onError);
    state
      ..currentUser = User(
        id: 'sup',
        name: 'Sid Supervisor',
        email: 'sid@marsu.edu.ph',
        role: 'Supervisor',
      )
      ..activeTab = 'attendance';
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: AppTheme.theme, home: const AppShell()),
      ),
    );
    await tester.pump();

    expect(find.byType(HeadAttendanceScreen), findsNothing);
    expect(find.text('Generate QR Code'), findsOneWidget);
  });
}
