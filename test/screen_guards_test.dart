import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/offices_screen.dart';
import 'package:projectsais/screens/accounts/student_documents_screen.dart';
import 'package:projectsais/screens/auth/login_screen.dart';
import 'package:projectsais/screens/reports/reports_screen.dart';
import 'package:projectsais/screens/tasks/assign_task_sheet.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

/// Report saves wait for [gate], then fail or succeed as [fail] says.
class _ReportStore extends FirestoreService {
  Completer<void> gate = Completer<void>()..complete();
  bool fail = true;
  final saved = <Report>[];

  @override
  Future<void> setReport(Report r) async {
    await gate.future;
    if (fail) throw Exception('offline');
    saved.add(r);
  }
}

/// A password reset that waits for the test.
class _SlowResetState extends AppState {
  final reset = Completer<String?>();

  @override
  Future<String?> sendPasswordResetEmail(String email) => reset.future;
}

User _user(String id, String name, String role) =>
    User(id: id, name: name, email: '$id@example.com', role: role);

/// Ignores the overflows the test font causes (it draws every glyph as a
/// full square), and nothing else.
void _ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Offices count each current assistant once, never below 0', (
    tester,
  ) async {
    _wide(tester);
    _ignoreOverflow();
    final head = _user('h1', 'Hana Head', 'Head');
    final state = AppState(firestoreService: FirestoreService())
      ..currentUser = head
      ..users = [
        head,
        _user('sa1', 'Ana Uno', 'Student Assistant'),
        _user('sa2', 'Ben Dos', 'Student Assistant'), // in two offices
        _user('sa3', 'Cara Tres', 'Student Assistant'), // placed by name
        _user('sa4', 'Dan Cuatro', 'Student Assistant'), // inactive office
        _user('sa5', 'Eva Cinco', 'Student Assistant'), // nowhere
      ]
      ..offices = const [
        Office(
          id: 'o1',
          name: 'Library',
          code: 'LIB',
          assistantIds: ['sa1', 'sa2', '', 'gone1', 'gone2', 'gone3'],
          assistantNames: ['Ana Uno', 'Ben Dos', 'Cara Tres', 'X', 'Y', 'Z'],
        ),
        Office(
          id: 'o2',
          name: 'Registrar',
          code: 'REG',
          assistantIds: ['sa2'],
          assistantNames: ['Ben Dos'],
        ),
        Office(
          id: 'o3',
          name: 'Old Office',
          code: 'OLD',
          isActive: false,
          assistantIds: ['sa4'],
          assistantNames: ['Dan Cuatro'],
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: OfficesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hero =
        tester.widget(
              find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_OfficesHero',
              ),
            )
            as dynamic;
    expect(hero.assignedAssistants, 3); // Ana, Ben (once), Cara
    expect(hero.unassignedAssistants, 2); // Dan, Eva
  });

  testWidgets(
    'Student Documents: a filter whose office vanished falls back to All',
    (tester) async {
      _wide(tester);
      _ignoreOverflow();
      final head = _user('h1', 'Hana Head', 'Head');
      final state = AppState(firestoreService: FirestoreService())
        ..currentUser = head
        ..users = [
          head,
          _user('sa1', 'Ana Uno', 'Student Assistant'),
          _user('sa2', 'Ben Dos', 'Student Assistant'),
        ]
        ..students = [
          Student(
            id: 's1',
            userId: 'sa1',
            name: 'Ana Uno',
            email: 'sa1@example.com',
            department: 'CICS',
            campus: 'Boac',
          ),
          Student(
            id: 's2',
            userId: 'sa2',
            name: 'Ben Dos',
            email: 'sa2@example.com',
            department: 'CICS',
            campus: 'Boac',
          ),
        ]
        ..offices = const [
          Office(
            id: 'o1',
            name: 'Library',
            code: 'LIB',
            assistantIds: ['sa1'],
            assistantNames: ['Ana Uno'],
          ),
          Office(
            id: 'o2',
            name: 'Registrar',
            code: 'REG',
            assistantIds: ['sa2'],
            assistantNames: ['Ben Dos'],
          ),
        ]
        ..documents = [
          Document(
            id: 'd1',
            name: 'a.pdf',
            fileName: 'a.pdf',
            uploadedBy: 'Hana Head',
            uploadedAt: '2026-11-27T00:00:00Z',
            documentType: 'Other',
            studentId: 'sa1',
            studentName: 'Ana Uno',
          ),
          Document(
            id: 'd2',
            name: 'b.pdf',
            fileName: 'b.pdf',
            uploadedBy: 'Hana Head',
            uploadedAt: '2026-11-27T00:00:00Z',
            documentType: 'Other',
            studentId: 'sa2',
            studentName: 'Ben Dos',
          ),
        ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: StudentDocumentsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('All Offices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      expect(find.text('Ana Uno'), findsOneWidget);
      expect(find.text('Ben Dos'), findsNothing);

      // Office renamed while the filter was still set to 'Library'.
      state.offices = const [
        Office(
          id: 'o1',
          name: 'Main Library',
          code: 'LIB',
          assistantIds: ['sa1'],
          assistantNames: ['Ana Uno'],
        ),
        Office(
          id: 'o2',
          name: 'Registrar',
          code: 'REG',
          assistantIds: ['sa2'],
          assistantNames: ['Ben Dos'],
        ),
      ];
      state.setTab(state.activeTab);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('All Offices'), findsOneWidget);
      expect(find.text('Ana Uno'), findsOneWidget);
      expect(find.text('Ben Dos'), findsOneWidget);
    },
  );

  group('Submit Report', () {
    final assistant = _user('sa1', 'Sara Assistant', 'Student Assistant');

    Future<_ReportStore> openForm(WidgetTester tester) async {
      _wide(tester);
      _ignoreOverflow();
      final store = _ReportStore();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(firestoreService: store)
            ..currentUser = assistant
            ..users = [assistant],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Report Title'),
        'Week 1',
      );
      return store;
    }

    Finder submit() => find.widgetWithText(ElevatedButton, 'Submit Report');

    testWidgets('a failed submit keeps what was typed, and says why', (
      tester,
    ) async {
      final store = await openForm(tester);
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.textContaining("couldn't be submitted"), findsOneWidget);
      expect(find.text('Week 1'), findsOneWidget);
      expect(submit(), findsOneWidget); // ready to try again

      store.fail = false;
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(store.saved.single.title, 'Week 1');
      expect(submit(), findsNothing); // closed
      expect(find.text('Report submitted successfully!'), findsOneWidget);
    });

    testWidgets('closed while saving, a failure is still reported', (
      tester,
    ) async {
      final store = await openForm(tester);
      store.gate = Completer<void>();
      await tester.tap(submit());
      await tester.pump();

      // Dragged away / closed while it saved.
      Navigator.of(tester.element(find.text('Submitting...'))).pop();
      await tester.pumpAndSettle();
      store.gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Failed to submit report. Please try again.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('Forgot password: closed while sending, an error is harmless', (
    tester,
  ) async {
    _wide(tester);
    final state = _SlowResetState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: LoginScreen(onShowRegister: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'juan@example.com',
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pump();

    await tester.tapAt(const Offset(5, 5)); // outside: closes the dialog
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    state.reset.complete('Too many requests.');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Assign Task: a student who left the list is not assigned', (
    tester,
  ) async {
    _wide(tester);
    _ignoreOverflow();
    final head = _user('h1', 'Hana Head', 'Head');
    final student = _user('sa1', 'Ana Uno', 'Student Assistant');
    final state = AppState(firestoreService: FirestoreService())
      ..currentUser = head
      ..users = [head, student]
      ..students = [
        Student(
          id: 's1',
          userId: 'sa1',
          name: 'Ana Uno',
          email: 'sa1@example.com',
          department: 'CICS',
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Task title'),
      'Shelve returns',
    );
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Assign to'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Uno').last);
    await tester.pumpAndSettle();

    // A live update takes her off the roster while the sheet is open.
    state.students = [];
    state.setTab(state.activeTab);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final assign = find.text('Assign Task').last;
    await tester.ensureVisible(assign);
    await tester.tap(assign);
    await tester.pumpAndSettle();
    expect(
      find.text('That student is no longer in your office. Choose again.'),
      findsOneWidget,
    );
    expect(state.tasks, isEmpty);
  });

  group('the top-bar clock', () {
    test('reads on a 12-hour clock', () {
      expect(clockText(DateTime(2026, 11, 27, 14, 5, 7)), '2:05:07 pm');
      expect(clockText(DateTime(2026, 11, 27, 0, 0)), '12:00:00 am');
      expect(
        clockText(DateTime(2026, 11, 27, 12, 30), seconds: false),
        '12:30 pm',
      );
    });

    testWidgets('ticks on its own, and stops when gone', (tester) async {
      var now = DateTime(2026, 11, 27, 9, 0, 0);
      final rebuild = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (_, _, _) => LiveClock(
              clock: () => now,
              builder: (_, time) => Text(clockText(time)),
            ),
          ),
        ),
      );
      expect(find.text('9:00:00 am'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      rebuild.value++; // a parent rebuild doesn't start it over
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('9:00:01 am'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      // Nothing left running (the test fails on a pending timer).
    });
  });
}
