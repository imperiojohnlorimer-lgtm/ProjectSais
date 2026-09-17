import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
export 'dtr_accomplishment_report.dart';

String _formatNotificationDate(dynamic value) {
  DateTime? date;
  if (value is Timestamp) {
    date = value.toDate().toLocal();
  } else if (value is DateTime) {
    date = value.toLocal();
  } else if (value is String) {
    date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
  }
  if (date == null) return value?.toString() ?? '';

  const months = <String>[
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
  final hour = date.hour == 0
      ? 12
      : (date.hour > 12 ? date.hour - 12 : date.hour);
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${months[date.month - 1]} ${date.day}, ${date.year}, $hour:$minute $period';
}

class Office {
  final String id;
  final String name;
  final String code;
  final List<String> headIds;
  final List<String> headNames;
  final List<String> assistantIds;
  final List<String> assistantNames;
  final int capacity;
  final bool isActive;
  final List<String> requiredSkills;

  const Office({
    required this.id,
    required this.name,
    required this.code,
    this.headIds = const [],
    this.headNames = const [],
    this.assistantIds = const [],
    this.assistantNames = const [],
    this.capacity = 0,
    this.isActive = true,
    this.requiredSkills = const [],
  });

  Office copyWith({
    String? name,
    String? code,
    List<String>? headIds,
    List<String>? headNames,
    List<String>? assistantIds,
    List<String>? assistantNames,
    int? capacity,
    bool? isActive,
    List<String>? requiredSkills,
  }) => Office(
    id: id,
    name: name ?? this.name,
    code: code ?? this.code,
    headIds: headIds ?? this.headIds,
    headNames: headNames ?? this.headNames,
    assistantIds: assistantIds ?? this.assistantIds,
    assistantNames: assistantNames ?? this.assistantNames,
    capacity: capacity ?? this.capacity,
    isActive: isActive ?? this.isActive,
    requiredSkills: requiredSkills ?? this.requiredSkills,
  );

  factory Office.fromJson(Map<String, dynamic> json) => Office(
    id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    code: json['code']?.toString() ?? '',
    headIds:
        (json['headIds'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        (json['headId'] == null ? const [] : [json['headId'].toString()]),
    headNames:
        (json['headNames'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        (json['headName'] == null ? const [] : [json['headName'].toString()]),
    assistantIds:
        (json['assistantIds'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        (json['assistantId'] == null
            ? const []
            : [json['assistantId'].toString()]),
    assistantNames:
        (json['assistantNames'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        (json['assistantName'] == null
            ? const []
            : [json['assistantName'].toString()]),
    capacity: (json['capacity'] as num?)?.toInt() ?? 0,
    isActive: json['isActive'] != false,
    requiredSkills:
        (json['requiredSkills'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'code': code,
    'headIds': headIds,
    'headNames': headNames,
    'assistantIds': assistantIds,
    'assistantNames': assistantNames,
    'capacity': capacity,
    'isActive': isActive,
    'requiredSkills': requiredSkills,
  };
}

// models/user.dart
class User {
  final String id;
  final String name;
  final String email;
  final String
  role; // 'Admin', 'Head', 'Supervisor', 'Student Assistant', 'Student'
  final String? department;
  final String? campus;
  final String? phone;
  final String? address;
  final String? avatar;
  final List<String> skills;
  final String status; // 'Active' | 'Archived'
  final String? studentId;
  final String? courseProgram;
  final String? yearLevel;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.department,
    this.campus,
    this.phone,
    this.address,
    this.avatar,
    this.skills = const [],
    this.status = 'Active',
    this.studentId,
    this.courseProgram,
    this.yearLevel,
  });

  User copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    String? avatar,
    List<String>? skills,
    String? department,
    String? campus,
    String? role,
    String? status,
    String? studentId,
    String? courseProgram,
    String? yearLevel,
  }) => User(
    id: id ?? this.id,
    name: name ?? this.name,
    email: email,
    role: role ?? this.role,
    department: department ?? this.department,
    campus: campus ?? this.campus,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    avatar: avatar ?? this.avatar,
    skills: skills ?? this.skills,
    status: status ?? this.status,
    studentId: studentId ?? this.studentId,
    courseProgram: courseProgram ?? this.courseProgram,
    yearLevel: yearLevel ?? this.yearLevel,
  );

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['_id'] ?? json['id'] ?? '',
    name: json['name'] ?? '',
    email: json['email'] ?? '',
    role: json['role'] ?? 'Student',
    department: json['department'],
    campus: json['campus'],
    phone: json['phone'],
    address: json['address'],
    avatar: json['avatar'],
    skills:
        (json['skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        const [],
    status: json['status'] ?? 'Active',
    studentId: json['studentId'],
    courseProgram: json['courseProgram'],
    yearLevel: json['yearLevel'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'department': department,
    'campus': campus,
    'phone': phone,
    'address': address,
    'avatar': avatar,
    'skills': skills,
    'status': status,
    'studentId': studentId,
    'courseProgram': courseProgram,
    'yearLevel': yearLevel,
  };

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class Student {
  final String id;
  final String name;
  final String email;
  final String department;
  final String? campus;
  final String status;
  final double totalHours;
  final String? phone;
  final String? address;
  final String? avatar;
  final String? userId;

  Student({
    required this.id,
    required this.name,
    required this.email,
    required this.department,
    this.campus,
    this.status = 'Active',
    this.totalHours = 0,
    this.phone,
    this.address,
    this.avatar,
    this.userId,
  });

  factory Student.fromJson(Map<String, dynamic> json) => Student(
    id: json['_id'] ?? json['id'] ?? '',
    name: json['name'] ?? '',
    email: json['email'] ?? '',
    department: json['department'] ?? '',
    campus: json['campus'],
    status: json['status'] ?? 'Active',
    totalHours: (json['totalHours'] ?? 0).toDouble(),
    phone: json['phone'],
    address: json['address'],
    avatar: json['avatar'],
    userId: json['userId'] is Map ? json['userId']['_id'] : json['userId'],
  );

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Student copyWith({
    String? name,
    String? email,
    String? department,
    String? campus,
    String? status,
    double? totalHours,
    String? phone,
    String? address,
    String? avatar,
    String? userId,
  }) => Student(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    department: department ?? this.department,
    campus: campus ?? this.campus,
    status: status ?? this.status,
    totalHours: totalHours ?? this.totalHours,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    avatar: avatar ?? this.avatar,
    userId: userId ?? this.userId,
  );
}

class AttendanceRecord {
  final String id;
  final String studentName;
  final String? studentId;
  final String date;
  final String timeIn;
  final String? timeOut;
  final double? totalHours;
  final String? academicYear;
  final bool isArchived;
  // True once the student's session window (morning or afternoon) has
  // closed while they were still clocked in — they missed their time-out,
  // so the record no longer counts toward verified hours.
  final bool isInvalid;

  AttendanceRecord({
    required this.id,
    required this.studentName,
    this.studentId,
    required this.date,
    required this.timeIn,
    this.timeOut,
    this.totalHours,
    this.academicYear,
    this.isArchived = false,
    this.isInvalid = false,
  });

  bool get isActive => timeOut == null || timeOut!.isEmpty;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: json['_id'] ?? json['id'] ?? '',
        studentName: json['studentName'] ?? '',
        studentId: json['studentId'] is Map
            ? json['studentId']['_id']
            : json['studentId'],
        date: json['date'] ?? '',
        timeIn: json['timeIn'] ?? '',
        timeOut: json['timeOut'],
        totalHours: (json['totalHours'] ?? 0).toDouble(),
        academicYear: json['academicYear']?.toString(),
        isArchived: json['isArchived'] == true,
        isInvalid: json['isInvalid'] == true,
      );
}

/// One subject/row of a student assistant's weekly class schedule, used to
/// auto-fill the "Class Schedule" grid of the DTR/Accomplishment Report —
/// mirrors the official form's Course/Subject, Units, and per-weekday
/// time-slot columns.
class ClassScheduleEntry {
  final String id;
  final String studentId;
  final String studentName;
  final String course;
  final String units;
  final String monday;
  final String tuesday;
  final String wednesday;
  final String thursday;
  final String friday;
  final String saturday;
  final String? academicYear;

  /// When this row was filled in from a recurring "Add Schedule"/"Add
  /// Subject" rule (rather than typed in by hand), this holds that rule's
  /// label — e.g. "Math 101". Used purely to tell, on the next sync, that
  /// a subject the student has since deleted from their calendar should
  /// have its row removed automatically instead of lingering forever.
  /// Null for a row the supervisor typed in manually, or once they've
  /// edited a synced row's Course/Subject text themselves.
  final String? sourceRuleLabel;

  const ClassScheduleEntry({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.course,
    this.units = '',
    this.monday = '',
    this.tuesday = '',
    this.wednesday = '',
    this.thursday = '',
    this.friday = '',
    this.saturday = '',
    this.academicYear,
    this.sourceRuleLabel,
  });

  factory ClassScheduleEntry.fromJson(Map<String, dynamic> json) =>
      ClassScheduleEntry(
        id: json['_id'] ?? json['id'] ?? '',
        studentId: json['studentId'] is Map
            ? json['studentId']['_id']
            : (json['studentId'] ?? ''),
        studentName: json['studentName'] ?? '',
        course: json['course'] ?? '',
        units: json['units']?.toString() ?? '',
        monday: json['monday'] ?? '',
        tuesday: json['tuesday'] ?? '',
        wednesday: json['wednesday'] ?? '',
        thursday: json['thursday'] ?? '',
        friday: json['friday'] ?? '',
        saturday: json['saturday'] ?? '',
        academicYear: json['academicYear']?.toString(),
        sourceRuleLabel: json['sourceRuleLabel']?.toString(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'studentId': studentId,
    'studentName': studentName,
    'course': course,
    'units': units,
    'monday': monday,
    'tuesday': tuesday,
    'wednesday': wednesday,
    'thursday': thursday,
    'friday': friday,
    'saturday': saturday,
    'academicYear': academicYear,
    'sourceRuleLabel': sourceRuleLabel,
  }..removeWhere((_, value) => value == null);
}

class Task {
  final String id;
  final String title;
  final String description;
  final String status; // 'Not Started', 'In Progress', 'Completed'
  final String priority; // 'High', 'Medium', 'Low'
  final String dueDate;
  final String? assignedTo;
  final String? assignedToName;
  final String? assignedBy;
  final String? category;
  final List<String> checklistItems;
  final bool isArchived;
  final String? academicYear;

  /// The calendar date this task's status last became 'Completed', in the
  /// same "MMM d, yyyy" format as [AttendanceRecord.date] (e.g. "Sep 3,
  /// 2026") — set automatically by [AppState.updateTaskStatus]. Drives the
  /// DTR/Accomplishment Report's automatic "task completed → attendance"
  /// entry: a completed task becomes that day's accomplishment instead of
  /// requiring the supervisor to type it in manually.
  final String? completedAt;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.dueDate,
    this.assignedTo,
    this.assignedToName,
    this.assignedBy,
    this.category,
    this.checklistItems = const [],
    this.isArchived = false,
    this.academicYear,
    this.completedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['_id'] ?? json['id'] ?? '',
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    status: json['status'] ?? 'Not Started',
    priority: json['priority'] ?? 'Medium',
    dueDate: json['dueDate'] ?? '',
    assignedTo: json['assignedTo'] is Map
        ? json['assignedTo']['_id']
        : json['assignedTo'],
    assignedToName:
        json['assignedToName'] ??
        (json['assignedTo'] is Map ? json['assignedTo']['name'] : null),
    assignedBy: json['assignedBy'] is Map
        ? json['assignedBy']['_id']
        : json['assignedBy'],
    category: json['category'],
    checklistItems:
        (json['checklistItems'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    isArchived: json['isArchived'] == true,
    academicYear: json['academicYear']?.toString(),
    completedAt: json['completedAt']?.toString(),
  );

  Task copyWith({
    String? title,
    String? description,
    String? status,
    String? priority,
    String? dueDate,
    String? assignedTo,
    String? assignedToName,
    String? assignedBy,
    String? category,
    List<String>? checklistItems,
    bool? isArchived,
    String? academicYear,
    String? completedAt,
    bool clearCompletedAt = false,
  }) => Task(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    dueDate: dueDate ?? this.dueDate,
    assignedTo: assignedTo ?? this.assignedTo,
    assignedToName: assignedToName ?? this.assignedToName,
    assignedBy: assignedBy ?? this.assignedBy,
    category: category ?? this.category,
    checklistItems: checklistItems ?? this.checklistItems,
    isArchived: isArchived ?? this.isArchived,
    academicYear: academicYear ?? this.academicYear,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
  );

  String get displayStatus {
    switch (status) {
      case 'Not Started':
        return 'Pending';
      case 'In Progress':
        return 'In Progress';
      case 'Completed':
        return 'Completed';
      default:
        return status;
    }
  }
}

class ReportAttachment {
  final String id;
  final String fileName;
  final String storagePath;
  final String? downloadUrl;
  final int? fileSize;

  ReportAttachment({
    required this.id,
    required this.fileName,
    required this.storagePath,
    this.downloadUrl,
    this.fileSize,
  });

  factory ReportAttachment.fromJson(Map<String, dynamic> json) =>
      ReportAttachment(
        id: json['_id'] ?? json['id'] ?? '',
        fileName: json['fileName'] ?? 'document',
        storagePath: json['storagePath'] ?? '',
        downloadUrl: json['downloadUrl'],
        fileSize: json['fileSize'] is int ? json['fileSize'] as int : null,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'storagePath': storagePath,
    'downloadUrl': downloadUrl,
    'fileSize': fileSize,
  }..removeWhere((_, value) => value == null);
}

class Report {
  final String id;
  final String? applicantId;
  final String title;
  final String content;
  final String studentName;
  final String status; // 'Pending', 'Approved', 'Waitlisted', 'Rejected'
  final String? submittedAt;
  final String? feedback;
  final List<ReportAttachment> attachments;
  final String? academicYear;
  final bool sentToHead;
  final String? sentToHeadAt;
  final List<ReportAttachment> headAttachments;

  Report({
    required this.id,
    this.applicantId,
    required this.title,
    required this.content,
    required this.studentName,
    required this.status,
    this.submittedAt,
    this.feedback,
    this.attachments = const [],
    this.academicYear,
    this.sentToHead = false,
    this.sentToHeadAt,
    this.headAttachments = const [],
  });

  factory Report.fromJson(Map<String, dynamic> json) => Report(
    id: json['_id'] ?? json['id'] ?? '',
    applicantId: json['applicantId']?.toString(),
    title: json['title'] ?? '',
    content: json['content'] ?? '',
    studentName: json['studentName'] ?? '',
    status: json['status'] ?? 'Pending',
    submittedAt: json['submittedAt'],
    feedback: json['feedback'],
    academicYear: json['academicYear']?.toString(),
    sentToHead: json['sentToHead'] == true,
    sentToHeadAt: json['sentToHeadAt'],
    attachments:
        (json['attachments'] as List<dynamic>?)
            ?.map(
              (item) => ReportAttachment.fromJson(item as Map<String, dynamic>),
            )
            .toList() ??
        const [],
    headAttachments:
        (json['headAttachments'] as List<dynamic>?)
            ?.map(
              (item) => ReportAttachment.fromJson(item as Map<String, dynamic>),
            )
            .toList() ??
        const [],
  );
}

/// A requirement string can optionally restrict the file type a student is
/// allowed to upload for it, encoded as "<label>::<typeCode>" (e.g.
/// "Resume::word"). Older requirements with no "::" suffix accept any file
/// type, same as before this restriction existed.
class RequirementSpec {
  final String label;
  final String? fileType; // 'word' | 'pdf' | 'image' | null (any file)

  const RequirementSpec(this.label, this.fileType);

  static const Map<String, String> typeLabels = {
    'word': 'Word document',
    'pdf': 'PDF',
    'image': 'Image',
  };

  static const Map<String, List<String>> typeExtensions = {
    'word': ['doc', 'docx'],
    'pdf': ['pdf'],
    'image': ['jpg', 'jpeg', 'png'],
  };

  factory RequirementSpec.parse(String raw) {
    final sepIndex = raw.lastIndexOf('::');
    if (sepIndex != -1) {
      final type = raw.substring(sepIndex + 2);
      if (typeLabels.containsKey(type)) {
        return RequirementSpec(raw.substring(0, sepIndex), type);
      }
    }
    return RequirementSpec(raw, null);
  }

  String get encoded => fileType == null ? label : '$label::$fileType';

  String? get fileTypeLabel => fileType == null ? null : typeLabels[fileType];

  List<String> get allowedExtensions =>
      fileType == null ? const [] : (typeExtensions[fileType] ?? const []);
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final String postedBy; // name of whoever created it (admin or supervisor)
  final String postedByRole; // 'Admin' | 'Supervisor'
  final String postedAt;
  final String? deadline;
  final String? slots;
  final List<String> requirements;
  final bool isOpen; // true = accepting applications
  final bool acceptsApplications;
  final String? postedById;

  /// The office this request/announcement is for (set when a Supervisor
  /// requests a student assistant for one of their offices).
  final String? officeId;
  final String? officeName;

  /// Approval workflow:
  /// - Admin-created announcements are 'Approved' immediately.
  /// - Supervisor-created announcements start as 'Pending' and are only
  ///   visible to students once an Admin approves them.
  final String approvalStatus; // 'Pending' | 'Approved' | 'Rejected'
  final String? rejectionReason;
  final String? academicYear;

  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.postedBy,
    this.postedByRole = 'Admin',
    required this.postedAt,
    this.deadline,
    this.slots,
    this.requirements = const [],
    this.isOpen = true,
    this.acceptsApplications = true,
    this.postedById,
    this.officeId,
    this.officeName,
    this.approvalStatus = 'Approved',
    this.rejectionReason,
    this.academicYear,
  });

  bool get isPending => approvalStatus == 'Pending';
  bool get isApproved => approvalStatus == 'Approved';
  bool get isRejected => approvalStatus == 'Rejected';

  /// Whether students should be able to see/apply to this announcement.
  bool get isVisibleToStudents => isApproved && isOpen;

  Announcement copyWith({
    bool? isOpen,
    bool? acceptsApplications,
    String? approvalStatus,
    String? rejectionReason,
  }) => Announcement(
    id: id,
    title: title,
    body: body,
    postedBy: postedBy,
    postedByRole: postedByRole,
    postedAt: postedAt,
    deadline: deadline,
    slots: slots,
    requirements: requirements,
    isOpen: isOpen ?? this.isOpen,
    acceptsApplications: acceptsApplications ?? this.acceptsApplications,
    postedById: postedById,
    officeId: officeId,
    officeName: officeName,
    approvalStatus: approvalStatus ?? this.approvalStatus,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    academicYear: academicYear ?? this.academicYear,
  );
}

class Application {
  final String id;
  final String announcementId;
  final String announcementTitle;
  final String applicantId;
  final String applicantName;
  final String appliedAt;
  final String status; // 'Pending', 'Approved', 'Rejected'
  final String? remarks;
  final List<String> skills;
  final List<ApplicationDocument> submittedDocuments;
  final String? academicYear;

  Application({
    required this.id,
    required this.announcementId,
    required this.announcementTitle,
    required this.applicantId,
    required this.applicantName,
    required this.appliedAt,
    this.status = 'Pending',
    this.remarks,
    this.skills = const [],
    this.submittedDocuments = const [],
    this.academicYear,
  });

  factory Application.fromJson(Map<String, dynamic> json) => Application(
    id: json['_id'] ?? json['id'] ?? '',
    announcementId: json['announcementId'] ?? '',
    announcementTitle: json['announcementTitle'] ?? '',
    applicantId: json['applicantId'] ?? '',
    applicantName: json['applicantName'] ?? '',
    appliedAt: json['appliedAt'] ?? '',
    status: json['status'] ?? 'Pending',
    remarks: json['remarks'],
    skills:
        (json['skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        const [],
    submittedDocuments:
        (json['submittedDocuments'] as List<dynamic>?)
            ?.map(
              (d) => ApplicationDocument.fromJson(d as Map<String, dynamic>),
            )
            .toList() ??
        const [],
    academicYear: json['academicYear']?.toString(),
  );

  Application copyWith({
    String? status,
    String? remarks,
    String? academicYear,
    List<ApplicationDocument>? submittedDocuments,
  }) => Application(
    id: id,
    announcementId: announcementId,
    announcementTitle: announcementTitle,
    applicantId: applicantId,
    applicantName: applicantName,
    appliedAt: appliedAt,
    skills: skills,
    status: status ?? this.status,
    remarks: remarks ?? this.remarks,
    submittedDocuments: submittedDocuments ?? this.submittedDocuments,
    academicYear: academicYear ?? this.academicYear,
  );
}

class ScreeningRecord {
  final String id;
  final String applicationId;
  final String applicantId;
  final String fullName;
  final String studentNumber;
  final String academicProgram;
  final String yearLevel;
  final String permanentAddress;
  final String presentAddress;
  final String contactInformation;
  final String targetOfficeId;
  final String targetOfficeName;
  final Map<String, int> skills;
  final Map<String, String> skillNotes;
  final Map<String, int> overall;
  final Map<String, String> overallNotes;
  final String recommendation;
  final String interviewerName;
  final String interviewerDate;
  final String notedByName;
  final String notedByTitle;
  final String generalNotes;
  final String status;

  const ScreeningRecord({
    required this.id,
    required this.applicationId,
    required this.applicantId,
    required this.fullName,
    required this.studentNumber,
    required this.academicProgram,
    required this.yearLevel,
    required this.permanentAddress,
    required this.presentAddress,
    required this.contactInformation,
    required this.targetOfficeId,
    required this.targetOfficeName,
    required this.skills,
    required this.skillNotes,
    required this.overall,
    required this.overallNotes,
    required this.recommendation,
    required this.interviewerName,
    required this.interviewerDate,
    required this.notedByName,
    required this.notedByTitle,
    required this.generalNotes,
    this.status = 'Completed',
  });

  static String stableIdForApplicant({
    required String applicantId,
    String? applicationId,
    String? fallback,
  }) {
    final seed = applicantId.trim().isNotEmpty
        ? applicantId.trim()
        : (applicationId ?? fallback ?? DateTime.now().millisecondsSinceEpoch.toString());
    return 'screen-$seed';
  }

  ScreeningRecord withId(String newId) => ScreeningRecord(
    id: newId,
    applicationId: applicationId,
    applicantId: applicantId,
    fullName: fullName,
    studentNumber: studentNumber,
    academicProgram: academicProgram,
    yearLevel: yearLevel,
    permanentAddress: permanentAddress,
    presentAddress: presentAddress,
    contactInformation: contactInformation,
    targetOfficeId: targetOfficeId,
    targetOfficeName: targetOfficeName,
    skills: skills,
    skillNotes: skillNotes,
    overall: overall,
    overallNotes: overallNotes,
    recommendation: recommendation,
    interviewerName: interviewerName,
    interviewerDate: interviewerDate,
    notedByName: notedByName,
    notedByTitle: notedByTitle,
    generalNotes: generalNotes,
    status: status,
  );

  factory ScreeningRecord.fromJson(Map<String, dynamic> json) =>
      ScreeningRecord(
        id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
        applicationId: json['applicationId']?.toString() ?? '',
        applicantId: json['applicantId']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? '',
        studentNumber: json['studentNumber']?.toString() ?? '',
        academicProgram: json['academicProgram']?.toString() ?? '',
        yearLevel: json['yearLevel']?.toString() ?? '',
        permanentAddress: json['permanentAddress']?.toString() ?? '',
        presentAddress: json['presentAddress']?.toString() ?? '',
        contactInformation: json['contactInformation']?.toString() ?? '',
        targetOfficeId: json['targetOfficeId']?.toString() ?? '',
        targetOfficeName: json['targetOfficeName']?.toString() ?? '',
        skills: _intMap(json['skills']),
        skillNotes: _stringMap(json['skillNotes']),
        overall: _intMap(json['overall']),
        overallNotes: _stringMap(json['overallNotes']),
        recommendation: json['recommendation']?.toString() ?? 'Recommended',
        interviewerName: json['interviewerName']?.toString() ?? '',
        interviewerDate: json['interviewerDate']?.toString() ?? '',
        notedByName: json['notedByName']?.toString() ?? '',
        notedByTitle: json['notedByTitle']?.toString() ?? '',
        generalNotes: json['generalNotes']?.toString() ?? '',
        status: json['status']?.toString() ?? 'Completed',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'applicationId': applicationId,
    'applicantId': applicantId,
    'fullName': fullName,
    'studentNumber': studentNumber,
    'academicProgram': academicProgram,
    'yearLevel': yearLevel,
    'permanentAddress': permanentAddress,
    'presentAddress': presentAddress,
    'contactInformation': contactInformation,
    'targetOfficeId': targetOfficeId,
    'targetOfficeName': targetOfficeName,
    'skills': skills,
    'skillNotes': skillNotes,
    'overall': overall,
    'overallNotes': overallNotes,
    'recommendation': recommendation,
    'interviewerName': interviewerName,
    'interviewerDate': interviewerDate,
    'notedByName': notedByName,
    'notedByTitle': notedByTitle,
    'generalNotes': generalNotes,
    'status': status,
  };

  static Map<String, int> _intMap(dynamic value) => value is Map
      ? value.map(
          (key, item) => MapEntry(key.toString(), (item as num?)?.toInt() ?? 0),
        )
      : <String, int>{};

  static Map<String, String> _stringMap(dynamic value) => value is Map
      ? value.map(
          (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
        )
      : <String, String>{};
}

class ApplicationDocument {
  final String id;
  final String applicationId;
  final String requirementName;
  final String fileName;
  final String uploadedAt;
  final String? description;
  final double? fileSize;
  final Uint8List? bytes; // Store file bytes for download capability
  final String? storagePath;
  final String? downloadUrl;

  ApplicationDocument({
    required this.id,
    required this.applicationId,
    required this.requirementName,
    required this.fileName,
    required this.uploadedAt,
    this.description,
    this.fileSize,
    this.bytes,
    this.storagePath,
    this.downloadUrl,
  });

  factory ApplicationDocument.fromJson(Map<String, dynamic> json) =>
      ApplicationDocument(
        id: json['_id'] ?? json['id'] ?? '',
        applicationId: json['applicationId'] ?? '',
        requirementName: json['requirementName'] ?? '',
        fileName: json['fileName'] ?? '',
        uploadedAt: json['uploadedAt'] ?? '',
        description: json['description'],
        fileSize: json['fileSize'] is num
            ? (json['fileSize'] as num).toDouble()
            : null,
        bytes: json['bytes'] is List
            ? Uint8List.fromList(
                (json['bytes'] as List)
                    .map((value) => int.tryParse(value.toString()) ?? 0)
                    .toList(),
              )
            : null,
        storagePath: json['storagePath'],
        downloadUrl: json['downloadUrl'],
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'applicationId': applicationId,
    'requirementName': requirementName,
    'fileName': fileName,
    'uploadedAt': uploadedAt,
    'description': description,
    'fileSize': fileSize,
    // Firestore rejects raw Uint8List payloads for large uploaded docs.
    // Keep the metadata and storage URL so the document remains readable
    // without writing the full file bytes into the database.
    'storagePath': storagePath,
    'downloadUrl': downloadUrl,
  };
}

class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String message;
  final String type; // 'announcement', 'application', 'system'
  final String createdAt;
  final bool isRead;
  final String? attachmentName;
  final String? attachmentUrl;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.attachmentName,
    this.attachmentUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] ?? json['_id'] ?? '',
        userId: json['userId'] ?? '',
        title: json['title'] ?? '',
        message: json['message'] ?? '',
        type: json['type'] ?? 'system',
        createdAt: _formatNotificationDate(json['createdAt']),
        isRead: json['isRead'] == true,
        attachmentName: json['attachmentName'],
        attachmentUrl: json['attachmentUrl'],
      );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'title': title,
    'message': message,
    'type': type,
    'createdAt': createdAt,
    'isRead': isRead,
    'attachmentName': attachmentName,
    'attachmentUrl': attachmentUrl,
  }..removeWhere((_, v) => v == null);

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    userId: userId,
    title: title,
    message: message,
    type: type,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    attachmentName: attachmentName,
    attachmentUrl: attachmentUrl,
  );
}

/// A single item a Supervisor has forwarded up to the Head — an approved
/// report, a submitted performance evaluation, or a generated DTR/
/// Accomplishment report. Shown on the Head's dedicated "Sent to Head"
/// screen, grouped by student, instead of mixed into general notifications.
class HeadForward {
  final String id;
  final String type; // 'report' | 'evaluation' | 'dtr_report'
  final String studentId;
  final String studentName;
  final String title;
  final String fileName;
  final String? downloadUrl;
  final String sentByName;
  final String? sentById;
  final String sentAt;
  final bool reviewed;

  HeadForward({
    required this.id,
    required this.type,
    required this.studentId,
    required this.studentName,
    required this.title,
    required this.fileName,
    this.downloadUrl,
    required this.sentByName,
    this.sentById,
    required this.sentAt,
    this.reviewed = false,
  });

  factory HeadForward.fromJson(Map<String, dynamic> json) => HeadForward(
    id: json['_id'] ?? json['id'] ?? '',
    type: json['type'] ?? 'report',
    studentId: json['studentId'] ?? '',
    studentName: json['studentName'] ?? '',
    title: json['title'] ?? '',
    fileName: json['fileName'] ?? '',
    downloadUrl: json['downloadUrl'],
    sentByName: json['sentByName'] ?? '',
    sentById: json['sentById'],
    sentAt: json['sentAt'] ?? '',
    reviewed: json['reviewed'] == true,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'studentId': studentId,
    'studentName': studentName,
    'title': title,
    'fileName': fileName,
    'downloadUrl': downloadUrl,
    'sentByName': sentByName,
    'sentById': sentById,
    'sentAt': sentAt,
    'reviewed': reviewed,
  }..removeWhere((_, v) => v == null);

  HeadForward copyWith({bool? reviewed}) => HeadForward(
    id: id,
    type: type,
    studentId: studentId,
    studentName: studentName,
    title: title,
    fileName: fileName,
    downloadUrl: downloadUrl,
    sentByName: sentByName,
    sentById: sentById,
    sentAt: sentAt,
    reviewed: reviewed ?? this.reviewed,
  );
}

class Document {
  final String id;
  final String name;
  final String fileName;
  final String uploadedBy;
  final String uploadedAt;
  final String documentType; // 'Certificate', 'Report', 'Assignment', 'Other'
  final String? description;
  final String? filePath;
  final double? fileSize; // in MB

  Document({
    required this.id,
    required this.name,
    required this.fileName,
    required this.uploadedBy,
    required this.uploadedAt,
    required this.documentType,
    this.description,
    this.filePath,
    this.fileSize,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
    id: json['_id'] ?? json['id'] ?? '',
    name: json['name'] ?? '',
    fileName: json['fileName'] ?? '',
    uploadedBy: json['uploadedBy'] ?? '',
    uploadedAt: json['uploadedAt'] ?? '',
    documentType: json['documentType'] ?? 'Other',
    description: json['description'],
    filePath: json['filePath'],
    fileSize: json['fileSize'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'uploadedBy': uploadedBy,
    'uploadedAt': uploadedAt,
    'documentType': documentType,
    'description': description,
    'filePath': filePath,
    'fileSize': fileSize,
  };
}

/// The 7 rubric criteria used on the official
/// "Performance Evaluation for Student Assistants" form,
/// each rated 1-10 (10-9 Exceptional ... 2-1 Consistently Below Expectations).
class EvaluationCriteria {
  static const List<String> keys = [
    'schedule',
    'assignedWork',
    'initiative',
    'quality',
    'cooperation',
    'attitude',
    'workLifeBalance',
  ];

  static const Map<String, String> labels = {
    'schedule':
        'Schedule: punctuality, dependability, coverage as needed, accountability',
    'assignedWork':
        'Assigned work: willingness, dependability, completeness, sense of responsibility',
    'initiative': 'Initiative: seeking work, asking questions, big picture',
    'quality':
        'Quality: accuracy, neatness, order, consideration, alertness, attentiveness',
    'cooperation':
        'Cooperation & Respect: teamwork, relations with staff/peers, communication',
    'attitude':
        'Attitude: helpfulness, professionalism, relations with patrons, prioritizing service, approachability',
    'workLifeBalance':
        'Work/Life Balance: separation of personal interests from job, no '
        'inappropriate use of phone/texting/chatting, professionalism/ '
        'representative of the office',
  };

  /// Rating-band label, e.g. 9 -> "Exceptional".
  static String bandLabel(int score) {
    if (score >= 9) return 'Exceptional';
    if (score >= 7) return 'Exceeds Expectations';
    if (score >= 5) return 'Meets Expectations';
    if (score >= 3) return 'Improvement Needed';
    return 'Consistently Below Expectations';
  }
}

/// A supervisor's end-of-semester performance evaluation of a student
/// assistant, based on verified DTR (attendance) and an approved
/// accomplishment report, mirroring the official evaluation form.
class Evaluation {
  final String id;
  final String studentId;
  final String studentName;
  final String office; // Office/College/Department Assigned
  final String term; // 'First Semester' | 'Midyear Term' | 'Second Semester'
  final String periodCovered;
  final String dateOfRating;
  final bool eligibleForRehire;

  /// One score (1-10) per key in [EvaluationCriteria.keys].
  final Map<String, int> ratings;

  /// Overall evaluation score (1-10), based on the individual ratings above.
  final int overallRating;

  final String departmentHeadComments;
  final String supervisorId;
  final String supervisorName;

  /// Snapshot of the basis used for this evaluation at the time it was made.
  final double verifiedDtrHours;
  final int approvedReportCount;

  final String status; // 'Draft' | 'Submitted'
  final String? academicYear;
  final String? createdAt;
  final String? updatedAt;
  final bool sentToHead;
  final String? sentToHeadAt;
  final String? headAttachmentName;
  final String? headAttachmentPath;
  final String? headAttachmentUrl;

  Evaluation({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.office,
    required this.term,
    required this.periodCovered,
    required this.dateOfRating,
    required this.eligibleForRehire,
    required this.ratings,
    required this.overallRating,
    required this.departmentHeadComments,
    required this.supervisorId,
    required this.supervisorName,
    this.verifiedDtrHours = 0,
    this.approvedReportCount = 0,
    this.status = 'Submitted',
    this.academicYear,
    this.createdAt,
    this.updatedAt,
    this.sentToHead = false,
    this.sentToHeadAt,
    this.headAttachmentName,
    this.headAttachmentPath,
    this.headAttachmentUrl,
  });

  double get averageRating {
    if (ratings.isEmpty) return 0;
    final sum = ratings.values.fold<int>(0, (a, b) => a + b);
    return sum / ratings.length;
  }

  factory Evaluation.fromJson(Map<String, dynamic> json) => Evaluation(
    id: json['_id'] ?? json['id'] ?? '',
    studentId: json['studentId'] ?? '',
    studentName: json['studentName'] ?? '',
    office: json['office'] ?? '',
    term: json['term'] ?? 'First Semester',
    periodCovered: json['periodCovered'] ?? '',
    dateOfRating: json['dateOfRating'] ?? '',
    eligibleForRehire: json['eligibleForRehire'] == true,
    ratings: (json['ratings'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ) ??
        const {},
    overallRating: (json['overallRating'] ?? 0) is num
        ? (json['overallRating'] as num).toInt()
        : 0,
    departmentHeadComments: json['departmentHeadComments'] ?? '',
    supervisorId: json['supervisorId'] ?? '',
    supervisorName: json['supervisorName'] ?? '',
    verifiedDtrHours: (json['verifiedDtrHours'] ?? 0).toDouble(),
    approvedReportCount: (json['approvedReportCount'] ?? 0) is num
        ? (json['approvedReportCount'] as num).toInt()
        : 0,
    status: json['status'] ?? 'Submitted',
    academicYear: json['academicYear']?.toString(),
    createdAt: json['createdAt'],
    updatedAt: json['updatedAt'],
    sentToHead: json['sentToHead'] == true,
    sentToHeadAt: json['sentToHeadAt'],
    headAttachmentName: json['headAttachmentName'],
    headAttachmentPath: json['headAttachmentPath'],
    headAttachmentUrl: json['headAttachmentUrl'],
  );

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'studentName': studentName,
    'office': office,
    'term': term,
    'periodCovered': periodCovered,
    'dateOfRating': dateOfRating,
    'eligibleForRehire': eligibleForRehire,
    'ratings': ratings,
    'overallRating': overallRating,
    'departmentHeadComments': departmentHeadComments,
    'supervisorId': supervisorId,
    'supervisorName': supervisorName,
    'verifiedDtrHours': verifiedDtrHours,
    'approvedReportCount': approvedReportCount,
    'status': status,
    'academicYear': academicYear,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'sentToHead': sentToHead,
    'sentToHeadAt': sentToHeadAt,
    'headAttachmentName': headAttachmentName,
    'headAttachmentPath': headAttachmentPath,
    'headAttachmentUrl': headAttachmentUrl,
  }..removeWhere((_, v) => v == null);

  Evaluation copyWith({
    String? office,
    String? term,
    String? periodCovered,
    String? dateOfRating,
    bool? eligibleForRehire,
    Map<String, int>? ratings,
    int? overallRating,
    String? departmentHeadComments,
    double? verifiedDtrHours,
    int? approvedReportCount,
    String? status,
    String? updatedAt,
    bool? sentToHead,
    String? sentToHeadAt,
    String? headAttachmentName,
    String? headAttachmentPath,
    String? headAttachmentUrl,
  }) => Evaluation(
    id: id,
    studentId: studentId,
    studentName: studentName,
    office: office ?? this.office,
    term: term ?? this.term,
    periodCovered: periodCovered ?? this.periodCovered,
    dateOfRating: dateOfRating ?? this.dateOfRating,
    eligibleForRehire: eligibleForRehire ?? this.eligibleForRehire,
    ratings: ratings ?? this.ratings,
    overallRating: overallRating ?? this.overallRating,
    departmentHeadComments:
        departmentHeadComments ?? this.departmentHeadComments,
    supervisorId: supervisorId,
    supervisorName: supervisorName,
    verifiedDtrHours: verifiedDtrHours ?? this.verifiedDtrHours,
    approvedReportCount: approvedReportCount ?? this.approvedReportCount,
    status: status ?? this.status,
    academicYear: academicYear,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sentToHead: sentToHead ?? this.sentToHead,
    sentToHeadAt: sentToHeadAt ?? this.sentToHeadAt,
    headAttachmentName: headAttachmentName ?? this.headAttachmentName,
    headAttachmentPath: headAttachmentPath ?? this.headAttachmentPath,
    headAttachmentUrl: headAttachmentUrl ?? this.headAttachmentUrl,
  );
}