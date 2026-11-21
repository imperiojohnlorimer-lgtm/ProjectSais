part of '../app_state.dart';

// ─── Class schedules ──────────────────────────────────────
//
// A Student Assistant's class schedule comes from the file they upload:
// with their application (it becomes their schedule when the application is
// approved), or later from the Calendar ("Upload new schedule", which waits
// for the Head). Only a Head changes an approved schedule; the Firestore
// rules hold everyone else to that. The Calendar and the DTR/Accomplishment
// Report read the version in effect on each day (class_schedule.dart).
extension AppStateClassSchedules on AppState {
  /// Requests waiting for the Head, oldest first.
  List<ScheduleRequest> get pendingScheduleRequests =>
      scheduleRequests.where((r) => r.isPending).toList()..sort(
        (a, b) => (a.submittedAt ?? DateTime(9999)).compareTo(
          b.submittedAt ?? DateTime(9999),
        ),
      );

  /// Decided or cancelled requests, newest first.
  List<ScheduleRequest> get decidedScheduleRequests =>
      scheduleRequests.where((r) => !r.isPending).toList()..sort(
        (a, b) => (b.submittedAt ?? DateTime(0)).compareTo(
          a.submittedAt ?? DateTime(0),
        ),
      );

  /// The signed-in Student Assistant's newest request, if any.
  ScheduleRequest? get myLatestScheduleRequest {
    final mine = scheduleRequests
        .where((r) => r.studentId == currentUser?.id)
        .toList();
    if (mine.isEmpty) return null;
    mine.sort(
      (a, b) => (b.submittedAt ?? DateTime(9999)).compareTo(
        a.submittedAt ?? DateTime(9999),
      ),
    );
    return mine.first;
  }

  /// Today in the Philippines as "yyyy-MM-dd".
  String get scheduleToday => ClassScheduleVersion.dayKey(philippineClock());

  /// Sends the signed-in Student Assistant's new class schedule to the Head.
  /// An older request still waiting is cancelled first: only the newest
  /// counts. Returns a problem to show, or null when sent.
  Future<String?> submitScheduleRequest({
    required String fileName,
    required String filePath,
    required List<RecurringScheduleRule> subjects,
    required String effectiveFrom,
    String note = '',
  }) async {
    final user = currentUser;
    if (user == null || user.role != 'Student Assistant') {
      return 'Only a Student Assistant can send a class schedule.';
    }
    if (subjects.isEmpty) return 'Add at least one class.';
    if (_sendingScheduleRequest) return 'Your schedule is already being sent.';
    _sendingScheduleRequest = true;
    try {
      _firestoreService ??= FirestoreService();
      final fs = _firestoreService!;
      for (final old in scheduleRequests.where(
        (r) => r.studentId == user.id && r.isPending,
      )) {
        try {
          await fs.updateScheduleRequest(old.id, {
            'status': ScheduleRequest.cancelled,
          });
        } catch (error) {
          debugPrint('Failed to cancel the older schedule request: $error');
          return 'Your earlier request could not be withdrawn. Please try again.';
        }
      }
      final request = ScheduleRequest(
        id: '${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        studentId: user.id,
        studentName: user.name,
        academicYear: academicYear,
        fileName: fileName,
        filePath: filePath,
        subjects: subjects,
        effectiveFrom: effectiveFrom,
        note: note.trim(),
      );
      try {
        await fs.createScheduleRequest(request);
      } catch (error) {
        debugPrint('Failed to send the schedule request: $error');
        return 'Your schedule could not be sent. Please try again.';
      }
      scheduleRequests = [
        // The live list may already hold the new one: it stays Pending.
        for (final r in scheduleRequests)
          r.studentId == user.id && r.isPending && r.id != request.id
              ? r.copyWith(status: ScheduleRequest.cancelled)
              : r,
        if (!scheduleRequests.any((r) => r.id == request.id))
          request.copyWith(),
      ];
      for (final headId in await _headIds()) {
        _addNotification(
          AppNotification(
            id: '',
            userId: headId,
            title: 'Schedule Change Request',
            message: '${user.name} sent a new class schedule for approval.',
            type: 'schedule',
            createdAt: _formattedToday(),
          ),
        );
      }
      _notify();
      return null;
    } finally {
      _sendingScheduleRequest = false;
    }
  }

  /// Withdraws the signed-in Student Assistant's waiting request.
  Future<String?> cancelScheduleRequest(String id) async {
    final request = scheduleRequests.where((r) => r.id == id).firstOrNull;
    if (request == null || !request.isPending) return null;
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateScheduleRequest(id, {
        'status': ScheduleRequest.cancelled,
      });
    } catch (error) {
      debugPrint('Failed to cancel the schedule request: $error');
      return 'The request could not be withdrawn. Please try again.';
    }
    scheduleRequests = [
      for (final r in scheduleRequests)
        r.id == id ? r.copyWith(status: ScheduleRequest.cancelled) : r,
    ];
    _notify();
    return null;
  }

  /// The Head approves a request: it becomes the student's schedule from
  /// its start day, their old typed subjects go, and they and their office
  /// Supervisors are told. Returns a problem to show, or null.
  Future<String?> approveScheduleRequest(String id) async {
    final head = currentUser;
    if (head == null || role != 'Head')
      return 'Only the Head can approve this.';
    final request = scheduleRequests.where((r) => r.id == id).firstOrNull;
    if (request == null) return 'This request is no longer listed.';
    if (!request.isPending)
      return 'This request was already ${request.status.toLowerCase()}.';
    final now = DateTime.now().toUtc().toIso8601String();
    final version = ClassScheduleVersion(
      id: 'cs_${DateTime.now().millisecondsSinceEpoch}',
      // The year in effect now: a request sent just before the year
      // changed applies to the new one.
      academicYear: academicYear,
      effectiveFrom: request.effectiveFrom.isEmpty
          ? scheduleToday
          : request.effectiveFrom,
      fileName: request.fileName,
      filePath: request.filePath,
      subjects: request.subjects,
      approvedAt: now,
      approvedBy: head.name,
      source: 'request',
      sourceId: request.id,
    );
    final fields = {
      'status': ScheduleRequest.approved,
      'reviewedBy': head.name,
      'reviewedAt': now,
    };
    final problem = await _addVersion(
      request.studentId,
      request.studentName,
      version,
      requestId: request.id,
      requestFields: fields,
    );
    if (problem != null) return problem;
    scheduleRequests = [
      for (final r in scheduleRequests)
        r.id == id
            ? r.copyWith(
                status: ScheduleRequest.approved,
                reviewedBy: head.name,
                reviewedAt: now,
              )
            : r,
    ];
    _tellScheduleApproved(request.studentId, request.studentName, version);
    _notify();
    return null;
  }

  /// The Head rejects a request with a reason; the old schedule stays.
  Future<String?> rejectScheduleRequest(String id, String reason) async {
    final head = currentUser;
    if (head == null || role != 'Head') return 'Only the Head can reject this.';
    final request = scheduleRequests.where((r) => r.id == id).firstOrNull;
    if (request == null || !request.isPending) {
      return 'This request is no longer waiting.';
    }
    final note = reason.trim();
    if (note.isEmpty) return 'Say why, so the student can fix it.';
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateScheduleRequest(id, {
        'status': ScheduleRequest.rejected,
        'reviewNote': note,
        'reviewedBy': head.name,
        'reviewedAt': now,
      });
    } catch (error) {
      debugPrint('Failed to reject the schedule request: $error');
      return 'The request could not be updated. It may have been withdrawn; '
          'the list will refresh.';
    }
    scheduleRequests = [
      for (final r in scheduleRequests)
        r.id == id
            ? r.copyWith(
                status: ScheduleRequest.rejected,
                reviewNote: note,
                reviewedBy: head.name,
                reviewedAt: now,
              )
            : r,
    ];
    _addNotification(
      AppNotification(
        id: '',
        userId: request.studentId,
        title: 'Class Schedule Not Approved',
        message: 'Your new class schedule was not approved. Reason: $note',
        type: 'schedule',
        createdAt: _formattedToday(),
      ),
    );
    _notify();
    return null;
  }

  /// The Head types or corrects a student's subjects directly. They take
  /// effect from [effectiveFrom] (today when not given); the file of the
  /// schedule in effect is kept.
  Future<String?> saveClassScheduleByHead({
    required String studentId,
    required String studentName,
    required List<RecurringScheduleRule> subjects,
    String? effectiveFrom,
  }) async {
    final head = currentUser;
    if (head == null || role != 'Head') return 'Only the Head can change this.';
    if (subjects.isEmpty) return 'Add at least one class.';
    _firestoreService ??= FirestoreService();
    OwnerSchedule current;
    try {
      current = await _firestoreService!.getOwnerSchedule(studentId);
    } catch (error) {
      debugPrint('Failed to read the class schedule: $error');
      return 'The schedule could not be read. Please try again.';
    }
    final inEffect = ClassScheduleVersion.inEffect(
      current.versions,
      philippineClock(),
      academicYear: academicYear,
    );
    final version = ClassScheduleVersion(
      id: 'cs_${DateTime.now().millisecondsSinceEpoch}',
      academicYear: academicYear,
      effectiveFrom: effectiveFrom ?? scheduleToday,
      fileName: inEffect?.fileName ?? '',
      filePath: inEffect?.filePath ?? '',
      subjects: subjects,
      approvedAt: DateTime.now().toUtc().toIso8601String(),
      approvedBy: head.name,
      source: 'head',
    );
    final problem = await _addVersion(studentId, studentName, version);
    if (problem != null) return problem;
    _tellScheduleApproved(studentId, studentName, version, byHead: true);
    _notify();
    return null;
  }

  /// After an approval: the application's class schedule becomes the
  /// student's, from today. Safe to run again (a schedule already taken
  /// from this application isn't added twice). Returns a problem, or null.
  Future<String?> _adoptApplicationSchedule(Application app) async {
    final schedule = app.classSchedule;
    if (schedule == null || schedule.subjects.isEmpty) return null;
    final version = ClassScheduleVersion(
      id: 'cs_${DateTime.now().millisecondsSinceEpoch}',
      academicYear: app.academicYear ?? academicYear,
      effectiveFrom: scheduleToday,
      fileName: schedule.fileName,
      filePath: schedule.filePath,
      subjects: schedule.subjects,
      approvedAt: DateTime.now().toUtc().toIso8601String(),
      approvedBy: currentUser?.name ?? '',
      source: 'application',
      sourceId: app.id,
    );
    return _addVersion(app.applicantId, app.applicantName, version);
  }

  Future<String?> _addVersion(
    String ownerId,
    String ownerName,
    ClassScheduleVersion version, {
    String? requestId,
    Map<String, dynamic>? requestFields,
  }) async {
    _firestoreService ??= FirestoreService();
    final fs = _firestoreService!;
    // The old typed subjects' days on the calendar, to clear afterwards.
    List<String> oldSubjectPrefixes = const [];
    try {
      final before = await fs.getOwnerSchedule(ownerId);
      oldSubjectPrefixes = [
        for (final r in before.rules)
          if (r.isSubject) 'rule_${r.id}_',
      ];
    } catch (error) {
      debugPrint('Failed to read the old schedule: $error');
    }
    String outcome;
    try {
      outcome = await fs.addClassScheduleVersion(
        ownerId: ownerId,
        ownerName: ownerName,
        version: version,
        requestId: requestId,
        requestFields: requestFields,
      );
    } catch (error) {
      debugPrint('Failed to save the class schedule: $error');
      return 'The class schedule could not be saved. Please try again.';
    }
    if (outcome == 'not-pending') {
      return 'This request was withdrawn or already decided.';
    }
    if (outcome == 'already') return null;
    if (oldSubjectPrefixes.isNotEmpty) {
      try {
        await fs.deleteScheduleEventsWithPrefixes(ownerId, oldSubjectPrefixes);
      } catch (error) {
        // They no longer count anywhere; the calendar hides them.
        debugPrint('Failed to clear the old subject days: $error');
      }
    }
    return null;
  }

  void _tellScheduleApproved(
    String studentId,
    String studentName,
    ClassScheduleVersion version, {
    bool byHead = false,
  }) {
    final from =
        philippineDayText('${version.effectiveFrom}T04:00:00Z') ??
        version.effectiveFrom;
    _addNotification(
      AppNotification(
        id: '',
        userId: studentId,
        title: byHead ? 'Class Schedule Updated' : 'Class Schedule Approved',
        message: byHead
            ? 'The Head updated your class schedule. It applies from $from.'
            : 'Your new class schedule was approved. It applies from $from.',
        type: 'schedule',
        createdAt: _formattedToday(),
      ),
    );
    final student = users.where((u) => u.id == studentId).firstOrNull;
    if (student == null) return;
    final supervisors = <String>{
      for (final office in officesForUser(student))
        if (office.hasAssistant(student.id, student.name))
          ...office.headIds.where((id) => id.isNotEmpty),
    };
    for (final id in supervisors) {
      _addNotification(
        AppNotification(
          id: '',
          userId: id,
          title: 'Class Schedule Updated',
          message:
              "$studentName's class schedule changed from $from. The next "
              'DTR sync uses it.',
          type: 'schedule',
          createdAt: _formattedToday(),
        ),
      );
    }
  }
}
