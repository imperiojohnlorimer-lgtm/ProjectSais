import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/accounts_screen.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/screens/accounts/applications_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

final _admin = User(
  id: 'a1',
  name: 'Ana Admin',
  email: 'admin@marsu.edu.ph',
  role: 'Admin',
);
final _head = User(
  id: 'h1',
  name: 'Hal Head',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);
final _sam = User(
  id: 's1',
  name: 'Sam Santos',
  email: 'sam@gmail.com',
  role: 'Student Assistant',
  status: 'Active',
  department: 'College of Education',
  campus: 'Boac',
  saId: 'SA 007',
  phone: '0917 123 4567',
  skills: const ['Typing', 'Filing'],
);

Application _application(String id, User user, {List<String> skills = const []}) =>
    Application(
      id: id,
      announcementId: 'ann1',
      announcementTitle: 'Hiring',
      applicantId: user.id,
      applicantName: user.name,
      appliedAt: '2026-09-01T08:30:00.000',
      status: 'Pending',
      academicYear: '2026-2027',
      skills: skills,
    );

void main() {
  group('the accounts spreadsheet', () {
    test('has a header and one row per account, with no phone number', () {
      final rows = accountsCsvRows([_admin, _sam]);

      expect(rows.first, [
        'Name',
        'Email',
        'Role',
        'Status',
        'Department',
        'Campus',
        'SA ID',
      ]);
      expect(rows[1], [
        'Ana Admin',
        'admin@marsu.edu.ph',
        'Admin',
        'Active',
        '',
        '',
        '',
      ]);
      expect(rows[2], [
        'Sam Santos',
        'sam@gmail.com',
        'Student Assistant',
        'Active',
        'College of Education',
        'Boac',
        'SA 007',
      ]);
      expect(rows.expand((r) => r), isNot(contains('0917 123 4567')));
    });

    test('is just the header for no accounts', () {
      expect(accountsCsvRows(const []), hasLength(1));
    });
  });

  group('the applications spreadsheet', () {
    test('lists the applicant, profile details and skills', () {
      final state = AppState()..users = [_head, _sam];
      final app = _application('app1', _sam, skills: const ['typing', 'Driving']);

      final rows = applicationsCsvRows(state, [app], {'app1': const []});

      expect(rows.first, [
        'Applicant',
        'Status',
        'Applied',
        'Academic year',
        'Department',
        'Campus',
        'Skills',
        'Matching requests',
      ]);
      expect(rows[1], [
        'Sam Santos',
        'Pending',
        '2026-09-01',
        '2026-2027',
        'College of Education',
        'Boac',
        // The application's and the profile's skills, each once.
        'typing; Driving; Filing',
        0,
      ]);
    });

    test('leaves department and campus blank when the profile is not loaded',
        () {
      final state = AppState()..users = [_head];
      final stranger = User(
        id: 'gone',
        name: 'Gone Person',
        email: 'gone@gmail.com',
        role: 'Student',
      );

      final rows = applicationsCsvRows(
        state,
        [_application('app2', stranger)],
        const {},
      );

      expect(rows[1].sublist(4, 6), ['', '']);
      expect(rows[1].last, 0);
    });
  });

  group('the Export CSV button', () {
    Future<void> pump(WidgetTester tester, AppState state, Widget home) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      // The test font draws every glyph as a full square, so some rows
      // overflow here though they fit in the app.
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(body: home),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool enabled(WidgetTester tester) => tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text('Export CSV'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap !=
        null;

    testWidgets('is on the Accounts page', (tester) async {
      final state = AppState()
        ..currentUser = _admin
        ..users = [_admin, _sam];
      await pump(tester, state, const AccountsScreen());

      expect(find.text('Export CSV'), findsOneWidget);
      expect(enabled(tester), isTrue);
    });

    testWidgets('is on Applications, off while nothing is listed', (
      tester,
    ) async {
      final state = AppState()
        ..currentUser = _head
        ..users = [_head, _sam];
      await pump(tester, state, const ApplicantScreeningScreen());

      expect(find.text('Export CSV'), findsOneWidget);
      expect(enabled(tester), isFalse);

      state.applications = [_application('app1', _sam)];
      // ignore: invalid_use_of_protected_member
      state.notifyListeners();
      await tester.pumpAndSettle();

      expect(enabled(tester), isTrue);
    });
  });
}
