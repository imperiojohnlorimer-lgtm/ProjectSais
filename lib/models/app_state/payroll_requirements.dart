part of '../app_state.dart';

  // ─── Payroll requirements (Head) ───────────────────────
  // The Head checks each Student Assistant's requirements; the Admin's
  // payroll waits until every one is checked (see buildPayrollPreview).
extension AppStatePayrollRequirements on AppState {
  /// Applies a saved change to the local copy, ahead of the live feed.
  void _setLocalPayrollCheck(
    String studentId,
    String studentName, {
    Map<String, PayrollCheckMark?> items = const {},
    Map<String, PayrollExclusion?> exclusions = const {},
  }) {
    final old = payrollChecks
        .where((c) => c.studentId == studentId)
        .firstOrNull;
    final newItems = {...?old?.items};
    items.forEach(
      (key, mark) => mark == null ? newItems.remove(key) : newItems[key] = mark,
    );
    final newExclusions = {...?old?.exclusions};
    exclusions.forEach(
      (term, exclusion) => exclusion == null
          ? newExclusions.remove(term)
          : newExclusions[term] = exclusion,
    );
    final updated = PayrollCheck(
      studentId: studentId,
      studentName: studentName,
      items: newItems,
      exclusions: newExclusions,
    );
    payrollChecks = [
      ...payrollChecks.where((c) => c.studentId != studentId),
      updated,
    ];
  }

  Future<void> _savePayrollMark(
    PayrollRecord row,
    String key,
    PayrollCheckMark? mark,
  ) async {
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setPayrollCheckItem(
      studentId: row.studentId,
      studentName: row.studentName,
      key: key,
      mark: mark,
    );
    _setLocalPayrollCheck(row.studentId, row.studentName, items: {key: mark});
    _notify();
  }

  PayrollCheckMark _payrollMark(
    String status,
    PayrollRequirement requirement, {
    String? note,
  }) => PayrollCheckMark(
    status: status,
    note: note,
    by: currentUser?.name ?? 'Head',
    byId: currentUser?.id,
    at: DateTime.now().toIso8601String(),
    fileRef: requirement.ref,
  );

  /// The supervisors of [studentId]'s office, who send their DTRs.
  Set<String> _payrollSupervisorIds(String studentId) {
    final user = users.where((u) => u.id == studentId).firstOrNull;
    if (user == null) return {};
    return {
      for (final office in officesForUser(user))
        for (final id in office.headIds)
          if (id.isNotEmpty) id,
    };
  }

  void _notifyPayroll(String userId, String title, String message) =>
      _addNotification(
        AppNotification(
          id: '',
          userId: userId,
          title: title,
          message: message,
          type: 'payroll_requirement',
          createdAt: _formattedToday(),
        ),
      );

  /// Head: [requirement] of [row]'s student is in order.
  Future<void> checkPayrollRequirement(
    PayrollRecord row,
    PayrollRequirement requirement,
  ) => _savePayrollMark(
    row,
    requirement.key,
    _payrollMark(PayrollCheckMark.checked, requirement),
  );

  /// Head: undoes a check or a return; [requirement] waits again.
  Future<void> clearPayrollRequirement(
    PayrollRecord row,
    PayrollRequirement requirement,
  ) => _savePayrollMark(row, requirement.key, null);

  /// Head: sends [requirement] back with [note] — only this one, the rest
  /// stay checked. The student and their office's supervisors are told
  /// what to correct; for a DTR, so is the supervisor who sent it.
  Future<void> returnPayrollRequirement(
    PayrollRecord row,
    PayrollRequirement requirement,
    String note,
  ) async {
    final reason = note.trim();
    await _savePayrollMark(
      row,
      requirement.key,
      _payrollMark(PayrollCheckMark.returned, requirement, note: reason),
    );

    final isDtr = requirement.kind == PayrollRequirementKind.dtr;
    final supervisors = _payrollSupervisorIds(row.studentId);
    if (isDtr) {
      final sender = headForwards
          .where((f) => f.id == requirement.ref)
          .firstOrNull
          ?.sentById;
      if (sender != null && sender.isNotEmpty) supervisors.add(sender);
    }
    _notifyPayroll(
      row.studentId,
      'Payroll Requirement Returned',
      'The Head returned your ${requirement.label} for the '
          '${row.periodLabel} payroll: "$reason". '
          '${isDtr ? 'Please check it with your supervisor.' : 'Please give the Head a corrected copy.'}',
    );
    for (final supervisorId in supervisors) {
      _notifyPayroll(
        supervisorId,
        'Payroll Requirement Returned',
        'The Head returned ${row.studentName}\'s ${requirement.label}: '
            '"$reason".'
            '${isDtr ? ' Please correct it and send it to the Head again.' : ''}',
      );
    }
    _notify();
  }

  /// Head: leaves [row]'s student out of their term's payroll, which then
  /// no longer waits for them. They aren't paid in it.
  Future<void> excludeFromPayroll(PayrollRecord row, String reason) async {
    final exclusion = PayrollExclusion(
      reason: reason.trim(),
      by: currentUser?.name ?? 'Head',
      byId: currentUser?.id,
      at: DateTime.now().toIso8601String(),
    );
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setPayrollExclusion(
      studentId: row.studentId,
      studentName: row.studentName,
      termLabel: row.periodLabel,
      exclusion: exclusion,
    );
    _setLocalPayrollCheck(
      row.studentId,
      row.studentName,
      exclusions: {row.periodLabel: exclusion},
    );
    _notifyPayroll(
      row.studentId,
      'Left Out of Payroll',
      'The Head left you out of the ${row.periodLabel} payroll: '
          '"${exclusion.reason}".',
    );
    _notify();
  }

  /// Head: puts [row]'s student back in their term's payroll.
  Future<void> includeInPayroll(PayrollRecord row) async {
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setPayrollExclusion(
      studentId: row.studentId,
      studentName: row.studentName,
      termLabel: row.periodLabel,
      exclusion: null,
    );
    _setLocalPayrollCheck(
      row.studentId,
      row.studentName,
      exclusions: {row.periodLabel: null},
    );
    _notifyPayroll(
      row.studentId,
      'Back in the Payroll',
      'The Head put you back in the ${row.periodLabel} payroll.',
    );
    _notify();
  }

  /// Head: tells each student in [rows] still holding up the payroll, and
  /// their office's supervisors, what's needed from them — requirements
  /// not on file yet, or returned. Ones only waiting for the Head's own
  /// check aren't mentioned. Returns how many students were reminded.
  int remindPayrollRequirements(List<PayrollRecord> rows) {
    var reminded = 0;
    for (final row in rows) {
      if (row.status != 'Incomplete') continue;
      final needed = row.requirements.where((r) => r.needsAction).toList();
      if (needed.isEmpty) continue;
      final list = needed.map((r) => r.label).join(', ');
      _notifyPayroll(
        row.studentId,
        'Payroll Requirements Needed',
        'Still needed for the ${row.periodLabel} payroll: $list.',
      );
      for (final supervisorId in _payrollSupervisorIds(row.studentId)) {
        _notifyPayroll(
          supervisorId,
          'Payroll Requirements Needed',
          'Still needed from ${row.studentName} for the ${row.periodLabel} '
              'payroll: $list.',
        );
      }
      reminded++;
    }
    _notify();
    return reminded;
  }

  /// This student's saved weekly class schedule rows (used to auto-fill
  /// the DTR/Accomplishment Report's "Class Schedule" grid), scoped the
  /// same way as [filteredStudents] so a supervisor only sees their own
  /// office's data.
  List<ClassScheduleEntry> classScheduleForStudent(String studentName) {
    final officeNames = role == 'Supervisor'
        ? _officeStudentNamesForSupervisor.toSet()
        : null;
    return classSchedules
        .where(
          (c) =>
              c.studentName == studentName &&
              (officeNames == null || officeNames.contains(c.studentName)),
        )
        .toList();
  }

  /// Replaces this student's saved weekly class schedule with [rows] —
  /// called when a supervisor edits and generates a DTR/Accomplishment
  /// Report, so the schedule is remembered for next time instead of having
  /// to be re-typed every month. Persists to Firestore when available,
  /// falling back to an in-memory update if the backend call fails.
  Future<void> saveClassScheduleForStudent(
    String studentId,
    String studentName,
    List<ClassScheduleEntry> rows,
  ) async {
    _firestoreService ??= FirestoreService();
    try {
      await _firestoreService!.deleteClassScheduleEntriesForStudent(
        studentName,
      );
      final saved = <ClassScheduleEntry>[];
      for (final row in rows) {
        saved.add(await _firestoreService!.addClassScheduleEntry(row));
      }
      classSchedules = [
        ...classSchedules.where((c) => c.studentName != studentName),
        ...saved,
      ];
    } catch (_) {
      // Firestore not available — fall back to an in-memory update so the
      // grid still stays pre-filled for the rest of this session.
      classSchedules = [
        ...classSchedules.where((c) => c.studentName != studentName),
        ...rows,
      ];
    }
    _notify();
  }

  /// The most recent evaluation already on file for a student + term
  /// (so a supervisor can see/edit what was already submitted).
  Evaluation? existingEvaluationFor(String studentName, String term) {
    final matches = filteredEvaluations
        .where((e) => e.studentName == studentName && e.term == term)
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return matches.first;
  }

  /// Create or update a performance evaluation.
  Future<bool> saveEvaluation(Evaluation evaluation) async {
    _firestoreService ??= FirestoreService();
    final nowIso = DateTime.now().toIso8601String();
    try {
      Evaluation savedEvaluation;
      if (evaluation.id.isEmpty) {
        // New evaluation: stamp createdAt/academicYear, then persist.
        final withCreated = Evaluation(
          id: '',
          studentId: evaluation.studentId,
          studentName: evaluation.studentName,
          office: evaluation.office,
          term: evaluation.term,
          periodCovered: evaluation.periodCovered,
          dateOfRating: evaluation.dateOfRating,
          eligibleForRehire: evaluation.eligibleForRehire,
          ratings: evaluation.ratings,
          overallRating: evaluation.overallRating,
          departmentHeadComments: evaluation.departmentHeadComments,
          supervisorId: evaluation.supervisorId,
          supervisorName: evaluation.supervisorName,
          verifiedDtrHours: evaluation.verifiedDtrHours,
          approvedReportCount: evaluation.approvedReportCount,
          status: evaluation.status,
          academicYear: academicYear,
          createdAt: nowIso,
          updatedAt: nowIso,
        );
        await _firestoreService!.setEvaluation(withCreated);
        evaluations = [withCreated, ...evaluations];
        savedEvaluation = withCreated;
      } else {
        final updated = evaluation.copyWith(updatedAt: nowIso);
        await _firestoreService!.setEvaluation(updated);
        evaluations = evaluations
            .map((e) => e.id == updated.id ? updated : e)
            .toList();
        savedEvaluation = updated;
      }

      // Notify the student assistant that their evaluation result is ready.
      if (savedEvaluation.status == 'Submitted') {
        String? recipientUserId;
        try {
          final student = students.firstWhere(
            (s) => s.id == savedEvaluation.studentId,
          );
          recipientUserId = student.userId;
        } catch (_) {
          recipientUserId = null;
        }
        // Fall back to matching by name if the student record lookup
        // didn't resolve a linked user account.
        if (recipientUserId == null || recipientUserId.isEmpty) {
          try {
            final matchedUser = users.firstWhere(
              (u) =>
                  u.role == 'Student Assistant' &&
                  u.name == savedEvaluation.studentName,
            );
            recipientUserId = matchedUser.id;
          } catch (_) {
            recipientUserId = null;
          }
        }

        if (recipientUserId != null && recipientUserId.isNotEmpty) {
          final band = EvaluationCriteria.bandLabel(
            savedEvaluation.overallRating,
          );
          _addNotification(
            AppNotification(
              id: 'n_${DateTime.now().millisecondsSinceEpoch}_$recipientUserId',
              userId: recipientUserId,
              title: 'Performance Evaluation Available',
              message:
                  'Your performance evaluation for ${savedEvaluation.term} '
                  '(${savedEvaluation.periodCovered}) is ready. Overall '
                  'rating: ${savedEvaluation.overallRating} — $band.',
              type: 'evaluation',
              createdAt: _formattedToday(),
            ),
          );
        }
      }

      _notify();
      return true;
    } catch (e) {
      debugPrint('Failed to save evaluation in Firestore: $e');
      return false;
    }
  }
}
