import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard_widgets.dart';
import '../../widgets/shared_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return switch (state.role) {
      'Student Assistant' => const _StudentAssistantDashboard(),
      'Supervisor' => const _SupervisorDashboard(),
      'Admin' => const _AdminDashboard(),
      // Head: full operational overview (students, attendance, reports).
      _ => const _HeadDashboard(),
    };
  }
}

/// Shared page frame: padding, heading, an optional lead card, the stats,
/// then the sections.
class _DashboardPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? lead;
  final List<DashboardStatTile> stats;
  final List<Widget> sections;

  const _DashboardPage({
    required this.title,
    required this.subtitle,
    this.lead,
    required this.stats,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = DashboardMetrics.of(context);
    return SingleChildScrollView(
      padding: metrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardHeading(title: title, subtitle: subtitle),
          SizedBox(height: metrics.isMobile ? 18 : 26),
          if (lead != null) ...[lead!, SizedBox(height: metrics.gap)],
          DashboardStatRow(tiles: stats),
          SizedBox(height: metrics.sectionGap),
          ...sections,
        ],
      ),
    );
  }
}

// ─── Head dashboard ────────────────────────────────────
class _HeadDashboard extends StatelessWidget {
  const _HeadDashboard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stats = state.dashboardStats;
    final metrics = DashboardMetrics.of(context);

    return _DashboardPage(
      title: 'Dashboard',
      subtitle: 'Overview of student assistant activity',
      stats: [
        DashboardStatTile(
          label: 'Total students',
          value: '${stats['totalStudents']}',
          icon: Icons.people_outline_rounded,
        ),
        DashboardStatTile(
          label: 'Active today',
          value: '${stats['activeToday']}',
          icon: Icons.access_time_rounded,
          tone: StatTone.good,
        ),
        DashboardStatTile(
          label: 'Pending reports',
          value: '${stats['pendingReports']}',
          icon: Icons.description_outlined,
          tone: StatTone.attention,
        ),
        DashboardStatTile(
          label: 'Avg. hours/week',
          value: stats['avgHoursPerWeek'],
          icon: Icons.bar_chart_rounded,
        ),
      ],
      sections: [
        _CampusDistributionSection(
          state: state,
          isMobileScreen: metrics.isMobile,
        ),
        SizedBox(height: metrics.sectionGap),
        if (metrics.isSmall)
          Column(
            children: [
              _RecentAttendanceSection(
                state: state,
                isMobileScreen: metrics.isMobile,
              ),
              SizedBox(height: metrics.gap + 8),
              _SystemStatusSection(
                isMobileScreen: metrics.isMobile,
                state: state,
              ),
            ],
          )
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _RecentAttendanceSection(
                    state: state,
                    isMobileScreen: false,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _SystemStatusSection(
                    isMobileScreen: false,
                    state: state,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Student Assistant dashboard (personal view only) ──
class _StudentAssistantDashboard extends StatelessWidget {
  const _StudentAssistantDashboard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final name = state.currentUser?.name ?? '';

    final myTasks = state.filteredTasks; // already scoped to this SA
    final myReports = state.filteredReports
        .where((r) => r.studentName == name)
        .toList();
    final myAttendance = state.filteredAttendance; // already scoped to this SA

    final totalHours = myAttendance
        .where((r) => r.countsTowardHours)
        .fold<double>(0, (sum, r) => sum + (r.totalHours ?? 0));
    final pendingTasks = myTasks.where((t) => t.status != 'Completed').length;
    final pendingReports = myReports.where((r) => r.status == 'Pending').length;

    return _DashboardPage(
      title: 'Welcome back, ${name.split(' ').first}',
      subtitle: 'Here\'s a quick look at your activity',
      // Duty status lives in the Today card, so there's no "On duty" tile.
      lead: const _TodayCard(),
      stats: [
        DashboardStatTile(
          label: 'My total hours',
          value: totalHours.toStringAsFixed(1),
          icon: Icons.access_time_rounded,
        ),
        DashboardStatTile(
          label: 'Pending tasks',
          value: '$pendingTasks',
          icon: Icons.task_alt_outlined,
          tone: pendingTasks > 0 ? StatTone.attention : StatTone.brand,
        ),
        DashboardStatTile(
          label: 'Pending reports',
          value: '$pendingReports',
          icon: Icons.description_outlined,
          tone: pendingReports > 0 ? StatTone.attention : StatTone.brand,
        ),
      ],
      sections: [
        DashboardSectionCard(
          title: 'My Tasks',
          actionLabel: 'View all',
          onAction: () => state.setTab('tasks'),
          child: myTasks.isEmpty
              ? const DashboardEmptyRow(
                  icon: Icons.task_alt_outlined,
                  message: 'No tasks assigned yet',
                )
              : Column(
                  children: myTasks
                      .take(4)
                      .map((t) => _TaskTile(task: t))
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        DashboardSectionCard(
          title: 'Recent Attendance',
          actionLabel: 'View all',
          onAction: () => state.setTab('attendance'),
          child: myAttendance.isEmpty
              ? const DashboardEmptyRow(
                  icon: Icons.access_time_outlined,
                  message: 'No attendance records yet',
                )
              : Column(
                  children: myAttendance
                      .take(3)
                      .map((a) => _AttendanceTile(record: a))
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        DashboardSectionCard(
          title: 'My Reports',
          actionLabel: 'View all',
          onAction: () => state.setTab('reports'),
          child: myReports.isEmpty
              ? const DashboardEmptyRow(
                  icon: Icons.description_outlined,
                  message: 'No reports submitted yet',
                )
              : Column(
                  children: myReports
                      .take(3)
                      .map((r) => _ReportTile(report: r))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

// ─── Student Assistant: Today card ─────────────────────
/// What a student assistant needs first: whether they're on duty and until
/// when, and how much of the weekly hours cap they've used. Follows
/// clock-attendance's rules: two sessions a day, a session that isn't timed
/// out before it ends doesn't count, and while the Admin's cap is on at most
/// [AppState.weeklyHourCap] hours are credited per Monday–Sunday week.
class _TodayCard extends StatefulWidget {
  const _TodayCard();

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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

  // Nothing notifies when the clock moves, so tick to keep the time on duty
  // and the session status current.
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final metrics = DashboardMetrics.of(context);
    final now = DateTime.now();

    final status = _DutyStatus(state: state, now: now);
    final week = _WeekHours(state: state, now: now);

    return DashboardSectionCard(
      title: 'Today',
      subtitle:
          '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}',
      actionLabel: 'Attendance',
      onAction: () => state.setTab('attendance'),
      child: metrics.isSmall
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                status,
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: AppTheme.slate100),
                ),
                week,
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: status),
                  const VerticalDivider(
                    width: 40,
                    thickness: 1,
                    color: AppTheme.slate100,
                  ),
                  Expanded(child: week),
                ],
              ),
            ),
    );
  }
}

/// Left half of the Today card: on duty or not, and what that means now.
class _DutyStatus extends StatelessWidget {
  final AppState state;
  final DateTime now;

  const _DutyStatus({required this.state, required this.now});

  @override
  Widget build(BuildContext context) {
    final record = state.activeAttendanceRecord;
    final start = state.activeDutyStart;
    final onDuty = record != null;
    final atCap =
        state.enforceAssistantHourCap &&
        state.myCreditedHoursThisWeek >= AppState.weeklyHourCap;
    final creditedToday = state.myCreditedHoursToday;

    final String headline;
    final String detail;
    String? hint;
    if (onDuty) {
      headline = start == null
          ? 'On duty'
          : 'On duty · ${_formatElapsed(now.difference(start))}';
      detail = 'Timed in at ${record.timeIn}';
      final session = start == null
          ? null
          : state.attendanceQrSessionLabel(start);
      final end = start == null ? null : state.attendanceQrSessionEnd(start);
      if (session != null && end != null) {
        hint =
            '$session ends at ${_formatClock(end)}. Time out before then, '
            'or this session won\'t count.';
      }
    } else {
      headline = 'Not on duty';
      final session = state.attendanceQrSessionLabel(now);
      final next = state.nextAttendanceSessionStart(now);
      if (atCap) {
        detail =
            'You\'ve reached this week\'s '
            '${_formatHours(AppState.weeklyHourCap)}-hour limit.';
        hint = 'You can time in again on Monday.';
      } else if (session != null) {
        detail =
            '$session is open until '
            '${_formatClock(state.attendanceQrSessionEnd(now)!)}.';
        hint = 'Scan the attendance QR code on the Attendance page to time in.';
      } else if (next != null) {
        detail =
            '${state.attendanceQrSessionLabel(next)} opens at '
            '${_formatClock(next)}.';
      } else {
        detail = 'Today\'s sessions are over.';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: onDuty ? AppTheme.emerald500 : AppTheme.slate300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                headline,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate700,
            height: 1.4,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 3),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.slate500,
              height: 1.4,
            ),
          ),
        ],
        if (creditedToday > 0) ...[
          const SizedBox(height: 10),
          Text(
            '${_hoursPhrase(creditedToday)} credited today',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate500,
            ),
          ),
        ],
        if (state.myMissedTimeOutToday) ...[
          const SizedBox(height: 10),
          const _CardNote(
            text: 'You missed a time-out today, so that session didn\'t count.',
          ),
        ],
      ],
    );
  }
}

/// Right half of the Today card: this week's credited hours against the cap.
class _WeekHours extends StatelessWidget {
  final AppState state;
  final DateTime now;

  const _WeekHours({required this.state, required this.now});

  @override
  Widget build(BuildContext context) {
    const cap = AppState.weeklyHourCap;
    final credited = state.myCreditedHoursThisWeek;
    final capOn = state.enforceAssistantHourCap;
    final start = state.activeDutyStart;
    final running = start == null || now.isBefore(start)
        ? 0.0
        : now.difference(start).inMinutes / 60.0;
    final full = credited >= cap;
    final left = full ? 0.0 : cap - credited;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'This week',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _formatHours(credited),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: capOn
                    ? ' of ${_formatHours(cap)} hours'
                    : (credited == 1 ? ' hour' : ' hours'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate500,
                ),
              ),
            ],
          ),
        ),
        if (capOn) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (credited / cap).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.slate100,
              valueColor: AlwaysStoppedAnimation<Color>(
                full ? AppTheme.amber500 : AppTheme.maroon,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            full
                ? 'Limit reached · resets Monday'
                : '${_hoursPhrase(left)} left · resets Monday',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate500,
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          const Text(
            'No weekly hour limit is set this year.',
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ],
        if (start != null) ...[
          const SizedBox(height: 10),
          if (capOn && !full && running >= left)
            _CardNote(
              text:
                  'This session has used up the week\'s hours. Time past '
                  '${_formatHours(cap)} hours won\'t count.',
            )
          else
            const Text(
              'Your current session is added when you time out.',
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
        ],
      ],
    );
  }
}

/// A short warning inside the Today card.
class _CardNote extends StatelessWidget {
  final String text;

  const _CardNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.amber50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: AppTheme.amber500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `6.5`, or `6` rather than `6.0`.
String _formatHours(double hours) {
  final text = hours.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// `1 hour`, `6.5 hours`.
String _hoursPhrase(double hours) =>
    hours == 1 ? '1 hour' : '${_formatHours(hours)} hours';

/// `12:00 PM` — the shape attendance times are stored in.
String _formatClock(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

/// `1h 42m`, `42m`.
String _formatElapsed(Duration elapsed) {
  if (elapsed.inMinutes < 1) return 'just started';
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes % 60;
  if (hours == 0) return '${minutes}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

// ─── Admin dashboard (Accounts / Departments / Settings scope) ──
class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final name = state.currentUser?.name ?? '';

    final activeUsers = state.users
        .where((u) => u.status != 'Archived')
        .toList();
    final totalAccounts = activeUsers.length;
    final headCount = activeUsers.where((u) => u.role == 'Head').length;
    final supervisorCount = activeUsers
        .where((u) => u.role == 'Supervisor')
        .length;
    final studentAssistantCount = activeUsers
        .where((u) => u.role == 'Student Assistant')
        .length;
    final totalDepartments = state.departments.length;

    return _DashboardPage(
      title: 'Welcome back, ${name.split(' ').first}',
      subtitle: 'Manage accounts, departments, and system settings',
      stats: [
        DashboardStatTile(
          label: 'Total accounts',
          value: '$totalAccounts',
          icon: Icons.manage_accounts_outlined,
        ),
        DashboardStatTile(
          label: 'Heads',
          value: '$headCount',
          icon: Icons.workspace_premium_outlined,
        ),
        DashboardStatTile(
          label: 'Supervisors',
          value: '$supervisorCount',
          icon: Icons.supervisor_account_outlined,
        ),
        DashboardStatTile(
          label: 'Departments',
          value: '$totalDepartments',
          icon: Icons.business_outlined,
        ),
      ],
      sections: [
        DashboardSectionCard(
          title: 'Role Breakdown',
          // The bar covers the three staffed roles, so it says so rather
          // than quoting the account total — admin accounts are not in it.
          subtitle:
              '${headCount + supervisorCount + studentAssistantCount} '
              'of $totalAccounts accounts are staffed roles',
          child: _RoleBreakdown(
            counts: {
              'Heads': headCount,
              'Supervisors': supervisorCount,
              'Student Assistants': studentAssistantCount,
            },
          ),
        ),
        const SizedBox(height: 18),
        DashboardSectionCard(
          title: 'Quick Actions',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AdminQuickAction(
                label: 'Manage Accounts',
                icon: Icons.manage_accounts_outlined,
                onTap: () => state.setTab('accounts'),
              ),
              _AdminQuickAction(
                label: 'Manage Departments',
                icon: Icons.business_outlined,
                onTap: () => state.setTab('departments'),
              ),
              _AdminQuickAction(
                label: 'Settings',
                icon: Icons.settings_outlined,
                onTap: () => state.setTab('settings'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Part-to-whole across the three staffed roles.
///
/// A stacked bar rather than three coloured dots: the roles are shares of one
/// total, and the bar shows that directly. Every segment is direct-labelled
/// below, so identity never rests on colour alone.
class _RoleBreakdown extends StatelessWidget {
  final Map<String, int> counts;

  const _RoleBreakdown({required this.counts});

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    if (total == 0) {
      return const DashboardEmptyRow(
        icon: Icons.groups_outlined,
        message: 'No active accounts yet',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            // Explicitly full width: the parent Column aligns to start, so a
            // Row of nothing but Expanded children would size to zero.
            width: double.infinity,
            height: 10,
            child: Row(
              // Stretch, or each segment is a childless ColoredBox that the
              // Row centres at zero height and nothing is drawn.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++)
                  if (entries[i].value > 0) ...[
                    // A 2px surface gap between segments keeps adjacent
                    // fills from reading as one block.
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: entries[i].value,
                      child: ColoredBox(
                        color: ChartPalette.categorical[i],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == entries.length - 1 ? 0 : 10),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: ChartPalette.categorical[i],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
                Text(
                  '${entries[i].value}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(entries[i].value / total * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AdminQuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AdminQuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.maroon50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.maroon100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: AppTheme.maroon),
              const SizedBox(width: 9),
              // Bounded so a long action name wraps the chip instead of
              // running off the card on a narrow phone.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.maroon,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Supervisor dashboard ──────────────────────────────
class _SupervisorDashboard extends StatelessWidget {
  const _SupervisorDashboard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final metrics = DashboardMetrics.of(context);

    final assignedStudents = state.filteredStudents.length;
    final activeToday = state.filteredAttendance
        .where((e) => e.isActive && !e.isInvalid)
        .length;
    final pendingReports = state.filteredReports
        .where((e) => e.status == 'Pending')
        .length;
    final pendingTasks = state.filteredTasks
        .where((e) => e.status != 'Completed')
        .length;

    return _DashboardPage(
      title: 'Supervisor Dashboard',
      subtitle: 'Your assigned student assistants at a glance',
      stats: [
        DashboardStatTile(
          label: 'Assigned students',
          value: '$assignedStudents',
          icon: Icons.people_outline_rounded,
        ),
        DashboardStatTile(
          label: 'Active today',
          value: '$activeToday',
          icon: Icons.access_time_rounded,
          tone: StatTone.good,
        ),
        DashboardStatTile(
          label: 'Pending reports',
          value: '$pendingReports',
          icon: Icons.description_outlined,
          tone: pendingReports > 0 ? StatTone.attention : StatTone.brand,
        ),
        DashboardStatTile(
          label: 'Pending tasks',
          value: '$pendingTasks',
          icon: Icons.task_alt_outlined,
          tone: pendingTasks > 0 ? StatTone.attention : StatTone.brand,
        ),
      ],
      sections: [
        if (metrics.isSmall)
          Column(
            children: [
              _SupervisorAttendanceSection(
                state: state,
                isMobileScreen: metrics.isMobile,
              ),
              const SizedBox(height: 18),
              _SupervisorSummarySection(
                state: state,
                isMobileScreen: metrics.isMobile,
              ),
              const SizedBox(height: 18),
              _SupervisorReportsSection(state: state),
              const SizedBox(height: 18),
              // Previously dropped below 768px, which left phone users with
              // no way to reach these from the dashboard at all.
              _SupervisorQuickActions(state: state),
            ],
          )
        else
          Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _SupervisorAttendanceSection(
                        state: state,
                        isMobileScreen: false,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _SupervisorSummarySection(
                        state: state,
                        isMobileScreen: false,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SupervisorReportsSection(state: state),
              const SizedBox(height: 20),
              _SupervisorQuickActions(state: state),
            ],
          ),
      ],
    );
  }
}
class _TaskTile extends StatelessWidget {
  final Task task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.slate900)),
                const SizedBox(height: 2),
                Text('Due: ${task.dueDate}', style: const TextStyle(fontSize: 11, color: AppTheme.slate500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge.fromStatus(task.displayStatus),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final Report report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.slate900)),
                if (report.submittedAt != null) ...[
                  const SizedBox(height: 2),
                  Text('Submitted: ${report.submittedAt}', style: const TextStyle(fontSize: 11, color: AppTheme.slate500)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge.fromStatus(report.status),
        ],
      ),
    );
  }
}

// ─── Campus Distribution section ───────────────────────
class _CampusDistributionSection extends StatefulWidget {
  final AppState state;
  final bool isMobileScreen;
  const _CampusDistributionSection({required this.state, required this.isMobileScreen});

  @override
  State<_CampusDistributionSection> createState() => _CampusDistributionSectionState();
}

class _CampusDistributionSectionState extends State<_CampusDistributionSection> {
  static const _allCampuses = 'All Campuses';
  late String _selectedCampus = _allCampuses;

  String _label(String c) => c == _allCampuses ? c : c.replaceAll(' Campus', '');

  static const _deptColors = [
    AppTheme.maroon,
    AppTheme.gold400,
    AppTheme.blue500,
    AppTheme.emerald500,
    AppTheme.amber500,
    AppTheme.maroonLight,
  ];

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isMobileScreen = widget.isMobileScreen;
    final campuses = state.campuses;
    final isAllSelected = _selectedCampus == _allCampuses;
    final perCampusCounts = state.studentsPerCampus;

    final trend = isAllSelected
        ? const <({String academicYear, int count})>[]
        : [
            for (final year in state.enrollmentHistory)
              (academicYear: year.academicYear, count: year.byCampus[_selectedCampus] ?? 0),
          ];

    final deptCounts = isAllSelected
        ? (() {
            final counts = <String, int>{};
            for (final c in campuses) {
              state.departmentBreakdownForCampus(c).forEach((dept, n) {
                counts[dept] = (counts[dept] ?? 0) + n;
              });
            }
            return counts;
          })()
        : state.departmentBreakdownForCampus(_selectedCampus);

    final totalOnCampus = deptCounts.values.fold<int>(0, (a, b) => a + b);
    final topDept = deptCounts.entries.isEmpty
        ? '—'
        : (deptCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student Assistants by Campus',
          style: TextStyle(fontSize: isMobileScreen ? 16 : 18, fontWeight: FontWeight.w800, color: AppTheme.slate900),
        ),
        const SizedBox(height: 4),
        Text(
          'Multi-year growth and department breakdown per campus',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppTheme.slate500),
        ),
        const SizedBox(height: 14),

        // Campus selector pills
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [_allCampuses, ...campuses].map((c) {
            final selected = c == _selectedCampus;
            return GestureDetector(
              onTap: () => setState(() => _selectedCampus = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.maroon : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? AppTheme.maroon : AppTheme.slate200),
                ),
                child: Text(
                  _label(c),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.slate600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // Enrollment (all campuses) or growth (one campus) card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.slate200, width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          padding: EdgeInsets.all(isMobileScreen ? 16 : 22),
          child: isAllSelected
              ? _CampusEnrollmentChart(counts: perCampusCounts, isMobileScreen: isMobileScreen)
              : _CampusGrowthChart(campus: _label(_selectedCampus), trend: trend, isMobileScreen: isMobileScreen),
        ),

        const SizedBox(height: 16),

        // Department breakdown card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.slate200, width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          padding: EdgeInsets.all(isMobileScreen ? 16 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isMobileScreen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'By Department — ${_label(_selectedCampus)}',
                          style: TextStyle(fontSize: isMobileScreen ? 14 : 15, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$totalOnCampus total  •  Top: ${topDept == '—' ? '—' : topDept.replaceAll('College of ', '')}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.slate500),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'By Department — ${_label(_selectedCampus)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: isMobileScreen ? 14 : 15, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$totalOnCampus total  •  Top: ${topDept == '—' ? '—' : topDept.replaceAll('College of ', '')}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.slate500),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              if (deptCounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: EmptyState(icon: Icons.business_outlined, message: 'No student assistants in this campus yet'),
                )
              else
                ...deptCounts.entries.toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final dept = entry.value.key;
                  final count = entry.value.value;
                  final maxCount = deptCounts.values.reduce((a, b) => a > b ? a : b);
                  final fraction = maxCount == 0 ? 0.0 : count / maxCount;
                  final color = _deptColors[index % _deptColors.length];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: isMobileScreen ? 110 : 190,
                          child: Text(
                            dept,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.slate700),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: fraction.clamp(0.03, 1.0),
                              minHeight: 10,
                              backgroundColor: AppTheme.slate100,
                              valueColor: AlwaysStoppedAnimation(color),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 22,
                          child: Text(
                            '$count',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

/// Title, subtitle and an optional chip, shared by the campus charts. On
/// phones the chip drops below the subtitle instead of squeezing the title.
class _ChartHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? chip;
  final bool isMobileScreen;

  const _ChartHeader({
    required this.title,
    required this.subtitle,
    this.chip,
    required this.isMobileScreen,
  });

  @override
  Widget build(BuildContext context) {
    final chipWidget = chip == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              chip!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate600,
              ),
            ),
          );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobileScreen ? 14 : 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.slate900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppTheme.slate500,
          ),
        ),
        if (isMobileScreen && chipWidget != null) ...[
          const SizedBox(height: 8),
          chipWidget,
        ],
      ],
    );
    if (isMobileScreen || chipWidget == null) return heading;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        const SizedBox(width: 10),
        chipWidget,
      ],
    );
  }
}

String _studentAssistants(int count) =>
    count == 1 ? '1 student assistant' : '$count student assistants';

/// Headcount across every campus, shown when "All Campuses" is selected.
///
/// Columns, not a line: the campuses are separate places, and a line
/// between them would suggest a trend from one to the next. Headcount is
/// one series, so every column is the same colour; the campus names on the
/// axis carry identity.
class _CampusEnrollmentChart extends StatelessWidget {
  final Map<String, int> counts;
  final bool isMobileScreen;

  const _CampusEnrollmentChart({
    required this.counts,
    required this.isMobileScreen,
  });

  // A column's value label and the gap above the column.
  static const _labelHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final maxCount = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    final plotHeight = isMobileScreen ? 150.0 : 190.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartHeader(
          title: 'Enrollment by Campus',
          subtitle: 'Student assistants currently enrolled, by campus',
          chip: '$total total',
          isMobileScreen: isMobileScreen,
        ),
        const SizedBox(height: 18),
        if (total == 0)
          SizedBox(
            height: plotHeight,
            child: const Center(
              child: Text(
                'No enrollment data yet',
                style: TextStyle(color: AppTheme.slate400),
              ),
            ),
          )
        else ...[
          SizedBox(
            height: plotHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in counts.entries)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${entry.key.replaceAll(' Campus', '')}: '
                          '${_studentAssistants(entry.value)}',
                      // Transparent but hit-testable, so hovering anywhere in
                      // the campus's band shows its tooltip.
                      child: ColoredBox(
                        color: Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${entry.value}',
                              style: TextStyle(
                                fontSize: isMobileScreen ? 12 : 13,
                                fontWeight: FontWeight.w800,
                                // A campus with none reads as empty, not as
                                // a value to compare.
                                color: entry.value == 0
                                    ? AppTheme.slate400
                                    : AppTheme.slate900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 24,
                              height:
                                  (plotHeight - _labelHeight) *
                                  entry.value /
                                  maxCount,
                              decoration: const BoxDecoration(
                                color: ChartPalette.series,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // The baseline every column grows from.
          Container(height: 1, color: AppTheme.slate200),
        ],
        const SizedBox(height: 10),
        Row(
          children: counts.keys.map((campus) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobileScreen ? 2 : 4,
                ),
                child: Text(
                  campus.replaceAll(' Campus', ''),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobileScreen ? 10.5 : 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// One campus's headcount, year over year.
///
/// A trend needs two points, so while only the current school year has a
/// headcount this shows that number rather than a lone dot on an empty
/// chart. Past years come from the headcount saved when each year is closed
/// ([AppState.enrollmentHistory]).
class _CampusGrowthChart extends StatelessWidget {
  final String campus;
  final List<({String academicYear, int count})> trend;
  final bool isMobileScreen;

  const _CampusGrowthChart({
    required this.campus,
    required this.trend,
    required this.isMobileScreen,
  });

  @override
  Widget build(BuildContext context) {
    // The most recent years that fit across the card.
    final maxYears = isMobileScreen ? 4 : 6;
    final shown = trend.length > maxYears
        ? trend.sublist(trend.length - maxYears)
        : trend;
    final current = shown.last;
    final previous = shown.length > 1 ? shown[shown.length - 2] : null;
    final change = previous == null ? 0 : current.count - previous.count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartHeader(
          title: 'Multi-Year Growth',
          subtitle: 'Student assistant headcount per school year, $campus',
          chip: previous == null
              ? null
              : change == 0
              ? 'No change from AY ${previous.academicYear}'
              : '${change > 0 ? '+' : '−'}${change.abs()} from '
                    'AY ${previous.academicYear}',
          isMobileScreen: isMobileScreen,
        ),
        const SizedBox(height: 18),
        if (previous == null) ...[
          Text(
            '${current.count}',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${current.count == 1 ? 'student assistant' : 'student assistants'}'
            ' in AY ${current.academicYear}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate600,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'The trend appears here once a second school year is recorded. '
            "Each year's headcount is saved when that school year is closed.",
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.slate400,
            ),
          ),
        ] else
          _GrowthLineChart(points: shown, isMobileScreen: isMobileScreen),
      ],
    );
  }
}

class _GrowthLineChart extends StatelessWidget {
  final List<({String academicYear, int count})> points;
  final bool isMobileScreen;

  const _GrowthLineChart({required this.points, required this.isMobileScreen});

  // Room on the left for the y-axis numbers, and above the plot for the
  // latest year's label.
  static const _axisWidth = 28.0;
  static const _headroom = 24.0;

  /// A round step giving about three gridlines from zero up to [maxValue].
  static int _tickStep(int maxValue) {
    if (maxValue <= 3) return 1;
    final raw = maxValue / 3;
    var magnitude = 1;
    while (magnitude * 10 <= raw) {
      magnitude *= 10;
    }
    for (final multiple in const [1, 2, 5]) {
      if (multiple * magnitude >= raw) return multiple * magnitude;
    }
    return 10 * magnitude;
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = points.fold<int>(0, (a, p) => a > p.count ? a : p.count);
    final step = _tickStep(maxCount);
    // Always from zero, so the line's height is the headcount itself.
    final top = maxCount <= step ? step : (maxCount / step).ceil() * step;
    final ticks = [for (var v = 0; v <= top; v += step) v];

    return Column(
      children: [
        SizedBox(
          height: isMobileScreen ? 150 : 180,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = (constraints.maxWidth - _axisWidth) / points.length;
              double yFor(int value) =>
                  constraints.maxHeight -
                  value / top * (constraints.maxHeight - _headroom);
              final offsets = [
                for (var i = 0; i < points.length; i++)
                  Offset(_axisWidth + slot * (i + 0.5), yFor(points[i].count)),
              ];

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GrowthLinePainter(
                        points: offsets,
                        gridLines: [for (final t in ticks) yFor(t)],
                        left: _axisWidth,
                      ),
                    ),
                  ),
                  for (final t in ticks)
                    Positioned(
                      left: 0,
                      width: _axisWidth - 8,
                      top: yFor(t) - 7,
                      child: Text(
                        '$t',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate400,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  // Only the latest year is labelled; the axis and the
                  // tooltips carry the rest.
                  Positioned(
                    left: offsets.last.dx - 30,
                    width: 60,
                    top: offsets.last.dy - 24,
                    child: Text(
                      '${points.last.count}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isMobileScreen ? 12 : 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                  ),
                  for (var i = 0; i < points.length; i++)
                    Positioned(
                      left: offsets[i].dx - 14,
                      top: offsets[i].dy - 14,
                      width: 28,
                      height: 28,
                      child: Tooltip(
                        message:
                            'AY ${points[i].academicYear}: '
                            '${_studentAssistants(points[i].count)}',
                        child: const ColoredBox(color: Colors.transparent),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: _axisWidth),
          child: Row(
            children: [
              for (final p in points)
                Expanded(
                  child: Text(
                    p.academicYear,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Gridlines, a faint wash under the line, the 2px line and its markers.
class _GrowthLinePainter extends CustomPainter {
  final List<Offset> points;
  final List<double> gridLines;
  final double left;

  _GrowthLinePainter({
    required this.points,
    required this.gridLines,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The first gridline is zero: the baseline, one step darker.
    for (var i = 0; i < gridLines.length; i++) {
      canvas.drawLine(
        Offset(left, gridLines[i]),
        Offset(size.width, gridLines[i]),
        Paint()
          ..color = i == 0 ? AppTheme.slate200 : AppTheme.slate100
          ..strokeWidth = 1,
      );
    }
    if (points.isEmpty) return;

    final baseline = gridLines.first;
    final area = Path()..moveTo(points.first.dx, baseline);
    for (final p in points) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(points.last.dx, baseline)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = ChartPalette.series.withValues(alpha: 0.10),
    );

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = ChartPalette.series
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Markers with a ring in the card's colour, so they stay legible where
    // they sit on the line.
    for (final p in points) {
      canvas.drawCircle(p, 6.5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4.5, Paint()..color = ChartPalette.series);
    }
  }

  @override
  bool shouldRepaint(covariant _GrowthLinePainter oldDelegate) =>
      !listEquals(oldDelegate.points, points) ||
      !listEquals(oldDelegate.gridLines, gridLines) ||
      oldDelegate.left != left;
}

class _SupervisorSummarySection extends StatelessWidget {
  final AppState state;
  final bool isMobileScreen;

  const _SupervisorSummarySection({required this.state, required this.isMobileScreen});

  @override
  Widget build(BuildContext context) {
    final activeToday = state.filteredAttendance.where((a) => a.isActive).length;
    final pendingReports = state.filteredReports.where((r) => r.status == 'Pending').length;
    final pendingTasks = state.filteredTasks.where((t) => t.status != 'Completed').length;
    final completedTasks = state.filteredTasks.where((t) => t.status == 'Completed').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Summary",
          style: TextStyle(fontSize: isMobileScreen ? 16 : 18, fontWeight: FontWeight.w800, color: AppTheme.slate900),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.slate200),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: .03), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _SupervisorInfoTile(icon: Icons.people_alt_outlined, title: 'Students On Duty', value: '$activeToday', color: AppTheme.emerald500),
              const SizedBox(height: 14),
              _SupervisorInfoTile(icon: Icons.description_outlined, title: 'Pending Reports', value: '$pendingReports', color: AppTheme.amber500),
              const SizedBox(height: 14),
              _SupervisorInfoTile(icon: Icons.task_alt_outlined, title: 'Pending Tasks', value: '$pendingTasks', color: AppTheme.blue500),
              const SizedBox(height: 14),
              _SupervisorInfoTile(icon: Icons.check_circle_outline, title: 'Completed Tasks', value: '$completedTasks', color: AppTheme.emerald500),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppTheme.maroon.withValues(alpha: .08), AppTheme.gold50]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Row(
            children: [
              const Icon(Icons.supervisor_account_rounded, color: AppTheme.maroon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Monitor attendance, reports and assigned tasks.',
                  style: TextStyle(color: AppTheme.slate600, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupervisorInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _SupervisorInfoTile({required this.icon, required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
        ),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SupervisorAttendanceSection extends StatelessWidget {
  final AppState state;
  final bool isMobileScreen;

  const _SupervisorAttendanceSection({required this.state, required this.isMobileScreen});

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: "Today's Attendance",
      actionLabel: 'View All',
      onAction: () => state.setTab('attendance'),
      child: state.filteredAttendance.isEmpty
          ? const DashboardEmptyRow(icon: Icons.access_time_outlined, message: 'No attendance records')
          : Column(children: state.filteredAttendance.take(5).map((e) => _AttendanceTile(record: e)).toList()),
    );
  }
}

class _SupervisorReportsSection extends StatelessWidget {
  final AppState state;

  const _SupervisorReportsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final reports = state.filteredReports.where((e) => e.status == 'Pending').toList();

    return DashboardSectionCard(
      title: 'Pending Reports',
      actionLabel: 'View All',
      onAction: () => state.setTab('reports'),
      child: reports.isEmpty
          ? const DashboardEmptyRow(icon: Icons.description_outlined, message: 'No pending reports')
          : Column(children: reports.take(5).map((r) => _ReportTile(report: r)).toList()),
    );
  }
}

class _SupervisorQuickActions extends StatelessWidget {
  final AppState state;

  const _SupervisorQuickActions({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.slate900)),
        const SizedBox(height: 14),
        // The cards used to be a fixed 260px wide, which is wider than a
        // 320px phone has room for once padding is taken off. They now
        // divide whatever width there is.
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 16.0;
            final columns = ((constraints.maxWidth + gap) / (260 + gap))
                .floor()
                .clamp(1, 3);
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _QuickActionCard(width: width, icon: Icons.access_time_rounded, color: AppTheme.emerald500, title: 'Attendance', subtitle: 'Monitor attendance records', onTap: () => state.setTab('attendance')),
                _QuickActionCard(width: width, icon: Icons.description_outlined, color: AppTheme.amber500, title: 'Reports', subtitle: 'Review submitted reports', onTap: () => state.setTab('reports')),
                _QuickActionCard(width: width, icon: Icons.task_alt_outlined, color: AppTheme.blue500, title: 'Tasks', subtitle: 'Manage assigned tasks', onTap: () => state.setTab('tasks')),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  final double width;

  const _QuickActionCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap, required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.slate200),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: .03), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: AppTheme.slate400),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Recent Attendance section ─────────────────────────
class _RecentAttendanceSection extends StatelessWidget {
  final AppState state;
  final bool isMobileScreen;
  const _RecentAttendanceSection({required this.state, required this.isMobileScreen});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Recent Attendance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: isMobileScreen ? 16 : 18, fontWeight: FontWeight.w800, color: AppTheme.slate900),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => state.setTab('attendance'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View All', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.maroon)),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_rounded, size: 15, color: AppTheme.maroon),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.slate200, width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: state.filteredAttendance.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyState(icon: Icons.access_time_outlined, message: 'No recent attendance records'),
                )
              : Column(
                  children: state.filteredAttendance.take(3).map((a) => _AttendanceTile(record: a)).toList(),
                ),
        ),
      ],
    );
  }
}

// ─── System Status section ─────────────────────────────
class _SystemStatusSection extends StatelessWidget {
  final bool isMobileScreen;
  final AppState state;
  const _SystemStatusSection({required this.isMobileScreen, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'System Status',
          style: TextStyle(fontSize: isMobileScreen ? 16 : 18, fontWeight: FontWeight.w800, color: AppTheme.slate900),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.slate200, width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _SystemStatusItem(label: 'Database', isHealthy: state.dbHealthy),
              const SizedBox(height: 14),
              _SystemStatusItem(label: 'Auth Service', isHealthy: state.authHealthy),
              const SizedBox(height: 14),
              _SystemStatusItem(label: 'Reports', isHealthy: state.reportsHealthy),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.emerald50, AppTheme.slate50],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.slate200, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.emerald500),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Response time: ${state.responseTimeMs}ms',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SystemStatusItem extends StatelessWidget {
  final String label;
  final bool isHealthy;

  const _SystemStatusItem({required this.label, required this.isHealthy});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isHealthy ? AppTheme.emerald500 : AppTheme.red500,
            boxShadow: [
              BoxShadow(
                color: (isHealthy ? AppTheme.emerald500 : AppTheme.red500).withValues(alpha: 0.4),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: (isHealthy ? AppTheme.emerald500 : AppTheme.red500).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isHealthy ? 'Healthy' : 'Down',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isHealthy ? AppTheme.emerald500 : AppTheme.red500,
            ),
          ),
        ),
      ],
    );
  }
}

class _AttendanceTile extends StatelessWidget {
  final dynamic record;
  const _AttendanceTile({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: record.isActive ? AppTheme.emerald50 : AppTheme.slate100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.access_time_rounded, size: 18, color: record.isActive ? AppTheme.emerald500 : AppTheme.slate400),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.slate900),
                ),
                const SizedBox(height: 2),
                Text('${record.date}  •  In: ${record.timeIn}', style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge.fromStatus(record.isActive ? 'On Duty' : 'Completed'),
        ],
      ),
    );
  }
}
