import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/payroll_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

const _department = 'College of Information and Computing Sciences';

User _assistant(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  role: 'Student Assistant',
  department: _department,
);

void main() {
  testWidgets('assistants with no office are filtered as Unassigned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
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
          ..users = [
            admin,
            _assistant('sa1', 'Ana Reyes'),
            _assistant('sa2', 'Ben Cruz'),
          ]
          ..offices = [
            const Office(
              id: 'o1',
              name: 'CICS Office',
              code: 'CICS',
              assistantIds: ['sa2'],
              assistantNames: ['Ben Cruz'],
            ),
          ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: PayrollScreen()),
        ),
      ),
    );

    expect(find.text('Unassigned office'), findsOneWidget);
    // Only the Department filter has it.
    final departmentTexts = find.text(_department).evaluate().length;

    await tester.tap(find.text('All offices'));
    await tester.pumpAndSettle();
    // The department isn't offered as an office.
    expect(find.text(_department), findsNWidgets(departmentTexts));
    expect(find.text('CICS Office'), findsWidgets);

    await tester.tap(find.text('Unassigned').last);
    await tester.pumpAndSettle();
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('Ben Cruz'), findsNothing);
  });
}
