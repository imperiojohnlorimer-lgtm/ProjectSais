/// When a signed-in person who has stopped using SAIS is signed out.
///
/// Counts from the latest activity: this tab's own, or one a sibling tab
/// reported (a person working in one tab isn't idle). Pure, so it is tested
/// with made-up clocks.
class IdleDeadline {
  IdleDeadline({
    this.limit = const Duration(minutes: 30),
    this.warnBefore = const Duration(minutes: 2),
    required DateTime now,
  }) : _lastActivity = now;

  /// How long without activity ends the session.
  final Duration limit;

  /// How long before that to warn.
  final Duration warnBefore;

  DateTime _lastActivity;

  /// The person did something (a tap, a key) at [now].
  void touch(DateTime now) {
    if (now.isAfter(_lastActivity)) _lastActivity = now;
  }

  /// Time since the last activity, counting [sharedLast] (another tab's).
  Duration idleFor(DateTime now, {DateTime? sharedLast}) {
    final last = sharedLast != null && sharedLast.isAfter(_lastActivity)
        ? sharedLast
        : _lastActivity;
    final idle = now.difference(last);
    return idle.isNegative ? Duration.zero : idle;
  }

  bool isExpired(DateTime now, {DateTime? sharedLast}) =>
      idleFor(now, sharedLast: sharedLast) >= limit;

  /// In the warning window: close to the limit, but not past it.
  bool isWarning(DateTime now, {DateTime? sharedLast}) {
    final idle = idleFor(now, sharedLast: sharedLast);
    return idle >= limit - warnBefore && idle < limit;
  }

  /// How long is left before the limit, for the warning's wording.
  Duration remaining(DateTime now, {DateTime? sharedLast}) {
    final left = limit - idleFor(now, sharedLast: sharedLast);
    return left.isNegative ? Duration.zero : left;
  }
}
