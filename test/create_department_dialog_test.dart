import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/create_department_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

void main() {
  testWidgets('Create Department asks for a name and code only, and its '
      'button stays in view on a short window', (tester) async {
    tester.view.physicalSize = const Size(1300, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = User(
      id: 'admin1',
      name: 'Ada Admin',
      email: 'ada@example.com',
      role: 'Admin',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: FirestoreService())
          ..currentUser = admin
          ..users = [admin],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: CreateDepartmentScreen()),
        ),
      ),
    );

    await tester.tap(find.text('Create Department').first);
    await tester.pumpAndSettle();

    expect(find.text('Department Name'), findsOneWidget);
    expect(find.text('Department Code (e.g. CICS)'), findsOneWidget);
    expect(find.text('Department Head'), findsNothing);

    // The button is pinned under the scrolling fields, inside the window.
    final button = find
        .widgetWithText(ElevatedButton, 'Create Department')
        .last;

    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(560));
  });
}
