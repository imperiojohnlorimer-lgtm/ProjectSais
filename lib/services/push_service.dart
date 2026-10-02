import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'supabase_storage_service.dart';

/// Whether this browser will show SAIS's push notifications.
enum PushPermission { unsupported, notAsked, denied, granted }

/// Push notifications through Firebase Cloud Messaging: the browser's
/// permission, the token the clockout-reminders function sends to, and
/// asking that function to push new notifications. Tests swap in a fake.
///
/// The browser half lives in web/firebase-messaging-sw.js, which shows the
/// notifications that arrive while SAIS is closed or in the background.
class PushService {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// The permission as it stands, without asking.
  Future<PushPermission> permission() async {
    if (!await _supported()) return PushPermission.unsupported;
    final settings = await _messaging.getNotificationSettings();
    return _fromStatus(settings.authorizationStatus);
  }

  /// Shows the browser's "Allow notifications?" prompt. Browsers only
  /// allow that in answer to a tap.
  Future<PushPermission> requestPermission() async {
    if (!await _supported()) return PushPermission.unsupported;
    final settings = await _messaging.requestPermission();
    return _fromStatus(settings.authorizationStatus);
  }

  /// This browser's token. With no web push key given, Firebase uses its
  /// default one, so the project needs none of its own.
  Future<String?> token() => _messaging.getToken();

  /// The data of each message that arrives while SAIS is open and showing.
  /// The browser shows those itself only while SAIS isn't.
  Stream<Map<String, dynamic>> get foregroundMessages =>
      FirebaseMessaging.onMessage.map((message) => message.data);

  /// Asks the clockout-reminders function to push these just-saved
  /// notifications to their recipients' devices. The function reads each
  /// from Firestore and sends it once, so nothing here decides what's sent.
  /// A failure only costs the push; the notification itself is saved.
  Future<void> deliver(List<String> notificationIds) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser
          ?.getIdToken();
      if (idToken == null || idToken.isEmpty) return;
      await http.post(
        Uri.parse(SupabaseStorageService.clockOutRemindersUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'apikey': SupabaseStorageService.publishableKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'notificationIds': notificationIds}),
      );
    } catch (error) {
      debugPrint('Could not push notifications: $error');
    }
  }

  /// Asks the clockout-reminders function to send this account's devices a
  /// test notification in [delaySeconds]. Returns whether it will, and the
  /// function's reason when it won't.
  Future<({bool ok, String? error})> sendTest({
    required int delaySeconds,
  }) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser
          ?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return (ok: false, error: 'You must be signed in.');
      }
      final response = await http.post(
        Uri.parse(SupabaseStorageService.clockOutRemindersUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'apikey': SupabaseStorageService.publishableKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'test': true, 'delaySeconds': delaySeconds}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (ok: true, error: null);
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        ok: false,
        error:
            body['error']?.toString() ??
            'The reminder server could not send a test.',
      );
    } catch (error) {
      debugPrint('Test push failed: $error');
      return (
        ok: false,
        error:
            'Could not reach the reminder server. Check your connection '
            'and try again.',
      );
    }
  }

  /// iPhone Safari, for one, only supports push once SAIS is added to the
  /// Home Screen; asking Firebase Messaging anything before then throws.
  Future<bool> _supported() async {
    try {
      return await _messaging.isSupported();
    } catch (_) {
      return false;
    }
  }

  static PushPermission _fromStatus(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notAsked,
      };
}
