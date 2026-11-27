import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/navigation/app_router.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

User _user(String role, {String id = 'u1'}) =>
    User(id: id, name: '$role Person', email: '$id@example.com', role: role);

void main() {
  late AppState state;
  late AppRouterDelegate router;

  /// Signs in (or switches account or role), the way AppState notifies.
  void signInAs(User user) {
    state.currentUser = user;
    state.setTab(state.activeTab);
  }

  /// The app as main.dart builds it, with a page that opens things when
  /// signed in and says "Login" when not.
  Future<void> pumpApp(
    WidgetTester tester, {
    Widget Function(BuildContext context)? signedIn,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      ),
    );
    router = AppRouterDelegate(
      state,
      home: (_) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => Scaffold(
          body: state.isAuthenticated
              ? Builder(
                  builder:
                      signedIn ??
                      (context) => Column(
                        children: [
                          TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  const AlertDialog(title: Text('Preview')),
                            ),
                            child: const Text('Open dialog'),
                          ),
                          TextButton(
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              builder: (_) => const Text('Sheet'),
                            ),
                            child: const Text('Open sheet'),
                          ),
                          TextButton(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Time to clock out'),
                                    duration: Duration(seconds: 20),
                                  ),
                                ),
                            child: const Text('Show snackbar'),
                          ),
                        ],
                      ),
                )
              : const Text('Login'),
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: router,
        routeInformationParser: const AppRouteParser(),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => state = AppState());

  group('what was open closes when the signed-in person changes', () {
    testWidgets('signing out closes an open dialog', (tester) async {
      signInAs(_user('Head'));
      await pumpApp(tester);
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Preview'), findsOneWidget);

      state.logout();
      await tester.pumpAndSettle();

      expect(find.text('Preview'), findsNothing);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('and a bottom sheet, and a snackbar', (tester) async {
      signInAs(_user('Supervisor'));
      await pumpApp(tester);
      await tester.tap(find.text('Show snackbar'));
      await tester.pump();
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet'), findsOneWidget);
      expect(find.text('Time to clock out'), findsOneWidget);

      state.logout();
      await tester.pumpAndSettle();

      expect(find.text('Sheet'), findsNothing);
      expect(find.text('Time to clock out'), findsNothing);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('a role change closes it; the same person again does not', (
      tester,
    ) async {
      signInAs(_user('Student Assistant'));
      await pumpApp(tester);
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      // A profile refresh: a new object, same account and role.
      signInAs(_user('Student Assistant'));
      await tester.pumpAndSettle();
      expect(find.text('Preview'), findsOneWidget);

      signInAs(_user('Student'));
      await tester.pumpAndSettle();
      expect(find.text('Preview'), findsNothing);
    });

    testWidgets('a dialog open while signing in closes', (tester) async {
      await pumpApp(tester, signedIn: (_) => const Text('Dashboard'));
      // Login's "Forgot password?" dialog, say.
      unawaited(
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Reset password')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reset password'), findsOneWidget);

      signInAs(_user('Head'));
      await tester.pumpAndSettle();
      expect(find.text('Reset password'), findsNothing);
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('signing out from a confirm dialog with the busy card', (
      tester,
    ) async {
      signInAs(_user('Head'));
      await pumpApp(
        tester,
        signedIn: (context) => TextButton(
          onPressed: () async {
            final ok = await showConfirmDialog(
              context,
              title: 'Log out?',
              message: 'You will be signed out.',
            );
            if (!ok || !context.mounted) return;
            await runWithBusy(context, () async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              state.logout();
            });
          },
          child: const Text('Log out'),
        ),
      );
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Working…'), findsNothing);
    });

    testWidgets(
      'a dialog whose save finishes as it is closed for sign-out leaves '
      'the app showing',
      (tester) async {
        final save = Completer<void>();
        signInAs(_user('Admin'));
        await pumpApp(
          tester,
          signedIn: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Edit account'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await save.future;
                      // Guarded the way most dialogs are: still mounted
                      // while it closes, so it pops what is under it,
                      // twice here (two dialogs finishing at once).
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            child: const Text('Open editor'),
          ),
        );
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pump();

        state.logout();
        await tester.pump(); // the dialog starts closing
        save.complete();
        // Login stays on screen through every frame: the app's page is
        // never taken away, not even for a moment.
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('Login'), findsOneWidget, reason: 'frame $i');
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Edit account'), findsNothing);
        expect(find.text('Login'), findsOneWidget);
      },
    );

    testWidgets('a snackbar shown once signed out stays', (tester) async {
      signInAs(_user('Head'));
      await pumpApp(tester);
      final messenger = ScaffoldMessenger.of(
        router.navigatorKey.currentContext!,
      );

      // As the shells do: sign out, then say so.
      state.logout();
      messenger.showSnackBar(
        const SnackBar(content: Text('You have been logged out')),
      );
      await tester.pumpAndSettle();

      expect(find.text('You have been logged out'), findsOneWidget);
    });
  });

  group('showConfirmDialog', () {
    testWidgets('answers with the button pressed', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await showConfirmDialog(
                context,
                title: 'Delete?',
                message: 'Sure?',
                confirmLabel: 'Delete',
              ),
              child: const Text('Ask'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('still closes after what opened it was removed', (
      tester,
    ) async {
      final shown = ValueNotifier(true);
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: shown,
              builder: (_, show, _) => show
                  ? Builder(
                      builder: (context) => TextButton(
                        onPressed: () async => answer = await showConfirmDialog(
                          context,
                          title: 'Archive?',
                          message: 'Sure?',
                        ),
                        child: const Text('Ask'),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      shown.value = false; // a live update removed the row
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Archive?'), findsNothing);
      expect(answer, isFalse);
    });
  });

  group('the page shown after signing out', () {
    test('a plain sign-out goes to the landing page', () {
      state.currentUser = _user('Head');
      state.logout();
      expect(state.publicPage, PublicPage.landing);
    });

    testWidgets('signed out for inactivity: Login, with the notice', (
      tester,
    ) async {
      state.currentUser = _user('Head');
      final done = state.signOutForInactivity(const Duration(minutes: 30));
      // Signing out waits on the (absent) services before it finishes.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.runAsync(() => done);

      expect(state.isAuthenticated, isFalse);
      expect(state.publicPage, PublicPage.login);
      expect(state.takeSignOutNotice(), contains('30 minutes'));
    });
  });

  group('popIfCurrent', () {
    testWidgets('closes its own dialog, and nothing under one closing', (
      tester,
    ) async {
      late BuildContext dialogContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (inner) {
                  dialogContext = inner;
                  return const AlertDialog(title: Text('Editor'));
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      Navigator.of(dialogContext).pop(); // closed from outside
      await tester.pump();
      popIfCurrent(dialogContext); // its own save finishing: no effect
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      popIfCurrent(dialogContext);
      await tester.pumpAndSettle();
      expect(find.text('Editor'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });
  });
}
