import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// The colour an application's status shows in, the same on every screen.
Color applicationStatusColor(String status) => switch (status) {
  Application.approved || 'Accepted' => AppTheme.emerald500,
  Application.forScreening => AppTheme.violet500,
  Application.waitlisted => AppTheme.blue500,
  Application.rejected => AppTheme.red500,
  _ => AppTheme.amber500,
};

/// The status as a small rounded pill.
class ApplicationStatusPill extends StatelessWidget {
  final String status;
  const ApplicationStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = applicationStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
