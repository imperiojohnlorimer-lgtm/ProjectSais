import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';

import 'recurring_schedule.dart';

/// A student's class schedule: the subjects read from their schedule file
/// (each a [RecurringScheduleRule] with `isSubject`, one per weekday it
/// meets), plus the file itself.
///
/// It reaches the Calendar and the DTR/Accomplishment Report in three ways:
/// with the application (approved with it), as a change the Student
/// Assistant sends from the Calendar (approved by the Head), or typed in by
/// the Head. Each approved one is kept as a [ClassScheduleVersion].

/// One class meeting the reader found, before the student checks it.
class ScheduleMeeting {
  final String title;
  final String instructor;
  final String room;
  final String mode; // 'Face-to-Face' or 'Online'
  final int? weekday; // DateTime.monday .. DateTime.saturday
  final int? start; // minutes after midnight
  final int? end;

  /// The reader isn't sure of something here: the student should look.
  final bool check;

  const ScheduleMeeting({
    required this.title,
    this.instructor = '',
    this.room = '',
    this.mode = 'Face-to-Face',
    this.weekday,
    this.start,
    this.end,
    this.check = false,
  });

  factory ScheduleMeeting.fromJson(Map<String, dynamic> json) {
    int? whole(Object? v) => v is num ? v.round() : null;
    final weekday = whole(json['weekday']);
    return ScheduleMeeting(
      title: json['title']?.toString() ?? '',
      instructor: json['instructor']?.toString() ?? '',
      room: json['room']?.toString() ?? '',
      mode: json['mode']?.toString() == 'Online' ? 'Online' : 'Face-to-Face',
      weekday: weekday != null && weekday >= 1 && weekday <= 6 ? weekday : null,
      start: whole(json['start']),
      end: whole(json['end']),
      check: json['check'] == true,
    );
  }
}

/// What the reader made of a file.
class ScheduleReadResult {
  final bool ok;
  final List<ScheduleMeeting> meetings;
  final List<String> warnings;

  /// 'ocr' (a picture or scanned PDF) or 'text' (a PDF's own words).
  final String source;

  const ScheduleReadResult({
    required this.ok,
    required this.meetings,
    this.warnings = const [],
    this.source = 'ocr',
  });

  factory ScheduleReadResult.fromJson(Map<String, dynamic> json) =>
      ScheduleReadResult(
        ok: json['ok'] == true,
        meetings: [
          for (final m in (json['meetings'] as List? ?? const []))
            if (m is Map)
              ScheduleMeeting.fromJson(Map<String, dynamic>.from(m)),
        ],
        warnings: [
          for (final w in (json['warnings'] as List? ?? const [])) w.toString(),
        ],
        source: json['source']?.toString() ?? 'ocr',
      );
}

/// The colours subjects take on the calendar, in turn.
const classSubjectColors = <Color>[
  Color(0xFF7B1C2E), // maroon
  Color(0xFF2563EB), // blue
  Color(0xFF059669), // emerald
  Color(0xFFB45309), // amber
  Color(0xFF7C3AED), // violet
  Color(0xFF0E7490), // cyan
];

/// Subject rules from checked rows: one rule per meeting, the same colour
/// for every meeting of one subject.
List<RecurringScheduleRule> classSubjectRules({
  required List<ClassMeetingRow> rows,
  required String ownerName,
  required String? academicYear,
  required String idPrefix,
}) {
  final colours = <String, Color>{};
  final rules = <RecurringScheduleRule>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final key = row.title.trim().toLowerCase();
    final colour = colours.putIfAbsent(
      key,
      () => classSubjectColors[colours.length % classSubjectColors.length],
    );
    rules.add(
      RecurringScheduleRule(
        id: '${idPrefix}_$i',
        ownerName: ownerName,
        label: row.title.trim(),
        weekday: row.weekday!,
        startTime: row.start!,
        endTime: row.end!,
        color: colour,
        icon: Icons.school_outlined,
        academicYear: academicYear,
        mode: row.mode,
        units: row.units.trim(),
        isSubject: true,
        instructor: row.instructor.trim(),
        room: row.room.trim(),
      ),
    );
  }
  return rules;
}

/// One row of the class schedule editor.
class ClassMeetingRow {
  String title;
  String units;
  String instructor;
  String room;
  String mode;
  int? weekday;
  TimeOfDay? start;
  TimeOfDay? end;
  bool check;

  ClassMeetingRow({
    this.title = '',
    this.units = '',
    this.instructor = '',
    this.room = '',
    this.mode = 'Face-to-Face',
    this.weekday,
    this.start,
    this.end,
    this.check = false,
  });

  factory ClassMeetingRow.fromMeeting(ScheduleMeeting m) {
    TimeOfDay? time(int? minutes) =>
        minutes == null || minutes < 0 || minutes >= 24 * 60
            ? null
            : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return ClassMeetingRow(
      title: m.title,
      instructor: m.instructor,
      room: m.room,
      mode: m.mode,
      weekday: m.weekday,
      start: time(m.start),
      end: time(m.end),
      check: m.check,
    );
  }

  factory ClassMeetingRow.fromRule(RecurringScheduleRule r) => ClassMeetingRow(
    title: r.label,
    units: r.units,
    instructor: r.instructor,
    room: r.room,
    mode: r.mode,
    weekday: r.weekday,
    start: r.startTime,
    end: r.endTime,
  );

  int? get startMinutes =>
      start == null ? null : start!.hour * 60 + start!.minute;
  int? get endMinutes => end == null ? null : end!.hour * 60 + end!.minute;

  /// What's wrong with this row, or null when it can be saved.
  String? get problem {
    if (title.trim().isEmpty) return 'Type the subject.';
    if (weekday == null) return 'Pick the day.';
    if (start == null || end == null) return 'Pick the start and end times.';
    if (endMinutes! <= startMinutes!)
      return 'The class must end after it starts.';
    return null;
  }
}

/// Problems with the rows as a whole: no class at all, or two classes on
/// the same day at the same time. Empty when they can be saved.
List<String> classScheduleProblems(List<ClassMeetingRow> rows) {
  final problems = <String>[];
  if (rows.isEmpty) problems.add('Add at least one class.');
  for (var i = 0; i < rows.length; i++) {
    final problem = rows[i].problem;
    if (problem != null) problems.add('Row ${i + 1}: $problem');
  }
  if (problems.isNotEmpty) return problems;
  for (var i = 0; i < rows.length; i++) {
    for (var j = i + 1; j < rows.length; j++) {
      final a = rows[i];
      final b = rows[j];
      if (a.weekday != b.weekday) continue;
      if (a.startMinutes! < b.endMinutes! && b.startMinutes! < a.endMinutes!) {
        problems.add('Rows ${i + 1} and ${j + 1} overlap on the same day.');
      }
    }
  }
  return problems;
}

List<RecurringScheduleRule> _rulesFrom(Object? raw) => [
  for (final r in (raw as List? ?? const []))
    if (r is Map) RecurringScheduleRule.fromJson(Map<String, dynamic>.from(r)),
];

/// The schedule sent with an application.
class ClassScheduleSubmission {
  /// The name its file is listed under among the application's documents.
  static const requirementName = 'Class schedule';

  final String fileName;
  final String filePath;
  final List<RecurringScheduleRule> subjects;

  const ClassScheduleSubmission({
    required this.fileName,
    required this.filePath,
    required this.subjects,
  });

  factory ClassScheduleSubmission.fromJson(Map<String, dynamic> json) =>
      ClassScheduleSubmission(
        fileName: json['fileName']?.toString() ?? '',
        filePath: json['filePath']?.toString() ?? '',
        subjects: _rulesFrom(json['subjects']),
      );

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'filePath': filePath,
    'subjects': subjects.map((r) => r.toJson()).toList(),
  };
}

/// An approved class schedule, in effect from [effectiveFrom] (a day,
/// "yyyy-MM-dd") until the next one starts or its academic year ends.
class ClassScheduleVersion {
  final String id;
  final String? academicYear;
  final String effectiveFrom;
  final String fileName;
  final String filePath;
  final List<RecurringScheduleRule> subjects;
  final String approvedAt; // ISO, UTC
  final String approvedBy; // name
  final String source; // 'application' | 'request' | 'head'
  final String sourceId;

  const ClassScheduleVersion({
    required this.id,
    required this.academicYear,
    required this.effectiveFrom,
    required this.fileName,
    required this.filePath,
    required this.subjects,
    required this.approvedAt,
    required this.approvedBy,
    required this.source,
    this.sourceId = '',
  });

  factory ClassScheduleVersion.fromJson(Map<String, dynamic> json) =>
      ClassScheduleVersion(
        id: json['id']?.toString() ?? '',
        academicYear: json['academicYear']?.toString(),
        effectiveFrom: json['effectiveFrom']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? '',
        filePath: json['filePath']?.toString() ?? '',
        subjects: _rulesFrom(json['subjects']),
        approvedAt: json['approvedAt']?.toString() ?? '',
        approvedBy: json['approvedBy']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        sourceId: json['sourceId']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'academicYear': academicYear,
    'effectiveFrom': effectiveFrom,
    'fileName': fileName,
    'filePath': filePath,
    'subjects': subjects.map((r) => r.toJson()).toList(),
    'approvedAt': approvedAt,
    'approvedBy': approvedBy,
    'source': source,
    'sourceId': sourceId,
  };

  DateTime? get startDay => DateTime.tryParse(effectiveFrom);

  /// The distinct subjects, by name.
  int get subjectCount =>
      subjects.map((s) => s.label.trim().toLowerCase()).toSet().length;

  /// The version in effect on [day]: the newest one started by then, in
  /// [academicYear] when given (a version with no year counts for any).
  /// Of two starting the same day, the later approved one.
  static ClassScheduleVersion? inEffect(
    List<ClassScheduleVersion> versions,
    DateTime day, {
    String? academicYear,
  }) {
    final date = DateTime(day.year, day.month, day.day);
    ClassScheduleVersion? best;
    for (final v in versions) {
      final start = v.startDay;
      if (start == null || start.isAfter(date)) continue;
      if (academicYear != null &&
          v.academicYear != null &&
          v.academicYear != academicYear) {
        continue;
      }
      if (best == null || !start.isBefore(best.startDay!)) best = v;
    }
    return best;
  }

  /// "yyyy-MM-dd" for [day].
  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// One owner's `recurringSchedules` document: the weekly rules they or their
/// supervisor keep ("Add Schedule"), and the approved class schedules.
class OwnerSchedule {
  final List<RecurringScheduleRule> rules;
  final List<ClassScheduleVersion> versions;

  const OwnerSchedule({this.rules = const [], this.versions = const []});

  factory OwnerSchedule.fromJson(Map<String, dynamic>? data) => OwnerSchedule(
    rules: _rulesFrom(data?['rules']),
    versions: [
      for (final v in (data?['classSchedules'] as List? ?? const []))
        if (v is Map)
          ClassScheduleVersion.fromJson(Map<String, dynamic>.from(v)),
    ],
  );

  /// The rules the DTR and the calendar go by on [day]: the weekly ones,
  /// and the subjects of the class schedule in effect then. Once any class
  /// schedule was approved, subjects typed into the weekly rules (the old
  /// way, or a write that skipped the app) no longer count.
  List<RecurringScheduleRule> rulesOn(DateTime day, {String? academicYear}) =>
      mergedRules([this], day, academicYear: academicYear);

  /// [rulesOn] across several documents kept for one student (their account
  /// and older ones), each rule once.
  static List<RecurringScheduleRule> mergedRules(
    List<OwnerSchedule> schedules,
    DateTime day, {
    String? academicYear,
  }) {
    final anyApproved = schedules.any((s) => s.versions.isNotEmpty);
    final merged = <String, RecurringScheduleRule>{};
    for (final s in schedules) {
      for (final r in s.rules) {
        if (anyApproved && r.isSubject) continue;
        merged[r.id] = r;
      }
      final version = ClassScheduleVersion.inEffect(
        s.versions,
        day,
        academicYear: academicYear,
      );
      for (final r in version?.subjects ?? const <RecurringScheduleRule>[]) {
        merged[r.id] = r;
      }
    }
    return merged.values.toList();
  }
}

/// A Student Assistant's request to replace their class schedule, waiting
/// for the Head (`scheduleRequests/{id}`).
class ScheduleRequest {
  static const pending = 'Pending';
  static const approved = 'Approved';
  static const rejected = 'Rejected';
  static const cancelled = 'Cancelled';

  final String id;
  final String studentId;
  final String studentName;
  final String? academicYear;
  final String fileName;
  final String filePath;
  final List<RecurringScheduleRule> subjects;
  final String effectiveFrom;
  final String note;
  final String status;
  final String reviewNote;
  final String reviewedBy;
  final String reviewedAt;
  final DateTime? submittedAt;

  const ScheduleRequest({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.academicYear,
    required this.fileName,
    required this.filePath,
    required this.subjects,
    required this.effectiveFrom,
    this.note = '',
    this.status = pending,
    this.reviewNote = '',
    this.reviewedBy = '',
    this.reviewedAt = '',
    this.submittedAt,
  });

  bool get isPending => status == pending;

  factory ScheduleRequest.fromJson(Map<String, dynamic> json) {
    final at = json['submittedAt'];
    return ScheduleRequest(
      id: json['id']?.toString() ?? '',
      studentId: json['studentId']?.toString() ?? '',
      studentName: json['studentName']?.toString() ?? '',
      academicYear: json['academicYear']?.toString(),
      fileName: json['fileName']?.toString() ?? '',
      filePath: json['filePath']?.toString() ?? '',
      subjects: _rulesFrom(json['subjects']),
      effectiveFrom: json['effectiveFrom']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      status: json['status']?.toString() ?? pending,
      reviewNote: json['reviewNote']?.toString() ?? '',
      reviewedBy: json['reviewedBy']?.toString() ?? '',
      reviewedAt: json['reviewedAt']?.toString() ?? '',
      submittedAt: at is Timestamp
          ? at.toDate()
          : at is DateTime
          ? at
          : DateTime.tryParse(at?.toString() ?? ''),
    );
  }

  /// The fields a Student Assistant saves when sending it; `submittedAt` is
  /// added as the server's time.
  Map<String, dynamic> toNewJson() => {
    'id': id,
    'studentId': studentId,
    'studentName': studentName,
    'academicYear': academicYear,
    'fileName': fileName,
    'filePath': filePath,
    'subjects': subjects.map((r) => r.toJson()).toList(),
    'effectiveFrom': effectiveFrom,
    'note': note,
    'status': pending,
  };

  ScheduleRequest copyWith({
    String? status,
    String? reviewNote,
    String? reviewedBy,
    String? reviewedAt,
  }) => ScheduleRequest(
    id: id,
    studentId: studentId,
    studentName: studentName,
    academicYear: academicYear,
    fileName: fileName,
    filePath: filePath,
    subjects: subjects,
    effectiveFrom: effectiveFrom,
    note: note,
    status: status ?? this.status,
    reviewNote: reviewNote ?? this.reviewNote,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    submittedAt: submittedAt,
  );
}
