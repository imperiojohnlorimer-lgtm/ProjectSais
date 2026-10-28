import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

import 'support/account_writes.dart';

/// A Firestore whose ID counter a test can hold back.
class _Store extends FirestoreService with AccountWrites {
  Completer<void>? gate;

  @override
  Future<String> allocateSaId(String userId, {int? seedMax}) async {
    await gate?.future;
    return super.allocateSaId(userId, seedMax: seedMax ?? 0);
  }
}

final _head = User(
  id: 'h1',
  name: 'John Lori',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);

User _assistant(int n, {bool withId = true}) => User(
  id: 's$n',
  name: 'Student $n',
  email: 'student$n@gmail.com',
  role: 'Student Assistant',
  saId: withId ? 'SA 0${n + 50}' : null,
);

Application _approved(User user) => Application(
  id: 'app_${user.id}',
  announcementId: 'ann1',
  announcementTitle: 'Hiring',
  applicantId: user.id,
  applicantName: user.name,
  appliedAt: '2026-09-01T00:00:00.000',
  status: 'Approved',
);

void main() {
  late _Store store;
  final onError = FlutterError.onError;

  setUp(() => store = _Store());

  Future<void> pumpPage(
    WidgetTester tester,
    List<User> assistants, {
    double width = 1440,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so some rows
    // overflow here though they fit in the app.
    addTearDown(() => FlutterError.onError = onError);
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);
    for (final user in assistants) {
      store.profiles[user.id] = user;
    }
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)
          ..currentUser = _head
          ..users = [_head, ...assistants]
          ..applications = [for (final u in assistants) _approved(u)],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: ApplicantScreeningScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final dialogTitle = find.text('Generate Endorsement Summary');

  testWidgets('opens the letter form for 17 approved students', (tester) async {
    await pumpPage(tester, [for (var i = 1; i <= 17; i++) _assistant(i)]);

    await tester.tap(find.text('Endorsement Summary'));
    await tester.pumpAndSettle();

    expect(dialogTitle, findsOneWidget);
    expect(find.text('Approved Student Assistants (17)'), findsOneWidget);
  });

  testWidgets('shows it is preparing while IDs are being given out', (
    tester,
  ) async {
    store.gate = Completer<void>();
    await pumpPage(tester, [_assistant(1), _assistant(2, withId: false)]);

    await tester.tap(find.text('Endorsement Summary'));
    await tester.pump();

    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('Endorsement Summary'), findsNothing);
    expect(dialogTitle, findsNothing);

    store.gate!.complete();
    await tester.pumpAndSettle();

    expect(dialogTitle, findsOneWidget);
    expect(find.text('SA 001'), findsOneWidget);
    expect(find.text('SA 051'), findsOneWidget); // the one it already held
  });

  testWidgets('says so when an ID cannot be given', (tester) async {
    await pumpPage(tester, [_assistant(1, withId: false)]);
    store.failAccountWrites = true;

    await tester.tap(find.text('Endorsement Summary'));
    await tester.pumpAndSettle();

    expect(dialogTitle, findsNothing);
    expect(
      find.textContaining('Could not prepare the Endorsement Summary'),
      findsOneWidget,
    );
    // The button is back for another try.
    expect(find.text('Endorsement Summary'), findsOneWidget);
    expect(find.text('Preparing…'), findsNothing);
  });

  testWidgets('with nobody approved it says so', (tester) async {
    await pumpPage(tester, const []);

    await tester.tap(find.text('Endorsement Summary'));
    await tester.pumpAndSettle();

    expect(find.text('No approved applicants to endorse yet.'), findsOneWidget);
  });

  testWidgets('Generate & Download waits, then reports a failure in the form', (
    tester,
  ) async {
    await pumpPage(tester, [_assistant(1)]);
    await tester.tap(find.text('Endorsement Summary'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate & Download'));
    await tester.pump();
    expect(find.text('Generating…'), findsOneWidget);

    // The Word template loads from the app's assets for real; opening the
    // file has no platform behind it here, which is the failure shown.
    for (
      var i = 0;
      i < 50 && find.text('Generating…').evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Generate & Download'), findsOneWidget);
    // Past the template and the document: it failed opening the file.
    expect(
      find.textContaining(
        'Could not generate document: MissingPluginException',
      ),
      findsOneWidget,
    );
    expect(dialogTitle, findsOneWidget);
  });
}
