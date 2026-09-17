import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

Future<void> _confirmClearAll(BuildContext context, AppState state) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Clear All Notifications',
    message: 'This will remove all your notifications. This cannot be undone.',
    confirmLabel: 'Clear All',
    confirmColor: AppTheme.red500,
  );
  if (ok) {
    await state.clearAllNotifications();
  }
}

class AdminNotificationsScreen extends StatelessWidget {
  const AdminNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notifs = state.myNotifications;
    final unread = notifs.where((n) => !n.isRead).length;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 420;
    final horizontalPadding = isCompact ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 4, height: 28,
                        decoration: BoxDecoration(color: AppTheme.maroon, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Notifications',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.slate900, letterSpacing: -0.3)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        unread > 0
                          ? 'Updates on announcements and applications · $unread unread'
                          : 'Updates on announcements and applications',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppTheme.slate400),
                      ),
                    ),
                    if (unread > 0 || notifs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (unread > 0)
                            TextButton.icon(
                              onPressed: () => state.markAllNotificationsRead(),
                              icon: const Icon(Icons.done_all_rounded, size: 14),
                              label: const Text('Mark all read', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.maroon,
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          if (notifs.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _confirmClearAll(context, state),
                              icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                              label: const Text('Clear all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.slate500,
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(width: 4, height: 28,
                              decoration: BoxDecoration(color: AppTheme.maroon, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text('Notifications',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.slate900, letterSpacing: -0.3)),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 14, top: 3),
                            child: Text(
                              unread > 0
                                ? 'Updates on announcements and applications · $unread unread'
                                : 'Updates on announcements and applications',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AppTheme.slate400),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (unread > 0 || notifs.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(left: isCompact ? 8 : 16, top: isCompact ? 2 : 0),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (unread > 0)
                              TextButton.icon(
                                onPressed: () => state.markAllNotificationsRead(),
                                icon: const Icon(Icons.done_all_rounded, size: 14),
                                label: const Text('Mark all read', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.maroon,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            if (notifs.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => _confirmClearAll(context, state),
                                icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                                label: const Text('Clear all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.slate500,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (notifs.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(color: AppTheme.slate100, shape: BoxShape.circle),
                            child: const Icon(Icons.notifications_none_outlined, size: 36, color: AppTheme.slate300),
                          ),
                          const SizedBox(height: 16),
                          const Text('No notifications yet',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate400)),
                          const SizedBox(height: 4),
                          const Text('Admin updates and approvals will appear here.',
                            style: TextStyle(fontSize: 13, color: AppTheme.slate500),
                            textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  )
                else
                  ...notifs.map((n) => _NotifTile(notif: n, state: state)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  final AppState state;
  const _NotifTile({required this.notif, required this.state});

  IconData get _icon {
    switch (notif.type) {
      case 'announcement': return Icons.campaign_outlined;
      case 'application': return Icons.assignment_outlined;
      default: return Icons.info_outline;
    }
  }

  Color get _iconColor {
    switch (notif.type) {
      case 'announcement': return AppTheme.maroon;
      case 'application': return AppTheme.blue500;
      default: return AppTheme.slate500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { if (!notif.isRead) state.markNotificationRead(notif.id); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notif.isRead ? AppTheme.slate200 : AppTheme.maroon200,
            width: notif.isRead ? 1 : 1.5,
          ),
          boxShadow: notif.isRead
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)]
            : [BoxShadow(color: AppTheme.maroon.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: notif.isRead ? AppTheme.slate100 : AppTheme.maroon50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, size: 16, color: notif.isRead ? AppTheme.slate400 : _iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(notif.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: notif.isRead ? AppTheme.slate600 : AppTheme.slate900,
                      )),
                  ),
                  if (!notif.isRead)
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: AppTheme.maroon, shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(notif.message,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: notif.isRead ? AppTheme.slate400 : AppTheme.slate600,
                  )),
                const SizedBox(height: 6),
                Text(notif.createdAt,
                  style: const TextStyle(fontSize: 11, color: AppTheme.slate400, fontWeight: FontWeight.w500)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
