import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/profile/profile_screen.dart';
import 'package:projectsais/screens/student_portal/sp_profile_screen.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/profile_widgets.dart';

User _user({String role = 'Supervisor'}) => User(
  id: 'u_1',
  name: 'Juan dela Cruz',
  email: 'juan@marsu.edu.ph',
  role: role,
  department: 'College of Information and Computing Sciences',
  campus: 'Boac Campus',
  phone: '0917 123 4567',
  address: '123 Sample Street, Boac',
  studentId: '23B0626',
  courseProgram: 'BSIT',
  yearLevel: '3rd Year',
);

void main() {
  // A bare AppState with currentUser set is enough: these screens read the
  // user and a few plain list fields. init() would need Firebase.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    Size size, {
    User? user,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState()..currentUser = user ?? _user(),
        child: MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The breakpoints the profile layout switches on, plus the extremes.
  const widths = [320.0, 390.0, 519.0, 520.0, 640.0, 899.0, 900.0, 1280.0,
      1920.0];

  group('ProfileScreen', () {
    for (final width in widths) {
      testWidgets('lays out without overflow at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          const ProfileScreen(),
          Size(width, 1400),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining("Juan dela Cruz's Profile"), findsOneWidget);
      });
    }

    testWidgets('shows the details, identity and account cards', (
      tester,
    ) async {
      await pumpScreen(tester, const ProfileScreen(), const Size(1280, 1400));
      expect(find.text('Personal Information'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('SUPERVISOR'), findsOneWidget);
      // Values from the user land in the read-only grid.
      expect(find.text('juan@marsu.edu.ph'), findsWidgets);
      expect(find.text('23B0626'), findsOneWidget);
    });

    testWidgets('fields go one per row on a phone, two when wide', (
      tester,
    ) async {
      // The old layout was a fixed two-column Row at every width.
      await pumpScreen(tester, const ProfileScreen(), const Size(390, 1600));
      final narrow = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ProfileFieldGrid),
              matching: find.byType(SizedBox),
            ),
          )
          .first
          .width!;

      await pumpScreen(tester, const ProfileScreen(), const Size(1280, 1400));
      final wide = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ProfileFieldGrid),
              matching: find.byType(SizedBox),
            ),
          )
          .first
          .width!;

      // One column fills its grid; two columns each take about half.
      expect(narrow, greaterThan(200));
      expect(wide, lessThan(narrow * 2));
    });

    testWidgets('edit toggles the grid for text fields and back', (
      tester,
    ) async {
      await pumpScreen(tester, const ProfileScreen(), const Size(1280, 1400));
      expect(find.byType(ProfileFieldGrid), findsOneWidget);
      expect(find.byType(ProfileTextField), findsNothing);

      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileFieldGrid), findsNothing);
      expect(find.byType(ProfileTextField), findsNWidgets(3));
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('the avatar carries a change-photo control', (tester) async {
      await pumpScreen(tester, const ProfileScreen(), const Size(1280, 1400));
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    });

    testWidgets('waits for the user rather than rendering empty', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(),
          child: const MaterialApp(
            home: Scaffold(body: ProfileScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Loading profile'), findsOneWidget);
    });
  });

  group('SpProfileScreen', () {
    for (final width in widths) {
      testWidgets('lays out without overflow at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          const SpProfileScreen(),
          Size(width, 1400),
          user: _user(role: 'Student'),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining("Juan dela Cruz's Profile"), findsOneWidget);
      });
    }

    testWidgets('shows its applications card, empty when there are none', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SpProfileScreen(),
        const Size(1280, 1400),
        user: _user(role: 'Student'),
      );
      expect(find.text('My Applications'), findsOneWidget);
      expect(find.text('No applications yet'), findsOneWidget);
    });

    testWidgets('edit toggles the grid for text fields', (tester) async {
      await pumpScreen(
        tester,
        const SpProfileScreen(),
        const Size(1280, 1400),
        user: _user(role: 'Student'),
      );
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileTextField), findsNWidgets(3));
    });
  });
}
