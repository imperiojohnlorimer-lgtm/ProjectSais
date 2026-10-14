import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/task_duty.dart';
import 'package:projectsais/screens/supervisor/dtr_accomplishment_report_screen.dart';
import 'package:projectsais/screens/tasks/assign_task_sheet.dart';
import 'package:projectsais/screens/tasks/tasks_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Keeps the duties, tasks and notifications the app saves in memory, and
/// refuses every save while [fail] is set.
class _Store extends FirestoreService {
  bool fail = false;
  final duties = <String, TaskDuty>{};
  final logs = <Task>[];
  final tasks = <Task>[];
  final active = <String, bool>{};
  final notifications = <Map<String, dynamic>>[];

  @override
  Future<void> setTaskDuty(TaskDuty duty) async {
    if (fail) throw Exception('permission-denied');
    duties[duty.id] = duty;
  }

  @override
  Future<void> renameTaskCategory(
    List<String> names, {
    required String from,
    required String to,
    required List<String> taskIds,
    List<String> dutyIds = const [],
  }) async {
    if (fail) throw Exception('permission-denied');
  }

  @override
  Future<void> setTaskDutyActive(String id, bool value) async {
    if (fail) throw Exception('permission-denied');
    active[id] = value;
  }

  @override
  Future<void> createDutyLog(Task t) async {
    if (fail) throw Exception('permission-denied');
    logs.add(t);
  }

  @override
  Future<void> setTask(Task t) async {
    if (fail) throw Exception('permission-denied');
    tasks.add(t);
  }

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);
}

final _supervisor = User(
  id: 'sup1',
  name: 'Sid Supervisor',
  email: 'sup@example.com',
  role: 'Supervisor',
);
final _assistant = User(
  id: 'sa1',
  name: 'Sara Assistant',
  email: 'sa@example.com',
  role: 'Student Assistant',
);

TaskDuty _duty({
  String id = 'duty1',
  bool active = true,
  String year = '2026-2027',
}) => TaskDuty(
  id: id,
  title: 'Receive documents',
  description: 'Receive and log the incoming documents.',
  priority: 'High',
  category: 'Administrative',
  assignedTo: 'sa1',
  assignedToName: 'Sara Assistant',
  assignedBy: 'sup1',
  academicYear: year,
  active: active,
);

AttendanceRecord _clockIn(
  AppState state, {
  String? date,
  bool archived = false,
}) => AttendanceRecord(
  id: 'att1',
  studentName: 'Sara Assistant',
  studentId: 'sa1',
  date: date ?? state.philippineToday(),
  timeIn: '8:00 AM',
  isArchived: archived,
);

AppState _studentState(_Store store, {bool clockedIn = true}) {
  final state = AppState(firestoreService: store)
    ..currentUser = _assistant
    ..users = [_assistant, _supervisor]
    ..taskDuties = [_duty()];
  if (clockedIn) state.attendance = [_clockIn(state)];
  return state;
}

Task _approvedLog(String today) => Task(
  id: 'dutylog_duty1_x',
  title: 'Receive documents',
  description: 'Logged 12 documents',
  status: 'Completed',
  priority: 'High',
  dueDate: today,
  assignedTo: 's1',
  assignedToName: 'Charlie A. Matining',
  assignedBy: 'sup1',
  completedAt: today,
  reviewStatus: 'Approved',
  dutyId: 'duty1',
  attendanceId: 'r1',
  workDate: today,
);

void main() {
  group('logging an ongoing duty', () {
    test('a clocked-in student logs the day for approval', () async {
      final store = _Store();
      final state = _studentState(store);

      final problem = await state.logDutyWork(
        state.taskDuties.single,
        note: '  Logged 12 documents ',
      );

      expect(problem, isNull);
      final log = store.logs.single;
      final day = state.philippineToday();
      expect(log.id, startsWith('dutylog_duty1_'));
      expect(log.title, 'Receive documents');
      expect(log.description, 'Logged 12 documents');
      expect(log.status, 'Completed');
      expect(log.reviewStatus, 'Pending');
      expect(log.assignedTo, 'sa1');
      expect(log.assignedBy, 'sup1');
      expect(log.category, 'Administrative');
      expect(log.completedAt, day);
      expect(log.workDate, day);
      expect(log.dutyId, 'duty1');
      expect(log.attendanceId, 'att1');
      expect(log.isDutyLog, isTrue);
      expect(log.awaitingApproval, isTrue);
      // It is a normal task of theirs now, waiting for the supervisor.
      expect(state.tasks.single.id, log.id);
      expect(store.notifications.single['title'], 'Task Awaiting Approval');
      expect(store.notifications.single['userId'], 'sup1');
      expect(store.tasks, isEmpty, reason: 'saved as a log, not a plain task');
    });

    test('without a clock-in today nothing is made', () async {
      final store = _Store();
      final state = _studentState(store, clockedIn: false);

      final problem = await state.logDutyWork(state.taskDuties.single);

      expect(problem, contains('Clock in first'));
      expect(store.logs, isEmpty);
      expect(state.tasks, isEmpty);
    });

    test("yesterday's or an archived clock-in does not count", () async {
      final store = _Store();
      final state = _studentState(store, clockedIn: false)
        ..attendance = [
          _clockIn(
            AppState(firestoreService: store),
            date: AppState(
              firestoreService: store,
            ).philippineToday(DateTime.now().subtract(const Duration(days: 1))),
          ),
        ];
      expect(await state.logDutyWork(state.taskDuties.single), isNotNull);

      state.attendance = [_clockIn(state, archived: true)];
      expect(await state.logDutyWork(state.taskDuties.single), isNotNull);
      expect(store.logs, isEmpty);
    });

    test('a missed time-out does not stop the log', () async {
      final store = _Store();
      final state = _studentState(store)
        ..attendance = [
          AttendanceRecord(
            id: 'att1',
            studentName: 'Sara Assistant',
            studentId: 'sa1',
            date: AppState(firestoreService: store).philippineToday(),
            timeIn: '8:00 AM',
            isInvalid: true,
          ),
        ];

      expect(await state.logDutyWork(state.taskDuties.single), isNull);
    });

    test('a day can be logged only once', () async {
      final store = _Store();
      final state = _studentState(store);

      expect(await state.logDutyWork(state.taskDuties.single), isNull);
      expect(
        await state.logDutyWork(state.taskDuties.single),
        contains('already logged'),
      );

      expect(store.logs, hasLength(1));
    });

    test('a stopped duty, or one from last year, cannot be logged', () async {
      final store = _Store();
      final state = _studentState(store);

      expect(await state.logDutyWork(_duty(active: false)), isNotNull);
      expect(await state.logDutyWork(_duty(year: '2025-2026')), isNotNull);
      expect(state.dutiesToLog, hasLength(1));
      state.taskDuties = [
        _duty(active: false),
        _duty(id: 'old', year: '2025-2026'),
      ];
      expect(state.dutiesToLog, isEmpty);
    });

    test('a failed save leaves nothing behind and does not notify', () async {
      final store = _Store()..fail = true;
      final state = _studentState(store);

      final problem = await state.logDutyWork(state.taskDuties.single);

      expect(problem, contains("Couldn't save"));
      expect(state.tasks, isEmpty);
      expect(store.notifications, isEmpty);
    });

    test('someone else cannot log it', () async {
      final store = _Store();
      final state = _studentState(store)
        ..currentUser = User(
          id: 'sa2',
          name: 'Other',
          email: 'o@example.com',
          role: 'Student Assistant',
        );

      expect(await state.logDutyWork(state.taskDuties.single), isNotNull);
    });

    test('a rejected log is completed again for its own day', () async {
      final store = _Store();
      final state = _studentState(store);
      await state.logDutyWork(state.taskDuties.single);
      final logId = state.tasks.single.id;
      // The supervisor sends it back: it is In Progress with no date.
      state.tasks = [
        state.tasks.single.copyWith(
          status: 'In Progress',
          clearCompletedAt: true,
          resetReview: true,
          reviewStatus: 'Rejected',
        ),
      ];

      await state.updateTaskStatus(logId, 'Completed');

      final again = state.tasks.single;
      expect(again.completedAt, state.philippineToday());
      expect(again.workDate, state.philippineToday());
      expect(again.reviewStatus, 'Pending');
    });
  });

  group('sending a rejected log again', () {
    Future<AppState> rejected(_Store store) async {
      final state = _studentState(store);
      await state.logDutyWork(state.taskDuties.single, note: 'Wrong count');
      state.tasks = [
        state.tasks.single.copyWith(
          status: 'In Progress',
          clearCompletedAt: true,
          resetReview: true,
          reviewStatus: 'Rejected',
        ),
      ];
      store.tasks.clear();
      store.notifications.clear();
      return state;
    }

    test('the note can be corrected and the day is kept', () async {
      final store = _Store();
      final state = await rejected(store);

      final problem = await state.resubmitDutyLog(
        state.tasks.single,
        note: ' Logged 14 documents ',
      );

      expect(problem, isNull);
      final sent = state.tasks.single;
      expect(sent.description, 'Logged 14 documents');
      expect(sent.status, 'Completed');
      expect(sent.completedAt, state.philippineToday());
      expect(sent.reviewStatus, 'Pending');
      expect(store.tasks.single.description, 'Logged 14 documents');
      expect(store.notifications.single['title'], 'Task Awaiting Approval');
    });

    test('a log that was not rejected cannot be sent again', () async {
      final store = _Store();
      final state = _studentState(store);
      await state.logDutyWork(state.taskDuties.single);

      expect(
        await state.resubmitDutyLog(state.tasks.single, note: 'x'),
        isNotNull,
      );
    });

    test('a failed resend restores the rejected log', () async {
      final store = _Store();
      final state = await rejected(store);
      store.fail = true;

      expect(
        await state.resubmitDutyLog(state.tasks.single, note: 'Fixed'),
        isNotNull,
      );

      expect(state.tasks.single.status, 'In Progress');
      expect(state.tasks.single.description, 'Wrong count');
    });
  });

  group('who is told about a log', () {
    test('the supervisor of the office now, not the one who gave it', () async {
      final store = _Store();
      final state = _studentState(store)
        ..users = [_assistant, _supervisor]
        ..offices = [
          const Office(
            id: 'o2',
            name: 'Library',
            code: 'LIB',
            headIds: ['sup2'],
            headNames: ['New Supervisor'],
            assistantIds: ['sa1'],
            assistantNames: ['Sara Assistant'],
          ),
        ];

      await state.logDutyWork(state.taskDuties.single);

      expect(store.notifications.map((n) => n['userId']), ['sup2']);
    });

    test('a failed log removes only that log', () async {
      final store = _Store()..fail = true;
      final state = _studentState(store)
        ..tasks = [
          Task(
            id: 'other',
            title: 'Other',
            description: '',
            status: 'Not Started',
            priority: 'Low',
            dueDate: 'x',
            assignedTo: 'sa1',
          ),
        ];

      await state.logDutyWork(state.taskDuties.single);

      expect(state.tasks.map((t) => t.id), ['other']);
    });

    test('a supervisor who no longer heads the student sees no duty', () {
      final state = AppState(firestoreService: _Store())
        ..currentUser = _supervisor
        ..users = [_assistant, _supervisor]
        ..taskDuties = [_duty()];

      expect(state.filteredDuties, isEmpty);
    });
  });

  group('categories and ongoing duties', () {
    test('renaming a category moves its duties too', () async {
      final store = _Store();
      final state = AppState(firestoreService: store)..taskDuties = [_duty()];

      expect(
        await state.renameTaskCategory('Administrative', 'Office Work'),
        isNull,
      );

      expect(state.taskDuties.single.category, 'Office Work');
    });

    test('a category with an ongoing duty cannot be deleted', () async {
      final state = AppState(firestoreService: _Store())
        ..taskDuties = [_duty()];

      expect(
        await state.deleteTaskCategory('Administrative'),
        contains('ongoing duty'),
      );
    });
  });

  group('giving and stopping an ongoing duty', () {
    AppState supervisorState(_Store store) => AppState(firestoreService: store)
      ..currentUser = _supervisor
      ..users = [_assistant, _supervisor];

    final student = Student(
      id: 'sa1',
      name: 'Sara Assistant',
      email: 'sa@example.com',
      department: 'CICS',
    );

    test(
      'the supervisor gives a student a duty and the student hears',
      () async {
        final store = _Store();
        final state = supervisorState(store);

        final problem = await state.createTaskDuty(
          title: ' Receive documents ',
          description: 'Log them.',
          priority: 'High',
          category: 'Administrative',
          student: student,
        );

        expect(problem, isNull);
        final saved = store.duties.values.single;
        expect(saved.title, 'Receive documents');
        expect(saved.assignedTo, 'sa1');
        expect(saved.assignedBy, 'sup1');
        expect(saved.academicYear, '2026-2027');
        expect(saved.active, isTrue);
        expect(state.taskDuties.single.id, saved.id);
        expect(store.notifications.single['userId'], 'sa1');
        expect(store.notifications.single['title'], 'New Ongoing Duty');
      },
    );

    test('a duty needs a title, an account and no twin', () async {
      final store = _Store();
      final state = supervisorState(store);

      expect(
        await state.createTaskDuty(
          title: ' ',
          description: '',
          priority: 'Low',
          category: 'General',
          student: student,
        ),
        isNotNull,
      );
      expect(
        await state.createTaskDuty(
          title: 'Filing',
          description: '',
          priority: 'Low',
          category: 'General',
          student: Student(
            id: 'ghost',
            name: 'No Account',
            email: 'g@example.com',
            department: 'CICS',
          ),
        ),
        contains('no Student Assistant account'),
      );
      expect(
        await state.createTaskDuty(
          title: 'Filing',
          description: '',
          priority: 'Low',
          category: 'General',
          student: student,
        ),
        isNull,
      );
      expect(
        await state.createTaskDuty(
          title: 'FILING',
          description: '',
          priority: 'Low',
          category: 'General',
          student: student,
        ),
        contains('already has an ongoing duty'),
      );
      expect(store.duties, hasLength(1));
    });

    test('a failed save gives no duty and no notice', () async {
      final store = _Store()..fail = true;
      final state = supervisorState(store);

      final problem = await state.createTaskDuty(
        title: 'Filing',
        description: '',
        priority: 'Low',
        category: 'General',
        student: student,
      );

      expect(problem, contains("Couldn't save"));
      expect(state.taskDuties, isEmpty);
      expect(store.notifications, isEmpty);
    });

    test('stopping a duty is undone when the save is refused', () async {
      final store = _Store();
      final state = supervisorState(store)..taskDuties = [_duty()];

      expect(await state.setTaskDutyActive('duty1', false), isTrue);
      expect(state.taskDuties.single.active, isFalse);
      expect(store.active['duty1'], isFalse);

      store.fail = true;
      expect(await state.setTaskDutyActive('duty1', true), isFalse);
      expect(state.taskDuties.single.active, isFalse);
    });
  });

  group('the Tasks page', () {
    Future<AppState> open(
      WidgetTester tester,
      AppState state, {
      Size size = const Size(1000, 1200),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: TasksScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('a clocked-in student logs their work from the panel', (
      tester,
    ) async {
      final store = _Store();
      await open(tester, _studentState(store));

      expect(find.text('Ongoing duties'), findsOneWidget);
      expect(
        find.text("You're clocked in. Log what you did today."),
        findsOneWidget,
      );
      await tester.tap(find.text("Log today's work").last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Logged 12 documents',
      );
      await tester.tap(find.text('Send for approval'));
      await tester.pumpAndSettle();

      expect(store.logs.single.description, 'Logged 12 documents');
      expect(find.text('Today: logged, waiting for approval'), findsOneWidget);
      // The log is a task card now, tagged as an ongoing duty, and never late.
      expect(find.text('Ongoing duty'), findsWidgets);
      expect(find.text('OVERDUE'), findsNothing);
    });

    testWidgets('without a clock-in the button is disabled', (tester) async {
      final store = _Store();
      await open(tester, _studentState(store, clockedIn: false));

      expect(find.text('Clock in to log your work for today.'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text("Log today's work"),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the supervisor sees their duties and stops one', (
      tester,
    ) async {
      final store = _Store();
      final state = AppState(firestoreService: store)
        ..currentUser = _supervisor
        ..users = [_assistant, _supervisor]
        ..offices = [
          const Office(
            id: 'o1',
            name: 'CICS Office',
            code: 'CICS',
            headIds: ['sup1'],
            headNames: ['Sid Supervisor'],
            assistantIds: ['sa1'],
            assistantNames: ['Sara Assistant'],
          ),
        ]
        ..taskDuties = [_duty()];
      await open(tester, state);

      expect(find.text('Ongoing duties'), findsOneWidget);
      expect(find.textContaining('Sara Assistant'), findsWidgets);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop').last);
      await tester.pumpAndSettle();

      expect(store.active['duty1'], isFalse);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('the panel fits a phone', (tester) async {
      final store = _Store();
      await open(tester, _studentState(store), size: const Size(390, 900));

      expect(tester.takeException(), isNull);
      expect(find.text("Log today's work"), findsOneWidget);
    });
  });

  group('Assign Task sheet', () {
    testWidgets('an ongoing duty needs no due date and goes to the student', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = _Store();
      final state = AppState(firestoreService: store)
        ..currentUser = _supervisor
        ..users = [_assistant, _supervisor]
        ..offices = [
          const Office(
            id: 'o1',
            name: 'CICS Office',
            code: 'CICS',
            headIds: ['sup1'],
            headNames: ['Sid Supervisor'],
            assistantIds: ['sa1'],
            assistantNames: ['Sara Assistant'],
          ),
        ]
        ..students = [
          Student(
            id: 'sa1',
            name: 'Sara Assistant',
            email: 'sa@example.com',
            department: 'CICS',
            userId: 'sa1',
          ),
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAssignTaskSheet(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Due date'), findsOneWidget);
      await tester.tap(find.text('Ongoing duty'));
      await tester.pumpAndSettle();
      expect(find.text('Due date'), findsNothing);
      expect(find.text('Give Ongoing Duty'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Task title'),
        'Receive documents',
      );
      // No student chosen yet.
      await tester.tap(find.text('Give Ongoing Duty'));
      await tester.pumpAndSettle();
      expect(find.text('Choose who this ongoing duty is for.'), findsOneWidget);

      await tester.tap(find.text('Assign to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sara Assistant').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give Ongoing Duty'));
      await tester.pumpAndSettle();

      expect(store.duties.values.single.title, 'Receive documents');
      expect(store.tasks, isEmpty, reason: 'a duty is not a one-off task');
    });
  });

  group('DTR/Accomplishment Report', () {
    Future<void> pumpDtr(
      WidgetTester tester, {
      bool missedTimeOut = false,
    }) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final head = User(
        id: 'h1',
        name: 'Maria Head',
        email: 'head@marsu.edu.ph',
        role: 'Head',
      );
      final probe = AppState();
      final today = probe.philippineToday();
      final state = AppState()
        ..currentUser = head
        ..users = [head]
        ..tasks = [_approvedLog(today)]
        ..attendance = [
          AttendanceRecord(
            id: 'r1',
            studentId: 's1',
            studentName: 'Charlie A. Matining',
            date: today,
            timeIn: '8:00 AM',
            timeOut: missedTimeOut ? null : '10:00 AM',
            totalHours: missedTimeOut ? null : 2,
            isInvalid: missedTimeOut,
          ),
        ]
        ..students = [
          Student(
            id: 's1',
            name: 'Charlie A. Matining',
            email: 'charlie@marsu.edu.ph',
            department: 'College of Information and Computing Sciences',
          ),
        ];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider(
              create: (_) => ScheduleService(InMemoryScheduleRepository()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: DtrAccomplishmentReportScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Report').first);
      await tester.pumpAndSettle();
    }

    testWidgets("an approved duty log shows the student's note", (
      tester,
    ) async {
      await pumpDtr(tester);

      final entry = find.text('Receive documents (Logged 12 documents)');
      await tester.dragUntilVisible(
        entry,
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      expect(entry, findsOneWidget);
    });

    testWidgets('a missed time-out keeps the warning beside the work', (
      tester,
    ) async {
      await pumpDtr(tester, missedTimeOut: true);

      final entry = find.textContaining(
        'Missed time-out — please record the time-out. Approved work: '
        'Receive documents (Logged 12 documents)',
      );
      await tester.dragUntilVisible(
        entry,
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      expect(entry, findsOneWidget);
    });
  });
}
