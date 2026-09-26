import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/programs_screen.dart';
import 'package:projectsais/screens/auth/register_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

const _cics = 'College of Information and Computing Sciences';
const _engineering = 'College of Engineering';
const _education = 'College of Education';

const _bsit = Program(
  id: 'p1',
  code: 'BSIT',
  name: 'Bachelor of Science in Information Technology',
  department: _cics,
);
const _bscs = Program(
  id: 'p2',
  code: 'BSCS',
  name: 'Bachelor of Science in Computer Science',
  department: _cics,
);
const _bsce = Program(
  id: 'p3',
  code: 'BSCE',
  name: 'Bachelor of Science in Civil Engineering',
  department: _engineering,
);

User _student(String id, String? program) => User(
  id: id,
  name: 'Student $id',
  email: '$id@marsu.edu.ph',
  role: 'Student Assistant',
  department: _cics,
  courseProgram: program,
);

// A bare AppState with the lists filled in; init() would need Firebase.
AppState _state() => AppState()
  ..currentUser = User(
    id: 'admin',
    name: 'Admin',
    email: 'admin@marsu.edu.ph',
    role: 'Admin',
  )
  ..departments = [_cics, _engineering, _education]
  ..departmentCodes = {_cics: 'CICS', _engineering: 'COE'}
  ..programs = [_bscs, _bsce, _bsit]
  ..users = [
    _student('a', 'BSIT'),
    _student('b', 'bsit'),
    _student('c', 'BSCS'),
  ];

Future<AppState> _pump(WidgetTester tester, Widget screen, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final state = _state();
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
  return state;
}

void main() {
  group('AppState programs', () {
    test('lists a department\'s programs and finds one by code', () {
      final state = _state();
      expect(
        state.programsForDepartment(_cics).map((p) => p.code),
        unorderedEquals(['BSIT', 'BSCS']),
      );
      expect(state.programsForDepartment(_education), isEmpty);
      expect(state.programByCode(' bsit ')?.id, 'p1');
      expect(state.programByCode(''), isNull);
    });

    test('refuses a blank field or a code already in use', () async {
      final state = _state();
      expect(await state.saveProgram(_bsit.copyWith(name: '  ')), isFalse);
      // Another program's code, in any case, is taken.
      expect(
        await state.saveProgram(
          const Program(id: '', code: 'bsit', name: 'Other', department: _cics),
        ),
        isFalse,
      );
      expect(state.programs, hasLength(3));
    });
  });

  group('ProgramsScreen', () {
    for (final width in [390.0, 800.0, 1440.0]) {
      testWidgets('lays out without overflow at ${width.toInt()}px', (
        tester,
      ) async {
        await _pump(tester, const ProgramsScreen(), Size(width, 1400));
        expect(tester.takeException(), isNull);
        expect(find.text('Programs'), findsWidgets);
      });
    }

    testWidgets('groups programs under their department', (tester) async {
      await _pump(tester, const ProgramsScreen(), const Size(1440, 1400));
      expect(find.text(_cics), findsOneWidget);
      expect(find.text('CICS'), findsOneWidget);
      expect(find.text('2 programs'), findsOneWidget);
      expect(find.text(_engineering), findsOneWidget);
      expect(find.text('1 program'), findsOneWidget);
      for (final code in ['BSIT', 'BSCS', 'BSCE']) {
        expect(find.text(code), findsOneWidget, reason: 'missing $code');
      }
      // Counted by code, ignoring case: "BSIT" and "bsit".
      expect(find.text('2 students'), findsOneWidget);
      expect(find.text('1 student'), findsOneWidget);
      expect(find.text('No students yet'), findsOneWidget);
      // A department without programs prompts for its first.
      expect(find.text(_education), findsOneWidget);
      expect(
        find.text('No programs yet. Add the first one for this department.'),
        findsOneWidget,
      );
    });

    testWidgets('search narrows to matching programs', (tester) async {
      await _pump(tester, const ProgramsScreen(), const Size(1440, 1400));
      await tester.enterText(find.byType(TextField).first, 'civil');
      await tester.pumpAndSettle();
      expect(find.text('BSCE'), findsOneWidget);
      expect(find.text('BSIT'), findsNothing);
      // Empty departments drop out while searching.
      expect(find.text(_education), findsNothing);
    });

    testWidgets('won\'t add a code another program already uses', (
      tester,
    ) async {
      final state = await _pump(
        tester,
        const ProgramsScreen(),
        const Size(1440, 1400),
      );
      // The CICS group's Add opens the dialog with CICS chosen.
      await tester.tap(find.widgetWithText(TextButton, 'Add').first);
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)).at(0),
        'bsit',
      );
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)).at(1),
        'Duplicate',
      );
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(ElevatedButton, 'Add Program'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          '"BSIT" is already used by Bachelor of Science in Information '
          'Technology.',
        ),
        findsOneWidget,
      );
      expect(state.programs, hasLength(3));
    });
  });

  group('Registration Course/Program', () {
    Future<void> openProgramMenu(WidgetTester tester) async {
      await tester.tap(find.text('Choose your program'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers only the chosen department\'s programs', (
      tester,
    ) async {
      await _pump(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1200),
      );
      await openProgramMenu(tester);
      expect(find.text(_bsit.name), findsOneWidget);
      expect(find.text(_bscs.name), findsOneWidget);
      expect(find.text(_bsce.name), findsNothing);
      // Close the menu, switch department, and look again.
      await tester.tap(find.text(_bsit.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CICS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_engineering).last);
      await tester.pumpAndSettle();
      // The CICS choice was cleared with the department change.
      expect(find.text('BSIT'), findsNothing);
      await openProgramMenu(tester);
      expect(find.text(_bsce.name), findsOneWidget);
      expect(find.text(_bsit.name), findsNothing);
    });

    testWidgets('shows departments as code over name, like programs', (
      tester,
    ) async {
      await _pump(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1200),
      );
      // Closed, the field shows just the chosen department's code.
      expect(find.text('CICS'), findsOneWidget);
      expect(find.text(_cics), findsNothing);
      await tester.tap(find.text('CICS'));
      await tester.pumpAndSettle();
      // Open, each option has its code with the full name under it; one
      // without a code shows its name alone.
      expect(find.text('COE'), findsWidgets);
      expect(find.text(_engineering), findsOneWidget);
      expect(find.text(_cics), findsOneWidget);
      expect(find.text(_education), findsOneWidget);
    });

    testWidgets('says so when a department has no programs', (tester) async {
      await _pump(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1200),
      );
      await tester.tap(find.text('CICS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_education).last);
      await tester.pumpAndSettle();
      expect(
        find.text('No programs listed for this department'),
        findsOneWidget,
      );
    });

    testWidgets('asks for a program when the department has some', (
      tester,
    ) async {
      await _pump(
        tester,
        RegisterScreen(onBackToLogin: () {}),
        const Size(1440, 1200),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Juan dela Cruz');
      await tester.enterText(fields.at(1), 'juan@marsu.edu.ph');
      await tester.enterText(fields.at(2), 'Str0ng!Pass');
      await tester.enterText(fields.at(3), '09171234567');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your course/program.'), findsOneWidget);
    });
  });
}
