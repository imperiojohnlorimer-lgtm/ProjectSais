/// The Head's check of each Student Assistant's payroll requirements.
///
/// A semester's payroll can only be approved once the Head has checked every
/// requirement of every Student Assistant in it: their application
/// requirements, Endorsement Letter, the term's Contract of Appointment, and
/// a DTR/Accomplishment Report for each month they worked. A requirement
/// with a mistake goes back on its own, with a note, instead of the whole
/// bundle being returned.
library;

/// The Head's decision on one requirement: checked, or returned with a note.
class PayrollCheckMark {
  static const checked = 'Checked';
  static const returned = 'Returned';

  final String status;
  final String? note;
  final String by;
  final String? byId;

  /// ISO 8601, when the Head decided.
  final String at;

  /// The file the decision was about (a forwarded DTR's id, a document's
  /// id), so a copy sent after a return can be told apart from the
  /// returned one.
  final String? fileRef;

  const PayrollCheckMark({
    required this.status,
    this.note,
    required this.by,
    this.byId,
    required this.at,
    this.fileRef,
  });

  bool get isChecked => status == checked;
  bool get isReturned => status == returned;

  factory PayrollCheckMark.fromJson(Map<String, dynamic> json) =>
      PayrollCheckMark(
        status: json['status']?.toString() ?? checked,
        note: json['note']?.toString(),
        by: json['by']?.toString() ?? '',
        byId: json['byId']?.toString(),
        at: json['at']?.toString() ?? '',
        fileRef: json['fileRef']?.toString(),
      );

  Map<String, dynamic> toJson() => {
    'status': status,
    'note': note,
    'by': by,
    'byId': byId,
    'at': at,
    'fileRef': fileRef,
  }..removeWhere((_, value) => value == null);
}

/// The Head leaving a Student Assistant out of one term's payroll, with
/// the reason. They aren't paid in it, and it no longer waits for them.
class PayrollExclusion {
  final String reason;
  final String by;
  final String? byId;

  /// ISO 8601.
  final String at;

  const PayrollExclusion({
    required this.reason,
    required this.by,
    this.byId,
    required this.at,
  });

  factory PayrollExclusion.fromJson(Map<String, dynamic> json) =>
      PayrollExclusion(
        reason: json['reason']?.toString() ?? '',
        by: json['by']?.toString() ?? '',
        byId: json['byId']?.toString(),
        at: json['at']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'reason': reason, 'by': by, 'byId': byId, 'at': at}
        ..removeWhere((_, value) => value == null);
}

/// One Student Assistant's payroll checks, saved as
/// `payrollChecks/{account id}`. [items] is keyed by
/// [PayrollRequirement.key]; [exclusions] by term label ("1st Semester, AY
/// 2026-2027"). Checks of the application requirements and the Endorsement
/// Letter carry over from term to term; contracts and DTRs are per term and
/// per month.
class PayrollCheck {
  final String studentId;
  final String studentName;
  final Map<String, PayrollCheckMark> items;
  final Map<String, PayrollExclusion> exclusions;

  const PayrollCheck({
    required this.studentId,
    this.studentName = '',
    this.items = const {},
    this.exclusions = const {},
  });

  factory PayrollCheck.fromJson(Map<String, dynamic> json) => PayrollCheck(
    studentId: (json['studentId'] ?? json['id'] ?? '').toString(),
    studentName: json['studentName']?.toString() ?? '',
    items: {
      for (final entry
          in (json['items'] as Map<String, dynamic>? ?? const {}).entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: PayrollCheckMark.fromJson(
            entry.value as Map<String, dynamic>,
          ),
    },
    exclusions: {
      for (final entry
          in (json['exclusions'] as Map<String, dynamic>? ?? const {}).entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: PayrollExclusion.fromJson(
            entry.value as Map<String, dynamic>,
          ),
    },
  );
}

enum PayrollRequirementKind { requirements, endorsement, contract, dtr }

/// A file on record for a requirement, which the Head opens to check it.
class PayrollRequirementFile {
  final String ref;
  final String name;
  final String? detail;
  final String? storagePath;
  final String? downloadUrl;

  /// "Oct 5, 2026" — when a forwarded DTR was sent, or a document filed.
  final String? date;

  const PayrollRequirementFile({
    required this.ref,
    required this.name,
    this.detail,
    this.storagePath,
    this.downloadUrl,
    this.date,
  });

  bool get canOpen =>
      (storagePath ?? '').isNotEmpty || (downloadUrl ?? '').isNotEmpty;
}

/// One line of a Student Assistant's payroll checklist, worked out for a
/// pay period. [files] is filled only for the Head, who can read them; the
/// Admin sees whether each line is checked.
class PayrollRequirement {
  static const requirementsKey = 'requirements';
  static const endorsementKey = 'endorsement';

  final String key;
  final PayrollRequirementKind kind;
  final String label;
  final PayrollCheckMark? mark;

  /// Newest first.
  final List<PayrollRequirementFile> files;

  /// What a check or return is recorded against: the newest file, or for
  /// the application requirements the application itself.
  final String? ref;

  const PayrollRequirement({
    required this.key,
    required this.kind,
    required this.label,
    this.mark,
    this.files = const [],
    this.ref,
  });

  /// "contract|1st Semester, AY 2026-2027": one contract per term.
  static String contractKey(String termLabel) => 'contract|$termLabel';

  /// "dtr|2026-09": one DTR/Accomplishment Report per month worked.
  static String dtrKey(int year, int month) =>
      'dtr|$year-${month.toString().padLeft(2, '0')}';

  bool get isChecked => mark?.isChecked ?? false;
  bool get isReturned => mark?.isReturned ?? false;

  /// Returned, and a different copy has come in since: the Head should
  /// look again.
  bool get isResent => isReturned && ref != null && ref != mark!.fileRef;

  /// Waiting on the student or their supervisor rather than the Head:
  /// nothing on file yet, or returned and not sent again. Only meaningful
  /// in a Head's session, where [files] are known.
  bool get needsAction =>
      !isChecked && (isReturned ? !isResent : files.isEmpty);

  /// What's holding this line up, for the Admin's list.
  String get shortStatus {
    if (isChecked) return 'Checked';
    if (isResent) return 'New copy to check';
    if (isReturned) return 'Returned';
    return 'Not checked';
  }
}
