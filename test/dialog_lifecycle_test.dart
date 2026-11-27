import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/recurring_schedule.dart';
import 'package:projectsais/screens/calendar/calendar_screen.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/recurring_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

/// Recurring rules kept in memory, remembering every save.
class _Rules implements RecurringScheduleRepository {
  _Rules(this.rules);

  List<RecurringScheduleRule> rules;
  final saves = <List<RecurringScheduleRule>>[];

  @override
  Future<List<RecurringScheduleRule>> loadRules(String ownerId) async => rules;

  @override
  Future<void> saveRules(
    String ownerId,
    String ownerName,
    List<RecurringScheduleRule> rules,
  ) async {
    saves.add(rules);
    this.rules = rules;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A controller that can say whether it was disposed.
class _TrackedController extends TextEditingController {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  test('a DTR day\'s hours can be emptied', () {
    const day = DtrDayEntry(day: 3, totalHours: 4);
    expect(day.copyWith(clearTotalHours: true).totalHours, isNull);
    expect(day.copyWith(totalHours: 2.5).totalHours, 2.5);
    expect(day.copyWith(note: 'x').totalHours, 4);
  });

  testWidgets('DisposeWhenGone waits until the dialog has finished closing', (
    tester,
  ) async {
    final controller = _TrackedController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => DisposeWhenGone(
                notifiers: [controller],
                child: AlertDialog(
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Library');

    await tester.tap(find.text('Cancel'));
    await tester.pump(); // closing: the field is still on screen
    expect(controller.disposed, isFalse);
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.disposed, isFalse);

    await tester.pumpAndSettle(); // gone
    expect(controller.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  group('Calendar: editing a recurring schedule', () {
    final supervisor = User(
      id: 'sup1',
      name: 'Sam Supervisor',
      email: 'sam@example.com',
      role: 'Supervisor',
    );

    Future<_Rules> pumpCalendar(
      WidgetTester tester,
      List<RecurringScheduleRule> rules,
    ) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repository = _Rules(rules);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>(
              create: (_) => AppState()
                ..currentUser = supervisor
                ..users = [supervisor],
            ),
            ChangeNotifierProvider(
              create: (_) => ScheduleService(InMemoryScheduleRepository()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(body: CalendarScreen(rulesRepository: repository)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    Future<void> editFirstRule(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
    }

    testWidgets('a subject opens the subject form and keeps what it had', (
      tester,
    ) async {
      final errors = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      // The calendar overflows a little under the test font; only real
      // errors matter here.
      FlutterError.onError = (details) {
        if (!details.toString().contains('overflowed')) errors.add(details);
      };
      addTearDown(() => FlutterError.onError = original);

      final repository = await pumpCalendar(tester, const [
        RecurringScheduleRule(
          id: 'r1',
          ownerName: 'Sam Supervisor',
          label: 'IT 401',
          weekday: DateTime.monday,
          startTime: TimeOfDay(hour: 8, minute: 0),
          endTime: TimeOfDay(hour: 10, minute: 0),
          color: Colors.blue,
          icon: Icons.menu_book_outlined,
          units: '3',
          isSubject: true,
          instructor: 'K. Santos',
          room: 'CL4',
        ),
      ]);
      await editFirstRule(tester);

      expect(find.text('Edit Subject'), findsOneWidget);
      // The units field is filled in.
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '3',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
      final saved = repository.saves.last.single;
      expect(saved.isSubject, isTrue);
      expect(saved.units, '3');
      expect(saved.instructor, 'K. Santos');
      expect(saved.room, 'CL4');
    });

    testWidgets('a plain schedule keeps what its form does not edit', (
      tester,
    ) async {
      final original = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = (details) {
        if (!details.toString().contains('overflowed')) errors.add(details);
      };
      addTearDown(() => FlutterError.onError = original);

      final repository = await pumpCalendar(tester, const [
        RecurringScheduleRule(
          id: 'r2',
          ownerName: 'Sam Supervisor',
          label: 'Library duty',
          weekday: DateTime.tuesday,
          startTime: TimeOfDay(hour: 13, minute: 0),
          endTime: TimeOfDay(hour: 15, minute: 0),
          color: Colors.green,
          icon: Icons.work_outline,
          room: 'Main Library',
        ),
      ]);
      await editFirstRule(tester);

      expect(find.text('Edit Schedule'), findsOneWidget);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
      final saved = repository.saves.last.single;
      expect(saved.isSubject, isFalse);
      expect(saved.room, 'Main Library');
      expect(saved.label, 'Library duty');
    });
  });
}
