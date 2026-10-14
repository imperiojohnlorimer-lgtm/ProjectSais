import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/tasks/manage_categories_dialog.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Records the category saves the app makes, and can refuse them.
class _Store extends FirestoreService {
  _Store({this.fail = false});

  final bool fail;
  final lists = <List<String>>[];
  final renamedTaskIds = <String>[];

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
    renamedTaskIds.addAll(taskIds);
  }
}

Task _task(String id, String? category, {bool archived = false}) => Task(
  id: id,
  title: 'Task $id',
  description: '',
  status: 'Not Started',
  priority: 'Medium',
  dueDate: 'Oct 21, 2026',
  category: category,
  isArchived: archived,
);

AppState _state(_Store store) => AppState(firestoreService: store)
  ..tasks = [
    _task('t1', 'Fieldwork'),
    _task('t2', 'Fieldwork', archived: true),
    _task('t3', 'Academic'),
    _task('t4', null),
  ];

void main() {
  group('task categories', () {
    test('a name already on the list is refused in any case', () async {
      final store = _Store();
      final state = _state(store);

      expect(state.findTaskCategory(' fieldwork '), 'Fieldwork');
      expect(await state.addTaskCategory('FIELDWORK'), isFalse);
      expect(store.lists, isEmpty);
    });

    test(
      'renaming moves the tasks filed under it, archived ones too',
      () async {
        final store = _Store();
        final state = _state(store);

        expect(
          await state.renameTaskCategory('Fieldwork', 'Field Work'),
          isNull,
        );

        expect(state.taskCategories, contains('Field Work'));
        expect(state.taskCategories, isNot(contains('Fieldwork')));
        expect(store.renamedTaskIds, ['t1', 't2']);
        expect(state.tasks.map((t) => t.category), [
          'Field Work',
          'Field Work',
          'Academic',
          null,
        ]);
      },
    );

    test('a rename that only changes the case is allowed', () async {
      final state = _state(_Store());

      expect(await state.renameTaskCategory('Fieldwork', 'FIELDWORK'), isNull);

      expect(state.taskCategories, contains('FIELDWORK'));
    });

    test(
      'a rename to another category, a blank or General is refused',
      () async {
        final store = _Store();
        final state = _state(store);

        expect(
          await state.renameTaskCategory('Fieldwork', 'academic'),
          '"Academic" is already a task category.',
        );
        expect(await state.renameTaskCategory('Fieldwork', '  '), isNotNull);
        expect(await state.renameTaskCategory('General', 'Other'), isNotNull);

        expect(store.lists, isEmpty);
        expect(state.taskCategories, contains('Fieldwork'));
      },
    );

    test('a failed rename changes nothing', () async {
      final state = _state(_Store(fail: true));

      expect(
        await state.renameTaskCategory('Fieldwork', 'Field Work'),
        isNotNull,
      );

      expect(state.taskCategories, contains('Fieldwork'));
      expect(state.tasks.first.category, 'Fieldwork');
    });

    test('a category in use, or General, cannot be deleted', () async {
      final store = _Store();
      final state = _state(store);

      expect(
        await state.deleteTaskCategory('Fieldwork'),
        contains('used by 2 tasks'),
      );
      expect(await state.deleteTaskCategory('General'), isNotNull);
      expect(store.lists, isEmpty);
    });

    test('an unused category is deleted', () async {
      final store = _Store();
      final state = _state(store);

      expect(await state.deleteTaskCategory('Reporting'), isNull);

      expect(state.taskCategories, isNot(contains('Reporting')));
      expect(store.lists.single, isNot(contains('Reporting')));
    });
  });

  group('Manage Categories dialog', () {
    Future<_Store> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 900);
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
      return store;
    }

    testWidgets('lists each category with how many tasks use it', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Task Categories'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('2 tasks'), findsOneWidget); // Fieldwork
      expect(find.text('1 task'), findsOneWidget); // Academic
      expect(find.text('No tasks yet'), findsNWidgets(3));

      // A category in use has no working delete button.
      final inUse = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.tooltip == "In use by 2 tasks, so it can't be deleted",
      );
      expect(inUse, findsOneWidget);
      expect(tester.widget<IconButton>(inUse).onPressed, isNull);
    });

    testWidgets('adds, then refuses a name that differs only by case', (
      tester,
    ) async {
      final store = await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Inventory');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Added "Inventory".'), findsOneWidget);
      expect(store.lists.single, contains('Inventory'));

      await tester.enterText(find.byType(TextField).first, 'inventory');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        find.text('"Inventory" is already a task category.'),
        findsOneWidget,
      );
      expect(store.lists, hasLength(1));
    });

    testWidgets('renames a category in place', (tester) async {
      final store = await open(tester);

      await tester.tap(find.byTooltip('Rename').first); // Administrative
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Administrative');
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Office Work');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Renamed "Administrative" to "Office Work".'),
        findsOneWidget,
      );
      expect(find.text('Office Work'), findsOneWidget);
      expect(store.lists.single, contains('Office Work'));
    });
  });
}
