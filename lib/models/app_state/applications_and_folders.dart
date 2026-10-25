part of '../app_state.dart';

  // ─── Document Folders (Head file manager) ─────────────
extension AppStateApplicationsAndFolders on AppState {
  /// Newest first, so a folder just made shows up at the front.
  List<DocumentFolder> _sortedFolders(Iterable<DocumentFolder> list) =>
      list.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> createDocumentFolder(String name) async {
    if (name.trim().isEmpty) return;
    _firestoreService ??= FirestoreService();
    final folder = DocumentFolder(
      id: '',
      name: name.trim(),
      createdBy: currentUser?.name ?? '',
      createdAt: DateTime.now().toIso8601String(),
    );
    final id = await _firestoreService!.addDocumentFolder(folder);
    documentFolders = AppState._withAdded(
      documentFolders,
      DocumentFolder(
        id: id,
        name: folder.name,
        createdBy: folder.createdBy,
        createdAt: folder.createdAt,
      ),
      (f) => f.id,
    );
    _notify();
  }

  Future<void> deleteDocumentFolder(String folderId) async {
    _firestoreService ??= FirestoreService();
    final docsInFolder = documents
        .where((d) => d.folderId == folderId)
        .toList();
    for (final doc in docsInFolder) {
      await _firestoreService!.deleteDocument(doc.id);
    }
    await _firestoreService!.deleteDocumentFolder(folderId);
    documents = documents.where((d) => d.folderId != folderId).toList();
    documentFolders = documentFolders.where((f) => f.id != folderId).toList();
    _notify();
  }

  /// Uploads a document either into a folder ([folderId]) or directly onto
  /// a student's own document list ([studentId]/[studentName]).
  Future<void> uploadManualDocument({
    String? folderId,
    String? studentId,
    String? studentName,
    required String fileName,
    required String storagePath,
    required String downloadUrl,
    double? fileSize,
  }) async {
    _firestoreService ??= FirestoreService();
    final doc = Document(
      id: '',
      name: fileName,
      fileName: fileName,
      uploadedBy: currentUser?.name ?? '',
      uploadedAt: DateTime.now().toIso8601String(),
      documentType: 'Other',
      filePath: storagePath,
      downloadUrl: downloadUrl,
      fileSize: fileSize,
      folderId: folderId,
      studentId: studentId,
      studentName: studentName,
    );
    await _firestoreService!.setDocument(doc);
    documents = await _firestoreService!.getAllDocuments();
    _notify();
  }

  Future<void> deleteManualDocument(String documentId) async {
    _firestoreService ??= FirestoreService();
    await _firestoreService!.deleteDocument(documentId);
    documents = documents.where((d) => d.id != documentId).toList();
    _notify();
  }

  /// The Head's newest hiring call this academic year, through which
  /// students apply to be a Student Assistant; null before there's one.
  /// Announcements arrive newest first. Closing it closes applications: an
  /// older call doesn't take over, with requirements that may be stale.
  Announcement? get currentHiringCall => announcements
      .where(
        (a) =>
            a.isHiringCall &&
            a.isApproved &&
            (a.academicYear == null || a.academicYear == academicYear),
      )
      .firstOrNull;

  /// Whether students can apply through [call] today.
  bool hiringCallTakesApplications(Announcement? call) =>
      call != null &&
      call.isOpen &&
      !call.isPastDeadline() &&
      allowAcademicApplications;

  /// What students see besides the hiring call: the Head's open
  /// announcements that take no applications, to read only.
  List<Announcement> get studentNotices =>
      studentVisibleAnnouncements.where((a) => !a.acceptsApplications).toList();

  /// The signed-in student's application this academic year, if any: the
  /// one general application, else the newest from before (when students
  /// applied to each posting).
  Application? get myCurrentApplication {
    final mine = myApplications;
    final user = currentUser;
    if (user == null || mine.isEmpty) return null;
    final generalId = Application.idFor(user.id, academicYear);
    final general = mine.where((a) => a.id == generalId).firstOrNull;
    if (general != null) return general;
    // Older ones are ordered by their "Oct 2, 2026" dates as text, so find
    // the newest by date.
    return mine.reduce(
      (a, b) => _anyDate(b.appliedAt).isAfter(_anyDate(a.appliedAt)) ? b : a,
    );
  }

  /// Applications as the Head works through them: all of them, less a
  /// rejected one its applicant has since replaced with a newer one that
  /// year. (Applying again replaces a rejected application in place; only
  /// one from before, made to an office's posting under its own id, would
  /// otherwise be listed beside the new one.)
  List<Application> get currentApplications {
    DateTime when(Application a) => _anyDate(a.appliedAt);
    bool replaced(Application a) =>
        a.status == Application.rejected &&
        applications.any(
          (b) =>
              b.id != a.id &&
              b.status != Application.rejected &&
              b.applicantId == a.applicantId &&
              b.academicYear == a.academicYear &&
              !when(b).isBefore(when(a)),
        );
    return applications.where((a) => !replaced(a)).toList();
  }

  /// Saves a student's application to be a Student Assistant, made through
  /// [currentHiringCall]. Refused for a Student Assistant, while the Admin
  /// has applications closed (the Firestore rules refuse that too), once
  /// the call is closed, replaced or past its deadline (the form may have
  /// been open since), and when they already applied this year — unless
  /// the Head rejected that application (a wrong document, say): then this
  /// one takes its place, under the same id.
  Future<bool> submitApplication(Application app) async {
    // A second tap while the first is saving would tell the Heads twice.
    if (_submittingApplication) return false;
    _submittingApplication = true;
    try {
      return await _submitApplication(app);
    } finally {
      _submittingApplication = false;
    }
  }

  Future<bool> _submitApplication(Application app) async {
    final call = currentHiringCall;
    final previous = myCurrentApplication;
    if (currentUser?.role == 'Student Assistant' ||
        call == null ||
        call.id != app.announcementId ||
        !hiringCallTakesApplications(call) ||
        (previous != null && previous.status != Application.rejected)) {
      return false;
    }
    _firestoreService ??= FirestoreService();
    app = app.copyWith(academicYear: app.academicYear ?? academicYear);
    try {
      await _firestoreService!.setApplication(app);
    } catch (error) {
      debugPrint('Failed to submit application to Firestore: $error');
      return false;
    }

    applications = [app, ...applications.where((a) => a.id != app.id)];
    final again = previous == null ? '' : ' again';
    // Notify the Heads
    for (final headId in await _headIds()) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_$headId',
          userId: headId,
          title: 'New Application',
          message: '${app.applicantName} applied$again ${AppState._appliedFor(app)}.',
          type: 'application',
          createdAt: _formattedToday(),
        ),
      );
    }
    // Notify the applicant
    _addNotification(
      AppNotification(
        id: 'n_${DateTime.now().millisecondsSinceEpoch}_${app.applicantId}',
        userId: app.applicantId,
        title: 'Application Submitted',
        message: 'Your application ${AppState._appliedFor(app)} has been submitted.',
        type: 'application',
        createdAt: _formattedToday(),
      ),
    );
    _notify();
    return true;
  }

  /// What the applicant is told when their application moves to [status],
  /// or null for a move they aren't told about (back to Pending).
  AppNotification? _applicationNotice(Application app, String? remarks) {
    final note = remarks == null || remarks.isEmpty ? '' : ' Remarks: $remarks';
    final (title, message) = switch (app.status) {
      Application.forScreening => (
        'Selected for Screening',
        'Your application ${AppState._appliedFor(app)} was selected for screening. '
            'The Head of Student Assistantship will set your interview.',
      ),
      Application.approved || 'Accepted' => (
        'Application Approved',
        'Your application ${AppState._appliedFor(app)} was approved. You are now a '
            'Student Assistant; the Head will place you in an office.$note',
      ),
      Application.waitlisted => (
        'Application Waitlisted',
        'Your application ${AppState._appliedFor(app)} was placed on the waitlist. '
            'The Head may still approve it later.$note',
      ),
      Application.rejected => (
        'Application Rejected',
        'Your application ${AppState._appliedFor(app)} was not accepted.$note You '
            'can fix it and apply again from the Apply page.',
      ),
      _ => ('', ''),
    };
    if (title.isEmpty) return null;
    return AppNotification(
      id: 'n_${DateTime.now().millisecondsSinceEpoch}_${app.applicantId}',
      userId: app.applicantId,
      title: title,
      message: message,
      type: 'application',
      createdAt: _formattedToday(),
    );
  }

  /// Picks the Pending applications [ids] for screening, one save each.
  /// Returns how many were saved.
  Future<int> sendToScreening(Iterable<String> ids) async {
    var saved = 0;
    for (final id in ids.toSet()) {
      final app = applications.where((a) => a.id == id).firstOrNull;
      if (app == null || app.status != Application.pending) continue;
      try {
        await updateApplicationStatus(id, Application.forScreening);
        saved++;
      } catch (error) {
        debugPrint('Failed to send $id to screening: $error');
      }
    }
    return saved;
  }

  /// Saves [id] as [status] and tells the applicant. The save comes first,
  /// and a failed one throws, so nobody is told of a decision that didn't
  /// stick.
  ///
  /// Approving makes the applicant a Student Assistant with an SA ID and
  /// no office: the Head places them in one later, matching their skills.
  /// Their Contract of Appointment and Endorsement Letter name the office,
  /// so they're only made here for someone already in one; otherwise the
  /// Head makes them from Applications after the placement.
  Future<void> updateApplicationStatus(
    String id,
    String status, {
    String? remarks,
  }) async {
    final original = applications.where((a) => a.id == id).firstOrNull;
    if (original == null) return;
    final updatedApplication = original.copyWith(
      status: status,
      remarks: remarks,
    );
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setApplication(updatedApplication);
    // By id: the live list may have changed while it saved.
    applications = [
      for (final a in applications) a.id == id ? updatedApplication : a,
    ];
    // Saving the same decision again (to finish an approval whose
    // promotion failed part way) tells no one a second time.
    final notice = original.status == status
        ? null
        : _applicationNotice(updatedApplication, remarks);
    if (notice != null) _addNotification(notice);
    // Everything below is safe to run again.
    if (updatedApplication.isApproved) {
      for (final skill in updatedApplication.skills) {
        final normalizedSkill = skill.trim();
        if (normalizedSkill.isEmpty ||
            skills.any(
              (existing) =>
                  existing.toLowerCase() == normalizedSkill.toLowerCase(),
            )) {
          continue;
        }
        try {
          await _firestoreService!.setSkill(normalizedSkill);
          skills = [...skills, normalizedSkill]..sort();
        } catch (error) {
          debugPrint('Failed to add approved application skill: $error');
        }
      }
      final applicantIndex = users.indexWhere(
        (user) => user.id == updatedApplication.applicantId,
      );
      if (applicantIndex >= 0) {
        final applicant = users[applicantIndex];
        // Their skills go on their profile, where offices match them.
        final mergedSkills = {
          ...applicant.skills,
          ...updatedApplication.skills,
        }.toList()..sort();
        final updatedApplicant = applicant.copyWith(skills: mergedSkills);
        // Only the skills: the rest of the profile may have changed since
        // this copy was loaded (an archive, say), and mustn't be undone.
        await _firestoreService!.updateUserFields(applicant.id, {
          'skills': mergedSkills,
        });
        await _upsertUser(updatedApplicant);
        if (currentUser?.id == updatedApplicant.id) {
          currentUser = updatedApplicant;
        }
        // Run again for one already promoted too: it also makes (or brings
        // back) their students record, which a cut-short approval may have
        // missed.
        if (applicant.role == 'Student' ||
            applicant.role == 'Student Assistant') {
          // "Application Approved" already tells them.
          final problem = await changeUserRole(
            updatedApplication.applicantId,
            'Student Assistant',
            notify: false,
          );
          // Saving the decision again finishes the promotion.
          if (problem != null) throw StateError(problem);
        }
        await ensureStudentAssistantId(updatedApplication.applicantId);
        if (original.status != status &&
            officesForUser(updatedApplicant).isNotEmpty) {
          // The approval stands either way; the Head can make them again
          // from Applications.
          try {
            await generateApprovedApplicantDocuments(updatedApplication.id);
          } catch (error) {
            debugPrint('Failed to generate appointment documents: $error');
          }
        }
      }
    }
    _notify();
  }

  /// Assigns a unique, sequential Student Assistant Program ID (e.g.
  /// "SA 001") the first time a user needs one, and returns it. Idempotent —
  /// if the user already has one, it's returned unchanged. This is how
  /// every Student Assistant automatically gets an SA ID, without a Head
  /// having to type one in by hand.
  ///
  /// The number comes from a counter in Firestore, taken in a transaction,
  /// so two Heads approving at the same moment can't be given the same ID.
  /// Only the `saId` field is written.
  Future<String?> ensureStudentAssistantId(String userId) async {
    final existing = users.where((u) => u.id == userId).firstOrNull;
    if (existing == null) return null;
    final held = existing.saId;
    if (held != null && held.trim().isNotEmpty) return held;

    _firestoreService ??= FirestoreService();
    final service = _firestoreService!;
    String newId;
    try {
      newId = await service.allocateSaId(userId);
    } on SaCounterNotSeeded {
      // The first time: number on from the highest ID any profile holds,
      // deleted ones included (their IDs stay taken).
      var highest = 0;
      for (final u in await service.getAllUserProfiles()) {
        final n = saNumber(u.saId);
        if (n != null && n > highest) highest = n;
      }
      newId = await service.allocateSaId(userId, seedMax: highest);
    }

    final current = users.where((u) => u.id == userId).firstOrNull;
    if (current != null) {
      final updated = current.copyWith(saId: newId);
      await _upsertUser(updated);
      if (currentUser?.id == updated.id) currentUser = updated;
    }
    _notify();
    return newId;
  }

  /// The number in an SA ID ("SA 007" -> 7), or null when it isn't one.
  @visibleForTesting
  static int? saNumber(String? saId) {
    final match = RegExp(r'^SA\s*0*(\d+)$').firstMatch(saId?.trim() ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<void> generateApprovedApplicantDocuments(String applicationId) async {
    await _generateApprovedApplicantDocument(
      applicationId,
      includeContract: true,
      includeEndorsement: true,
    );
  }

  /// Generates only the Contract of Appointment for an approved applicant,
  /// leaving any previously generated Endorsement Letter untouched.
  Future<void> generateContractOfAppointmentDocument(
    String applicationId,
  ) async {
    await _generateApprovedApplicantDocument(
      applicationId,
      includeContract: true,
      includeEndorsement: false,
    );
  }

  /// Generates only the Endorsement Letter for an approved applicant,
  /// leaving any previously generated Contract of Appointment untouched.
  Future<void> generateEndorsementLetterDocument(String applicationId) async {
    await _generateApprovedApplicantDocument(
      applicationId,
      includeContract: false,
      includeEndorsement: true,
    );
  }

  Future<void> _generateApprovedApplicantDocument(
    String applicationId, {
    required bool includeContract,
    required bool includeEndorsement,
  }) async {
    final appIndex = applications.indexWhere((a) => a.id == applicationId);
    if (appIndex < 0) return;

    final app = applications[appIndex];
    if (app.status != 'Approved' && app.status != 'Accepted') return;

    final applicant = users.firstWhere(
      (user) => user.id == app.applicantId,
      orElse: () => User(
        id: app.applicantId,
        name: app.applicantName,
        email: '',
        role: 'Student',
      ),
    );

    // Prefer the applicant's actual assigned Office (as shown on their
    // profile / User Profile dialog) over parsing the announcement title —
    // that title-parsing was only ever a fallback and doesn't reflect the
    // applicant's real office assignment.
    final assignedOffices = officesForUser(applicant);
    final officeName = assignedOffices.isNotEmpty
        ? assignedOffices.map((o) => o.name).join(', ')
        : (app.announcementTitle.contains('-')
              ? app.announcementTitle.split('-').last.trim()
              : 'Student Assistant Office');

    // Immediate Supervisor should be the head of the applicant's assigned
    // office, not whichever admin happens to be generating the document.
    final officeHeadNames = assignedOffices.expand((o) => o.headNames).toList();
    final supervisorName = officeHeadNames.isNotEmpty
        ? officeHeadNames.join(', ')
        : (currentUser?.name ?? 'Office Supervisor');
    final supervisorRole = currentUser?.role ?? 'Supervisor';

    ApplicationDocument? contractDocument;
    ApplicationDocument? endorsementDocument;

    if (includeContract) {
      final rawContractDocument = await const AppointmentDocumentService()
          .generateContractOfAppointment(
            application: app,
            applicant: applicant,
            officeName: officeName,
            supervisorName: supervisorName,
            supervisorRole: supervisorRole,
            startDate: AppointmentDocumentService.formatDate(DateTime.now()),
            endDate: 'End of Academic Term',
          );
      contractDocument = await _uploadGeneratedDocument(rawContractDocument);
    }

    if (includeEndorsement) {
      final rawEndorsementDocument = await const AppointmentDocumentService()
          .generateEndorsementLetter(
            application: app,
            applicant: applicant,
            supervisorName: supervisorName,
            officeName: officeName,
            campusName: applicant.campus ?? 'Main Campus',
            studentId: applicant.studentId,
            courseProgram: applicant.courseProgram,
            yearLevel: applicant.yearLevel,
            contactNumber: applicant.phone,
            // "Endorsed By" is whoever (the Head) is generating this document.
            endorsedByName: currentUser?.name,
            endorsedByContact: currentUser?.phone,
            endorsedByEmail: currentUser?.email,
          );
      endorsementDocument = await _uploadGeneratedDocument(
        rawEndorsementDocument,
      );
    }

    // Upload the generated bytes to Supabase Storage instead of embedding
    // them directly in the Firestore document. A ~500KB docx as a raw
    // Firestore int array blows well past Firestore's 1MB document limit
    // and per-field size limits, which is why the write was silently
    // failing to persist the real fileSize/bytes (showing "0.00 MB" after
    // a refresh) and why downloads fell back to a data: URI — which
    // browsers save under the generic name "download" since data: URIs
    // don't carry a real filename/Content-Disposition.
    final filteredDocuments = app.submittedDocuments
        .where(
          (doc) =>
              (includeContract &&
                      doc.requirementName == 'Contract of Appointment') ==
                  false &&
              (includeEndorsement &&
                      doc.requirementName == 'Endorsement Letter') ==
                  false,
        )
        .toList();

    final generatedDocuments = [
      ...filteredDocuments,
      if (contractDocument != null) contractDocument,
      if (endorsementDocument != null) endorsementDocument,
    ];

    final updated = app.copyWith(submittedDocuments: generatedDocuments);
    applications[appIndex] = updated;
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setApplication(updated);
    _notify();
  }

  /// Uploads a freshly-generated document's bytes to Supabase Storage and
  /// returns a copy carrying `storagePath`/`downloadUrl` instead of the raw
  /// bytes, so it's small enough to store in Firestore and downloads with
  /// its real filename via a signed URL. Falls back to keeping the raw
  /// bytes only if the upload itself fails, so document generation never
  /// completely breaks if storage is briefly unavailable.
  Future<ApplicationDocument> _uploadGeneratedDocument(
    ApplicationDocument doc,
  ) async {
    final bytes = doc.bytes;
    if (bytes == null || bytes.isEmpty) return doc;

    try {
      final extension = doc.fileName.contains('.')
          ? doc.fileName.split('.').last
          : 'docx';
      final storagePath =
          'applications/${fb_auth.FirebaseAuth.instance.currentUser?.uid ?? currentUser?.id ?? 'user'}/${doc.applicationId}/${doc.id}/${doc.fileName}';
      final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
        bytes: bytes,
        path: storagePath,
        contentType: SupabaseStorageService.contentTypeForExtension(extension),
      );
      return ApplicationDocument(
        id: doc.id,
        applicationId: doc.applicationId,
        requirementName: doc.requirementName,
        fileName: doc.fileName,
        uploadedAt: doc.uploadedAt,
        description: doc.description,
        fileSize: doc.fileSize,
        bytes: null,
        storagePath: storagePath,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      // Storage upload failed — keep the raw bytes so the document is at
      // least usable this session, even though it won't survive a refresh.
      return doc;
    }
  }

  List<Application> get myApplications => applications
      .where(
        (a) =>
            a.applicantId == currentUser?.id &&
            (a.academicYear == null || a.academicYear == academicYear),
      )
      .toList();

  List<Application> get myArchivedApplications => applications
      .where(
        (a) =>
            a.applicantId == currentUser?.id &&
            a.academicYear != null &&
            a.academicYear != academicYear,
      )
      .toList();

  /// Supervisors' requests for a student assistant that applicants are
  /// matched against: approved, still open, this academic year.
  List<Announcement> get openOfficeRequests => announcements
      .where(
        (a) =>
            a.isSupervisorRequest &&
            a.isApproved &&
            a.isOpen &&
            (a.academicYear == null || a.academicYear == academicYear),
      )
      .toList();

  /// The skills [application]'s applicant brings: those they applied with
  /// and those already on their profile.
  List<String> applicantSkills(Application application) {
    final applicant = users
        .where((u) => u.id == application.applicantId)
        .firstOrNull;
    final seen = <String>{};
    return [
      for (final skill in [...application.skills, ...?applicant?.skills])
        if (skill.trim().isNotEmpty && seen.add(skill.trim().toLowerCase()))
          skill.trim(),
    ];
  }

  /// How [application] matches each of [openOfficeRequests], best first;
  /// requests it matches nothing of are left out.
  List<SkillMatch> skillMatchesFor(Application application) {
    final skills = applicantSkills(application);
    return [
      for (final request in openOfficeRequests)
        if (SkillMatch.of(request, skills) case final match when match.hasMatch)
          match,
    ]..sort((a, b) => b.count.compareTo(a.count));
  }

  List<String> skillsForUser(User user) {
    final names = [...user.skills];
    for (final application in applications) {
      if ((application.applicantId == user.id ||
              application.applicantName.trim().toLowerCase() ==
                  user.name.trim().toLowerCase()) &&
          (application.status == 'Approved' ||
              application.status == 'Accepted')) {
        names.addAll(application.skills);
      }
    }
    // Once per skill, whatever its case, spelled as on the Head's list: a
    // student with "Communication skills" and "Communication Skills" has
    // the one skill.
    return AppState.uniqueSkills([for (final name in names) findSkill(name) ?? name]);
  }

  /// Finds the most relevant completed screening/assessment record for
  /// [user], matched by applicant id first and falling back to name.
  ScreeningRecord? screeningRecordForUser(User user) {
    final matches = screeningRecords
        .where(
          (record) =>
              record.applicantId == user.id ||
              (record.fullName.trim().toLowerCase() ==
                  user.name.trim().toLowerCase()),
        )
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final byYear = (a.academicYear ?? '').compareTo(b.academicYear ?? '');
      if (byYear != 0) return byYear;
      return a.interviewerDate.compareTo(b.interviewerDate);
    });
    return matches.last;
  }

  /// Full screening/assessment history for [user] across all academic
  /// years, most recent first.
  List<ScreeningRecord> screeningHistoryForUser(User user) {
    final matches = screeningRecords
        .where(
          (record) =>
              record.applicantId == user.id ||
              (record.fullName.trim().toLowerCase() ==
                  user.name.trim().toLowerCase()),
        )
        .toList();
    matches.sort((a, b) {
      final byYear = (b.academicYear ?? '').compareTo(a.academicYear ?? '');
      if (byYear != 0) return byYear;
      return b.interviewerDate.compareTo(a.interviewerDate);
    });
    return matches;
  }

  /// Computes a 0-100 recommendation score for assigning [user] to
  /// [office], based on their screening/assessment result (skills &
  /// overall ratings + interviewer recommendation) and how many of their
  /// tagged skills were validated during screening.
  ///
  /// Returns null when the applicant has no screening record yet, so the
  /// UI can show "Not yet assessed" instead of a misleading score.
  /// Returns how many of [office.requiredSkills] are present among
  /// [user]'s skills (profile + approved application), case-insensitively.
  int matchedRequiredSkillsCount(User user, Office office) {
    if (office.requiredSkills.isEmpty) return 0;
    final taggedSkills = skillsForUser(
      user,
    ).map((skill) => skill.trim().toLowerCase()).toSet();
    return office.requiredSkills
        .where((req) => taggedSkills.contains(req.trim().toLowerCase()))
        .length;
  }

  /// 0-100 score of how well [user]'s skills cover [office.requiredSkills].
  /// Returns null when the office has no required skills configured.
  double? requiredSkillMatchScore(User user, Office office) {
    if (office.requiredSkills.isEmpty) return null;
    final matched = matchedRequiredSkillsCount(user, office);
    return matched / office.requiredSkills.length * 100;
  }

  double? recommendationScoreForOffice(User user, Office office) {
    final record = screeningRecordForUser(user);
    final skillScore = requiredSkillMatchScore(user, office);
    if (record == null) return skillScore;

    double averageOf(Map<String, int> ratings) {
      if (ratings.isEmpty) return 0;
      final total = ratings.values.fold<int>(0, (sum, value) => sum + value);
      return total / ratings.length; // ratings are on a 1-5 scale
    }

    final skillsAvg = averageOf(record.skills);
    final overallAvg = averageOf(record.overall);

    // Base score: weighted blend of skill ratings and overall evaluation,
    // scaled to 0-100.
    double score = ((skillsAvg * 0.6) + (overallAvg * 0.4)) / 5 * 100;

    // Adjust for the interviewer's final recommendation.
    switch (record.recommendation) {
      case 'Highly Recommended':
        score += 10;
        break;
      case 'Recommended':
        score += 3;
        break;
      case 'Recommended with Reservations':
        score -= 10;
        break;
      case 'Not Recommended':
        score -= 40;
        break;
    }

    // Small bonus when the skills validated in screening overlap with the
    // skills already tagged on the applicant's profile/application.
    final taggedSkills = skillsForUser(user);
    if (taggedSkills.isNotEmpty && record.skills.isNotEmpty) {
      final matchedCount = record.skills.keys.where((skill) {
        return taggedSkills.any(
          (tagged) => tagged.trim().toLowerCase() == skill.trim().toLowerCase(),
        );
      }).length;
      score += (matchedCount / record.skills.length) * 5;
    }

    // Blend in how well the applicant covers the office's required skills,
    // when the office has any configured. Weighted evenly with the
    // screening-based score so a strong skill match still moves the needle
    // even for a well-screened applicant, and vice versa.
    if (skillScore != null) {
      score = (score * 0.5) + (skillScore * 0.5);
    }

    return score.clamp(0, 100);
  }

  /// Returns [users] sorted best-match-first for [office], using
  /// [recommendationScoreForOffice]. Applicants without an assessment on
  /// file are pushed to the end (alphabetically among themselves).
  List<User> sortByOfficeMatch(List<User> users, Office office) {
    final sorted = [...users];
    sorted.sort((a, b) {
      final scoreA = recommendationScoreForOffice(a, office);
      final scoreB = recommendationScoreForOffice(b, office);
      if (scoreA == null && scoreB == null) return a.name.compareTo(b.name);
      if (scoreA == null) return 1;
      if (scoreB == null) return -1;
      return scoreB.compareTo(scoreA);
    });
    return sorted;
  }
}
