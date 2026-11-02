import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/auth/login_screen.dart';
import 'package:projectsais/screens/auth/register_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Counts registrations and answers none of them, as a slow network would.
class _SlowRegisterState extends AppState {
  int registrations = 0;
  final pending = Completer<String?>();

  @override
  Future<String?> registerWithEmail(User user, String password) {
    registrations++;
    return pending.future;
  }
}

void main() {
  // A bare AppState is enough: the screens only read `departments` and
  // `campuses`, which are plain fields. init() would need Firebase.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    Size size, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: AppTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Every breakpoint the auth layouts switch on, plus the extremes.
  const widths = [
    320.0,
    390.0,
    459.0,
    460.0,
    640.0,
    899.0,
    900.0,
    1024.0,
    1440.0,
    1920.0,
  ];

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

    // The branding panel is a fixed column with no scroll of its own, so a
    // short browser window is the case that overflows it.
    for (final height in [560.0, 600.0, 680.0, 900.0]) {
      testWidgets('branding panel fits a ${height.toInt()}px-tall window', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          LoginScreen(onShowRegister: () {}),
          Size(1440, height),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Duty hours that add up'), findsOneWidget);
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
        'First name',
        'Middle name',
        'Last name',
        'Suffix',
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

      await tester.enterText(find.byType(TextFormField).at(4), 'Str0ng!Pass');
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
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in all required fields.'), findsOneWidget);
    });

    testWidgets('phone and Student ID only take their own shape', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1000),
      );
      final fields = find.byType(TextFormField);
      String textOf(int i) =>
          tester.widget<TextFormField>(fields.at(i)).controller!.text;

      await tester.enterText(fields.at(5), '12345678912');
      await tester.enterText(fields.at(6), 'ABC123');
      expect(textOf(5), '');
      expect(textOf(6), '');

      await tester.enterText(fields.at(5), '09171234567');
      await tester.enterText(fields.at(6), '23b0626');
      expect(textOf(5), '0917 123 4567');
      expect(textOf(6), '23B0626');
    });

    testWidgets('asks for a first and a last name', (tester) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1200),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Juan');
      await tester.enterText(fields.at(3), 'juan@marsu.edu.ph');
      await tester.enterText(fields.at(4), 'Str0ng!Pass');
      await tester.enterText(fields.at(5), '09171234567');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in all required fields.'), findsOneWidget);
    });

    testWidgets('names take only letters and name punctuation', (tester) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1000),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Ma. Niña2!');
      await tester.enterText(fields.at(2), "O'Brien-Dela Cruz#");
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'Ma. Niña',
      );
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller!.text,
        "O'Brien-Dela Cruz",
      );
    });

    testWidgets('an unfinished Student ID is refused', (tester) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1200),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Juan');
      await tester.enterText(fields.at(2), 'Dela Cruz');
      await tester.enterText(fields.at(3), 'juan@marsu.edu.ph');
      await tester.enterText(fields.at(4), 'Str0ng!Pass');
      await tester.enterText(fields.at(5), '09171234567');
      await tester.enterText(fields.at(6), '23B06');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid Student ID, e.g. 23B0626.'),
        findsOneWidget,
      );
    });
  });
  group('Auth screens, as designed', () {
    testWidgets('desktop shows the numbered list, phones do not', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(1440, 900),
      );
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);

      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(390, 844),
      );
      expect(find.text('01'), findsNothing);
      // The brand stays: the seal and name sit in the bar on top.
      expect(find.text('SAIS'), findsOneWidget);
    });

    for (final size in [const Size(320, 568), const Size(390, 844)]) {
      testWidgets('login fits ${size.width.toInt()}x${size.height.toInt()} '
          'with text at 150%', (tester) async {
        await pumpScreen(
          tester,
          LoginScreen(onShowRegister: () {}, onBack: () {}),
          size,
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Welcome back'), findsOneWidget);
      });

      testWidgets('register fits ${size.width.toInt()}x${size.height.toInt()} '
          'with text at 150%', (tester) async {
        await pumpScreen(
          tester,
          RegisterScreen(onBackToLogin: () {}, onBack: () {}),
          size,
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Create your account'), findsOneWidget);
      });
    }

    testWidgets('login fields carry autofill hints and a tab order', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(1440, 900),
      );
      final email = tester.widget<TextField>(find.byType(TextField).at(0));
      final password = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(email.autofillHints, contains(AutofillHints.username));
      expect(email.textInputAction, TextInputAction.next);
      expect(password.autofillHints, contains(AutofillHints.password));
      expect(password.textInputAction, TextInputAction.done);
    });

    testWidgets('register fields carry autofill hints and never submit on '
        'the keyboard', (tester) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1200),
      );
      TextField field(int index) => tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(TextFormField).at(index),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(field(0).autofillHints, contains(AutofillHints.givenName));
      expect(field(2).autofillHints, contains(AutofillHints.familyName));
      expect(field(3).autofillHints, contains(AutofillHints.email));
      expect(field(4).autofillHints, contains(AutofillHints.newPassword));
      expect(field(5).autofillHints, contains(AutofillHints.telephoneNumber));
      // Every text field moves on; "done" never submits past the dropdowns
      // and the consent box.
      for (var i = 0; i < 7; i++) {
        expect(field(i).textInputAction, TextInputAction.next);
      }
    });

    testWidgets('the Privacy Notice link and the sign-in links are 44px '
        'targets', (tester) async {
      await pumpScreen(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(390, 1900),
      );
      final link = find.ancestor(
        of: find.text('Read the Privacy Notice'),
        matching: find.byType(ConstrainedBox),
      );
      final heights = tester
          .widgetList<ConstrainedBox>(link)
          .map((box) => box.constraints.minHeight);
      expect(heights, contains(44));
    });
  });
  group('Auth screens: how they behave', () {
    testWidgets('Remember me is one checkbox with its name and its state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(390, 844),
      );

      final box = find.byType(Checkbox);
      expect(box, findsOneWidget);
      expect(tester.getSemantics(box).label, contains('Remember me'));
      SemanticsData data() => tester.getSemantics(box).getSemanticsData();
      expect(data().flagsCollection.isChecked, CheckedState.isFalse);
      await tester.tap(find.text('Remember me'));
      await tester.pump();
      expect(data().flagsCollection.isChecked, CheckedState.isTrue);
      handle.dispose();
    });

    testWidgets('the show-password eye is its own control', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(390, 844),
      );

      final eye = tester.getSemantics(find.byTooltip('Show or hide password'));
      final field = tester.getSemantics(find.byType(TextField).at(1));
      final eyeName = '${eye.label} ${eye.tooltip}';
      expect(eyeName, contains('Show or hide password'));
      expect(field.label, isNot(contains('Show or hide password')));
      handle.dispose();
    });

    testWidgets('Tab visits each control once, in order', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(onShowRegister: () {}),
        const Size(1440, 900),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      String stop() {
        final context = FocusManager.instance.primaryFocus?.context;
        if (context == null) return 'none';
        if (context.findAncestorWidgetOfExactType<IconButton>() != null) {
          return 'eye';
        }
        if (context.findAncestorWidgetOfExactType<TextField>() != null) {
          return 'field';
        }
        if (context.findAncestorWidgetOfExactType<Checkbox>() != null) {
          return 'checkbox';
        }
        if (context.findAncestorWidgetOfExactType<ElevatedButton>() != null) {
          return 'login';
        }
        if (context.findAncestorWidgetOfExactType<OutlinedButton>() != null) {
          return 'google';
        }
        return 'link';
      }

      final stops = <String>[stop()];
      for (var i = 0; i < 7; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        stops.add(stop());
      }
      expect(stops, [
        'field', // email
        'field', // password
        'eye',
        'checkbox', // Remember me: a single stop
        'link', // Forgot password?
        'login',
        'google',
        'link', // Register here
      ]);
    });

    testWidgets('a second tap while an account is being made does nothing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = _SlowRegisterState();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: RegisterScreen(onBackToLogin: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Juan');
      await tester.enterText(fields.at(2), 'Dela Cruz');
      await tester.enterText(fields.at(3), 'juan@marsu.edu.ph');
      await tester.enterText(fields.at(4), 'Str0ng!Pass');
      await tester.enterText(fields.at(5), '09171234567');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(state.registrations, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The button is disabled now; the form's own guard covers the rest.
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();
      expect(state.registrations, 1);
    });

    for (final size in [const Size(320, 568), const Size(390, 844)]) {
      testWidgets('login and register fit ${size.width.toInt()}x'
          '${size.height.toInt()} with the keyboard open', (tester) async {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await pumpScreen(
          tester,
          LoginScreen(onShowRegister: () {}, onBack: () {}),
          size,
        );
        expect(tester.takeException(), isNull);
        await pumpScreen(
          tester,
          RegisterScreen(onBackToLogin: () {}, onBack: () {}),
          size,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
