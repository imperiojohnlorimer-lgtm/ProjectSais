import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_state.dart';
import '../../models/backup_info.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Admin-only page for the weekly encrypted backup that a GitHub Actions
/// workflow makes in a private repository: whether it is working, the
/// backups kept, a download for each and a way to delete older ones.
///
/// Restoring is deliberately not here. It needs the backup's passphrase and
/// the full-access Firebase key, and neither may ever be held by the web app.
class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  @override
  void initState() {
    super.initState();
    // Look again on opening: what the banner knew may be old.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().checkBackupHealth(fresh: true);
    });
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  /// "Nov 1, 8:00 PM" in the viewer's own time zone.
  static String _when(DateTime? date) =>
      date == null ? '—' : AppState.monthDayTime(date.toLocal());

  static String _day(DateTime? date) =>
      date == null ? '—' : AppState.monthDay(date.toLocal());

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    final state = context.watch<AppState>();
    final overview = state.backupOverview;
    final health = state.backupHealthStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: HeroBanner(
            isMobile: isMobile,
            icon: Icons.backup_outlined,
            title: 'Backups',
            subtitle:
                'The weekly encrypted backup of all SAIS records and files',
            stats: [
              HeroStatData(
                label: 'Last backup',
                value: _day(overview?.lastSuccessAt),
                icon: Icons.check_circle_outline,
              ),
              HeroStatData(
                label: 'Stored size',
                value: overview == null ? '—' : _size(overview.storedBytes),
                icon: Icons.storage_outlined,
              ),
              HeroStatData(
                label: 'Next backup',
                value: _day(overview?.nextRunAt),
                icon: Icons.schedule,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: _body(context, state, overview, health, hPad)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    AppState state,
    BackupOverview? overview,
    BackupHealth? health,
    double hPad,
  ) {
    // Nothing has answered yet.
    if (overview == null && state.backupError == null) {
      return const LoadingState(message: 'Checking the backups…');
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCallout(
            health: health,
            error: state.backupError,
            overview: overview,
            checking: state.backupChecking,
            onRefresh: () => state.checkBackupHealth(fresh: true),
          ),
          if (overview != null) ...[
            const SizedBox(height: 16),
            _Card(
              title: 'Kept backups',
              subtitle:
                  'GitHub keeps each backup for about 22 days, then removes '
                  'it by itself. Deleting one here is permanent.',
              child: _artifactList(context, state, overview),
            ),
            const SizedBox(height: 16),
            _Card(title: 'Recent runs', child: _runList(overview)),
          ],
          const SizedBox(height: 16),
          const _Card(title: 'Restoring a backup', child: _RestoreSteps()),
        ],
      ),
    );
  }

  Widget _artifactList(
    BuildContext context,
    AppState state,
    BackupOverview overview,
  ) {
    final items = overview.available;
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No backup is kept right now.',
          style: TextStyle(fontSize: 13, color: AppTheme.slate500),
        ),
      );
    }
    return Column(
      children: [
        for (final artifact in items)
          _ArtifactRow(
            key: ValueKey(artifact.id),
            artifact: artifact,
            isNewestGood: artifact.id == overview.protectedId,
          ),
      ],
    );
  }

  Widget _runList(BackupOverview overview) {
    if (overview.runs.isEmpty) {
      return const Text(
        'The backup has not run yet.',
        style: TextStyle(fontSize: 13, color: AppTheme.slate500),
      );
    }
    return Column(
      children: [
        for (final run in overview.runs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                _RunBadge(run: run),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _when(run.createdAt),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
                Text(
                  run.event == 'schedule' ? 'Scheduled' : 'Started by hand',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Card({required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusCallout extends StatelessWidget {
  final BackupHealth? health;
  final String? error;
  final BackupOverview? overview;
  final bool checking;
  final Future<void> Function() onRefresh;

  const _StatusCallout({
    required this.health,
    required this.error,
    required this.overview,
    required this.checking,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final ok = health == BackupHealth.ok;
    final severe =
        health == BackupHealth.failed ||
        health == BackupHealth.overdue ||
        health == BackupHealth.noUsableBackup;
    final color = ok
        ? AppTheme.emerald500
        : severe
        ? AppTheme.red500
        : AppTheme.amber500;
    final background = ok
        ? AppTheme.emerald50
        : severe
        ? AppTheme.red50
        : AppTheme.amber50;
    final title = switch (health) {
      BackupHealth.ok => 'The weekly backup is working',
      BackupHealth.failed => 'The latest backup did not finish',
      BackupHealth.overdue =>
        'No backup has finished in over $backupOverdueDays days',
      BackupHealth.noUsableBackup => 'There is no backup to download',
      _ => 'The backups could not be checked',
    };
    final detail = switch (health) {
      BackupHealth.ok =>
        'The last backup finished ${_BackupsScreenState._when(overview?.lastSuccessAt)}.',
      BackupHealth.failed =>
        'Open the Actions tab of the backup repository on GitHub to see the '
            'error, or wait for next Sunday\'s run.',
      BackupHealth.overdue =>
        'The last good backup was '
            '${_BackupsScreenState._when(overview?.lastSuccessAt)}. Check that '
            'the schedule on GitHub is still on.',
      BackupHealth.noUsableBackup =>
        'Every kept backup has expired, or none came from a finished run.',
      _ => error ?? 'Try again in a moment.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AsyncButton(
            label: 'Refresh',
            busyLabel: 'Checking…',
            icon: Icons.refresh,
            kind: AsyncButtonKind.outlined,
            onPressed: checking ? null : onRefresh,
          ),
        ],
      ),
    );
  }
}

class _RunBadge extends StatelessWidget {
  final BackupRun run;
  const _RunBadge({required this.run});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = run.isRunning
        ? ('Running', AppTheme.amber50, AppTheme.amber500)
        : run.succeeded
        ? ('Succeeded', AppTheme.emerald50, AppTheme.emerald500)
        : run.conclusion == 'cancelled'
        ? ('Cancelled', AppTheme.slate100, AppTheme.slate600)
        : ('Failed', AppTheme.red50, AppTheme.red500);
    return SizedBox(
      width: 92,
      child: Align(
        alignment: Alignment.centerLeft,
        child: StatusBadge(label: label, bgColor: bg, textColor: fg),
      ),
    );
  }
}

class _ArtifactRow extends StatelessWidget {
  final BackupArtifact artifact;

  /// The newest good backup: SAIS keeps it so one always exists.
  final bool isNewestGood;

  const _ArtifactRow({
    super.key,
    required this.artifact,
    required this.isNewestGood,
  });

  String get _expires {
    final at = artifact.expiresAt;
    if (at == null) return '';
    final days = at.difference(DateTime.now().toUtc()).inDays;
    if (days < 0) return 'expires today';
    return days == 0
        ? 'expires today'
        : 'expires in $days ${days == 1 ? 'day' : 'days'}';
  }

  Future<void> _download(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await state.backupDownloadUrl(artifact.id);
    if (result.url == null) {
      AppSnackBar.showWithMessenger(
        messenger,
        result.error ?? 'Could not get the download link.',
        type: SnackType.error,
      );
      return;
    }
    // In this tab, not a new one: by now the tap is too old for a browser to
    // allow a pop-up. GitHub sends the zip as an attachment, so the page
    // stays where it is while the file downloads.
    final opened = await launchUrl(
      Uri.parse(result.url!),
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self',
    );
    if (!opened) {
      AppSnackBar.showWithMessenger(
        messenger,
        'The browser could not start the download.',
        type: SnackType.error,
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final error = await state.deleteBackup(artifact.id);
    AppSnackBar.showWithMessenger(
      messenger,
      error ?? 'The backup was deleted.',
      type: error == null ? SnackType.success : SnackType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final created = _BackupsScreenState._when(artifact.createdAt);
    final details = [
      _BackupsScreenState._size(artifact.sizeBytes),
      if (_expires.isNotEmpty) _expires,
    ].join(' · ');
    final buttons = [
      AsyncButton(
        label: 'Download',
        busyLabel: 'Preparing…',
        icon: Icons.download_outlined,
        kind: AsyncButtonKind.filled,
        onPressed: () => _download(context),
      ),
      Tooltip(
        message: isNewestGood
            ? 'The newest good backup is kept so one always exists.'
            : '',
        child: AsyncButton(
          label: 'Delete',
          busyLabel: 'Deleting…',
          icon: Icons.delete_outline,
          kind: AsyncButtonKind.outlined,
          confirm: () => showConfirmDialog(
            context,
            title: 'Delete this backup?',
            message:
                'The backup of $created will be removed from GitHub for good. '
                'If it is the only copy of that week\'s data, it cannot be '
                'brought back.',
            confirmLabel: 'Delete',
          ),
          onPressed: isNewestGood ? null : () => _delete(context),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Backup of $created',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate900,
                  ),
                ),
                if (isNewestGood)
                  const StatusBadge(
                    label: 'Newest good backup',
                    bgColor: AppTheme.emerald50,
                    textColor: AppTheme.emerald500,
                  ),
                if (!artifact.fromSuccessfulRun)
                  const StatusBadge(
                    label: 'From a run that failed',
                    bgColor: AppTheme.amber50,
                    textColor: AppTheme.amber500,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              details,
              style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    info,
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: buttons),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 12),
                    ...[buttons.first, const SizedBox(width: 8), buttons.last],
                  ],
                ),
        );
      },
    );
  }
}

class _RestoreSteps extends StatelessWidget {
  const _RestoreSteps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Download the backup above. GitHub gives a .zip with one .sais file '
          'inside; unzip it.',
      'On the computer that has the backup tool, run: '
          'node unseal.js <file>.sais — and type the backup passphrase.',
      'Run node restore.js <name> to see what it would write, then add '
          '--yes to write it to the live system.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${i + 1}. ${steps[i]}',
              style: const TextStyle(fontSize: 13, color: AppTheme.slate700),
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          'Restoring is not done from SAIS on purpose: it needs the '
          'passphrase and the full-access Firebase key, and the website '
          'never holds either. The backups are encrypted, so a downloaded '
          'file is unreadable without the passphrase.',
          style: TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
      ],
    );
  }
}
