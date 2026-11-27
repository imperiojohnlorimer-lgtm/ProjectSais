import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';
import 'philippine_dates.dart';
import 'web_print_stub.dart'
    if (dart.library.html) 'web_print.dart'
    as web_print;

/// A list as it is printed: the page's [title], [details] lines under it
/// (period, filters in use), and [rows], the same rows its CSV export holds
/// (the first is the header), so the paper and the spreadsheet match.
class PrintableList {
  final String title;
  final List<String> details;
  final List<List<Object?>> rows;

  const PrintableList({
    required this.title,
    this.details = const [],
    required this.rows,
  });

  /// How many people or records are listed (the rows under the header).
  int get count => rows.isEmpty ? 0 : rows.length - 1;
}

/// Whether this build can print a list (the web app; not the Android app).
bool get canPrintLists => web_print.WebPrintUtils.isSupported;

/// One cell as printed: nothing for an empty value, two decimals for a
/// number with a fraction (hours, pay), a saved time ("2026-11-10T04:00…")
/// as its day in the Philippines, anything else as written.
String printCell(Object? value) => switch (value) {
  null => '',
  int v => '$v',
  double v => v.toStringAsFixed(2),
  String v when _savedTime.hasMatch(v) => philippineDayText(v) ?? v,
  _ => value.toString(),
};

final _savedTime = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

/// The filters a page has away from their defaults, as one line, e.g.
/// "Filters: Role: Student · Search: "dela"", or null when none are on.
/// [filters] maps each filter's name to its value; null or empty values
/// are left out.
String? filtersLine(Map<String, String?> filters) {
  final on = [
    for (final MapEntry(:key, :value) in filters.entries)
      if ((value ?? '').trim().isNotEmpty) '$key: ${value!.trim()}',
  ];
  return on.isEmpty ? null : 'Filters: ${on.join(' · ')}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A calendar day as printed: "Aug 1, 2026".
String printDay(DateTime day) =>
    '${_months[day.month - 1]} ${day.day}, ${day.year}';

/// "Printed Nov 16, 2026, 3:05 PM by Juan Dela Cruz" for a Philippine
/// [clock] time.
String printedLine(DateTime clock, String? by) {
  final hour = clock.hour % 12 == 0 ? 12 : clock.hour % 12;
  final minute = clock.minute.toString().padLeft(2, '0');
  final half = clock.hour < 12 ? 'AM' : 'PM';
  final who = (by ?? '').trim();
  return 'Printed ${_months[clock.month - 1]} ${clock.day}, ${clock.year}, '
      '$hour:$minute $half${who.isEmpty ? '' : ' by $who'}';
}

/// The lines printed under the title: the page's own [list.details], how
/// many are listed, and who printed it when.
@visibleForTesting
List<String> printDetails(PrintableList list, DateTime clock, String? by) => [
  ...list.details,
  '${list.count} listed',
  printedLine(clock, by),
];

Set<String> _saidValues(PrintableList list) {
  final values = <String>{};
  void add(String raw) {
    final v = raw.trim();
    if (v.isNotEmpty) values.add(v);
  }

  add(list.title);
  final titleComma = list.title.indexOf(', ');
  if (titleComma != -1) {
    add(list.title.substring(titleComma + 2));
  }
  for (final line in list.details) {
    add(line);
    if (line.startsWith('Filters: ')) {
      for (final entry in line.substring('Filters: '.length).split(' · ')) {
        final colon = entry.indexOf(': ');
        if (colon == -1) continue;
        final key = entry.substring(0, colon).trim();
        if (key == 'Search') continue;
        add(entry.substring(colon + 2));
      }
    } else {
      final colon = line.indexOf(': ');
      if (colon != -1) add(line.substring(colon + 2));
    }
  }
  return values;
}

/// [list]'s table as printed: every cell as text ([printCell]), and the
/// columns whose every value is a number, to align right. A column holding
/// one value on every row that the title or the details already say (the
/// payroll's period, the rehiring term) is left out: on paper it would only
/// repeat itself down the page. The first column (who each row is) always
/// stays.
@visibleForTesting
({List<List<String>> rows, Set<int> numeric}) printableTable(
  PrintableList list,
) {
  if (list.rows.isEmpty) return (rows: const [], numeric: const {});
  final header = list.rows.first;
  final body = list.rows.skip(1).toList();
  Object? at(List<Object?> row, int i) => i < row.length ? row[i] : null;
  final said = _saidValues(list);
  final keep = [
    for (var i = 0; i < header.length; i++)
      if (i == 0 ||
          !(body.isNotEmpty &&
              at(body.first, i) is String &&
              (at(body.first, i) as String).isNotEmpty &&
              said.contains((at(body.first, i) as String).trim()) &&
              body.every((row) => at(row, i) == at(body.first, i))))
        i,
  ];
  final numeric = <int>{
    for (final (k, i) in keep.indexed)
      if (body.isNotEmpty &&
          body.every((row) => at(row, i) is num || at(row, i) == null) &&
          body.any((row) => at(row, i) is num))
        k,
  };
  return (
    rows: [
      for (final row in list.rows)
        [for (final i in keep) printCell(at(row, i))],
    ],
    numeric: numeric,
  );
}

/// Opens the browser's print dialog for [list]. A refusal is shown, not
/// swallowed.
Future<void> printList(BuildContext context, PrintableList list) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final table = printableTable(list);
  try {
    await web_print.WebPrintUtils.printTable(
      title: list.title,
      details: printDetails(
        list,
        state.philippineClock(),
        state.currentUser?.name,
      ),
      rows: table.rows,
      numeric: table.numeric,
    );
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Could not print the list: $error'),
        backgroundColor: AppTheme.red500,
      ),
    );
  }
}
