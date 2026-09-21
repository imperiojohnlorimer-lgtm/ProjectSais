import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../models/schedule_event.dart';
import 'supabase_storage_service.dart';

/// Simple Firestore helper for `announcements` collection.
///
/// Methods return simple types to make UI wiring straightforward.
class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? instance})
    : _db = instance ?? FirebaseFirestore.instance;

  CollectionReference get _announcements => _db.collection('announcements');

  CollectionReference get _notifications => _db.collection('notifications');

  /// Ping announcements collection and return elapsed milliseconds or -1 on failure.
  Future<int> pingAnnouncements() async {
    try {
      final sw = Stopwatch()..start();
      await _announcements.limit(1).get();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Adds a new announcement and returns the created document reference.
  Future<DocumentReference> addAnnouncement({
    required String title,
    required String body,
    Map<String, dynamic>? extra,
    String? id,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      ...?extra,
    };

    if (id != null && id.isNotEmpty) {
      final docRef = _announcements.doc(id);
      await docRef.set(data);
      return docRef;
    }

    return await _announcements.add(data);
  }

  /// Streams announcements, newest first by `createdAt`.
  ///
  /// Sorted on the client rather than with a server-side `orderBy`: Firestore
  /// silently drops documents that lack the ordered field, so announcements
  /// without `createdAt` (added by hand or by older versions) would vanish.
  /// Those sort last.
  Stream<List<Map<String, dynamic>>> announcementsStream() {
    return _announcements.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
      DateTime? created(Map<String, dynamic> m) {
        final v = m['createdAt'];
        return v is Timestamp ? v.toDate() : null;
      }

      list.sort((a, b) {
        final ca = created(a);
        final cb = created(b);
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        return cb.compareTo(ca);
      });
      return list;
    });
  }

  /// Newest-first by `createdAt`, sorted here rather than with a server-side
  /// `orderBy` — for the same reason [announcementsStream] does it.
  ///
  /// An `orderBy` alongside a `where` on a different field also needs a
  /// composite index, and without one Firestore rejects the whole query.
  /// That is what left student assistants with an empty attendance list
  /// while supervisors, whose query has no `where`, saw everything.
  /// Records missing `createdAt` sort last instead of disappearing.
  static List<Map<String, dynamic>> _newestFirst(QuerySnapshot snap) {
    final list = snap.docs
        .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
        .toList();
    DateTime? created(Map<String, dynamic> m) {
      final value = m['createdAt'];
      return value is Timestamp ? value.toDate() : null;
    }

    list.sort((a, b) {
      final ca = created(a);
      final cb = created(b);
      if (ca == null && cb == null) return 0;
      if (ca == null) return 1;
      if (cb == null) return -1;
      return cb.compareTo(ca);
    });
    return list;
  }

  /// Streams every attendance document, newest first.
  Stream<List<Map<String, dynamic>>> attendanceStream() {
    return _attendance.snapshots().map(_newestFirst);
  }

  Stream<List<Map<String, dynamic>>> attendanceStreamForStudent(String uid) {
    return _attendance
        .where('studentId', isEqualTo: uid)
        .snapshots()
        .map(_newestFirst);
  }

  /// Streams tasks collection in real-time.
  Stream<List<Map<String, dynamic>>> tasksStream() {
    return _tasks
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> tasksStreamForUser(String uid) {
    return _tasks
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> tasksStreamForUserName(String name) {
    return _tasks
        .where('assignedToName', isEqualTo: name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  /// Streams submitted applications in real time for the admin view.
  Stream<List<Map<String, dynamic>>> applicationsStream() {
    return _applications
        .orderBy('appliedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  /// An applicant's own applications. Sorted here for the same reason the
  /// attendance streams are: a `where` plus an `orderBy` on another field
  /// needs a composite index, and without one the query is rejected and the
  /// applicant sees nothing.
  Stream<List<Map<String, dynamic>>> applicationsStreamForApplicant(
    String uid,
  ) {
    return _applications.where('applicantId', isEqualTo: uid).snapshots().map((
      snap,
    ) {
      final list = snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
      list.sort(
        (a, b) => (b['appliedAt'] ?? '').toString().compareTo(
          (a['appliedAt'] ?? '').toString(),
        ),
      );
      return list;
    });
  }

  CollectionReference get _users => _db.collection('users');

  Future<void> setUserProfile(User user) async {
    await _users.doc(user.id).set(user.toJson());
  }

  Future<void> deleteUserProfile(String id) async {
    await _users.doc(id).delete();
  }

  Future<User> migrateUserProfileToAuthUid({
    required String uid,
    required String email,
    required User fallback,
  }) async {
    final snapshot = await _users
        .where('email', isEqualTo: email.toLowerCase())
        .get();
    final rolePriority = {
      'Admin': 4,
      'Supervisor': 3,
      'Student Assistant': 2,
      'Student': 1,
    };
    final sourceDoc = snapshot.docs.isEmpty
        ? null
        : snapshot.docs.reduce((first, next) {
            final firstRole = (first.data() as Map<String, dynamic>)['role'];
            final nextRole = (next.data() as Map<String, dynamic>)['role'];
            return (rolePriority[firstRole] ?? 0) >=
                    (rolePriority[nextRole] ?? 0)
                ? first
                : next;
          });
    final source = sourceDoc == null
        ? fallback
        : User.fromJson({
            ...(sourceDoc.data() as Map<String, dynamic>),
            'id': sourceDoc.id,
          });
    final canonical = source.copyWith(id: uid);

    await _users.doc(uid).set(canonical.toJson());
    for (final doc in snapshot.docs) {
      if (doc.id != uid) await doc.reference.delete();
    }
    return canonical;
  }

  Future<void> archiveAnnouncementsForAcademicYear(String academicYear) async {
    final snapshot = await _announcements
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('announcements');
    for (final announcement in snapshot.docs) {
      await archiveCollection.doc(announcement.id).set({
        ...(announcement.data() as Map<String, dynamic>),
        'archivedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> archiveCalendarEventsForAcademicYear(String academicYear) async {
    final events = await _db
        .collection('schedule_events')
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('calendar_events');
    for (final event in events.docs) {
      final scheduleEvent = ScheduleEvent.fromJson({
        ...event.data(),
        'id': event.id,
      });
      await archiveCollection.doc(event.id).set({
        ...scheduleEvent.toJson(),
        'archivedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<Map<String, dynamic>?> getAcademicYearSettings() async {
    final snapshot = await _db
        .collection('meta')
        .doc('academic_year_settings')
        .get();
    return snapshot.exists ? snapshot.data() : null;
  }

  Future<void> saveAcademicYearSettings(Map<String, dynamic> settings) async {
    await _db.collection('meta').doc('academic_year_settings').set(settings);
  }

  Future<void> archiveAcademicYearSettings(
    String academicYear,
    Map<String, dynamic> settings,
  ) async {
    final archiveRef = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear);
    if ((await archiveRef.get()).exists) return;
    await archiveRef.set({
      ...settings,
      'academicYear': academicYear,
      'archivedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveAttendanceForAcademicYear(String academicYear) async {
    final attendanceSnapshot = await _attendance.get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('attendance');
    final records = attendanceSnapshot.docs
        .where(
          (doc) => (doc.data() as Map<String, dynamic>)['isArchived'] != true,
        )
        .toList();
    for (var offset = 0; offset < records.length; offset += 400) {
      final batch = _db.batch();
      final chunk = records.skip(offset).take(400);
      for (final record in chunk) {
        final data = Map<String, dynamic>.from(
          record.data() as Map<String, dynamic>,
        );
        data['archivedAt'] = FieldValue.serverTimestamp();
        batch.set(archiveCollection.doc(record.id), data);
        batch.update(record.reference, {
          'isArchived': true,
          'archivedAcademicYear': academicYear,
          'archivedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> archiveReportsForAcademicYear(String academicYear) async {
    final reportSnapshot = await _reports
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('reports');
    for (final report in reportSnapshot.docs) {
      final data = Map<String, dynamic>.from(
        report.data() as Map<String, dynamic>,
      );
      final attachments = (data['attachments'] as List<dynamic>?) ?? [];
      final archivedAttachments = <Map<String, dynamic>>[];
      for (final rawAttachment in attachments) {
        final attachment = ReportAttachment.fromJson(
          Map<String, dynamic>.from(rawAttachment as Map),
        );
        if (attachment.storagePath.isEmpty) {
          archivedAttachments.add(attachment.toJson());
          continue;
        }
        final archivePath =
            'academic_year_archives/$academicYear/reports/${report.id}/${attachment.fileName}';
        try {
          final archivedUrl = await SupabaseStorageService.instance
              .archiveDocument(
                sourcePath: attachment.storagePath,
                archivePath: archivePath,
              );
          archivedAttachments.add({
            ...attachment.toJson(),
            'storagePath': archivePath,
            'downloadUrl': archivedUrl,
          });
        } catch (_) {
          archivedAttachments.add(attachment.toJson());
        }
      }
      data['attachments'] = archivedAttachments;
      data['archivedAt'] = FieldValue.serverTimestamp();
      await archiveCollection.doc(report.id).set(data);
    }
  }

  Future<void> archiveApplicationsForAcademicYear(String academicYear) async {
    final applicationSnapshot = await _applications
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('applications');
    for (final application in applicationSnapshot.docs) {
      final data = Map<String, dynamic>.from(
        application.data() as Map<String, dynamic>,
      );
      final documents = (data['submittedDocuments'] as List<dynamic>?) ?? [];
      final archivedDocuments = <Map<String, dynamic>>[];
      for (final rawDocument in documents) {
        final document = ApplicationDocument.fromJson(
          Map<String, dynamic>.from(rawDocument as Map),
        );
        if (document.storagePath == null || document.storagePath!.isEmpty) {
          archivedDocuments.add(document.toJson());
          continue;
        }
        final archivePath =
            'academic_year_archives/$academicYear/applications/${application.id}/${document.fileName}';
        try {
          final archivedUrl = await SupabaseStorageService.instance
              .archiveDocument(
                sourcePath: document.storagePath!,
                archivePath: archivePath,
              );
          archivedDocuments.add({
            ...document.toJson(),
            'storagePath': archivePath,
            'downloadUrl': archivedUrl,
          });
        } catch (_) {
          archivedDocuments.add(document.toJson());
        }
      }
      data['submittedDocuments'] = archivedDocuments;
      data['archivedAt'] = FieldValue.serverTimestamp();
      await archiveCollection.doc(application.id).set(data);
    }
  }

  Future<List<Map<String, dynamic>>> getAcademicYearArchives() async {
    final snapshot = await _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .orderBy('academicYear', descending: true)
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  CollectionReference get _offices => _db.collection('offices');

  CollectionReference get _departments => _db.collection('departments');

  Future<List<String>> getAllDepartments() async {
    final snapshot = await _departments.orderBy('name').get();
    return snapshot.docs
        .map(
          (doc) =>
              (doc.data() as Map<String, dynamic>)['name']?.toString() ?? '',
        )
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<Map<String, String>> getDepartmentCodes() async {
    final snapshot = await _departments.get();
    return {
      for (final doc in snapshot.docs)
        if ((doc.data() as Map<String, dynamic>)['name']
                ?.toString()
                .isNotEmpty ==
            true)
          (doc.data() as Map<String, dynamic>)['name'].toString():
              (doc.data() as Map<String, dynamic>)['code']?.toString() ?? '',
    };
  }

  Future<void> setDepartment(String name, {String code = ''}) async {
    await _departments.doc(name).set({
      'name': name,
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteDepartment(String name) async {
    await _departments.doc(name).delete();
  }

  Future<void> updateDepartment(String oldName, String newName) async {
    await setDepartment(newName);
    if (oldName != newName) await deleteDepartment(oldName);
  }

  CollectionReference get _skills => _db.collection('skills');

  Future<List<String>> getAllSkills() async {
    final snapshot = await _skills.orderBy('name').get();
    return snapshot.docs
        .map(
          (doc) =>
              (doc.data() as Map<String, dynamic>)['name']?.toString() ?? '',
        )
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> setSkill(String name) async {
    await _skills.doc(name).set({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteSkill(String name) async {
    await _skills.doc(name).delete();
  }

  Future<void> updateSkill(String oldName, String newName) async {
    await setSkill(newName);
    if (oldName != newName) await deleteSkill(oldName);
  }

  Future<List<Office>> getAllOffices() async {
    final snapshot = await _offices.get();
    return snapshot.docs
        .map(
          (doc) => Office.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  Future<void> setOffice(Office office) async {
    await _offices.doc(office.id).set(office.toJson());
  }

  Future<void> deleteOffice(String id) async {
    await _offices.doc(id).delete();
  }

  Future<User?> getUserProfileById(String id) async {
    final doc = await _users.doc(id).get();
    if (!doc.exists) return null;
    return User.fromJson({
      ...(doc.data() as Map<String, dynamic>),
      'id': doc.id,
    });
  }

  Future<User?> getUserProfileByEmail(String email) async {
    final snapshot = await _users
        .where('email', isEqualTo: email.toLowerCase())
        .get();
    if (snapshot.docs.isEmpty) return null;

    // Prefer the highest-privilege profile when duplicate records exist for
    // an email, so an older Student document cannot hide a saved Admin role.
    final rolePriority = {
      'Admin': 4,
      'Supervisor': 3,
      'Student Assistant': 2,
      'Student': 1,
    };
    final doc = snapshot.docs.reduce((first, next) {
      final firstRole = (first.data() as Map<String, dynamic>)['role'];
      final nextRole = (next.data() as Map<String, dynamic>)['role'];
      return (rolePriority[firstRole] ?? 0) >= (rolePriority[nextRole] ?? 0)
          ? first
          : next;
    });
    return User.fromJson({
      ...(doc.data() as Map<String, dynamic>),
      'id': doc.id,
    });
  }

  /// Looks up a user profile by Student ID. Used to make sure a Student ID
  /// can't be claimed by more than one account during registration.
  Future<User?> getUserProfileByStudentId(String studentId) async {
    final normalized = studentId.trim();
    if (normalized.isEmpty) return null;

    final snapshot = await _users
        .where('studentId', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    return User.fromJson({
      ...(doc.data() as Map<String, dynamic>),
      'id': doc.id,
    });
  }

  Future<List<User>> getAllUserProfiles() async {
    final snapshot = await _users.get();
    return snapshot.docs
        .map(
          (doc) => User.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  // Students
  CollectionReference get _students => _db.collection('students');

  Future<List<Student>> getAllStudents() async {
    final snap = await _students.get();
    return snap.docs
        .map(
          (d) => Student.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<String>> getStudentIdsForUser(String uid) async {
    final snap = await _students.where('userId', isEqualTo: uid).get();
    return snap.docs.map((doc) => doc.id).toList();
  }

  Future<void> setStudent(Student s) async {
    final data = {
      'name': s.name,
      'email': s.email,
      'department': s.department,
      'campus': s.campus,
      'status': s.status,
      'totalHours': s.totalHours,
      'phone': s.phone,
      'address': s.address,
      'avatar': s.avatar,
      'userId': s.userId,
    }..removeWhere((k, v) => v == null);
    if (s.id.isNotEmpty) {
      await _students.doc(s.id).set(data);
    } else {
      await _students.add(data);
    }
  }

  Future<void> deleteStudent(String id) async {
    await _students.doc(id).delete();
  }

  // Attendance
  CollectionReference get _attendance => _db.collection('attendance');

  Future<List<Map<String, dynamic>>> getAllAttendance() async {
    final snap = await _attendance.get();
    return snap.docs
        .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAttendanceForStudent(String uid) async {
    final snap = await _attendance.where('studentId', isEqualTo: uid).get();
    return snap.docs
        .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
        .toList();
  }

  Future<DocumentReference> addAttendance(
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final payload = {...data, 'createdAt': FieldValue.serverTimestamp()};
    if (id != null && id.isNotEmpty) {
      final docRef = _attendance.doc(id);
      await docRef.set(payload);
      return docRef;
    }
    return await _attendance.add(payload);
  }

  Future<void> deleteAttendance(String id) async {
    await _attendance.doc(id).delete();
  }

  Future<void> updateAttendance(String id, Map<String, dynamic> data) async {
    await _attendance.doc(id).update(data);
  }

  // Class Schedule
  CollectionReference get _classSchedules => _db.collection('classSchedules');

  Future<List<ClassScheduleEntry>> getAllClassSchedules() async {
    final snap = await _classSchedules.get();
    return snap.docs
        .map(
          (d) => ClassScheduleEntry.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<ClassScheduleEntry>> getClassSchedulesForStudent(
    String uid,
  ) async {
    final snap = await _classSchedules.where('studentId', isEqualTo: uid).get();
    return snap.docs
        .map(
          (d) => ClassScheduleEntry.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<ClassScheduleEntry> addClassScheduleEntry(ClassScheduleEntry c) async {
    final data = c.toJson()..remove('id');
    final docRef = await _classSchedules.add(data);
    return ClassScheduleEntry(
      id: docRef.id,
      studentId: c.studentId,
      studentName: c.studentName,
      course: c.course,
      units: c.units,
      monday: c.monday,
      tuesday: c.tuesday,
      wednesday: c.wednesday,
      thursday: c.thursday,
      friday: c.friday,
      saturday: c.saturday,
      academicYear: c.academicYear,
      sourceRuleLabel: c.sourceRuleLabel,
    );
  }

  Future<void> deleteClassScheduleEntry(String id) async {
    await _classSchedules.doc(id).delete();
  }

  /// Deletes every saved class-schedule row for [studentName], so a fresh
  /// set can be written in its place (used when a supervisor re-saves the
  /// whole grid from the DTR/Accomplishment Report screen).
  Future<void> deleteClassScheduleEntriesForStudent(String studentName) async {
    final snap = await _classSchedules
        .where('studentName', isEqualTo: studentName)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  // Tasks
  CollectionReference get _tasks => _db.collection('tasks');

  Future<List<Task>> getAllTasks() async {
    final snap = await _tasks.orderBy('createdAt', descending: true).get();
    return snap.docs
        .map(
          (d) => Task.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Task>> getTasksForUser(String uid) async {
    final snap = await _tasks
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map(
          (d) => Task.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Task>> getTasksForUserName(String name) async {
    final snap = await _tasks.where('assignedToName', isEqualTo: name).get();
    return snap.docs
        .map(
          (d) => Task.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Task>> getTasksForAssigneeIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final snap = await _tasks.where('assignedTo', whereIn: ids).get();
    return snap.docs
        .map(
          (d) => Task.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setTask(Task t) async {
    final data = {
      'title': t.title,
      'description': t.description,
      'status': t.status,
      'priority': t.priority,
      'dueDate': t.dueDate,
      'assignedTo': t.assignedTo,
      'assignedToName': t.assignedToName,
      'assignedBy': t.assignedBy,
      'category': t.category,
      'checklistItems': t.checklistItems,
      'isArchived': t.isArchived,
      'academicYear': t.academicYear,
      'completedAt': t.completedAt,
    }..removeWhere((k, v) => v == null);

    if (t.id.isNotEmpty) {
      final docRef = _tasks.doc(t.id);
      final existing = await docRef.get();
      if (existing.exists &&
          (existing.data() as Map<String, dynamic>?)?.containsKey(
                'createdAt',
              ) ==
              true) {
        await docRef.set(data, SetOptions(merge: true));
      } else {
        await docRef.set({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } else {
      final payload = {...data, 'createdAt': FieldValue.serverTimestamp()};
      await _tasks.add(payload);
    }
  }

  Future<void> deleteTask(String id) async {
    await _tasks.doc(id).delete();
  }

  Future<void> archiveTasksForAcademicYear(String academicYear) async {
    final snapshot = await _tasks
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('tasks');
    for (final task in snapshot.docs) {
      await archiveCollection.doc(task.id).set({
        ...(task.data() as Map<String, dynamic>),
        'archivedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Reports
  CollectionReference get _reports => _db.collection('reports');

  Future<List<Report>> getAllReports() async {
    final snap = await _reports.get();
    return snap.docs
        .map(
          (d) => Report.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Report>> getReportsForApplicant(String uid) async {
    final snap = await _reports.where('applicantId', isEqualTo: uid).get();
    return snap.docs
        .map(
          (d) => Report.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Report>> getReportsForStudentName(String name) async {
    final snap = await _reports.where('studentName', isEqualTo: name).get();
    return snap.docs
        .map(
          (d) => Report.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  /// Ping reports collection and return elapsed milliseconds or -1 on failure.
  Future<int> pingReports() async {
    try {
      final sw = Stopwatch()..start();
      await _reports.limit(1).get();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  Future<void> setReport(Report r) async {
    final data = {
      'applicantId': r.applicantId,
      'title': r.title,
      'content': r.content,
      'studentName': r.studentName,
      'status': r.status,
      'submittedAt': r.submittedAt,
      'feedback': r.feedback,
      'academicYear': r.academicYear,
      'attachments': r.attachments
          .map((attachment) => attachment.toJson())
          .toList(),
      'sentToHead': r.sentToHead,
      'sentToHeadAt': r.sentToHeadAt,
      'headAttachments': r.headAttachments
          .map((attachment) => attachment.toJson())
          .toList(),
    }..removeWhere((k, v) => v == null);
    if (r.id.isNotEmpty) {
      await _reports.doc(r.id).set(data);
    } else {
      await _reports.add(data);
    }
  }

  // Items a Supervisor has forwarded to the Head (reports, evaluations,
  // DTR/Accomplishment reports) — shown on the Head's dedicated screen.
  CollectionReference get _headForwards => _db.collection('headForwards');

  Future<List<HeadForward>> getAllHeadForwards() async {
    final snap = await _headForwards.get();
    return snap.docs
        .map(
          (d) => HeadForward.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<String> addHeadForward(HeadForward forward) async {
    final ref = await _headForwards.add(forward.toJson());
    return ref.id;
  }

  /// Streams forwarded items in real time so the Head's "Sent to Head"
  /// screen updates immediately, even if it was already open when a
  /// supervisor sends something (or the Head logged in earlier).
  Stream<List<Map<String, dynamic>>> headForwardsStream() {
    return _headForwards.snapshots().map(
      (snap) => snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList(),
    );
  }

  Future<void> setHeadForwardReviewed(String id, bool reviewed) async {
    await _headForwards.doc(id).update({'reviewed': reviewed});
  }

  // Payroll: one processed record per Student Assistant per month, created
  // by an Admin running the Payroll screen's "Process Payroll" action.
  CollectionReference get _payrollRecords => _db.collection('payrollRecords');

  Future<List<PayrollRecord>> getAllPayrollRecords() async {
    final snap = await _payrollRecords.get();
    return snap.docs
        .map(
          (d) => PayrollRecord.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Stream<List<Map<String, dynamic>>> payrollRecordsStream() {
    return _payrollRecords.snapshots().map(
      (snap) => snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList(),
    );
  }

  Future<String> addPayrollRecord(PayrollRecord record) async {
    final ref = await _payrollRecords.add(record.toJson());
    return ref.id;
  }

  Future<void> updatePayrollRecord(String id, Map<String, dynamic> data) async {
    await _payrollRecords.doc(id).update(data);
  }

  // Performance Evaluations
  CollectionReference get _evaluations => _db.collection('evaluations');

  Future<List<Evaluation>> getAllEvaluations() async {
    final snap = await _evaluations.get();
    return snap.docs
        .map(
          (d) => Evaluation.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setEvaluation(Evaluation e) async {
    final data = e.toJson();
    if (e.id.isNotEmpty) {
      await _evaluations.doc(e.id).set(data);
    } else {
      await _evaluations.add(data);
    }
  }

  Future<void> deleteEvaluation(String id) async {
    await _evaluations.doc(id).delete();
  }

  // Applications
  CollectionReference get _applications => _db.collection('applications');

  Future<List<Application>> getAllApplications() async {
    final snap = await _applications.get();
    return snap.docs
        .map(
          (d) => Application.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setApplication(Application a) async {
    final data = {
      'announcementId': a.announcementId,
      'announcementTitle': a.announcementTitle,
      'applicantId': a.applicantId,
      'applicantName': a.applicantName,
      'appliedAt': a.appliedAt,
      'status': a.status,
      'remarks': a.remarks,
      'skills': a.skills,
      'submittedDocuments': a.submittedDocuments
          .map((document) => document.toJson())
          .toList(),
      'academicYear': a.academicYear,
    }..removeWhere((k, v) => v == null);
    if (a.id.isNotEmpty) {
      await _applications.doc(a.id).set(data);
    } else {
      await _applications.add(data);
    }
  }

  CollectionReference get _screeningRecords =>
      _db.collection('screeningRecords');

  // Deduping (by applicant + academic year) is handled by AppState, which
  // needs to keep records from different academic years distinct instead
  // of collapsing all of an applicant's screenings into one.
  Future<List<ScreeningRecord>> getAllScreeningRecords() async {
    final snap = await _screeningRecords.get();
    return snap.docs
        .map(
          (doc) => ScreeningRecord.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  Future<List<ScreeningRecord>> getScreeningRecordsForApplicant(
    String applicantId,
  ) async {
    final snap = await _screeningRecords
        .where('applicantId', isEqualTo: applicantId)
        .get();
    return snap.docs
        .map(
          (doc) => ScreeningRecord.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  Future<void> setScreeningRecord(ScreeningRecord record) async {
    final data = record.toJson();
    data.remove('id');
    await _screeningRecords.doc(record.id).set(data);
  }

  Future<void> deleteScreeningRecord(String id) async {
    await _screeningRecords.doc(id).delete();
  }

  // Document Folders (Head's free-form file manager)

  CollectionReference get _documentFolders => _db.collection('documentFolders');

  Future<List<DocumentFolder>> getAllDocumentFolders() async {
    final snap = await _documentFolders.get();
    return snap.docs
        .map(
          (doc) => DocumentFolder.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  Future<String> addDocumentFolder(DocumentFolder folder) async {
    final ref = await _documentFolders.add(folder.toJson());
    return ref.id;
  }

  Future<void> deleteDocumentFolder(String id) async {
    await _documentFolders.doc(id).delete();
  }

  // Notifications

  Future<List<Map<String, dynamic>>> getNotificationsForUser(
    String userId,
  ) async {
    final snap = await _notifications.where('userId', isEqualTo: userId).get();
    return snap.docs
        .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
        .toList();
  }

  Future<void> addNotification(Map<String, dynamic> payload) async {
    final id = payload['id']?.toString();
    final data = {...payload, 'createdAt': FieldValue.serverTimestamp()};
    if (id != null && id.isNotEmpty) {
      await _notifications.doc(id).set(data);
    } else {
      await _notifications.add(data);
    }
  }

  Future<void> updateNotification(String id, Map<String, dynamic> data) async {
    await _notifications.doc(id).update(data);
  }

  Future<void> deleteNotification(String id) async {
    await _notifications.doc(id).delete();
  }

  Future<void> deleteNotificationsForUser(String userId) async {
    final snap = await _notifications.where('userId', isEqualTo: userId).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // Documents
  CollectionReference get _documents => _db.collection('documents');

  Future<List<Document>> getAllDocuments() async {
    final snap = await _documents.get();
    return snap.docs
        .map(
          (d) => Document.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setDocument(Document doc) async {
    final data = doc.toJson();
    if (doc.id.isNotEmpty) {
      await _documents.doc(doc.id).set(data);
    } else {
      await _documents.add(data);
    }
  }

  Future<void> deleteDocument(String id) async {
    await _documents.doc(id).delete();
  }

  /// Reads a single announcement by id, or null if missing.
  Future<Map<String, dynamic>?> getAnnouncement(String id) async {
    final doc = await _announcements.doc(id).get();
    if (!doc.exists) return null;
    return {...(doc.data() as Map<String, dynamic>), 'id': doc.id};
  }

  // Attendance QR token (single doc) ------------------------------------------------
  /// Stores the attendance QR token for a session (`yyyyMMdd-AM` /
  /// `yyyyMMdd-PM`) with a server timestamp.
  Future<void> setCurrentQrToken(String token, String sessionKey) async {
    final doc = _db.collection('meta').doc('current_qr');
    await doc.set({
      'token': token,
      'sessionKey': sessionKey,
      'generatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Returns the current attendance QR token doc, or null if missing.
  Future<Map<String, dynamic>?> getCurrentQrToken() async {
    final doc = await _db.collection('meta').doc('current_qr').get();
    if (!doc.exists) return null;
    return {...(doc.data() as Map<String, dynamic>), 'id': doc.id};
  }

  /// Updates an announcement (partial update).
  Future<void> updateAnnouncement(String id, Map<String, dynamic> data) async {
    await _announcements.doc(id).update(data);
  }

  /// Deletes an announcement.
  Future<void> deleteAnnouncement(String id) async {
    await _announcements.doc(id).delete();
  }
}
