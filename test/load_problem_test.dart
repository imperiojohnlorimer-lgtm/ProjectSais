import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/screens/accounts/payroll_screen.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/dashboard/dashboard_screen.dart';
import 'package:projectsais/screens/student_portal/student_portal_shell.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/load_problem_banner.dart';

/// Firestore's live queries, one fresh stream per query opened (as Firestore
/// does), so a test can answer or fail each, and count how often one was
/// opened again.
class _Fake extends FirestoreService {
  final streams =
      <String, List<StreamController<List<Map<String, dynamic>>>>>{};
  final docs = <String, List<StreamController<Map<String, dynamic>?>>>{};

  Stream<List<Map<String, dynamic>>> _open(String key) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    (streams[key] ??= []).add(controller);
    return controller.stream;
  }

  int opened(String key) => streams[key]?.length ?? 0;

  void push(String key, [List<Map<String, dynamic>> data = const []]) =>
      streams[key]!.last.add(data);

  void fail(String key, String code) => streams[key]!.last.addError(
    FirebaseException(plugin: 'cloud_firestore', code: code),
  );

  /// Every query this session opened answers with nothing in it.
  void answerAll({Map<String, dynamic>? profile, String? profileId}) {
    for (final list in streams.values) {
      if (!list.last.isClosed) list.last.add(const []);
    }
    for (final entry in docs.entries) {
      final data = entry.key == 'users/$profileId' ? profile : null;
      if (!entry.value.last.isClosed) entry.value.last.add(data);
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> collectionStream(
    String collection, {
    bool newestFirst = false,
  }) => _open(collection);

  @override
  Stream<List<Map<String, dynamic>>> whereStream(
    String collection,
    String field,
    Object value, {
    bool newestFirst = false,
  }) => _open('$collection.$field=$value');

  @override
  Stream<List<Map<String, dynamic>>> whereInStream(
    String collection,
    String field,
    List<Object> values,
  ) => _open('$collection.$field in $values');

  @override
  Stream<Map<String, dynamic>?> docStream(String collection, String id) {
    final controller = StreamController<Map<String, dynamic>?>();
    (docs['$collection/$id'] ??= []).add(controller);
    return controller.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> announcementsStream() => _open('ann');

  @override
  Stream<List<Map<String, dynamic>>> attendanceStream() => _open('attendance');

  @override
  Stream<List<Map<String, dynamic>>> attendanceStreamForStudent(String uid) =>
      _open('attendance.$uid');

  @override
  Stream<List<Map<String, dynamic>>> tasksStream() => _open('tasks');

  @override
  Stream<List<Map<String, dynamic>>> applicationsStream() =>
      _open('applications');

  @override
  Stream<List<Map<String, dynamic>>> applicationsStreamForApplicant(
    String uid,
  ) => _open('applications.$uid');

  @override
  Stream<List<Map<String, dynamic>>> headForwardsStream() =>
      _open('headForwards');

  @override
  Stream<List<Map<String, dynamic>>> payrollRecordsStream() =>
      _open('payrollRecords');

  @override
  Stream<List<Map<String, dynamic>>> payrollSheetsStream() =>
      _open('payrollSheets');

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => [];
}

final _admin = User(
  id: 'admin1',
  name: 'Ana Admin',
  email: 'admin@example.com',
  role: 'Admin',
);
final _student = User(
  id: 'stu1',
  name: 'Sam Student',
  email: 'sam@example.com',
  role: 'Student',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<(AppState, _Fake)> _signedIn(User user) async {
  final fake = _Fake();
  final state = AppState(firestoreService: fake)..currentUser = user;
  await state.init();
  addTearDown(state.dispose);
  return (state, fake);
}

void main() {
  test('a failed query is reported, with the quota named', () async {
    final (state, fake) = await _signedIn(_admin);
    expect(state.hasLoadProblem, isFalse);

    fake.fail('attendance', 'resource-exhausted');
    await _settle();

    expect(state.hasLoadProblem, isTrue);
    expect(state.failedLoads, ['Attendance']);
    expect(state.loadProblemMessage, contains('free daily limit'));
  });

  test('any other failure gets the general message', () async {
    final (state, fake) = await _signedIn(_admin);

    fake.fail('reports', 'permission-denied');
    await _settle();

    expect(state.failedLoads, ['Reports']);
    expect(state.loadProblemMessage, contains('could not be loaded'));
  });

  test('the same query answering with data ends the problem', () async {
    final (state, fake) = await _signedIn(_admin);
    fake.fail('attendance', 'unavailable');
    await _settle();
    expect(state.hasLoadProblem, isTrue);

    fake.push('attendance');
    await _settle();

    expect(state.hasLoadProblem, isFalse);
    expect(state.loadProblemMessage, isNull);
  });

  test('a query that has not answered yet is not a problem', () async {
    final (state, _) = await _signedIn(_admin);

    expect(state.hasLoadProblem, isFalse);
  });

  test(
    'a student\'s by-name fallbacks are refused without a warning',
    () async {
      final (state, fake) = await _signedIn(_student);

      fake.fail('reports.studentName=Sam Student', 'permission-denied');
      fake.fail('tasks.assignedToName=Sam Student', 'permission-denied');
      await _settle();

      expect(state.hasLoadProblem, isFalse);
      // They count as answered, so nothing waits on them.
      expect(
        state.isLoaded('Reports'),
        isFalse,
      ); // 'Reports: own' still to come
      fake.push('reports.applicantId=stu1');
      await _settle();
      expect(state.isLoaded('Reports'), isTrue);
    },
  );

  test('a list the student does need failing is reported', () async {
    final (state, fake) = await _signedIn(_student);

    fake.fail('tasks.assignedTo=stu1', 'permission-denied');
    await _settle();

    expect(state.failedLoads, ['Tasks: own']);
  });

  test('a query that never answers is reported when the wait runs out', () {
    fakeAsync((async) {
      final fake = _Fake();
      final state = AppState(firestoreService: fake)..currentUser = _admin;
      state.init();
      async.flushMicrotasks();
      expect(state.hasLoadProblem, isFalse);

      async.elapse(AppState.loadTimeout + const Duration(seconds: 1));

      expect(state.failedLoads, contains('Attendance'));
      expect(state.payrollDataLoaded, isFalse);

      // Late data still ends the problem.
      fake.push('attendance');
      async.flushMicrotasks();
      expect(state.failedLoads, isNot(contains('Attendance')));
      state.dispose();
    });
  });

  test('a snapshot that cannot be read is a failure, not fresh data', () async {
    final (state, fake) = await _signedIn(_admin);
    fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
    await _settle();
    expect(state.payrollDataLoaded, isTrue);

    fake.push('attendance', [
      {'id': 'a1', 'totalHours': 'not a number'},
    ]);
    await _settle();

    expect(state.failedLoads, ['Attendance']);
    expect(state.payrollDataLoaded, isFalse);
  });

  test('a Supervisor does not ask for applications', () async {
    final sup = User(
      id: 's1',
      name: 'Sol Sup',
      email: 's@e.com',
      role: 'Supervisor',
    );
    final (state, fake) = await _signedIn(sup);

    expect(fake.opened('applications'), 0);
    expect(state.isLoaded('Applications'), isTrue);
  });

  test('a report is worked out only from records that all arrived', () async {
    final sup = User(
      id: 's1',
      name: 'Sol Sup',
      email: 's@e.com',
      role: 'Supervisor',
    );
    final (state, fake) = await _signedIn(sup);
    await _settle();
    expect(state.reportDataLoaded, isFalse);

    fake.answerAll(profile: sup.toJson(), profileId: sup.id);
    await _settle();
    expect(state.reportDataLoaded, isTrue);

    fake.fail('attendance', 'unavailable');
    await _settle();
    expect(state.reportDataLoaded, isFalse);
  });

  test('the saved payroll sheets count for opening a sheet', () async {
    final (state, fake) = await _signedIn(_admin);
    fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
    await _settle();
    expect(state.payrollSheetsLoaded, isTrue);

    fake.fail('payrollSheets', 'unavailable');
    await _settle();

    // Approving does not need them; opening a sheet does.
    expect(state.payrollDataLoaded, isTrue);
    expect(state.payrollSheetsLoaded, isFalse);
  });

  test('signing out clears the problem', () async {
    final (state, fake) = await _signedIn(_admin);
    fake.fail('attendance', 'unavailable');
    await _settle();

    state.logout();

    expect(state.hasLoadProblem, isFalse);
  });

  group('Try again', () {
    test('opens the queries afresh and finishes when they answer', () async {
      final (state, fake) = await _signedIn(_admin);
      fake.fail('attendance', 'unavailable');
      await _settle();
      expect(fake.opened('attendance'), 1);

      final retry = state.retryLoading();
      // A second tap joins the first instead of restarting again.
      expect(state.retryLoading(), same(retry));
      expect(fake.opened('attendance'), 2);
      expect(state.hasLoadProblem, isFalse, reason: 'cleared on restart');

      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      await retry;

      expect(state.hasLoadProblem, isFalse);
      expect(state.isLoaded('Attendance'), isTrue);
      expect(fake.opened('attendance'), 2);
    });

    test('a query that fails again is reported again', () async {
      final (state, fake) = await _signedIn(_admin);
      fake.fail('attendance', 'unavailable');
      await _settle();

      final retry = state.retryLoading();
      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      fake.fail('attendance', 'unavailable');
      await retry;

      expect(state.failedLoads, ['Attendance']);
    });

    test('does nothing when signed out', () async {
      final fake = _Fake();
      final state = AppState(firestoreService: fake);
      addTearDown(state.dispose);

      await state.retryLoading();

      expect(fake.opened('attendance'), 0);
    });
  });

  group('payroll', () {
    test('is not approved before the data has arrived', () async {
      final (state, _) = await _signedIn(_admin);

      expect(state.payrollDataLoaded, isFalse);
      await expectLater(state.approvePayroll([]), throwsStateError);
      await expectLater(state.releasePayroll([]), throwsStateError);
    });

    test('is approved once everything it needs has arrived', () async {
      final (state, fake) = await _signedIn(_admin);

      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      await _settle();

      expect(state.payrollDataLoaded, isTrue);
      expect((await state.approvePayroll([])).$1, 0);
    });

    test('is refused while attendance has failed', () async {
      final (state, fake) = await _signedIn(_admin);
      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      await _settle();

      fake.fail('attendance', 'resource-exhausted');
      await _settle();

      expect(state.payrollDataLoaded, isFalse);
      await expectLater(state.approvePayroll([]), throwsStateError);

      fake.push('attendance');
      await _settle();
      expect((await state.approvePayroll([])).$1, 0);
    });

    test('a retry does not let stale data pass before it answers', () async {
      final (state, fake) = await _signedIn(_admin);
      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      await _settle();
      expect(state.payrollDataLoaded, isTrue);

      final retry = state.retryLoading();

      expect(state.payrollDataLoaded, isFalse);
      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      await retry;
      expect(state.payrollDataLoaded, isTrue);
    });
  });

  group('the banner', () {
    Widget host(AppState state) => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: const Column(children: [LoadProblemBanner(), Text('page')]),
        ),
      ),
    );

    // The state's own timers must be gone before a widget test ends.
    Future<void> finish(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    }

    testWidgets('shows nothing while all is well', (tester) async {
      final fake = _Fake();
      final state = AppState(firestoreService: fake)..currentUser = _admin;
      await tester.runAsync(state.init);

      await tester.pumpWidget(host(state));

      expect(find.text('Try again'), findsNothing);
      await finish(tester, state);
    });

    testWidgets('says what failed and tries again on tap', (tester) async {
      final fake = _Fake();
      final state = AppState(firestoreService: fake)..currentUser = _admin;
      await tester.runAsync(state.init);
      await tester.pumpWidget(host(state));

      fake.fail('attendance', 'resource-exhausted');
      await tester.runAsync(_settle);
      await tester.pump();

      expect(find.textContaining('free daily limit'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.textContaining('Trying to load'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(fake.opened('attendance'), 2);

      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      await tester.runAsync(_settle);
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('free daily limit'), findsNothing);
      await finish(tester, state);
    });
  });

  group('the shell of each role', () {
    // (role, who signs in, the query to fail, the shell)
    final cases = <(String, User, String, Widget)>[
      ('Admin', _admin, 'attendance', const AppShell()),
      (
        'Head',
        User(id: 'h1', name: 'Hana Head', email: 'h@e.com', role: 'Head'),
        'attendance',
        const AppShell(),
      ),
      (
        'Supervisor',
        User(id: 's1', name: 'Sol Sup', email: 's@e.com', role: 'Supervisor'),
        'attendance',
        const AppShell(),
      ),
      (
        'Student Assistant',
        User(
          id: 'sa1',
          name: 'Sia Assistant',
          email: 'sa@e.com',
          role: 'Student Assistant',
        ),
        'attendance.sa1',
        const AppShell(),
      ),
      (
        'Student',
        _student,
        'tasks.assignedTo=stu1',
        const StudentPortalShell(),
      ),
    ];

    for (final (role, user, key, shell) in cases) {
      testWidgets('shows the banner for the $role', (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final onError = FlutterError.onError;
        // The test font draws every glyph as a full square, so some rows
        // overflow here though they fit in the app.
        FlutterError.onError = (details) =>
            details.exceptionAsString().contains('overflowed')
            ? null
            : onError?.call(details);
        addTearDown(() => FlutterError.onError = onError);
        final fake = _Fake();
        final state = AppState(firestoreService: fake)..currentUser = user;
        await tester.runAsync(state.init);
        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: state,
            child: MaterialApp(theme: AppTheme.theme, home: shell),
          ),
        );
        expect(find.text('Try again'), findsNothing);

        fake.fail(key, 'permission-denied');
        await tester.runAsync(_settle);
        await tester.pump();
        FlutterError.onError = onError;

        expect(find.textContaining('could not be loaded'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
    }
  });

  group('the Student Assistant\'s office card', () {
    final assistant = User(
      id: 'sa1',
      name: 'Sia Assistant',
      email: 'sa@e.com',
      role: 'Student Assistant',
    );

    Future<(AppState, _Fake)> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      // The test font draws every glyph as a full square, so some rows
      // overflow here though they fit in the app.
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
      final fake = _Fake();
      final state = AppState(firestoreService: fake)..currentUser = assistant;
      await tester.runAsync(state.init);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      return (state, fake);
    }

    Future<void> close(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    }

    testWidgets('waits for the offices, then says the student is not placed', (
      tester,
    ) async {
      final (state, fake) = await open(tester);
      expect(find.text('My Office'), findsNothing);

      fake.answerAll(profile: assistant.toJson(), profileId: assistant.id);
      await tester.runAsync(_settle);
      await tester.pump();

      expect(find.text('My Office'), findsOneWidget);
      expect(
        find.textContaining("not placed in an office yet"),
        findsOneWidget,
      );
      await close(tester, state);
    });

    testWidgets('is hidden when the offices could not be loaded', (
      tester,
    ) async {
      final (state, fake) = await open(tester);

      fake.fail('offices', 'permission-denied');
      await tester.runAsync(_settle);
      await tester.pump();

      expect(find.text('My Office'), findsNothing);
      expect(find.textContaining('not placed'), findsNothing);
      await close(tester, state);
    });
  });

  testWidgets(
    'Prepare Payroll Sheet waits until the payroll data has arrived',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late AppState state;
      late _Fake fake;
      await tester.runAsync(() async {
        (state, fake) = await _signedIn(_admin);
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: PayrollScreen()),
          ),
        ),
      );

      expect(find.text('Loading payroll data…'), findsOneWidget);
      expect(find.text('Prepare Payroll Sheet'), findsNothing);

      fake.answerAll(profile: _admin.toJson(), profileId: _admin.id);
      await tester.pump();
      await tester.pump();

      expect(find.text('Prepare Payroll Sheet'), findsOneWidget);
      state.logout();
    },
  );
}
