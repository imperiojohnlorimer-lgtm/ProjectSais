/// A ready-made task the Head sets up under a category, so a Supervisor can
/// pick it when assigning a task instead of typing the same one out again.
/// Choosing one only fills the form in: the Supervisor can still change
/// anything before assigning, and a task made from it is independent of the
/// template afterwards.
class TaskTemplate {
  /// Longest a title, description, checklist step or checklist may be, so one
  /// template (they all live in a single Firestore document) stays small.
  static const maxTitle = 80;
  static const maxDescription = 500;
  static const maxChecklistItem = 80;
  static const maxChecklistItems = 12;

  final String id;
  final String category;
  final String title;
  final String description;
  final String priority; // 'High', 'Medium', 'Low'
  final List<String> checklist;

  /// Whether a task made from it is an ongoing duty (see [TaskDuty]).
  final bool ongoing;

  const TaskTemplate({
    required this.id,
    required this.category,
    required this.title,
    this.description = '',
    this.priority = 'Medium',
    this.checklist = const [],
    this.ongoing = false,
  });

  factory TaskTemplate.fromJson(Map<String, dynamic> json) => TaskTemplate(
    id: json['id']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    priority: const ['High', 'Medium', 'Low'].contains(json['priority'])
        ? json['priority'] as String
        : 'Medium',
    checklist: [
      for (final item in json['checklist'] as List<dynamic>? ?? const [])
        if (item.toString().trim().isNotEmpty) item.toString(),
    ],
    ongoing: json['ongoing'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'title': title,
    'description': description,
    'priority': priority,
    'checklist': checklist,
    'ongoing': ongoing,
  };

  TaskTemplate copyWith({
    String? category,
    String? title,
    String? description,
    String? priority,
    List<String>? checklist,
    bool? ongoing,
  }) => TaskTemplate(
    id: id,
    category: category ?? this.category,
    title: title ?? this.title,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    checklist: checklist ?? this.checklist,
    ongoing: ongoing ?? this.ongoing,
  );
}
