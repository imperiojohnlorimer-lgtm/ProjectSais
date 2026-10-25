part of '../app_state.dart';

// ─── Clock-out reminder ────────────────────────────
extension AppStateClockOutReminder on AppState {
  /// When the holder of [record] is reminded to clock out:
  /// [AppState.clockOutReminderLead] before its session ends. Null when its time-in
  /// can't be read, falls outside both sessions, or comes after that moment
  /// (they'd be reminded the instant they clocked in).
  DateTime? clockOutReminderTime(AttendanceRecord record) {
    final day = _parseFormattedDate(record.date);
    final start = day == null ? null : _parseTime(record.timeIn, day);
    if (start == null) return null;
    final end = attendanceQrSessionEnd(start);
    if (end == null) return null;
    final remindAt = end.subtract(AppState.clockOutReminderLead);
    return start.isBefore(remindAt) ? remindAt : null;
  }

  /// Reminds the signed-in Student Assistant to clock out once a session
  /// they're clocked in to is [AppState.clockOutReminderLead] from its end, and sets
  /// a timer for a reminder still ahead. Runs on every change to their
  /// attendance, so clocking in sets the timer and clocking out clears it,
  /// and opening the app late in a session sends the reminder it missed
  /// while closed. Returns the reminder sent, if any.
  AppNotification? remindToClockOutIfDue([DateTime? at]) {
    _clockOutReminderTimer?.cancel();
    _clockOutReminderTimer = null;
    final user = currentUser;
    if (user == null || role != 'Student Assistant') return null;
    final now = at ?? DateTime.now();

    AppNotification? sent;
    DateTime? next;
    for (final record in filteredAttendance) {
      if (!record.isActive || record.isInvalid || record.isArchived) continue;
      final remindAt = clockOutReminderTime(record);
      if (remindAt == null) continue;
      final end = remindAt.add(AppState.clockOutReminderLead);
      if (now.isBefore(remindAt)) {
        if (next == null || remindAt.isBefore(next)) next = remindAt;
      } else if (now.isBefore(end)) {
        sent ??= _sendClockOutReminder(user, record, end);
      }
      // Past its end it's a missed time-out, which staff sessions void.
    }

    if (next != null) {
      _clockOutReminderTimer = Timer(
        next.difference(now),
        () => remindToClockOutIfDue(),
      );
    }
    return sent;
  }

  AppNotification? _sendClockOutReminder(
    User user,
    AttendanceRecord record,
    DateTime end,
  ) {
    final id = AppState.clockOutReminderId(record.id);
    if (!_clockOutRemindersHandled.add(id) ||
        notifications.any((n) => n.id == id)) {
      return null;
    }

    final session = attendanceQrSessionLabel(end) ?? 'Session';
    final hour = end.hour % 12 == 0 ? 12 : end.hour % 12;
    final clock =
        '$hour:${end.minute.toString().padLeft(2, '0')} '
        '${end.hour < 12 ? 'AM' : 'PM'}';
    final reminder = AppNotification(
      id: id,
      userId: user.id,
      title: 'Time to Clock Out',
      message:
          'Your ${session.toLowerCase()} ends at $clock. Scan the attendance '
          'QR code to clock out before then, or this session won\'t count '
          'toward your hours.',
      type: 'attendance',
      createdAt: _formattedToday(),
    );
    // Not pushed from here: the clockout-reminders job pushes it to the
    // student's devices on its own schedule.
    _addNotification(reminder, id: id, push: false);
    _notify();
    if (!_clockOutReminderAlerts.isClosed) {
      _clockOutReminderAlerts.add(reminder);
    }
    return reminder;
  }
}
