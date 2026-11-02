part of '../app_state.dart';

/// What the live queries could not load, so the app can say so (and let the
/// user try again) instead of showing empty or old lists as if they were true.
extension AppStateLoadProblems on AppState {
  /// A live query failed and has not answered with data since. Fallback
  /// queries the rules always refuse do not count (see `_optionalLoads`).
  bool get hasLoadProblem => _loadFailures.isNotEmpty;

  /// The labels of the queries that failed, in order.
  List<String> get failedLoads => _loadFailures.keys.toList()..sort();

  /// What to tell the user, or null when nothing failed.
  String? get loadProblemMessage {
    if (_loadFailures.isEmpty) return null;
    if (_loadFailures.containsValue('resource-exhausted')) {
      return 'The database may have reached its free daily limit, so some '
          'lists can be empty or out of date. Try again later.';
    }
    return 'Some information could not be loaded and may be missing or out '
        'of date.';
  }

  /// Whether everything payroll is worked out from has arrived in this
  /// session: the attendance, accounts, reports, the Head's checks and the
  /// payouts already made, wherever this role reads them. An error or the
  /// load timeout does not count as arrived. True when no listeners are
  /// running (nothing to wait for).
  bool get payrollDataLoaded {
    if (!_loadTracking) return true;
    const needed = [
      'Attendance',
      'Users',
      'Students',
      'Reports',
      'Payroll checks',
      'Payroll records',
    ];
    return needed.every(
      (label) => !_loadExpected.contains(label) || _loadOk.contains(label),
    );
  }

  /// Whether the saved payroll sheets have arrived too: opening a sheet
  /// starts a new one when none is found, and saving that would replace the
  /// one that is only missing from the screen.
  bool get payrollSheetsLoaded =>
      payrollDataLoaded &&
      (!_loadTracking ||
          !_loadExpected.contains('Payroll sheets') ||
          _loadOk.contains('Payroll sheets'));

  /// Whether what a DTR/Accomplishment Report is worked out from has arrived
  /// without error: the attendance, tasks, accounts, students and class
  /// schedules, wherever this role reads them. The report builder copies them
  /// into fields the person then edits, so it must not start on part of them.
  /// True when no listeners are running.
  bool get reportDataLoaded {
    if (!_loadTracking) return true;
    const needed = [
      'Attendance',
      'Tasks',
      'Users',
      'Students',
      'Class schedules',
    ];
    return needed.every(
      (label) => !_loadExpected.contains(label) || _loadOk.contains(label),
    );
  }

  /// Opens the live queries afresh (a query that failed does not come back
  /// by itself) and completes once they have all answered, or after
  /// [AppState.loadTimeout]. Does nothing while the first load is under way,
  /// and a second tap joins the first.
  Future<void> retryLoading() {
    if (_disposed || currentUser == null || _loadPending) {
      return Future.value();
    }
    final running = _retryInFlight;
    if (running != null) return running;
    final run = _retryLoading().whenComplete(() {
      _retryInFlight = null;
      if (!_disposed) _notify();
    });
    _retryInFlight = run;
    _notify();
    return run;
  }

  /// A "Try again" is under way (its failures were cleared on restart).
  bool get isRetryingLoad => _retryInFlight != null;

  Future<void> _retryLoading() async {
    _startRealtimeListeners();
    unawaited(_refreshArchives());
    final answered = Completer<void>();
    void check() {
      if (_loadReady.containsAll(_loadExpected) && !answered.isCompleted) {
        answered.complete();
      }
    }

    addListener(check);
    try {
      check();
      await answered.future.timeout(AppState.loadTimeout, onTimeout: () {});
    } finally {
      removeListener(check);
    }
  }
}
