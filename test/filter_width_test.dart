import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/supervisor/performance_evaluation_screen.dart';
import 'package:projectsais/services/firestore_service.dart';

/// The header toolbar puts its filters in a Row beside the search box, which
/// gives them unbounded width. A dropdown that fills its width (isExpanded)
/// needs a bounded one, or it fails to lay out on a wide screen.
void main() {
  for (final width in [1200.0, 900.0, 700.0]) {
    testWidgets('Performance Evaluation lays out at $width px wide', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final state = AppState(firestoreService: FirestoreService());
      state.currentUser = User(
        id: 'sup1',
        name: 'Sid Supervisor',
        email: 'sup@example.com',
        role: 'Supervisor',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(body: PerformanceEvaluationScreen()),
          ),
        ),
      );
      await tester.pump();

      // The test font draws wider than the app's, so a plain overflow isn't
      // a finding here; an unbounded-width layout failure is.
      final problems = <String>[];
      Object? error;
      while ((error = tester.takeException()) != null) {
        problems.add(error.toString());
      }
      expect(
        problems.where((p) => !p.contains('overflowed')),
        isEmpty,
        reason: 'the term filter must have a bounded width',
      );
      expect(find.byType(DropdownButton<String>), findsWidgets);
    });
  }
}
