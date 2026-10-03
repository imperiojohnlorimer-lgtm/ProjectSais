import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/navigation/app_router.dart';
import 'package:projectsais/services/firestore_service.dart';

User _user(String role) => User(
  id: 'u_$role',
  name: '$role Person',
  email: '${role.replaceAll(' ', '').toLowerCase()}@example.com',
  role: role,
);

const _roles = ['Admin', 'Head', 'Supervisor', 'Student Assistant', 'Student'];

void main() {
  late AppState state;
  late AppRouterDelegate router;
  late int reports;

  setUp(() {
    state = AppState(firestoreService: FirestoreService());
    router = AppRouterDelegate(state, home: (_) => const SizedBox());
    reports = 0;
    router.addListener(() => reports++);
  });
  tearDown(() => router.dispose());

  /// Signs in as [role], the way a finished sign-in leaves AppState.
  void signIn(String role) {
    state.currentUser = _user(role);
    state.setTab(state.activeTab);
  }

  group('addresses', () {
    test('every page a role has gets its own, and leads back to it', () {
      for (final role in _roles) {
        final pages = AppRoutes.pagesFor(role);
        final paths = [for (final p in pages) AppRoutes.pathFor(role, p.id)];
        expect(paths.toSet(), hasLength(pages.length), reason: role);
        for (final page in pages) {
          expect(
            AppRoutes.tabAt(role, AppRoutes.pathFor(role, page.id)),
            page.id,
            reason: '$role ${page.id}',
          );
        }
      }
    });

    test('read like the sidebar', () {
      expect(AppRoutes.pathFor('Head', 'head_forwards'), '/sent-to-head');
      expect(AppRoutes.pathFor('Head', 'calendar'), '/schedule');
      expect(
        AppRoutes.pathFor('Head', 'announcements_admin'),
        '/announcements',
      );
      expect(
        AppRoutes.pathFor('Supervisor', 'dtr_accomplishment_report'),
        '/dtr-accomplishment-report',
      );
      expect(
        AppRoutes.pathFor('Supervisor', 'sv_announcements'),
        '/request-student-assistant',
      );
    });

    test("/notifications is each role's own Notifications page", () {
      expect(AppRoutes.tabAt('Head', '/notifications'), 'admin_notifications');
      expect(
        AppRoutes.tabAt('Supervisor', '/notifications'),
        'sa_notifications',
      );
      expect(
        AppRoutes.tabAt('Student Assistant', '/notifications'),
        'sa_notifications',
      );
      expect(AppRoutes.tabAt('Student', '/notifications'), 'notifications');
      expect(AppRoutes.tabAt('Admin', '/notifications'), isNull);
    });

    test('ignore letter case and a trailing slash', () {
      expect(AppRoutes.tabAt('Head', '/Tasks/'), 'tasks');
    });

    test("the Academic Year page's names the year, for the Admin and the "
        'Head only', () {
      expect(
        AppRoutes.academicYearPath('2026-2027'),
        '/academic-year/2026-2027',
      );
      expect(
        AppRoutes.academicYearAt('/academic-year/2026-2027/'),
        '2026-2027',
      );
      expect(AppRoutes.academicYearAt('/academic-year/next'), isNull);
      for (final role in ['Admin', 'Head']) {
        expect(
          AppRoutes.tabAt(role, '/academic-year/2026-2027'),
          AppState.academicYearTab,
        );
      }
      expect(AppRoutes.tabAt('Supervisor', '/academic-year/2026-2027'), isNull);
      expect(AppRoutes.tabAt('Head', '/academic-year/next'), isNull);
    });
  });

  group('signed out', () {
    test('the landing page, Login and Register have their own', () async {
      expect(router.currentConfiguration, '/');

      await router.setNewRoutePath('/login');
      expect(state.publicPage, PublicPage.login);
      expect(router.currentConfiguration, '/login');

      state.showPublicPage(PublicPage.register);
      expect(router.currentConfiguration, '/register');
      expect(reports, greaterThan(0));
    });

    test('a signed-in page waits on Login with its address kept, then opens '
        'after sign-in', () async {
      await router.setNewRoutePath('/tasks');

      expect(state.publicPage, PublicPage.login);
      expect(router.currentConfiguration, '/tasks');

      signIn('Student Assistant');

      expect(state.activeTab, 'tasks');
      expect(router.currentConfiguration, '/tasks');
    });

    test('leaving Login for Register forgets the page asked for', () async {
      await router.setNewRoutePath('/tasks');
      state.showPublicPage(PublicPage.register);

      expect(router.currentConfiguration, '/register');
      signIn('Student Assistant');
      expect(state.activeTab, 'dashboard');
    });

    test('signing out goes back to the public page', () async {
      signIn('Head');
      await router.setNewRoutePath('/tasks');

      state.logout();

      expect(router.currentConfiguration, '/');
    });
  });

  group('signed in', () {
    test('changing page changes the address', () {
      signIn('Supervisor');
      reports = 0;

      state.setTab('reports');

      expect(router.currentConfiguration, '/reports');
      expect(reports, 1);
    });

    test("data changes that don't change the page leave it alone", () {
      signIn('Supervisor');
      reports = 0;

      state.showPublicPage(PublicPage.register); // any AppState change
      state.setTab(state.activeTab);

      expect(reports, 0);
    });

    test('an address opens its page', () async {
      signIn('Head');

      await router.setNewRoutePath('/notifications');

      expect(state.activeTab, 'admin_notifications');
      expect(router.currentConfiguration, '/notifications');
    });

    test("a page the role doesn't have opens its first page instead", () async {
      signIn('Student Assistant');
      reports = 0;

      await router.setNewRoutePath('/payroll');

      expect(state.activeTab, 'dashboard');
      expect(router.currentConfiguration, '/dashboard');
      expect(reports, 1, reason: 'the address bar is put right');
    });

    test('a signed-in visitor sent to /login gets their first page', () async {
      signIn('Head');
      state.setTab('tasks');

      await router.setNewRoutePath('/login');

      expect(router.currentConfiguration, '/dashboard');
    });

    test('opening an academic year puts it in the address', () {
      signIn('Head');
      state.setTab('admin_notifications');

      state.openAcademicYear('2025-2026');

      expect(router.currentConfiguration, '/academic-year/2025-2026');
      expect(state.academicYearOpenedFrom, 'admin_notifications');
    });

    test('an academic year address opens that year', () async {
      signIn('Admin');

      await router.setNewRoutePath('/academic-year/2025-2026');

      expect(state.activeTab, AppState.academicYearTab);
      expect(state.academicYearShown, '2025-2026');
      expect(router.currentConfiguration, '/academic-year/2025-2026');
    });

    test('/academic-year alone opens the year in effect', () async {
      signIn('Head');

      await router.setNewRoutePath('/academic-year');

      expect(state.activeTab, AppState.academicYearTab);
      expect(router.currentConfiguration, '/academic-year/2026-2027');
    });

    test('other roles get their first page instead', () async {
      signIn('Supervisor');

      await router.setNewRoutePath('/academic-year/2026-2027');

      expect(state.activeTab, 'dashboard');
      expect(router.currentConfiguration, '/dashboard');
    });

    test('an academic year waits on Login, then opens after sign-in', () async {
      await router.setNewRoutePath('/academic-year/2025-2026');
      expect(router.currentConfiguration, '/academic-year/2025-2026');

      signIn('Head');

      expect(state.activeTab, AppState.academicYearTab);
      expect(state.academicYearShown, '2025-2026');
      expect(router.currentConfiguration, '/academic-year/2025-2026');
    });

    test('a student lands on Announcements and moves between its pages', () {
      signIn('Student');

      expect(state.activeTab, 'announcements');
      expect(router.currentConfiguration, '/announcements');

      state.setTab('profile');
      expect(router.currentConfiguration, '/profile');
    });
  });

  group('in the browser', () {
    late List<MethodCall> sent;

    Future<void> pumpApp(WidgetTester tester, String location) async {
      sent = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          sent.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: router,
          routeInformationParser: const AppRouteParser(),
          routeInformationProvider: PlatformRouteInformationProvider(
            initialRouteInformation: RouteInformation(uri: Uri.parse(location)),
          ),
        ),
      );
      await tester.pump();
    }

    /// What the browser does on Back, Forward or a typed address.
    Future<void> browserOpens(WidgetTester tester, String location) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.navigation.name,
        SystemChannels.navigation.codec.encodeMethodCall(
          MethodCall('pushRouteInformation', {
            'location': location,
            'state': null,
          }),
        ),
        (_) {},
      );
      await tester.pump();
    }

    Iterable<String> addressesShown() => sent
        .where((c) => c.method == 'routeInformationUpdated')
        .map((c) => (c.arguments as Map)['uri'].toString());

    testWidgets('opening a page link starts on that page', (tester) async {
      signIn('Supervisor');
      await pumpApp(tester, '/performance-evaluation');

      expect(state.activeTab, 'performance_evaluation');
    });

    testWidgets('Back and Forward open the page they land on', (tester) async {
      signIn('Supervisor');
      await pumpApp(tester, '/dashboard');

      await browserOpens(tester, '/tasks');
      expect(state.activeTab, 'tasks');

      await browserOpens(tester, '/dashboard');
      expect(state.activeTab, 'dashboard');
    });

    testWidgets('changing page puts its address in the address bar', (
      tester,
    ) async {
      signIn('Supervisor');
      await pumpApp(tester, '/dashboard');

      state.setTab('attendance');
      await tester.pump();

      expect(addressesShown(), contains('/attendance'));
    });

    testWidgets('a link to a signed-in page waits while the session is '
        'restored', (tester) async {
      final waits = <bool>[];
      router.dispose();
      router = AppRouterDelegate(
        state,
        home: (waiting) {
          waits.add(waiting);
          return const SizedBox();
        },
      );
      await pumpApp(tester, '/tasks');
      expect(waits.last, isTrue);

      state.sessionChecked = true;
      state.setTab(state.activeTab); // what init does once it knows
      await tester.pump();

      expect(waits.last, isFalse);
      expect(state.publicPage, PublicPage.login);
    });
  });
}
