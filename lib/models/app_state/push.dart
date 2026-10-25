part of '../app_state.dart';

// ─── Push notifications ────────────────────────────
extension AppStatePush on AppState {
  /// Registers this browser for push notifications: once the browser
  /// allows them, saves its token under the signed-in account. Asks for
  /// that permission only when [ask] is set, from a Turn on button:
  /// browsers refuse, or hold it against the site, when a page asks without
  /// a tap. Runs at every sign-in, which also saves a token the browser has
  /// since replaced. Not for the Admin, who has no notifications to get.
  Future<void> registerForPush({bool ask = false}) async {
    final user = currentUser;
    if (user == null || role == 'Admin' || pushBusy) return;
    pushBusy = true;
    _notify();
    try {
      final permission = ask
          ? await _push.requestPermission()
          : await _push.permission();
      if (currentUser?.id != user.id) return;
      pushPermission = permission;
      if (permission != PushPermission.granted) return;
      final token = await _push.token();
      if (token == null || currentUser?.id != user.id) return;
      _firestoreService ??= FirestoreService();
      await _firestoreService!.savePushToken(token, user.id);
      _pushToken = token;
      _listenForPushMessages();
    } catch (error) {
      debugPrint('Could not register for push notifications: $error');
    } finally {
      pushBusy = false;
      _notify();
    }
  }

  /// A push that arrives while SAIS is open and showing reaches the page
  /// rather than the notification tray, so it pops up like the reminder the
  /// app raises itself — unless that one already did.
  void _listenForPushMessages() {
    _pushMessagesSub ??= _push.foregroundMessages.listen((data) {
      final user = currentUser;
      final id = data['notificationId']?.toString();
      if (user == null || id == null) return;
      if (data['type'] != 'clockout' && data['type'] != 'test') return;
      if (!_clockOutRemindersHandled.add(id)) return;
      if (_clockOutReminderAlerts.isClosed) return;
      _clockOutReminderAlerts.add(
        AppNotification(
          id: id,
          userId: user.id,
          title: data['title']?.toString() ?? 'Time to Clock Out',
          message: data['body']?.toString() ?? '',
          type: 'attendance',
          createdAt: _formattedToday(),
        ),
      );
    });
  }

  Future<void> _forgetPushToken() async {
    final token = _pushToken;
    _pushToken = null;
    pushPermission = null;
    await _pushMessagesSub?.cancel();
    _pushMessagesSub = null;
    if (token == null) return;
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!
          .deletePushToken(token)
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Could not remove this browser from push: $error');
    }
  }

  /// Asks the clockout-reminders function to send this account's devices a
  /// test notification. Returns what to tell the user.
  Future<({bool ok, String message})> sendTestPush() async {
    final result = await _push.sendTest(delaySeconds: AppState.pushTestDelaySeconds);
    return (
      ok: result.ok,
      message: result.ok
          ? 'A test notification arrives in about ${AppState.pushTestDelaySeconds} '
                'seconds. Lock your phone or switch apps to see it.'
          : result.error ?? 'The reminder server could not send a test.',
    );
  }
}
