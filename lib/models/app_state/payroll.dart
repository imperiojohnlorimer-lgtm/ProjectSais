part of '../app_state.dart';

  // ─── Payroll ───────────────────────────────────────────
  // Parses the handful of date-string shapes this codebase already writes
  // ("Sep 19, 2026" from attendance, "9/19/2026" from reports) so payroll
  // can filter both by an arbitrary pay period.
extension AppStatePayroll on AppState {
  DateTime? _parsePayrollDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    if (slash != null) {
      try {
        return DateTime(
          int.parse(slash.group(3)!),
          int.parse(slash.group(1)!),
          int.parse(slash.group(2)!),
        );
      } catch (_) {
        return null;
      }
    }

    const abbrMonths = [
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
    const fullMonths = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final named = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})$').firstMatch(s);
    if (named != null) {
      final monthName = named.group(1)!;
      var index = abbrMonths.indexOf(monthName);
      if (index < 0) index = fullMonths.indexOf(monthName);
      if (index < 0) return null;
      try {
        return DateTime(
          int.parse(named.group(3)!),
          index + 1,
          int.parse(named.group(2)!),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _dateWithinRange(String? raw, DateTime start, DateTime endInclusive) {
    final parsed = _parsePayrollDate(raw);
    if (parsed == null) return false;
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
        !day.isAfter(
          DateTime(endInclusive.year, endInclusive.month, endInclusive.day),
        );
  }

  /// Every calendar month touched by [start]..[endInclusive] (both ends
  /// inclusive), so a semester-long pay period can still have the 25–40
  /// hour rule checked and capped one month at a time.
  List<(int month, int year)> _monthsInRange(
    DateTime start,
    DateTime endInclusive,
  ) {
    final months = <(int, int)>[];
    var cursor = DateTime(start.year, start.month);
    final last = DateTime(endInclusive.year, endInclusive.month);
    while (!cursor.isAfter(last)) {
      months.add((cursor.month, cursor.year));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return months;
  }

  /// This student's verified (timed-out, non-archived) attendance hours
  /// within [start]..[endInclusive], broken down by calendar month so each
  /// month's payable hours can be capped at [PayrollRecord.maximumMonthlyHours]
  /// individually before the semester total is summed. Isn't scoped to the
  /// current viewer's role since only an Admin runs payroll.
  /// Who this user's attendance and report rows may be logged under: their
  /// account id plus any linked Student roster id, and — for older rows
  /// saved without an id — their account and roster names, lowercase and
  /// trimmed. [studentsByUserId]/[studentsByEmail] are precomputed once by
  /// the caller (typically [buildPayrollPreview], over every active
  /// assistant) rather than rescanning the full [students] roster per user.
  ({Set<String> ids, Set<String> names}) _payrollIdentityFor(
    User user, {
    required Map<String, Student> studentsByUserId,
    required Map<String, Student> studentsByEmail,
  }) {
    final linked =
        studentsByUserId[user.id] ??
        studentsByEmail[user.email.trim().toLowerCase()];
    return (
      ids: {user.id, if (linked != null) linked.id},
      names: {
        user.name.trim().toLowerCase(),
        if (linked != null) linked.name.trim().toLowerCase(),
      },
    );
  }

  /// Whether a row saved under [rowId] / [rowName] is one of [ids]'.
  /// Rows carry an id, and that decides it — two students can share a
  /// name. Only rows saved without one fall back to [names].
  bool _payrollRowMatches(
    String? rowId,
    String rowName,
    Set<String> ids,
    Set<String> names,
  ) => (rowId ?? '').isNotEmpty
      ? ids.contains(rowId)
      : names.contains(rowName.trim().toLowerCase());

  /// Hours count only when [AttendanceRecord.countsTowardPay]: a record
  /// flagged as a missed time-out is never paid, even once it has a
  /// time-out on it.
  List<PayrollMonthBreakdown> monthlyHoursInPeriod(
    Set<String> studentIds,
    Set<String> studentNameKeys,
    DateTime start,
    DateTime endInclusive,
  ) {
    bool belongsToStudent(AttendanceRecord a) => _payrollRowMatches(
      a.studentId,
      a.studentName,
      studentIds,
      studentNameKeys,
    );

    return _monthsInRange(start, endInclusive).map((entry) {
      final (month, year) = entry;
      final monthStart = DateTime(year, month, 1);
      final monthEndInclusive = DateTime(year, month + 1, 0);
      final rangeStart = monthStart.isBefore(start) ? start : monthStart;
      final rangeEnd = monthEndInclusive.isAfter(endInclusive)
          ? endInclusive
          : monthEndInclusive;

      final hours = attendance
          .where(
            (a) =>
                a.countsTowardPay &&
                belongsToStudent(a) &&
                _dateWithinRange(a.date, rangeStart, rangeEnd),
          )
          .fold<double>(0, (sum, a) => sum + (a.totalHours ?? 0));

      return PayrollMonthBreakdown(
        month: month,
        year: year,
        hoursWorked: hours,
        payableHours: hours
            .clamp(0, PayrollRecord.maximumMonthlyHours)
            .toDouble(),
      );
    }).toList();
  }

  /// A date saved in any of the shapes the app writes (ISO, "Sep 19,
  /// 2026", "9/19/2026"), for sorting newest first.
  DateTime _anyDate(String? raw) =>
      DateTime.tryParse(raw ?? '') ??
      _parsePayrollDate(raw) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// A Student Assistant's payroll checklist for the term [termLabel]:
  /// their application requirements, Endorsement Letter, the term's
  /// Contract of Appointment, and a DTR/Accomplishment Report for each
  /// month in [breakdown] they worked, each with the Head's mark from
  /// [check]. The files are only found in a Head's session; the Admin
  /// can't read them and goes by the marks alone.
  List<PayrollRequirement> _payrollRequirementsFor(
    User user, {
    required Set<String> ids,
    required Set<String> names,
    required List<PayrollMonthBreakdown> breakdown,
    required String termLabel,
    required PayrollCheck? check,
  }) {
    PayrollRequirement requirement(
      String key,
      PayrollRequirementKind kind,
      String label,
      List<PayrollRequirementFile> files, {
      String? ref,
    }) => PayrollRequirement(
      key: key,
      kind: kind,
      label: label,
      mark: check?.items[key],
      files: files,
      ref: ref ?? files.firstOrNull?.ref,
    );

    PayrollRequirementFile appFile(ApplicationDocument doc, Application app) =>
        PayrollRequirementFile(
          ref: doc.id.isNotEmpty ? doc.id : doc.fileName,
          name: doc.requirementName.isNotEmpty
              ? doc.requirementName
              : doc.fileName,
          detail: doc.fileName,
          storagePath: doc.storagePath,
          downloadUrl: doc.downloadUrl,
          date: doc.uploadedAt.isEmpty ? app.appliedAt : doc.uploadedAt,
        );

    // The application they were hired from: the newest approved one.
    final hiredFrom =
        applications
            .where(
              (a) =>
                  ids.contains(a.applicantId) &&
                  (a.status == 'Approved' || a.status == 'Accepted'),
            )
            .toList()
          ..sort(
            (a, b) => _anyDate(b.appliedAt).compareTo(_anyDate(a.appliedAt)),
          );
    final application = hiredFrom.firstOrNull;
    final appDocs = application?.submittedDocuments ?? const [];

    // This term's contract comes with its rehire decision; a student hired
    // during the term has the one made when their application was approved.
    final rehireContracts = [
      for (final r in rehireRecords)
        if (ids.contains(r.studentId) &&
            r.termLabel == termLabel &&
            r.isRehired &&
            r.hasContract)
          PayrollRequirementFile(
            ref: r.contractDocumentId ?? r.id,
            name: 'Contract of Appointment',
            detail: r.contractFileName ?? r.termLabel,
            storagePath: r.contractStoragePath,
            downloadUrl: r.contractDownloadUrl,
            date: r.decidedAt,
          ),
    ];
    final contracts = rehireContracts.isNotEmpty
        ? rehireContracts
        : [
            for (final doc in appDocs)
              if (AppState._isContractFile(doc)) appFile(doc, application!),
          ];

    final forwardedDtrs = <(int, int), List<HeadForward>>{};
    for (final f in headForwards) {
      final month = f.dtrMonth;
      if (month == null) continue;
      if (!_payrollRowMatches(f.studentId, f.studentName, ids, names)) {
        continue;
      }
      forwardedDtrs.putIfAbsent(month, () => []).add(f);
    }

    // Newest first. Forwards carry only a date, so on the day a returned
    // copy is sent again, the returned one goes behind the new one.
    List<PayrollRequirementFile> dtrFiles(int year, int month) {
      final returnedRef = check?.items[PayrollRequirement.dtrKey(year, month)];
      final returned = returnedRef?.isReturned == true
          ? returnedRef!.fileRef
          : null;
      final forwards = [...?forwardedDtrs[(year, month)]]
        ..sort((a, b) {
          final byDate = _anyDate(b.sentAt).compareTo(_anyDate(a.sentAt));
          if (byDate != 0) return byDate;
          return (a.id == returned ? 1 : 0) - (b.id == returned ? 1 : 0);
        });
      return [
        for (final f in forwards)
          PayrollRequirementFile(
            ref: f.id,
            name: f.fileName,
            detail: 'From ${f.sentByName}',
            storagePath: f.storagePath,
            downloadUrl: f.downloadUrl,
            date: f.sentAt,
          ),
      ];
    }

    return [
      requirement(
        PayrollRequirement.requirementsKey,
        PayrollRequirementKind.requirements,
        'Application requirements',
        [
          for (final doc in appDocs)
            if (!AppState._isContractFile(doc) && !AppState._isEndorsementFile(doc))
              appFile(doc, application!),
        ],
        // The set as a whole: a corrected copy is handed to the Head, not
        // sent through SAIS.
        ref: application?.id,
      ),
      requirement(
        PayrollRequirement.endorsementKey,
        PayrollRequirementKind.endorsement,
        'Endorsement Letter',
        [
          for (final doc in appDocs)
            if (AppState._isEndorsementFile(doc)) appFile(doc, application!),
        ],
      ),
      requirement(
        PayrollRequirement.contractKey(termLabel),
        PayrollRequirementKind.contract,
        'Contract of Appointment',
        contracts,
      ),
      for (final m in breakdown)
        if (m.hoursWorked > 0)
          requirement(
            PayrollRequirement.dtrKey(m.year, m.month),
            PayrollRequirementKind.dtr,
            'DTR/Accomplishment Report (${AppState._fullMonthNames[m.month - 1]} '
            '${m.year})',
            dtrFiles(m.year, m.month),
          ),
    ];
  }

  /// Builds a payroll preview for the pay period [start]..[endInclusive]
  /// (typically a whole semester, not a single month): every active Student
  /// Assistant, plus anyone else with paid hours in the period — a student
  /// not rehired, or whose account was archived, before payroll ran is
  /// still owed for them. Purely computed for anyone not yet approved. Once
  /// a student has a persisted [PayrollRecord] for this exact period
  /// (status 'Approved' or 'Released'), that persisted record is returned
  /// as-is instead of recomputing, so an approved amount stays fixed even
  /// if attendance data changes afterward.
  ///
  /// [periodLabel] is the term, "1st Semester, AY 2026-2027": the Head's
  /// exclusions and contract checks are kept under it. A student is
  /// 'Ready' once they have hours and the Head has checked every
  /// requirement on their checklist; 'Excluded' if the Head left them out
  /// of the term; 'No hours' if there's nothing to pay; otherwise — a
  /// requirement unchecked, or some of these days already paid under
  /// another period — 'Incomplete', which holds up the whole period (see
  /// [AppState.payrollHeldBy]).
  List<PayrollRecord> buildPayrollPreview({
    required DateTime start,
    required DateTime endInclusive,
    required String periodLabel,
  }) {
    final isoStart = _isoDate(start);
    final isoEnd = _isoDate(endInclusive);
    final existingByStudent = {
      for (final p in payrollRecords)
        if (p.periodStart == isoStart && p.periodEnd == isoEnd) p.studentId: p,
    };
    // Pay for other periods that share days with this one (ISO dates
    // compare in date order).
    final overlappingByStudent = {
      for (final p in payrollRecords)
        if ((p.periodStart != isoStart || p.periodEnd != isoEnd) &&
            p.periodStart.compareTo(isoEnd) <= 0 &&
            p.periodEnd.compareTo(isoStart) >= 0)
          p.studentId: p,
    };
    final idsWithHours = {
      for (final a in attendance)
        if (a.countsTowardPay &&
            (a.studentId ?? '').isNotEmpty &&
            _dateWithinRange(a.date, start, endInclusive))
          a.studentId!,
    };

    // Built once for the whole preview rather than rescanning `students`
    // per user inside `_payrollIdentityFor`.
    final studentsByUserId = {
      for (final s in students)
        if (s.userId != null) s.userId!: s,
    };
    final studentsByEmail = {
      for (final s in students) s.email.trim().toLowerCase(): s,
    };
    final checksByStudent = {for (final c in payrollChecks) c.studentId: c};

    final rows = <PayrollRecord>[];
    for (final user in users) {
      final existing = existingByStudent[user.id];
      final identity = _payrollIdentityFor(
        user,
        studentsByUserId: studentsByUserId,
        studentsByEmail: studentsByEmail,
      );
      final isAssistant =
          user.role == 'Student Assistant' && user.status == 'Active';
      if (existing == null &&
          !isAssistant &&
          !identity.ids.any(idsWithHours.contains)) {
        continue;
      }
      if (existing != null) {
        rows.add(existing);
        continue;
      }

      final breakdown = monthlyHoursInPeriod(
        identity.ids,
        identity.names,
        start,
        endInclusive,
      );
      final dtrVerified = breakdown.any((m) => m.hoursWorked > 0);
      final check = checksByStudent[user.id];
      final requirements = _payrollRequirementsFor(
        user,
        ids: identity.ids,
        names: identity.names,
        breakdown: breakdown,
        termLabel: periodLabel,
        check: check,
      );
      final reportVerified = requirements.every((r) => r.isChecked);
      final exclusion = check?.exclusions[periodLabel];
      // Left blank for an assistant not in an office, so Payroll shows
      // them as unassigned instead of under an "office" named after their
      // department.
      final assignedOffices = officesForUser(user);
      final office = assignedOffices.isNotEmpty
          ? assignedOffices.first.name
          : '';

      final overlapping = overlappingByStudent[user.id];

      rows.add(
        PayrollRecord(
          id: '',
          studentId: user.id,
          studentName: user.name,
          saId: user.saId,
          office: office,
          campus: user.campus,
          department: user.department,
          periodStart: isoStart,
          periodEnd: isoEnd,
          periodLabel: periodLabel,
          monthlyBreakdown: breakdown,
          dtrVerified: dtrVerified,
          reportVerified: reportVerified,
          status: exclusion != null
              ? 'Excluded'
              : !dtrVerified
              ? 'No hours'
              : reportVerified && overlapping == null
              ? 'Ready'
              : 'Incomplete',
          overlappingPayroll: overlapping,
          requirements: requirements,
          exclusion: exclusion,
        ),
      );
    }

    // Pay on file for an account that's gone still belongs to the period.
    final listed = {for (final row in rows) row.studentId};
    rows.addAll(
      existingByStudent.values.where((p) => !listed.contains(p.studentId)),
    );
    return rows;
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The Admin's saved payroll sheet for a pay period, if any.
  PayrollSheet? payrollSheetFor(String periodStart, String periodEnd) {
    final id = PayrollSheet.idForPeriod(periodStart, periodEnd);
    return payrollSheets.where((sheet) => sheet.id == id).firstOrNull;
  }

  /// The most recently saved payroll sheet, whose signatories and header
  /// fields a new period's sheet starts from.
  PayrollSheet? get latestPayrollSheet {
    if (payrollSheets.isEmpty) return null;
    return payrollSheets.reduce(
      (a, b) => (b.updatedAt ?? '').compareTo(a.updatedAt ?? '') > 0 ? b : a,
    );
  }

  Future<PayrollSheet> savePayrollSheet(PayrollSheet sheet) async {
    _firestoreService ??= FirestoreService();
    final saved = sheet.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
      updatedBy: currentUser?.name ?? 'Admin',
    );
    await _firestoreService!.setPayrollSheet(saved);
    payrollSheets = [saved, ...payrollSheets.where((s) => s.id != saved.id)];
    _notify();
    return saved;
  }

  /// Administrators approve payroll: computes the payable amount from
  /// total hours rendered for every currently-'Ready' entry in [preview]
  /// and records it in the payroll records with status 'Approved' —
  /// skipping anyone excluded, with no hours, already 'Approved', or
  /// 'Released'. [preview] must be the whole period; while anyone in it is
  /// 'Incomplete' ([AppState.payrollHeldBy]), nobody is approved.
  /// Each is saved under [PayrollRecord.idFor] and only if nothing is there
  /// yet, so a period approved elsewhere in the meantime isn't paid twice.
  /// Does not notify students yet; that happens on [releasePayroll].
  Future<(int count, double total)> approvePayroll(
    List<PayrollRecord> preview,
  ) async {
    final held = AppState.payrollHeldBy(preview);
    if (held.isNotEmpty) {
      throw StateError(
        '${held.length} Student Assistant(s) aren\'t ready to be paid yet.',
      );
    }
    _firestoreService ??= FirestoreService();
    final today = _formattedToday();
    var count = 0;
    var total = 0.0;

    for (final record in preview) {
      if (record.status != 'Ready') continue;
      final toSave = record.copyWith(
        id: PayrollRecord.idFor(
          record.studentId,
          record.periodStart,
          record.periodEnd,
        ),
        status: 'Approved',
        approvedAt: today,
        approvedBy: currentUser?.name ?? 'Admin',
      );
      if (!await _firestoreService!.createPayrollRecord(toSave)) continue;
      payrollRecords = [
        toSave,
        ...payrollRecords.where((p) => p.id != toSave.id),
      ];
      count++;
      total += record.grossPay;
    }

    _notify();
    return (count, total);
  }

  /// Administrators release payroll: marks each 'Approved' record in
  /// [approved] — what the Admin sees listed, filters and all — as
  /// 'Released' (the actual payout moment) and notifies each Student
  /// Assistant that their pay has been released.
  Future<(int count, double total)> releasePayroll(
    List<PayrollRecord> approved,
  ) async {
    _firestoreService ??= FirestoreService();
    final today = _formattedToday();
    var count = 0;
    var total = 0.0;

    final toRelease = approved.where(
      (p) => p.status == 'Approved' && p.id.isNotEmpty,
    );

    for (final record in toRelease) {
      final releasedBy = currentUser?.name ?? 'Admin';
      await _firestoreService!.updatePayrollRecord(record.id, {
        'status': 'Released',
        'releasedAt': today,
        'releasedBy': releasedBy,
      });
      payrollRecords = payrollRecords
          .map(
            (p) => p.id == record.id
                ? p.copyWith(
                    status: 'Released',
                    releasedAt: today,
                    releasedBy: releasedBy,
                  )
                : p,
          )
          .toList();
      count++;
      total += record.grossPay;

      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${record.studentId}',
          userId: record.studentId,
          title: 'Payout Released',
          message:
              'Your pay for ${record.periodLabel} (${record.payableHours.toStringAsFixed(1)} hrs · '
              '₱${record.grossPay.toStringAsFixed(2)}) has been released.',
          type: 'payroll',
          createdAt: today,
        ),
      );
    }

    _notify();
    return (count, total);
  }
}
