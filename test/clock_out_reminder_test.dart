import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Keeps the notifications the app saves in memory.
class _Store extends FirestoreService {
  final added = <Map<String, dynamic>>[];
  final updated = <String, Map<String, dynamic>>{};

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      added.add(payload);

  @override
  Future<void> updateNotification(String id, Map<String, dynamic> data) async =>
      updated[id] = data;

  @override
  Future<void> deleteNotification(String id) async {}
}

final _assistant = User(
  id: 'sa1',
  name: 'Sara Assistant',
  email: 'sa@example.com',
  role: 'Student Assistant',
);
final _supervisor = User(
  id: 'sup1',
  name: 'Sid Supervisor',
  email: 'sup@example.com',
  role: 'Supervisor',
);

/// The day every record below is from.
DateTime _at(int hour, int minute) => DateTime(2026, 10, 5, hour, minute);

AttendanceRecord _record({
  String id = 'r1',
  String timeIn = '8:05 AM',
  String? timeOut,
  String studentId = 'sa1',
  bool isInvalid = false,
  bool isArchived = false,
}) => AttendanceRecord(
  id: id,
  studentName: studentId == 'sa1' ? 'Sara Assistant' : 'Olga Other',
  studentId: studentId,
  date: 'Oct 5, 2026',
  timeIn: timeIn,
  timeOut: timeOut,
  isInvalid: isInvalid,
  isArchived: isArchived,
);

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store();
    state = AppState(firestoreService: store);
  });

  group('reminder time', () {
    test('is 30 minutes before the clocked-in session ends', () {
      expect(state.clockOutReminderTime(_record()), _at(11, 30));
      expect(
        state.clockOutReminderTime(_record(timeIn: '12:45 PM')),
        _at(16, 30),
      );
    });

    test('is none for a time-in after it, outside both sessions, or '
        'unreadable', () {
      expect(state.clockOutReminderTime(_record(timeIn: '11:40 AM')), isNull);
      expect(state.clockOutReminderTime(_record(timeIn: '6:00 PM')), isNull);
      expect(state.clockOutReminderTime(_record(timeIn: 'soon')), isNull);
    });
  });

  group('a clocked-in student assistant', () {
    setUp(() {
      state.currentUser = _assistant;
      state.attendance = [_record()];
    });
    tearDown(() => state.dispose());

    test('is not reminded before the time', () {
      expect(state.remindToClockOutIfDue(_at(11, 29)), isNull);
      expect(store.added, isEmpty);
    });

    test('is reminded 30 minutes before the morning session ends', () {
      final reminder = state.remindToClockOutIfDue(_at(11, 30));

      expect(reminder, isNotNull);
      expect(reminder!.title, 'Time to Clock Out');
      expect(reminder.type, 'attendance');
      expect(
        reminder.message,
        'Your morning session ends at 12:00 PM. Scan the attendance QR code '
        'to clock out before then, or this session won\'t count toward your '
        'hours.',
      );
      final saved = store.added.single;
      expect(saved['id'], 'clockout_r1');
      expect(saved['userId'], 'sa1');
      expect(state.myNotifications.single.id, 'clockout_r1');
      expect(state.unreadNotificationCount, 1);
      expect(state.notificationTab(state.myNotifications.single), 'attendance');
    });

    test('is reminded before the afternoon session ends', () {
      state.attendance = [_record(timeIn: '1:00 PM')];

      final reminder = state.remindToClockOutIfDue(_at(16, 30));

      expect(
        reminder!.message,
        startsWith(
          'Your afternoon session ends at '
          '5:00 PM.',
        ),
      );
    });

    test('gets a reminder that came due while the app was closed', () {
      expect(state.remindToClockOutIfDue(_at(11, 50)), isNotNull);
    });

    test('pops the reminder up while the app is open', () async {
      final shown = state.clockOutReminderAlerts.first;

      final reminder = state.remindToClockOutIfDue(_at(11, 30));

      expect(await shown, same(reminder));
    });

    test('is reminded only once, even after deleting it', () {
      state.remindToClockOutIfDue(_at(11, 30));
      expect(state.remindToClockOutIfDue(_at(11, 31)), isNull);

      state.deleteNotification('clockout_r1');
      expect(state.remindToClockOutIfDue(_at(11, 32)), isNull);
      expect(store.added, hasLength(1));
    });

    test('is not reminded again when another device already did', () {
      state.notifications = [
        AppNotification(
          id: 'clockout_r1',
          userId: 'sa1',
          title: 'Time to Clock Out',
          message: '',
          type: 'attendance',
          createdAt: 'Oct 5, 2026',
        ),
      ];

      expect(state.remindToClockOutIfDue(_at(11, 30)), isNull);
      expect(store.added, isEmpty);
    });

    test('is not reminded once the session is over', () {
      expect(state.remindToClockOutIfDue(_at(12, 0)), isNull);
      expect(store.added, isEmpty);
    });

    test('who clocked in after the reminder time gets none', () {
      state.attendance = [_record(timeIn: '11:40 AM')];

      expect(state.remindToClockOutIfDue(_at(11, 45)), isNull);
    });

    test('is not reminded after clocking out, or about a voided or archived '
        'session', () {
      for (final record in [
        _record(timeOut: '11:00 AM'),
        _record(isInvalid: true),
        _record(isArchived: true),
      ]) {
        state.attendance = [record];
        expect(state.remindToClockOutIfDue(_at(11, 30)), isNull);
      }
      expect(store.added, isEmpty);
    });

    test("is not reminded about someone else's session", () {
      state.attendance = [_record(studentId: 'sa2')];

      expect(state.remindToClockOutIfDue(_at(11, 30)), isNull);
    });
  });

  test('staff are never reminded', () {
    state.currentUser = _supervisor;
    state.attendance = [_record()];

    expect(state.remindToClockOutIfDue(_at(11, 30)), isNull);
    expect(store.added, isEmpty);
  });

  testWidgets('the reminder pops up on screen and opens Attendance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    state.currentUser = _assistant;
    state.attendance = [_record()];
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    state.remindToClockOutIfDue(_at(11, 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    final snackBar = find.byType(SnackBar);
    expect(
      find.descendant(of: snackBar, matching: find.text('Time to Clock Out')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: snackBar, matching: find.text('Open Attendance')),
    );
    await tester.pump();

    expect(state.activeTab, 'attendance');
    expect(store.updated['clockout_r1'], {'isRead': true});
  });
}
