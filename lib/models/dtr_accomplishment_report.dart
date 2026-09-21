/// One row of the 31-day Daily Time Record table.
class DtrDayEntry {
  final int day;
  final String? amIn;
  final String? amOut;
  final String? pmIn;
  final String? pmOut;
  final double? totalHours;

  /// The "Accomplishment/s" cell — free text, or a status label such as
  /// "Class Schedule", "Saturday", "Sunday", "Midterm Examination", etc.
  final String? note;

  /// True when this entry was auto-filled from a task the student marked
  /// "Completed" on a day they weren't supposed to be working (a weekend
  /// with no matching schedule, or an official holiday). Flagged instead of
  /// silently crediting hours, so the supervisor can review/correct it.
  final bool isInvalid;

  /// True when this entry was auto-filled from a completed task on a valid
  /// working day, but no recurring schedule rule was found for that weekday
  /// to derive AM/PM in-out times from — hours need to be filled in by hand.
  final bool needsVerification;

  const DtrDayEntry({
    required this.day,
    this.amIn,
    this.amOut,
    this.pmIn,
    this.pmOut,
    this.totalHours,
    this.note,
    this.isInvalid = false,
    this.needsVerification = false,
  });

  DtrDayEntry copyWith({
    String? amIn,
    String? amOut,
    String? pmIn,
    String? pmOut,
    double? totalHours,
    String? note,
    bool? isInvalid,
    bool? needsVerification,
  }) => DtrDayEntry(
    day: day,
    amIn: amIn ?? this.amIn,
    amOut: amOut ?? this.amOut,
    pmIn: pmIn ?? this.pmIn,
    pmOut: pmOut ?? this.pmOut,
    totalHours: totalHours ?? this.totalHours,
    note: note ?? this.note,
    isInvalid: isInvalid ?? this.isInvalid,
    needsVerification: needsVerification ?? this.needsVerification,
  );
}

/// One row of the 8-row weekly Class Schedule grid.
class DtrClassScheduleEntry {
  final String course;
  final String units;
  final String monday;
  final String tuesday;
  final String wednesday;
  final String thursday;
  final String friday;
  final String saturday;

  /// When this row was filled in from a recurring "Add Schedule"/"Add
  /// Subject" rule (rather than typed in by hand), this holds that rule's
  /// label. Lets a later sync tell that a subject deleted from the
  /// student's calendar should have its row removed automatically,
  /// without touching rows the supervisor typed in by hand. Null for a
  /// manual row, or once the supervisor edits a synced row's name.
  final String? sourceRuleLabel;

  const DtrClassScheduleEntry({
    this.course = '',
    this.units = '',
    this.monday = '',
    this.tuesday = '',
    this.wednesday = '',
    this.thursday = '',
    this.friday = '',
    this.saturday = '',
    this.sourceRuleLabel,
  });

  DtrClassScheduleEntry copyWith({
    String? course,
    String? units,
    String? monday,
    String? tuesday,
    String? wednesday,
    String? thursday,
    String? friday,
    String? saturday,
    String? sourceRuleLabel,
    bool clearSourceRuleLabel = false,
  }) => DtrClassScheduleEntry(
    course: course ?? this.course,
    units: units ?? this.units,
    monday: monday ?? this.monday,
    tuesday: tuesday ?? this.tuesday,
    wednesday: wednesday ?? this.wednesday,
    thursday: thursday ?? this.thursday,
    friday: friday ?? this.friday,
    saturday: saturday ?? this.saturday,
    sourceRuleLabel: clearSourceRuleLabel
        ? null
        : (sourceRuleLabel ?? this.sourceRuleLabel),
  );
}

/// All the data needed to fill one DTR/Accomplishment Report document.
class DtrAccomplishmentReportData {
  final String studentId;
  final String studentName;
  final String department;

  /// Name printed above the "Signature Over Printed Name of Student
  /// Assistant" line. Defaults to [studentName] in the DTR screen, but
  /// kept as its own field in case a formal/legal name ever needs to
  /// differ from the display name used elsewhere.
  final String studentSignatureName;

  /// Name printed above "Signature Over Printed Name of Immediate
  /// Supervisor" — the student's office supervisor, who verifies and
  /// checks the report.
  final String supervisorName;

  /// Name printed above "Head, Student Assistantship" in the Approved
  /// section — the app's Head, who approves the report. (The template's
  /// token for it is still called {{ADMIN_SIG_NAME}}.)
  final String approverName;

  /// e.g. "February 01 – 28, 2026"
  final String monthYearLabel;
  final List<DtrDayEntry> days; // up to 31 entries, index 0 = day 1
  final List<DtrClassScheduleEntry> classSchedule; // up to 8 entries

  const DtrAccomplishmentReportData({
    required this.studentId,
    required this.studentName,
    required this.department,
    this.studentSignatureName = '',
    this.supervisorName = '',
    this.approverName = '',
    required this.monthYearLabel,
    required this.days,
    required this.classSchedule,
  });

  double get totalHours =>
      days.fold<double>(0, (sum, d) => sum + (d.totalHours ?? 0));

  String get totalUnits {
    final sum = classSchedule.fold<double>(0, (total, row) {
      final parsed = double.tryParse(row.units.trim());
      return total + (parsed ?? 0);
    });
    return sum == 0 ? '' : sum.toStringAsFixed(1);
  }
}
