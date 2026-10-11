import 'models.dart';

/// One Student Assistant's attendance over a period, for the Head's
/// Attendance summary.
class AssistantAttendance {
  final User assistant;

  /// The offices they're placed in; empty when not placed yet.
  final List<Office> offices;

  /// Their records in the period, newest first. Archived ones are here only
  /// when asked for, and never count in the figures.
  final List<AttendanceRecord> records;

  /// Whether they're clocked in right now: an open record dated today.
  final bool clockedIn;

  /// Days with verified hours, each date once however it was written.
  final int verifiedDays;

  const AssistantAttendance({
    required this.assistant,
    required this.offices,
    required this.records,
    required this.clockedIn,
    required this.verifiedDays,
  });

  /// The records that count: not archived.
  Iterable<AttendanceRecord> get live => records.where((r) => !r.isArchived);

  /// Verified hours: records timed out properly.
  double get hours => records
      .where((r) => r.countsTowardHours)
      .fold<double>(0, (sum, r) => sum + (r.totalHours ?? 0));

  /// Sessions where they never timed out.
  int get missedTimeOuts => live.where((r) => r.isInvalid).length;

  /// Whether they have any attendance in the period.
  bool get hasAttendance => live.isNotEmpty;

  /// The date of their latest record in the period, as saved.
  String? get lastDate => live.isEmpty ? null : live.first.date;

  String get officeLabel => offices.isEmpty
      ? 'No office yet'
      : offices.map((office) => office.name).join(', ');
}
