// What the Admin's Backups page knows about the weekly backup, as the
// backup-status function reports it from GitHub. The backups themselves are
// encrypted `.sais` files; nothing here can open one.

/// One run of the "SAIS Weekly Backup" workflow.
class BackupRun {
  final int id;

  /// GitHub's `queued`, `in_progress` or `completed`.
  final String status;

  /// `success`, `failure`, `cancelled`, `timed_out`…; null while it runs.
  final String? conclusion;

  /// `schedule` for the Sunday run, `workflow_dispatch` for one started by hand.
  final String event;
  final DateTime? createdAt;

  const BackupRun({
    required this.id,
    required this.status,
    required this.conclusion,
    required this.event,
    required this.createdAt,
  });

  bool get isRunning => status != 'completed';
  bool get succeeded => conclusion == 'success';

  /// Finished without succeeding (failed, timed out, cancelled…).
  bool get failed => !isRunning && !succeeded;

  factory BackupRun.fromJson(Map<String, dynamic> json) => BackupRun(
    id: (json['id'] as num).toInt(),
    status: json['status']?.toString() ?? '',
    conclusion: json['conclusion']?.toString(),
    event: json['event']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
  );
}

/// One kept backup (a GitHub Actions artifact holding a single `.sais` file).
class BackupArtifact {
  final int id;
  final String name;
  final int sizeBytes;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool expired;

  /// It came from a run that finished successfully; a failed run can leave
  /// a partial file behind.
  final bool fromSuccessfulRun;

  const BackupArtifact({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.createdAt,
    required this.expiresAt,
    required this.expired,
    required this.fromSuccessfulRun,
  });

  factory BackupArtifact.fromJson(Map<String, dynamic> json) => BackupArtifact(
    id: (json['id'] as num).toInt(),
    name: json['name']?.toString() ?? '',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    expired: json['expired'] == true,
    fromSuccessfulRun: json['fromSuccessfulRun'] == true,
  );
}

/// Everything the page shows.
class BackupOverview {
  /// The newest runs, newest first.
  final List<BackupRun> runs;

  /// The weekly backups GitHub still lists, newest first.
  final List<BackupArtifact> artifacts;

  /// When the newest successful run started; null if there has been none.
  final DateTime? lastSuccessAt;

  /// The size of the backups kept (this repository's only; GitHub's free
  /// storage is shared with other things, so this is not "space left").
  final int storedBytes;

  /// The newest good backup. It cannot be deleted from SAIS.
  final int? protectedId;
  final DateTime? nextRunAt;
  final DateTime? fetchedAt;

  const BackupOverview({
    required this.runs,
    required this.artifacts,
    required this.lastSuccessAt,
    required this.storedBytes,
    required this.protectedId,
    required this.nextRunAt,
    required this.fetchedAt,
  });

  /// The backups still there to download, newest first.
  List<BackupArtifact> get available =>
      artifacts.where((artifact) => !artifact.expired).toList();

  factory BackupOverview.fromJson(Map<String, dynamic> json) => BackupOverview(
    runs: [
      for (final run in (json['runs'] as List? ?? const []))
        BackupRun.fromJson(Map<String, dynamic>.from(run as Map)),
    ],
    artifacts: [
      for (final item in (json['artifacts'] as List? ?? const []))
        BackupArtifact.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    lastSuccessAt: DateTime.tryParse(json['lastSuccessAt']?.toString() ?? ''),
    storedBytes: (json['storedBytes'] as num?)?.toInt() ?? 0,
    protectedId: (json['protectedId'] as num?)?.toInt(),
    nextRunAt: DateTime.tryParse(json['nextRunAt']?.toString() ?? ''),
    fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? ''),
  );
}

/// How the weekly backup is doing.
enum BackupHealth {
  /// A good backup exists and the latest run did not fail.
  ok,

  /// The latest finished run did not succeed (failed, timed out, cancelled).
  failed,

  /// The last successful run is more than [backupOverdueDays] days old.
  overdue,

  /// No successful run has left a backup that can still be downloaded.
  noUsableBackup,

  /// The check itself could not be made, so nothing is known.
  unavailable,
}

/// The weekly run plus a day of slack for a late start.
const backupOverdueDays = 8;

/// How the backup is doing, from [overview] (null when it could not be
/// fetched) at [now]. A failed check is never read as "ok".
BackupHealth backupHealth(BackupOverview? overview, DateTime now) {
  if (overview == null) return BackupHealth.unavailable;

  // The newest run that has finished decides "failed": a run still going
  // says nothing yet, and an older failure is repaired by a newer success.
  final finished = overview.runs.where((run) => !run.isRunning);
  if (finished.isNotEmpty && finished.first.failed) {
    return BackupHealth.failed;
  }
  if (!overview.artifacts.any(
    (artifact) => !artifact.expired && artifact.fromSuccessfulRun,
  )) {
    return BackupHealth.noUsableBackup;
  }
  final last = overview.lastSuccessAt;
  if (last == null ||
      now.difference(last) > const Duration(days: backupOverdueDays)) {
    return BackupHealth.overdue;
  }
  return BackupHealth.ok;
}
