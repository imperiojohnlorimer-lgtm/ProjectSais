import 'dart:html';

/// When any open tab of SAIS last saw the person do something, kept in the
/// browser's local storage so a person working in one tab isn't signed out
/// because another tab sat idle (the sign-in is shared by every tab).
class SharedActivity {
  // One entry per account: two tabs signed in as different people (each in
  // its own session) must not keep each other from timing out.
  static String _key(String owner) => 'sais.lastActivity.$owner';

  static DateTime? read(String owner) {
    try {
      final stored = window.localStorage[_key(owner)];
      final millis = stored == null ? null : int.tryParse(stored);
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      // Storage blocked (a private window): this tab's own clock decides.
      return null;
    }
  }

  static void write(String owner, DateTime when) {
    try {
      window.localStorage[_key(owner)] = when.millisecondsSinceEpoch.toString();
    } catch (_) {}
  }
}
