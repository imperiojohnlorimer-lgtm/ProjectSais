import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/screens/auth/login_screen.dart';
import 'package:projectsais/screens/auth/register_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

void main() {
  // A bare AppState is enough: the screens only read `departments` and
  // `campuses`, which are plain fields. init() would need Firebase.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: MaterialApp(theme: AppTheme.theme, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Every breakpoint the auth layouts switch on, plus the extremes.
  const widths = [320.0, 390.0, 459.0, 460.0, 640.0, 899.0, 900.0, 1024.0,
      1440.0, 1920.0];

  group('LoginScreen', () {
    for (final width in widths) {
      testWidgets('lays out without overflow at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          LoginScreen(onShowRegister: () {}, onBack: () {}),
          Size(width, 900),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Welcome back'), findsOneWidget);
      });
    }

    testWidgets('shows the branding panel only on desktop', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(1440, 900),
      );
      expect(find.text('Duty hours that add up'), findsOneWidget);

      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(390, 844),
      );
      expect(find.text('Duty hours that add up'), findsNothing);
    });

    testWidgets('back control only appears when onBack is given', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(1440, 900),
      );
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

      var backs = 0;
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}, onBack: () => backs++),
        const Size(1440, 900),
      );
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(backs, 1);
    });

    testWidgets('register link fires its callback', (tester) async {
      var shown = 0;
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () => shown++),
        const Size(1440, 900),
      );
      // The footer link is a RichText span, not a Text widget.
      await tester.tap(
        find.textContaining('Register here', findRichText: true),
      );
      await tester.pumpAndSettle();
      expect(shown, 1);
    });

    testWidgets('empty submit surfaces an error banner', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(1440, 900),
      );
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter both email and password.'),
        findsOneWidget,
      );
    });
  });

  group('RegisterScreen', () {
    for (final width in widths) {
      testWidgets('lays out without overflow at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          RegisterScreen(onBackToLogin: () {}, onBack: () {}),
          Size(width, 1000),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Create your account'), findsOneWidget);
      });
    }

    testWidgets('groups fields under section headings', (tester) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1000),
      );
      expect(find.text('YOUR ACCOUNT'), findsOneWidget);
      expect(find.text('STUDENT DETAILS'), findsOneWidget);
      for (final label in [
        'Full name',
        'Email address',
        'Password',
        'Phone number',
        'Student ID',
        'Course/Program',
        'Year level',
        'Department',
        'Campus',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label');
      }
    });

    testWidgets('password checklist appears and counts met rules', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1000),
      );
      expect(find.text('Password requirements'), findsNothing);

      await tester.enterText(
        find.byType(TextFormField).at(2),
        'Str0ng!Pass',
      );
      await tester.pumpAndSettle();
      expect(find.text('Password requirements'), findsOneWidget);
      expect(find.text('6 of 6'), findsOneWidget);
    });

    testWidgets('empty submit surfaces an error banner', (tester) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1000),
      );
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in all required fields.'), findsOneWidget);
    });
  });
}
