import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/payroll_requirements_screen.dart';
import 'package:projectsais/screens/accounts/payroll_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

class _FakeFirestore extends FirestoreService {
  final items = <String, PayrollCheckMark?>{};
  final notifications = <Map<String, dynamic>>[];

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);

  @override
  Future<void> setPayrollCheckItem({
    required String studentId,
    required String studentName,
    required String key,
    required PayrollCheckMark? mark,
  }) async => items['$studentId/$key'] = mark;
}

const _term = '1st Semester, AY 2026-2027';

User _assistant(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  role: 'Student Assistant',
);

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

AppState _state(_FakeFirestore fake, User viewer) =>
    AppState(firestoreService: fake)
      ..currentUser = viewer
      ..academicYear = '2026-2027'
      ..academicSemester = '1st Semester'
      ..users = [
        viewer,
        _assistant('sa1', 'Ana Reyes'),
        _assistant('sa2', 'Ben Cruz'),
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
      ..headForwards = [
        HeadForward(
          id: 'f1',
          type: 'dtr_report',
          studentId: 'sa2',
          studentName: 'Ben Cruz',
          title: 'DTR/Accomplishment Report (September 2026)',
          fileName: 'dtr-ben-september.docx',
          storagePath: 'reports/sv1/dtr-ben-september.docx',
          sentByName: 'Sam Supervisor',
          sentById: 'sv1',
          sentAt: 'Oct 2, 2026',
        ),
      ];

Future<void> _pump(WidgetTester tester, AppState state, Widget screen) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final head = User(
    id: 'head1',
    name: 'Hana Head',
    email: 'head@example.com',
    role: 'Head',
  );
  final admin = User(
    id: 'admin1',
    name: 'Ada Admin',
    email: 'admin@example.com',
    role: 'Admin',
  );

  group('Head', () {
    for (final width in [1300.0, 390.0]) {
      testWidgets('checks and returns requirements at ${width.toInt()} px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final fake = _FakeFirestore();
        final state = _state(fake, head)..payrollChecks = [_allChecked('sa1')];

        await _pump(tester, state, const PayrollRequirementsScreen());

        // Ana is ready; Ben holds up the payroll.
        expect(
          find.textContaining('of 2 ready', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Ben Cruz'), findsOneWidget);
        expect(find.text('Ana Reyes'), findsNothing);
        expect(
          find.textContaining('waiting on 1 Student Assistant'),
          findsOneWidget,
        );
        expect(find.text('Waiting for your check.'), findsOneWidget);

        // Return the DTR: a note is required.
        await tester.ensureVisible(find.text('Return').last);
        await tester.tap(find.text('Return').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Return'));
        await tester.pumpAndSettle();
        expect(find.text('Please write a short note.'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'No signature');
        await tester.tap(find.widgetWithText(FilledButton, 'Return'));
        await tester.pumpAndSettle();

        expect(fake.items['sa2/dtr|2026-09']?.note, 'No signature');
        expect(find.textContaining('"No signature"'), findsOneWidget);

        // Then check it once corrected.
        final check = find.text('Check').last;
        await tester.ensureVisible(check);
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(fake.items['sa2/dtr|2026-09']?.isChecked, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('checking with no copy in SAIS asks first', (tester) async {
      tester.view.physicalSize = const Size(1300, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeFirestore();
      final state = _state(fake, head)..payrollChecks = [_allChecked('sa1')];

      await _pump(tester, state, const PayrollRequirementsScreen());
      // The application requirements are the first line.
      await tester.tap(find.text('Check').first);
      await tester.pumpAndSettle();

      expect(find.text('No Copy in SAIS'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.items, isEmpty);
    });
  });

  group('Admin', () {
    testWidgets('Approve waits until everyone is checked', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = _state(_FakeFirestore(), admin)
        ..payrollRecordsLoaded = true
        ..payrollChecks = [_allChecked('sa1')];

      await _pump(tester, state, const PayrollScreen());

      ElevatedButton approve() => tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Approve'),
          matching: find.byWidgetPredicate((w) => w is ElevatedButton),
        ),
      );
      expect(approve().onPressed, isNull);
      expect(find.text('Waiting on 1 Student Assistant'), findsOneWidget);
      // In the waiting card and in the list.
      expect(find.text('Ben Cruz'), findsNWidgets(2));

      state.payrollChecks = [_allChecked('sa1'), _allChecked('sa2')];
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      state.notifyListeners();
      await tester.pumpAndSettle();

      expect(approve().onPressed, isNotNull);
      expect(find.text('Waiting on 1 Student Assistant'), findsNothing);
      expect(find.text('Ben Cruz'), findsOneWidget);
      expect(find.text('2 ready · whole period'), findsOneWidget);
    });
  });
}
