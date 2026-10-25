import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/navigation/app_router.dart';
import 'package:projectsais/screens/auth/register_screen.dart';
import 'package:projectsais/screens/privacy/privacy_notice.dart';
import 'package:projectsais/theme/app_theme.dart';

void main() {
  Future<void> pumpRegister(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: AppTheme.theme,
          home: RegisterScreen(onBackToLogin: () {}),
        ),
      ),
    );
  }

  Future<void> fillRequiredFields(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Juan');
    await tester.enterText(fields.at(2), 'Dela Cruz');
    await tester.enterText(fields.at(3), 'juan@gmail.com');
    await tester.enterText(fields.at(4), 'Zq7!kdLm92');
    await tester.enterText(fields.at(5), '09171234567');
    await tester.pump();
  }

  Future<void> createAccount(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump();
  }

  const refusal =
      'Please read and accept the Privacy Notice to create an account.';

  group('registration', () {
    testWidgets('needs the Privacy Notice accepted', (tester) async {
      await pumpRegister(tester);
      await fillRequiredFields(tester);

      await createAccount(tester);

      expect(find.text(refusal), findsOneWidget);
    });

    testWidgets('accepting it lets the form go on', (tester) async {
      await pumpRegister(tester);
      await fillRequiredFields(tester);

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await createAccount(tester);

      expect(find.text(refusal), findsNothing);
      // Let the form's short pause and the failed sign-up (no services here)
      // play out so the test ends cleanly.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the notice opens in a window, keeping what was typed', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fillRequiredFields(tester);

      await tester.ensureVisible(find.text('Read the Privacy Notice'));
      await tester.tap(find.text('Read the Privacy Notice'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Notice'), findsOneWidget);
      expect(find.text('Your rights'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Notice'), findsNothing);
      final first = tester.widget<TextFormField>(
        find.byType(TextFormField).at(0),
      );
      expect(first.controller!.text, 'Juan');
    });
  });

  group('the notice', () {
    testWidgets('is a page of its own with a way back', (tester) async {
      var back = 0;
      await tester.pumpWidget(
        MaterialApp(home: PrivacyScreen(onBack: () => back++)),
      );

      expect(find.text('Who this is from'), findsOneWidget);
      expect(find.text('What SAIS collects'), findsOneWidget);
      // The contact is still to be filled in, and the draft says so.
      expect(find.textContaining('Data Protection Officer'), findsWidgets);
      expect(find.textContaining('Draft'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      expect(back, 1);
    });

    test('has an address', () {
      expect(AppRoutes.privacy, '/privacy');
    });

    test('covers what the system really keeps', () {
      final text = PrivacyNotice.sections
          .expand((s) => [s.heading, ...s.body])
          .join(' ')
          .toLowerCase();

      for (final word in ['attendance', 'payroll', 'firebase', 'supabase']) {
        expect(text, contains(word), reason: word);
      }
    });
  });

  group('the consent on a profile', () {
    test('is saved, read back and kept through a copy', () {
      final user = User(
        id: 'u1',
        name: 'Juan Dela Cruz',
        email: 'juan@gmail.com',
        role: 'Student',
        consentAt: '2026-10-26T01:02:03.000Z',
        consentVersion: PrivacyNotice.version,
      );

      final back = User.fromJson(user.toJson());

      expect(back.consentAt, '2026-10-26T01:02:03.000Z');
      expect(back.consentVersion, PrivacyNotice.version);
      expect(
        back.copyWith(role: 'Student Assistant').consentAt,
        back.consentAt,
      );
    });

    test('is left off a profile that has none', () {
      final json = User(
        id: 'u1',
        name: 'Old Account',
        email: 'old@gmail.com',
        role: 'Student',
      ).toJson();

      expect(json.containsKey('consentAt'), isFalse);
      expect(json.containsKey('consentVersion'), isFalse);
    });
  });
}
