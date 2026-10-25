import 'dart:html';

/// When any open tab of SAIS last saw the person do something, kept in the
/// browser's local storage so a person working in one tab isn't signed out
/// because another tab sat idle (the sign-in is shared by every tab).
class SharedActivity {
  static const _key = 'sais.lastActivity';

  static DateTime? read() {
    try {
      final stored = window.localStorage[_key];
      final millis = stored == null ? null : int.tryParse(stored);
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      // Storage blocked (a private window): this tab's own clock decides.
      return null;
    }
  }

  static void write(DateTime when) {
    try {
      window.localStorage[_key] = when.millisecondsSinceEpoch.toString();
    } catch (_) {}
  }
}
