import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../models/recurring_schedule.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/dtr_accomplishment_report_document_service.dart';
import '../../services/recurring_schedule_repository.dart';
import '../../services/schedule_service.dart';
import '../../utils/web_download_stub.dart'
    if (dart.library.html) '../../utils/web_download.dart'
    as web_download;

/// Supervisor screen: generate a student assistant's official
/// "DTR/Accomplishment Report/Class Schedule" document for a given month,
/// pre-filled from verified attendance (DTR) records, then editable and
/// downloadable as a .docx — mirrors [PerformanceEvaluationScreen].
class DtrAccomplishmentReportScreen extends StatefulWidget {
  const DtrAccomplishmentReportScreen({super.key});

  @override
  State<DtrAccomplishmentReportScreen> createState() =>
      _DtrAccomplishmentReportScreenState();
}

class _DtrAccomplishmentReportScreenState
    extends State<DtrAccomplishmentReportScreen> {
  String _search = '';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Student? _reportStudent;

  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    // Inline report builder — swaps in place of the student list, staying
    // inside this same screen (and the app shell's sidebar/top bar) rather
    // than navigating to a separate full-screen route.
    if (_reportStudent != null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.slate50, Colors.white],
            stops: [0.0, 0.25],
          ),
        ),
        child: _DtrReportBuilderScreen(
          key: ValueKey(_reportStudent!.id),
          student: _reportStudent!,
          month: _month,
          onBack: () => setState(() => _reportStudent = null),
        ),
      );
    }

    final all = state.filteredStudents;
    final students = all.where((s) {
      final q = _search.trim().toLowerCase();
      return q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.department.toLowerCase().contains(q);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final verifiedByStudent = {
      for (final student in all)
        student.name: state.verifiedDtrHoursForStudent(student.name),
    };
    final withHours = verifiedByStudent.values.where((h) => h > 0).length;
    final totalVerified = verifiedByStudent.values.fold<double>(
      0,
      (running, hours) => running + hours,
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.slate50, Colors.white],
          stops: [0.0, 0.25],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
            child: HeroBanner(
              isMobile: isMobile,
              icon: Icons.fact_check_rounded,
              title: 'DTR / Accomplishment Report',
              subtitle:
                  'Generate the official form for a student assistant, '
                  'pre-filled from verified DTR records',
              searchHint: 'Search by name or department...',
              onSearch: (value) => setState(() => _search = value),
              filters: [SizedBox(width: 190, child: _monthDropdown())],
              stats: [
                HeroStatData(
                  label: 'Assistants',
                  value: '${all.length}',
                  icon: Icons.groups_rounded,
                ),
                HeroStatData(
                  label: 'With DTR hours',
                  value: '$withHours',
                  icon: Icons.check_circle_rounded,
                ),
                HeroStatData(
                  label: 'Verified hours',
                  value: totalVerified.toStringAsFixed(1),
                  icon: Icons.access_time_filled_rounded,
                ),
                HeroStatData(
                  label: 'Period',
                  value: _months[_month.month - 1].substring(0, 3),
                  icon: Icons.calendar_month_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: students.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
                    itemCount: students.length,
                    itemBuilder: (context, i) =>
                        _studentCard(context, state, students[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _monthDropdown() => SizedBox(
    height: 40,
    child: DropdownButtonFormField<int>(
      initialValue: _month.month,
      isDense: true,
      // Fills the fixed-width box and ellipsizes, rather than sizing itself
      // to the widest month and running "September" past the edge.
      isExpanded: true,
      icon: const Icon(Icons.expand_more_rounded, color: AppTheme.slate400),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.slate700,
      ),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(
          Icons.calendar_month_rounded,
          size: 16,
          color: AppTheme.slate400,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.maroon, width: 1.6),
        ),
      ),
      items: List.generate(
        12,
        (i) => DropdownMenuItem(
          value: i + 1,
          child: Text(_months[i], maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      onChanged: (v) =>
          setState(() => _month = DateTime(_month.year, v ?? _month.month)),
    ),
  );
  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.slate100, AppTheme.slate50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              size: 38,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No student assistants found',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try a different search term or switch the selected month.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.slate400),
          ),
        ],
      ),
    ),
  );

  Widget _studentCard(BuildContext context, AppState state, Student student) {
    final verifiedHours = state.verifiedDtrHoursForStudent(student.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.maroon, AppTheme.gold],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppTheme.maroon, AppTheme.maroonLight],
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.maroon50,
                          child: Text(
                            student.initials,
                            style: const TextStyle(
                              color: AppTheme.maroon,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.apartment_rounded,
                                  size: 12,
                                  color: AppTheme.slate400,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    student.department,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.slate400,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  // Chips and the action share one row so the card stays
                  // compact; they wrap onto separate lines when narrow.
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _basisChip(
                            icon: Icons.access_time_filled_rounded,
                            label:
                                'Verified DTR: ${verifiedHours.toStringAsFixed(1)} hrs',
                            ok: verifiedHours > 0,
                          ),
                          _basisChip(
                            icon: Icons.calendar_month_rounded,
                            label:
                                '${_months[_month.month - 1]} ${_month.year}',
                            ok: true,
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () =>
                            _openReportBuilder(context, state, student),
                        icon: const Icon(Icons.description_rounded, size: 16),
                        label: const Text(
                          'Generate Report',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _basisChip({
    required IconData icon,
    required String label,
    required bool ok,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: ok ? AppTheme.emerald50 : AppTheme.slate50,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: ok
            ? AppTheme.emerald500.withValues(alpha: 0.2)
            : AppTheme.slate200,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: ok ? AppTheme.emerald500 : AppTheme.slate400,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: ok ? AppTheme.emerald500 : AppTheme.slate400,
          ),
        ),
      ],
    ),
  );

  void _openReportBuilder(
    BuildContext context,
    AppState state,
    Student student,
  ) {
    setState(() => _reportStudent = student);
  }
}

/// Full-page editor: shows the auto-populated 31-day DTR table (from
/// verified attendance records) and the weekly class-schedule grid, both
/// editable, then generates the filled .docx.
class _DtrReportBuilderScreen extends StatefulWidget {
  final Student student;
  final DateTime month;
  final VoidCallback onBack;

  const _DtrReportBuilderScreen({
    super.key,
    required this.student,
    required this.month,
    required this.onBack,
  });

  @override
  State<_DtrReportBuilderScreen> createState() =>
      _DtrReportBuilderScreenState();
}

class _DtrReportBuilderScreenState extends State<_DtrReportBuilderScreen> {
  static const _months = [
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

  late List<DtrDayEntry> _days;
  late List<TextEditingController> _noteCtrls;
  late List<DtrClassScheduleEntry> _schedule;
  late List<List<TextEditingController>> _scheduleCtrls; // [row][8 fields]
  bool _generating = false;
  bool _syncingSchedule = false;
  bool _sendingToHead = false;

  // Header and sign-off fields printed on the report. They start from the
  // student's roster entry, their office supervisor and the Head, and can
  // be corrected before generating.
  late final TextEditingController _studentNameCtrl;
  late final TextEditingController _departmentCtrl;
  late final TextEditingController _monthCtrl;
  late final TextEditingController _studentSigCtrl;
  late final TextEditingController _supervisorCtrl;
  late final TextEditingController _approverCtrl;

  /// This student's recurring weekly schedule rules ("Add Schedule"/"Add
  /// Subject" on the Schedule/Calendar screen), keyed by weekday. Used to
  /// (a) validate whether a completed task falls on a day the student is
  /// actually supposed to be working, and (b) auto-fill that day's AM/PM
  /// in/out times from the matching rule's start/end time.
  List<RecurringScheduleRule> _rules = [];

  int get _daysInMonth =>
      DateTime(widget.month.year, widget.month.month + 1, 0).day;

  /// Every plausible name "Add Schedule"/"Add Subject" rules could have
  /// been saved under for this student.
  ///
  /// Those are saved from the Schedule/Calendar screen keyed by whoever is
  /// logged in at the time (their [User.name]) — which is not guaranteed to
  /// be byte-for-byte identical to this [Student] roster entry's own `name`
  /// field (different capitalization/spacing, a nickname vs. full name, the
  /// roster entry not being linked to a [User] account via `userId`/email
  /// at all, edits made in one profile but not the other, etc).
  ///
  /// Rather than betting on a single guess and silently coming up empty
  /// when it's wrong (which is exactly what was happening), every rules
  /// lookup below tries every candidate name and merges whatever it finds
  /// — the matched [User.name] (by `userId`, then by email) if one exists,
  /// and this roster entry's own `name`, in that order, skipping
  /// duplicates.
  List<String> _scheduleOwnerNameCandidates(AppState state) {
    final candidates = <String>[];
    final email = widget.student.email.toLowerCase();
    for (final u in state.users) {
      if (widget.student.userId != null && u.id == widget.student.userId) {
        candidates.add(u.name);
      } else if (email.isNotEmpty && u.email.toLowerCase() == email) {
        candidates.add(u.name);
      }
    }
    candidates.add(widget.student.name);
    final seen = <String>{};
    return candidates.where((n) => n.trim().isNotEmpty && seen.add(n)).toList();
  }

  /// Loads this student's recurring schedule rules, trying every
  /// [_scheduleOwnerNameCandidates] name and merging the results (deduped
  /// by rule id) — see that method for why a single name isn't reliable
  /// enough to bet the whole lookup on.
  Future<List<RecurringScheduleRule>> _loadAllRulesForStudent(
    AppState state,
  ) async {
    const repo = RecurringScheduleRepository();
    final merged = <String, RecurringScheduleRule>{};
    for (final name in _scheduleOwnerNameCandidates(state)) {
      for (final rule in await repo.loadRules(name)) {
        merged[rule.id] = rule;
      }
    }
    return merged.values.toList();
  }

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _studentNameCtrl = TextEditingController(text: widget.student.name);
    _departmentCtrl = TextEditingController(text: widget.student.department);
    _monthCtrl = TextEditingController(text: _monthYearLabel);
    _studentSigCtrl = TextEditingController(text: widget.student.name);
    _supervisorCtrl = TextEditingController(
      text: _defaultSupervisorName(state),
    );
    _approverCtrl = TextEditingController(text: _defaultApproverName(state));
    _days = _buildDaysFromAttendance(state);
    _noteCtrls = _days
        .map((d) => TextEditingController(text: d.note ?? ''))
        .toList();

    // The student's recurring weekly schedule (set up on their Schedule
    // screen) may not be cached yet — load it, then refresh only the cells
    // the supervisor hasn't touched so a "Class Schedule"/"Holiday" default
    // reflects it without clobbering manual edits. Also load the raw
    // recurring rules (start/end times) used to validate & time-stamp
    // completed-task entries below.
    //
    // This waits for the first frame: ScheduleService.refresh notifies its
    // listeners straight away, and doing that while this screen is still
    // being built is a "markNeedsBuild() called during build" error.
    final ownerNames = _scheduleOwnerNameCandidates(state);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Looked up once, up front: after the awaits below this screen may
      // already be closed, and a closed screen can't read providers.
      final schedules = context.read<ScheduleService>();
      final rulesFuture = _loadAllRulesForStudent(state);
      // Force a fresh Firestore read every time this screen opens, rather
      // than `ensureLoaded` (which is a no-op once anything — even an
      // empty result from before the student's schedule existed — is
      // already cached for this name). Without this, a student's schedule
      // could go stale here for the rest of the app session even though
      // the Class Schedule table below (which re-queries directly, with
      // no caching layer) correctly shows it.
      for (final name in ownerNames) {
        await schedules.refresh(name);
      }
      final rules = await rulesFuture;
      if (!mounted) return;
      _rules = rules;
      final refreshed = _buildDaysFromAttendance(state);
      setState(() {
        for (var i = 0; i < _days.length; i++) {
          final oldDefault = _days[i].note ?? '';
          if (_noteCtrls[i].text == oldDefault) {
            _noteCtrls[i].text = refreshed[i].note ?? '';
          }
        }
        _days = refreshed;
      });
    });

    // Auto-fill from the student's previously saved weekly class schedule,
    // if any — same automated pull as the DTR table above. Starts with 8
    // rows (or however many were saved, if more) — "Add Subject" below the
    // table grows it further, up to the template's 12-row capacity.
    final saved = state.classScheduleForStudent(widget.student.name);
    final startingRows = saved.length > 8
        ? (saved.length > _maxScheduleRows ? _maxScheduleRows : saved.length)
        : 8;
    _schedule = List.generate(
      startingRows,
      (i) => i < saved.length
          ? DtrClassScheduleEntry(
              course: saved[i].course,
              units: saved[i].units,
              monday: saved[i].monday,
              tuesday: saved[i].tuesday,
              wednesday: saved[i].wednesday,
              thursday: saved[i].thursday,
              friday: saved[i].friday,
              saturday: saved[i].saturday,
              sourceRuleLabel: saved[i].sourceRuleLabel,
            )
          : const DtrClassScheduleEntry(),
    );
    _scheduleCtrls = List.generate(
      startingRows,
      (i) => _controllersFor(_schedule[i]),
    );

    // Nothing manually saved yet for this student — fall back to their
    // "Add Schedule" recurring rules from the Schedule/Calendar screen
    // (same rules that already default the "Accomplishment/s" column
    // above). Also re-triggerable manually via the "Sync from Schedule"
    // button next to the section title, since this report screen may
    // already have been open before the student set up their schedule.
    //
    // This now always runs (not just when nothing was saved yet): the
    // recurring rules live in Firestore and can change on the student's
    // own device at any time, so every time this screen opens it
    // reconciles against whatever the calendar currently says — adding
    // new subjects, updating edited ones, and removing rows for subjects
    // the student deleted — instead of freezing whatever was auto-saved
    // the first time and never looking again.
    _syncFromRecurringSchedule();
  }

  /// Supervisors and the Head can both open this screen, so "Verified and
  /// checked by — Immediate Supervisor" can't simply be whoever is signed
  /// in: a supervisor verifies their own students' reports, but when the
  /// Head opens one it's the supervisor of the office the student is
  /// assigned to. Blank when the student has no office yet.
  String _defaultSupervisorName(AppState state) {
    if (_isSupervisor(state)) return state.currentUser?.name ?? '';
    final student = widget.student;
    final name = student.name.trim().toLowerCase();
    for (final office in state.offices) {
      final assigned =
          office.assistantIds.contains(student.id) ||
          (student.userId != null &&
              office.assistantIds.contains(student.userId)) ||
          office.assistantNames.any((n) => n.trim().toLowerCase() == name);
      if (assigned && office.headNames.isNotEmpty) {
        return office.headNames.first;
      }
    }
    return '';
  }

  /// "Approved — Head, Student Assistantship", as the template reads: the
  /// app's Head (the same title the Applicant Screening form gives them),
  /// whether that's who is signed in or who the report goes to.
  String _defaultApproverName(AppState state) {
    if (state.role == 'Head') return state.currentUser?.name ?? '';
    return state.users.where((u) => u.role == 'Head').firstOrNull?.name ?? '';
  }

  /// Only an office supervisor sends reports on to the Head; the Head
  /// opening this screen is the one they'd be sent to.
  bool _isSupervisor(AppState state) => state.role == 'Supervisor';

  List<TextEditingController> _controllersFor(DtrClassScheduleEntry row) => [
    TextEditingController(text: row.course),
    TextEditingController(text: row.units),
    TextEditingController(text: row.monday),
    TextEditingController(text: row.tuesday),
    TextEditingController(text: row.wednesday),
    TextEditingController(text: row.thursday),
    TextEditingController(text: row.friday),
    TextEditingController(text: row.saturday),
  ];

  // The template's Class Schedule table has exactly 12 physical rows
  // (assets/templates/dtr_accomplishment_report_template.docx) — a 13th
  // subject would have nowhere to render, so "Add Subject" stops here.
  static const _maxScheduleRows = 12;

  void _addScheduleRow() {
    if (_schedule.length >= _maxScheduleRows) return;
    setState(() {
      _schedule.add(const DtrClassScheduleEntry());
      _scheduleCtrls.add(_controllersFor(const DtrClassScheduleEntry()));
    });
  }

  void _removeScheduleRow(int i) {
    setState(() {
      _schedule.removeAt(i);
      for (final c in _scheduleCtrls[i]) {
        c.dispose();
      }
      _scheduleCtrls.removeAt(i);
    });
  }

  /// Loads this student's "Add Schedule" recurring rules and fills the
  /// Class Schedule grid from them, grouped by label into course rows.
  ///
  /// Runs automatically every time this screen opens (not just once), and
  /// re-runnable any time via the "Sync from Schedule" button. Matches
  /// rows by Course/Subject label rather than position, so a subject the
  /// student adds or edits from their own account shows up here the next
  /// time this screen loads without disturbing any other, differently
  /// named row the supervisor typed in by hand.
  ///
  /// Also removes rows for subjects the student has since deleted from
  /// their calendar. Each synced row remembers which rule label filled it
  /// in ([DtrClassScheduleEntry.sourceRuleLabel], persisted to Firestore
  /// with the rest of the row — no on-device storage involved) — if that
  /// label is no longer among the student's current rules, the row is
  /// removed automatically. A row typed in manually (never matched a
  /// rule) is never touched by this.
  Future<void> _syncFromRecurringSchedule({bool manual = false}) async {
    if (manual) setState(() => _syncingSchedule = true);
    final state = context.read<AppState>();
    final ownerNames = _scheduleOwnerNameCandidates(state);
    // Only rules added via "Add Subject" belong in this Class Schedule
    // table — plain "Add Schedule" entries (e.g. a general work shift) are
    // a different kind of thing and should never end up here, even though
    // they're the same underlying rule type under the hood.
    final rules = (await _loadAllRulesForStudent(
      state,
    )).where((r) => r.isSubject).toList();
    if (!mounted) return;
    if (manual) setState(() => _syncingSchedule = false);

    final currentLabels = rules.map((r) => r.label).toSet();

    // Every row this screen previously filled in from a rule remembers
    // that rule's label in [DtrClassScheduleEntry.sourceRuleLabel] (saved
    // to Firestore alongside the row itself — no local/device storage
    // involved). If that label is no longer among the student's current
    // rules, the subject was deleted from their calendar, so remove the
    // row here too. A row the supervisor typed in by hand has no
    // sourceRuleLabel and is never touched by this.
    final hadRemovals = _schedule.any(
      (r) =>
          r.sourceRuleLabel != null &&
          !currentLabels.contains(r.sourceRuleLabel),
    );
    if (hadRemovals) {
      setState(() {
        for (var i = _schedule.length - 1; i >= 0; i--) {
          final label = _schedule[i].sourceRuleLabel;
          if (label != null && !currentLabels.contains(label)) {
            for (final c in _scheduleCtrls[i]) {
              c.dispose();
            }
            _schedule.removeAt(i);
            _scheduleCtrls.removeAt(i);
          }
        }
        // Keep at least one row so the table never disappears entirely.
        if (_schedule.isEmpty) {
          _schedule.add(const DtrClassScheduleEntry());
          _scheduleCtrls.add(_controllersFor(const DtrClassScheduleEntry()));
        }
      });
    }

    if (rules.isEmpty) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No "Add Subject" entries found under any of: '
              '${ownerNames.map((n) => '"$n"').join(', ')}. '
              'If the student added one from their own account, check that '
              'account\'s exact name against this student\'s profile.',
            ),
            backgroundColor: AppTheme.blue500,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }
    final byLabel = <String, RecurringScheduleRule>{};
    final dayTexts = <String, Map<int, String>>{};
    for (final rule in rules) {
      byLabel[rule.label] = rule;
      (dayTexts[rule.label] ??= {})[rule.weekday] = rule.timeRange;
    }
    final labels = byLabel.keys.take(_maxScheduleRows).toList();

    // Matched by Course/Subject label rather than row position, so this
    // never overwrites a differently-named row the supervisor typed in by
    // hand — it only ever updates the row for that exact subject (or fills
    // it into an empty row / appends a new one). The automatic run still
    // skips a subject whose row is mid-edit — i.e. it already has a
    // different, non-empty course name — to avoid fighting the supervisor
    // while they're typing; the manual "Sync from Schedule" button always
    // overwrites, since that's an explicit request for the latest data.
    setState(() {
      for (final label in labels) {
        final rule = byLabel[label]!;
        final days = dayTexts[label]!;

        var idx = _schedule.indexWhere((r) => r.course == label);
        if (idx == -1) {
          idx = _schedule.indexWhere(
            (r) =>
                r.course.isEmpty &&
                r.units.isEmpty &&
                r.monday.isEmpty &&
                r.tuesday.isEmpty &&
                r.wednesday.isEmpty &&
                r.thursday.isEmpty &&
                r.friday.isEmpty &&
                r.saturday.isEmpty,
          );
        }
        if (idx == -1) {
          if (_schedule.length >= _maxScheduleRows) continue;
          _schedule.add(const DtrClassScheduleEntry());
          _scheduleCtrls.add(_controllersFor(const DtrClassScheduleEntry()));
          idx = _schedule.length - 1;
        }

        // Prefer the "Add Subject" units value when present; otherwise keep
        // whatever was already typed into the grid so plain "Add Schedule"
        // rules (which carry no units) don't wipe a manual entry.
        final units = rule.units.isNotEmpty ? rule.units : _schedule[idx].units;
        _schedule[idx] = DtrClassScheduleEntry(
          course: label,
          units: units,
          monday: days[DateTime.monday] ?? '',
          tuesday: days[DateTime.tuesday] ?? '',
          wednesday: days[DateTime.wednesday] ?? '',
          thursday: days[DateTime.thursday] ?? '',
          friday: days[DateTime.friday] ?? '',
          saturday: days[DateTime.saturday] ?? '',
          sourceRuleLabel: label,
        );
        _scheduleCtrls[idx][0].text = _schedule[idx].course;
        _scheduleCtrls[idx][1].text = _schedule[idx].units;
        _scheduleCtrls[idx][2].text = _schedule[idx].monday;
        _scheduleCtrls[idx][3].text = _schedule[idx].tuesday;
        _scheduleCtrls[idx][4].text = _schedule[idx].wednesday;
        _scheduleCtrls[idx][5].text = _schedule[idx].thursday;
        _scheduleCtrls[idx][6].text = _schedule[idx].friday;
        _scheduleCtrls[idx][7].text = _schedule[idx].saturday;
      }
    });
    if (manual) {
      // The button's job is "get me the latest schedule" as a whole — also
      // refresh the daily list above (which reads materialized calendar
      // events through a cache that doesn't invalidate on its own) so both
      // sections reflect the same up-to-date schedule together, instead of
      // only the Class Schedule table below updating.
      for (final name in ownerNames) {
        await context.read<ScheduleService>().refresh(name);
      }
      if (!mounted) return;
      final refreshedDays = _buildDaysFromAttendance(state);
      setState(() {
        for (var i = 0; i < _days.length; i++) {
          final oldDefault = _days[i].note ?? '';
          if (_noteCtrls[i].text == oldDefault) {
            _noteCtrls[i].text = refreshedDays[i].note ?? '';
          }
        }
        _days = refreshedDays;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Class Schedule synced.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _studentNameCtrl,
      _departmentCtrl,
      _monthCtrl,
      _studentSigCtrl,
      _supervisorCtrl,
      _approverCtrl,
      ..._noteCtrls,
    ]) {
      c.dispose();
    }
    for (final row in _scheduleCtrls) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  /// Fully automated: pulls this student's real clock-in/out attendance
  /// records (from your Attendance/DTR feature — [AppState.filteredAttendance])
  /// for the selected month and maps them onto the 31 fixed day rows, with
  /// no manual data entry needed. A student can clock in/out more than once
  /// a day, so every session for a given date is merged into that row:
  /// morning sessions fill AM In/Out, afternoon/evening sessions fill PM
  /// In/Out, and the hours across all of the day's sessions are summed.
  /// Days with no clock-in at all default to "Class Schedule" on weekdays
  /// and "Saturday"/"Sunday" on weekends, matching the official form's
  /// convention — everything is still editable afterward for corrections.
  List<DtrDayEntry> _buildDaysFromAttendance(AppState state) {
    const monthAbbr = [
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
    final prefix = '${monthAbbr[widget.month.month - 1]} ';
    final yearSuffix = ', ${widget.month.year}';

    // Group every clock-in/out session for this student in this month by
    // calendar day (a day can have more than one session).
    final sessionsByDay = <int, List<AttendanceRecord>>{};
    for (final r in state.filteredAttendance) {
      if (r.studentName != widget.student.name) continue;
      if (r.isArchived) continue;
      final date = r.date;
      if (!date.startsWith(prefix) || !date.endsWith(yearSuffix)) continue;
      final dayStr = date
          .substring(prefix.length, date.length - yearSuffix.length)
          .replaceAll(',', '')
          .trim();
      final day = int.tryParse(dayStr);
      if (day == null) continue;
      (sessionsByDay[day] ??= []).add(r);
    }

    // Group every task this student marked "Completed" this month by the
    // calendar day it was completed on — a finished task is itself an
    // accomplishment, so it drives that day's entry automatically when
    // there's no separate clock-in/out session already covering it.
    final tasksByDay = <int, List<Task>>{};
    for (final t in state.tasks) {
      if (t.isArchived || t.status != 'Completed') continue;
      final owner = t.assignedToName ?? '';
      if (owner != widget.student.name) continue;
      final completed = t.completedAt;
      if (completed == null) continue;
      if (!completed.startsWith(prefix) || !completed.endsWith(yearSuffix)) {
        continue;
      }
      final dayStr = completed
          .substring(prefix.length, completed.length - yearSuffix.length)
          .replaceAll(',', '')
          .trim();
      final day = int.tryParse(dayStr);
      if (day == null) continue;
      (tasksByDay[day] ??= []).add(t);
    }

    return List.generate(_daysInMonth, (i) {
      final day = i + 1;
      final sessions = sessionsByDay[day];
      final weekday = DateTime(
        widget.month.year,
        widget.month.month,
        day,
      ).weekday;
      final date = DateTime(widget.month.year, widget.month.month, day);

      if (sessions == null || sessions.isEmpty) {
        final completedTasks = tasksByDay[day];
        if (completedTasks != null && completedTasks.isNotEmpty) {
          return _entryFromCompletedTasks(day, date, weekday, completedTasks);
        }
        return DtrDayEntry(day: day, note: _defaultNoteFor(date, weekday));
      }

      // Sort sessions chronologically so AM/PM slots fill in order.
      sessions.sort(
        (a, b) => (_hour24(a.timeIn) ?? 0).compareTo(_hour24(b.timeIn) ?? 0),
      );

      String? amIn, amOut, pmIn, pmOut;
      var totalHours = 0.0;
      var hasOngoing = false;

      for (final s in sessions) {
        totalHours += s.totalHours ?? 0;
        if (s.isActive) hasOngoing = true;
        final inIsPm = _isPm(s.timeIn);
        if (!inIsPm && amIn == null) {
          amIn = s.timeIn;
          amOut = s.timeOut;
        } else if (inIsPm && pmIn == null) {
          pmIn = s.timeIn;
          pmOut = s.timeOut;
        } else {
          // Extra session in an already-filled slot: push into the other
          // half if it's free, otherwise fold its time into the existing
          // out-time so no data is silently dropped.
          if (!inIsPm) {
            amOut = s.timeOut ?? amOut;
          } else {
            pmOut = s.timeOut ?? pmOut;
          }
        }
      }

      return DtrDayEntry(
        day: day,
        amIn: amIn,
        amOut: amOut,
        pmIn: pmIn,
        pmOut: pmOut,
        totalHours: totalHours == 0 ? null : totalHours,
        note: hasOngoing ? 'Present (ongoing)' : 'Present',
      );
    });
  }

  /// Builds a day's entry from the task(s) the student completed that day,
  /// when there's no separate clock-in/out session for the day.
  ///
  /// Validity mirrors the official DTR's own convention: a student isn't
  /// supposed to be working on an official holiday or a weekend, so a task
  /// completed then is flagged [DtrDayEntry.isInvalid] rather than silently
  /// credited — the supervisor still sees it and can correct it, but it
  /// won't count toward hours until they do. On a normal working day, the
  /// student's recurring schedule rule for that weekday (if one has been
  /// set up via "Add Schedule"/"Add Subject") supplies the AM/PM in/out
  /// times and hours; if no rule exists yet for that day,
  /// [DtrDayEntry.needsVerification] is set instead so the times are left
  /// blank for manual entry rather than guessed.
  DtrDayEntry _entryFromCompletedTasks(
    int day,
    DateTime date,
    int weekday,
    List<Task> completedTasks,
  ) {
    final state = context.read<AppState>();
    final titles = completedTasks
        .map((t) => t.title.trim())
        .where((t) => t.isNotEmpty)
        .join('; ');
    final accomplishment = titles.isEmpty ? 'Task completed' : titles;

    final isWeekend =
        weekday == DateTime.saturday || weekday == DateTime.sunday;
    final isHoliday = state.isHoliday(date);
    if (isHoliday || isWeekend) {
      final reason = isHoliday
          ? 'Holiday'
          : (weekday == DateTime.saturday ? 'Saturday' : 'Sunday');
      return DtrDayEntry(
        day: day,
        note:
            'Invalid — task completed on a non-working day ($reason): $accomplishment',
        isInvalid: true,
      );
    }

    RecurringScheduleRule? rule;
    for (final r in _rules) {
      if (r.weekday == weekday) {
        rule = r;
        break;
      }
    }
    if (rule == null) {
      return DtrDayEntry(
        day: day,
        note: '$accomplishment (schedule not set — please verify time in/out)',
        needsVerification: true,
      );
    }

    final startMinutes = rule.startTime.hour * 60 + rule.startTime.minute;
    final noon = 12 * 60;
    final isStartPm = startMinutes >= noon;
    final hours =
        ((rule.endTime.hour * 60 + rule.endTime.minute) - startMinutes) / 60.0;

    return DtrDayEntry(
      day: day,
      amIn: isStartPm ? null : RecurringScheduleRule.formatTime(rule.startTime),
      amOut: isStartPm ? null : RecurringScheduleRule.formatTime(rule.endTime),
      pmIn: isStartPm ? RecurringScheduleRule.formatTime(rule.startTime) : null,
      pmOut: isStartPm ? RecurringScheduleRule.formatTime(rule.endTime) : null,
      totalHours: hours > 0 ? hours : null,
      note: accomplishment,
    );
  }

  /// Default "Accomplishment/s" label for a day with no clock-in, in order
  /// of priority: official holiday (fixed, never editable by the student) →
  /// weekend → the student's recurring weekly schedule (set up on their
  /// Schedule screen) → the original blanket "Class Schedule" fallback for
  /// students who haven't set one up yet.
  /// Extracts the rule id embedded in a materialized calendar event's id
  /// (`rule_<ruleId>_<yyyymmdd>`, see [_eventIdFor] in the calendar
  /// screen), or null for an event that isn't rule-generated at all (a
  /// plain one-off "Add Event", or malformed/legacy data).
  String? _ruleIdFromEventId(String id) {
    if (!id.startsWith('rule_')) return null;
    final withoutPrefix = id.substring('rule_'.length);
    final lastUnderscore = withoutPrefix.lastIndexOf('_');
    if (lastUnderscore == -1) return null;
    return withoutPrefix.substring(0, lastUnderscore);
  }

  String _defaultNoteFor(DateTime date, int weekday) {
    final state = context.read<AppState>();
    if (state.isHoliday(date)) return 'Holiday';
    if (weekday == DateTime.saturday) return 'Saturday';
    if (weekday == DateTime.sunday) return 'Sunday';

    // A class subject (from "Add Subject") isn't work the student did that
    // day — only a general "Add Schedule" entry (an actual work shift)
    // should ever fill in as the day's default accomplishment. Both kinds
    // of rule generate identical-looking calendar events, so the only way
    // to tell them apart here is by looking each event's rule id up
    // against the subject rules loaded into [_rules].
    final subjectRuleIds = _rules
        .where((r) => r.isSubject)
        .map((r) => r.id)
        .toSet();

    final scheduleService = context.read<ScheduleService>();
    for (final ownerName in _scheduleOwnerNameCandidates(state)) {
      final todaysEvents = scheduleService
          .eventsForDay(ownerName, date)
          .where((e) => !subjectRuleIds.contains(_ruleIdFromEventId(e.id)))
          .toList();
      if (todaysEvents.isNotEmpty) {
        final e = todaysEvents.first;
        return '${e.title} (${e.details})';
      }
    }
    // No recurring weekly (non-subject) schedule entered for this student
    // at all yet — fall back to the original convention so nothing
    // changes for them until they set one up.
    final hasAnySchedule = _scheduleOwnerNameCandidates(state).any(
      (name) => scheduleService
          .eventsFor(name)
          .any(
            (e) =>
                e.id.startsWith('rule_') &&
                !subjectRuleIds.contains(_ruleIdFromEventId(e.id)),
          ),
    );
    return hasAnySchedule ? '' : 'Class Schedule';
  }

  /// Parses a "h:mm AM/PM" time string (the format produced by
  /// [AppState.clockIn]/[AppState.clockOut]) into a 24-hour hour value, for
  /// chronological sorting of a day's sessions.
  int? _hour24(String time) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(time.trim());
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final isPm = match.group(3)!.toUpperCase() == 'PM';
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    return hour;
  }

  bool _isPm(String time) => (_hour24(time) ?? 0) >= 12;

  /// Builds the report data from the current form state, persisting any
  /// schedule edits along the way. Shared by "Generate & Download" and
  /// "Send to Head" so both work off the exact same data.
  Future<DtrAccomplishmentReportData> _buildReportData() async {
    // Pull the latest text typed into the note / schedule fields.
    final days = List.generate(
      _days.length,
      (i) => _days[i].copyWith(note: _noteCtrls[i].text),
    );
    final schedule = List.generate(_scheduleCtrls.length, (i) {
      final c = _scheduleCtrls[i];
      final course = c[0].text;
      // If the supervisor retyped the Course/Subject name away from what
      // was synced in, treat it as a manual row from now on so it's never
      // auto-removed just because the original rule later disappears.
      final sourceRuleLabel = course == _schedule[i].sourceRuleLabel
          ? _schedule[i].sourceRuleLabel
          : null;
      return DtrClassScheduleEntry(
        course: course,
        units: c[1].text,
        monday: c[2].text,
        tuesday: c[3].text,
        wednesday: c[4].text,
        thursday: c[5].text,
        friday: c[6].text,
        saturday: c[7].text,
        sourceRuleLabel: sourceRuleLabel,
      );
    }).where((r) => r.course.trim().isNotEmpty).toList();

    // Remember the (possibly edited) class schedule for next time, so the
    // supervisor doesn't have to re-type it every month.
    final state = context.read<AppState>();
    await state.saveClassScheduleForStudent(
      widget.student.id,
      widget.student.name,
      List.generate(
        schedule.length,
        (i) => ClassScheduleEntry(
          id: 'cs_${widget.student.id}_$i',
          studentId: widget.student.id,
          studentName: widget.student.name,
          course: schedule[i].course,
          units: schedule[i].units,
          monday: schedule[i].monday,
          tuesday: schedule[i].tuesday,
          wednesday: schedule[i].wednesday,
          thursday: schedule[i].thursday,
          friday: schedule[i].friday,
          saturday: schedule[i].saturday,
          sourceRuleLabel: schedule[i].sourceRuleLabel,
        ),
      ),
    );

    return DtrAccomplishmentReportData(
      studentId: widget.student.id,
      studentName: _studentNameCtrl.text.trim(),
      department: _departmentCtrl.text.trim(),
      studentSignatureName: _studentSigCtrl.text.trim(),
      supervisorName: _supervisorCtrl.text.trim(),
      approverName: _approverCtrl.text.trim(),
      monthYearLabel: _monthYearLabel,
      days: days,
      classSchedule: schedule,
    );
  }

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generating = true);

    final data = await _buildReportData();

    try {
      final doc = await const DtrAccomplishmentReportDocumentService()
          .generateDtrAccomplishmentReport(data: data);
      final bytes = doc.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to generate the report document.');
      }

      if (kIsWeb) {
        web_download.WebDownloadUtils.downloadBytes(doc.fileName, bytes);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Downloading ${doc.fileName}...'),
            backgroundColor: AppTheme.emerald500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      } else {
        final uri = Uri.dataFromBytes(
          bytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          parameters: {'filename': doc.fileName},
        );
        final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!opened)
          throw Exception('The browser could not open the document.');
        messenger.showSnackBar(
          SnackBar(
            content: Text('Opening ${doc.fileName}...'),
            backgroundColor: AppTheme.emerald500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not generate document: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _sendToHead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Send to Head?'),
        content: Text(
          'This will send ${widget.student.name}\'s DTR/Accomplishment report '
          '(${_months[widget.month.month - 1]} ${widget.month.year}) to the Head.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.maroon,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    setState(() => _sendingToHead = true);

    final data = await _buildReportData();

    try {
      final doc = await const DtrAccomplishmentReportDocumentService()
          .generateDtrAccomplishmentReport(data: data);
      final bytes = doc.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to generate the report document.');
      }

      final ok = await state.sendDtrReportToHead(
        studentId: widget.student.id,
        studentName: widget.student.name,
        monthLabel: '${_months[widget.month.month - 1]} ${widget.month.year}',
        bytes: bytes,
        fileName: doc.fileName,
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'DTR/Accomplishment report sent to Head'
                  : 'Failed to send report to Head',
            ),
            backgroundColor: ok ? AppTheme.emerald500 : AppTheme.red500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not send document: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingToHead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 14.0 : 24.0;

    // Laid out like the Applicant Screening form: an official header card,
    // a live summary, numbered sections mirroring the printed report, and
    // the sign-off names, with the actions at the foot.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // In-page header (no separate route/AppBar) — stays inside the
        // parent screen so the sidebar and top bar remain visible.
        Padding(
          padding: EdgeInsets.fromLTRB(hPad - 8, isMobile ? 10 : 16, hPad, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppTheme.slate700,
                tooltip: 'Back to Students',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DTR / Accomplishment Report',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      '${widget.student.name} · '
                      '${_months[widget.month.month - 1]} ${widget.month.year}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 28),
            children: [
              _officialHeader(isMobile),
              const SizedBox(height: 18),
              _liveSummary(isMobile),
              const SizedBox(height: 18),
              _section(
                number: 1,
                icon: Icons.badge_outlined,
                title: 'Report Details',
                isMobile: isMobile,
                child: _grid(isMobile ? 1 : 3, [
                  _input('Name of Student Assistant', _studentNameCtrl),
                  _input('Assigned College/Department', _departmentCtrl),
                  _input('For the Month/Year', _monthCtrl, readOnly: true),
                ]),
              ),
              const SizedBox(height: 18),
              _section(
                number: 2,
                icon: Icons.access_time_filled_rounded,
                title: 'Daily Time Record',
                description:
                    'Pulled from this student\'s clock-in/out records for the '
                    'month. Days without one default to "Class Schedule", '
                    '"Saturday" or "Sunday". Edit anything before generating.',
                isMobile: isMobile,
                child: _dtrTable(isMobile),
              ),
              const SizedBox(height: 18),
              _section(
                number: 3,
                icon: Icons.calendar_month_outlined,
                title: 'Class Schedule',
                description:
                    'Filled from the student\'s saved class schedule, or their '
                    'subjects on the Schedule/Calendar screen. Edits are '
                    'remembered for next month. Up to 12 subjects.',
                isMobile: isMobile,
                trailing: TextButton.icon(
                  onPressed: _syncingSchedule
                      ? null
                      : () => _syncFromRecurringSchedule(manual: true),
                  icon: _syncingSchedule
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.maroon,
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 15),
                  label: Text(isMobile ? 'Sync' : 'Sync from Schedule'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.maroon,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
                child: _scheduleTable(isMobile),
              ),
              const SizedBox(height: 18),
              _section(
                number: 4,
                icon: Icons.draw_outlined,
                title: 'Sign-off',
                description: 'Printed above each signature line on the report.',
                isMobile: isMobile,
                child: _grid(isMobile ? 1 : 3, [
                  _signatory(
                    'Prepared by',
                    'Student Assistant',
                    _studentSigCtrl,
                  ),
                  _signatory(
                    'Verified and checked by',
                    'Immediate Supervisor',
                    _supervisorCtrl,
                  ),
                  _signatory(
                    'Approved',
                    'Head, Student Assistantship',
                    _approverCtrl,
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              _actions(isMobile),
            ],
          ),
        ),
      ],
    );
  }

  String get _monthYearLabel =>
      '${_months[widget.month.month - 1]} 01–$_daysInMonth, '
      '${widget.month.year}';

  Widget _officialHeader(bool isMobile) {
    final photoSize = isMobile ? 70.0 : 90.0;
    final photo = Container(
      width: photoSize,
      height: photoSize,
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      clipBehavior: Clip.antiAlias,
      child: _studentPhoto(photoSize),
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REPUBLIC OF THE PHILIPPINES',
          style: TextStyle(
            fontSize: isMobile ? 9 : 10,
            color: AppTheme.slate500,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          'MARINDUQUE STATE UNIVERSITY',
          style: TextStyle(
            fontSize: isMobile ? 14.5 : 18,
            fontWeight: FontWeight.w900,
            color: AppTheme.slate900,
            letterSpacing: -0.3,
          ),
        ),
        Text(
          isMobile
              ? 'OFFICE OF THE VP FOR STUDENT AFFAIRS & SERVICES'
              : 'OFFICE OF THE VICE PRESIDENT FOR STUDENT AFFAIRS & SERVICES',
          style: TextStyle(
            fontSize: isMobile ? 9.5 : 10.5,
            color: AppTheme.maroon,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        if (!isMobile)
          const Text(
            'Student Auxiliary & Employment Extension Division (SAEED)',
            style: TextStyle(fontSize: 10, color: AppTheme.slate500),
          ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // On a phone the long agency title needs the full width, so the
          // photo moves below it, beside the student's name.
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppLogo(size: 44),
                const SizedBox(width: 10),
                Expanded(child: titleBlock),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                photo,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.student.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _monthYearLabel,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else
            Row(
              children: [
                const AppLogo(size: 60),
                const SizedBox(width: 14),
                Expanded(child: titleBlock),
                photo,
              ],
            ),
          SizedBox(height: isMobile ? 14 : 18),
          Container(height: 1, color: AppTheme.slate200),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.maroon50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'STUDENT ASSISTANT\'S DTR / ACCOMPLISHMENT REPORT / CLASS SCHEDULE',
              style: TextStyle(
                fontSize: isMobile ? 11.5 : 13.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.maroon,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The student's profile photo for the 2x2 box, from their roster entry
  /// or, failing that, their linked account.
  String? _studentAvatarUrl() {
    final own = widget.student.avatar;
    if (own != null && own.isNotEmpty) return own;
    final email = widget.student.email.toLowerCase();
    for (final user in context.read<AppState>().users) {
      final linked = widget.student.userId != null
          ? user.id == widget.student.userId
          : email.isNotEmpty && user.email.toLowerCase() == email;
      if (linked && (user.avatar ?? '').isNotEmpty) return user.avatar;
    }
    return null;
  }

  Widget _studentPhoto(double size) {
    Widget initials() => Container(
      color: AppTheme.maroon50,
      alignment: Alignment.center,
      child: Text(
        widget.student.initials,
        style: TextStyle(
          fontSize: size * 0.3,
          fontWeight: FontWeight.w800,
          color: AppTheme.maroon,
        ),
      ),
    );

    final url = _studentAvatarUrl();
    if (url == null) return initials();
    if (url.startsWith('data:image')) {
      try {
        final comma = url.indexOf(',');
        final bytes = base64Decode(
          url.substring(comma + 1).replaceAll(RegExp(r'\s+'), ''),
        );
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => initials(),
        );
      } catch (_) {
        return initials();
      }
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => initials(),
    );
  }

  /// Hours logged this month against the payroll's 25–40 hour monthly
  /// range, recomputed as days are edited — the report's counterpart of the
  /// screening form's live score. Kept light (a white card, color only in
  /// the ring and figures) to match the app's compact headers.
  Widget _liveSummary(bool isMobile) {
    final state = context.read<AppState>();
    var totalHours = 0.0;
    var presentDays = 0;
    var needsReview = 0;
    var holidays = 0;
    for (final d in _days) {
      final date = DateTime(widget.month.year, widget.month.month, d.day);
      totalHours += d.totalHours ?? 0;
      if ((d.totalHours ?? 0) > 0) presentDays++;
      if (d.isInvalid || d.needsVerification) needsReview++;
      if (state.isHoliday(date)) holidays++;
    }

    const minimum = PayrollRecord.minimumMonthlyHours;
    const maximum = PayrollRecord.maximumMonthlyHours;
    final (statusColor, status) = totalHours < minimum
        ? (
            AppTheme.amber500,
            'Below the ${minimum.toStringAsFixed(0)}-hour monthly minimum',
          )
        : totalHours > maximum
        ? (
            AppTheme.maroon,
            'Over the ${maximum.toStringAsFixed(0)}-hour cap — only '
                '${maximum.toStringAsFixed(0)} hrs are payable',
          )
        : (AppTheme.emerald500, 'Within the payable 25–40 hour range');

    final ringSize = isMobile ? 48.0 : 56.0;
    final ring = SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: (totalHours / maximum).clamp(0.0, 1.0),
              strokeWidth: 5,
              backgroundColor: AppTheme.slate100,
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
          Text(
            totalHours.toStringAsFixed(totalHours % 1 == 0 ? 0 : 1),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppTheme.slate900,
            ),
          ),
        ],
      ),
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Hours This Month',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: AppTheme.slate900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          status,
          style: TextStyle(
            color: statusColor,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        const Text(
          'Updates as you edit each day',
          style: TextStyle(color: AppTheme.slate400, fontSize: 11),
        ),
      ],
    );
    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _summaryPill('$presentDays', 'Days present', AppTheme.emerald500),
        _summaryPill(
          '$needsReview',
          'Need review',
          needsReview > 0 ? AppTheme.amber500 : AppTheme.slate500,
        ),
        _summaryPill('$holidays', 'Holidays', AppTheme.maroon),
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 14 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ring,
                    const SizedBox(width: 12),
                    Expanded(child: label),
                  ],
                ),
                const SizedBox(height: 12),
                pills,
              ],
            )
          : Row(
              children: [
                ring,
                const SizedBox(width: 16),
                Expanded(child: label),
                pills,
              ],
            ),
    );
  }

  Widget _summaryPill(String value, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.slate500,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  /// A numbered form section, styled after the Applicant Screening form.
  Widget _section({
    required int number,
    required IconData icon,
    required String title,
    required Widget child,
    required bool isMobile,
    String? description,
    Widget? trailing,
  }) => Container(
    padding: EdgeInsets.all(isMobile ? 14 : 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.slate200),
      boxShadow: [
        BoxShadow(
          color: AppTheme.slate900.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppTheme.maroon,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 16, color: AppTheme.maroon),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.slate500,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  /// Lays [fields] out [columns] to a row, each the same width.
  Widget _grid(int columns, List<Widget> fields) => LayoutBuilder(
    builder: (context, constraints) {
      final width = ((constraints.maxWidth - (columns - 1) * 12) / columns)
          .floorToDouble();
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final field in fields) SizedBox(width: width, child: field),
        ],
      );
    },
  );

  Widget _input(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) => TextField(
    controller: controller,
    readOnly: readOnly,
    style: TextStyle(color: readOnly ? AppTheme.slate500 : null),
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: AppTheme.slate50,
      suffixIcon: readOnly
          ? const Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppTheme.slate300,
            )
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _signatory(
    String caption,
    String role,
    TextEditingController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Container(width: 3, height: 12, color: AppTheme.maroon),
          const SizedBox(width: 6),
          Text(
            caption.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _input('Printed Name', controller),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          role,
          style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
      ),
    ],
  );

  Widget _actions(bool isMobile) {
    Widget spinner(Color color) => SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
    final generate = FilledButton.icon(
      onPressed: _generating ? null : _generate,
      icon: _generating
          ? spinner(Colors.white)
          : const Icon(Icons.download_rounded, size: 16),
      label: Text(_generating ? 'Generating...' : 'Generate & Download'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.maroon,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    final send = OutlinedButton.icon(
      onPressed: _sendingToHead ? null : _sendToHead,
      icon: _sendingToHead
          ? spinner(AppTheme.maroon)
          : const Icon(Icons.send_rounded, size: 16),
      label: Text(_sendingToHead ? 'Sending...' : 'Send to Head'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.maroon,
        side: const BorderSide(color: AppTheme.maroon200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    final back = TextButton(
      onPressed: widget.onBack,
      child: const Text('Back to Students'),
    );
    final canSend = _isSupervisor(context.read<AppState>());

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          generate,
          if (canSend) ...[const SizedBox(height: 10), send],
          back,
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [back, if (canSend) send, generate],
    );
  }

  // ── Daily Time Record table — modernized card-style grid: a tinted,
  // sticky-feeling header, soft zebra striping, rounded "chip" date badges
  // and bordered (not flat-filled) fields so it reads as a clean data grid
  // rather than a form. Maroon is reserved for weekend/holiday emphasis and
  // the "Hrs" column so the eye lands on what matters.

  static const List<double> _dtrColWidths = [52, 74, 74, 74, 74, 64, 230];
  static const _weekdayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  /// Whether [date] should render with the same maroon weekend/holiday
  /// emphasis used by the Schedule calendar's `weekendTextStyle`.
  bool _isDtrSpecialDay(DateTime date) {
    final state = context.read<AppState>();
    return state.isHoliday(date) ||
        date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
  }

  /// Minimum width the "Accomplishment/s" column needs to stay readable
  /// (not scrunched) — below this, the table falls back to a horizontally
  /// scrollable fixed-width layout instead of squeezing everything.
  static const double _dtrMinAccWidth = 220;

  Widget _dtrTable(bool isMobile) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_days.length, (i) => _dtrMobileCard(i)),
      );
    }

    // Everything except the "Accomplishment/s" column has a fixed,
    // content-driven width — that column absorbs whatever room is left so
    // the card always fills the section instead of leaving a dead gap on
    // the right when the window is wide.
    final fixedWidth = _dtrColWidths.take(6).reduce((a, b) => a + b);
    // Row horizontal padding (8 * 2) + a little breathing room for dividers.
    const chromeWidth = 8.0 * 2 + 12;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          // No shadow: this grid already sits inside the section card, and
          // a second drop shadow just muddies the edge between them.
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.slate200),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth - fixedWidth - chromeWidth;
              final fitsFlexibly = available >= _dtrMinAccWidth;

              final table = Column(
                children: [
                  _dtrGroupHeaderRow(flexible: fitsFlexibly),
                  _dtrHeaderRow(flexible: fitsFlexibly),
                  ...List.generate(
                    _days.length,
                    (i) => _dtrRow(i, flexible: fitsFlexibly),
                  ),
                ],
              );

              if (fitsFlexibly) {
                // Enough room: let the accomplishment column stretch to
                // fill the card, so no space goes to waste on the right.
                return SizedBox(width: double.infinity, child: table);
              }

              // Too narrow (e.g. a small laptop split-screen): keep the
              // original fixed-width, horizontally scrollable layout so
              // nothing gets clipped or crushed.
              final totalWidth = fixedWidth + _dtrColWidths[6] + chromeWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: totalWidth, child: table),
              );
            },
          ),
        ),
      ],
    );
  }

  /// One day's entry as a self-contained card, entirely within the phone's
  /// width — no horizontal scrolling, nothing clipped at the screen edge.
  /// Morning/Afternoon in-out pairs sit two-per-row (they always fit),
  /// and the notes field runs full width beneath.
  Widget _dtrMobileCard(int i) {
    final d = _days[i];
    final date = DateTime(widget.month.year, widget.month.month, d.day);
    final special = _isDtrSpecialDay(date);
    final invalid = d.isInvalid;
    final needsVerification = d.needsVerification;
    final dateColor = invalid
        ? AppTheme.red500
        : (special ? AppTheme.maroon : AppTheme.slate800);
    final accentColor = invalid
        ? AppTheme.red500
        : (needsVerification
              ? AppTheme.amber500
              : (special ? AppTheme.maroon : null));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            // Left inset leaves room for the attention rail below.
            padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: special ? AppTheme.maroon50 : AppTheme.slate50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: special
                              ? AppTheme.maroon100
                              : AppTheme.slate100,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: dateColor,
                            ),
                          ),
                          Text(
                            _weekdayAbbr[date.weekday - 1],
                            style: TextStyle(
                              fontSize: 8.5,
                              color: special
                                  ? AppTheme.maroonLight
                                  : AppTheme.slate400,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (invalid)
                      _dtrStatusChip(
                        Icons.error_outline_rounded,
                        'Needs fix',
                        AppTheme.red500,
                      )
                    else if (needsVerification)
                      _dtrStatusChip(
                        Icons.warning_amber_rounded,
                        'Verify',
                        AppTheme.amber500,
                      )
                    else if (special)
                      _dtrStatusChip(
                        Icons.celebration_rounded,
                        'Non-working day',
                        AppTheme.maroon,
                      ),
                    const Spacer(),
                    _dtrHoursPill(
                      d.totalHours?.toStringAsFixed(1),
                      (v) => setState(
                        () => _days[i] = d.copyWith(
                          totalHours: double.tryParse(v),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _dtrSessionLabel('MORNING'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _dtrMobileField(
                        'In',
                        d.amIn,
                        (v) => setState(() => _days[i] = d.copyWith(amIn: v)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dtrMobileField(
                        'Out',
                        d.amOut,
                        (v) => setState(() => _days[i] = d.copyWith(amOut: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _dtrSessionLabel('AFTERNOON'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _dtrMobileField(
                        'In',
                        d.pmIn,
                        (v) => setState(() => _days[i] = d.copyWith(pmIn: v)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dtrMobileField(
                        'Out',
                        d.pmOut,
                        (v) => setState(() => _days[i] = d.copyWith(pmOut: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notes_rounded,
                        size: 12,
                        color: AppTheme.slate400,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'ACCOMPLISHMENT/S',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate400,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                TextField(
                  controller: _noteCtrls[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: dateColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: invalid
                        ? AppTheme.red50
                        : (needsVerification
                              ? AppTheme.amber50
                              : AppTheme.slate50),
                    hintText: 'What did they work on?',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppTheme.maroon,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Attention rail: only weekends/holidays and rows that need a
          // second look get one, so scanning the list stays cheap.
          if (accentColor != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: accentColor),
            ),
        ],
      ),
    );
  }

  Widget _dtrStatusChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _dtrSessionLabel(String label) => Row(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.maroon.withValues(alpha: 0.18)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: AppTheme.maroon,
            letterSpacing: 0.6,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 1, color: AppTheme.slate100)),
    ],
  );

  Widget _dtrMobileField(
    String label,
    String? initial,
    ValueChanged<String> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate400,
            letterSpacing: 0.3,
          ),
        ),
      ),
      TextField(
        controller: TextEditingController(text: initial ?? ''),
        onChanged: onChanged,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.slate700,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.slate50,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          hintText: '—',
          hintStyle: const TextStyle(
            color: AppTheme.slate300,
            fontWeight: FontWeight.w600,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.maroon, width: 1.4),
          ),
        ),
      ),
    ],
  );

  /// Thin uppercase "MORNING" / "AFTERNOON" band spanning the In/Out pairs
  /// beneath it, so the grid reads as two clear sessions instead of four
  /// loose columns.
  Widget _dtrGroupHeaderRow({bool flexible = false}) => Container(
    color: AppTheme.slate50,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    child: Row(
      children: [
        SizedBox(width: _dtrColWidths[0]),
        _groupLabel('MORNING', _dtrColWidths[1] + _dtrColWidths[2]),
        _dtrVDivider(),
        _groupLabel('AFTERNOON', _dtrColWidths[3] + _dtrColWidths[4]),
        _dtrVDivider(),
        SizedBox(width: _dtrColWidths[5]),
        _dtrVDivider(),
        if (flexible)
          const Expanded(child: SizedBox())
        else
          SizedBox(width: _dtrColWidths[6]),
      ],
    ),
  );

  Widget _groupLabel(String label, double width) => SizedBox(
    width: width,
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.maroon50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.maroon,
            letterSpacing: 0.8,
          ),
        ),
      ),
    ),
  );

  Widget _dtrVDivider() => const SizedBox(
    width: 1,
    height: 14,
    child: ColoredBox(color: AppTheme.slate200),
  );

  Widget _dtrHeaderRow({bool flexible = false}) => Container(
    decoration: const BoxDecoration(
      color: AppTheme.slate50,
      border: Border(bottom: BorderSide(color: AppTheme.slate200, width: 1.2)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
    child: Row(
      children: [
        _headerCell('Date', _dtrColWidths[0]),
        _headerCell('In', _dtrColWidths[1]),
        _headerCell('Out', _dtrColWidths[2]),
        _headerCell('In', _dtrColWidths[3]),
        _headerCell('Out', _dtrColWidths[4]),
        _headerCell('Hrs', _dtrColWidths[5]),
        _headerCell(
          'Accomplishment/s',
          _dtrColWidths[6],
          alignStart: true,
          icon: Icons.notes_rounded,
          flexible: flexible,
        ),
      ],
    ),
  );

  Widget _headerCell(
    String label,
    double width, {
    bool alignStart = false,
    IconData? icon,
    bool flexible = false,
  }) {
    final content = Row(
      mainAxisAlignment: alignStart
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: AppTheme.slate400),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: alignStart ? TextAlign.start : TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
    if (flexible) {
      return Expanded(
        child: Padding(padding: const EdgeInsets.only(left: 6), child: content),
      );
    }
    return SizedBox(width: width, child: content);
  }

  Widget _dtrRow(int i, {bool flexible = false}) {
    final d = _days[i];
    final date = DateTime(widget.month.year, widget.month.month, d.day);
    final special = _isDtrSpecialDay(date);
    final invalid = d.isInvalid;
    final needsVerification = d.needsVerification;
    final dateColor = invalid
        ? AppTheme.red500
        : (special ? AppTheme.maroon : AppTheme.slate800);
    final isLast = i == _days.length - 1;
    final rowColor = invalid
        ? AppTheme.red50
        : (needsVerification
              ? AppTheme.amber50
              : (special
                    ? AppTheme.maroon.withValues(alpha: 0.03)
                    : Colors.white));

    return Container(
      decoration: BoxDecoration(
        color: rowColor,
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppTheme.slate100)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _dtrColWidths[0],
            child: Center(
              child: Container(
                width: 36,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: special ? AppTheme.maroon50 : AppTheme.slate50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: special ? AppTheme.maroon100 : AppTheme.slate100,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: dateColor,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _weekdayAbbr[date.weekday - 1],
                      style: TextStyle(
                        fontSize: 8.5,
                        color: special
                            ? AppTheme.maroonLight
                            : AppTheme.slate400,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _dtrCompactField(
            _dtrColWidths[1],
            d.amIn,
            (v) => setState(() => _days[i] = d.copyWith(amIn: v)),
          ),
          _dtrCompactField(
            _dtrColWidths[2],
            d.amOut,
            (v) => setState(() => _days[i] = d.copyWith(amOut: v)),
          ),
          _dtrCompactField(
            _dtrColWidths[3],
            d.pmIn,
            (v) => setState(() => _days[i] = d.copyWith(pmIn: v)),
          ),
          _dtrCompactField(
            _dtrColWidths[4],
            d.pmOut,
            (v) => setState(() => _days[i] = d.copyWith(pmOut: v)),
          ),
          SizedBox(
            width: _dtrColWidths[5],
            child: Center(
              child: _dtrHoursPill(
                d.totalHours?.toStringAsFixed(1),
                (v) => setState(
                  () => _days[i] = d.copyWith(totalHours: double.tryParse(v)),
                ),
              ),
            ),
          ),
          _buildNoteField(
            i: i,
            width: _dtrColWidths[6],
            flexible: flexible,
            dateColor: dateColor,
            invalid: invalid,
            needsVerification: needsVerification,
          ),
        ],
      ),
    );
  }

  /// The "Accomplishment/s" note field — either fixed-width (narrow-screen
  /// fallback) or stretched via [Expanded] to fill the card's remaining
  /// width, so wide screens don't leave a blank strip on the right.
  Widget _buildNoteField({
    required int i,
    required double width,
    required bool flexible,
    required Color dateColor,
    required bool invalid,
    required bool needsVerification,
  }) {
    final field = Padding(
      padding: const EdgeInsets.only(left: 6),
      child: TextField(
        controller: _noteCtrls[i],
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: dateColor,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: invalid
              ? AppTheme.red50
              : (needsVerification ? AppTheme.amber50 : AppTheme.slate50),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          prefixIcon: invalid
              ? const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppTheme.red500,
                )
              : (needsVerification
                    ? const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: AppTheme.amber500,
                      )
                    : null),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.maroon, width: 1.4),
          ),
        ),
      ),
    );
    if (flexible) return Expanded(child: field);
    return SizedBox(width: width, child: field);
  }

  Widget _dtrCompactField(
    double width,
    String? initial,
    ValueChanged<String> onChanged,
  ) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextField(
        controller: TextEditingController(text: initial ?? ''),
        onChanged: onChanged,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.slate700,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.slate50,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          hintText: '—',
          hintStyle: const TextStyle(
            color: AppTheme.slate300,
            fontWeight: FontWeight.w600,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.maroon, width: 1.4),
          ),
        ),
      ),
    ),
  );

  /// The "Hrs" cell rendered as a small pill rather than a plain boxed
  /// field, so the one number that summarizes the whole row visually
  /// stands apart from the raw in/out times either side of it.
  Widget _dtrHoursPill(String? initial, ValueChanged<String> onChanged) =>
      Container(
        width: 52,
        decoration: BoxDecoration(
          color: AppTheme.maroon.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: TextField(
          controller: TextEditingController(text: initial ?? ''),
          onChanged: onChanged,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.maroon,
          ),
          decoration: const InputDecoration(
            isDense: true,
            filled: false,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            border: InputBorder.none,
            hintText: '—',
            hintStyle: TextStyle(
              color: AppTheme.maroonLight,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

  static const _scheduleDayLabels = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];
  static const _scheduleDayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  Widget _scheduleTable(bool isMobile) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(
            _scheduleCtrls.length,
            (i) => _scheduleMobileCard(i),
          ),
          const SizedBox(height: 4),
          _scheduleAddRow(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 14,
            headingRowColor: WidgetStateProperty.all(AppTheme.slate50),
            columns: const [
              DataColumn(label: Text('Course / Subject')),
              DataColumn(label: Text('Units')),
              DataColumn(label: Text('Monday')),
              DataColumn(label: Text('Tuesday')),
              DataColumn(label: Text('Wednesday')),
              DataColumn(label: Text('Thursday')),
              DataColumn(label: Text('Friday')),
              DataColumn(label: Text('Saturday')),
              DataColumn(label: Text('')),
            ],
            rows: List.generate(_scheduleCtrls.length, (i) {
              final ctrls = _scheduleCtrls[i];
              return DataRow(
                cells: [
                  ...List.generate(8, (j) {
                    final width = j == 0 ? 140.0 : (j == 1 ? 56.0 : 110.0);
                    return DataCell(
                      SizedBox(
                        width: width,
                        child: TextField(
                          controller: ctrls[j],
                          style: const TextStyle(fontSize: 12.5),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    );
                  }),
                  DataCell(
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppTheme.slate400,
                      ),
                      tooltip: 'Remove subject',
                      onPressed: () => _removeScheduleRow(i),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 10),
        _scheduleAddRow(),
      ],
    );
  }

  /// One subject's row as a card: name + units + remove button up top, then
  /// the six weekday fields in a `Wrap` so they reflow to fit the screen
  /// (two-per-line on a phone) instead of a DataTable getting clipped.
  Widget _scheduleMobileCard(int i) {
    final ctrls = _scheduleCtrls[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.maroon.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 13,
                  color: AppTheme.maroon,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Subject ${i + 1}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate400,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _removeScheduleRow(i),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.slate400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _scheduleMobileField('Course / Subject', ctrls[0]),
              ),
              const SizedBox(width: 8),
              Expanded(child: _scheduleMobileField('Units', ctrls[1])),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.maroon.withValues(alpha: 0.18),
                  ),
                ),
                child: const Text(
                  'WEEKLY SCHEDULE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.maroon,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: AppTheme.slate100)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _scheduleDayLabels.length,
              (j) => SizedBox(
                width: 100,
                child: _scheduleMobileField(_scheduleDayShort[j], ctrls[j + 2]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleMobileField(String label, TextEditingController controller) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate400,
                letterSpacing: 0.3,
              ),
            ),
          ),
          TextField(
            controller: controller,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.slate200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.slate200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppTheme.maroon,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ],
      );

  Widget _scheduleAddRow() => Row(
    children: [
      TextButton.icon(
        onPressed: _schedule.length >= _maxScheduleRows
            ? null
            : _addScheduleRow,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Add Subject'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.maroon,
          disabledForegroundColor: AppTheme.slate300,
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        '${_schedule.length}/$_maxScheduleRows subjects',
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.slate400,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
