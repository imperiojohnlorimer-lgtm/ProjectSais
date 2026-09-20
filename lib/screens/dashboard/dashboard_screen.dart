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

/// Shared page frame: padding, heading, then the sections.
class _DashboardPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<DashboardStatTile> stats;
  final List<Widget> sections;

  const _DashboardPage({
    required this.title,
    required this.subtitle,
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
    final activeRecord = state.activeAttendanceRecord;

    final totalHours = myAttendance.fold<double>(
      0,
      (sum, r) => sum + (r.totalHours ?? 0),
    );
    final pendingTasks = myTasks.where((t) => t.status != 'Completed').length;
    final pendingReports = myReports.where((r) => r.status == 'Pending').length;
    final onDuty = activeRecord != null;

    return _DashboardPage(
      title: 'Welcome back, ${name.split(' ').first}',
      subtitle: 'Here\'s a quick look at your activity',
      stats: [
        DashboardStatTile(
          label: 'My total hours',
          value: totalHours.toStringAsFixed(1),
          icon: Icons.access_time_rounded,
        ),
        DashboardStatTile(
          label: 'On duty',
          value: onDuty ? 'Yes' : 'No',
          icon: Icons.badge_outlined,
          tone: onDuty ? StatTone.good : StatTone.muted,
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

    final trend = isAllSelected ? const <int?>[] : (state.campusGrowthTrend[_selectedCampus] ?? const <int?>[]);

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

        // Line chart card
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
              ? _AllCampusesBarChart(counts: perCampusCounts, isMobileScreen: isMobileScreen)
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Multi-Year Growth',
                          style: TextStyle(fontSize: isMobileScreen ? 14 : 15, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Student assistant headcount trend, ${_selectedCampus.replaceAll(' Campus', '')}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  ),
                  if (trend.isNotEmpty && trend.first != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${trend.first} enrolled  •  ${state.growthYears.first}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.emerald500),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: isMobileScreen ? 160 : 200,
                width: double.infinity,
                child: trend.isEmpty
                    ? const Center(child: Text('No trend data', style: TextStyle(color: AppTheme.slate400)))
                    : CustomPaint(
                        painter: _LineChartPainter(values: trend.map((e) => e?.toDouble()).toList()),
                        child: Container(),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: state.growthYears.map((y) {
                  return Expanded(
                    child: Text(
                      y.replaceAll('AY ', ''),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.slate400),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
              Text(
                'Future school years will populate automatically once enrollment for that year is recorded.',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppTheme.slate400),
              ),
            ],
          ),
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

/// Simple line-chart painter: draws a polyline with a soft gradient fill
/// underneath and dot markers, only across data points that actually have
/// a value. Null entries (future school years with no data yet) are left
/// as empty gaps on the x-axis — nothing is drawn or interpolated for them.
/// Bar comparison of student assistant headcount across every campus,
/// shown when "All Campuses" is selected.
class _AllCampusesBarChart extends StatelessWidget {
  final Map<String, int> counts;
  final bool isMobileScreen;
  const _AllCampusesBarChart({required this.counts, required this.isMobileScreen});

  // Headcount across campuses is one series, so it gets one colour: the
  // campus names on the axis already carry identity. The five hues this used
  // to cycle through implied five categories that do not exist, and two of
  // them were the status colours, which mean good and warning elsewhere.

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final maxCount = counts.values.isEmpty ? 0 : counts.values.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Enrollment by Campus',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: isMobileScreen ? 14 : 15, fontWeight: FontWeight.w800, color: AppTheme.slate900),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppTheme.emerald50, borderRadius: BorderRadius.circular(20)),
              child: Text(
                '$total total',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.emerald500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Student assistants currently enrolled, by campus',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTheme.slate500),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: isMobileScreen ? 150 : 190,
          child: total == 0
              ? const Center(child: Text('No enrollment data yet', style: TextStyle(color: AppTheme.slate400)))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final entries = counts.entries.toList();
                    final n = entries.length;
                    final colWidth = constraints.maxWidth / n;
                    const numberLabelHeight = 22.0;
                    const topPad = 6.0;
                    const bottomPad = 6.0;
                    final lineAreaHeight = constraints.maxHeight - numberLabelHeight - topPad - bottomPad;

                    final points = <Offset>[];
                    final dotColors = <Color>[];
                    for (int i = 0; i < n; i++) {
                      final count = entries[i].value;
                      final frac = maxCount == 0 ? 0.0 : count / maxCount;
                      final x = colWidth * (i + 0.5);
                      final y = numberLabelHeight + topPad + lineAreaHeight * (1 - frac.clamp(0.04, 1.0));
                      points.add(Offset(x, y));
                      dotColors.add(ChartPalette.series);
                    }

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CampusEnrollmentLineChartPainter(
                              points: points,
                              dotColors: dotColors,
                              chartTop: numberLabelHeight,
                            ),
                          ),
                        ),
                        for (int i = 0; i < n; i++)
                          Positioned(
                            left: colWidth * i,
                            top: points[i].dy - numberLabelHeight - 6,
                            width: colWidth,
                            child: Text(
                              '${entries[i].value}',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: isMobileScreen ? 12 : 13, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        const SizedBox(height: 10),
        Row(
          children: counts.keys.map((campus) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobileScreen ? 2 : 4),
                child: Text(
                  campus.replaceAll(' Campus', ''),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: isMobileScreen ? 10.5 : 11.5, fontWeight: FontWeight.w600, color: AppTheme.slate600),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Paints the connecting line, gradient area fill, and colored dot markers
/// for the "Enrollment by Campus" line chart.
class _CampusEnrollmentLineChartPainter extends CustomPainter {
  final List<Offset> points;
  final List<Color> dotColors;
  final double chartTop;
  _CampusEnrollmentLineChartPainter({required this.points, required this.dotColors, required this.chartTop});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Horizontal gridlines across the chart area (below the number labels).
    final gridPaint = Paint()
      ..color = AppTheme.slate100
      ..strokeWidth = 1;
    final chartHeight = size.height - chartTop;
    for (int i = 0; i <= 3; i++) {
      final y = chartTop + chartHeight / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.length == 1) {
      final p = points.first;
      final dotFillPaint = Paint()..color = dotColors.first;
      final dotStrokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(p, 5.5, dotFillPaint);
      canvas.drawCircle(p, 5.5, dotStrokePaint);
      return;
    }

    // Area fill under the line.
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.maroon.withValues(alpha: 0.16), AppTheme.maroon.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // The connecting line.
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    final linePaint = Paint()
      ..color = AppTheme.maroon
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Dot markers, colored per campus to match the original bar colors.
    final dotStrokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < points.length; i++) {
      final dotFillPaint = Paint()..color = dotColors[i];
      canvas.drawCircle(points[i], 5.5, dotFillPaint);
      canvas.drawCircle(points[i], 5.5, dotStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CampusEnrollmentLineChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.dotColors != dotColors;
}

class _LineChartPainter extends CustomPainter {
  final List<double?> values;
  _LineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final known = values.whereType<double>().toList();

    // Leave a little headroom so the line/dots don't clip at the top/bottom.
    const topPad = 12.0;
    const bottomPad = 6.0;
    final chartHeight = size.height - topPad - bottomPad;
    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;

    // Horizontal gridlines span the full timeline, including empty years.
    final gridPaint = Paint()
      ..color = AppTheme.slate100
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = topPad + chartHeight / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (known.isEmpty) return;

    final maxV = known.reduce((a, b) => a > b ? a : b);
    final minV = known.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV) == 0 ? (maxV == 0 ? 1 : maxV) : (maxV - minV);

    // Only build points for indices that actually have data.
    final points = <Offset>[
      for (int i = 0; i < values.length; i++)
        if (values[i] != null)
          Offset(
            stepX * i,
            topPad + chartHeight - ((values[i]! - minV) / range) * chartHeight,
          ),
    ];

    if (points.length == 1) {
      // Only the current year has data — just show a single marker, no line.
      final dotFillPaint = Paint()..color = const Color(0xFFB08900);
      final dotStrokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(points.first, 5, dotFillPaint);
      canvas.drawCircle(points.first, 5, dotStrokePaint);
      return;
    }

    // Area fill under the line (only across the known points)
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.gold400.withValues(alpha: 0.28), AppTheme.gold400.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // The line itself
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    final linePaint = Paint()
      ..color = const Color(0xFFB08900)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Dot markers
    final dotFillPaint = Paint()..color = const Color(0xFFB08900);
    final dotStrokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in points) {
      canvas.drawCircle(p, 4.5, dotFillPaint);
      canvas.drawCircle(p, 4.5, dotStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => oldDelegate.values != values;
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
