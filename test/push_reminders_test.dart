import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/admin_notifications_screen.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/attendance/attendance_screen.dart';
import 'package:projectsais/screens/student_portal/sp_notifications_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/push_service.dart';

/// Stands in for the browser: [current] is its notification permission,
/// [answer] what the "Allow notifications?" prompt returns.
class _FakePush extends PushService {
  PushPermission current = PushPermission.notAsked;
  PushPermission answer = PushPermission.granted;
  String? deviceToken = 'device-1';
  int prompts = 0;
  final messages = StreamController<Map<String, dynamic>>.broadcast();
  final delivered = <List<String>>[];
  Completer<({bool ok, String? error})>? test;

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return current = answer;
  }

  @override
  Future<String?> token() async => deviceToken;

  @override
  Stream<Map<String, dynamic>> get foregroundMessages => messages.stream;

  @override
  Future<void> deliver(List<String> notificationIds) async =>
      delivered.add(notificationIds);

  @override
  Future<({bool ok, String? error})> sendTest({required int delaySeconds}) =>
      (test = Completer()).future;
}

/// Keeps the device tokens, notifications and tasks the app saves in
/// memory.
class _Store extends FirestoreService {
  bool failSave = false;
  bool failNotifications = false;
  final tokens = <String, String>{};
  final deleted = <String>[];
  final notifications = <Map<String, dynamic>>[];

  @override
  Future<void> savePushToken(String token, String userId) async {
    if (failSave) throw Exception('unavailable');
    tokens[token] = userId;
  }

  @override
  Future<void> deletePushToken(String token) async {
    deleted.add(token);
    tokens.remove(token);
  }

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {
    if (failNotifications) throw Exception('unavailable');
    notifications.add(payload);
  }

  @override
  Future<void> setTask(Task t) async {}
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
final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@example.com',
  role: 'Head',
);
final _admin = User(
  id: 'admin1',
  name: 'Ada Admin',
  email: 'admin@example.com',
  role: 'Admin',
);

Map<String, dynamic> _pushed(String type, String id) => {
  'type': type,
  'notificationId': id,
  'title': 'Time to Clock Out',
  'body': 'Your morning session ends at 12:00 PM.',
};

void main() {
  late _FakePush push;
  late _Store store;
  late AppState state;

  setUp(() {
    push = _FakePush();
    store = _Store();
    state = AppState(firestoreService: store, pushService: push);
    state.currentUser = _assistant;
  });

  group('signing in', () {
    test('registers this browser once notifications are allowed', () async {
      push.current = PushPermission.granted;

      await state.registerForPush();

      expect(store.tokens, {'device-1': 'sa1'});
      expect(state.pushOn, isTrue);
      expect(state.pushPermission, PushPermission.granted);
      expect(push.prompts, 0);
    });

    test('never asks for permission by itself', () async {
      await state.registerForPush();

      expect(push.prompts, 0);
      expect(store.tokens, isEmpty);
      expect(state.pushPermission, PushPermission.notAsked);
      expect(state.pushOn, isFalse);
    });

    test('registers staff and students as well', () async {
      state.currentUser = _supervisor;
      push.current = PushPermission.granted;

      await state.registerForPush();

      expect(store.tokens, {'device-1': 'sup1'});
    });

    test('leaves out the Admin, who gets no notifications', () async {
      state.currentUser = _admin;
      push.current = PushPermission.granted;

      await state.registerForPush();

      expect(store.tokens, isEmpty);
      expect(state.pushPermission, isNull);
    });
  });

  group('turning reminders on', () {
    test('asks the browser, then registers it', () async {
      await state.registerForPush(ask: true);

      expect(push.prompts, 1);
      expect(store.tokens, {'device-1': 'sa1'});
      expect(state.pushOn, isTrue);
    });

    test('does nothing more when the student blocks notifications', () async {
      push.answer = PushPermission.denied;

      await state.registerForPush(ask: true);

      expect(store.tokens, isEmpty);
      expect(state.pushPermission, PushPermission.denied);
      expect(state.pushOn, isFalse);
    });

    test('does nothing where the browser has no push', () async {
      push.current = PushPermission.unsupported;
      push.answer = PushPermission.unsupported;

      await state.registerForPush(ask: true);

      expect(store.tokens, isEmpty);
      expect(state.pushPermission, PushPermission.unsupported);
    });

    test('stays off when the device cannot be saved', () async {
      store.failSave = true;

      await state.registerForPush(ask: true);

      expect(state.pushOn, isFalse);
      expect(state.pushPermission, PushPermission.granted);
      expect(state.pushBusy, isFalse);
    });
  });

  test('signing out takes this browser off the account', () async {
    push.current = PushPermission.granted;
    await state.registerForPush();

    await state.signOut();

    expect(store.deleted, ['device-1']);
    expect(store.tokens, isEmpty);
    expect(state.pushOn, isFalse);
  });

  group('a new notification', () {
    setUp(() {
      state.tasks = [
        Task(
          id: 't1',
          title: 'File the forms',
          description: '',
          status: 'In Progress',
          priority: 'Medium',
          dueDate: 'Oct 30, 2026',
          assignedTo: 'sa1',
          assignedToName: 'Sara Assistant',
          assignedBy: 'sup1',
        ),
      ];
    });

    test('is sent for pushing once it is saved', () async {
      await state.updateTaskStatus('t1', 'Completed');
      await pumpEventQueue();

      final saved = store.notifications.single;
      expect(saved['userId'], 'sup1');
      expect(push.delivered, [
        [saved['id']],
      ]);
    });

    test('is not pushed when it could not be saved', () async {
      store.failNotifications = true;

      await state.updateTaskStatus('t1', 'Completed');
      await pumpEventQueue();

      expect(push.delivered, isEmpty);
    });

    test('except the clock-out reminder, which has its own schedule', () async {
      state.attendance = [
        AttendanceRecord(
          id: 'r1',
          studentName: 'Sara Assistant',
          studentId: 'sa1',
          date: 'Oct 5, 2026',
          timeIn: '8:05 AM',
        ),
      ];

      state.remindToClockOutIfDue(DateTime(2026, 10, 5, 11, 30));
      await pumpEventQueue();

      expect(store.notifications.single['id'], 'clockout_r1');
      expect(push.delivered, isEmpty);
    });
  });

  group('a push while SAIS is open', () {
    setUp(() async {
      push.current = PushPermission.granted;
      await state.registerForPush();
    });
    tearDown(() => state.dispose());

    test('pops up once', () async {
      final shown = <AppNotification>[];
      state.clockOutReminderAlerts.listen(shown.add);

      push.messages.add(_pushed('clockout', 'clockout_r1'));
      push.messages.add(_pushed('clockout', 'clockout_r1'));
      await pumpEventQueue();

      expect(shown.single.id, 'clockout_r1');
      expect(shown.single.title, 'Time to Clock Out');
      expect(shown.single.message, 'Your morning session ends at 12:00 PM.');
    });

    test("doesn't pop up again after the app's own reminder", () async {
      state.attendance = [
        AttendanceRecord(
          id: 'r1',
          studentName: 'Sara Assistant',
          studentId: 'sa1',
          date: 'Oct 5, 2026',
          timeIn: '8:05 AM',
        ),
      ];
      final shown = <AppNotification>[];
      state.clockOutReminderAlerts.listen(shown.add);

      state.remindToClockOutIfDue(DateTime(2026, 10, 5, 11, 30));
      push.messages.add(_pushed('clockout', 'clockout_r1'));
      await pumpEventQueue();

      expect(shown, hasLength(1));
    });

    test('shows a test, and ignores anything else', () async {
      final shown = <AppNotification>[];
      state.clockOutReminderAlerts.listen(shown.add);

      push.messages.add(_pushed('test', 'push_test_1'));
      push.messages.add(_pushed('other', 'x1'));
      push.messages.add({'type': 'clockout'});
      await pumpEventQueue();

      expect(shown.single.id, 'push_test_1');
    });
  });

  testWidgets('a test that arrives while SAIS is showing pops up with no '
      'way onward', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    push.current = PushPermission.granted;
    await state.registerForPush();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    push.messages.add({
      'type': 'test',
      'notificationId': 'push_test_1',
      'title': 'Test Notification',
      'body': 'SAIS notifications are working on this device.',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    final snackBar = find.byType(SnackBar);
    expect(
      find.descendant(of: snackBar, matching: find.text('Test Notification')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: snackBar, matching: find.text('Open Attendance')),
      findsNothing,
    );
  });

  group('Attendance page', () {
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(home: Scaffold(body: AttendanceScreen())),
        ),
      );
      await tester.pump();
    }

    testWidgets('offers to turn reminders on, then to send a test', (
      tester,
    ) async {
      state.pushPermission = PushPermission.notAsked;
      await pumpPage(tester);

      expect(find.text('Clock-out reminders'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(push.prompts, 1);
      expect(store.tokens, {'device-1': 'sa1'});
      expect(find.textContaining('On for this device'), findsOneWidget);
      expect(find.text('Send a test'), findsOneWidget);
      expect(find.text('Turn on'), findsNothing);
    });

    testWidgets('says how to unblock notifications', (tester) async {
      state.pushPermission = PushPermission.denied;
      await pumpPage(tester);

      expect(
        find.textContaining('Notifications are blocked for SAIS'),
        findsOneWidget,
      );
      expect(find.text('Turn on'), findsNothing);
    });

    testWidgets('is not shown to staff', (tester) async {
      state.currentUser = _supervisor;
      await pumpPage(tester);

      expect(find.text('Clock-out reminders'), findsNothing);
    });
  });

  group('Notifications page', () {
    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(home: Scaffold(body: screen)),
        ),
      );
      await tester.pump();
    }

    testWidgets("offers phone notifications on a Supervisor's", (tester) async {
      state.currentUser = _supervisor;
      state.pushPermission = PushPermission.notAsked;
      await pumpScreen(tester, const SpNotificationsScreen());

      expect(find.text('Phone notifications'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(store.tokens, {'device-1': 'sup1'});
      expect(find.textContaining('On for this device'), findsOneWidget);
    });

    testWidgets('shows a test is sending until the server answers', (
      tester,
    ) async {
      state.currentUser = _supervisor;
      push.current = PushPermission.granted;
      await state.registerForPush();
      await pumpScreen(tester, const SpNotificationsScreen());

      await tester.tap(find.text('Send a test'));
      await tester.pump();

      expect(find.text('Sending…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Sending…'));
      expect(push.prompts, 0);

      push.test!.complete((ok: true, error: null));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.text('Send a test'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('A test notification arrives'),
        findsOneWidget,
      );
    });

    testWidgets("and on the Head's", (tester) async {
      state.currentUser = _head;
      state.pushPermission = PushPermission.notAsked;
      await pumpScreen(tester, const AdminNotificationsScreen());

      expect(find.text('Phone notifications'), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
    });
  });
}
