/// An ongoing duty: something a Student Assistant does on and off through
/// the term, like receiving documents, which has no due date and is never
/// "done". The supervisor sets it up once. On each day the student clocks
/// in they can log what they did, which makes that day's task (see
/// [Task.dutyId]) for the supervisor to approve; a day they don't clock in
/// makes nothing, and nothing is overdue.
class TaskDuty {
  /// Longest a title or the student's note about a day may be.
  static const maxTitle = 80;
  static const maxNote = 300;

  final String id;
  final String title;
  final String description;
  final String priority; // 'High', 'Medium', 'Low'
  final String category;

  /// The student's account id, name and the supervisor's account id.
  final String assignedTo;
  final String assignedToName;
  final String assignedBy;

  /// The academic year it was set up in. A duty only takes logs in that
  /// year, so one never carries over into the next by itself.
  final String academicYear;

  /// False once the supervisor stops it (or the student leaves).
  final bool active;

  const TaskDuty({
    required this.id,
    required this.title,
    this.description = '',
    this.priority = 'Medium',
    this.category = 'General',
    required this.assignedTo,
    required this.assignedToName,
    required this.assignedBy,
    required this.academicYear,
    this.active = true,
  });

  factory TaskDuty.fromJson(Map<String, dynamic> json) => TaskDuty(
    id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    priority: const ['High', 'Medium', 'Low'].contains(json['priority'])
        ? json['priority'] as String
        : 'Medium',
    category: json['category']?.toString() ?? 'General',
    assignedTo: json['assignedTo']?.toString() ?? '',
    assignedToName: json['assignedToName']?.toString() ?? '',
    assignedBy: json['assignedBy']?.toString() ?? '',
    academicYear: json['academicYear']?.toString() ?? '',
    active: json['active'] != false,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'priority': priority,
    'category': category,
    'assignedTo': assignedTo,
    'assignedToName': assignedToName,
    'assignedBy': assignedBy,
    'academicYear': academicYear,
    'active': active,
  };

  TaskDuty copyWith({String? category, bool? active}) => TaskDuty(
    id: id,
    title: title,
    description: description,
    priority: priority,
    category: category ?? this.category,
    assignedTo: assignedTo,
    assignedToName: assignedToName,
    assignedBy: assignedBy,
    academicYear: academicYear,
    active: active ?? this.active,
  );

  /// The id of the task that logs this duty for [day] (a Philippine
  /// calendar date). One per duty per day: a second log is the same
  /// document, so it can't be made twice.
  String logIdFor(DateTime day) =>
      'dutylog_${id}_${day.year}'
      '${day.month.toString().padLeft(2, '0')}'
      '${day.day.toString().padLeft(2, '0')}';
}
