import 'models.dart';

double _cents(double value) => (value * 100).roundToDouble() / 100;

double _toDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

int _toInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

/// A signatory box (A–D) at the foot of the Hourly Wage Payroll.
class PayrollSignatory {
  final String name;
  final String title;

  const PayrollSignatory({required this.name, required this.title});

  factory PayrollSignatory.fromJson(Map<String, dynamic> json) =>
      PayrollSignatory(name: json['name'] ?? '', title: json['title'] ?? '');

  Map<String, dynamic> toJson() => {'name': name, 'title': title};
}

/// One student row of the printed Hourly Wage Payroll. It starts out from the
/// system's computed [PayrollRecord], but the Admin can correct any column
/// before printing, so it stores what the sheet says rather than recomputing
/// it from attendance.
class PayrollSheetEntry {
  /// Empty for a row the Admin added by hand.
  final String studentId;
  final String campus;
  final String name;
  final String designation;
  final double hoursWorked;
  final double ratePerHour;
  final int undertimeHours;
  final int undertimeMinutes;
  final double taxesWithheld;
  final double sss;
  final String remarks;

  const PayrollSheetEntry({
    this.studentId = '',
    required this.campus,
    required this.name,
    this.designation = 'Student Assistant',
    this.hoursWorked = 0,
    this.ratePerHour = PayrollRecord.ratePerHour,
    this.undertimeHours = 0,
    this.undertimeMinutes = 0,
    this.taxesWithheld = 0,
    this.sss = 0,
    this.remarks = '',
  });

  /// Hours are the payable ones (capped at 40 a month), so hours × rate
  /// always matches the amount the system approved.
  factory PayrollSheetEntry.fromRecord(PayrollRecord record) =>
      PayrollSheetEntry(
        studentId: record.studentId,
        campus: (record.campus ?? '').trim(),
        name: record.studentName,
        hoursWorked: record.payableHours,
        remarks: monthsWorkedLabel(record.monthlyBreakdown),
      );

  // Each amount is rounded to the centavo as printed, so a column's total
  // always equals the sum of what's on the sheet.
  double get totalAmount => _cents(hoursWorked * ratePerHour);
  double get undertimeAmount =>
      _cents((undertimeHours + undertimeMinutes / 60) * ratePerHour);
  double get grossAmount => _cents(totalAmount - undertimeAmount);
  double get netPay => _cents(grossAmount - taxesWithheld - sss);

  static const _monthLabels = [
    'Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'June', //
    'July', 'Aug.', 'Sept.', 'Oct.', 'Nov.', 'Dec.',
  ];

  /// The months actually worked, written the way the university's sample
  /// payroll reads: "Oct. 2025", "Sept.-Nov. 2025", or "Dec. 2025-Jan. 2026".
  static String monthsWorkedLabel(List<PayrollMonthBreakdown> months) {
    final worked = months.where((m) => m.payableHours > 0).toList()
      ..sort(
        (a, b) => (a.year * 12 + a.month).compareTo(b.year * 12 + b.month),
      );
    if (worked.isEmpty) return '';
    final first = worked.first;
    final last = worked.last;
    final from = _monthLabels[first.month - 1];
    final to = _monthLabels[last.month - 1];
    if (first.year != last.year) return '$from ${first.year}-$to ${last.year}';
    if (first.month == last.month) return '$from ${first.year}';
    return '$from-$to ${last.year}';
  }

  factory PayrollSheetEntry.fromJson(Map<String, dynamic> json) =>
      PayrollSheetEntry(
        studentId: json['studentId'] ?? '',
        campus: json['campus'] ?? '',
        name: json['name'] ?? '',
        designation: json['designation'] ?? 'Student Assistant',
        hoursWorked: _toDouble(json['hoursWorked']),
        ratePerHour: json['ratePerHour'] == null
            ? PayrollRecord.ratePerHour
            : _toDouble(json['ratePerHour']),
        undertimeHours: _toInt(json['undertimeHours']),
        undertimeMinutes: _toInt(json['undertimeMinutes']),
        taxesWithheld: _toDouble(json['taxesWithheld']),
        sss: _toDouble(json['sss']),
        remarks: json['remarks'] ?? '',
      );

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'campus': campus,
    'name': name,
    'designation': designation,
    'hoursWorked': hoursWorked,
    'ratePerHour': ratePerHour,
    'undertimeHours': undertimeHours,
    'undertimeMinutes': undertimeMinutes,
    'taxesWithheld': taxesWithheld,
    'sss': sss,
    'remarks': remarks,
  };
}

/// The Admin's editable copy of the Hourly Wage Payroll for one pay period:
/// the header fields, every student row, and signatory boxes A–D. It's saved
/// so edits survive until the payroll is printed, and
/// [PayrollDocumentService] prints exactly what it holds.
class PayrollSheet {
  static const defaultEntityName = 'MARINDUQUE STATE UNIVERSITY';

  /// Boxes A–D as printed on the university's sample payroll.
  static const defaultSignatories = [
    PayrollSignatory(
      name: 'Atty. CRISPIN FRANCIS M. JANDUSAY',
      title: 'Vice-President for Administration & Finance',
    ),
    PayrollSignatory(name: 'MAE KRISTINE L. MONTARON', title: 'Accountant III'),
    PayrollSignatory(
      name: 'DIOSDADO P. ZULUETA, FFCP, DPA',
      title: 'SUC President III',
    ),
    PayrollSignatory(name: 'MARICEL P. GALANG', title: 'Disbursing Officer'),
  ];

  final String id;
  // ISO 8601 (yyyy-MM-dd), matching [PayrollRecord.periodStart]/periodEnd.
  final String periodStart;
  final String periodEnd;
  final String periodLabel;
  final String entityName;
  final String payrollNo;
  final String fundCluster;
  final List<PayrollSheetEntry> entries;

  /// Always four, in box order A, B, C, D.
  final List<PayrollSignatory> signatories;
  final String? updatedAt;
  final String? updatedBy;

  const PayrollSheet({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.periodLabel,
    this.entityName = defaultEntityName,
    this.payrollNo = '',
    this.fundCluster = '',
    this.entries = const [],
    this.signatories = defaultSignatories,
    this.updatedAt,
    this.updatedBy,
  });

  /// One saved sheet per pay period.
  static String idForPeriod(String periodStart, String periodEnd) =>
      'payroll-sheet-$periodStart-$periodEnd';

  /// A fresh sheet for a period from the system's payroll [records]. The
  /// entity name, fund cluster and signatories rarely change, so they carry
  /// over from [previous] (the last sheet the Admin saved) when there is one.
  /// The payroll number is unique to each payroll, so it always starts blank.
  factory PayrollSheet.fromRecords({
    required String periodStart,
    required String periodEnd,
    required String periodLabel,
    required List<PayrollRecord> records,
    PayrollSheet? previous,
  }) => PayrollSheet(
    id: idForPeriod(periodStart, periodEnd),
    periodStart: periodStart,
    periodEnd: periodEnd,
    periodLabel: periodLabel,
    entityName: previous?.entityName ?? defaultEntityName,
    fundCluster: previous?.fundCluster ?? '',
    entries: records.map(PayrollSheetEntry.fromRecord).toList()
      ..sort(
        (a, b) => a.campus != b.campus
            ? a.campus.compareTo(b.campus)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      ),
    signatories: previous?.signatories ?? defaultSignatories,
  );

  double get totalNetPay =>
      _cents(entries.fold<double>(0, (sum, e) => sum + e.netPay));

  PayrollSheet copyWith({
    String? periodLabel,
    String? entityName,
    String? payrollNo,
    String? fundCluster,
    List<PayrollSheetEntry>? entries,
    List<PayrollSignatory>? signatories,
    String? updatedAt,
    String? updatedBy,
  }) => PayrollSheet(
    id: id,
    periodStart: periodStart,
    periodEnd: periodEnd,
    periodLabel: periodLabel ?? this.periodLabel,
    entityName: entityName ?? this.entityName,
    payrollNo: payrollNo ?? this.payrollNo,
    fundCluster: fundCluster ?? this.fundCluster,
    entries: entries ?? this.entries,
    signatories: signatories ?? this.signatories,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  factory PayrollSheet.fromJson(Map<String, dynamic> json) {
    final storedSignatories = (json['signatories'] as List<dynamic>? ?? [])
        .map((s) => PayrollSignatory.fromJson(s as Map<String, dynamic>))
        .toList();
    return PayrollSheet(
      id: json['_id'] ?? json['id'] ?? '',
      periodStart: json['periodStart'] ?? '',
      periodEnd: json['periodEnd'] ?? '',
      periodLabel: json['periodLabel'] ?? '',
      entityName: json['entityName'] ?? defaultEntityName,
      payrollNo: json['payrollNo'] ?? '',
      fundCluster: json['fundCluster'] ?? '',
      entries: (json['entries'] as List<dynamic>? ?? [])
          .map((e) => PayrollSheetEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      // Pad with the defaults so there are always four boxes to print.
      signatories: [
        for (var i = 0; i < defaultSignatories.length; i++)
          i < storedSignatories.length
              ? storedSignatories[i]
              : defaultSignatories[i],
      ],
      updatedAt: json['updatedAt'],
      updatedBy: json['updatedBy'],
    );
  }

  Map<String, dynamic> toJson() => {
    'periodStart': periodStart,
    'periodEnd': periodEnd,
    'periodLabel': periodLabel,
    'entityName': entityName,
    'payrollNo': payrollNo,
    'fundCluster': fundCluster,
    'entries': entries.map((e) => e.toJson()).toList(),
    'signatories': signatories.map((s) => s.toJson()).toList(),
    'updatedAt': updatedAt,
    'updatedBy': updatedBy,
  }..removeWhere((_, v) => v == null);
}
