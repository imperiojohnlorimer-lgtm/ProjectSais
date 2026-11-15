import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/utils/csv.dart';
import 'package:projectsais/widgets/export_list_button.dart';

void main() {
  group('csvOf', () {
    test('starts with a byte-order mark and ends each row with CRLF', () {
      final text = csvOf([
        ['Name', 'Hours'],
        ['Juan', 12.5],
      ]);

      expect(text, '﻿Name,Hours\r\nJuan,12.5\r\n');
    });

    test('quotes commas, quotes and line breaks', () {
      final text = csvOf([
        ['Dela Cruz, Juan', 'He said "hi"', 'two\nlines'],
      ]);

      expect(text, '﻿"Dela Cruz, Juan","He said ""hi""","two\nlines"\r\n');
    });

    test('leaves blanks empty and keeps numbers as numbers', () {
      expect(
        csvOf([
          [null, '', 0, -3.5],
        ]),
        '﻿,,0,-3.5\r\n',
      );
    });

    test('keeps a typed cell from running as a spreadsheet formula', () {
      final text = csvOf([
        ['=HYPERLINK("http://x")', '+1', '-1', '@SUM(A1)', 'plain'],
      ]);

      expect(text, contains("\"'=HYPERLINK(\"\"http://x\"\")\""));
      expect(text, contains(",'+1,'-1,'@SUM(A1),plain"));
    });

    test('keeps accented names intact as UTF-8', () {
      final bytes = csvBytes([
        ['María Núñez'],
      ]);

      expect(utf8.decode(bytes), contains('María Núñez'));
      // EF BB BF: Excel reads the file as UTF-8 because of it.
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    });
  });

  test('csvFileSafe makes a name fit for a file', () {
    expect(
      csvFileSafe('1st Semester, AY 2026-2027'),
      '1st-Semester-AY-2026-2027',
    );
    expect(csvFileSafe('2026-10-01-to-'), '2026-10-01-to');
  });

  group('ExportListButton', () {
    Future<void> pump(
      WidgetTester tester, {
      VoidCallback? onSaveCsv,
      VoidCallback? onPrint,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportListButton(
            onSaveCsv: onSaveCsv,
            onPrint: onPrint,
            showPrint: true,
          ),
        ),
      ),
    );

    testWidgets('offers Print and the spreadsheet from one menu', (
      tester,
    ) async {
      var saved = 0;
      var printed = 0;
      await pump(tester, onSaveCsv: () => saved++, onPrint: () => printed++);

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text(ExportListButton.printLabel), findsOneWidget);
      expect(find.text(ExportListButton.csvLabel), findsOneWidget);

      await tester.tap(find.text(ExportListButton.csvLabel));
      await tester.pumpAndSettle();
      expect((saved, printed), (1, 0));

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ExportListButton.printLabel));
      await tester.pumpAndSettle();
      expect((saved, printed), (1, 1));
    });

    testWidgets('leaves Print out where printing is not available', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportListButton(
              onSaveCsv: () {},
              onPrint: () {},
              showPrint: false,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text(ExportListButton.printLabel), findsNothing);
      expect(find.text(ExportListButton.csvLabel), findsOneWidget);
    });

    testWidgets('does nothing while the list is empty', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(ExportListButton.csvLabel), findsNothing);
    });
  });
}
