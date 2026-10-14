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

/// Keeps what the app saves in memory, and can refuse the saves.
class _Store extends FirestoreService {
  _Store({this.fail = false});

  final bool fail;
  final lists = <List<String>>[];
  final templates = <Map<String, dynamic>>[];
  final tasks = <Task>[];

  @override
  Future<void> setTaskCategories(List<String> names) async {
    if (fail) throw Exception('offline');
    lists.add(names);
  }

  @override
  Future<void> renameTaskCategory(
    List<String> names, {
    required String from,
    required String to,
    required List<String> taskIds,
    List<String> dutyIds = const [],
  }) async {
    if (fail) throw Exception('offline');
    lists.add(names);
  }

  @override
  Future<void> upsertTaskTemplate(Map<String, dynamic> template) async {
    if (fail) throw Exception('offline');
    templates.removeWhere((t) => t['id'] == template['id']);
    templates.add(template);
  }

  @override
  Future<void> removeTaskTemplate(String id) async {
    if (fail) throw Exception('offline');
    templates.removeWhere((t) => t['id'] == id);
  }

  @override
  Future<void> setTask(Task t) async {
    if (fail) throw Exception('offline');
    tasks.add(t);
  }
}

TaskTemplate _template(
  String id,
  String category,
  String title, {
  String priority = 'Medium',
  List<String> checklist = const [],
}) => TaskTemplate(
  id: id,
  category: category,
  title: title,
  description: 'Details of $title',
  priority: priority,
  checklist: checklist,
);

AppState _state(_Store store, {List<TaskTemplate> templates = const []}) =>
    AppState(firestoreService: store)..taskTemplates = [...templates];

void main() {
  group('task templates', () {
    test(
      'a template is saved trimmed, and listed under its category',
      () async {
        final store = _Store();
        final state = _state(store);

        final problem = await state.saveTaskTemplate(
          const TaskTemplate(
            id: 'tpl_1',
            category: 'Administrative',
            title: '  Receive documents ',
            checklist: ['Log it', '  ', ' Stamp it '],
          ),
        );

        expect(problem, isNull);
        final saved = state.templatesIn('Administrative').single;
        expect(saved.title, 'Receive documents');
        expect(saved.checklist, ['Log it', 'Stamp it']);
        expect(store.templates.single['title'], 'Receive documents');
        expect(state.templatesIn('Academic'), isEmpty);
      },
    );

    test(
      'a blank title, unknown category or repeated title is refused',
      () async {
        final store = _Store();
        final state = _state(
          store,
          templates: [_template('a', 'Administrative', 'Filing')],
        );

        expect(
          await state.saveTaskTemplate(_template('b', 'Administrative', ' ')),
          isNotNull,
        );
        expect(
          await state.saveTaskTemplate(_template('c', 'Nowhere', 'Filing')),
          isNotNull,
        );
        expect(
          await state.saveTaskTemplate(
            _template('d', 'Administrative', 'FILING'),
          ),
          contains('already has a template'),
        );
        // The same title is fine in another category.
        expect(
          await state.saveTaskTemplate(_template('e', 'Academic', 'Filing')),
          isNull,
        );
        expect(store.templates, hasLength(1));
      },
    );

    test('editing a template replaces it', () async {
      final store = _Store();
      final state = _state(
        store,
        templates: [_template('a', 'Administrative', 'Filing')],
      );

      final edited = state.taskTemplates.single.copyWith(priority: 'High');
      expect(await state.saveTaskTemplate(edited), isNull);

      expect(state.taskTemplates.single.priority, 'High');
      expect(state.taskTemplates, hasLength(1));
    });

    test('a failed save leaves the list unchanged', () async {
      final state = _state(_Store(fail: true));

      expect(
        await state.saveTaskTemplate(
          _template('a', 'Administrative', 'Filing'),
        ),
        isNotNull,
      );

      expect(state.taskTemplates, isEmpty);
    });

    test('deleting removes only that template', () async {
      final store = _Store();
      final state = _state(
        store,
        templates: [
          _template('a', 'Administrative', 'Filing'),
          _template('b', 'Administrative', 'Encoding'),
        ],
      );

      expect(await state.deleteTaskTemplate('a'), isNull);

      expect(state.taskTemplates.map((t) => t.id), ['b']);
    });

    test(
      'renaming a category moves its templates; deleting is refused',
      () async {
        final store = _Store();
        final state = _state(
          store,
          templates: [_template('a', 'Fieldwork', 'Deliver documents')],
        );

        expect(
          await state.deleteTaskCategory('Fieldwork'),
          contains('template'),
        );
        expect(
          await state.renameTaskCategory('Fieldwork', 'Field Work'),
          isNull,
        );

        expect(state.templatesIn('Field Work'), hasLength(1));
        expect(state.templatesIn('Fieldwork'), isEmpty);
      },
    );

    test(
      'a category with too many tasks to move in one batch is refused',
      () async {
        final store = _Store();
        final state = AppState(firestoreService: store)
          ..tasks = [
            for (var i = 0; i <= FirestoreService.maxRenamedTasks; i++)
              Task(
                id: 't$i',
                title: 'Task $i',
                description: '',
                status: 'Not Started',
                priority: 'Medium',
                dueDate: 'Oct 21, 2026',
                category: 'Fieldwork',
              ),
          ];

        expect(
          await state.renameTaskCategory('Fieldwork', 'Field Work'),
          contains('too many'),
        );
        expect(state.taskCategories, contains('Fieldwork'));
        expect(store.lists, isEmpty);
      },
    );
  });

  group('Assign Task sheet', () {
    late _Store store;
    late AppState state;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store = _Store();
      state = _state(
        store,
        templates: [
          _template(
            'a',
            'General',
            'Receive documents',
            priority: 'High',
            checklist: ['Log it', 'Stamp it'],
          ),
          _template('b', 'General', 'Filing'),
          _template('c', 'Academic', 'Grade sheets'),
        ],
      );
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

    testWidgets('shows the chosen category\'s templates only', (tester) async {
      await open(tester);

      expect(find.text('START FROM A TEMPLATE'), findsOneWidget);
      expect(find.text('Receive documents'), findsOneWidget);
      expect(find.text('Filing'), findsOneWidget);
      expect(find.text('Grade sheets'), findsNothing);
    });

    testWidgets('picking a template fills the form, and it assigns as typed', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Receive documents'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, 'Receive documents'),
        findsOneWidget,
      );
      expect(find.text('Log it'), findsOneWidget);
      expect(find.text('Stamp it'), findsOneWidget);

      // Edit the title afterwards: the task is its own copy.
      await tester.enterText(
        find.widgetWithText(TextField, 'Receive documents'),
        'Receive documents today',
      );
      await tester.tap(find.text('Assign Task').last);
      await tester.pumpAndSettle();

      final made = store.tasks.single;
      expect(made.title, 'Receive documents today');
      expect(made.priority, 'High');
      expect(made.category, 'General');
      expect(made.checklistItems, ['Log it', 'Stamp it']);
    });

    testWidgets('picking another template asks before replacing typed text', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'My own task');
      await tester.tap(find.text('Filing'));
      await tester.pumpAndSettle();

      expect(find.text('Use This Template?'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filing'), findsOneWidget);

      // Picking another one straight away needs no question: nothing typed.
      await tester.tap(find.text('Receive documents'));
      await tester.pumpAndSettle();
      expect(find.text('Use This Template?'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Receive documents'),
        findsOneWidget,
      );
    });

    testWidgets('a changed priority counts as typed content', (tester) async {
      await open(tester);

      await tester.tap(find.text('Receive documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Low'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filing'));
      await tester.pumpAndSettle();

      expect(find.text('Use This Template?'), findsOneWidget);
    });

    testWidgets('a category the Head deletes while it is open is dropped', (
      tester,
    ) async {
      await open(tester);

      state.taskCategories = ['Academic', 'Reporting'];
      state.notifyListeners();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Academic'), findsWidgets);
      expect(find.text('START FROM A TEMPLATE'), findsOneWidget);
      expect(find.text('Grade sheets'), findsOneWidget);
    });

    testWidgets('an ordinary task can have more than twelve checklist steps', (
      tester,
    ) async {
      await open(tester);

      for (var i = 1; i <= 13; i++) {
        await tester.enterText(
          find.widgetWithText(TextField, 'Add a checklist step'),
          'Step $i',
        );
        await tester.tap(find.byTooltip('Add step'));
        await tester.pump();
      }

      expect(find.text('Step 13'), findsOneWidget);
    });

    testWidgets('a task needs a title, and nothing is saved without one', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Assign Task').last);
      await tester.pumpAndSettle();

      expect(find.text('Give the task a title.'), findsOneWidget);
      expect(store.tasks, isEmpty);
    });
  });

  group('Manage Categories templates', () {
    testWidgets('adds a template under an opened category', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = _Store();
      final state = _state(store);
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
      expect(find.text('TEMPLATES'), findsOneWidget);
      await tester.tap(find.text('Add template'));
      await tester.pumpAndSettle();

      expect(find.text('New Template'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Receive documents',
      );
      await tester.tap(find.text('Save Template'));
      await tester.pumpAndSettle();

      expect(find.text('New Template'), findsNothing);
      expect(find.text('Receive documents'), findsOneWidget);
      expect(find.text('No tasks yet · 1 template'), findsOneWidget);
      expect(store.templates.single['category'], 'Administrative');
    });
  });
}
