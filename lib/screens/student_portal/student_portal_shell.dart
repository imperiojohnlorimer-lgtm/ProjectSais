import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'announcements_screen.dart';
import 'sp_notifications_screen.dart';
import 'sp_profile_screen.dart';

class StudentPortalShell extends StatefulWidget {
  const StudentPortalShell({super.key});
  @override
  State<StudentPortalShell> createState() => _StudentPortalShellState();
}

class _StudentPortalShellState extends State<StudentPortalShell> {
  int _tab = 0;

  static const _navItems = [
    (id: 0, label: 'Announcements', icon: Icons.campaign_outlined,       activeIcon: Icons.campaign),
    (id: 1, label: 'Notifications',  icon: Icons.notifications_outlined,  activeIcon: Icons.notifications),
    (id: 2, label: 'Profile',        icon: Icons.person_outline,           activeIcon: Icons.person),
  ];

  Widget _body() {
    switch (_tab) {
      case 0: return const AnnouncementsScreen();
      case 1: return const SpNotificationsScreen();
      case 2: return const SpProfileScreen();
      default: return const AnnouncementsScreen();
    }
  }

  String _title() {
    switch (_tab) {
      case 0: return 'Announcements';
      case 1: return 'Notifications';
      case 2: return 'Profile';
      default: return 'Student Portal';
    }
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
                    content: const Text('You have been logged out successfully.'),
                    backgroundColor: AppTheme.blue500,
                    duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                );
              },
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadNotificationCount;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final isCompact = screenWidth < 480;

    return Scaffold(
      backgroundColor: AppTheme.slate50,
      body: Row(
        children: [
          if (!isMobile)
            SizedBox(
              width: 280,
              child: _Sidebar(
                navItems: _navItems,
                activeTab: _tab,
                unread: unread,
                state: state,
                onTabChange: (i) => setState(() => _tab = i),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                // Top bar — identical to app_shell
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: isCompact ? 10 : 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: AppTheme.slate200, width: 1)),
                  ),
                  child: isMobile
                      ? Row(
                          children: [
                            // Title
                            Expanded(
                              child: Text(
                                _title(),
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
                            // Time pill
                            StreamBuilder(
                              stream: Stream.periodic(const Duration(seconds: 1)),
                              builder: (context, snapshot) {
                                final now = DateTime.now();
                                final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
                                final m = now.minute.toString().padLeft(2, '0');
                                final ampm = now.hour >= 12 ? 'pm' : 'am';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.maroon.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text('$h:$m $ampm',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.maroon)),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            // Notification bell
                            Stack(clipBehavior: Clip.none, children: [
                              GestureDetector(
                                onTap: () => setState(() => _tab = 1),
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.slate100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.notifications_outlined, color: AppTheme.maroon, size: 18),
                                ),
                              ),
                              if (unread > 0)
                                Positioned(
                                  top: -2, right: -2,
                                  child: Container(
                                    width: 14, height: 14,
                                    decoration: const BoxDecoration(color: AppTheme.red500, shape: BoxShape.circle),
                                    child: Center(child: Text('$unread',
                                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))),
                                  ),
                                ),
                            ]),
                            const SizedBox(width: 6),
                            // Avatar / profile
                            GestureDetector(
                              onTap: () => setState(() => _tab = 2),
                              child: UserAvatar(
                                avatarUrl: state.currentUser?.avatar,
                                initials: state.currentUser?.initials ?? '?',
                                size: 36,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Logout
                            GestureDetector(
                              onTap: () => _showLogoutConfirmation(context),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.slate100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.logout, color: AppTheme.slate600, size: 18),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (isMobile) ...[
                              AppLogo(size: 36),
                              const SizedBox(width: 10),
                            ],
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [AppTheme.maroon, AppTheme.maroonDark],
                              ).createShader(bounds),
                              child: Text(
                                _title(),
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                            const Spacer(),
                            StreamBuilder(
                              stream: Stream.periodic(const Duration(seconds: 1)),
                              builder: (context, _) {
                                final now = DateTime.now();
                                final time =
                                    "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'pm' : 'am'}";
                                const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                                final date = "${months[now.month - 1]} ${now.day}";
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(time, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.maroon)),
                                    Text(date, style: const TextStyle(fontSize: 12, color: AppTheme.slate500, fontWeight: FontWeight.w500)),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: 24),
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.notifications_outlined, color: AppTheme.maroon),
                                  onPressed: () => setState(() => _tab = 1),
                                  tooltip: 'Notifications',
                                ),
                                if (unread > 0)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(color: AppTheme.red500, shape: BoxShape.circle),
                                      child: Center(
                                        child: Text(
                                          '$unread',
                                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _tab = 2),
                              child: UserAvatar(
                                avatarUrl: state.currentUser?.avatar,
                                initials: state.currentUser?.initials ?? '?',
                                size: 34,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.logout, color: AppTheme.slate600),
                              onPressed: () => _showLogoutConfirmation(context),
                              tooltip: 'Logout',
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: _body(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile
        ? Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.slate200)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: _navItems.map((item) {
                  final isActive = _tab == item.id;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = item.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        color: Colors.transparent,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                              decoration: BoxDecoration(
                                color: isActive ? AppTheme.maroon50 : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Stack(clipBehavior: Clip.none, children: [
                                Icon(isActive ? item.activeIcon : item.icon,
                                  size: 21,
                                  color: isActive ? AppTheme.maroon : AppTheme.slate400),
                                if (item.id == 1 && unread > 0)
                                  Positioned(
                                    top: -3, right: -6,
                                    child: Container(
                                      width: 12, height: 12,
                                      decoration: const BoxDecoration(color: AppTheme.red500, shape: BoxShape.circle),
                                    ),
                                  ),
                              ]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isActive ? AppTheme.maroon : AppTheme.slate400,
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
          )
        : null,
    );
  }
}

// ── Sidebar — mirrors app_shell _Sidebar exactly ──────────────────────
class _Sidebar extends StatelessWidget {
  final List<({int id, String label, IconData icon, IconData activeIcon})> navItems;
  final int activeTab;
  final int unread;
  final AppState state;
  final ValueChanged<int> onTabChange;

  const _Sidebar({
    required this.navItems,
    required this.activeTab,
    required this.unread,
    required this.state,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header with gold bottom border
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.gold400, width: 2)),
            ),
            child: Row(
              children: [
                AppLogo(size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('SAIS',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.slate900, letterSpacing: -0.5)),
                      Text('Student Portal',
                        style: TextStyle(fontSize: 9, color: AppTheme.maroon, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Nav items
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                children: navItems.map((item) {
                  final isActive = activeTab == item.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () => onTabChange(item.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: isActive
                            ? const LinearGradient(
                                colors: [AppTheme.maroon, AppTheme.maroonDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: isActive ? AppTheme.gold400 : Colors.transparent,
                              width: 4,
                            ),
                          ),
                          boxShadow: isActive
                            ? [BoxShadow(color: AppTheme.maroon.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))]
                            : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
                        ),
                        child: Row(
                          children: [
                            Stack(clipBehavior: Clip.none, children: [
                              Icon(isActive ? item.activeIcon : item.icon,
                                size: 20,
                                color: isActive ? Colors.white : AppTheme.slate700),
                              if (item.id == 1 && unread > 0)
                                Positioned(
                                  top: -4, right: -4,
                                  child: Container(
                                    width: 14, height: 14,
                                    decoration: const BoxDecoration(color: AppTheme.red500, shape: BoxShape.circle),
                                    child: Center(
                                      child: Text('$unread',
                                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                ),
                            ]),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(item.label,
                                style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: isActive ? Colors.white : AppTheme.slate700,
                                  letterSpacing: 0.3)),
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

          // User card — matches app_shell bottom user card exactly
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
                BoxShadow(color: AppTheme.maroon.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
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
                    children: [                      Text(
                        state.currentUser?.name ?? 'Student',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.slate900, letterSpacing: 0.2),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.role,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppTheme.slate500, letterSpacing: 0.2),
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