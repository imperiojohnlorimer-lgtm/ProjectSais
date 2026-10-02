import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';

/// Turns on push notifications for this device, which reach it with SAIS
/// closed, or says why they can't be, and offers a test once they're on.
/// One switch covers every push SAIS sends this account; [title] and the
/// two texts only say what this screen's notifications are.
class PushNotificationsCard extends StatefulWidget {
  final String title;

  /// What turning them on gets, shown with the Turn on button.
  final String offText;

  /// Shown once they're on for this device.
  final String onText;

  const PushNotificationsCard({
    super.key,
    required this.title,
    required this.offText,
    required this.onText,
  });

  @override
  State<PushNotificationsCard> createState() => _PushNotificationsCardState();
}

class _PushNotificationsCardState extends State<PushNotificationsCard> {
  bool _sendingTest = false;

  static void _snack(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _turnOn(BuildContext context, AppState state) async {
    await state.registerForPush(ask: true);
    if (!context.mounted) return;
    if (state.pushOn) {
      _snack(
        context,
        'Notifications are on for this device.',
        AppTheme.emerald500,
      );
    } else if (state.pushPermission == PushPermission.granted) {
      _snack(
        context,
        'Could not turn on notifications on this device. Reload SAIS and '
        'try again.',
        AppTheme.red500,
      );
    }
    // Blocked or unsupported: the card now says why.
  }

  Future<void> _sendTest(BuildContext context, AppState state) async {
    setState(() => _sendingTest = true);
    final result = await state.sendTestPush();
    if (!mounted) return;
    setState(() => _sendingTest = false);
    if (!context.mounted) return;
    _snack(
      context,
      result.message,
      result.ok ? AppTheme.emerald500 : AppTheme.red500,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final on = state.pushOn;

    final String detail;
    String? actionLabel;
    Future<void> Function()? action;
    var busy = false;
    if (state.pushBusy) {
      detail = 'Checking this device…';
    } else if (on) {
      detail = widget.onText;
      busy = _sendingTest;
      actionLabel = busy ? 'Sending…' : 'Send a test';
      action = () => _sendTest(context, state);
    } else if (state.pushPermission == PushPermission.denied) {
      detail =
          'Notifications are blocked for SAIS in this browser. Allow them '
          'in the browser\'s site settings, then reload SAIS.';
    } else if (state.pushPermission == PushPermission.unsupported) {
      detail = defaultTargetPlatform == TargetPlatform.iOS
          ? 'On an iPhone, add SAIS to your Home Screen (Share → Add to '
                'Home Screen) and open it from there to turn these on.'
          : 'This browser can\'t show notifications. They still appear '
                'inside SAIS.';
    } else {
      detail = widget.offText;
      actionLabel = 'Turn on';
      action = () => _turnOn(context, state);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            on
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            size: 18,
            color: on ? AppTheme.emerald500 : AppTheme.slate500,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AppTheme.slate500,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: busy ? null : action,
                    icon: busy
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.maroon,
                            ),
                          )
                        : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.maroon,
                      backgroundColor: AppTheme.maroon50,
                      disabledForegroundColor: AppTheme.maroon.withValues(
                        alpha: 0.75,
                      ),
                      disabledBackgroundColor: AppTheme.maroon50,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
