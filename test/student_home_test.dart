import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/navigation/app_router.dart';
import 'package:projectsais/screens/student_portal/student_home_screen.dart';
import 'package:projectsais/screens/student_portal/student_portal_shell.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

final _student = User(
  id: 'stu1',
  name: 'Sam Student',
  firstName: 'Sam',
  lastName: 'Student',
  email: 'sam@marsu.edu.ph',
  role: 'Student',
);

Announcement _call({
  bool isOpen = true,
  String? deadline,
  List<String> requirements = const ['Resume::pdf', 'Grades'],
}) => Announcement(
  id: 'call1',
  title: 'Student Assistant Hiring',
  body: 'Apply to be a Student Assistant.',
  postedBy: 'Helen Head',
  postedAt: '10/1/2026',
  isOpen: isOpen,
  deadline: deadline,
  requirements: requirements,
);

Application _application(String status) => Application(
  id: Application.idFor(_student.id, '2026-2027'),
  announcementId: 'call1',
  announcementTitle: Application.generalTitle,
  applicantId: _student.id,
  applicantName: _student.name,
  appliedAt: 'Oct 2, 2026',
  status: status,
  skills: const [],
  academicYear: '2026-2027',
);

void main() {
  late AppState state;

  setUp(() {
    state = AppState(firestoreService: FirestoreService())
      ..currentUser = _student
      ..users = [_student];
  });

  Future<void> pump(WidgetTester tester, Widget screen, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so some rows
    // overflow here though they fit in the app.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);
    addTearDown(() => FlutterError.onError = onError);
    // A new key each time, so a second call starts the page afresh with
    // whatever the state holds by then.
    await tester.pumpWidget(
      KeyedSubtree(
        key: UniqueKey(),
        child: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(body: screen),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the portal\'s pages', () {
    test('start with Home, which a student opens on', () {
      expect(StudentPortalShell.pages.first, (id: 'home', label: 'Home'));
      expect(AppRoutes.homeTab('Student'), 'home');
      expect(AppRoutes.pathFor('Student', 'home'), '/home');
      expect(AppRoutes.tabAt('Student', '/apply'), 'announcements');
    });

    test('the greeting uses the first name, then the name', () {
      expect(StudentHomeScreen.greeting(_student), 'Welcome, Sam');
      expect(
        StudentHomeScreen.greeting(
          User(id: 'x', name: 'Rita Reyes', email: 'r@e.com', role: 'Student'),
        ),
        'Welcome, Rita',
      );
      expect(StudentHomeScreen.greeting(null), 'Welcome');
    });
  });

  group('the Home page', () {
    testWidgets('welcomes a new student and points to Apply', (tester) async {
      state.announcements = [_call(deadline: '10/30/2026')];

      await pump(tester, const StudentHomeScreen(), const Size(390, 900));

      expect(find.text('Welcome, Sam'), findsOneWidget);
      expect(find.text('HOW IT WORKS'), findsOneWidget);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Start working'), findsOneWidget);
      expect(find.textContaining('Hiring is open'), findsOneWidget);
      // Requirement names, not the raw "Resume::pdf" form.
      expect(find.textContaining('Resume, Grades'), findsOneWidget);
      expect(find.textContaining('::'), findsNothing);

      await tester.ensureVisible(find.text('Continue to Apply'));
      await tester.tap(find.text('Continue to Apply'));
      expect(state.activeTab, 'announcements');
    });

    testWidgets('says why applying is closed, as the Apply page does', (
      tester,
    ) async {
      await pump(tester, const StudentHomeScreen(), const Size(1300, 900));

      expect(
        find.textContaining("Applications aren't open yet"),
        findsOneWidget,
      );
      expect(find.text('Continue to Apply'), findsOneWidget);
    });

    testWidgets('follows the application: waiting, screening, decided', (
      tester,
    ) async {
      state.announcements = [_call()];

      state.applications = [_application(Application.pending)];
      await pump(tester, const StudentHomeScreen(), const Size(390, 900));
      expect(find.textContaining('Submitted.'), findsOneWidget);
      expect(find.text('View my application'), findsOneWidget);
      expect(find.textContaining('Have ready'), findsNothing);

      state.applications = [_application(Application.forScreening)];
      await pump(tester, const StudentHomeScreen(), const Size(390, 900));
      expect(find.textContaining('selected for screening'), findsOneWidget);

      state.applications = [_application(Application.approved)];
      await pump(tester, const StudentHomeScreen(), const Size(390, 900));
      expect(find.textContaining('now a Student Assistant'), findsOneWidget);

      state.applications = [_application(Application.waitlisted)];
      await pump(tester, const StudentHomeScreen(), const Size(390, 900));
      expect(find.textContaining('waitlist'), findsOneWidget);
      expect(find.text('Waitlisted'), findsOneWidget);
    });

    testWidgets('a rejected student can apply again only while it is open', (
      tester,
    ) async {
      state
        ..announcements = [_call()]
        ..applications = [_application(Application.rejected)];

      await pump(tester, const StudentHomeScreen(), const Size(390, 900));
      expect(find.text('Apply Again'), findsOneWidget);
      expect(find.text('Not accepted'), findsOneWidget);

      state.announcements = [_call(isOpen: false)];
      await pump(tester, const StudentHomeScreen(), const Size(390, 900));
      expect(find.text('Apply Again'), findsNothing);
      expect(find.text('View my application'), findsOneWidget);
    });
  });

  group('the portal shell', () {
    testWidgets('opens on Home and keeps the bell and avatar on their pages', (
      tester,
    ) async {
      state.activeTab = 'dashboard';

      await pump(tester, const StudentPortalShell(), const Size(1440, 1000));
      expect(find.text('Welcome, Sam'), findsOneWidget);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(state.activeTab, 'notifications');

      await tester.tap(find.byTooltip('View Profile'));
      await tester.pumpAndSettle();
      expect(state.activeTab, 'profile');

      await tester.tap(find.text('Home').first);
      await tester.pumpAndSettle();
      expect(state.activeTab, 'home');
      await tester.tap(find.text('Continue to Apply'));
      await tester.pumpAndSettle();
      expect(state.activeTab, 'announcements');
    });

    testWidgets('on a phone, the four tabs fit and Apply is the second', (
      tester,
    ) async {
      state.activeTab = 'home';

      await pump(tester, const StudentPortalShell(), const Size(320, 700));

      for (final label in ['Home', 'Apply', 'Notifications', 'Profile']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('Apply').last);
      await tester.pumpAndSettle();
      expect(state.activeTab, 'announcements');
    });
  });
}
