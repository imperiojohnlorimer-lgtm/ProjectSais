/// Formats a due date the way tasks store it everywhere else in the app
/// ("Mon D, YYYY", e.g. "Sep 19, 2026").
String formatDueDate(DateTime d) {
  const months = [
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
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Reads a due date back out of the "Mon D, YYYY" form tasks store it in.
/// Returns null for anything that does not parse, so callers can treat the
/// date as unknown rather than overdue.
DateTime? parseDueDate(String raw) {
  const months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  final parts = raw.replaceAll(',', '').trim().split(RegExp(r'\s+'));
  if (parts.length < 3) return null;
  final month = months.indexOf(parts[0].toLowerCase().substring(0, 3)) + 1;
  final day = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (month == 0 || day == null || year == null) return null;
  return DateTime(year, month, day);
}
