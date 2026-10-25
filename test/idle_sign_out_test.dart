import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/utils/auth_errors.dart';
import 'package:projectsais/utils/idle_deadline.dart';
import 'package:projectsais/utils/password_validator.dart';
import 'package:projectsais/widgets/idle_sign_out_guard.dart';

void main() {
  group('friendly sign-in errors', () {
    test(
      'an unknown email, a wrong password and a bad credential sound alike',
      () {
        final messages = {
          for (final code in [
            'invalid-credential',
            'wrong-password',
            'user-not-found',
            'invalid-login-credentials',
          ])
            friendlyAuthError(code),
        };

        expect(messages, {'Wrong email or password.'});
      },
    );

    test('too many attempts and no connection say what to do', () {
      expect(friendlyAuthError('too-many-requests'), contains('Wait'));
      expect(friendlyAuthError('network-request-failed'), contains('internet'));
    });

    test('anything else is generic, never Firebase\'s own wording', () {
      expect(
        friendlyAuthError('something-new'),
        'Login failed. Please try again.',
      );
      expect(friendlyAuthError(null), 'Login failed. Please try again.');
      expect(
        friendlyAuthError('invalid-credential'),
        isNot(contains('Firebase')),
      );
    });
  });

  group('the idle limit', () {
    final start = DateTime(2026, 10, 26, 9);

    test('counts from the last activity', () {
      final idle = IdleDeadline(now: start);

      expect(idle.isExpired(start.add(const Duration(minutes: 29))), isFalse);
      expect(idle.isExpired(start.add(const Duration(minutes: 30))), isTrue);

      idle.touch(start.add(const Duration(minutes: 20)));
      expect(idle.isExpired(start.add(const Duration(minutes: 40))), isFalse);
      expect(idle.isExpired(start.add(const Duration(minutes: 50))), isTrue);
    });

    test('warns in the last two minutes only', () {
      final idle = IdleDeadline(now: start);

      expect(idle.isWarning(start.add(const Duration(minutes: 27))), isFalse);
      expect(idle.isWarning(start.add(const Duration(minutes: 28))), isTrue);
      expect(idle.isWarning(start.add(const Duration(minutes: 30))), isFalse);
      expect(
        idle.remaining(start.add(const Duration(minutes: 29))),
        const Duration(minutes: 1),
      );
    });

    test('another tab\'s activity counts', () {
      final idle = IdleDeadline(now: start);
      final now = start.add(const Duration(minutes: 31));

      expect(idle.isExpired(now), isTrue);
      expect(
        idle.isExpired(now, sharedLast: start.add(const Duration(minutes: 25))),
        isFalse,
      );
    });

    test('a clock that goes backwards is not idle time', () {
      final idle = IdleDeadline(now: start);

      expect(
        idle.idleFor(start.subtract(const Duration(minutes: 5))),
        Duration.zero,
      );
    });
  });

  group('the guard', () {
    var now = DateTime(2026, 10, 26, 9);

    Future<AppState> pump(WidgetTester tester) async {
      now = DateTime(2026, 10, 26, 9);
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = AppState()
        ..currentUser = User(
          id: 'a1',
          name: 'Ana Admin',
          email: 'a@example.com',
          role: 'Admin',
        );
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: IdleSignOutGuard(
                clock: () => now,
                child: const Center(child: Text('Dashboard')),
              ),
            ),
          ),
        ),
      );
      return state;
    }

    testWidgets('warns near the limit, then signs out and says why', (
      tester,
    ) async {
      final state = await pump(tester);

      now = now.add(const Duration(minutes: 28, seconds: 30));
      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining("signed out in about"), findsOneWidget);
      expect(state.isAuthenticated, isTrue);

      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(seconds: 16));
      // Signing out waits on the (absent) services before it finishes.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(state.isAuthenticated, isFalse);
      expect(
        state.takeSignOutNotice(),
        'You were signed out after 30 minutes without activity. Log in again '
        'to continue.',
      );
      // Said once.
      expect(state.takeSignOutNotice(), isNull);
    });

    testWidgets('a tap keeps the person signed in', (tester) async {
      final state = await pump(tester);

      now = now.add(const Duration(minutes: 25));
      await tester.tap(find.text('Dashboard'));
      now = now.add(const Duration(minutes: 25));
      await tester.pump(const Duration(seconds: 16));

      expect(state.isAuthenticated, isTrue);
    });

    testWidgets('nobody is signed out when nobody is signed in', (
      tester,
    ) async {
      final state = await pump(tester);
      state.logout();

      now = now.add(const Duration(hours: 3));
      await tester.pump(const Duration(seconds: 16));

      expect(state.takeSignOutNotice(), isNull);
    });
  });

  group('Remember me', () {
    test('is passed on to the sign-in', () async {
      final state = AppState();

      // No Firebase here, so the sign-in itself fails; the choice is made
      // before it, which is what is checked.
      final problem = await state.signInWithEmailAndPassword(
        'a@example.com',
        'x',
        remember: false,
      );

      expect(state.rememberChoice, isFalse);
      expect(problem, 'Login failed. Please try again.');
    });
  });

  group('passwords', () {
    test('need ten characters', () {
      expect(PasswordValidator.validate('Zq7!kdLm9').isValid, isFalse);
      expect(PasswordValidator.validate('Zq7!kdLm92').isValid, isTrue);
    });

    test('refuse the ones everybody tries, however they are dressed up', () {
      for (final common in [
        'Password#2026',
        'Welcome#2026',
        'Marsu#2026!!',
      ]) {
        final result = PasswordValidator.validate(common);
        expect(result.isValid, isFalse, reason: common);
      }
      expect(PasswordValidator.validate('Zq7!kdLm92').errors, isEmpty);
    });
  });
}
