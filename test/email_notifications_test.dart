import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/push_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/email_notifications_card.dart';

/// Keeps the profile it is asked to save, or refuses.
class _Store extends FirestoreService {
  final saved = <User>[];
  bool fail = false;

  @override
  Future<void> setUserProfile(User user) async {
    if (fail) throw Exception('offline');
    saved.add(user);
  }
}

class _Push extends PushService {
  int tests = 0;
  ({bool ok, String message}) answer = (
    ok: true,
    message: 'A test email was sent to s***@gmail.com. Check your inbox.',
  );

  @override
  Future<({bool ok, String message})> sendTestEmail() async {
    tests++;
    return answer;
  }
}

User _user({String role = 'Student Assistant', bool? email}) => User(
  id: 'u1',
  name: 'Sam Santos',
  email: 'sam@gmail.com',
  role: role,
  emailNotifications: email,
);

void main() {
  group('the email setting on a profile', () {
    test('counts as on until the person turns it off', () {
      expect(_user().emailsOn, isTrue);
      expect(_user(email: true).emailsOn, isTrue);
      expect(_user(email: false).emailsOn, isFalse);
    });

    test('is left out of a profile that never chose, so it saves as before',
        () {
      expect(_user().toJson().containsKey('emailNotifications'), isFalse);
      expect(_user(email: false).toJson()['emailNotifications'], isFalse);
      expect(_user(email: true).toJson()['emailNotifications'], isTrue);
    });

    test('reads back from a saved profile, and ignores anything else', () {
      final base = _user().toJson();
      expect(
        User.fromJson({...base, 'emailNotifications': false}).emailNotifications,
        isFalse,
      );
      expect(User.fromJson(base).emailNotifications, isNull);
      expect(
        User.fromJson({...base, 'emailNotifications': 'no'}).emailNotifications,
        isNull,
      );
    });

    test('survives copying the profile', () {
      expect(_user(email: false).copyWith(phone: '0917').emailNotifications,
          isFalse);
      expect(_user().copyWith(emailNotifications: false).emailsOn, isFalse);
    });
  });

  group('AppState.updateProfile', () {
    test('saves the choice, and puts it back when the save fails', () async {
      final store = _Store();
      final state = AppState(firestoreService: store)..currentUser = _user();
      state.users = [state.currentUser!];

      await state.updateProfile(emailNotifications: false);
      expect(state.currentUser!.emailsOn, isFalse);
      expect(store.saved.single.emailNotifications, isFalse);

      store.fail = true;
      await expectLater(
        state.updateProfile(emailNotifications: true),
        throwsException,
      );
      expect(state.currentUser!.emailsOn, isFalse);
      expect(state.users.single.emailsOn, isFalse);
    });
  });

  group('an Admin editing someone else', () {
    test('carries the latest email choice, not the dialog copy\'s old one',
        () async {
      final store = _Store();
      final admin = User(
        id: 'a1',
        name: 'Ana Admin',
        email: 'admin@marsu.edu.ph',
        role: 'Admin',
      );
      // The dialog opened when they still had email on; since then they
      // turned it off, and the live list knows.
      final stale = _user(email: true);
      final state = AppState(firestoreService: store)
        ..currentUser = admin
        ..users = [admin, _user(email: false)];

      await state.updateManagedUser(stale.copyWith(phone: '0917 123 4567'));

      expect(store.saved.single.phone, '0917 123 4567');
      expect(store.saved.single.emailNotifications, isFalse);
    });

    test('leaves a profile that never chose without the field', () async {
      final store = _Store();
      final admin = User(
        id: 'a1',
        name: 'Ana Admin',
        email: 'admin@marsu.edu.ph',
        role: 'Admin',
      );
      final state = AppState(firestoreService: store)
        ..currentUser = admin
        ..users = [admin, _user()];

      await state.updateManagedUser(_user().copyWith(phone: '0917 123 4567'));

      expect(
        store.saved.single.toJson().containsKey('emailNotifications'),
        isFalse,
      );
    });

    test('withEmailNotifications can put the choice back to unset', () {
      expect(_user(email: false).withEmailNotifications(null).emailNotifications,
          isNull);
      expect(_user().withEmailNotifications(false).emailsOn, isFalse);
    });
  });

  group('the card', () {
    late _Store store;
    late _Push push;

    Future<AppState> pump(WidgetTester tester, User user) async {
      store = _Store();
      push = _Push();
      final state = AppState(firestoreService: store, pushService: push)
        ..currentUser = user
        ..users = [user];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: EmailNotificationsCard()),
          ),
        ),
      );
      return state;
    }

    testWidgets('says it is on, with the address, until turned off', (
      tester,
    ) async {
      await pump(tester, _user());

      expect(find.text('Email notifications'), findsOneWidget);
      expect(find.textContaining('sam@gmail.com'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Send a test email'), findsOneWidget);
    });

    testWidgets('the switch turns it off and saves, and hides the test', (
      tester,
    ) async {
      final state = await pump(tester, _user());

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(state.currentUser!.emailsOn, isFalse);
      expect(store.saved.single.emailNotifications, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('Send a test email'), findsNothing);
      expect(find.textContaining('Off.'), findsOneWidget);
    });

    testWidgets('a failed save leaves it as it was and says so', (
      tester,
    ) async {
      final state = await pump(tester, _user());
      store.fail = true;

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(state.currentUser!.emailsOn, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(
        find.textContaining('Could not change email notifications'),
        findsOneWidget,
      );
    });

    testWidgets('Send a test email reports the answer', (tester) async {
      await pump(tester, _user());

      await tester.tap(find.text('Send a test email'));
      await tester.pumpAndSettle();

      expect(push.tests, 1);
      expect(find.textContaining('A test email was sent'), findsOneWidget);
    });

    testWidgets('Send a test email shows why it could not', (tester) async {
      await pump(tester, _user());
      push.answer = (ok: false, message: 'Please wait a minute.');

      await tester.tap(find.text('Send a test email'));
      await tester.pumpAndSettle();

      expect(find.text('Please wait a minute.'), findsOneWidget);
    });

    testWidgets('is not shown to the Admin, who gets no notifications', (
      tester,
    ) async {
      await pump(tester, _user(role: 'Admin'));

      expect(find.text('Email notifications'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });
}
