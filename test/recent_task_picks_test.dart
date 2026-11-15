import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/task_template.dart';
import 'package:projectsais/screens/tasks/assign_task_sheet.dart';
import 'package:projectsais/screens/tasks/manage_categories_dialog.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

class _Store extends FirestoreService {
  _Store({this.failTemplates = false});

  final bool failTemplates;
  final tasks = <Task>[];
  final templateBatches = <List<Map<String, dynamic>>>[];

  @override
  Future<void> setTask(Task t) async => tasks.add(t);

  @override
  Future<void> upsertTaskTemplates(List<Map<String, dynamic>> templates) async {
    if (failTemplates) throw Exception('offline');
    templateBatches.add(templates);
  }
}

final _head = User(
  id: 'h1',
  name: 'Hana Head',
  email: 'h@marsu.edu.ph',
  role: 'Head',
);

Task _task(
  String id,
  String title, {
  String category = 'General',
  String description = '',
  String priority = 'Medium',
  List<String> checklist = const [],
  String? dutyId,
  bool archived = false,
}) => Task(
  id: id,
  title: title,
  description: description,
  status: 'Not Started',
  priority: priority,
  dueDate: 'Oct 21, 2026',
  category: category,
  checklistItems: checklist,
  dutyId: dutyId,
  isArchived: archived,
);

AppState _state(
  List<Task> tasks, {
  List<TaskTemplate> templates = const [],
  _Store? store,
}) => AppState(firestoreService: store ?? _Store())
  ..currentUser = _head
  ..tasks = tasks
  ..taskTemplates = [...templates];

void main() {
  group('tasks grouped by title', () {
    test('same title in any case is one line, the most repeated first', () {
      final state = _state([
        _task('1', 'Encode grades'),
        _task('2', 'Update inventory'),
        _task('3', 'encode grades '),
        _task('4', 'Update inventory'),
        _task('5', 'Encode grades'),
        _task('6', 'Sweep the lobby'),
      ]);

      final groups = state.taskTitleGroups(state.tasks, 'General');

      expect(groups.map((g) => g.title), [
        'Encode grades',
        'Update inventory',
        'Sweep the lobby',
      ]);
      expect(groups.map((g) => g.count), [3, 2, 1]);
      // The newest of a title stands for it.
      expect(groups.first.latest.id, '1');
    });

    test('their counts add up to what the category row says', () {
      final state = _state([
        _task('1', 'A'),
        _task('2', 'A', archived: true),
        _task('3', 'B', dutyId: 'd1'),
        _task('4', 'C', category: 'Academic'),
      ]);

      final groups = state.taskTitleGroups(state.tasks, 'General');

      expect(
        groups.fold<int>(0, (sum, g) => sum + g.count),
        state.tasksInCategory('General'),
      );
    });

    test('a tie keeps the newer title above the older one', () {
      final state = _state([_task('1', 'New one'), _task('2', 'Old one')]);

      expect(
        state.taskTitleGroups(state.tasks, 'General').map((g) => g.title),
        ['New one', 'Old one'],
      );
    });
  });

  group('recently assigned picks', () {
    test(
      'come from the category, carry the newest version, skip duty logs',
      () {
        final state = _state([
          _task(
            '1',
            'Encode grades',
            description: 'Newest wording',
            priority: 'High',
            checklist: ['Open the sheet', ' '],
          ),
          _task('2', 'Encode grades', description: 'Old wording'),
          _task('3', 'Log of a duty', dutyId: 'd1'),
          _task('4', 'Grade sheets', category: 'Academic'),
          _task('5', '   '),
        ]);

        final picks = state.recentTaskPicks('General');

        expect(picks.map((t) => t.title), ['Encode grades']);
        expect(picks.single.id, 'recent:1');
        expect(picks.single.description, 'Newest wording');
        expect(picks.single.priority, 'High');
        expect(picks.single.checklist, ['Open the sheet']);
        expect(picks.single.ongoing, isFalse);
      },
    );

    test('leave out a title the Head already made a template', () {
      final state = _state(
        [_task('1', 'Filing'), _task('2', 'Sweeping')],
        templates: [
          const TaskTemplate(id: 'a', category: 'General', title: 'FILING'),
        ],
      );

      expect(state.recentTaskPicks('General').map((t) => t.title), [
        'Sweeping',
      ]);
    });

    test('offer a long list, but not an endless one', () {
      final state = _state([
        for (var i = 0; i < 40; i++) _task('$i', 'Task $i'),
      ]);

      expect(AppState.maxRecentTaskPicks, 30);
      expect(
        state.recentTaskPicks('General'),
        hasLength(AppState.maxRecentTaskPicks),
      );
    });

    test('a Supervisor sees only the tasks of their own assistants', () {
      final state = AppState(firestoreService: _Store())
        ..currentUser = User(
          id: 's1',
          name: 'Sam Supervisor',
          email: 's@marsu.edu.ph',
          role: 'Supervisor',
        )
        ..tasks = [_task('1', 'Someone else\'s task')];

      expect(state.recentTaskPicks('General'), isEmpty);
    });
  });

  group('Assign Task sheet', () {
    // The dropdown of saved tasks (the one keyed by category | pick).
    final savedTasks = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.contains('|'),
    );

    Future<void> open(WidgetTester tester, AppState state) async {
      // Only the sheet's own reads matter here.
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
    }

    testWidgets('offers tasks already given, and picking one fills the form', (
      tester,
    ) async {
      final state = _state([
        _task(
          '1',
          'Encode grades',
          description: 'Use the new template',
          priority: 'High',
          checklist: ['Open the sheet'],
        ),
        _task('2', 'Encode grades'),
        _task('3', 'Grade sheets', category: 'Academic'),
      ]);
      await open(tester, state);

      // One dropdown, closed: nothing crammed onto the form.
      expect(find.text('START FROM A SAVED TASK'), findsOneWidget);
      expect(find.text('Type my own'), findsOneWidget);
      expect(find.text('Encode grades'), findsNothing);

      await tester.tap(savedTasks);
      await tester.pumpAndSettle();
      expect(find.text('GIVEN BEFORE'), findsOneWidget);
      expect(find.text('Encode grades'), findsOneWidget);
      expect(find.text('Grade sheets'), findsNothing);

      await tester.tap(find.text('Encode grades'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Encode grades'), findsOneWidget);
      expect(find.text('Use the new template'), findsOneWidget);
      expect(find.text('Open the sheet'), findsOneWidget);
    });

    testWidgets('shows no dropdown when the category has nothing to offer', (
      tester,
    ) async {
      await open(tester, _state(const []));

      expect(find.text('START FROM A SAVED TASK'), findsNothing);
    });

    testWidgets('templates come first, then the tasks given before', (
      tester,
    ) async {
      final state = _state(
        [_task('1', 'Sweeping')],
        templates: [
          const TaskTemplate(id: 'a', category: 'General', title: 'Filing'),
        ],
      );
      await open(tester, state);
      await tester.tap(savedTasks);
      await tester.pumpAndSettle();

      expect(find.text('TEMPLATES'), findsOneWidget);
      expect(find.text('GIVEN BEFORE'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Filing')).dy,
        lessThan(tester.getTopLeft(find.text('Sweeping')).dy),
      );
    });

    testWidgets('Type my own lets go of a pick and keeps what is typed', (
      tester,
    ) async {
      await open(tester, _state([_task('1', 'Sweeping', description: 'Hall')]));
      await tester.tap(savedTasks);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sweeping'));
      await tester.pumpAndSettle();

      await tester.tap(savedTasks);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type my own').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Sweeping'), findsOneWidget);
      // Picking it again is a fresh pick: the text on the form is now the
      // person's own, so replacing it is asked about.
      await tester.tap(savedTasks);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sweeping').last);
      await tester.pumpAndSettle();
      expect(find.text('Use This Template?'), findsOneWidget);
    });

    testWidgets('turning down a replacement keeps the earlier pick shown', (
      tester,
    ) async {
      await open(
        tester,
        _state([_task('1', 'Sweeping'), _task('2', 'Filing')]),
      );
      await tester.tap(savedTasks);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sweeping'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Changed by hand');

      await tester.tap(savedTasks);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filing').last);
      await tester.pumpAndSettle();
      expect(find.text('Use This Template?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Changed by hand'), findsOneWidget);
      // The dropdown still names the earlier pick, not the one turned down.
      expect(
        find.descendant(of: savedTasks, matching: find.text('Sweeping')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: savedTasks, matching: find.text('Filing')),
        findsNothing,
      );
    });
  });

  group('Task Categories dialog', () {
    testWidgets('an opened category lists the tasks given under it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = _state([
        _task('1', 'Encode grades', category: 'Administrative'),
        _task('2', 'Encode grades', category: 'Administrative'),
        _task('3', 'File memos', category: 'Administrative'),
        _task('4', 'Other', category: 'Academic'),
      ]);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showManageCategoriesDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('3 tasks'), findsOneWidget);
      await tester.tap(find.text('Administrative'));
      await tester.pumpAndSettle();

      expect(find.text('TASKS GIVEN'), findsOneWidget);
      expect(find.text('Encode grades'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      expect(find.text('File memos'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
    });

    testWidgets('a category with no tasks has no such block', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = _state(const []);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showManageCategoriesDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrative'));
      await tester.pumpAndSettle();

      expect(find.text('TASKS GIVEN'), findsNothing);
      expect(find.text('TEMPLATES'), findsOneWidget);
    });
  });

  group('making templates from tasks already given', () {
    List<TaskTitleGroup> groupsOf(
      AppState state, [
      String category = 'General',
    ]) => state.taskTitleGroups(state.tasks, category);

    test(
      'saves every ticked task in one go, from its newest version',
      () async {
        final store = _Store();
        final state = _state([
          _task(
            '1',
            'Encode grades',
            description: ' Newest wording ',
            priority: 'High',
            checklist: ['Open the sheet', ' '],
          ),
          _task('2', 'Encode grades', description: 'Old wording'),
          _task('3', 'Sweep the lobby'),
        ], store: store);

        final result = await state.saveTaskTemplatesFromTasks(
          'General',
          groupsOf(state),
        );

        expect(result.problem, isNull);
        expect(result.made, 2);
        expect(result.skipped, 0);
        expect(store.templateBatches, hasLength(1));
        expect(store.templateBatches.single, hasLength(2));
        final grades = state
            .templatesIn('General')
            .firstWhere((t) => t.title == 'Encode grades');
        expect(grades.description, 'Newest wording');
        expect(grades.priority, 'High');
        expect(grades.checklist, ['Open the sheet']);
        expect(grades.ongoing, isFalse);
        expect(
          state.taskTemplates.map((t) => t.id).toSet(),
          hasLength(2),
          reason: 'every template has its own id',
        );
      },
    );

    test(
      'leaves out titles that already are templates and duty logs',
      () async {
        final store = _Store();
        final state = _state(
          [
            _task('1', 'Filing'),
            _task('2', 'Log of a duty', dutyId: 'd1'),
            _task('3', 'Sweeping'),
          ],
          templates: [
            const TaskTemplate(id: 'a', category: 'General', title: 'FILING'),
          ],
          store: store,
        );

        final result = await state.saveTaskTemplatesFromTasks(
          'General',
          groupsOf(state),
        );

        expect(result.made, 1);
        expect(result.skipped, 2);
        expect(state.templatesIn('General').map((t) => t.title), [
          'FILING',
          'Sweeping',
        ]);
      },
    );

    test('nothing new to make saves nothing', () async {
      final store = _Store();
      final state = _state(
        [_task('1', 'Filing')],
        templates: [
          const TaskTemplate(id: 'a', category: 'General', title: 'Filing'),
        ],
        store: store,
      );

      final result = await state.saveTaskTemplatesFromTasks(
        'General',
        groupsOf(state),
      );

      expect(result.made, 0);
      expect(result.problem, isNull);
      expect(store.templateBatches, isEmpty);
    });

    test('cuts what is too long for a template', () async {
      final state = _state([
        _task(
          '1',
          'T' * 100,
          description: 'D' * 600,
          checklist: [for (var i = 0; i < 15; i++) 'S' * 100],
        ),
      ]);

      await state.saveTaskTemplatesFromTasks('General', groupsOf(state));

      final made = state.taskTemplates.single;
      expect(made.title, hasLength(TaskTemplate.maxTitle));
      expect(made.description, hasLength(TaskTemplate.maxDescription));
      expect(made.checklist, hasLength(TaskTemplate.maxChecklistItems));
      expect(made.checklist.first, hasLength(TaskTemplate.maxChecklistItem));
    });

    test('refuses, and saves none, when they would not all fit', () async {
      final store = _Store();
      final state = _state(
        [_task('1', 'One'), _task('2', 'Two')],
        templates: [
          for (var i = 0; i < AppState.maxTaskTemplates - 1; i++)
            TaskTemplate(id: 'x$i', category: 'Academic', title: 'T$i'),
        ],
        store: store,
      );

      final result = await state.saveTaskTemplatesFromTasks(
        'General',
        groupsOf(state),
      );

      expect(result.made, 0);
      expect(result.problem, contains('only 1 more'));
      expect(store.templateBatches, isEmpty);
      expect(state.taskTemplates, hasLength(AppState.maxTaskTemplates - 1));
    });

    test('a failed save changes nothing', () async {
      final state = _state([
        _task('1', 'One'),
      ], store: _Store(failTemplates: true));

      final result = await state.saveTaskTemplatesFromTasks(
        'General',
        groupsOf(state),
      );

      expect(result.made, 0);
      expect(result.problem, contains("Couldn't save"));
      expect(state.taskTemplates, isEmpty);
    });

    test('a category that is not on the list is refused', () async {
      final state = _state([_task('1', 'One', category: 'Nowhere')]);

      final result = await state.saveTaskTemplatesFromTasks(
        'Nowhere',
        groupsOf(state, 'Nowhere'),
      );

      expect(result.made, 0);
      expect(result.problem, isNotNull);
    });

    Future<AppState> openDialog(
      WidgetTester tester,
      List<Task> tasks, {
      List<TaskTemplate> templates = const [],
    }) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = _state(tasks, templates: templates);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showManageCategoriesDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrative'));
      await tester.pumpAndSettle();
      return state;
    }

    List<Task> three() => [
      _task('1', 'Encode grades', category: 'Administrative'),
      _task('2', 'File memos', category: 'Administrative'),
      _task('3', 'Sweep the lobby', category: 'Administrative'),
    ];

    testWidgets('tick several and make them all templates at once', (
      tester,
    ) async {
      final state = await openDialog(tester, three());

      expect(find.textContaining('Make '), findsNothing);
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Make 2 templates'), findsOneWidget);

      await tester.tap(find.text('Make 2 templates'));
      await tester.pumpAndSettle();

      expect(find.text('Made 2 templates.'), findsOneWidget);
      expect(state.templatesIn('Administrative'), hasLength(2));
      // They are templates now: tagged, no longer tickable, and the button
      // is gone.
      expect(find.text('Template'), findsNWidgets(2));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.textContaining('Make '), findsNothing);
    });

    testWidgets('Select all and Clear', (tester) async {
      await openDialog(tester, three());

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('Make 3 templates'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Make '), findsNothing);
      expect(find.text('Select all'), findsOneWidget);
    });

    testWidgets('a long list shows ten, and the rest on Show all', (
      tester,
    ) async {
      await openDialog(tester, [
        for (var i = 1; i <= 12; i++)
          _task('$i', 'Task number $i', category: 'Administrative'),
      ]);

      expect(find.text('Show all 12'), findsOneWidget);
      expect(find.text('Task number 11'), findsNothing);

      await tester.tap(find.text('Show all 12'));
      await tester.pumpAndSettle();

      expect(find.text('Task number 12'), findsOneWidget);
      expect(find.text('Show fewer'), findsOneWidget);
    });

    testWidgets('opening another category drops the ticks', (tester) async {
      final state = _state(three());
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showManageCategoriesDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrative'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Make 1 template'), findsOneWidget);

      await tester.tap(find.text('Academic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrative'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Make '), findsNothing);
    });
  });
}
