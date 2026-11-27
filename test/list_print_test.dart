import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/payroll_screen.dart';
import 'package:projectsais/screens/accounts/rehiring_screen.dart';
import 'package:projectsais/screens/students/students_screen.dart';
import 'package:projectsais/utils/list_print.dart';
import 'package:projectsais/widgets/application_status.dart';

void main() {
  group('printCell', () {
    test('writes empty values as nothing and fractions with 2 decimals', () {
      expect(printCell(null), '');
      expect(printCell(7), '7');
      expect(printCell(12.5), '12.50');
      expect(printCell(0.0), '0.00');
      expect(printCell('Dela Cruz, Juan'), 'Dela Cruz, Juan');
      // A saved time prints as its day in the Philippines.
      expect(printCell('2026-11-10T20:30:00.000Z'), 'Nov 11, 2026');
      expect(printCell('2026-11-10'), '2026-11-10');
    });
  });

  group('filtersLine', () {
    test('names only the filters in use', () {
      expect(filtersLine({'Search': '', 'Role': null}), isNull);
      expect(
        filtersLine({'Search': ' dela ', 'Role': null, 'Campus': 'Boac'}),
        'Filters: Search: dela · Campus: Boac',
      );
    });
  });

  group('the lines under the title', () {
    test('add how many are listed and who printed it when', () {
      final list = PrintableList(
        title: 'Students',
        details: const ['Filters: Campus: Boac'],
        rows: const [
          ['Name'],
          ['Ana'],
          ['Ben'],
        ],
      );
      expect(printDetails(list, DateTime(2026, 11, 16, 15, 5), 'Hal Head'), [
        'Filters: Campus: Boac',
        '2 listed',
        'Printed Nov 16, 2026, 3:05 PM by Hal Head',
      ]);
      expect(
        printedLine(DateTime(2026, 1, 2, 0, 9), null),
        'Printed Jan 2, 2026, 12:09 AM',
      );
      expect(
        printedLine(DateTime(2026, 1, 2, 12, 0), ''),
        'Printed Jan 2, 2026, 12:00 PM',
      );
    });

    test('the table leaves out a column the title already says', () {
      const term = '1st Semester, AY 2026-2027';
      final table = printableTable(
        const PrintableList(
          title: 'Payroll, $term',
          rows: [
            ['Name', 'Period', 'Hours', 'Status'],
            ['Ana', term, 12.5, 'Ready'],
            ['Ben', term, 3, 'Ready'],
          ],
        ),
      );
      // Period goes; Status stays (the same on every row, but not said).
      expect(table.rows, [
        ['Name', 'Hours', 'Status'],
        ['Ana', '12.50', 'Ready'],
        ['Ben', '3', 'Ready'],
      ]);
      expect(table.numeric, {1});
    });

    test('the table always keeps who each row is', () {
      final table = printableTable(
        const PrintableList(
          title: 'Students',
          details: ['Filters: Search: Sam Santos'],
          rows: [
            ['Name', 'Hours'],
            ['Sam Santos', 2],
          ],
        ),
      );
      expect(table.rows.last, ['Sam Santos', '2']);
    });

    test('count nothing for an empty list', () {
      expect(const PrintableList(title: 'x', rows: []).count, 0);
    });

    test('keeps columns whose value is only a substring of the title or details', () {
      const term = '2nd Semester, AY 2026-2027';
      final table = printableTable(
        const PrintableList(
          title: 'Rehiring, $term',
          details: [
            'Pay period: Nov 1, 2026 to Nov 30, 2026',
            'Filters: Show: Not Evaluated · Department: CICS',
          ],
          rows: [
            ['Name', 'Term', 'Eligible', 'Evaluation', 'Code', 'Department', 'Show'],
            ['Ana', term, 'No', 'Evaluated', 'CS', 'CICS', 'Not Evaluated'],
            ['Ben', term, 'No', 'Evaluated', 'CS', 'CICS', 'Not Evaluated'],
          ],
        ),
      );
      // Term, Department, and Show match full stated values and are dropped;
      // Eligible ('No'), Evaluation ('Evaluated'), and Code ('CS') are only
      // substrings of 'Nov'/'Not Evaluated'/'CICS' and stay.
      expect(table.rows, [
        ['Name', 'Eligible', 'Evaluation', 'Code'],
        ['Ana', 'No', 'Evaluated', 'CS'],
        ['Ben', 'No', 'Evaluated', 'CS'],
      ]);
    });

    test('does not drop a column matching the Search filter', () {
      final table = printableTable(
        const PrintableList(
          title: 'Students',
          details: ['Filters: Search: Active'],
          rows: [
            ['Name', 'Status'],
            ['Ana', 'Active'],
            ['Ben', 'Active'],
          ],
        ),
      );
      expect(table.rows, [
        ['Name', 'Status'],
        ['Ana', 'Active'],
        ['Ben', 'Active'],
      ]);
    });
  });

  group('rows shared by the spreadsheet and the printout', () {
    test('Students', () {
      final state = AppState();
      final rows = studentsCsvRows(state, [
        Student(
          id: 's1',
          name: 'Sam Santos',
          email: 'sam@example.com',
          department: 'CICS',
          campus: 'Boac',
          phone: '0917 123 4567',
          totalHours: 12.345,
        ),
      ]);
      expect(rows.first.first, 'Name');
      expect(rows[1], [
        'Sam Santos',
        'sam@example.com',
        'CICS',
        'Boac',
        '0917 123 4567',
        'Active',
        12.35,
        '',
      ]);
    });

    test('Payroll names the statuses as the page does', () {
      final rows = payrollCsvRows([
        const PayrollRecord(
          id: 'p1',
          studentId: 's1',
          studentName: 'Sam Santos',
          saId: 'SA 007',
          office: '',
          periodStart: '2026-08-01',
          periodEnd: '2026-12-31',
          periodLabel: '1st Semester, AY 2026-2027',
          dtrVerified: true,
          reportVerified: false,
          status: 'Incomplete',
        ),
      ], '1st Semester, AY 2026-2027');
      expect(rows.first.length, rows[1].length);
      expect(rows[1][6], 'Not ready');
      expect(rows[1][9], 0.0);
    });

    test('Rehiring shows a missing decision as Pending', () {
      final sam = User(
        id: 's1',
        name: 'Sam Santos',
        email: 'sam@example.com',
        role: 'Student Assistant',
        saId: 'SA 007',
      );
      final rows = rehiringCsvRows([sam], {'s1': null}, {
        's1': null,
      }, '2nd Semester, AY 2026-2027');
      expect(rows[1].sublist(0, 6), [
        'Sam Santos',
        'SA 007',
        '2nd Semester, AY 2026-2027',
        null,
        'No evaluation',
        'Pending',
      ]);
    });
  });

  group('the status guide', () {
    test('explains every status, in the words each side sees', () {
      final head = applicationStatusGuide(forStudent: false);
      final student = applicationStatusGuide(forStudent: true);
      const all = [
        Application.pending,
        Application.forScreening,
        Application.approved,
        Application.waitlisted,
        Application.rejected,
      ];
      expect(head.map((e) => e.$1), all);
      expect(student.map((e) => e.$1), all);
      expect(head.last.$2, 'Rejected');
      expect(student.last.$2, 'Not accepted');
    });

    testWidgets('opens as a dialog and closes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => StatusGuideLink(
                label: 'What the statuses mean',
                onTap: () =>
                    showApplicationStatusGuide(context, forStudent: false),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('What the statuses mean'));
      await tester.pumpAndSettle();
      expect(find.text('Waitlisted'), findsOneWidget);
      expect(find.textContaining('Approve Anyway'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Waitlisted'), findsNothing);
    });
  });
}
