import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/utils/csv.dart';
import 'package:projectsais/widgets/export_csv_button.dart';

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

      expect(
        text,
        '﻿"Dela Cruz, Juan","He said ""hi""","two\nlines"\r\n',
      );
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

  group('ExportCsvButton', () {
    Future<void> pump(WidgetTester tester, VoidCallback? onPressed) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExportCsvButton(onPressed: onPressed)),
          ),
        );

    testWidgets('saves when there is something to save', (tester) async {
      var taps = 0;
      await pump(tester, () => taps++);

      await tester.tap(find.text('Export CSV'));
      expect(taps, 1);
    });

    testWidgets('does nothing while the list is empty', (tester) async {
      await pump(tester, null);

      await tester.tap(find.text('Export CSV'));
      expect(tester.takeException(), isNull);
    });
  });
}
