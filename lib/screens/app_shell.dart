import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import './dashboard/dashboard_screen.dart';
import './students/students_screen.dart';
import './attendance/attendance_screen.dart';
import './tasks/tasks_screen.dart';
import './reports/reports_screen.dart';
import './accounts/accounts_screen.dart';
import './accounts/applications_screen.dart';
import './accounts/applicant_screening_screen.dart';
import './accounts/admin_announcements_screen.dart';
import './accounts/create_department_screen.dart';
import './accounts/payroll_screen.dart';
import './accounts/skills_screen.dart';
import './profile/profile_screen.dart';
import './settings/academic_year_settings_screen.dart';
import './accounts/offices_screen.dart';
import './calendar/calendar_screen.dart';
import './student_portal/announcements_screen.dart';
import './accounts/admin_notifications_screen.dart';
import './accounts/head_forwards_screen.dart';
import './accounts/student_documents_screen.dart';
import './accounts/document_folders_screen.dart';
import './student_portal/sp_notifications_screen.dart';
import './supervisor/sv_announcements_screen.dart';
import './supervisor/performance_evaluation_screen.dart';
import './supervisor/dtr_accomplishment_report_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _navItems = [
    (
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
    ),
    (
      id: 'profile',
      label: 'Profile',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
    ),
    (
      id: 'accounts',
      label: 'Accounts',
      icon: Icons.manage_accounts_outlined,
      activeIcon: Icons.manage_accounts,
      roles: ['Admin'],
    ),
    (
      id: 'departments',
      label: 'Departments',
      icon: Icons.business_outlined,
      activeIcon: Icons.business,
      roles: ['Admin'],
    ),
    (
      id: 'payroll',
      label: 'Payroll',
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      roles: ['Admin'],
    ),
    (
      id: 'skills',
      label: 'Skills',
      icon: Icons.stars_outlined,
      activeIcon: Icons.stars,
      roles: ['Head'],
    ),
    (
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      roles: ['Admin'],
    ),
    (
      id: 'offices',
      label: 'Offices',
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance,
      roles: ['Head'],
    ),
    (
      id: 'announcements_admin',
      label: 'Announcements',
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign,
      roles: ['Head'],
    ),
    (
      id: 'applications',
      label: 'Applications',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment,
      roles: ['Head'],
    ),
    (
      id: 'applicant_screening',
      label: 'Applicant Screening',
      icon: Icons.how_to_reg_outlined,
      activeIcon: Icons.how_to_reg,
      roles: ['Head'],
    ),
    (
      id: 'students',
      label: 'Students',
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      roles: ['Head', 'Supervisor'],
    ),
    (
      id: 'calendar',
      label: 'Schedule',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today,
      roles: ['Head', 'Supervisor', 'Student Assistant'],
    ),
    (
      id: 'tasks',
      label: 'Tasks',
      icon: Icons.task_alt_outlined,
      activeIcon: Icons.task_alt,
      roles: ['Head', 'Supervisor', 'Student Assistant'],
    ),
    (
      id: 'attendance',
      label: 'Attendance',
      icon: Icons.access_time_outlined,
      activeIcon: Icons.access_time_filled,
      roles: ['Head', 'Supervisor', 'Student Assistant'],
    ),
    (
      id: 'reports',
      label: 'Reports',
      icon: Icons.description_outlined,
      activeIcon: Icons.description,
      roles: ['Supervisor', 'Student Assistant'],
    ),
    (
      id: 'performance_evaluation',
      label: 'Performance Evaluation',
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      roles: ['Supervisor'],
    ),
    (
      id: 'dtr_accomplishment_report',
      label: 'DTR/Accomplishment Report',
      icon: Icons.description_outlined,
      activeIcon: Icons.description,
      roles: ['Head', 'Supervisor'],
    ),
    // Announcements & Notifications: separate supervisor submission flow.
    (
      id: 'announcements',
      label: 'Announcements',
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign,
      roles: ['Student Assistant'],
    ),
    (
      id: 'sv_announcements',
      label: 'Request Student Assistant',
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign,
      roles: ['Supervisor'],
    ),
    (
      id: 'head_forwards',
      label: 'Sent to Head',
      icon: Icons.forward_to_inbox_outlined,
      activeIcon: Icons.forward_to_inbox,
      roles: ['Head'],
    ),
    (
      id: 'student_documents',
      label: 'Student Documents',
      icon: Icons.folder_shared_outlined,
      activeIcon: Icons.folder_shared,
      roles: ['Head'],
    ),
    (
      id: 'document_folders',
      label: 'Document Folders',
      icon: Icons.folder_outlined,
      activeIcon: Icons.folder,
      roles: ['Head'],
    ),
    (
      id: 'admin_notifications',
      label: 'Notifications',
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      roles: ['Head'],
    ),
    (
      id: 'sa_notifications',
      label: 'Notifications',
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      roles: ['Student Assistant', 'Supervisor'],
    ),
  ];

  List<({String id, String label, IconData icon, IconData activeIcon})>
  _filteredNav(String role) {
    final result =
        <({String id, String label, IconData icon, IconData activeIcon})>[];

    for (final item in _navItems) {
      final dynamic itemDynamic = item;
      try {
        // Try to access roles if they exist
        final roles = itemDynamic.roles as List<String>?;
        if (roles != null && !roles.contains(role)) {
          continue;
        }
      } catch (_) {
        // No roles field, item is available for all roles
      }

      result.add((
        id: itemDynamic.id as String,
        label: itemDynamic.label as String,
        icon: itemDynamic.icon as IconData,
        activeIcon: itemDynamic.activeIcon as IconData,
      ));
    }

    return result;
  }

  Widget _buildBody(String tab) {
    switch (tab) {
      case 'dashboard':
        return const DashboardScreen();
      case 'profile':
        return const ProfileScreen();
      case 'accounts':
        return const AccountsScreen();
      case 'departments':
        return const CreateDepartmentScreen();
      case 'payroll':
        return const PayrollScreen();
      case 'skills':
        return const SkillsScreen();
      case 'offices':
        return const OfficesScreen();
      case 'settings':
        return const AcademicYearSettingsScreen();
      case 'announcements_admin':
        return const AdminAnnouncementsScreen();
      case 'applications':
        return const ApplicationsScreen();
      case 'applicant_screening':
        return const ApplicantScreeningScreen();
      case 'students':
        return const StudentsScreen();
      case 'calendar':
        return const CalendarScreen();
      case 'tasks':
        return const TasksScreen();
      case 'attendance':
        return const AttendanceScreen();
      case 'reports':
        return const ReportsScreen();
      case 'performance_evaluation':
        return const PerformanceEvaluationScreen();
      case 'dtr_accomplishment_report':
        return const DtrAccomplishmentReportScreen();
      case 'announcements':
        return const AnnouncementsScreen();
      case 'sv_announcements':
        return const SvAnnouncementsScreen();
      case 'sa_notifications':
        return const SpNotificationsScreen();
      case 'admin_notifications':
        return const AdminNotificationsScreen();
      case 'head_forwards':
        return const HeadForwardsScreen();
      case 'student_documents':
        return const StudentDocumentsScreen();
      case 'document_folders':
        return const DocumentFoldersScreen();
      default:
        return const DashboardScreen();
    }
  }

  String _tabTitle(String tab) {
    switch (tab) {
      case 'dashboard':
        return 'Dashboard';
      case 'profile':
        return 'Profile';
      case 'accounts':
        return 'Accounts';
      case 'applications':
        return 'Applications';
      case 'applicant_screening':
        return 'Applicant Screening';
      case 'departments':
        return 'Departments';
      case 'payroll':
        return 'Payroll';
      case 'offices':
        return 'Offices';
      case 'settings':
        return 'Settings';
      case 'students':
        return 'Students';
      case 'calendar':
        return 'Schedule';
      case 'tasks':
        return 'Tasks';
      case 'attendance':
        return 'Attendance';
      case 'reports':
        return 'Reports';
      case 'performance_evaluation':
        return 'Performance Evaluation';
      case 'announcements':
        return 'Announcements';
      case 'sv_announcements':
        return 'Request Student Assistant';
      case 'sa_notifications':
        return 'Notifications';
      case 'admin_notifications':
        return 'Notifications';
      case 'head_forwards':
        return 'Sent to Head';
      case 'student_documents':
        return 'Student Documents';
      case 'document_folders':
        return 'Document Folders';
      default:
        return 'SAIS';
    }
  }

  Widget _academicYearBadge(String academicYear, {bool compact = false}) {
    final yearParts = academicYear.split('-');
    final compactYear = yearParts.length == 2
        ? 'AY ${yearParts.first}-${yearParts.last.substring(yearParts.last.length - 2)}'
        : academicYear;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: AppTheme.maroon.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppTheme.maroon,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            compact ? compactYear : 'Academic Year $academicYear',
            style: TextStyle(
              fontSize: compact ? 9 : 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.maroon,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final messenger = ScaffoldMessenger.of(context);
                await context.read<AppState>().signOut();
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text(
                      'You have been logged out successfully.',
                    ),
                    backgroundColor: AppTheme.blue500,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final role = state.role;
    final nav = _filteredNav(role);
    final activeTab = state.activeTab;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final isCompact = screenWidth < 480;

    // Notification bell is shown for Head, Student Assistants, and Supervisors.
    final showNotificationBell =
        role == 'Head' || role == 'Student Assistant' || role == 'Supervisor';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.slate50,
      drawer: isMobile
          ? _Drawer(nav: nav, activeTab: activeTab, state: state)
          : null,
      body: Row(
        children: [
          // Sidebar - only visible on larger screens
          if (!isMobile)
            SizedBox(
              width: 280,
              child: _Sidebar(nav: nav, activeTab: activeTab, state: state),
            ),
          // Main content area
          Expanded(
            child: Column(
              children: [
                // Top app bar
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 32,
                    vertical: isCompact ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: AppTheme.slate200, width: 1),
                    ),
                  ),
                  child: isMobile
                      ? Row(
                          children: [
                            // Hamburger
                            GestureDetector(
                              onTap: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.maroon.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppTheme.maroon.withValues(
                                      alpha: 0.15,
                                    ),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.menu_rounded,
                                  color: AppTheme.maroon,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _tabTitle(activeTab),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isCompact ? 18 : 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.maroon,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: _academicYearBadge(
                                      state.academicYear,
                                      compact: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Notification bell (SA + Supervisor)
                            if (showNotificationBell)
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  GestureDetector(
                                    onTap: () => context
                                        .read<AppState>()
                                        .setTab('sa_notifications'),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppTheme.slate100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.notifications_outlined,
                                        color: AppTheme.maroon,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  if (state.unreadNotificationCount > 0)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.red500,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${state.unreadNotificationCount}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            if (showNotificationBell) const SizedBox(width: 6),
                            // Avatar / profile
                            GestureDetector(
                              onTap: () =>
                                  context.read<AppState>().setTab('profile'),
                              child: UserAvatar(
                                avatarUrl: state.currentUser?.avatar,
                                initials: state.currentUser?.initials ?? '?',
                                size: 36,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (isMobile)
                              IconButton(
                                icon: const Icon(
                                  Icons.menu,
                                  color: AppTheme.slate700,
                                ),
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                              ),
                            Row(
                              children: [
                                ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          AppTheme.maroon,
                                          AppTheme.maroonDark,
                                        ],
                                      ).createShader(bounds),
                                  child: Text(
                                    _tabTitle(activeTab),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _academicYearBadge(state.academicYear),
                              ],
                            ),
                            const Spacer(),
                            StreamBuilder(
                              stream: Stream.periodic(
                                const Duration(seconds: 1),
                              ),
                              builder: (context, snapshot) {
                                final now = DateTime.now();
                                final time =
                                    "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'pm' : 'am'}";
                                final date =
                                    "${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][now.month - 1]} ${now.day}";
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      time,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.maroon,
                                      ),
                                    ),
                                    Text(
                                      date,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.slate500,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: 24),
                            if (showNotificationBell)
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.notifications_outlined,
                                      color: AppTheme.maroon,
                                    ),
                                    onPressed: () =>
                                        context.read<AppState>().setTab(
                                          role == 'Head'
                                              ? 'admin_notifications'
                                              : 'sa_notifications',
                                        ),
                                    tooltip: 'Notifications',
                                  ),
                                  if (state.unreadNotificationCount > 0)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.red500,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${state.unreadNotificationCount}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            IconButton(
                              icon: UserAvatar(
                                avatarUrl: state.currentUser?.avatar,
                                initials: state.currentUser?.initials ?? '?',
                                size: 28,
                              ),
                              onPressed: () =>
                                  context.read<AppState>().setTab('profile'),
                              tooltip: 'View Profile',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.logout,
                                color: AppTheme.slate600,
                              ),
                              onPressed: () => _showLogoutConfirmation(context),
                              tooltip: 'Logout',
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                ),
                // Main content
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    // AnimatedSwitcher lays children out loose and centred;
                    // without this a screen shorter than the viewport gets
                    // floated to the middle with empty bands above and below.
                    child: SizedBox.expand(
                      key: ValueKey(activeTab),
                      child: _buildBody(activeTab),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<({String id, String label, IconData icon, IconData activeIcon})>
  nav;
  final String activeTab;
  final AppState state;

  const _Sidebar({
    required this.nav,
    required this.activeTab,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.gold400, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Logo Container
                    AppLogo(size: 52),
                    const SizedBox(width: 12),
                    // Branding Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'SAIS',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Student Assistant\nInformation System',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppTheme.maroon,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Nav Items
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                children: nav.map((item) {
                  final isActive = activeTab == item.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () {
                        context.read<AppState>().setTab(item.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: isActive
                              ? const LinearGradient(
                                  colors: [
                                    AppTheme.maroon,
                                    AppTheme.maroonDark,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: isActive
                                  ? AppTheme.gold400
                                  : Colors.transparent,
                              width: 4,
                            ),
                          ),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: AppTheme.maroon.withValues(
                                      alpha: 0.2,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                  ),
                                ],
                        ),
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  isActive ? item.activeIcon : item.icon,
                                  size: 20,
                                  color: isActive
                                      ? Colors.white
                                      : AppTheme.slate700,
                                ),
                                if ((item.id == 'sa_notifications' ||
                                        item.id == 'admin_notifications') &&
                                    state.unreadNotificationCount > 0)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.red500,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${state.unreadNotificationCount}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isActive
                                      ? Colors.white
                                      : AppTheme.slate700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // User card at bottom
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.maroon50, AppTheme.gold50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.maroon200, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                UserAvatar(
                  avatarUrl: state.currentUser?.avatar,
                  initials: state.currentUser?.initials ?? '?',
                  size: 44,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.currentUser?.name ?? 'User',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.slate900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.role,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: AppTheme.slate500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Drawer extends StatelessWidget {
  final List<({String id, String label, IconData icon, IconData activeIcon})>
  nav;
  final String activeTab;
  final AppState state;

  const _Drawer({
    required this.nav,
    required this.activeTab,
    required this.state,
  });

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
                final messenger = ScaffoldMessenger.of(context);
                await context.read<AppState>().signOut();
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text(
                      'You have been logged out successfully.',
                    ),
                    backgroundColor: AppTheme.blue500,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.gold400, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Logo Container
                    AppLogo(size: 56),
                    const SizedBox(width: 16),
                    // Branding Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'SAIS',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Student Assistant\nInformation System',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.maroon,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Nav Items
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                children: nav.map((item) {
                  final isActive = activeTab == item.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () {
                        context.read<AppState>().setTab(item.id);
                        Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: isActive
                              ? const LinearGradient(
                                  colors: [
                                    AppTheme.maroon,
                                    AppTheme.maroonDark,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: isActive
                                  ? AppTheme.gold400
                                  : Colors.transparent,
                              width: 4,
                            ),
                          ),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: AppTheme.maroon.withValues(
                                      alpha: 0.2,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                  ),
                                ],
                        ),
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  isActive ? item.activeIcon : item.icon,
                                  size: 20,
                                  color: isActive
                                      ? Colors.white
                                      : AppTheme.slate700,
                                ),
                                if ((item.id == 'sa_notifications' ||
                                        item.id == 'admin_notifications') &&
                                    state.unreadNotificationCount > 0)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.red500,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${state.unreadNotificationCount}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isActive
                                      ? Colors.white
                                      : AppTheme.slate700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // User card at bottom
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.maroon50, AppTheme.gold50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.maroon200, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                UserAvatar(
                  avatarUrl: state.currentUser?.avatar,
                  initials: state.currentUser?.initials ?? '?',
                  size: 44,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.currentUser?.name ?? 'User',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.slate900,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        state.role.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.maroon,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Standalone logout button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Material(
              color: AppTheme.red500.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showLogoutConfirmation(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.red500.withValues(alpha: 0.25),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        size: 17,
                        color: AppTheme.red500,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Log Out',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.red500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
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
