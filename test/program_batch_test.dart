import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/program_batch.dart';
import 'package:projectsais/screens/accounts/programs_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

const _cics = 'College of Information and Computing Sciences';
const _engineering = 'College of Engineering';

const _bsit = Program(
  id: 'p1',
  code: 'BSIT',
  name: 'Bachelor of Science in Information Technology',
  department: _cics,
);
const _bsce = Program(
  id: 'p3',
  code: 'BSCE',
  name: 'Bachelor of Science in Civil Engineering',
  department: _engineering,
);

ProgramRow _row(String code, String name) => (code: code, name: name);

/// Keeps what the batch writes, so no Firestore is needed.
class _Store extends FirestoreService {
  final batches = <List<Program>>[];
  bool fail = false;
  int _next = 0;

  @override
  Future<List<Program>> saveProgramsBatch(List<Program> programs) async {
    if (fail) throw Exception('offline');
    batches.add(programs);
    return [
      for (final p in programs)
        Program(
          id: 'n${_next++}',
          code: p.code,
          name: p.name,
          department: p.department,
        ),
    ];
  }
}

AppState _state(_Store store) => AppState(firestoreService: store)
  ..currentUser = User(
    id: 'admin',
    name: 'Admin',
    email: 'admin@marsu.edu.ph',
    role: 'Admin',
  )
  ..departments = [_cics, _engineering]
  ..departmentCodes = {_cics: 'CICS', _engineering: 'COE'}
  ..programs = [_bsce, _bsit];

void main() {
  group('planProgramBatch', () {
    test('rows with nothing typed in are skipped', () {
      expect(planProgramBatch([_row('', ''), _row('  ', ' ')], [_bsit]), [
        null,
        null,
      ]);
    });

    test('a half-filled row says so', () {
      final errors = planProgramBatch(
        [
          _row('BSCS', ''),
          _row('', 'Some name'),
          _row('BSCX', 'Computer Science'),
        ],
        [_bsit],
      );
      expect(errors[0], 'Fill in both the code and the name.');
      expect(errors[1], 'Fill in both the code and the name.');
      expect(errors[2], isNull);
    });

    test(
      'a code another program uses is named like the one-at-a-time form did',
      () {
        final errors = planProgramBatch([_row(' bsit ', 'Duplicate')], [_bsit]);
        expect(
          errors.single,
          '"BSIT" is already used by Bachelor of Science in Information '
          'Technology.',
        );
      },
    );

    test(
      'a code used twice in the list flags every row that has it, ignoring case',
      () {
        final errors = planProgramBatch(
          [
            _row('BSCS', 'Computer Science'),
            _row('bscs', 'Computer Science again'),
            _row('BSEE', 'Electrical'),
          ],
          [_bsit],
        );
        expect(errors[0], '"BSCS" is listed more than once here.');
        expect(errors[1], '"bscs" is listed more than once here.');
        expect(errors[2], isNull);
      },
    );

    test('the same name under different codes is fine', () {
      final errors = planProgramBatch([
        _row('A', 'Same name'),
        _row('B', 'Same name'),
      ], const []);
      expect(errors, [null, null]);
    });

    test(
      'a program already on the list wins over a repeat inside the list',
      () {
        final errors = planProgramBatch(
          [_row('BSIT', 'x'), _row('BSIT', 'y')],
          [_bsit],
        );
        expect(errors.every((e) => e!.contains('is already used by')), isTrue);
      },
    );
  });

  group('parseProgramLines', () {
    test('reads a comma, a tab, " - " and an en dash', () {
      final parsed = parseProgramLines(
        'BSIT, Bachelor of Science in Information Technology\n'
        'BSCS\tBachelor of Science in Computer Science\n'
        'BSEE - Bachelor of Science in Electrical Engineering\n'
        'BSME – Bachelor of Science in Mechanical Engineering',
      );
      expect(parsed.unreadable, isEmpty);
      expect(parsed.rows.map((r) => r.code), ['BSIT', 'BSCS', 'BSEE', 'BSME']);
      expect(
        parsed.rows[2].name,
        'Bachelor of Science in Electrical Engineering',
      );
    });

    test(
      'the first separator splits, so a name may hold commas and a code a hyphen',
      () {
        final parsed = parseProgramLines(
          'BSHM, Bachelor of Science in Hospitality Management, Major in Cuisine\n'
          'BSIT-Drafting, Drafting Technology\n'
          'BSIT-Drafting - Drafting Technology',
        );
        expect(
          parsed.rows[0].name,
          'Bachelor of Science in Hospitality Management, Major in Cuisine',
        );
        expect(parsed.rows[1].code, 'BSIT-Drafting');
        expect(parsed.rows[2].code, 'BSIT-Drafting');
        expect(parsed.rows[2].name, 'Drafting Technology');
      },
    );

    test(
      'a copied table is read by its tabs: empty cells stay empty, commas stay in a cell',
      () {
        final parsed = parseProgramLines(
          '\tBachelor of Science, Major in Computing\n'
          'BSHM\tBachelor of Science in Hospitality Management, Cuisine\n'
          'BSCS, Alt\tComputer Science\n'
          'BSCE\tCivil Engineering\textra column\n'
          'BSEE\t\n',
        );
        expect(parsed.rows.map((r) => r.code), ['BSHM', 'BSCS, Alt']);
        expect(
          parsed.rows[0].name,
          'Bachelor of Science in Hospitality Management, Cuisine',
        );
        expect(parsed.rows[1].name, 'Computer Science');
        // No code, a third column and a missing name are handed back.
        expect(parsed.unreadable, hasLength(3));
        expect(
          parsed.unreadable.first,
          'Bachelor of Science, Major in Computing',
        );
      },
    );

    test(
      'blank lines are skipped, junk lines are handed back, Windows line ends work',
      () {
        final parsed = parseProgramLines(
          'BSIT, Information Technology\r\n\r\n   \r\njust words\r\nBSCS,\r\n, No code\r\nBSCE, Civil\r\n',
        );
        expect(parsed.rows.map((r) => r.code), ['BSIT', 'BSCE']);
        expect(parsed.unreadable, ['just words', 'BSCS,', ', No code']);
      },
    );
  });

  group('AppState.saveProgramsBatch', () {
    test(
      'saves every filled row in one batch and lists them by code',
      () async {
        final store = _Store();
        final state = _state(store);
        final result = await state.saveProgramsBatch(_cics, [
          _row(' BSCS ', ' Computer Science '),
          _row('', ''),
          _row('BSEE', 'Electrical'),
        ]);
        expect(result.ok, isTrue);
        expect(result.saved, 2);
        expect(store.batches, hasLength(1));
        expect(store.batches.single.map((p) => p.code), ['BSCS', 'BSEE']);
        expect(store.batches.single.first.name, 'Computer Science');
        expect(
          store.batches.single.every((p) => p.department == _cics),
          isTrue,
        );
        expect(state.programs.map((p) => p.code), [
          'BSCE',
          'BSCS',
          'BSEE',
          'BSIT',
        ]);
      },
    );

    test('one bad row saves nothing and is reported on its row', () async {
      final store = _Store();
      final state = _state(store);
      final result = await state.saveProgramsBatch(_cics, [
        _row('BSCS', 'Computer Science'),
        _row('bsit', 'Clash'),
      ]);
      expect(result.ok, isFalse);
      expect(result.rowErrors[0], isNull);
      expect(result.rowErrors[1], contains('is already used by'));
      expect(store.batches, isEmpty);
      expect(state.programs, hasLength(2));
    });

    test(
      'a department that is gone, no rows, or too many rows are refused',
      () async {
        final store = _Store();
        final state = _state(store);
        expect(
          (await state.saveProgramsBatch('College of Nowhere', [
            _row('A', 'a'),
          ])).message,
          isNotNull,
        );
        expect(
          (await state.saveProgramsBatch(_cics, [_row('', '')])).message,
          'Fill in at least one program.',
        );
        final many = [
          for (var i = 0; i <= maxProgramRows; i++) _row('C$i', 'Program $i'),
        ];
        expect(
          (await state.saveProgramsBatch(_cics, many)).message,
          contains('$maxProgramRows'),
        );
        expect(store.batches, isEmpty);
      },
    );

    test('a failed write adds nothing', () async {
      final store = _Store()..fail = true;
      final state = _state(store);
      final result = await state.saveProgramsBatch(_cics, [_row('BSCS', 'CS')]);
      expect(result.ok, isFalse);
      expect(result.message, contains('Nothing was added'));
      expect(state.programs, hasLength(2));
    });

    test(
      'a program the live listener already delivered is not listed twice',
      () async {
        final store = _Store();
        final state = _state(store);
        // The first id the fake store hands out is "n0".
        state.programs = [
          ...state.programs,
          const Program(id: 'n0', code: 'BSCS', name: 'CS', department: _cics),
        ];
        await state.saveProgramsBatch(_cics, [_row('BSEE', 'Electrical')]);
        expect(state.programs.where((p) => p.id == 'n0'), hasLength(1));
      },
    );
  });

  group('Add Program dialog', () {
    late _Store store;
    late AppState state;

    Future<void> openAdd(WidgetTester tester, {double width = 1440}) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      store = _Store();
      state = _state(store);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: ProgramsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The CICS group's Add opens it with CICS chosen.
      await tester.tap(find.widgetWithText(TextButton, 'Add').first);
      await tester.pumpAndSettle();
    }

    Finder dialogFields() => find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );

    Future<void> fillRow(
      WidgetTester tester,
      int row,
      String code,
      String name,
    ) async {
      await tester.enterText(dialogFields().at(row * 2), code);
      await tester.enterText(dialogFields().at(row * 2 + 1), name);
    }

    Finder addButton(String label) => find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(ElevatedButton, label),
    );

    testWidgets('starts with one row, as before', (tester) async {
      await openAdd(tester);
      expect(dialogFields(), findsNWidgets(2));
      expect(addButton('Add Program'), findsOneWidget);
      expect(find.text('Remove this row'), findsNothing);
      expect(find.text('Add another row'), findsOneWidget);
    });

    testWidgets('rows can be added and removed, and the button counts them', (
      tester,
    ) async {
      await openAdd(tester);
      await tester.tap(find.text('Add another row'));
      await tester.tap(find.text('Add another row'));
      await tester.pumpAndSettle();
      expect(dialogFields(), findsNWidgets(6));
      await fillRow(tester, 0, 'BSCS', 'Computer Science');
      await fillRow(tester, 1, 'BSEE', 'Electrical');
      await tester.pumpAndSettle();
      expect(addButton('Add 2 Programs'), findsOneWidget);

      // Removing the middle row keeps the others' text.
      await tester.tap(find.byTooltip('Remove this row').at(1));
      await tester.pumpAndSettle();
      expect(dialogFields(), findsNWidgets(4));
      expect(find.text('BSCS'), findsOneWidget);
      expect(find.text('BSEE'), findsNothing);
      expect(addButton('Add Program'), findsOneWidget);
    });

    testWidgets('saves several at once, closes, and says how many', (
      tester,
    ) async {
      await openAdd(tester);
      await tester.tap(find.text('Add another row'));
      await tester.tap(find.text('Add another row'));
      await tester.pumpAndSettle();
      await fillRow(tester, 0, 'BSCS', 'Computer Science');
      await fillRow(tester, 1, 'BSEE', 'Electrical Engineering');
      await fillRow(tester, 2, 'BSIS', 'Information Systems');
      await tester.pumpAndSettle();
      await tester.tap(addButton('Add 3 Programs'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(store.batches, hasLength(1));
      expect(store.batches.single, hasLength(3));
      expect(find.text('3 programs added to $_cics'), findsOneWidget);
      expect(
        state.programs.map((p) => p.code),
        containsAll(['BSCS', 'BSEE', 'BSIS']),
      );
    });

    testWidgets('one program still reads "Program "CODE" added!"', (
      tester,
    ) async {
      await openAdd(tester);
      await fillRow(tester, 0, 'BSCS', 'Computer Science');
      await tester.tap(addButton('Add Program'));
      await tester.pumpAndSettle();
      expect(find.text('Program "BSCS" added!'), findsOneWidget);
    });

    testWidgets('a pasted list fills the rows and keeps what it could not read', (
      tester,
    ) async {
      await openAdd(tester);
      await tester.tap(find.text('Paste a list'));
      await tester.pumpAndSettle();
      // The paste box is the last text field of the dialog.
      await tester.enterText(
        dialogFields().last,
        'BSCS, Computer Science\nBSEE - Electrical Engineering\nthis line is junk\n',
      );
      await tester.tap(find.text('Fill rows'));
      await tester.pumpAndSettle();
      // The empty first row is used, then one new row: 2 rows + the paste box.
      expect(dialogFields(), findsNWidgets(5));
      expect(find.text('BSCS'), findsOneWidget);
      expect(find.text('Electrical Engineering'), findsOneWidget);
      expect(find.textContaining('2 rows filled in.'), findsOneWidget);
      expect(find.textContaining('1 line could not be read'), findsOneWidget);
      // The junk line is still in the box.
      expect(find.text('this line is junk'), findsOneWidget);
      await tester.tap(addButton('Add 2 Programs'));
      await tester.pumpAndSettle();
      expect(store.batches.single.map((p) => p.code), ['BSCS', 'BSEE']);
    });

    testWidgets('paste beyond the limit is reported, not dropped', (
      tester,
    ) async {
      await openAdd(tester, width: 1440);
      await tester.tap(find.text('Paste a list'));
      await tester.pumpAndSettle();
      final lines = [
        for (var i = 0; i < maxProgramRows + 3; i++) 'C$i, Program $i',
      ].join('\n');
      await tester.enterText(dialogFields().last, lines);
      await tester.tap(find.text('Fill rows'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 not added'), findsOneWidget);
      // The add-row button is spent.
      final addRow = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Add another row'),
      );
      expect(addRow.onPressed, isNull);
    });

    testWidgets('a clashing code is shown on its row and nothing is saved', (
      tester,
    ) async {
      await openAdd(tester);
      await tester.tap(find.text('Add another row'));
      await tester.pumpAndSettle();
      await fillRow(tester, 0, 'BSCS', 'Computer Science');
      await fillRow(tester, 1, 'bsit', 'Duplicate');
      await tester.tap(addButton('Add 2 Programs'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '"BSIT" is already used by Bachelor of Science in Information '
          'Technology.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Fix the highlighted row, then try again.'),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(store.batches, isEmpty);
      // Typing again clears the complaint.
      await tester.enterText(dialogFields().at(2), 'BSXX');
      await tester.pumpAndSettle();
      expect(
        find.text('Fix the highlighted row, then try again.'),
        findsNothing,
      );
    });

    testWidgets('an empty form asks for at least one program', (tester) async {
      await openAdd(tester);
      await tester.tap(addButton('Add Program'));
      await tester.pumpAndSettle();
      expect(find.text('Fill in at least one program.'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('a failed save keeps the dialog and what was typed', (
      tester,
    ) async {
      await openAdd(tester);
      store.fail = true;
      await fillRow(tester, 0, 'BSCS', 'Computer Science');
      await tester.tap(addButton('Add Program'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing was added'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('BSCS'), findsOneWidget);
      expect(state.programs, hasLength(2));
    });

    testWidgets('Edit keeps the single pair, with no extra rows or paste', (
      tester,
    ) async {
      await openAdd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit program').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit Program'), findsOneWidget);
      expect(dialogFields(), findsNWidgets(2));
      expect(find.text('Add another row'), findsNothing);
      expect(find.text('Paste a list'), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('fits a phone with several rows and the paste box', (
      tester,
    ) async {
      await openAdd(tester, width: 390);
      await tester.tap(find.text('Add another row'));
      await tester.tap(find.text('Add another row'));
      await tester.tap(find.text('Paste a list'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Program 2'), findsOneWidget);
    });
  });
}
