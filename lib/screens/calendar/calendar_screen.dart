import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../theme/app_theme.dart';
import '../../models/app_state.dart';
import '../../models/recurring_schedule.dart';
import '../../models/schedule_event.dart';
import '../../services/recurring_schedule_repository.dart';
import '../../services/schedule_service.dart';
import '../../widgets/shared_widgets.dart';

/// Displays a user's schedule. Admins and Supervisors can additionally
/// browse other people's schedules via [_ScheduleOwnerSelector].
///
/// All event data flows through [ScheduleService] — this widget never
/// touches storage directly, so plugging in a real database later only
/// means swapping the repository passed into `ScheduleService` in
/// `main.dart`.
/// Whose schedule is on screen. Schedules are stored and protected per
/// account ([id]); [name] is only for display and the saved records.
typedef _Owner = ({String id, String name});

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  // null = viewing my own schedule. Otherwise holds the name of the
  // Supervisor/Student Assistant being viewed (Admin/Supervisor only).
  String? _viewingName;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheduleService = context.watch<ScheduleService>();
    scheduleService.activeAcademicYear = state.academicYear;

    final isSupervisor = state.role == 'Supervisor';
    final isAdmin = state.role == 'Head';
    final canViewOthers = isSupervisor || isAdmin;

    final List<
      ({
        String name,
        String role,
        String? department,
        String? campus,
        String? avatar,
      })
    >
    viewableUsers = isSupervisor
        ? state.filteredStudents
              .where((s) => s.name != state.currentUser?.name)
              .map(
                (s) => (
                  name: s.name,
                  role: 'Student Assistant',
                  department: s.department,
                  campus: s.campus,
                  avatar: s.avatar,
                ),
              )
              .toList()
        : isAdmin
        ? state.users
              .where(
                (u) =>
                    (u.role == 'Supervisor' || u.role == 'Student Assistant') &&
                    u.status != 'Archived',
              )
              .map(
                (u) => (
                  name: u.name,
                  role: u.role,
                  department: u.department,
                  campus: u.campus,
                  avatar: u.avatar,
                ),
              )
              .toList()
        : const <
            ({
              String name,
              String role,
              String? department,
              String? campus,
              String? avatar,
            })
          >[];

    // The picker works in names; schedules are kept per account.
    final accountIdByName = <String, String>{
      if (isSupervisor)
        for (final s in state.filteredStudents) s.name: s.userId ?? s.id
      else if (isAdmin)
        for (final u in state.users) u.name: u.id,
    };

    final isViewingOther = canViewOthers && _viewingName != null;
    final _Owner owner = _viewingName != null
        ? (id: accountIdByName[_viewingName] ?? '', name: _viewingName!)
        : (
            id: state.currentUser?.id ?? '',
            name: state.currentUser?.name ?? '',
          );

    // Kick off a load for this owner if we haven't fetched their events yet.
    // ScheduleService caches per-owner, so this is a no-op once loaded.
    if (owner.id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scheduleService.ensureLoaded(owner.id),
      );
    }

    final selected = _selectedDay ?? _focusedDay;
    final events = scheduleService.eventsForDay(owner.id, selected);

    // Header figures for this owner's calendar.
    final now = DateTime.now();
    final todayCount = scheduleService.eventsForDay(owner.id, now).length;
    final upcomingCount =
        List.generate(
          7,
          (offset) => now.add(Duration(days: offset + 1)),
        ).fold<int>(
          0,
          (running, day) =>
              running + scheduleService.eventsForDay(owner.id, day).length,
        );
    final allEventCount = scheduleService.eventsFor(owner.id).length;
    final isToday = isSameDay(selected, DateTime.now());
    final isLoading = scheduleService.isLoading(owner.id);

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16.0 : 28.0,
        isMobile ? 8 : 24,
        isMobile ? 16.0 : 28.0,
        28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          HeroBanner(
            isMobile: isMobile,
            icon: Icons.calendar_month_rounded,
            title: 'Schedule',
            subtitle: isViewingOther
                ? "Viewing $_viewingName's schedule"
                : 'View and manage your upcoming events',
            stats: [
              HeroStatData(
                label: 'Today',
                value: '$todayCount',
                icon: Icons.today_rounded,
              ),
              HeroStatData(
                label: 'Selected day',
                value: '${events.length}',
                icon: Icons.event_available_rounded,
              ),
              HeroStatData(
                label: 'Next 7 days',
                value: '$upcomingCount',
                icon: Icons.upcoming_rounded,
              ),
              HeroStatData(
                label: 'All events',
                value: '$allEventCount',
                icon: Icons.event_note_rounded,
              ),
            ],
            filters: [
              _actionBar(
                context: context,
                scheduleService: scheduleService,
                owner: owner,
                isViewingOther: isViewingOther,
                isMobile: isMobile,
              ),
            ],
          ),

          if (canViewOthers) ...[
            const SizedBox(height: 16),
            _ScheduleOwnerSelector(
              users: viewableUsers,
              selectedName: _viewingName,
              currentUserAvatarUrl: state.currentUser?.avatar,
              currentUserInitials: state.currentUser?.initials ?? '?',
              officeScoped: isSupervisor,
              onChanged: (name) => setState(() {
                _viewingName = name;
                _selectedDay = null;
                _focusedDay = DateTime.now();
              }),
            ),
          ],

          SizedBox(height: isMobile ? 16 : 24),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              children: [
                // Top accent strip
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: TableCalendar<ScheduleEvent>(
                    firstDay: DateTime.utc(2026, 1, 1),
                    lastDay: DateTime.utc(2027, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    calendarFormat: _format,
                    eventLoader: (day) =>
                        scheduleService.eventsForDay(owner.id, day),
                    startingDayOfWeek: StartingDayOfWeek.sunday,
                    onDaySelected: (sel, foc) => setState(() {
                      _selectedDay = sel;
                      _focusedDay = foc;
                    }),
                    onFormatChanged: (f) => setState(() => _format = f),
                    onPageChanged: (foc) => setState(() => _focusedDay = foc),
                    rowHeight: 48,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      cellMargin: const EdgeInsets.all(4),
                      selectedDecoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.maroon, AppTheme.maroonDark],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.maroon.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      todayDecoration: BoxDecoration(
                        color: AppTheme.gold400.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.gold400, width: 1.5),
                      ),
                      todayTextStyle: const TextStyle(
                        color: AppTheme.maroon,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      selectedTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      defaultTextStyle: const TextStyle(
                        color: AppTheme.slate700,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      weekendTextStyle: const TextStyle(
                        color: AppTheme.maroon,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      markerDecoration: const BoxDecoration(
                        color: AppTheme.maroon,
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 3,
                      markerSize: 5,
                      markerMargin: const EdgeInsets.symmetric(horizontal: 1),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonDecoration: BoxDecoration(
                        color: AppTheme.maroon50,
                        border: Border.all(color: AppTheme.maroon200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      formatButtonTextStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.maroon,
                      ),
                      formatButtonPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      titleCentered: true,
                      titleTextStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppTheme.slate900,
                        letterSpacing: -0.2,
                      ),
                      headerPadding: const EdgeInsets.symmetric(vertical: 12),
                      leftChevronIcon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.maroon50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.chevron_left_rounded,
                          color: AppTheme.maroon,
                          size: 18,
                        ),
                      ),
                      rightChevronIcon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.maroon50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.maroon,
                          size: 18,
                        ),
                      ),
                      leftChevronMargin: const EdgeInsets.only(left: 8),
                      rightChevronMargin: const EdgeInsets.only(right: 8),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppTheme.slate400,
                      ),
                      weekendStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppTheme.maroon,
                      ),
                      decoration: BoxDecoration(),
                    ),
                    daysOfWeekHeight: 36,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Events section ───────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday ? "Today's Events" : 'Events — ${_fmt(selected)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      isToday
                          ? 'What\'s on your plate today'
                          : _fmtFull(selected),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
              if (events.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${events.length} event${events.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Event list
          if (isLoading && events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.maroon),
              ),
            )
          else if (events.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.slate100),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.event_note_outlined,
                      size: 28,
                      color: AppTheme.slate300,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No events scheduled',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate400,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select a different day to see events',
                    style: TextStyle(fontSize: 12, color: AppTheme.slate300),
                  ),
                ],
              ),
            )
          else
            ...events.asMap().entries.map(
              (e) => Padding(
                padding: EdgeInsets.only(
                  bottom: e.key < events.length - 1 ? 12 : 0,
                ),
                child: _EventTile(
                  event: e.value,
                  onDelete: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Remove this event?'),
                        content: Text(
                          'This removes just "${e.value.title}" on this date. '
                          'If it\'s part of a recurring subject/schedule, use '
                          '"Manage Schedules" instead to edit or remove the '
                          'whole thing — otherwise it\'ll regenerate next '
                          'time that schedule is edited.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await scheduleService.deleteEvent(owner.id, e.value.id);
                      if (mounted) setState(() {});
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Recurring "Add Schedule" support ──────────────────────────────────
  //
  // Unlike "Add Event" (a single one-off, bookmark-like entry that is never
  // wired into the DTR/Accomplishment Report template), "Add Schedule" saves
  // a [RecurringScheduleRule] — e.g. "Class Schedule, every Monday, 8:00 AM
  // – 5:00 PM" — and automatically generates one [ScheduleEvent] occurrence
  // for every matching weekday across the *entire* academic year (past and
  // future alike, from [AppState.academicYearStart] through
  // [AppState.academicYearEnd]), skipping official holidays
  // ([AppState.isHoliday]), which are fixed and never user-editable. Rules
  // are stored via [RecurringScheduleRepository] so the DTR report's
  // "Class Schedule" table can auto-fill from the same data.

  final _rulesRepository = const RecurringScheduleRepository();

  Future<List<RecurringScheduleRule>> _loadRules(_Owner owner) =>
      _rulesRepository.loadRules(owner.id);

  Future<void> _saveRules(_Owner owner, List<RecurringScheduleRule> rules) =>
      _rulesRepository.saveRules(owner.id, owner.name, rules);

  /// Same as [_saveRules], but surfaces a failure (e.g. a Firestore
  /// permission error on this collection) as a visible SnackBar instead of
  /// silently doing nothing — a schedule change that "didn't take" used to
  /// look identical to one that succeeded but wasn't found later.
  Future<bool> _saveRulesOrShowError(
    _Owner owner,
    List<RecurringScheduleRule> rules,
  ) async {
    try {
      await _saveRules(owner, rules);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save schedule: $e'),
            backgroundColor: AppTheme.red500,
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return false;
    }
  }

  String _eventIdFor(String ruleId, DateTime date) =>
      'rule_${ruleId}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  /// Deletes every generated occurrence for [rule] — past and future alike
  /// — then recreates them for the whole academic year
  /// ([AppState.academicYearStart] through [AppState.academicYearEnd]),
  /// skipping holidays. Called both when a rule is first added and after it
  /// is edited, so adding/editing a schedule always reflects the full year,
  /// including days that have already passed.
  Future<void> _regenerateOccurrences(
    ScheduleService scheduleService,
    _Owner owner,
    RecurringScheduleRule rule,
  ) async {
    final state = context.read<AppState>();

    final existing = scheduleService
        .eventsFor(owner.id)
        .where((e) => e.id.startsWith('rule_${rule.id}_'))
        .toList();
    for (final e in existing) {
      await scheduleService.deleteEvent(owner.id, e.id);
    }

    var cursor = DateTime(
      state.academicYearStart.year,
      state.academicYearStart.month,
      state.academicYearStart.day,
    );
    final end = state.academicYearEnd;
    while (!cursor.isAfter(end)) {
      if (cursor.weekday == rule.weekday && !state.isHoliday(cursor)) {
        await scheduleService.addEvent(
          ScheduleEvent(
            id: _eventIdFor(rule.id, cursor),
            ownerId: owner.id,
            ownerName: owner.name,
            title: rule.label,
            details: '${rule.timeRange} · ${rule.mode}',
            date: cursor,
            color: rule.color,
            icon: rule.icon,
            academicYear: state.academicYear,
          ),
        );
      }
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  Future<void> _deleteRule(
    ScheduleService scheduleService,
    _Owner owner,
    RecurringScheduleRule rule,
  ) async {
    final all = scheduleService
        .eventsFor(owner.id)
        .where((e) => e.id.startsWith('rule_${rule.id}_'))
        .toList();
    for (final e in all) {
      await scheduleService.deleteEvent(owner.id, e.id);
    }
    final rules = await _loadRules(owner);
    rules.removeWhere((r) => r.id == rule.id);
    await _saveRulesOrShowError(owner, rules);
  }

  static const _recurringWeekdayShort = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];
  static const _recurringColorOptions = [
    AppTheme.maroon,
    AppTheme.gold400,
    AppTheme.emerald500,
    AppTheme.blue500,
  ];
  static const _recurringIconOptions = [
    Icons.school_outlined,
    Icons.work_outline,
    Icons.menu_book_outlined,
    Icons.event_note_outlined,
  ];

  // ── Header helpers (responsive) ─────────────────────────────────────

  /// "Add Schedule" / "Add Subject" / "Add Event" / manage-schedules.
  ///
  /// On desktop these render as a normal Row. On mobile they become a
  /// horizontally-scrollable chip row so they never force the title text
  /// into a near-zero-width column (the original overflow bug) and never
  /// wrap into a cramped multi-line jumble either.
  ///
  /// "Add Schedule"/"Add Subject" (and the manage-schedules icon) stay
  /// visible while a supervisor is viewing a student's calendar via the
  /// selector below, so they can set up that student's recurring schedule
  /// directly — the DTR report's "Sync from Schedule" reads the exact same
  /// rules, keyed by whichever account is being viewed here. "Add Event" (a
  /// personal one-off entry, never pulled into the DTR report) stays
  /// limited to your own calendar.
  Widget _actionBar({
    required BuildContext context,
    required ScheduleService scheduleService,
    required _Owner owner,
    required bool isViewingOther,
    required bool isMobile,
  }) {
    final chips = <Widget>[
      _actionChip(
        icon: Icons.event_repeat_rounded,
        label: 'Add Schedule',
        dense: isMobile,
        onTap: () =>
            _showAddScheduleDialog(context, scheduleService, owner),
      ),
      SizedBox(width: isMobile ? 8 : 10),
      _actionChip(
        icon: Icons.menu_book_outlined,
        label: 'Add Subject',
        dense: isMobile,
        onTap: () => _showAddSubjectDialog(context, scheduleService, owner),
      ),
      if (!isViewingOther) ...[
        SizedBox(width: isMobile ? 8 : 10),
        _actionChip(
          icon: Icons.add_rounded,
          label: 'Add Event',
          filled: true,
          dense: isMobile,
          onTap: () => _showAddEventDialog(context, scheduleService, owner),
        ),
      ],
      SizedBox(width: isMobile ? 6 : 10),
      _iconButton(
        icon: Icons.tune_rounded,
        dense: isMobile,
        onTap: () =>
            _showManageSchedulesDialog(context, scheduleService, owner),
      ),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(children: chips),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: chips);
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
    bool dense = false,
  }) {
    final Color background = filled ? AppTheme.maroon : Colors.white;
    final Color foreground = filled ? Colors.white : AppTheme.maroon;
    final double radius = dense ? 11 : 12;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 14 : 16,
            vertical: dense ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: filled
                ? null
                : Border.all(
                    color: AppTheme.maroon.withOpacity(0.55),
                    width: 1.3,
                  ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppTheme.maroon.withOpacity(0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: dense ? 16 : 18, color: foreground),
              SizedBox(width: dense ? 5 : 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: dense ? 12.5 : 13,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool dense = false,
  }) {
    final double radius = dense ? 11 : 12;
    return Material(
      color: AppTheme.slate900.withOpacity(0.045),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? 10 : 12),
          child: Icon(icon, size: 18, color: AppTheme.slate500),
        ),
      ),
    );
  }

  /// "Add Schedule" — a recurring weekly rule, distinct from the one-off
  /// entries created by "Add Event". This *is* the rule the DTR report's
  /// "Class Schedule" table auto-fills from.
  ///
  /// Pass [existingRule] to edit a rule already saved — the dialog then
  /// pre-fills every field and, on save, replaces that rule in place and
  /// regenerates its occurrences for the whole academic year (instead of
  /// appending a brand-new rule).
  void _showAddScheduleDialog(
    BuildContext context,
    ScheduleService scheduleService,
    _Owner owner, {
    RecurringScheduleRule? existingRule,
  }) async {
    final isEditing = existingRule != null;
    final existingRules = await _loadRules(owner);
    if (!mounted) return;
    final academicYear = context.read<AppState>().academicYear;
    final academicYearEnd = context.read<AppState>().academicYearEnd;

    final labelCtrl = TextEditingController(
      text: existingRule?.label ?? 'Class Schedule',
    );
    int weekday = existingRule?.weekday ?? DateTime.monday;
    TimeOfDay start =
        existingRule?.startTime ?? const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay end =
        existingRule?.endTime ?? const TimeOfDay(hour: 17, minute: 0);
    Color color = existingRule?.color ?? _recurringColorOptions.first;
    IconData icon = existingRule?.icon ?? _recurringIconOptions.first;
    String mode = existingRule?.mode ?? 'Face-to-Face';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DialogHeader(
                      icon: Icons.event_repeat_rounded,
                      title: isEditing ? 'Edit Schedule' : 'Add Schedule',
                      accent: color,
                      onClose: () => Navigator.of(dialogContext).pop(),
                      subtitle:
                          'Repeats automatically every week until the end '
                          'of the semester, skipping holidays. Different from '
                          '"Add Event", which is a single one-time entry.',
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: labelCtrl,
                              decoration: _modernFieldDecoration(
                                'Label (e.g. Class Schedule)',
                                icon: Icons.label_outline,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Repeats every'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(6, (i) {
                                final d = i + 1; // Mon..Sat
                                return _PillChoice(
                                  label: _recurringWeekdayShort[i],
                                  selected: weekday == d,
                                  accent: color,
                                  onTap: () =>
                                      setDialogState(() => weekday = d),
                                );
                              }),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Mode'),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _PillChoice(
                                    label: 'Face-to-Face',
                                    selected: mode == 'Face-to-Face',
                                    accent: color,
                                    onTap: () => setDialogState(
                                      () => mode = 'Face-to-Face',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PillChoice(
                                    label: 'Online',
                                    selected: mode == 'Online',
                                    accent: color,
                                    onTap: () =>
                                        setDialogState(() => mode = 'Online'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _RecurringTimeField(
                                    label: 'Start',
                                    time: start,
                                    onTap: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: start,
                                      );
                                      if (picked != null)
                                        setDialogState(() => start = picked);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _RecurringTimeField(
                                    label: 'End',
                                    time: end,
                                    onTap: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: end,
                                      );
                                      if (picked != null)
                                        setDialogState(() => end = picked);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Color'),
                            const SizedBox(height: 10),
                            Row(
                              children: _recurringColorOptions
                                  .map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: _ColorSwatch(
                                        color: c,
                                        selected: color == c,
                                        onTap: () =>
                                            setDialogState(() => color = c),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Icon'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _recurringIconOptions
                                  .map(
                                    (i) => _IconTile(
                                      icon: i,
                                      selected: icon == i,
                                      accent: color,
                                      onTap: () =>
                                          setDialogState(() => icon = i),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 15,
                                    color: color,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Repeats every ${_recurringWeekdayShort[weekday - 1]} ($mode) until '
                                      '${academicYearEnd.month}/${academicYearEnd.day}/${academicYearEnd.year}, '
                                      'automatically skipping official holidays.',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.slate600,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _DialogFooter(
                      accent: color,
                      confirmLabel: isEditing ? 'Save Changes' : 'Add Schedule',
                      onCancel: () => Navigator.of(dialogContext).pop(),
                      onConfirm: () async {
                        if (labelCtrl.text.trim().isEmpty) return;
                        final rule = RecurringScheduleRule(
                          id:
                              existingRule?.id ??
                              'r${DateTime.now().microsecondsSinceEpoch}',
                          ownerName: owner.name,
                          label: labelCtrl.text.trim(),
                          weekday: weekday,
                          startTime: start,
                          endTime: end,
                          color: color,
                          icon: icon,
                          academicYear: academicYear,
                          mode: mode,
                        );
                        Navigator.of(dialogContext).pop();
                        final rules = isEditing
                            ? existingRules
                                  .map((r) => r.id == rule.id ? rule : r)
                                  .toList()
                            : [...existingRules, rule];
                        final ok = await _saveRulesOrShowError(
                          owner,
                          rules,
                        );
                        if (!ok) return;
                        await _regenerateOccurrences(
                          scheduleService,
                          owner,
                          rule,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// "Add Subject" — a shortcut on top of "Add Schedule" for the common
  /// case of adding a class subject: same recurring weekly rule underneath,
  /// but with a required Units field. Since the DTR "Class Schedule" table
  /// groups rules by [RecurringScheduleRule.label] into one row per
  /// subject, saving here also stamps [units] onto every other existing
  /// rule that shares this label (e.g. the same subject on another
  /// weekday), so the subject's unit count stays consistent across days.
  void _showAddSubjectDialog(
    BuildContext context,
    ScheduleService scheduleService,
    _Owner owner, {
    RecurringScheduleRule? existingRule,
  }) async {
    final isEditing = existingRule != null;
    final existingRules = await _loadRules(owner);
    if (!mounted) return;
    final academicYear = context.read<AppState>().academicYear;
    final academicYearEnd = context.read<AppState>().academicYearEnd;

    final labelCtrl = TextEditingController(text: existingRule?.label ?? '');
    final unitsCtrl = TextEditingController(text: existingRule?.units ?? '');
    int weekday = existingRule?.weekday ?? DateTime.monday;
    TimeOfDay start =
        existingRule?.startTime ?? const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay end =
        existingRule?.endTime ?? const TimeOfDay(hour: 17, minute: 0);
    Color color = existingRule?.color ?? _recurringColorOptions.first;
    IconData icon = existingRule?.icon ?? Icons.menu_book_outlined;
    String mode = existingRule?.mode ?? 'Face-to-Face';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DialogHeader(
                      icon: Icons.menu_book_rounded,
                      title: isEditing ? 'Edit Subject' : 'Add Subject',
                      accent: color,
                      onClose: () => Navigator.of(dialogContext).pop(),
                      subtitle:
                          'Adds a recurring class subject — repeats every '
                          'week until the end of the semester — and fills the '
                          'Course/Subject and Units columns on the DTR/Report '
                          'automatically.',
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: labelCtrl,
                              decoration: _modernFieldDecoration(
                                'Course / Subject',
                                icon: Icons.school_outlined,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: unitsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: _modernFieldDecoration(
                                'Units',
                                icon: Icons.numbers_rounded,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Repeats every'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(6, (i) {
                                final d = i + 1; // Mon..Sat
                                return _PillChoice(
                                  label: _recurringWeekdayShort[i],
                                  selected: weekday == d,
                                  accent: color,
                                  onTap: () =>
                                      setDialogState(() => weekday = d),
                                );
                              }),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Mode'),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _PillChoice(
                                    label: 'Face-to-Face',
                                    selected: mode == 'Face-to-Face',
                                    accent: color,
                                    onTap: () => setDialogState(
                                      () => mode = 'Face-to-Face',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PillChoice(
                                    label: 'Online',
                                    selected: mode == 'Online',
                                    accent: color,
                                    onTap: () =>
                                        setDialogState(() => mode = 'Online'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _RecurringTimeField(
                                    label: 'Start',
                                    time: start,
                                    onTap: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: start,
                                      );
                                      if (picked != null)
                                        setDialogState(() => start = picked);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _RecurringTimeField(
                                    label: 'End',
                                    time: end,
                                    onTap: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: end,
                                      );
                                      if (picked != null)
                                        setDialogState(() => end = picked);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Color'),
                            const SizedBox(height: 10),
                            Row(
                              children: _recurringColorOptions
                                  .map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: _ColorSwatch(
                                        color: c,
                                        selected: color == c,
                                        onTap: () =>
                                            setDialogState(() => color = c),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Icon'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _recurringIconOptions
                                  .map(
                                    (i) => _IconTile(
                                      icon: i,
                                      selected: icon == i,
                                      accent: color,
                                      onTap: () =>
                                          setDialogState(() => icon = i),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 15,
                                    color: color,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Repeats every ${_recurringWeekdayShort[weekday - 1]} ($mode) until '
                                      '${academicYearEnd.month}/${academicYearEnd.day}/${academicYearEnd.year}, '
                                      'automatically skipping official holidays.',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.slate600,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _DialogFooter(
                      accent: color,
                      confirmLabel: isEditing ? 'Save Changes' : 'Add Subject',
                      onCancel: () => Navigator.of(dialogContext).pop(),
                      onConfirm: () async {
                        if (labelCtrl.text.trim().isEmpty) return;
                        final label = labelCtrl.text.trim();
                        final units = unitsCtrl.text.trim();
                        final rule = RecurringScheduleRule(
                          id:
                              existingRule?.id ??
                              'r${DateTime.now().microsecondsSinceEpoch}',
                          ownerName: owner.name,
                          label: label,
                          weekday: weekday,
                          startTime: start,
                          endTime: end,
                          color: color,
                          icon: icon,
                          academicYear: academicYear,
                          mode: mode,
                          units: units,
                          isSubject: true,
                        );
                        Navigator.of(dialogContext).pop();
                        // Stamp `units` onto every other rule sharing this
                        // subject's label too, so the DTR sync (which groups by
                        // label) reflects the same unit count regardless of
                        // which weekday's rule it reads it from.
                        var rules = isEditing
                            ? existingRules
                                  .map((r) => r.id == rule.id ? rule : r)
                                  .toList()
                            : [...existingRules, rule];
                        rules = rules
                            .map(
                              (r) => r.label == label && r.id != rule.id
                                  ? r.copyWith(units: units)
                                  : r,
                            )
                            .toList();
                        final ok = await _saveRulesOrShowError(
                          owner,
                          rules,
                        );
                        if (!ok) return;
                        await _regenerateOccurrences(
                          scheduleService,
                          owner,
                          rule,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Lists this owner's recurring schedule rules, with a way to edit a rule
  /// (which regenerates its occurrences for the whole academic year, past
  /// and future) or delete one entirely (which removes all of its
  /// occurrences too).
  void _showManageSchedulesDialog(
    BuildContext context,
    ScheduleService scheduleService,
    _Owner owner,
  ) async {
    var rules = await _loadRules(owner);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Recurring Schedules',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppTheme.slate900,
            ),
          ),
          content: SizedBox(
            width: 340,
            child: rules.isEmpty
                ? const Text(
                    'No recurring schedules yet. Use "Add Schedule" to set up '
                    'days that repeat automatically, like every Monday.',
                    style: TextStyle(fontSize: 13, color: AppTheme.slate500),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: rules
                        .map(
                          (rule) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: rule.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    rule.icon,
                                    color: rule.color,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rule.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppTheme.slate900,
                                        ),
                                      ),
                                      Text(
                                        'Every ${rule.weekdayName} · ${rule.timeRange} · ${rule.mode}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppTheme.slate500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: AppTheme.slate500,
                                  ),
                                  tooltip: 'Edit',
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop();
                                    _showAddScheduleDialog(
                                      context,
                                      scheduleService,
                                      owner,
                                      existingRule: rule,
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: AppTheme.red500,
                                  ),
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    final confirmed = await showConfirmDialog(
                                      dialogContext,
                                      title: 'Delete this schedule?',
                                      message:
                                          'This removes "${rule.label}" '
                                          '(every ${rule.weekdayName}) and all '
                                          'of its days on the calendar for the '
                                          'whole academic year. It also drops '
                                          'out of the DTR report\'s class '
                                          'schedule.',
                                      confirmLabel: 'Delete',
                                    );
                                    if (!confirmed) return;
                                    await _deleteRule(
                                      scheduleService,
                                      owner,
                                      rule,
                                    );
                                    rules = await _loadRules(owner);
                                    setDialogState(() {});
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final removed = await _cleanupOrphanedEvents(
                  dialogContext,
                  scheduleService,
                  owner,
                  rules,
                );
                if (removed > 0 && mounted) setState(() {});
              },
              child: const Text(
                'Clean up stray events',
                style: TextStyle(color: AppTheme.slate500),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  /// Removes every calendar event that looks like it came from a recurring
  /// rule (its id follows the `rule_<ruleId>_<date>` pattern from
  /// [_eventIdFor]) but whose rule no longer exists — e.g. a rule created
  /// before this student's schedule moved to Firestore, or one deleted
  /// through some other path that didn't clean up its occurrences. These
  /// can't be edited (there's nothing to edit) and, since a single rule
  /// generates one event per matching weekday for the whole academic year,
  /// there can be dozens of them — this removes all of them in one action
  /// rather than requiring them to be deleted one at a time.
  ///
  /// Shows a confirmation with the exact count before deleting anything,
  /// since this can't be undone.
  Future<int> _cleanupOrphanedEvents(
    BuildContext dialogContext,
    ScheduleService scheduleService,
    _Owner owner,
    List<RecurringScheduleRule> currentRules,
  ) async {
    await scheduleService.refresh(owner.id);
    final currentRuleIds = currentRules.map((r) => r.id).toSet();
    final orphans = scheduleService.eventsFor(owner.id).where((e) {
      if (!e.id.startsWith('rule_')) return false;
      final withoutPrefix = e.id.substring('rule_'.length);
      final lastUnderscore = withoutPrefix.lastIndexOf('_');
      if (lastUnderscore == -1) return true; // malformed id, definitely stray
      final ruleId = withoutPrefix.substring(0, lastUnderscore);
      return !currentRuleIds.contains(ruleId);
    }).toList();

    if (!mounted) return 0;
    if (orphans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No stray events found — everything here matches a current schedule.',
          ),
          backgroundColor: AppTheme.blue500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return 0;
    }

    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (confirmContext) => AlertDialog(
        title: const Text('Remove stray events?'),
        content: Text(
          'Found ${orphans.length} calendar event${orphans.length == 1 ? '' : 's'} left over from '
          'a schedule that no longer exists (e.g. "${orphans.first.title}"). '
          'These can\'t be edited since there\'s nothing behind them anymore. '
          'Remove all ${orphans.length} of them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return 0;

    for (final e in orphans) {
      await scheduleService.deleteEvent(owner.id, e.id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${orphans.length} stray event${orphans.length == 1 ? '' : 's'}.',
          ),
          backgroundColor: AppTheme.blue500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
    return orphans.length;
  }

  void _showAddEventDialog(
    BuildContext context,
    ScheduleService scheduleService,
    _Owner owner,
  ) {
    final titleCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    DateTime pickedDay = _selectedDay ?? _focusedDay;
    Color pickedColor = AppTheme.maroon;
    IconData pickedIcon = Icons.event_note_outlined;

    const colorOptions = [
      AppTheme.maroon,
      AppTheme.gold400,
      AppTheme.emerald500,
      AppTheme.blue500,
      AppTheme.red500,
    ];
    const iconOptions = [
      Icons.event_note_outlined,
      Icons.groups_outlined,
      Icons.school_outlined,
      Icons.task_alt_outlined,
      Icons.description_outlined,
      Icons.business_center_outlined,
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DialogHeader(
                      icon: Icons.event_note_rounded,
                      title: 'Add Event',
                      accent: pickedColor,
                      onClose: () => Navigator.of(dialogContext).pop(),
                      subtitle: 'A single one-time entry on your calendar.',
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: titleCtrl,
                              decoration: _modernFieldDecoration(
                                'Event title',
                                icon: Icons.title_rounded,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: detailsCtrl,
                              decoration: _modernFieldDecoration(
                                'Details (e.g. Room 201 · 9:00 AM)',
                                icon: Icons.notes_rounded,
                              ),
                            ),
                            const SizedBox(height: 18),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: pickedDay,
                                  firstDate: DateTime.utc(2026, 1, 1),
                                  lastDate: DateTime.utc(2027, 12, 31),
                                );
                                if (picked != null)
                                  setDialogState(() => pickedDay = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.slate50,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.calendar_today_rounded,
                                        size: 15,
                                        color: pickedColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _fmtFull(pickedDay),
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        color: AppTheme.slate700,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: AppTheme.slate400,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Color'),
                            const SizedBox(height: 10),
                            Row(
                              children: colorOptions
                                  .map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: _ColorSwatch(
                                        color: c,
                                        selected: pickedColor == c,
                                        onTap: () => setDialogState(
                                          () => pickedColor = c,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 18),
                            const _DialogSectionLabel('Icon'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: iconOptions
                                  .map(
                                    (i) => _IconTile(
                                      icon: i,
                                      selected: pickedIcon == i,
                                      accent: pickedColor,
                                      onTap: () =>
                                          setDialogState(() => pickedIcon = i),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _DialogFooter(
                      accent: pickedColor,
                      confirmLabel: 'Add Event',
                      onCancel: () => Navigator.of(dialogContext).pop(),
                      onConfirm: () async {
                        if (titleCtrl.text.trim().isEmpty) return;
                        await scheduleService.addEvent(
                          ScheduleEvent(
                            id: '', // assigned by the repository
                            ownerId: owner.id,
                            ownerName: owner.name,
                            title: titleCtrl.text.trim(),
                            details: detailsCtrl.text.trim().isEmpty
                                ? 'No details added'
                                : detailsCtrl.text.trim(),
                            date: pickedDay,
                            color: pickedColor,
                            icon: pickedIcon,
                            academicYear: context.read<AppState>().academicYear,
                          ),
                        );
                        setState(() {
                          _selectedDay = pickedDay;
                          _focusedDay = pickedDay;
                        });
                        if (dialogContext.mounted)
                          Navigator.of(dialogContext).pop();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _fmt(DateTime d) {
    const m = [
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
    return '${m[d.month - 1]} ${d.day}';
  }

  String _fmtFull(DateTime d) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    const months = [
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
    return '${days[d.weekday % 7]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// Lets Admins/Supervisors pick whose schedule is currently displayed.
/// Entries are grouped for easier scanning: Admins see Supervisors and
/// Student Assistants grouped separately by role, then by campus within
/// each role. Supervisors (who only browse their own Student Assistants)
/// see a single group broken down by department.
///
/// Built as a custom overlay panel (rather than a plain DropdownButton) so
/// the menu can use avatars, hover highlighting, and its own card styling.
class _ScheduleOwnerSelector extends StatefulWidget {
  final List<
    ({
      String name,
      String role,
      String? department,
      String? campus,
      String? avatar,
    })
  >
  users;
  final String? selectedName;
  final String? currentUserAvatarUrl;
  final String currentUserInitials;
  final bool officeScoped;
  final ValueChanged<String?> onChanged;

  const _ScheduleOwnerSelector({
    required this.users,
    required this.selectedName,
    required this.currentUserAvatarUrl,
    required this.currentUserInitials,
    required this.officeScoped,
    required this.onChanged,
  });

  @override
  State<_ScheduleOwnerSelector> createState() => _ScheduleOwnerSelectorState();
}

class _ScheduleOwnerSelectorState extends State<_ScheduleOwnerSelector> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _open = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggle(BuildContext context) {
    if (_open) {
      _removeOverlay();
    } else {
      _showOverlay(context);
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_open && mounted) setState(() => _open = false);
  }

  void _showOverlay(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap outside to dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 8),
            child: Align(
              alignment: Alignment.topLeft,
              child: _ScheduleOwnerMenu(
                width: size.width,
                users: widget.users,
                selectedName: widget.selectedName,
                currentUserAvatarUrl: widget.currentUserAvatarUrl,
                currentUserInitials: widget.currentUserInitials,
                officeScoped: widget.officeScoped,
                onSelect: (name) {
                  _removeOverlay();
                  widget.onChanged(name);
                },
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedName == null
        ? null
        : widget.users.where((u) => u.name == widget.selectedName).firstOrNull;
    final label = selected == null
        ? 'My Schedule'
        : "${selected.name}'s Schedule";

    String initialsFromName(String name) {
      final parts = name
          .trim()
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.isEmpty) return '?';
      if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
      return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
          .toUpperCase();
    }

    return CompositedTransformTarget(
      link: _link,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggle(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _open ? AppTheme.maroon : AppTheme.maroon200,
                width: _open ? 1.4 : 1,
              ),
              boxShadow: _open
                  ? [
                      BoxShadow(
                        color: AppTheme.maroon.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                selected == null
                    ? UserAvatar(
                        avatarUrl: widget.currentUserAvatarUrl,
                        initials: widget.currentUserInitials,
                        size: 26,
                      )
                    : UserAvatar(
                        avatarUrl: selected.avatar,
                        initials: initialsFromName(selected.name),
                        size: 26,
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate900,
                    ),
                  ),
                ),
                if (selected?.role != null) ...[
                  _RolePill(role: selected!.role),
                  const SizedBox(width: 8),
                ],
                AnimatedRotation(
                  duration: const Duration(milliseconds: 150),
                  turns: _open ? 0.5 : 0,
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: AppTheme.maroon,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// The floating panel itself. Groups are collapsed by default and expand
/// on tap, and a search field lets people jump straight to a name instead
/// of scrolling — keeps the panel short instead of dumping every person
/// on screen at once.
class _ScheduleOwnerMenu extends StatefulWidget {
  final double width;
  final List<
    ({
      String name,
      String role,
      String? department,
      String? campus,
      String? avatar,
    })
  >
  users;
  final String? selectedName;
  final String? currentUserAvatarUrl;
  final String currentUserInitials;
  final bool officeScoped;
  final ValueChanged<String?> onSelect;

  const _ScheduleOwnerMenu({
    required this.width,
    required this.users,
    required this.selectedName,
    required this.currentUserAvatarUrl,
    required this.currentUserInitials,
    required this.officeScoped,
    required this.onSelect,
  });

  @override
  State<_ScheduleOwnerMenu> createState() => _ScheduleOwnerMenuState();
}

class _ScheduleOwnerMenuState extends State<_ScheduleOwnerMenu> {
  String _query = '';
  String _filterRole = 'All';
  String _filterDept = 'All Departments';
  String _filterCampus = 'All Campuses';

  @override
  Widget build(BuildContext context) {
    final roles = widget.users.map((u) => u.role).toSet().toList()..sort();
    final showRoleFilter = roles.length > 1;

    final depts = <String>{
      for (final u in widget.users)
        if ((u.department ?? '').isNotEmpty) u.department!,
    }.toList()..sort();
    final campuses = <String>{
      for (final u in widget.users)
        if ((u.campus ?? '').isNotEmpty) u.campus!,
    }.toList()..sort();

    final q = _query.trim().toLowerCase();
    final filtered = widget.users.where((u) {
      final matchQuery = q.isEmpty || u.name.toLowerCase().contains(q);
      final matchRole = _filterRole == 'All' || u.role == _filterRole;
      final matchDept =
          widget.officeScoped ||
          _filterDept == 'All Departments' ||
          (u.department ?? '') == _filterDept;
      final matchCampus =
          _filterCampus == 'All Campuses' || (u.campus ?? '') == _filterCampus;
      return matchQuery && matchRole && matchDept && matchCampus;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final showMySchedule =
        q.isEmpty &&
        _filterRole == 'All' &&
        (widget.officeScoped || _filterDept == 'All Departments') &&
        _filterCampus == 'All Campuses';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: widget.width < 300 ? 300 : widget.width,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.slate50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate900,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search people',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.slate400,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppTheme.slate400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                  ),
                ),
              ),
            ),

            // Department uses a proper dropdown — a pill row would get
            // unwieldy as more departments get added. Campus and role stay
            // as pill rows since those lists are expected to stay short.
            // Custom-built overlay (not the native DropdownButton) so it
            // doesn't fight with the overlay this whole menu already lives
            // in — same reliable pattern as the outer selector.
            if (!widget.officeScoped && depts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: _FilterDropdown(
                  icon: Icons.apartment_rounded,
                  value: _filterDept,
                  options: ['All Departments', ...depts],
                  onChanged: (v) => setState(() => _filterDept = v),
                ),
              ),
            if (campuses.isNotEmpty)
              _PillRow(
                icon: Icons.location_on_rounded,
                value: _filterCampus,
                options: ['All Campuses', ...campuses],
                onChanged: (v) => setState(() => _filterCampus = v),
              ),
            if (showRoleFilter)
              _PillRow(
                icon: Icons.badge_rounded,
                value: _filterRole,
                options: ['All', ...roles],
                onChanged: (v) => setState(() => _filterRole = v),
              ),

            const SizedBox(height: 4),
            const Divider(height: 1, color: AppTheme.slate100),

            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                shrinkWrap: true,
                children: [
                  if (showMySchedule)
                    _MenuRow(
                      leading: UserAvatar(
                        avatarUrl: widget.currentUserAvatarUrl,
                        initials: widget.currentUserInitials,
                        size: 28,
                      ),
                      title: 'My Schedule',
                      selected: widget.selectedName == null,
                      onTap: () => widget.onSelect(null),
                    ),
                  for (final u in filtered)
                    _MenuRow(
                      leading: UserAvatar(
                        avatarUrl: u.avatar,
                        initials: u.name
                            .trim()
                            .split(RegExp(r'\s+'))
                            .where((p) => p.isNotEmpty)
                            .map((p) => p[0])
                            .take(2)
                            .join()
                            .toUpperCase(),
                        size: 28,
                      ),
                      title: u.name,
                      subtitle: [
                        u.role,
                        if ((u.campus ?? '').isNotEmpty)
                          u.campus!.replaceAll(' Campus', ''),
                      ].join(' · '),
                      selected: widget.selectedName == u.name,
                      onTap: () => widget.onSelect(u.name),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No matches',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.slate400,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A proper dropdown for filters with lists that can grow long (department
/// today, possibly more later) — a pill row would just wrap into an
/// unreadable wall of chips as options are added. Built as its own small
/// overlay panel (not the native DropdownButton/showMenu route), using the
/// same CompositedTransformFollower approach as the outer schedule
/// selector, so it doesn't fight with the overlay this whole menu already
/// lives inside.
class _FilterDropdown extends StatefulWidget {
  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  State<_FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<_FilterDropdown> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _open = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_open && mounted) setState(() => _open = false);
  }

  void _showOverlay(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: size.width < 180 ? 180 : size.width,
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    children: widget.options.map((o) {
                      final active = o == widget.value;
                      return InkWell(
                        onTap: () {
                          _removeOverlay();
                          widget.onChanged(o);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          color: active
                              ? AppTheme.maroon.withValues(alpha: 0.08)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: active
                                        ? AppTheme.maroon
                                        : AppTheme.slate700,
                                  ),
                                ),
                              ),
                              if (active)
                                const Icon(
                                  Icons.check_rounded,
                                  size: 15,
                                  color: AppTheme.maroon,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open ? _removeOverlay() : _showOverlay(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _open ? AppTheme.maroon : AppTheme.slate200,
                width: _open ? 1.3 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 14, color: AppTheme.slate400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 120),
                  turns: _open ? 0.5 : 0,
                  child: const Icon(
                    Icons.expand_more_rounded,
                    size: 17,
                    color: AppTheme.slate400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrollable row of filter chips (department, campus, role).
/// Plain gesture-driven chips — same mechanism as the working role pills —
/// so they're always reliably tappable, with a small leading icon and a
/// smooth active-state transition for a cleaner, more modern feel.
class _PillRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _PillRow({
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 30,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            Icon(icon, size: 14, color: AppTheme.slate300),
            const SizedBox(width: 6),
            for (final o in options) ...[
              _Pill(label: o, active: value == o, onTap: () => onChanged(o)),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? AppTheme.maroon : AppTheme.slate50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? AppTheme.maroon : AppTheme.slate200,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppTheme.slate600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single hoverable / tappable row inside the schedule-owner menu.
class _MenuRow extends StatefulWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MenuRow({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _hovering;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: widget.selected
                    ? AppTheme.maroon.withValues(alpha: 0.08)
                    : (_hovering ? AppTheme.slate50 : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: widget.selected
                    ? Border.all(color: AppTheme.maroon.withValues(alpha: 0.25))
                    : null,
              ),
              child: Row(
                children: [
                  widget.leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: highlighted
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: AppTheme.slate900,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            widget.subtitle!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.selected) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppTheme.maroon,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded role badge ("Supervisor" / "Student Assistant").
class _RolePill extends StatelessWidget {
  final String role;
  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    final isSupervisor = role == 'Supervisor';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isSupervisor ? AppTheme.gold400 : AppTheme.maroon).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isSupervisor ? const Color(0xFF8A6D00) : AppTheme.maroon,
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final ScheduleEvent event;
  final VoidCallback? onDelete;
  const _EventTile({required this.event, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: event.color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          // Color accent bar
          Container(
            width: 5,
            height: 72,
            decoration: BoxDecoration(
              color: event.color,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(event.icon, color: event.color, size: 20),
          ),
          const SizedBox(width: 14),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  event.details,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Right indicator dot
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: event.color,
              shape: BoxShape.circle,
            ),
          ),
          if (onDelete != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppTheme.slate400,
                tooltip: 'Remove this event',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared decoration for the modern "filled" text fields used across the
/// Add Event / Add Subject / Add Schedule dialogs.
InputDecoration _modernFieldDecoration(String label, {IconData? icon}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 18, color: AppTheme.slate400),
    filled: true,
    fillColor: AppTheme.slate50,
    labelStyle: const TextStyle(
      color: AppTheme.slate500,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.maroon, width: 1.6),
    ),
  );
}

/// Modern dialog header: a soft gradient icon badge, title + optional
/// subtitle, and a circular close button — replaces the plain bold
/// [AlertDialog] title used previously.
class _DialogHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final VoidCallback onClose;

  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.onClose,
    this.subtitle,
    this.accent = AppTheme.maroon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: AppTheme.slate900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onClose,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 16,
                color: AppTheme.slate500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section eyebrow label ("REPEATS EVERY", "COLOR", ...) used above each
/// group of choices inside a dialog.
class _DialogSectionLabel extends StatelessWidget {
  final String text;
  const _DialogSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppTheme.slate400,
        letterSpacing: 0.6,
      ),
    );
  }
}

/// Pill-shaped selectable chip with a soft glow when selected — used for
/// weekday and mode pickers in place of the plain [ChoiceChip].
class _PillChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  const _PillChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AppTheme.maroon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent : AppTheme.slate50,
          borderRadius: BorderRadius.circular(24),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.slate600,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

/// Circular color swatch with a check mark drawn on top when selected,
/// plus a lift shadow — a step up from the plain bordered circle.
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 2.5 : 0),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: selected ? 0.45 : 0.2),
              blurRadius: selected ? 10 : 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : null,
      ),
    );
  }
}

/// Rounded icon tile with a soft tinted background when selected.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _IconTile({
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : AppTheme.slate50,
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: accent, width: 1.4) : null,
        ),
        child: Icon(
          icon,
          size: 19,
          color: selected ? accent : AppTheme.slate400,
        ),
      ),
    );
  }
}

/// Footer action row shared by the dialogs: a plain "Cancel" text button
/// and a full-weight gradient primary button.
class _DialogFooter extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final Color accent;

  const _DialogFooter({
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    this.accent = AppTheme.maroon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: AppTheme.slate500,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [accent, accent.withValues(alpha: 0.75)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onConfirm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      confirmLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringTimeField extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _RecurringTimeField({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.slate50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.access_time,
                size: 15,
                color: AppTheme.maroon,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.slate400,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    RecurringScheduleRule.formatTime(time),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.slate700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
