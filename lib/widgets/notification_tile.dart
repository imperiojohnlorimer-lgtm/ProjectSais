import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// One notification on a Notifications screen. Unread ones stand out with a
/// maroon border and dot. A chevron shows when tapping opens the screen the
/// notification is about ([opensScreen]).
class NotificationTile extends StatelessWidget {
  final AppNotification notif;
  final bool opensScreen;
  final VoidCallback onTap;

  const NotificationTile({
    super.key,
    required this.notif,
    required this.opensScreen,
    required this.onTap,
  });

  static (IconData, Color) _look(String type) => switch (type) {
    'announcement' => (Icons.campaign_outlined, AppTheme.maroon),
    'application' => (Icons.assignment_outlined, AppTheme.blue500),
    'task' => (Icons.task_alt_rounded, AppTheme.emerald500),
    'report' => (Icons.description_outlined, AppTheme.blue500),
    'head_forward' => (Icons.forward_to_inbox_outlined, AppTheme.maroon),
    'office' => (Icons.apartment_outlined, AppTheme.violet500),
    'payroll' => (Icons.payments_outlined, AppTheme.emerald500),
    'evaluation' => (Icons.fact_check_outlined, AppTheme.amber500),
    'rehire' => (Icons.autorenew_rounded, AppTheme.maroon),
    _ => (Icons.info_outline, AppTheme.slate500),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = _look(notif.type);
    return MouseRegion(
      cursor: opensScreen || !notif.isRead
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
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
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppTheme.maroon.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
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
                child: Icon(
                  icon,
                  size: 16,
                  color: notif.isRead ? AppTheme.slate400 : iconColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: notif.isRead
                                  ? AppTheme.slate600
                                  : AppTheme.slate900,
                            ),
                          ),
                        ),
                        if (!notif.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.maroon,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notif.message,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: notif.isRead
                            ? AppTheme.slate400
                            : AppTheme.slate600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notif.createdAt,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (opensScreen) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppTheme.slate400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
