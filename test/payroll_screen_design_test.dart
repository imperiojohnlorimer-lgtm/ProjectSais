import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/payroll_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

const _term = '1st Semester, AY 2026-2027';

const _checked = PayrollCheckMark(
  status: PayrollCheckMark.checked,
  by: 'Hana Head',
  at: '2026-12-01T09:00:00.000',
);

PayrollCheck _allChecked(String studentId) => PayrollCheck(
  studentId: studentId,
  items: {
    PayrollRequirement.requirementsKey: _checked,
    PayrollRequirement.endorsementKey: _checked,
    PayrollRequirement.contractKey(_term): _checked,
    PayrollRequirement.dtrKey(2026, 9): _checked,
  },
);

User _assistant(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  role: 'Student Assistant',
);

final _admin = User(
  id: 'admin1',
  name: 'Ada Admin',
  email: 'admin@example.com',
  role: 'Admin',
);

/// Ana is ready (everything checked); Ben is not (nothing checked).
AppState _state({String benName = 'Ben Cruz', String? benOffice}) {
  return AppState(firestoreService: FirestoreService())
    ..currentUser = _admin
    ..academicYear = '2026-2027'
    ..academicSemester = '1st Semester'
    ..payrollRecordsLoaded = true
    ..users = [
      _admin,
      _assistant('sa1', 'Ana Reyes'),
      _assistant('sa2', benName),
    ]
    ..offices = [
      if (benOffice != null)
        Office(
          id: 'o1',
          name: benOffice,
          code: 'LONG',
          assistantIds: const ['sa2'],
          assistantNames: [benName],
        ),
    ]
    ..attendance = [
      for (final (i, id) in ['sa1', 'sa2'].indexed)
        AttendanceRecord(
          id: 'a$i',
          studentId: id,
          studentName: id,
          date: 'Sep 10, 2026',
          timeIn: '8:00 AM',
          timeOut: '12:00 PM',
          totalHours: 4,
        ),
    ]
    ..payrollChecks = [_allChecked('sa1')];
}

Future<void> _pump(
  WidgetTester tester,
  AppState state, {
  double width = 1400,
  double height = 2200,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: PayrollScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The status tab labelled [label]: an InkWell in the tabs' own horizontal
/// scroller (the cards' headers are InkWells too, and hold a status chip with
/// the same words).
Finder _tab(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  ),
  matching: find.widgetWithText(InkWell, label),
);

/// Opens every card on the page.
Future<void> _openAll(WidgetTester tester) async {
  final chevrons = find.byIcon(Icons.expand_more_rounded);
  for (var i = chevrons.evaluate().length - 1; i >= 0; i--) {
    await tester.ensureVisible(chevrons.at(i));
    await tester.tap(chevrons.at(i));
    await tester.pumpAndSettle();
  }
}

ElevatedButton _approve(WidgetTester tester) => tester.widget<ElevatedButton>(
  find.ancestor(
    of: find.text('Approve'),
    matching: find.byWidgetPredicate((w) => w is ElevatedButton),
  ),
);

void main() {
  group('layout', () {
    for (final width in [320.0, 390.0, 560.0, 700.0, 900.0, 1000.0, 1400.0]) {
      testWidgets('draws without overflow at ${width.toInt()} px', (
        tester,
      ) async {
        await _pump(tester, _state(), width: width);
        expect(tester.takeException(), isNull);
        expect(find.text('Progress'.toUpperCase()), findsOneWidget);
        expect(find.text('Ana Reyes'), findsOneWidget);
        // And with every card open.
        await _openAll(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Hours worked'), findsNWidgets(2));
      });
    }

    testWidgets('a long name and office fit a phone card', (tester) async {
      final state = _state(
        benName: 'Maria Guadalupe Hernandez-Villanueva de la Cruz Santos',
        benOffice:
            'Office of the University Registrar and Student Records Section',
      );
      await _pump(tester, state, width: 390);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the mobile filter panel opens without overflow', (
      tester,
    ) async {
      await _pump(tester, _state(), width: 360);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Campus'), findsWidgets);
    });
  });

  group('the cards', () {
    testWidgets('start closed: who, pay and standing, none of the detail', (
      tester,
    ) async {
      await _pump(tester, _state());
      // The initials avatar, name, office, status chip and the pay (₱100.00
      // is also the "To approve" amount, hence two).
      expect(find.text('AR'), findsWidgets);
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Unassigned office'), findsNWidgets(2));
      expect(find.text('₱100.00'), findsWidgets);
      // One chevron per card, plus one for Ben in the waiting card.
      expect(find.byIcon(Icons.expand_more_rounded), findsNWidgets(3));
      // A Not ready person says why, in one line.
      expect(find.text('4 requirements not checked'), findsOneWidget);
      // Nothing else yet.
      expect(find.text('Hours worked'), findsNothing);
      expect(find.text('Payable hours'), findsNothing);
      expect(find.text('Gross pay'), findsNothing);
      expect(find.text('DTR verified'), findsNothing);
      expect(find.text('Requirements checked'), findsNothing);
      expect(find.text('Sep'), findsNothing);
    });

    testWidgets('open on a tap to show everything about that person', (
      tester,
    ) async {
      await _pump(tester, _state());
      await tester.tap(find.text('Ana Reyes'));
      await tester.pumpAndSettle();
      expect(find.text('Hours worked'), findsOneWidget);
      expect(find.text('Payable hours'), findsOneWidget);
      expect(find.text('Gross pay'), findsOneWidget);
      expect(find.text('DTR verified'), findsOneWidget);
      expect(find.text('Requirements checked'), findsOneWidget);
      // Her month cells too (Sep has her hours).
      expect(find.text('Sep'), findsOneWidget);
      // The other card stays closed.
      expect(find.text('4 requirements not checked'), findsOneWidget);
      expect(find.text('Hours worked'), findsOneWidget);
    });

    testWidgets('close again on a second tap', (tester) async {
      await _pump(tester, _state());
      await tester.tap(find.text('Ana Reyes'));
      await tester.pumpAndSettle();
      expect(find.text('Hours worked'), findsOneWidget);
      await tester.tap(find.text('Ana Reyes'));
      await tester.pumpAndSettle();
      expect(find.text('Hours worked'), findsNothing);
    });

    testWidgets('a Not ready card opens to its missing requirements', (
      tester,
    ) async {
      await _pump(tester, _state());
      await tester.tap(find.text('Ben Cruz').last);
      await tester.pumpAndSettle();
      // The closed-card hint gives way to the full list.
      expect(find.text('Application requirements'), findsWidgets);
      expect(find.text('Endorsement Letter'), findsWidgets);
      expect(find.text('No DTR records'), findsNothing);
      expect(find.text('DTR verified'), findsOneWidget);
    });

    testWidgets('stay open while the tab or filter changes', (tester) async {
      await _pump(tester, _state());
      await tester.tap(find.text('Ana Reyes'));
      await tester.pumpAndSettle();
      expect(find.text('Hours worked'), findsOneWidget);
      // Away to another tab and back: still open.
      await tester.tap(_tab('Not ready'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Reyes'), findsNothing);
      await tester.tap(_tab('All'));
      await tester.pumpAndSettle();
      expect(find.text('Hours worked'), findsOneWidget);
    });

    testWidgets('can all be open at once without overflow', (tester) async {
      await _pump(tester, _state(), width: 390);
      await _openAll(tester);
      expect(find.text('Hours worked'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('are announced as buttons that can be expanded', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _state());
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Ana Reyes, .*Ready')),
      );
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isExpanded.name, 'isFalse');
      await tester.tap(find.text('Ana Reyes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('^Ana Reyes, .*Ready')))
            .flagsCollection
            .isExpanded
            .name,
        'isTrue',
      );
      handle.dispose();
    });

    testWidgets('Ready and Not ready read as different chips', (tester) async {
      await _pump(tester, _state());
      // One card's chip each, plus the tab and legend wording elsewhere.
      expect(find.text('Ready'), findsWidgets);
      expect(find.text('Not ready'), findsWidgets);
    });
  });

  group('status tabs', () {
    testWidgets('count what the list holds, and hide "No hours" when empty', (
      tester,
    ) async {
      await _pump(tester, _state());
      expect(
        find.descendant(of: _tab('All'), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tab('Ready'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tab('Not ready'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tab('Released'), matching: find.text('0')),
        findsOneWidget,
      );
      expect(_tab('No hours'), findsNothing);
    });

    testWidgets('a tab narrows the list, not what Approve works on', (
      tester,
    ) async {
      await _pump(tester, _state());
      expect(find.text('Ana Reyes'), findsOneWidget);
      // Ben is in the waiting card and in the list.
      expect(find.text('Ben Cruz'), findsNWidgets(2));

      await tester.tap(_tab('Ready'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Reyes'), findsOneWidget);
      // Only the waiting card names Ben now.
      expect(find.text('Ben Cruz'), findsOneWidget);
      // Approve still waits for Ben: the tab did not change that.
      expect(_approve(tester).onPressed, isNull);
      expect(find.text('Waiting on 1 not ready'), findsOneWidget);

      await tester.tap(_tab('Not ready'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Reyes'), findsNothing);
      expect(find.text('Ben Cruz'), findsNWidgets(2));
    });

    testWidgets('Approve covers the whole period even on an empty tab', (
      tester,
    ) async {
      final state = _state();
      await _pump(tester, state);
      await tester.tap(_tab('Not ready'));
      await tester.pumpAndSettle();
      state.payrollChecks = [_allChecked('sa1'), _allChecked('sa2')];
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state.notifyListeners();
      await tester.pumpAndSettle();
      // Nobody is "Not ready" now, yet both are ready to approve.
      expect(
        find.text('No Student Assistants with this status.'),
        findsOneWidget,
      );
      expect(_approve(tester).onPressed, isNotNull);
      expect(find.text('2 ready · whole period'), findsOneWidget);
    });

    testWidgets('the Ready tab holds only Ready, not Approved or Released', (
      tester,
    ) async {
      final state = _state()
        ..payrollChecks = [_allChecked('sa1'), _allChecked('sa2')];
      await _pump(tester, state);
      await tester.tap(_tab('Released'));
      await tester.pumpAndSettle();
      expect(
        find.text('No Student Assistants with this status.'),
        findsOneWidget,
      );
      await tester.tap(_tab('Ready'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsOneWidget);
    });

    testWidgets('are counted by the campus / department / office filters', (
      tester,
    ) async {
      final state = _state(benOffice: 'Library');
      await _pump(tester, state);
      await tester.tap(find.text('All offices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      // Only Ben is in the Library: one person in the view.
      expect(
        find.descendant(of: _tab('All'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tab('Ready'), matching: find.text('0')),
        findsOneWidget,
      );
      // Approve is still for everyone in the period.
      expect(find.text('Waiting on 1 not ready'), findsOneWidget);
    });
  });

  group('the overview', () {
    testWidgets('keeps the two steps, the progress bar and the sheet button', (
      tester,
    ) async {
      await _pump(tester, _state());
      expect(find.text('TO APPROVE'), findsOneWidget);
      expect(find.text('TO RELEASE'), findsOneWidget);
      expect(find.text('Release'), findsOneWidget);
      expect(find.text('0 of 2 approved or released'), findsOneWidget);
      expect(find.text('Ready 1'), findsOneWidget);
      expect(find.text('Not ready 1'), findsOneWidget);
      expect(find.text('Prepare Payroll Sheet'), findsOneWidget);
    });
  });

  group('cards with an SA ID and big text', () {
    /// Carla has an approved payroll for the term, with an SA ID and a long
    /// office name.
    AppState withSaId() {
      final state = _state();
      state.users = [...state.users, _assistant('sa3', 'Carla Santos')];
      state.payrollRecords = [
        PayrollRecord(
          id: PayrollRecord.idFor('sa3', '2026-08-01', '2026-12-31'),
          studentId: 'sa3',
          studentName: 'Carla Santos',
          saId: 'SA-007',
          office: 'Office of the University Registrar and Student Records',
          periodStart: '2026-08-01',
          periodEnd: '2026-12-31',
          periodLabel: _term,
          monthlyBreakdown: const [
            PayrollMonthBreakdown(
              month: 9,
              year: 2026,
              hoursWorked: 30,
              payableHours: 30,
            ),
          ],
          dtrVerified: true,
          reportVerified: true,
          status: 'Approved',
          approvedAt: 'Dec 20, 2026',
          approvedBy: 'Ada Admin',
        ),
      ];
      return state;
    }

    for (final (width, scale) in [(320.0, 1.0), (320.0, 1.3), (360.0, 1.5)]) {
      testWidgets('fit at $width px with text at ${scale}x', (tester) async {
        await _pump(tester, withSaId(), width: width, textScale: scale);
        expect(tester.takeException(), isNull);
        await _openAll(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('say the SA ID, office and standing to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, withSaId());
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Carla Santos, SA-007, Office of the University.*Approved'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Ben Cruz, Unassigned office, Not ready.*4 requirements'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an opened card belongs to its pay period', (tester) async {
      await _pump(tester, withSaId());
      await tester.tap(find.text('Ana Reyes'));
      await tester.pumpAndSettle();
      expect(find.text('Hours worked'), findsOneWidget);
      // Another semester is another period: everyone starts closed.
      await tester.tap(find.text('1st Semester'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2nd Semester').last);
      await tester.pumpAndSettle();
      expect(find.text('Hours worked'), findsNothing);
    });
  });

  group('the waiting card', () {
    /// Ana is ready; [count] people with hours and nothing checked.
    AppState manyHeld(int count, {bool returned = false}) {
      final state = _state();
      state.users = [
        for (final u in state.users)
          if (u.id != 'sa2') u,
        for (var i = 0; i < count; i++) _assistant('h$i', 'Held ${i + 1}'),
      ];
      state.attendance = [
        for (final u in state.users.where((u) => u.id.startsWith('h')))
          AttendanceRecord(
            id: 'att_${u.id}',
            studentId: u.id,
            studentName: u.id,
            date: 'Sep 10, 2026',
            timeIn: '8:00 AM',
            timeOut: '12:00 PM',
            totalHours: 4,
          ),
        ...state.attendance.where((a) => a.studentId == 'sa1'),
      ];
      if (returned) {
        state.payrollChecks = [
          ...state.payrollChecks,
          const PayrollCheck(
            studentId: 'h0',
            items: {
              PayrollRequirement.requirementsKey: PayrollCheckMark(
                status: PayrollCheckMark.returned,
                note: 'Wrong file',
                by: 'Hana Head',
                at: '2026-12-01T09:00:00.000',
              ),
            },
          ),
        ];
      }
      return state;
    }

    testWidgets('lists each person as one slim line, pills hidden', (
      tester,
    ) async {
      await _pump(tester, _state());
      expect(find.text('Waiting on 1 Student Assistant'), findsOneWidget);
      // Ben's line says how much is missing, once in the card.
      expect(find.text('4 to check'), findsOneWidget);
      // None of his pills, in the card or in his own (closed) card.
      expect(find.text('Application requirements'), findsNothing);
      expect(find.text('Endorsement Letter'), findsNothing);
    });

    testWidgets('open on a tap to show what the person is missing', (
      tester,
    ) async {
      await _pump(tester, _state());
      await tester.tap(find.text('Ben Cruz').first);
      await tester.pumpAndSettle();
      expect(find.text('Application requirements'), findsOneWidget);
      expect(find.text('Endorsement Letter'), findsOneWidget);
      expect(find.text('Contract of Appointment'), findsOneWidget);
      await tester.tap(find.text('Ben Cruz').first);
      await tester.pumpAndSettle();
      expect(find.text('Application requirements'), findsNothing);
    });

    testWidgets('say when something was returned', (tester) async {
      await _pump(tester, manyHeld(2, returned: true));
      expect(find.text('4 to check · 1 returned'), findsOneWidget);
      expect(find.text('4 to check'), findsOneWidget);
    });

    testWidgets('show six people, then all of them on request', (tester) async {
      await _pump(tester, manyHeld(8));
      expect(find.text('Waiting on 8 Student Assistants'), findsOneWidget);
      expect(find.text('4 to check'), findsNWidgets(6));
      expect(find.text('Show all 8'), findsOneWidget);
      await tester.ensureVisible(find.text('Show all 8'));
      await tester.tap(find.text('Show all 8'));
      await tester.pumpAndSettle();
      expect(find.text('4 to check'), findsNWidgets(8));
      expect(find.text('Show fewer'), findsOneWidget);
      await tester.tap(find.text('Show fewer'));
      await tester.pumpAndSettle();
      expect(find.text('4 to check'), findsNWidgets(6));
    });

    testWidgets('one open line leaves the others closed', (tester) async {
      await _pump(tester, manyHeld(3));
      await tester.tap(find.text('Held 1').first);
      await tester.pumpAndSettle();
      expect(find.text('Application requirements'), findsOneWidget);
    });

    for (final width in [320.0, 390.0, 900.0, 1400.0]) {
      testWidgets('fits ${width.toInt()} px, closed and open', (tester) async {
        await _pump(tester, manyHeld(8, returned: true), width: width);
        expect(tester.takeException(), isNull);
        await _openAll(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
