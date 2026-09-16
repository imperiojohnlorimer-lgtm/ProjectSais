import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The four consistent snackbar "moods" used across the whole app.
enum SnackType { success, error, warning, info }

/// Centralized helper that guarantees every SnackBar in the app looks the
/// same: colored background matching its type, a leading icon, floating
/// behavior, rounded shape and white text. Prefer this over building a raw
/// SnackBar directly so the design stays consistent everywhere.
class AppSnackBar {
  AppSnackBar._();

  static const _radius = 10.0;
  static const _duration = Duration(seconds: 3);

  /// Show a snackbar using a [BuildContext].
  static void show(
    BuildContext context,
    String message, {
    SnackType type = SnackType.info,
    Duration duration = _duration,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(_build(message, type, duration));
  }

  /// Show a snackbar using an already-resolved [ScaffoldMessengerState].
  /// Useful after an `await` when the original `context` may no longer be
  /// safe to use directly (grab the messenger before the `await` instead).
  static void showWithMessenger(
    ScaffoldMessengerState messenger,
    String message, {
    SnackType type = SnackType.info,
    Duration duration = _duration,
  }) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(_build(message, type, duration));
  }

  // Convenience shorthands -----------------------------------------------

  static void success(BuildContext context, String message, {Duration? duration}) =>
      show(context, message, type: SnackType.success, duration: duration ?? _duration);

  static void error(BuildContext context, String message, {Duration? duration}) =>
      show(context, message, type: SnackType.error, duration: duration ?? _duration);

  static void warning(BuildContext context, String message, {Duration? duration}) =>
      show(context, message, type: SnackType.warning, duration: duration ?? _duration);

  static void info(BuildContext context, String message, {Duration? duration}) =>
      show(context, message, type: SnackType.info, duration: duration ?? _duration);

  // Internals --------------------------------------------------------------

  static SnackBar _build(String message, SnackType type, Duration duration) {
    final _SnackStyle style = _styleFor(type);
    return SnackBar(
      content: Row(
        children: [
          Icon(style.icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: style.color,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    );
  }

  static _SnackStyle _styleFor(SnackType type) {
    switch (type) {
      case SnackType.success:
        return _SnackStyle(AppTheme.emerald500, Icons.check_circle_rounded);
      case SnackType.error:
        return _SnackStyle(AppTheme.red500, Icons.error_rounded);
      case SnackType.warning:
        return _SnackStyle(AppTheme.amber500, Icons.warning_rounded);
      case SnackType.info:
        return _SnackStyle(AppTheme.blue500, Icons.info_rounded);
    }
  }
}

class _SnackStyle {
  final Color color;
  final IconData icon;
  const _SnackStyle(this.color, this.icon);
}