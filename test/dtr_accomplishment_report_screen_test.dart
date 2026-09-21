import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/supervisor/dtr_accomplishment_report_screen.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';

final _head = User(
  id: 'h1',
  name: 'Maria Head',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);

final _supervisor = User(
  id: 'sup1',
  name: 'Sam Supervisor',
  email: 'sam@marsu.edu.ph',
  role: 'Supervisor',
);

final _admin = User(
  id: 'a1',
  name: 'Alex Admin',
  email: 'admin@marsu.edu.ph',
  role: 'Admin',
);

/// The printed name in the sign-off box captioned [caption].
String _signOffName(WidgetTester tester, String caption) {
  final box = find.ancestor(
    of: find.text(caption.toUpperCase()),
    matching: find.byType(Column),
  );
  final field = find.descendant(
    of: box.first,
    matching: find.byType(TextField),
  );
  return tester.widget<TextField>(field).controller!.text;
}

void main() {
  // A bare AppState is enough; init() would need Firebase. Recurring
  // schedule rules come from Firestore, whose repository fails soft to
  // "no rules" without it.
  Future<void> pumpScreen(
    WidgetTester tester,
    Size size, {
    required User user,
    List<User> others = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = AppState()
      ..currentUser = user
      ..users = [user, ...others]
      ..students = [
        Student(
          id: 's1',
          name: 'Charlie A. Matining',
          email: 'charlie@marsu.edu.ph',
          department: 'College of Information and Computing Sciences',
        ),
      ]
      ..offices = [
        const Office(
          id: 'o1',
          name: 'Registrar',
          code: 'REG',
          headIds: ['sup1'],
          headNames: ['Sam Supervisor'],
          assistantIds: ['s1'],
          assistantNames: ['Charlie A. Matining'],
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
  }

  Future<void> openBuilder(WidgetTester tester) async {
    await tester.tap(find.text('Generate Report').first);
    await tester.pumpAndSettle();
  }

  // The sign-off and buttons sit below the 31-day table, and the list only
  // builds what's on screen.
  Future<void> scrollToActions(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('Back to Students'),
      find.byType(ListView).last,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('student list lays out cleanly at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpScreen(tester, Size(width, 1400), user: _head);
      expect(tester.takeException(), isNull);
      expect(find.text('Charlie A. Matining'), findsOneWidget);
    });

    testWidgets('opens the report builder cleanly at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpScreen(tester, Size(width, 1400), user: _head);
      await openBuilder(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Hours This Month'), findsOneWidget);
      expect(find.text('REPORT DETAILS'), findsOneWidget);
    });
  }

  testWidgets('the Head is not offered "Send to Head"', (tester) async {
    await pumpScreen(tester, const Size(1280, 1400), user: _head);
    await openBuilder(tester);
    await scrollToActions(tester);

    expect(find.text('Send to Head'), findsNothing);
    expect(find.text('Generate & Download'), findsOneWidget);
    // The student's own office supervisor verifies the report, and the
    // Head — who is generating it — approves it, as the template reads.
    expect(_signOffName(tester, 'Verified and checked by'), 'Sam Supervisor');
    expect(_signOffName(tester, 'Approved'), 'Maria Head');
  });

  testWidgets('a supervisor can send the report to the Head', (tester) async {
    await pumpScreen(
      tester,
      const Size(1280, 1400),
      user: _supervisor,
      others: [_head, _admin],
    );
    await openBuilder(tester);
    await scrollToActions(tester);

    expect(find.text('Send to Head'), findsOneWidget);
    expect(_signOffName(tester, 'Verified and checked by'), 'Sam Supervisor');
    // Approved is the Head, not an Admin account.
    expect(_signOffName(tester, 'Approved'), 'Maria Head');
  });
}
