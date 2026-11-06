import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/backup_info.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/navigation/app_router.dart';
import 'package:projectsais/screens/backups/backups_screen.dart';
import 'package:projectsais/services/backup_service.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/backup_health_banner.dart';

final _now = DateTime.utc(2026, 11, 4, 9);

BackupRun _run(int id, String? conclusion, DateTime at) => BackupRun(
  id: id,
  status: conclusion == null ? 'in_progress' : 'completed',
  conclusion: conclusion,
  event: 'schedule',
  createdAt: at,
);

BackupArtifact _artifact(
  int id,
  DateTime at, {
  bool expired = false,
  bool good = true,
}) => BackupArtifact(
  id: id,
  name: 'sais-backup-$id',
  sizeBytes: 84 * 1024 * 1024,
  createdAt: at,
  expiresAt: at.add(const Duration(days: 22)),
  expired: expired,
  fromSuccessfulRun: good,
);

/// A healthy overview whose times are counted back from [at] (the real clock
/// unless a test pins it), because the app judges "overdue" by the real clock.
BackupOverview _overview({
  DateTime? at,
  List<BackupRun>? runs,
  List<BackupArtifact>? artifacts,
  DateTime? lastSuccessAt,
  int? protectedId,
}) {
  final base = at ?? DateTime.now().toUtc();
  final nov1 = base.subtract(const Duration(days: 3));
  final oct25 = base.subtract(const Duration(days: 10));
  return BackupOverview(
    runs: runs ?? [_run(3, 'success', nov1), _run(2, 'failure', oct25)],
    artifacts: artifacts ?? [_artifact(300, nov1), _artifact(200, oct25)],
    lastSuccessAt: lastSuccessAt ?? nov1,
    storedBytes: 2 * 84 * 1024 * 1024,
    protectedId: protectedId ?? 300,
    nextRunAt: DateTime.utc(2026, 11, 8, 12),
    fetchedAt: _now,
  );
}

class _FakeBackups extends BackupService {
  BackupOverview? overview = _overview();
  String? listError;
  String? deleteError;
  int lists = 0;
  bool lastFresh = false;
  final deleted = <int>[];
  Completer<void>? hold;

  @override
  Future<({BackupOverview? overview, String? error})> list({
    bool fresh = false,
  }) async {
    lists++;
    lastFresh = fresh;
    if (hold != null) await hold!.future;
    if (listError != null) return (overview: null, error: listError);
    return (overview: overview, error: null);
  }

  @override
  Future<({String? url, String? error})> downloadUrl(int artifactId) async =>
      (url: 'https://example.com/$artifactId.zip', error: null);

  @override
  Future<String?> delete(int artifactId) async {
    deleted.add(artifactId);
    if (deleteError != null) return deleteError;
    overview = _overview(
      artifacts: [
        for (final a in overview!.artifacts)
          if (a.id != artifactId) a,
      ],
    );
    return null;
  }
}

User _user(String role) => User(
  id: 'u_$role',
  name: '$role Person',
  email: '$role@example.com',
  role: role,
);

AppState _state(_FakeBackups backups, {String role = 'Admin'}) =>
    AppState(firestoreService: FirestoreService(), backupService: backups)
      ..currentUser = _user(role);

void main() {
  group('backupHealth', () {
    test('a failed check is never "ok"', () {
      expect(backupHealth(null, _now), BackupHealth.unavailable);
    });

    test('a recent success with a kept backup is ok', () {
      expect(backupHealth(_overview(at: _now), _now), BackupHealth.ok);
    });

    test(
      'the newest finished run failing is failed, even with older good ones',
      () {
        final overview = _overview(
          at: _now,
          runs: [
            _run(4, 'failure', DateTime.utc(2026, 11, 3)),
            _run(3, 'success', DateTime.utc(2026, 11, 1)),
          ],
        );
        expect(backupHealth(overview, _now), BackupHealth.failed);
      },
    );

    test('timed out and cancelled count as not succeeding', () {
      for (final conclusion in ['timed_out', 'cancelled', 'startup_failure']) {
        final overview = _overview(
          at: _now,
          runs: [_run(4, conclusion, DateTime.utc(2026, 11, 3))],
        );
        expect(
          backupHealth(overview, _now),
          BackupHealth.failed,
          reason: conclusion,
        );
      }
    });

    test('a run still going says nothing; the last finished one decides', () {
      final good = _overview(
        at: _now,
        runs: [
          _run(4, null, DateTime.utc(2026, 11, 4)),
          _run(3, 'success', DateTime.utc(2026, 11, 1)),
        ],
      );
      expect(backupHealth(good, _now), BackupHealth.ok);
      final bad = _overview(
        at: _now,
        runs: [
          _run(4, null, DateTime.utc(2026, 11, 4)),
          _run(3, 'failure', DateTime.utc(2026, 11, 1)),
        ],
      );
      expect(backupHealth(bad, _now), BackupHealth.failed);
    });

    test('a newer success repairs an older failure', () {
      final overview = _overview(
        at: _now,
        runs: [
          _run(4, 'success', DateTime.utc(2026, 11, 3)),
          _run(3, 'failure', DateTime.utc(2026, 11, 1)),
        ],
        lastSuccessAt: DateTime.utc(2026, 11, 3),
      );
      expect(backupHealth(overview, _now), BackupHealth.ok);
    });

    test('over 8 days since the last success is overdue', () {
      final overview = _overview(
        at: _now,
        runs: [_run(3, 'success', DateTime.utc(2026, 10, 20))],
        lastSuccessAt: DateTime.utc(2026, 10, 20),
      );
      expect(backupHealth(overview, _now), BackupHealth.overdue);
      final edge = _overview(
        at: _now,
        lastSuccessAt: _now.subtract(const Duration(days: 8)),
      );
      expect(backupHealth(edge, _now), BackupHealth.ok);
      final past = _overview(
        at: _now,
        lastSuccessAt: _now.subtract(const Duration(days: 8, minutes: 1)),
      );
      expect(backupHealth(past, _now), BackupHealth.overdue);
    });

    test('no downloadable backup from a good run is its own state', () {
      expect(
        backupHealth(_overview(at: _now, artifacts: []), _now),
        BackupHealth.noUsableBackup,
      );
      expect(
        backupHealth(
          _overview(
            at: _now,
            artifacts: [
              _artifact(300, DateTime.utc(2026, 11, 1), expired: true),
            ],
          ),
          _now,
        ),
        BackupHealth.noUsableBackup,
      );
      expect(
        backupHealth(
          _overview(
            at: _now,
            artifacts: [_artifact(300, DateTime.utc(2026, 11, 1), good: false)],
          ),
          _now,
        ),
        BackupHealth.noUsableBackup,
      );
    });

    test('no success ever is overdue', () {
      final overview = BackupOverview(
        runs: [_run(1, 'success', DateTime.utc(2026, 11, 1))],
        artifacts: [_artifact(1, DateTime.utc(2026, 11, 1))],
        lastSuccessAt: null,
        storedBytes: 0,
        protectedId: 1,
        nextRunAt: null,
        fetchedAt: null,
      );
      expect(backupHealth(overview, _now), BackupHealth.overdue);
    });
  });

  test('the function\'s answer is read into an overview', () {
    final overview = BackupOverview.fromJson({
      'runs': [
        {
          'id': 5,
          'status': 'completed',
          'conclusion': 'success',
          'event': 'schedule',
          'createdAt': '2026-11-01T12:00:00Z',
        },
      ],
      'artifacts': [
        {
          'id': 9,
          'name': 'sais-backup-2026-11-01_2000',
          'sizeBytes': 84000000,
          'createdAt': '2026-11-01T12:05:00Z',
          'expiresAt': '2026-11-23T12:05:00Z',
          'expired': false,
          'runId': 5,
          'fromSuccessfulRun': true,
        },
      ],
      'lastSuccessAt': '2026-11-01T12:00:00Z',
      'storedBytes': 84000000,
      'protectedId': 9,
      'nextRunAt': '2026-11-08T12:00:00.000Z',
      'fetchedAt': '2026-11-04T09:00:00.000Z',
    });
    expect(overview.runs.single.succeeded, isTrue);
    expect(overview.artifacts.single.fromSuccessfulRun, isTrue);
    expect(overview.protectedId, 9);
    expect(overview.available, hasLength(1));
    expect(overview.nextRunAt, DateTime.utc(2026, 11, 8, 12));
  });

  group('AppState', () {
    test('an Admin\'s check fills the overview', () async {
      final backups = _FakeBackups();
      final state = _state(backups);
      await state.checkBackupHealth();
      expect(state.backupOverview, isNotNull);
      expect(state.backupError, isNull);
      expect(state.backupChecking, isFalse);
      expect(state.backupHealthStatus, isNotNull);
    });

    test('nobody else asks, and nothing is known before a check', () async {
      for (final role in [
        'Head',
        'Supervisor',
        'Student Assistant',
        'Student',
      ]) {
        final backups = _FakeBackups();
        final state = _state(backups, role: role);
        await state.checkBackupHealth();
        expect(backups.lists, 0, reason: role);
        expect(state.backupHealthStatus, isNull, reason: role);
        expect(
          (await state.backupDownloadUrl(1)).error,
          isNotNull,
          reason: role,
        );
        expect(await state.deleteBackup(1), isNotNull, reason: role);
        expect(backups.deleted, isEmpty, reason: role);
      }
    });

    test('a failed check says unavailable, not ok', () async {
      final backups = _FakeBackups()..listError = 'The GitHub token expired.';
      final state = _state(backups);
      await state.checkBackupHealth();
      expect(state.backupHealthStatus, BackupHealth.unavailable);
      expect(state.backupError, 'The GitHub token expired.');
      // A later good answer clears it.
      backups.listError = null;
      await state.checkBackupHealth();
      expect(state.backupError, isNull);
      expect(state.backupHealthStatus, isNot(BackupHealth.unavailable));
    });

    test('a failed refresh after a good one is still unavailable', () async {
      final backups = _FakeBackups();
      final state = _state(backups);
      await state.checkBackupHealth();
      backups.listError = 'offline';
      await state.checkBackupHealth(fresh: true);
      expect(state.backupHealthStatus, BackupHealth.unavailable);
    });

    test('a second check while one runs joins it', () async {
      final backups = _FakeBackups()..hold = Completer();
      final state = _state(backups);
      final first = state.checkBackupHealth();
      final second = state.checkBackupHealth(fresh: true);
      expect(identical(first, second), isTrue);
      backups.hold!.complete();
      await first;
      expect(backups.lists, 1);
    });

    test('an answer that arrives after sign-out is dropped', () async {
      final backups = _FakeBackups()..hold = Completer();
      final state = _state(backups);
      final pending = state.checkBackupHealth();
      state.logout();
      backups.hold!.complete();
      await pending;
      expect(state.backupOverview, isNull);
      expect(state.backupHealthStatus, isNull);
      expect(state.backupChecking, isFalse);
    });

    test(
      'signing out forgets what was known, and the next Admin starts fresh',
      () async {
        final backups = _FakeBackups();
        final state = _state(backups);
        await state.checkBackupHealth();
        state.logout();
        expect(state.backupOverview, isNull);
        state.currentUser = _user('Admin');
        await state.checkBackupHealth();
        expect(backups.lists, 2);
        expect(state.backupOverview, isNotNull);
      },
    );

    test('deleting asks the server, then looks at the list again', () async {
      final backups = _FakeBackups();
      final state = _state(backups);
      await state.checkBackupHealth();
      final error = await state.deleteBackup(200);
      expect(error, isNull);
      expect(backups.deleted, [200]);
      expect(backups.lastFresh, isTrue);
      expect(state.backupOverview!.artifacts.map((a) => a.id), [300]);
    });

    test('a refused delete returns the reason', () async {
      final backups = _FakeBackups()
        ..deleteError = 'That is the newest good backup.';
      final state = _state(backups);
      await state.checkBackupHealth();
      expect(await state.deleteBackup(300), 'That is the newest good backup.');
    });
  });

  group('addresses', () {
    test('/backups is the Admin\'s alone', () {
      expect(AppRoutes.tabAt('Admin', '/backups'), 'backups');
      expect(AppRoutes.pathFor('Admin', 'backups'), '/backups');
      for (final role in [
        'Head',
        'Supervisor',
        'Student Assistant',
        'Student',
      ]) {
        expect(AppRoutes.tabAt(role, '/backups'), isNull, reason: role);
      }
    });
  });

  group('banner', () {
    Future<void> pump(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: BackupHealthBanner()),
          ),
        ),
      );
    }

    testWidgets('says nothing while all is well or before a check', (
      tester,
    ) async {
      final backups = _FakeBackups();
      final state = _state(backups);
      await pump(tester, state);
      expect(find.text('Open Backups'), findsNothing);
      await tester.runAsync(state.checkBackupHealth);
      await tester.pump();
      expect(find.text('Open Backups'), findsNothing);
    });

    testWidgets('warns when the latest run failed, and opens Backups', (
      tester,
    ) async {
      final backups = _FakeBackups()
        ..overview = _overview(
          runs: [_run(4, 'failure', DateTime.utc(2026, 11, 3))],
        );
      final state = _state(backups);
      await tester.runAsync(state.checkBackupHealth);
      await pump(tester, state);
      expect(find.textContaining('did not finish'), findsOneWidget);
      await tester.tap(find.text('Open Backups'));
      await tester.pump();
      expect(state.activeTab, 'backups');
      // On the Backups page itself it says nothing.
      expect(find.text('Open Backups'), findsNothing);
    });

    testWidgets('says when the check itself failed', (tester) async {
      final backups = _FakeBackups()..listError = 'offline';
      final state = _state(backups);
      await tester.runAsync(state.checkBackupHealth);
      await pump(tester, state);
      expect(find.textContaining('could not check'), findsOneWidget);
    });

    testWidgets('goes away at sign-out', (tester) async {
      final backups = _FakeBackups()
        ..overview = _overview(
          runs: [_run(4, 'failure', DateTime.utc(2026, 11, 3))],
        );
      final state = _state(backups);
      await tester.runAsync(state.checkBackupHealth);
      await pump(tester, state);
      expect(find.text('Open Backups'), findsOneWidget);
      state.logout();
      await tester.pump();
      expect(find.text('Open Backups'), findsNothing);
    });
  });

  group('page', () {
    Future<void> pump(
      WidgetTester tester,
      AppState state, {
      double width = 1300,
    }) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: BackupsScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('lists the kept backups and protects the newest good one', (
      tester,
    ) async {
      final backups = _FakeBackups();
      final state = _state(backups);
      await pump(tester, state);
      expect(backups.lastFresh, isTrue, reason: 'opening looks again');
      expect(find.text('The weekly backup is working'), findsOneWidget);
      expect(find.text('Kept backups'), findsOneWidget);
      expect(find.text('Newest good backup'), findsOneWidget);
      expect(find.text('Download'), findsNWidgets(2));
      // Two Delete buttons; the newest good one's is disabled.
      final deletes = find.widgetWithText(OutlinedButton, 'Delete');
      expect(deletes, findsNWidgets(2));
      expect(tester.widget<OutlinedButton>(deletes.first).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(deletes.last).onPressed, isNotNull);
      expect(find.text('Restoring a backup'), findsOneWidget);
      expect(find.text('Stored size'), findsOneWidget);
    });

    testWidgets('deleting an older backup asks first, then removes it', (
      tester,
    ) async {
      final backups = _FakeBackups();
      final state = _state(backups);
      await pump(tester, state);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete this backup?'), findsOneWidget);
      // Cancel leaves it alone.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backups.deleted, isEmpty);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(backups.deleted, [200]);
      expect(find.text('The backup was deleted.'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('a failed check shows the reason with Refresh', (tester) async {
      final backups = _FakeBackups()..listError = 'The GitHub token expired.';
      final state = _state(backups);
      await pump(tester, state);
      expect(find.text('The backups could not be checked'), findsOneWidget);
      expect(find.text('The GitHub token expired.'), findsOneWidget);
      expect(find.text('Kept backups'), findsNothing);
      backups.listError = null;
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Kept backups'), findsOneWidget);
    });

    testWidgets('a failed run is shown plainly', (tester) async {
      final backups = _FakeBackups()
        ..overview = _overview(
          runs: [
            _run(4, 'failure', DateTime.utc(2026, 11, 3)),
            _run(3, 'success', DateTime.utc(2026, 11, 1)),
          ],
        );
      final state = _state(backups);
      await pump(tester, state);
      expect(find.text('The latest backup did not finish'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Succeeded'), findsOneWidget);
    });

    testWidgets('fits a phone', (tester) async {
      final backups = _FakeBackups();
      final state = _state(backups);
      await pump(tester, state, width: 390);
      expect(find.text('Kept backups'), findsOneWidget);
      expect(find.text('Download'), findsNWidgets(2));
    });
  });
}
