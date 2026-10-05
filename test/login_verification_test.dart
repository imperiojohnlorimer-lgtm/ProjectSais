import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/screens/auth/login_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Stands in for Firebase: counts sign-ins and links, answers as told.
class _FakeAuthState extends AppState {
  String? signInAnswer = AppState.unverifiedEmailMessage;
  ({bool ok, String message}) linkAnswer = (
    ok: true,
    message: 'A new verification link was sent to juan@gmail.com.',
  );
  int signIns = 0;
  int linksSent = 0;

  @override
  Future<String?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signIns++;
    return signInAnswer;
  }

  @override
  Future<({bool ok, String message})> sendNewVerificationLink(
    String email,
    String password,
  ) async {
    linksSent++;
    return linkAnswer;
  }
}

void main() {
  Future<_FakeAuthState> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = _FakeAuthState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: LoginScreen(onShowRegister: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'juan@gmail.com');
    await tester.enterText(find.byType(TextField).at(1), 'Secret123!');
    return state;
  }

  Future<void> logIn(WidgetTester tester) async {
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
  }

  testWidgets('an unverified login offers a new link instead of sending one', (
    tester,
  ) async {
    final state = await pumpLogin(tester);
    await logIn(tester);

    expect(state.signIns, 1);
    // Sending one here would replace the link the student is about to open.
    expect(state.linksSent, 0);
    expect(find.text(AppState.unverifiedEmailMessage), findsOneWidget);
    expect(find.text('Send a new link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Send a new link sends one and swaps the error for a notice', (
    tester,
  ) async {
    final state = await pumpLogin(tester);
    await logIn(tester);
    await tester.tap(find.text('Send a new link'));
    await tester.pumpAndSettle();

    expect(state.linksSent, 1);
    expect(
      find.text('A new verification link was sent to juan@gmail.com.'),
      findsOneWidget,
    );
    expect(find.text(AppState.unverifiedEmailMessage), findsNothing);
    // Another link takes another Log In first.
    expect(find.text('Send a new link'), findsNothing);
  });

  testWidgets('a link that could not be sent keeps the button', (tester) async {
    final state = await pumpLogin(tester);
    state.linkAnswer = (
      ok: false,
      message: 'Too many links were sent. Wait a few minutes, then try again.',
    );
    await logIn(tester);
    await tester.tap(find.text('Send a new link'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Too many links were sent. Wait a few minutes, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Send a new link'), findsOneWidget);
  });

  testWidgets('other login errors have no link button', (tester) async {
    final state = await pumpLogin(tester);
    state.signInAnswer = 'The password is invalid.';
    await logIn(tester);

    expect(find.text('The password is invalid.'), findsOneWidget);
    expect(find.text('Send a new link'), findsNothing);
  });

  testWidgets('typing clears the banner and its button', (tester) async {
    await pumpLogin(tester);
    await logIn(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Secret123!x');
    await tester.pump();

    expect(find.text(AppState.unverifiedEmailMessage), findsNothing);
    expect(find.text('Send a new link'), findsNothing);
  });

  testWidgets('Enter while logging in does not sign in a second time', (
    tester,
  ) async {
    final state = await pumpLogin(tester);
    await tester.tap(find.text('Log In'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.showKeyboard(find.byType(TextField).at(1));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(state.signIns, 1);
  });
}
