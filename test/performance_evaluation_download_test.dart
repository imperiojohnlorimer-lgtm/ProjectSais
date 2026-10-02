import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/supervisor/performance_evaluation_screen.dart';
import 'package:projectsais/services/firestore_service.dart';

void main() {
  testWidgets('Download shows it is preparing the file until it is done', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = AppState(firestoreService: FirestoreService());
    state.currentUser = User(
      id: 'sup1',
      name: 'Sid Supervisor',
      email: 'sup@example.com',
      role: 'Supervisor',
    );
    state.offices = [
      Office(
        id: 'o1',
        name: 'CICS Office',
        code: 'CICS',
        headIds: const ['sup1'],
        headNames: const ['Sid Supervisor'],
        assistantIds: const ['sa1'],
        assistantNames: const ['Sara Assistant'],
      ),
    ];
    state.students = [
      Student(
        id: 'sa1',
        userId: 'sa1',
        name: 'Sara Assistant',
        email: 'sa@example.com',
        department: 'College of Information and Computing Sciences',
      ),
    ];
    state.evaluations = [
      Evaluation(
        id: 'e1',
        studentId: 'sa1',
        studentName: 'Sara Assistant',
        office: 'CICS Office',
        term: 'First Semester',
        periodCovered: 'August 2026 – December 2026',
        dateOfRating: 'Oct 3, 2026',
        eligibleForRehire: true,
        ratings: const {},
        overallRating: 6,
        departmentHeadComments: '',
        supervisorId: 'sup1',
        supervisorName: 'Sid Supervisor',
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: PerformanceEvaluationScreen()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The Word template loads from the app's assets for real.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Preparing…'), findsNothing);
  });
}
