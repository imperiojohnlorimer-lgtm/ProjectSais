import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/accounts_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

import 'support/account_writes.dart';

/// Account writes that wait for the test, then are refused. The test makes
/// [gate] itself, so it lives in the test's own clock.
class _Store extends FirestoreService with AccountWrites {
  late Completer<void> gate;

  @override
  Future<void> updateUserFields(String id, Map<String, dynamic> fields) async {
    await gate.future;
    failAccountWrites = true;
    return super.updateUserFields(id, fields);
  }
}

final _admin = User(
  id: 'a1',
  name: 'Ana Admin',
  firstName: 'Ana',
  lastName: 'Admin',
  email: 'ana@marsu.edu.ph',
  role: 'Admin',
);

final _sam = User(
  id: 'sa1',
  name: 'Sam Student',
  firstName: 'Sam',
  lastName: 'Student',
  email: 'sam@gmail.com',
  role: 'Student',
);

void main() {
  testWidgets('deleting shows a spinner on that button until it is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so the rows
    // overflow here though they fit in the app.
    final onError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = onError);
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);

    final store = _Store()
      ..gate = Completer<void>()
      ..profiles[_sam.id] = _sam;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)
          ..currentUser = _admin
          ..users = [_admin, _sam],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: AccountsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delete = find.byTooltip('Delete account permanently').first;
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pump();

    final spinner = find.byWidgetPredicate(
      (w) => w is CircularProgressIndicator && w.value == null,
    );
    expect(spinner, findsOneWidget);
    // The archive button is off too while it saves.
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.archive_outlined).first,
          )
          .onPressed,
      isNull,
    );

    store.gate.complete();
    await tester.pumpAndSettle();

    expect(spinner, findsNothing);
    expect(find.textContaining("Couldn't delete"), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.archive_outlined).first,
          )
          .onPressed,
      isNotNull,
    );
  });
}
