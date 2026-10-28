import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/reports/reports_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// A Firestore whose report saves wait for the test, then fail. The test
/// makes [gate] itself, so it lives in the test's own clock.
class _Store extends FirestoreService {
  late Completer<void> gate;

  @override
  Future<void> setReport(Report r) async {
    await gate.future;
    throw Exception('offline');
  }
}

void main() {
  testWidgets('Approve waits for the save, after the question, then says why '
      'it failed', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = onError);
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);

    final store = _Store()..gate = Completer<void>();
    final supervisor = User(
      id: 'sv1',
      name: 'Sid Supervisor',
      email: 'sv@example.com',
      role: 'Supervisor',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)
          ..currentUser = supervisor
          ..users = [supervisor]
          ..offices = const [
            Office(
              id: 'o1',
              name: 'CICS Office',
              code: 'CICS',
              headIds: ['sv1'],
              headNames: ['Sid Supervisor'],
              assistantIds: ['sa1'],
              assistantNames: ['Sara Assistant'],
            ),
          ]
          ..reports = [
            Report(
              id: 'r1',
              title: 'October report',
              content: 'Filed documents.',
              studentName: 'Sara Assistant',
              status: 'Pending',
            ),
          ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: ReportsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final spinner = find.byWidgetPredicate(
      (w) => w is CircularProgressIndicator && w.value == null,
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();
    // The question is up: nothing is waiting yet.
    expect(find.text('Approve this report?'), findsOneWidget);
    expect(spinner, findsNothing);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve').last);
    await tester.pump();
    expect(find.text('Approving…'), findsOneWidget);
    expect(spinner, findsOneWidget);

    // Rejecting meanwhile does nothing: no question, no second write.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reject this report?'), findsNothing);

    store.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Failed to approve report'), findsOneWidget);
    expect(find.text('Approving…'), findsNothing);
  });
}
