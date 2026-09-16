import 'package:flutter/material.dart';

/// A student's recurring weekly schedule rule — e.g. "Class Schedule, every
/// Monday, 8:00 AM – 5:00 PM". This is the *template*; [ScheduleEvent]
/// occurrences on the calendar are generated from it (one per matching
/// weekday, skipping holidays) so each date can still be viewed/edited
/// individually while the rule itself stays the single source of truth.
class RecurringScheduleRule {
  final String id;
  final String ownerName;
  final String label; // e.g. "Class Schedule", "OJT Duty"
  final int weekday; // DateTime.monday .. DateTime.saturday (1-6)
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final Color color;
  final IconData icon;
  final String? academicYear;
  final String mode; // 'Face-to-Face' or 'Online'

  /// Unit count for this subject (e.g. "3"), set via "Add Subject". Empty
  /// for rules created via the plain "Add Schedule" flow. When several
  /// weekday rules share the same [label] (i.e. the same subject meeting
  /// on multiple days), they're expected to carry the same [units] value.
  final String units;

  /// True only for rules created via "Add Subject". The DTR/Accomplishment
  /// Report's "Class Schedule" table is specifically a *class* schedule —
  /// it should only ever be filled in from actual subjects, not from
  /// general "Add Schedule" entries (e.g. plain work-shift rules). This is
  /// tracked explicitly rather than inferred from `units.isNotEmpty`, so a
  /// subject whose units field is left blank doesn't quietly disappear
  /// from the table, and a plain schedule rule can't accidentally end up
  /// in it either.
  final bool isSubject;

  const RecurringScheduleRule({
    required this.id,
    required this.ownerName,
    required this.label,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.color,
    required this.icon,
    this.academicYear,
    this.mode = 'Face-to-Face',
    this.units = '',
    this.isSubject = false,
  });

  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String get weekdayName => _weekdayNames[weekday - 1];

  static String formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String get timeRange => '${formatTime(startTime)} - ${formatTime(endTime)}';

  RecurringScheduleRule copyWith({
    String? label,
    int? weekday,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    Color? color,
    IconData? icon,
    String? mode,
    String? units,
    bool? isSubject,
  }) => RecurringScheduleRule(
    id: id,
    ownerName: ownerName,
    label: label ?? this.label,
    weekday: weekday ?? this.weekday,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    academicYear: academicYear,
    mode: mode ?? this.mode,
    units: units ?? this.units,
    isSubject: isSubject ?? this.isSubject,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerName': ownerName,
    'label': label,
    'weekday': weekday,
    'startHour': startTime.hour,
    'startMinute': startTime.minute,
    'endHour': endTime.hour,
    'endMinute': endTime.minute,
    'colorValue': color.toARGB32(),
    'iconCodePoint': icon.codePoint,
    'academicYear': academicYear,
    'mode': mode,
    'units': units,
    'isSubject': isSubject,
  };

  factory RecurringScheduleRule.fromJson(Map<String, dynamic> json) =>
      RecurringScheduleRule(
        id: json['id'] as String,
        ownerName: json['ownerName'] as String,
        label: json['label'] as String,
        weekday: json['weekday'] as int,
        startTime: TimeOfDay(
          hour: json['startHour'] as int,
          minute: json['startMinute'] as int,
        ),
        endTime: TimeOfDay(
          hour: json['endHour'] as int,
          minute: json['endMinute'] as int,
        ),
        color: Color(json['colorValue'] as int),
        icon: _iconFromCodePoint(json['iconCodePoint'] as int),
        academicYear: json['academicYear'] as String?,
        // Older saved rules won't have these keys yet — defaults keep them
        // valid. `isSubject` falls back to "does it have units?" for rules
        // saved before this field existed, so pre-existing subjects don't
        // suddenly vanish from the Class Schedule table.
        mode: json['mode'] as String? ?? 'Face-to-Face',
        units: json['units'] as String? ?? '',
        isSubject:
            json['isSubject'] as bool? ?? ((json['units'] as String? ?? '').isNotEmpty),
      );

  static IconData _iconFromCodePoint(int codePoint) {
    switch (codePoint) {
      case 0xe80c: // school
        return Icons.school_outlined;
      case 0xe8f9: // work
        return Icons.work_outline;
      case 0xe1a3: // book
        return Icons.menu_book_outlined;
      case 0xea3d: // event
        return Icons.event_note_outlined;
      default:
        return Icons.event_note_outlined;
    }
  }
}