import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/backup_info.dart';
import '../theme/app_theme.dart';

/// A strip under the Admin's top bar when the weekly backup has failed, is
/// late, has nothing to download, or could not be checked. Shows nothing
/// while all is well, before the first check has answered, and on the
/// Backups page itself (which says the same). Admins have no notification
/// bell, push or email, so this is how they are told.
class BackupHealthBanner extends StatelessWidget {
  const BackupHealthBanner({super.key});

  /// What each state says, and whether it is serious enough for red.
  static ({String message, bool severe})? describe(BackupHealth? health) =>
      switch (health) {
        null || BackupHealth.ok => null,
        BackupHealth.failed => (
          message:
              'The latest weekly backup did not finish. Open Backups to see '
              'what happened.',
          severe: true,
        ),
        BackupHealth.overdue => (
          message:
              'No weekly backup has finished in over $backupOverdueDays '
              'days. Open Backups to check.',
          severe: true,
        ),
        BackupHealth.noUsableBackup => (
          message:
              'There is no backup you can download right now. Open Backups '
              'to check.',
          severe: true,
        ),
        BackupHealth.unavailable => (
          message:
              'SAIS could not check the weekly backup. Open Backups to try '
              'again.',
          severe: false,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final (health, tab) = context.select<AppState, (BackupHealth?, String)>(
      (s) => (s.backupHealthStatus, s.activeTab),
    );
    final text = describe(health);
    if (text == null || tab == 'backups') return const SizedBox.shrink();
    final color = text.severe ? AppTheme.red500 : AppTheme.amber500;
    final isMobile = MediaQuery.of(context).size.width < 900;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          isMobile ? 16 : 32,
          8,
          isMobile ? 8 : 24,
          8,
        ),
        decoration: BoxDecoration(
          color: text.severe ? AppTheme.red50 : AppTheme.amber50,
          border: Border(
            bottom: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.backup_outlined, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text.message,
                style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => context.read<AppState>().setTab('backups'),
              child: const Text('Open Backups'),
            ),
          ],
        ),
      ),
    );
  }
}
