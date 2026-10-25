import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/idle_deadline.dart';
import '../utils/shared_activity_stub.dart'
    if (dart.library.html) '../utils/shared_activity_web.dart';

/// Signs the person out after [limit] without a tap, a scroll or a key, on a
/// shared office computer especially: a sign-in that lasts forever is open to
/// the next person who sits down. Warns shortly before.
///
/// The check runs every few seconds, and the moment a hidden tab comes back
/// (browsers slow timers in background tabs, so waiting for one could let an
/// idle tab linger). Activity in another open tab counts too.
class IdleSignOutGuard extends StatefulWidget {
  final Widget child;
  final Duration limit;
  final Duration warnBefore;

  /// How often the deadline is checked.
  final Duration checkEvery;

  /// Where "now" comes from, so a test can move time.
  final DateTime Function() clock;

  const IdleSignOutGuard({
    super.key,
    required this.child,
    this.limit = const Duration(minutes: 30),
    this.warnBefore = const Duration(minutes: 2),
    this.checkEvery = const Duration(seconds: 15),
    this.clock = DateTime.now,
  });

  @override
  State<IdleSignOutGuard> createState() => _IdleSignOutGuardState();
}

class _IdleSignOutGuardState extends State<IdleSignOutGuard>
    with WidgetsBindingObserver {
  late IdleDeadline _deadline;
  Timer? _timer;
  bool _warned = false;
  DateTime _lastShared = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _deadline = IdleDeadline(
      limit: widget.limit,
      warnBefore: widget.warnBefore,
      now: widget.clock(),
    );
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _timer = Timer.periodic(widget.checkEvery, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _active();
    return false; // Only watching: the key still goes where it was going.
  }

  void _active() {
    final now = widget.clock();
    _deadline.touch(now);
    _warned = false;
    // Told to the other tabs, but not on every pointer move.
    if (now.difference(_lastShared) > const Duration(seconds: 5)) {
      _lastShared = now;
      // Only a signed-in person's activity counts for their other tabs.
      final owner = context.read<AppState>().currentUser?.id;
      if (owner != null) SharedActivity.write(owner, now);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() {
    if (!mounted) return;
    final app = context.read<AppState>();
    if (!app.isAuthenticated) {
      // Nobody to sign out; start the count afresh for whoever signs in.
      _deadline.touch(widget.clock());
      _warned = false;
      return;
    }
    final now = widget.clock();
    final shared = SharedActivity.read(app.currentUser?.id ?? '');
    if (_deadline.isExpired(now, sharedLast: shared)) {
      app.signOutForInactivity(widget.limit);
      return;
    }
    if (!_warned && _deadline.isWarning(now, sharedLast: shared)) {
      _warned = true;
      final minutes = (_deadline.remaining(now, sharedLast: shared).inSeconds /
              60)
          .ceil();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            "You'll be signed out in about $minutes "
            '${minutes == 1 ? 'minute' : 'minutes'} because SAIS has been '
            'idle. Tap anywhere to stay signed in.',
          ),
          backgroundColor: AppTheme.slate900,
          duration: const Duration(seconds: 15),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _active(),
      onPointerMove: (_) => _active(),
      onPointerSignal: (_) => _active(),
      child: widget.child,
    );
  }
}
