part of '../app_state.dart';

/// One requirement the Head checks before a Student Assistant's pay is
/// approved, as the Student Assistant sees it.
class MyPayItem {
  final String label;

  /// [PayrollCheckMark.checked], [PayrollCheckMark.returned], or null while
  /// the Head hasn't decided.
  final String? status;
  final String? note;

  const MyPayItem({required this.label, this.status, this.note});

  bool get isChecked => status == PayrollCheckMark.checked;
  bool get isReturned => status == PayrollCheckMark.returned;
}

/// What a Student Assistant can see of their own pay: this month's verified
/// hours against the monthly minimum, the Head's check of their
/// requirements, and their latest payout.
class MyPaySummary {
  final String monthLabel;
  final double hoursThisMonth;
  final List<MyPayItem> items;

  /// The newest pay that was released to them, if any.
  final PayrollRecord? lastReleased;

  /// Pay the Admin approved that isn't released yet.
  final PayrollRecord? approved;

  /// This month's hours as payroll counts them ([AttendanceRecord.countsTowardPay]):
  /// like [hoursThisMonth], plus records archived along with their year.
  final double payHoursThisMonth;

  /// The Head left them out of this term's payroll: nothing to estimate.
  final bool leftOut;

  /// Today falls in a pay period that is already approved or released, so
  /// its amount is shown instead of an estimate.
  final bool monthAlreadyInPayroll;

  const MyPaySummary({
    required this.monthLabel,
    required this.hoursThisMonth,
    required this.items,
    this.lastReleased,
    this.approved,
    double? payHoursThisMonth,
    this.leftOut = false,
    this.monthAlreadyInPayroll = false,
  }) : payHoursThisMonth = payHoursThisMonth ?? hoursThisMonth;

  double get minimumHours => PayrollRecord.minimumMonthlyHours;
  double get maximumHours => PayrollRecord.maximumMonthlyHours;
  bool get reachedMinimum => hoursThisMonth >= minimumHours;
  double get hoursToGo => reachedMinimum ? 0 : minimumHours - hoursThisMonth;

  /// This month's hours that would be paid: payroll caps each month at
  /// [maximumHours].
  double get payableHoursThisMonth =>
      payHoursThisMonth.clamp(0, maximumHours).toDouble();
  bool get overMaximum => payHoursThisMonth > maximumHours;

  /// What this month's verified hours come to at the payroll rate. Only an
  /// estimate: the amount is fixed when the Admin approves the payroll.
  double get estimatedPay => payableHoursThisMonth * PayrollRecord.ratePerHour;
  bool get showsEstimate => !leftOut && !monthAlreadyInPayroll;
  int get returnedCount => items.where((i) => i.isReturned).length;
  int get checkedCount => items.where((i) => i.isChecked).length;
}

extension AppStateMyPay on AppState {
  /// The pay card for the signed-in Student Assistant, from what the rules
  /// let them read: their own attendance, payroll records and payroll check.
  MyPaySummary? get myPay => _buildMyPay();

  MyPaySummary? _buildMyPay() {
    final user = currentUser;
    if (user == null || role != 'Student Assistant') return null;

    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final today = philippineClock();
    var hours = 0.0;
    var payHours = 0.0;
    for (final record in filteredAttendance) {
      if (!record.countsTowardPay) continue;
      final day = _parseFormattedDate(record.date);
      if (day == null || day.year != today.year || day.month != today.month) {
        continue;
      }
      // Payroll also pays records archived along with their academic year;
      // the hours line, like every other current total, leaves them out.
      payHours += record.totalHours ?? 0;
      if (record.countsTowardHours) hours += record.totalHours ?? 0;
    }

    final check = payrollChecks.cast<PayrollCheck?>().firstWhere(
      (c) => c?.studentId == user.id,
      orElse: () => null,
    );
    PayrollCheckMark? mark(String key) => check?.items[key];

    MyPayItem item(String label, PayrollCheckMark? m) =>
        MyPayItem(label: label, status: m?.status, note: m?.note);

    final items = [
      item(
        'Application requirements',
        mark(PayrollRequirement.requirementsKey),
      ),
      item('Endorsement Letter', mark(PayrollRequirement.endorsementKey)),
      item(
        'Contract of Appointment',
        mark(
          PayrollRequirement.contractKey(
            RehireRecord.termLabelFor(academicYear, academicSemester),
          ),
        ),
      ),
      item(
        'DTR/Accomplishment Report for ${monthNames[today.month - 1]}',
        mark(PayrollRequirement.dtrKey(today.year, today.month)),
      ),
    ];

    final mine = payrollRecords.where((p) => p.studentId == user.id).toList();
    final released = mine.where((p) => p.status == 'Released').toList();
    PayrollRecord? newestRelease;
    for (final p in released) {
      if (newestRelease == null ||
          (_parsePayrollDate(p.releasedAt) ?? DateTime(2000)).isAfter(
            _parsePayrollDate(newestRelease.releasedAt) ?? DateTime(2000),
          )) {
        newestRelease = p;
      }
    }
    final approved = mine.where((p) => p.status == 'Approved').toList();

    final day = DateTime(today.year, today.month, today.day);
    bool covers(PayrollRecord p) {
      final start = DateTime.tryParse(p.periodStart);
      final end = DateTime.tryParse(p.periodEnd);
      return start != null &&
          end != null &&
          !day.isBefore(start) &&
          !day.isAfter(end);
    }

    return MyPaySummary(
      monthLabel: '${monthNames[today.month - 1]} ${today.year}',
      hoursThisMonth: hours,
      payHoursThisMonth: payHours,
      items: items,
      lastReleased: newestRelease,
      approved: approved.isEmpty ? null : approved.last,
      leftOut:
          check?.exclusions[RehireRecord.termLabelFor(
            academicYear,
            academicSemester,
          )] !=
          null,
      monthAlreadyInPayroll: mine.any(
        (p) => (p.status == 'Approved' || p.status == 'Released') && covers(p),
      ),
    );
  }
}
