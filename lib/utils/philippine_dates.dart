/// Saved times shown as days in the Philippines, whatever time zone the
/// browser is in.
library;

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

/// The calendar day in the Philippines at the saved time [iso], or null
/// when [iso] is empty or can't be read.
DateTime? philippineDayOf(String? iso) {
  final at = DateTime.tryParse(iso?.trim() ?? '');
  if (at == null) return null;
  final clock = at.toUtc().add(const Duration(hours: 8));
  return DateTime(clock.year, clock.month, clock.day);
}

/// [iso] as a day in the Philippines, "Nov 11, 2026", or null when it is
/// empty or can't be read.
String? philippineDayText(String? iso) {
  final day = philippineDayOf(iso);
  if (day == null) return null;
  return '${_months[day.month - 1]} ${day.day}, ${day.year}';
}

/// Noon in the Philippines on the calendar [day], as the UTC time to save
/// for a date someone picked: read back, it is the same day.
String philippineNoonIso(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day, 4).toIso8601String();
