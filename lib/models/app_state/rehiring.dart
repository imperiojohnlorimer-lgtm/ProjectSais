part of '../app_state.dart';

  // ─── Rehiring ──────────────────────────────────────
extension AppStateRehiring on AppState {
  /// Terms the Head can make rehire decisions for: the current term (per the
  /// academic year settings) and the three after it.
  List<({String academicYear, String semester})> get rehireTermOptions {
    final options = [(academicYear: academicYear, semester: academicSemester)];
    while (options.length < 4) {
      options.add(
        RehireRecord.nextTerm(options.last.academicYear, options.last.semester),
      );
    }
    return options;
  }

  /// The term the Rehiring screen opens on: the one after the current term,
  /// skipping the optional Summer term.
  ({String academicYear, String semester}) get defaultRehireTerm {
    var term = RehireRecord.nextTerm(academicYear, academicSemester);
    if (term.semester == 'Summer') {
      term = RehireRecord.nextTerm(term.academicYear, term.semester);
    }
    return term;
  }

  /// Whether decisions for a term should already be in effect, i.e. the
  /// academic year settings have reached that term. While a term change can
  /// still be undone, only terms reached before it count: applying a
  /// decision can't be taken back.
  bool rehireTermHasStarted(String termYear, String termSemester) {
    final target = RehireRecord.termOrder(termYear, termSemester);
    var current = RehireRecord.termOrder(academicYear, academicSemester);
    final previous = _previousAcademicTerm;
    if (canUndoTermChange && previous != null && current != null) {
      final before = RehireRecord.termOrder(
        previous['academicYear']?.toString() ?? '',
        previous['semester']?.toString() ?? '',
      );
      if (before != null && before < current) current = before;
    }
    // A term that can't be placed on the calendar shouldn't hold the
    // decision back forever.
    if (target == null || current == null) return true;
    return target <= current;
  }

  /// [user]'s most recent submitted performance evaluation — the one whose
  /// "Eligible for Rehire" mark the rehire decision follows up on.
  Evaluation? latestEvaluationForUser(User user) {
    final ids = {user.id, for (final s in _studentRecordsForUser(user)) s.id};
    final name = user.name.trim().toLowerCase();
    final matches = evaluations
        .where(
          (e) =>
              e.status == 'Submitted' &&
              (ids.contains(e.studentId) ||
                  e.studentName.trim().toLowerCase() == name),
        )
        .toList();
    matches.sort((a, b) {
      final byYear = (b.academicYear ?? '').compareTo(a.academicYear ?? '');
      if (byYear != 0) return byYear;
      final byTerm = (AppState._evaluationTermOrder[b.term] ?? -1).compareTo(
        AppState._evaluationTermOrder[a.term] ?? -1,
      );
      if (byTerm != 0) return byTerm;
      return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
    });
    return matches.firstOrNull;
  }

  RehireRecord? rehireRecordFor(
    String userId,
    String termYear,
    String termSemester,
  ) => rehireRecords
      .where(
        (r) =>
            r.studentId == userId &&
            r.academicYear == termYear &&
            r.semester == termSemester,
      )
      .firstOrNull;

  /// Everyone the Head decides on for a term: all current Student
  /// Assistants, plus anyone already decided on for that term — a student
  /// who wasn't rehired is a Student again, but their decision should stay
  /// visible and reversible.
  List<User> rehireCandidates(String termYear, String termSemester) {
    final decided = rehireRecords
        .where((r) => r.academicYear == termYear && r.semester == termSemester)
        .map((r) => r.studentId)
        .toSet();
    return users
        .where(
          (u) =>
              u.status != 'Archived' &&
              (u.role == 'Student Assistant' || decided.contains(u.id)),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Records the Head's rehire decision for [user] for the given term and
  /// notifies the student and their office supervisors. A rehire also gets
  /// the new term's Contract of Appointment, filed in Student Documents.
  ///
  /// The roster change itself (office, role, students record) waits until
  /// the term starts — see [_applyRehireRecord] — unless it already has.
  /// Returns an error message, or null on success.
  Future<String?> decideRehire({
    required User user,
    required String termYear,
    required String termSemester,
    required bool rehire,
    String? officeId,
    String remarks = '',
  }) async {
    Office? office;
    if (rehire) {
      office = offices.where((o) => o.id == officeId).firstOrNull;
      if (office == null) return 'Choose the office they will be rehired to.';
      if (!office.assistantIds.contains(user.id) &&
          office.capacity > 0 &&
          office.assistantIds.length >= office.capacity) {
        return '${office.name} is already at its capacity of '
            '${office.capacity}.';
      }
    }

    final currentOffices = officesForUser(user);
    final previous = rehireRecordFor(user.id, termYear, termSemester);
    final List<String> officeIds;
    final List<String> officeNames;
    if (office != null) {
      officeIds = [office.id];
      officeNames = [office.name];
    } else if (currentOffices.isNotEmpty) {
      officeIds = currentOffices.map((o) => o.id).toList();
      officeNames = currentOffices.map((o) => o.name).toList();
    } else {
      // Already taken off their office by an earlier decision for this
      // term; keep recording where they were.
      officeIds = previous?.officeIds ?? const [];
      officeNames = previous?.officeNames ?? const [];
    }

    final evaluation = latestEvaluationForUser(user);
    var record = RehireRecord(
      id: RehireRecord.idFor(user.id, termYear, termSemester),
      studentId: user.id,
      studentName: user.name,
      saId: user.saId,
      academicYear: termYear,
      semester: termSemester,
      decision: rehire ? RehireRecord.rehired : RehireRecord.notRehired,
      officeIds: officeIds,
      officeNames: officeNames,
      evaluationId: evaluation?.id,
      evaluationTerm: evaluation?.term,
      evaluationAcademicYear: evaluation?.academicYear,
      evaluationOverallRating: evaluation?.overallRating,
      eligibleForRehire: evaluation?.eligibleForRehire,
      remarks: remarks.trim(),
      decidedById: currentUser?.id ?? '',
      decidedByName: currentUser?.name ?? '',
      decidedAt: DateTime.now().toIso8601String(),
    );

    try {
      _firestoreService ??= FirestoreService();
      // A changed decision shouldn't leave the old contract behind in
      // Student Documents.
      final oldContractId = previous?.contractDocumentId;
      if (oldContractId != null && oldContractId.isNotEmpty) {
        await _firestoreService!.deleteDocument(oldContractId);
        documents = documents.where((d) => d.id != oldContractId).toList();
      }
      if (office != null) {
        try {
          record = await _attachRehireContract(record, user, office);
        } catch (error) {
          // The decision still stands; the Rehiring screen offers to
          // generate the contract again.
          debugPrint('Failed to generate rehire contract: $error');
        }
      }
      await _firestoreService!.setRehireRecord(record);
      rehireRecords = [
        record,
        ...rehireRecords.where((r) => r.id != record.id),
      ];
      if (rehireTermHasStarted(termYear, termSemester)) {
        await _applyRehireRecord(record);
      }
    } catch (error) {
      debugPrint('Failed to save rehire decision: $error');
      _notify();
      return 'Could not save the decision: $error';
    }

    final officeLabel = officeNames.isEmpty
        ? ''
        : ' in ${officeNames.join(', ')}';
    _addNotification(
      AppNotification(
        id: 'n_${DateTime.now().microsecondsSinceEpoch}_rehire_${user.id}',
        userId: user.id,
        title: rehire
            ? 'Rehired as Student Assistant'
            : 'Student Assistantship Not Renewed',
        message: rehire
            ? 'You have been rehired as a Student Assistant for '
                  '${record.termLabel}$officeLabel.'
                  '${record.hasContract ? ' Your new Contract of Appointment has been prepared.' : ''}'
            : 'Your Student Assistant appointment will not be renewed for '
                  '${record.termLabel}.'
                  '${record.remarks.isNotEmpty ? ' Remarks: ${record.remarks}' : ''}',
        type: 'rehire',
        createdAt: _formattedToday(),
      ),
    );
    _notifyOfficeUsers(
      {...currentOffices.expand((o) => o.headIds), ...?office?.headIds},
      title: rehire
          ? 'Student Assistant Rehired'
          : 'Student Assistant Not Rehired',
      message: rehire
          ? '${user.name} was rehired for ${record.termLabel}$officeLabel.'
          : '${user.name} will not be rehired for ${record.termLabel}.',
    );
    _notify();
    return null;
  }

  /// Puts a pending decision into effect now, without waiting for its term
  /// to start. Returns an error message, or null on success.
  Future<String?> applyRehireDecisionNow(RehireRecord record) async {
    try {
      await _applyRehireRecord(record);
      _notify();
      return null;
    } catch (error) {
      debugPrint('Failed to apply rehire decision: $error');
      return 'Could not apply the decision: $error';
    }
  }

  /// Retries the Contract of Appointment for a rehire whose contract
  /// couldn't be generated when the decision was made.
  Future<String?> generateRehireContract(RehireRecord record) async {
    final user = users.where((u) => u.id == record.studentId).firstOrNull;
    final office = offices
        .where((o) => o.id == record.officeIds.firstOrNull)
        .firstOrNull;
    if (user == null || office == null) {
      return 'The student or their office could not be found.';
    }
    try {
      final updated = await _attachRehireContract(record, user, office);
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setRehireRecord(updated);
      rehireRecords = rehireRecords
          .map((r) => r.id == updated.id ? updated : r)
          .toList();
      _notify();
      return null;
    } catch (error) {
      debugPrint('Failed to generate rehire contract: $error');
      return 'Could not generate the contract: $error';
    }
  }

  /// Generates the Contract of Appointment for a rehired student's new
  /// term, uploads it, and files it under the student so it shows up in
  /// Student Documents.
  Future<RehireRecord> _attachRehireContract(
    RehireRecord record,
    User user,
    Office office,
  ) async {
    final today = DateTime.now();
    final termStart = RehireRecord.termStart(
      record.academicYear,
      record.semester,
    );
    final startDate = termStart == null || termStart.isBefore(today)
        ? today
        : termStart;
    final raw = await const AppointmentDocumentService()
        .generateContractOfAppointment(
          application: Application(
            id: record.id,
            announcementId: '',
            announcementTitle: 'Rehire - ${record.termLabel}',
            applicantId: user.id,
            applicantName: user.name,
            appliedAt: record.decidedAt,
            status: 'Approved',
          ),
          applicant: user,
          officeName: office.name,
          supervisorName: office.headNames.isNotEmpty
              ? office.headNames.join(', ')
              : 'Office Supervisor',
          supervisorRole: 'Supervisor',
          startDate: AppointmentDocumentService.formatDate(startDate),
          endDate: 'End of ${record.termLabel}',
        );
    final bytes = raw.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('The contract document came out empty.');
    }

    // Same 'reports/<uploaderUid>/<timestamp>/<file>' shape the Head's other
    // uploads use, which the upload-document function accepts.
    final uploaderUid =
        fb_auth.FirebaseAuth.instance.currentUser?.uid ??
        currentUser?.id ??
        'user';
    final storagePath =
        'reports/$uploaderUid/${today.millisecondsSinceEpoch}/${raw.fileName}';
    final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
      bytes: bytes,
      path: storagePath,
      contentType: SupabaseStorageService.contentTypeForExtension('docx'),
    );

    final document = Document(
      id: '${record.id}_contract',
      name: 'Contract of Appointment (${record.termLabel})',
      fileName: raw.fileName,
      uploadedBy: currentUser?.name ?? '',
      uploadedAt: today.toIso8601String(),
      documentType: 'Contract',
      description: 'Contract of Appointment for ${record.termLabel} (rehire)',
      filePath: storagePath,
      fileSize: raw.fileSize,
      downloadUrl: downloadUrl,
      studentId: user.id,
      studentName: user.name,
    );
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setDocument(document);
    documents = [document, ...documents.where((d) => d.id != document.id)];

    return record.copyWith(
      contractDocumentId: document.id,
      contractFileName: raw.fileName,
      contractStoragePath: storagePath,
      contractDownloadUrl: downloadUrl,
    );
  }

  /// Puts a rehire decision into effect on the roster. Safe to run more
  /// than once: it only moves the student into the state the decision asks
  /// for.
  /// - Rehired: a Student Assistant (again, if they'd been let go) in the
  ///   decision's office, with their students record active and an SA ID.
  /// - Not Rehired: off every office, students record archived, and back to
  ///   the Student role — so they can apply again later. Their SA ID and
  ///   history are kept.
  Future<void> _applyRehireRecord(RehireRecord record) async {
    final user = users.where((u) => u.id == record.studentId).firstOrNull;
    if (user != null) {
      if (record.isRehired) {
        if (user.role == 'Student') {
          await changeUserRole(user.id, 'Student Assistant', notify: false);
        } else {
          await _setStudentRecordsStatus(user, 'Active');
        }
        final officeId = record.officeIds.firstOrNull;
        if (officeId != null) await _setAssistantOffice(user, officeId);
        await ensureStudentAssistantId(user.id);
      } else {
        await _setAssistantOffice(user, null);
        await _setStudentRecordsStatus(user, 'Archived');
        if (user.role == 'Student Assistant') {
          await changeUserRole(user.id, 'Student', notify: false);
        }
      }
    }

    final applied = record.copyWith(
      applied: true,
      appliedAt: DateTime.now().toIso8601String(),
    );
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setRehireRecord(applied);
    rehireRecords = rehireRecords
        .map((r) => r.id == applied.id ? applied : r)
        .toList();
  }

  /// Applies every recorded rehire decision whose term has now started.
  Future<void> _applyDueRehireDecisions() async {
    final due = rehireRecords
        .where(
          (r) => !r.applied && rehireTermHasStarted(r.academicYear, r.semester),
        )
        .toList();
    for (final record in due) {
      try {
        await _applyRehireRecord(record);
      } catch (error) {
        debugPrint('Failed to apply rehire decision ${record.id}: $error');
      }
    }
  }

  /// Makes [officeId] the only office [user] is a student assistant in (the
  /// same one-office rule as [assignStudentAssistantsToOffice]); a null
  /// [officeId] takes them off every office.
  Future<void> _setAssistantOffice(User user, String? officeId) async {
    // Matched by id (see Office.hasAssistant): matching by name would also
    // move or remove another student who happens to share it.
    for (final office in offices.toList()) {
      final isMember = office.hasAssistant(user.id, user.name);
      if (office.id == officeId) {
        if (isMember) continue;
        await saveOffice(
          office.copyWith(
            assistantIds: [...office.assistantIds, user.id],
            assistantNames: [...office.assistantNames, user.name],
          ),
        );
      } else if (isMember) {
        await saveOffice(office.withoutAssistant(user.id, user.name));
      }
    }
  }

  AttendanceRecord? get activeAttendanceRecord {
    try {
      return filteredAttendance.firstWhere(
        (r) => !r.isArchived && !r.isInvalid && r.isActive,
      );
    } catch (_) {
      return null;
    }
  }

  /// When the current user's open session started, or null when they
  /// aren't clocked in or its time can't be read.
  DateTime? get activeDutyStart {
    final record = activeAttendanceRecord;
    if (record == null) return null;
    final day = _parseFormattedDate(record.date);
    if (day == null) return null;
    return _parseTime(record.timeIn, day);
  }

  /// Hours credited to the current user from finished sessions in the
  /// current Monday–Sunday week: the figure clock-attendance checks
  /// against [AppState.weeklyHourCap].
  double get myCreditedHoursThisWeek {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    return filteredAttendance
        .where((r) {
          if (r.isActive || r.isArchived || r.isInvalid) return false;
          final day = _parseFormattedDate(r.date);
          return day != null &&
              !day.isBefore(monday) &&
              day.isBefore(nextMonday);
        })
        .fold<double>(0, (total, r) => total + (r.totalHours ?? 0));
  }

  /// Hours credited to the current user from sessions finished today.
  double get myCreditedHoursToday {
    final today = _formattedToday();
    return filteredAttendance
        .where(
          (r) =>
              r.date == today && !r.isActive && !r.isArchived && !r.isInvalid,
        )
        .fold<double>(0, (total, r) => total + (r.totalHours ?? 0));
  }

  /// Whether one of the current user's sessions today was voided because
  /// they didn't time out before it ended.
  bool get myMissedTimeOutToday {
    final today = _formattedToday();
    return filteredAttendance.any(
      (r) => r.date == today && r.isInvalid && !r.isArchived,
    );
  }
}
