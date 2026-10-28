import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/profile/profile_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// A Firestore whose profile save waits for the test. The test makes [gate]
/// itself, so it lives in the test's own clock.
class _Store extends FirestoreService {
  late Completer<void> gate;
  bool fail = false;

  @override
  Future<void> setUserProfile(User user) async {
    await gate.future;
    if (fail) throw Exception('offline');
  }
}

final _user = User(
  id: 'u_1',
  name: 'Juan dela Cruz',
  email: 'juan@marsu.edu.ph',
  role: 'Supervisor',
  phone: '0917 123 4567',
  address: '123 Sample Street, Boac',
);

void main() {
  Future<_Store> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = _Store()..gate = Completer<void>();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)..currentUser = _user,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('Save changes waits for the save before saying it is updated', (
    tester,
  ) async {
    final store = await pump(tester);

    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('Profile updated.'), findsNothing);

    store.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Saving…'), findsNothing);
    expect(find.text('Profile updated.'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
  });

  testWidgets('a failed save says so and stays in the form', (tester) async {
    final store = await pump(tester);
    store.fail = true;

    await tester.tap(find.text('Save changes'));
    await tester.pump();
    store.gate.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save your profile'), findsOneWidget);
    expect(find.text('Profile updated.'), findsNothing);
    expect(find.text('Save changes'), findsOneWidget);
  });
}
