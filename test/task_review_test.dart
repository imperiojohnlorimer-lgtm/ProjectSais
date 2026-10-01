import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/reports/reports_screen.dart';
import 'package:projectsais/screens/supervisor/dtr_accomplishment_report_screen.dart';
import 'package:projectsais/screens/tasks/tasks_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Keeps the tasks, reports and notifications the app saves in memory, and
/// refuses every save while [fail] is set.
class _Store extends FirestoreService {
  bool fail = false;
  final tasks = <String, Task>{};
  final reports = <String, Report>{};
  final notifications = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> sentTo(String userId) =>
      notifications.where((n) => n['userId'] == userId).toList();

  @override
  Future<void> setTask(Task t) async {
    if (fail) throw Exception('permission-denied');
    tasks[t.id] = t;
  }

  @override
  Future<void> setReport(Report r) async {
    if (fail) throw Exception('permission-denied');
    reports[r.id] = r;
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

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Oct 1, 2026", the way tasks and attendance store a date.
String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

final _today = _day(DateTime.now());

Task _task({
  String id = 't1',
  String title = 'File the forms',
  String status = 'Not Started',
  String? completedAt,
  String? reviewStatus,
  String? reviewNote,
  String assignedTo = 'sa1',
  bool archived = false,
}) => Task(
  id: id,
  title: title,
  description: '',
  status: status,
  priority: 'Medium',
  dueDate: 'Oct 30, 2026',
  assignedTo: assignedTo,
  assignedToName: 'Sara Assistant',
  assignedBy: 'sup1',
  isArchived: archived,
  completedAt: completedAt,
  reviewStatus: reviewStatus,
  reviewNote: reviewNote,
);

Task _waiting({String id = 't1', String title = 'File the forms'}) => _task(
  id: id,
  title: title,
  status: 'Completed',
  completedAt: _today,
  reviewStatus: 'Pending',
);

Task _approved({
  String id = 't1',
  String title = 'File the forms',
  String? completedAt,
  String assignedTo = 'sa1',
}) => _task(
  id: id,
  title: title,
  status: 'Completed',
  completedAt: completedAt ?? _today,
  reviewStatus: 'Approved',
  assignedTo: assignedTo,
);

Report _report(
  String id, {
  String status = 'Pending',
  List<String> taskIds = const [],
  String content = '',
}) => Report(
  id: id,
  applicantId: 'sa1',
  title: 'Report $id',
  content: content,
  studentName: 'Sara Assistant',
  status: status,
  taskIds: taskIds,
);

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store();
    state = AppState(firestoreService: store);
  });

  group('the student', () {
    setUp(() => state.currentUser = _assistant);

    test('sends a completed task for approval', () async {
      state.tasks = [_task()];

      expect(await state.updateTaskStatus('t1', 'Completed'), isTrue);

      final task = store.tasks['t1']!;
      expect(task.status, 'Completed');
      expect(task.reviewStatus, 'Pending');
      expect(task.completedAt, _today);
      expect(task.awaitingApproval, isTrue);
      expect(store.sentTo('sup1').single['title'], 'Task Awaiting Approval');
    });

    test('can take a task back before it is approved', () async {
      state.tasks = [_waiting()];

      await state.updateTaskStatus('t1', 'In Progress');

      final task = store.tasks['t1']!;
      expect(task.reviewStatus, isNull);
      expect(task.completedAt, isNull);
      expect(task.awaitingApproval, isFalse);
    });

    test('can no longer change an approved task', () async {
      state.tasks = [_approved()];

      expect(await state.updateTaskStatus('t1', 'In Progress'), isFalse);

      expect(state.tasks.single.isApproved, isTrue);
      expect(store.tasks, isEmpty);
      expect(store.notifications, isEmpty);
    });

    test('keeps a rejection note while working on the task', () async {
      state.tasks = [
        _task(
          status: 'In Progress',
          reviewStatus: 'Rejected',
          reviewNote: 'Page 2 is missing',
        ),
      ];

      await state.updateTaskStatus('t1', 'Not Started');

      expect(store.tasks['t1']!.wasRejected, isTrue);
      expect(store.tasks['t1']!.reviewNote, 'Page 2 is missing');
    });

    test('clears the rejection by completing the task again', () async {
      state.tasks = [
        _task(
          status: 'In Progress',
          reviewStatus: 'Rejected',
          reviewNote: 'Page 2 is missing',
        ),
      ];

      await state.updateTaskStatus('t1', 'Completed');

      final task = store.tasks['t1']!;
      expect(task.reviewStatus, 'Pending');
      expect(task.reviewNote, isNull);
      expect(task.reviewedAt, isNull);
    });
  });

  group('the supervisor', () {
    setUp(() => state.currentUser = _supervisor);

    test('approves a completed task and tells the student', () async {
      state.tasks = [_waiting()];

      expect(await state.reviewTask('t1', approve: true), isTrue);

      final task = store.tasks['t1']!;
      expect(task.status, 'Completed');
      expect(task.isApproved, isTrue);
      expect(task.completedAt, _today);
      expect(task.reviewedBy, 'sup1');
      expect(task.reviewedAt, _today);
      expect(store.sentTo('sa1').single['title'], 'Task Approved');
    });

    test('rejects a task back to In Progress with the reason', () async {
      state.tasks = [_waiting()];

      final ok = await state.reviewTask(
        't1',
        approve: false,
        note: ' Page 2 is missing ',
      );

      expect(ok, isTrue);
      final task = store.tasks['t1']!;
      expect(task.status, 'In Progress');
      expect(task.completedAt, isNull);
      expect(task.wasRejected, isTrue);
      expect(task.reviewNote, 'Page 2 is missing');
      final sent = store.sentTo('sa1').single;
      expect(sent['title'], 'Task Rejected');
      expect(sent['message'], endsWith('Reason: Page 2 is missing'));
    });

    test('reviews a task completed before approvals existed', () async {
      state.tasks = [_task(status: 'Completed', completedAt: 'Sep 25, 2026')];

      expect(state.tasks.single.awaitingApproval, isTrue);
      expect(await state.reviewTask('t1', approve: true), isTrue);
      expect(store.tasks['t1']!.isApproved, isTrue);
    });

    test('can only review a task waiting for approval', () async {
      state.tasks = [_task(status: 'In Progress'), _approved(id: 't2')];

      expect(await state.reviewTask('t1', approve: true), isFalse);
      expect(await state.reviewTask('t2', approve: false), isFalse);
      expect(store.tasks, isEmpty);
    });

    test('sees a refused review undone, and nobody is told', () async {
      store.fail = true;
      state.tasks = [_waiting()];

      expect(await state.reviewTask('t1', approve: true), isFalse);

      expect(state.tasks.single.awaitingApproval, isTrue);
      expect(store.notifications, isEmpty);
    });
  });

  group('tasks offered for a report', () {
    setUp(() => state.currentUser = _assistant);

    test('are approved ones not already in a report', () {
      state.tasks = [
        _approved(id: 'a', title: 'Shelve returns'),
        _waiting(id: 'b', title: 'Waiting'),
        _task(id: 'c', title: 'Not done'),
        _approved(id: 'd', title: 'In a pending report'),
        _approved(id: 'e', title: 'In an approved report'),
        _approved(id: 'f', title: 'In a rejected report'),
        _approved(id: 'g', title: 'Archived').copyWith(isArchived: true),
      ];
      state.reports = [
        _report('r1', taskIds: ['d']),
        _report('r2', status: 'Approved', taskIds: ['e']),
        _report('r3', status: 'Rejected', taskIds: ['f']),
      ];

      expect(
        state.reportableTasks.map((t) => t.title),
        unorderedEquals(['Shelve returns', 'In a rejected report']),
      );
    });

    test('leave out tasks named in older reports', () {
      state.tasks = [
        _approved(id: 'a', title: 'Shelve returns'),
        _approved(id: 'b', title: 'Sort the mail'),
      ];
      // Written before reports recorded their tasks.
      state.reports = [
        _report('r1', content: '• Shelve returns — the morning batch'),
      ];

      expect(state.reportableTasks.map((t) => t.title), ['Sort the mail']);
    });

    test('come most recently completed first', () {
      state.tasks = [
        _approved(id: 'a', title: 'Older', completedAt: 'Sep 30, 2026'),
        _approved(id: 'b', title: 'Newer', completedAt: 'Oct 1, 2026'),
        _approved(id: 'c', title: 'Oldest', completedAt: 'Sep 9, 2026'),
      ];

      expect(state.reportableTasks.map((t) => t.title), [
        'Newer',
        'Older',
        'Oldest',
      ]);
    });

    test("stay used when the supervisor approves the report", () async {
      state
        ..currentUser = _supervisor
        ..reports = [
          _report('r1', taskIds: ['a']),
        ];

      await state.updateReportStatus('r1', 'Approved');

      expect(store.reports['r1']!.taskIds, ['a']);
    });

    test('are recorded when a report is read back', () {
      final report = Report.fromJson({
        'id': 'r1',
        'title': 'Week 1',
        'content': '',
        'studentName': 'Sara Assistant',
        'taskIds': ['a', 'b'],
      });
      expect(report.taskIds, ['a', 'b']);
      expect(Report.fromJson({'id': 'r2'}).taskIds, isEmpty);
    });
  });

  group('Tasks screen', () {
    Future<void> pumpTasks(
      WidgetTester tester,
      User user,
      List<Task> tasks, {
      double width = 1280,
    }) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      state
        ..currentUser = user
        ..users = [_supervisor, _assistant]
        ..students = [
          Student(
            id: 'sa1',
            name: 'Sara Assistant',
            email: 'sa@example.com',
            department: 'CICS',
            userId: 'sa1',
          ),
        ]
        ..offices = [
          const Office(
            id: 'o1',
            name: 'Library',
            code: 'LIB',
            headIds: ['sup1'],
            assistantIds: ['sa1'],
          ),
        ]
        ..tasks = tasks;
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
    }

    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'a supervisor sees Approve and Reject at ${width.toInt()}px',
        (tester) async {
          // The test font draws every glyph as a full square, so the
          // progress strip's label overflows at phone width though it fits
          // in the app. Only an overflow anywhere else fails this test.
          final overflows = <String>[];
          final onError = FlutterError.onError;
          FlutterError.onError = (details) =>
              details.exceptionAsString().contains('overflowed')
              ? overflows.add(
                  [
                    ...?details.informationCollector?.call().map(
                      (n) => n.toStringDeep(),
                    ),
                  ].join('\n'),
                )
              : onError?.call(details);
          try {
            await pumpTasks(tester, _supervisor, [_waiting()], width: width);
          } finally {
            FlutterError.onError = onError;
          }

          expect(
            overflows.where((o) => !o.contains('_ProgressSummary')),
            isEmpty,
          );
          expect(find.text('For Approval'), findsWidgets);
          expect(find.text('Approve'), findsOneWidget);
          expect(find.text('Reject'), findsOneWidget);
          expect(find.text('Completed: $_today'), findsOneWidget);
        },
      );
    }

    testWidgets('a supervisor approves a task', (tester) async {
      await pumpTasks(tester, _supervisor, [_waiting()]);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Approve Task'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve').last);
      await tester.pumpAndSettle();

      expect(store.tasks['t1']!.isApproved, isTrue);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('on $_today'), findsOneWidget);
    });

    testWidgets('a supervisor rejects a task with a reason', (tester) async {
      await pumpTasks(tester, _supervisor, [_waiting()]);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Page 2 is missing');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(store.tasks['t1']!.status, 'In Progress');
      expect(
        find.text('Rejected on $_today: Page 2 is missing'),
        findsOneWidget,
      );
    });

    testWidgets('the filters split completed tasks by approval', (
      tester,
    ) async {
      await pumpTasks(tester, _supervisor, [
        _waiting(id: 'a', title: 'Waiting one'),
        _approved(id: 'b', title: 'Approved one'),
        _task(id: 'c', title: 'Open one', status: 'In Progress'),
      ]);

      await tester.tap(find.text('For Approval').first);
      await tester.pumpAndSettle();
      expect(find.text('Waiting one'), findsOneWidget);
      expect(find.text('Approved one'), findsNothing);

      await tester.tap(find.text('Approved').first);
      await tester.pumpAndSettle();
      expect(find.text('Approved one'), findsOneWidget);
      expect(find.text('Waiting one'), findsNothing);
      expect(find.text('Open one'), findsNothing);
    });

    testWidgets("a student can't change an approved task", (tester) async {
      await pumpTasks(tester, _assistant, [
        _approved(id: 'a', title: 'Approved one'),
        _waiting(id: 'b', title: 'Waiting one'),
      ]);

      expect(
        find.textContaining('It is on your DTR and can go into a report.'),
        findsOneWidget,
      );
      expect(
        find.text("Waiting for your supervisor's approval."),
        findsOneWidget,
      );
      // Only the waiting task still offers its status buttons.
      expect(find.text('Not Started'), findsNWidgets(2));
      expect(find.text('Approve'), findsNothing);
    });
  });

  group('DTR/Accomplishment Report', () {
    Future<void> pumpDtr(WidgetTester tester, List<Task> tasks) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final head = User(
        id: 'h1',
        name: 'Maria Head',
        email: 'head@marsu.edu.ph',
        role: 'Head',
      );
      final dtrState = AppState()
        ..currentUser = head
        ..users = [head]
        ..tasks = tasks
        ..attendance = [
          AttendanceRecord(
            id: 'r1',
            studentId: 's1',
            studentName: 'Charlie A. Matining',
            date: _today,
            timeIn: '8:00 AM',
            timeOut: '10:00 AM',
            totalHours: 2,
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
            ChangeNotifierProvider<AppState>.value(value: dtrState),
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

    testWidgets("writes the day's approved tasks instead of Present", (
      tester,
    ) async {
      await pumpDtr(tester, [
        _approved(id: 'a', title: 'Shelve returns', assignedTo: 's1'),
        _approved(id: 'b', title: 'Sort the mail', assignedTo: 's1'),
        _waiting(id: 'c', title: 'Not yet approved').copyWith(assignedTo: 's1'),
      ]);

      final entry = find.text('Shelve returns; Sort the mail');
      await tester.dragUntilVisible(
        entry,
        find.byType(ListView).last,
        const Offset(0, -300),
      );

      expect(entry, findsOneWidget);
      expect(find.text('Present'), findsNothing);
      expect(find.textContaining('Not yet approved'), findsNothing);
    });

    testWidgets('still writes Present while a task waits for approval', (
      tester,
    ) async {
      await pumpDtr(tester, [
        _waiting(id: 'c', title: 'Not yet approved').copyWith(assignedTo: 's1'),
      ]);

      final entry = find.text('Present');
      await tester.dragUntilVisible(
        entry,
        find.byType(ListView).last,
        const Offset(0, -300),
      );

      expect(entry, findsOneWidget);
    });
  });

  group('Submit Report', () {
    Future<void> openForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      state
        ..currentUser = _assistant
        ..users = [_assistant]
        ..tasks = [
          _approved(id: 'a', title: 'Shelve returns'),
          _approved(id: 'b', title: 'Sort the mail'),
          _waiting(id: 'c', title: 'Not yet approved'),
        ]
        ..reports = [
          _report('r1', taskIds: ['b']),
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers only approved tasks not in a report yet', (
      tester,
    ) async {
      await openForm(tester);

      expect(find.text('APPROVED TASKS — INCLUDED ABOVE'), findsOneWidget);
      expect(find.text('Shelve returns'), findsOneWidget);
      expect(find.text('Sort the mail'), findsNothing);
      expect(find.text('Not yet approved'), findsNothing);
      expect(
        find.textContaining(
          "1 completed task is waiting for your supervisor's",
        ),
        findsOneWidget,
      );
    });

    testWidgets('records the tasks the report takes', (tester) async {
      await openForm(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Report Title'),
        'Week 1',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Report'));
      await tester.pumpAndSettle();

      final saved = store.reports.values.single;
      expect(saved.taskIds, ['a']);
      expect(saved.content, '• Shelve returns');
      // The next report doesn't offer it again.
      expect(state.reportableTasks, isEmpty);
    });
  });
}
