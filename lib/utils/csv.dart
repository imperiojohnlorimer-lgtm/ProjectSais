import 'dart:convert';
import 'dart:typed_data';

/// Rows of cells as a CSV file that Excel and Google Sheets open correctly:
/// a byte-order mark so accented names survive, CRLF line ends, and quotes
/// around anything with a comma, quote or line break.
///
/// A text cell that starts with =, +, - or @ would be run as a formula by a
/// spreadsheet (a name or remark someone typed in could do that), so those
/// get a leading apostrophe. Numbers are written as they are.
String csvOf(List<List<Object?>> rows) {
  final out = StringBuffer('﻿');
  for (final row in rows) {
    out.write(row.map(_cell).join(','));
    out.write('\r\n');
  }
  return out.toString();
}

Uint8List csvBytes(List<List<Object?>> rows) =>
    Uint8List.fromList(utf8.encode(csvOf(rows)));

String _cell(Object? value) {
  if (value == null) return '';
  if (value is num) return value.toString();
  var text = value.toString();
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
  if (text.contains(RegExp(r'[",\r\n]'))) {
    text = '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// A file name part from free text: letters, digits, dots, dashes.
String csvFileSafe(String text) =>
    text.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-').replaceAll(
      RegExp(r'^-+|-+$'),
      '',
    );
