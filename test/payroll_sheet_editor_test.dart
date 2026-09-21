import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/payroll_sheet_editor.dart';
import 'package:projectsais/theme/app_theme.dart';

PayrollSheet _sheet() => const PayrollSheet(
  id: 'payroll-sheet-2025-08-01-2025-12-31',
  periodStart: '2025-08-01',
  periodEnd: '2025-12-31',
  periodLabel: '1st Semester, AY 2025-2026',
  entries: [
    PayrollSheetEntry(
      studentId: 's1',
      campus: 'Boac Campus',
      name: 'Miciano, Mark Dave M.',
      hoursWorked: 80,
      remarks: 'Sept.-Nov. 2025',
    ),
    PayrollSheetEntry(
      studentId: 's2',
      campus: 'Gasan Campus',
      name: 'Lugod, Alyssa May S.',
      hoursWorked: 64,
      remarks: 'Oct.-Nov. 2025',
    ),
  ],
);

void main() {
  // A bare AppState is enough: the editor only reads the campus list until
  // the Admin saves. init() would need Firebase.
  Future<void> pumpEditor(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: PayrollSheetEditor(
              sheet: _sheet(),
              systemEntries: () => _sheet().entries,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 700.0, 1280.0]) {
    testWidgets('lays out without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpEditor(tester, Size(width, 1600));
      expect(tester.takeException(), isNull);
      expect(find.text('HOURLY WAGE PAYROLL'), findsOneWidget);
      expect(find.text('Miciano, Mark Dave M.'), findsOneWidget);
    });
  }

  testWidgets('recomputes a row as its hours are edited', (tester) async {
    await pumpEditor(tester, const Size(1280, 1600));
    // 80 hrs × ₱25.00 for the first row; 64 × 25 for the second.
    expect(
      find.textContaining('Net Pay ₱2,000.00', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('₱3,600.00'), findsOneWidget); // section total
    expect(find.text('Unsaved'), findsNothing);

    final hours = find.widgetWithText(TextField, 'Hours Worked').first;
    await tester.enterText(hours, '40');
    await tester.pump();

    expect(
      find.textContaining('Net Pay ₱1,000.00', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('₱2,600.00'), findsOneWidget);
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets('adds a blank row under the first campus', (tester) async {
    await pumpEditor(tester, const Size(1280, 1600));
    expect(find.widgetWithText(TextField, 'Name'), findsNWidgets(2));

    await tester.tap(find.text('Add Row'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Name'), findsNWidgets(3));
    expect(find.text('BOAC CAMPUS · 2'), findsOneWidget);
  });
}
