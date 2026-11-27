import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/main.dart' show zxingLibraryPath;
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/widgets/load_problem_banner.dart';
import 'package:projectsais/widgets/offline_banner.dart';
import 'package:provider/provider.dart';

import 'support/fake_connectivity.dart';

/// A Firestore whose profile read answers with [profile], or fails like an
/// offline read when [unreachable].
class _ProfileStore extends FirestoreService {
  User? profile;
  bool unreachable = false;

  @override
  Future<User?> getUserProfileById(String uid) async {
    if (unreachable) {
      throw Exception('unavailable: Failed to get document because the '
          'client is offline.');
    }
    return profile;
  }
}

final _supervisor = User(
  id: 'sup',
  name: 'Sid Supervisor',
  email: 'sid@example.com',
  role: 'Supervisor',
);

void main() {
  late FakeConnectivity connection;
  late _ProfileStore store;
  late AppState state;

  setUp(() {
    connection = FakeConnectivity();
    store = _ProfileStore();
    state = AppState(firestoreService: store, connectivity: connection);
  });

  group('knowing it is offline', () {
    test('follows the connection and tells the screens', () {
      var told = 0;
      state.addListener(() => told++);

      expect(state.isOffline, isFalse);
      connection.set(false);
      expect(state.isOffline, isTrue);
      connection.set(true);
      expect(state.isOffline, isFalse);
      expect(told, 2);
    });

    test('a session that could not be reopened is retried when back online',
        () async {
      state.sessionRestoreFailed = true;
      connection.set(false);
      connection.set(true);
      await Future<void>.delayed(Duration.zero);
      // Firebase isn't running in tests, so the retry finds no account; what
      // matters is that it ran and the notice went away.
      expect(state.sessionRestoreFailed, isFalse);
    });
  });

  group('reopening a signed-in session', () {
    test("offline, a staff member isn't turned into a Student", () async {
      store.unreachable = true;

      await state.restoreSessionFor(uid: 'sup', email: 'sid@example.com');

      expect(state.currentUser, isNull);
      expect(state.sessionRestoreFailed, isTrue);
    });

    test('online, the profile opens the right account', () async {
      store.profile = _supervisor;

      await state.restoreSessionFor(uid: 'sup', email: 'sid@example.com');

      expect(state.currentUser?.role, 'Supervisor');
      expect(state.sessionRestoreFailed, isFalse);
    });

    test('an account with no profile at all is still a new Student', () async {
      await state.restoreSessionFor(
        uid: 'new',
        email: 'new@example.com',
        displayName: 'New Person',
      );

      expect(state.currentUser?.role, 'Student');
      expect(state.currentUser?.name, 'New Person');
    });

    test('an account signed out meanwhile is not reopened', () async {
      store.profile = _supervisor;

      await state.restoreSessionFor(
        uid: 'sup',
        email: 'sid@example.com',
        stillSignedIn: () => false,
      );

      expect(state.currentUser, isNull);
    });

    test('someone who signed in meanwhile stays signed in', () async {
      store.profile = _supervisor;
      final other = User(
        id: 'other',
        name: 'Olive Other',
        email: 'olive@example.com',
        role: 'Head',
      );
      state.currentUser = other;

      await state.restoreSessionFor(uid: 'sup', email: 'sid@example.com');

      expect(state.currentUser?.id, 'other');
    });

    test('a retry with someone already signed in only clears the notice',
        () async {
      state
        ..currentUser = _supervisor
        ..sessionRestoreFailed = true;

      await state.retrySessionRestore();

      expect(state.sessionRestoreFailed, isFalse);
      expect(state.currentUser?.id, 'sup');
    });

    test('signing out clears the notice', () {
      state.sessionRestoreFailed = true;
      state.logout();
      expect(state.sessionRestoreFailed, isFalse);
    });
  });

  group('the offline banner', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(home: Scaffold(body: Column(children: [child]))),
        ),
      );
    }

    testWidgets('shows nothing with a connection', (tester) async {
      await pump(tester, const OfflineBanner());
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    });

    testWidgets('says what still works when signed in', (tester) async {
      await pump(tester, const OfflineBanner());
      connection.set(false);
      await tester.pump();
      expect(find.textContaining("You can still see what's open"), findsOne);
    });

    testWidgets('says signing in needs a connection', (tester) async {
      await pump(tester, const OfflineBanner(onAuthPage: true));
      connection.set(false);
      await tester.pump();
      expect(find.text("You're offline. Signing in needs a connection."),
          findsOne);
    });

    testWidgets('offers Try again when the account could not be opened',
        (tester) async {
      state.sessionRestoreFailed = true;
      await pump(tester, const OfflineBanner(onAuthPage: true));
      expect(find.textContaining("SAIS couldn't open your account"), findsOne);
      expect(find.text('Try again'), findsOne);
      expect(find.text('Sign out'), findsOne);
    });

    testWidgets('the load-problem strip steps aside while offline',
        (tester) async {
      connection.set(false);
      await pump(tester, const LoadProblemBanner());
      expect(find.byType(Container), findsNothing);
    });
  });

  group('the offline cache stays in step', () {
    test("sais-sw.js asks for the Firebase scripts firebase_core_web loads",
        () {
      final worker = File('web/sais-sw.js').readAsStringSync();
      final version = RegExp(
        r"FIREBASE_JS_VERSION = '([0-9.]+)'",
      ).firstMatch(worker)?.group(1);

      final config = jsonDecode(
        File('.dart_tool/package_config.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final package = (config['packages'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((p) => p['name'] == 'firebase_core_web');
      final root = Uri.parse(package['rootUri'] as String);
      final dir = root.isAbsolute
          ? root.toFilePath()
          : File('.dart_tool/${root.path}').absolute.path;
      final sdk = File('$dir/lib/src/firebase_sdk_version.dart')
          .readAsStringSync();
      final expected = RegExp(
        r"supportedFirebaseJsSdkVersion = '([0-9.]+)'",
      ).firstMatch(sdk)?.group(1);

      expect(version, isNotNull);
      expect(version, expected);
    });

    test('the scanner library the app asks for is the one in web/', () {
      expect(File('web/$zxingLibraryPath').existsSync(), isTrue);
      final worker = File('web/sais-sw.js').readAsStringSync();
      expect(worker, contains("'$zxingLibraryPath'"));
    });
  });
}
