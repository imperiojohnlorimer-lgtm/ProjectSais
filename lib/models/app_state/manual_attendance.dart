part of '../app_state.dart';

/// Someone listed on an office by name only: their place in the office's
/// supervisor or student assistant list has no account id. Until it has,
/// a student assistant can't clock in there and a supervisor can't show
/// its attendance code or see its records (the Firestore rules and the
/// clock-attendance server go by the id).
class UnlinkedOfficePerson {
  final Office office;
  final bool isSupervisor;
  final String name;

  /// The one account this name can safely be linked to, or null when there
  /// is none, several, or linking would place the person twice.
  final User? match;

  const UnlinkedOfficePerson({
    required this.office,
    required this.isSupervisor,
    required this.name,
    required this.match,
  });
}

// Attendance staff record by hand, and linking office entries to accounts.
extension AppStateManualAttendance on AppState {
  /// How many days back a supervisor or the Head may record attendance.
  static const manualAttendanceDays = 7;

  /// The student assistants the signed-in user may record attendance for:
  /// every active one for the Head; for a Supervisor, those in the offices
  /// they head by account id (what the Firestore rules allow).
  List<User> get manualAttendanceAssistants {
    bool active(User user) =>
        user.role == 'Student Assistant' && user.status != 'Archived';
    final List<User> list;
    if (role == 'Head') {
      list = users.where(active).toList();
    } else if (role == 'Supervisor') {
      final ids = {for (final office in qrOffices) ...office.assistantIds}
        ..remove('');
      list = users
          .where((user) => active(user) && ids.contains(user.id))
          .toList();
    } else {
      return const [];
    }
    return list..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  /// The days, newest first, staff may record attendance for: today and the
  /// [manualAttendanceDays] before it (Philippine dates), none before the
  /// academic year started.
  List<DateTime> manualAttendanceDayChoices({DateTime? now}) {
    final today = _philippineDay(now);
    final start = DateTime(
      academicYearStart.year,
      academicYearStart.month,
      academicYearStart.day,
    );
    return [
      for (var back = 0; back <= manualAttendanceDays; back++)
        DateTime(today.year, today.month, today.day - back),
    ].where((day) => !day.isBefore(start)).toList();
  }

  /// The session ('AM' or 'PM') [minutes] past midnight falls in, or null.
  static String? _sessionOf(int minutes) {
    if (minutes >= AppState._qrMorningStartMinutes &&
        minutes <= AppState._qrMorningEndMinutes) {
      return 'AM';
    }
    if (minutes >= AppState._qrAfternoonStartMinutes &&
        minutes <= AppState._qrAfternoonEndMinutes) {
      return 'PM';
    }
    return null;
  }

  /// [assistant]'s attendance records, archived ones left out, matched as
  /// the Head's summary matches them: by account or roster id, or by name
  /// for a record saved without an id.
  List<AttendanceRecord> _liveRecordsOf(User assistant) {
    final studentRecords = _studentRecordsForUser(assistant);
    final ids = {
      assistant.id,
      for (final s in studentRecords) ...[s.id, ?s.userId],
    };
    final names = {
      assistant.name.trim().toLowerCase(),
      for (final s in studentRecords) s.name.trim().toLowerCase(),
    }..remove('');
    return attendance
        .where(
          (record) =>
              !record.isArchived &&
              ((record.studentId ?? '').isNotEmpty
                  ? ids.contains(record.studentId)
                  : names.contains(record.studentName.trim().toLowerCase())),
        )
        .toList();
  }

  /// Why attendance from [timeIn] to [timeOut] (`8:00 AM`) on [day] can't
  /// be recorded by hand for [assistant], or null when it can. "Today" is
  /// Philippine time ([now] stands in for the clock in tests).
  String? manualAttendanceProblem({
    required User assistant,
    required DateTime day,
    required String timeIn,
    required String timeOut,
    DateTime? now,
  }) {
    final date = DateTime(day.year, day.month, day.day);
    final today = _philippineDay(now);
    if (date.isAfter(today)) return "Attendance can't be recorded ahead.";
    if (!manualAttendanceDayChoices(now: now).contains(date)) {
      return 'Attendance can only be recorded for the last '
          '${AppStateManualAttendance.manualAttendanceDays} days of this '
          'academic year.';
    }

    final start = _parseTimeOfDayMinutes(timeIn);
    final end = _parseTimeOfDayMinutes(timeOut);
    if (start == null || end == null) return 'Pick a time-in and a time-out.';
    final session = _sessionOf(start);
    if (session == null || _sessionOf(end) == null) {
      return 'Attendance runs 7:30 AM–12:00 PM and 12:30 PM–5:00 PM.';
    }
    if (_sessionOf(end) != session) {
      return 'The time-in and time-out must be in the same session '
          '(morning or afternoon). Record each session separately.';
    }
    if (end <= start) return 'The time-out must be after the time-in.';
    if (date == today) {
      final clock = philippineClock(now);
      if (end > clock.hour * 60 + clock.minute) {
        return "The time-out can't be later than now.";
      }
    }

    for (final record in _liveRecordsOf(assistant)) {
      if (attendanceDay(record) != date) continue;
      final otherStart = _parseTimeOfDayMinutes(record.timeIn);
      if (otherStart == null) continue;
      final otherSession = _sessionOf(otherStart);
      // A record still open runs, as far as anyone knows, to its session's
      // end.
      final otherEnd = record.isActive
          ? (otherSession == 'AM'
                ? AppState._qrMorningEndMinutes
                : AppState._qrAfternoonEndMinutes)
          : _parseTimeOfDayMinutes(record.timeOut ?? '');
      if (otherEnd == null) continue;
      if (start < otherEnd && otherStart < end) {
        return record.isActive
            ? '${assistant.name} has a record from ${record.timeIn} that '
                  'session with no time-out. Use Record time-out on it '
                  'instead.'
            : 'This overlaps their record from ${record.timeIn} to '
                  '${record.timeOut} that day.';
      }
    }

    // Whether pay for the day is already approved can't be checked here:
    // payroll records are the Admin's, and neither the Head nor a
    // Supervisor may read them. The 7-day limit keeps the window small.
    return null;
  }

  /// Records attendance from [timeIn] to [timeOut] on [day] for
  /// [assistant], entered by a Supervisor or the Head when there was no
  /// code to scan. Returns null once saved, else why not. The weekly hours
  /// cap applies as at a scan; the record says who entered it, and the
  /// student is told.
  Future<String?> recordManualAttendance({
    required User assistant,
    required DateTime day,
    required String timeIn,
    required String timeOut,
    DateTime? now,
  }) async {
    final problem = manualAttendanceProblem(
      assistant: assistant,
      day: day,
      timeIn: timeIn,
      timeOut: timeOut,
      now: now,
    );
    if (problem != null) return problem;

    final date = DateTime(day.year, day.month, day.day);
    final dateLabel =
        '${AppState._monthNames[date.month - 1]} ${date.day}, ${date.year}';
    final dayKey =
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    // Never one of the server's `<uid>_<yyyyMMdd>_<n>` ids: its numbering
    // skips ids that don't end in a number, so the two can't collide.
    final id =
        '${assistant.id}_${dayKey}_manual_'
        '${DateTime.now().millisecondsSinceEpoch}';
    final officeId = offices
        .where(
          (office) =>
              office.isActive && office.assistantIds.contains(assistant.id),
        )
        .firstOrNull
        ?.id;
    final elapsed = _hoursBetween(timeIn, timeOut);
    final draft = AttendanceRecord(
      id: id,
      studentName: assistant.name,
      studentId: assistant.id,
      date: dateLabel,
      timeIn: timeIn,
      timeOut: timeOut,
    );
    final totalHours = _hoursWithinWeeklyCap(draft, elapsed);
    final edit = _attendanceEdit('Attendance recorded by hand');
    final record = AttendanceRecord(
      id: id,
      studentName: assistant.name,
      studentId: assistant.id,
      date: dateLabel,
      timeIn: timeIn,
      timeOut: timeOut,
      totalHours: totalHours,
      academicYear: academicYear,
      officeId: officeId,
      editedBy: edit.by,
      editedAt: edit.at,
      editNote: edit.note,
    );

    attendance = [record, ...attendance];
    _notify();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.addAttendance({
        'studentName': assistant.name,
        'studentId': assistant.id,
        'date': dateLabel,
        'timeIn': timeIn,
        'timeOut': timeOut,
        'totalHours': totalHours,
        // Kept alongside, as clock-attendance does, when the cap trimmed it.
        if (totalHours < elapsed) 'hoursBeforeWeeklyCap': elapsed,
        'academicYear': academicYear,
        'officeId': ?officeId,
        'isInvalid': false,
        'isArchived': false,
        ...edit.fields,
      }, id: id);
      _tellStudentOfEdit(record, edit.note);
      return null;
    } catch (error) {
      debugPrint('Could not record attendance by hand: $error');
      attendance = attendance.where((a) => a.id != id).toList();
      _notify();
      return error.toString().contains('permission-denied')
          ? "Couldn't save: you may not record attendance for this student "
                'assistant.'
          : "Couldn't save the attendance. Check your connection and try "
                'again.';
    }
  }

  /// Everyone listed on an active office by name only (see
  /// [UnlinkedOfficePerson]), for the Head's Offices page.
  List<UnlinkedOfficePerson> get unlinkedOfficePeople {
    String key(String name) => name.trim().toLowerCase();

    // Name-only places across all active offices, to spot a name that sits
    // id-less in two offices (linking it to one would be a guess).
    final nameOnlyAssistants = <String, Set<String>>{};
    for (final office in offices.where((o) => o.isActive)) {
      for (var i = 0; i < office.assistantNames.length; i++) {
        final id = i < office.assistantIds.length ? office.assistantIds[i] : '';
        final name = key(office.assistantNames[i]);
        if (id.isEmpty && name.isNotEmpty) {
          nameOnlyAssistants.putIfAbsent(name, () => {}).add(office.id);
        }
      }
    }

    User? matchFor(Office office, String name, bool isSupervisor) {
      final wanted = key(name);
      final candidates = users
          .where(
            (user) =>
                user.status != 'Archived' &&
                user.role == (isSupervisor ? 'Supervisor' : 'Student Assistant') &&
                key(user.name) == wanted,
          )
          .toList();
      if (candidates.length != 1) return null;
      final user = candidates.single;
      if (isSupervisor) {
        return office.headIds.contains(user.id) ? null : user;
      }
      final placed = offices.any((o) => o.assistantIds.contains(user.id));
      final elsewhere = (nameOnlyAssistants[wanted] ?? const {}).length > 1;
      return placed || elsewhere ? null : user;
    }

    final people = <UnlinkedOfficePerson>[];
    for (final office in offices.where((o) => o.isActive)) {
      for (final isSupervisor in const [true, false]) {
        final ids = isSupervisor ? office.headIds : office.assistantIds;
        final names = isSupervisor ? office.headNames : office.assistantNames;
        for (var i = 0; i < names.length; i++) {
          final id = i < ids.length ? ids[i] : '';
          final name = names[i].trim();
          if (id.isNotEmpty || name.isEmpty) continue;
          people.add(
            UnlinkedOfficePerson(
              office: office,
              isSupervisor: isSupervisor,
              name: name,
              match: matchFor(office, name, isSupervisor),
            ),
          );
        }
      }
    }
    return people;
  }

  /// Links [person]'s place in their office to their matching account.
  /// Read and written in one transaction, so a place that changed since the
  /// page was drawn is left alone. Returns whether it saved.
  Future<bool> linkOfficePerson(UnlinkedOfficePerson person) async {
    final match = person.match;
    if (match == null) return false;
    final wanted = person.name.trim().toLowerCase();
    try {
      _firestoreService ??= FirestoreService();
      final saved = await _firestoreService!.updateOffices(
        {person.office.id},
        (stored) {
          final current = stored[person.office.id];
          if (current == null) return null;
          final names = person.isSupervisor
              ? current.headNames
              : current.assistantNames;
          final ids = [
            ...(person.isSupervisor ? current.headIds : current.assistantIds),
          ];
          // The lists run in parallel; an older office can have fewer ids.
          while (ids.length < names.length) {
            ids.add('');
          }
          if (ids.contains(match.id)) return null;
          // Placed by id in another office since the page was drawn (that
          // office is read too, through officeAssignments): linking now
          // would list them in two offices.
          if (!person.isSupervisor &&
              stored.values.any(
                (office) =>
                    office.id != current.id &&
                    office.assistantIds.contains(match.id),
              )) {
            return null;
          }
          final at = [
            for (var i = 0; i < names.length; i++)
              if (ids[i].isEmpty && names[i].trim().toLowerCase() == wanted) i,
          ].firstOrNull;
          if (at == null) return null;
          ids[at] = match.id;
          return {
            current.id: person.isSupervisor
                ? current.copyWith(headIds: ids)
                : current.copyWith(assistantIds: ids),
          };
        },
        people: person.isSupervisor ? const [] : [match.id],
      );
      if (saved == null) return false;
      await _showSavedOffices(saved);
      return true;
    } catch (error) {
      debugPrint('Could not link ${person.name} to their account: $error');
      return false;
    }
  }
}
