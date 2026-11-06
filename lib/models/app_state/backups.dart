part of '../app_state.dart';

// ─── Backups (Admin) ───────────────────────────────
// The weekly encrypted backup is made by a GitHub Actions workflow in a
// private repository. The backup-status function (which alone holds the
// GitHub token) tells the Admin's session what is there; this keeps the
// answer for the Backups page and the banner. Nothing is written to
// Firestore: an Admin has no notification bell, push or email, so the
// warning is shown only while an Admin is signed in.
extension AppStateBackups on AppState {
  /// How the backup is doing, or null before the first check has answered.
  /// A check that failed is [BackupHealth.unavailable], never "ok".
  BackupHealth? get backupHealthStatus {
    if (backupError != null) return BackupHealth.unavailable;
    final overview = backupOverview;
    if (overview == null) return null;
    return backupHealth(overview, DateTime.now().toUtc());
  }

  /// Asks the backup-status function how the backup is doing. Admin only.
  /// [fresh] skips the function's short memory (the Refresh button). A second
  /// call while one is running joins it. An answer that arrives after
  /// sign-out (or for another account) is dropped.
  Future<void> checkBackupHealth({bool fresh = false}) {
    final user = currentUser;
    if (user == null || role != 'Admin') return Future.value();
    final running = _backupCheckInFlight;
    if (running != null) return running;
    final generation = _backupGeneration;
    bool current() =>
        !_disposed &&
        generation == _backupGeneration &&
        currentUser?.id == user.id;

    final future = () async {
      backupChecking = true;
      _notify();
      try {
        final result = await _backups.list(fresh: fresh);
        if (!current()) return;
        if (result.overview != null) {
          backupOverview = result.overview;
          backupError = null;
        } else {
          backupError =
              result.error ?? 'The backup service could not be reached.';
        }
      } finally {
        if (current()) {
          backupChecking = false;
          _backupCheckInFlight = null;
          _notify();
        }
      }
    }();
    _backupCheckInFlight = future;
    return future;
  }

  /// A short-lived link to one backup's zip on GitHub, or the reason there
  /// is none.
  Future<({String? url, String? error})> backupDownloadUrl(int artifactId) {
    if (role != 'Admin') {
      return Future.value((
        url: null,
        error: 'Only the Admin can download backups.',
      ));
    }
    return _backups.downloadUrl(artifactId);
  }

  /// Deletes one backup (never the newest good one) and reloads the list.
  /// The error to show, or null when it is gone.
  Future<String?> deleteBackup(int artifactId) async {
    if (role != 'Admin') return 'Only the Admin can delete backups.';
    final error = await _backups.delete(artifactId);
    // Whatever happened, the list may have changed. A check already under
    // way may have started before the delete, so let it finish and ask again.
    await _backupCheckInFlight;
    await checkBackupHealth(fresh: true);
    return error;
  }

  /// Forgets what the signed-out account knew, and drops any answer still
  /// on its way.
  void _forgetBackups() {
    _backupGeneration++;
    backupOverview = null;
    backupError = null;
    backupChecking = false;
    _backupCheckInFlight = null;
  }
}
