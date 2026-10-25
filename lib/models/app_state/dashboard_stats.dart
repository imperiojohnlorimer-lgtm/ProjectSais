part of '../app_state.dart';

extension AppStateDashboardStats on AppState {
  // ─── Dashboard Stats ───────────────────────────────
  Map<String, dynamic> get dashboardStats => {
    'totalStudents': filteredStudents.length,
    'activeToday': attendance
        .where(
          (a) =>
              !a.isArchived &&
              !a.isInvalid &&
              a.academicYear == academicYear &&
              a.isActive,
        )
        .length,
    'pendingReports': reports
        .where((r) => r.status == 'Pending' && r.academicYear == academicYear)
        .length,
    'avgHoursPerWeek': _computeAvgHoursPerWeek(),
  };

  String _computeAvgHoursPerWeek() {
    if (students.isEmpty) return '0';

    // Use attendance records in the last 28 days (4 weeks) to compute
    // a per-student weekly average. For each student, sum their
    // attendance totalHours (or compute from timeIn/timeOut when missing),
    // then divide by 4 to obtain weekly hours. Finally average across students.
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 28));

    // Map by student userId or studentName when userId is not present.
    final Map<String, double> hoursByStudent = {};

    for (final rec in attendance) {
      if (rec.isArchived || rec.academicYear != academicYear) continue;
      DateTime? recDate = _parseFormattedDate(rec.date);
      if (recDate == null) continue;
      if (recDate.isBefore(cutoff)) continue;

      double recHours = 0;
      if (rec.totalHours != null && rec.totalHours! > 0) {
        recHours = rec.totalHours!;
      } else if (rec.timeOut != null && rec.timeOut!.isNotEmpty) {
        final inDt = _parseTime(rec.timeIn, recDate);
        final outDt = _parseTime(rec.timeOut!, recDate);
        if (inDt != null && outDt != null && outDt.isAfter(inDt)) {
          recHours = outDt.difference(inDt).inMinutes / 60.0;
        }
      }

      final key = (rec.studentId != null && rec.studentId!.isNotEmpty)
          ? rec.studentId!
          : rec.studentName;
      hoursByStudent[key] = (hoursByStudent[key] ?? 0) + recHours;
    }

    double sumWeekly = 0;
    for (final s in students) {
      final key = (s.userId != null && s.userId!.isNotEmpty)
          ? s.userId!
          : s.name;
      final totalHours = hoursByStudent[key] ?? 0;
      final weekly = totalHours / 4.0;
      sumWeekly += weekly;
    }

    final avg = sumWeekly / students.length;
    return avg.toStringAsFixed(1);
  }

  DateTime? _parseFormattedDate(String dateStr) {
    // Expected format: 'Mon D, YYYY' e.g. 'Jan 5, 2026'
    try {
      final parts = dateStr.split(' ');
      if (parts.length < 3) return null;
      final monthStr = parts[0];
      final dayStr = parts[1].replaceAll(',', '');
      final yearStr = parts[2];
      final months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final m = months[monthStr];
      if (m == null) return null;
      final d = int.tryParse(dayStr);
      final y = int.tryParse(yearStr);
      if (d == null || y == null) return null;
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseTime(String timeStr, DateTime baseDate) {
    // Expected format: 'h:mm AM' or 'hh:mm PM'
    try {
      final parts = timeStr.split(' ');
      if (parts.length < 2) return null;
      final hm = parts[0].split(':');
      if (hm.length != 2) return null;
      final hour = int.tryParse(hm[0]);
      final minute = int.tryParse(hm[1]);
      final period = parts[1].toUpperCase();
      if (hour == null || minute == null) return null;
      var h = hour % 12;
      if (period == 'PM') h += 12;
      return DateTime(baseDate.year, baseDate.month, baseDate.day, h, minute);
    } catch (_) {
      return null;
    }
  }

  Future<void> checkSystemStatus() async {
    _firestoreService ??= FirestoreService();
    // Check Firestore latency
    try {
      final ping = await _firestoreService!.pingAnnouncements();
      if (ping >= 0) {
        dbHealthy = true;
        responseTimeMs = ping;
      } else {
        dbHealthy = false;
        responseTimeMs = 0;
      }
    } catch (_) {
      dbHealthy = false;
      responseTimeMs = 0;
    }

    // Auth service reachable
    try {
      final _ = fb_auth.FirebaseAuth.instance;
      authHealthy = true;
    } catch (_) {
      authHealthy = false;
    }

    // Reports collection check
    try {
      final pingR = await _firestoreService!.pingReports();
      reportsHealthy = pingR >= 0;
    } catch (_) {
      reportsHealthy = false;
    }

    _notify();
  }

  /// Count of student assistants per campus, in the same order as [campuses].
  /// Students whose campus doesn't match a known campus are simply not counted.
  Map<String, int> get studentsPerCampus {
    final counts = {for (final c in campuses) c: 0};
    for (final s in effectiveStudents) {
      final campus = s.campus;
      if (campus != null && counts.containsKey(campus)) {
        counts[campus] = counts[campus]! + 1;
      }
    }
    return counts;
  }

  /// Count of student assistants per department, scoped to a single campus.
  /// Only departments with at least one student assistant on that campus are included.
  Map<String, int> departmentBreakdownForCampus(String campus) {
    final counts = <String, int>{};
    for (final s in effectiveStudents) {
      if (s.campus != campus) continue;
      counts[s.department] = (counts[s.department] ?? 0) + 1;
    }
    return counts;
  }

  /// Student-assistant headcount per campus for each school year, oldest
  /// first and ending with the current year, which is counted live. A past
  /// year's headcount is the one saved with its archive when the year was
  /// closed (see [FirestoreService.archiveAcademicYearSettings]); years
  /// closed before that was saved are left out rather than guessed.
  List<({String academicYear, Map<String, int> byCampus})>
  get enrollmentHistory {
    final byYear = <String, Map<String, int>>{};
    for (final archive in academicYearArchives) {
      final year = (archive['academicYear'] ?? archive['id'])?.toString();
      final counts = archive['headcountByCampus'];
      // A year after the current one is left over from an undone move.
      if (year == null || counts is! Map || year.compareTo(academicYear) >= 0) {
        continue;
      }
      byYear[year] = {
        for (final entry in counts.entries)
          if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
      };
    }
    byYear[academicYear] = studentsPerCampus;
    return [
      for (final year in byYear.keys.toList()..sort())
        (academicYear: year, byCampus: byYear[year]!),
    ];
  }

  /// Today's date as the app writes it ("Oct 14, 2026"): Philippine time, the
  /// same day attendance, tasks and the rules go by, whatever this device's
  /// clock says.
  String _formattedToday() => philippineToday();
}
