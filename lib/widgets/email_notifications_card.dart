import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_snackbar.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

/// The switch for emailing this account's notifications to the address it
/// signed up with, so they arrive even when the person isn't signed in. On
/// unless they turned it off. The email only says what kind of update it is
/// and links to SAIS. Not shown to the Admin, who gets no notifications.
class EmailNotificationsCard extends StatefulWidget {
  const EmailNotificationsCard({super.key});

  @override
  State<EmailNotificationsCard> createState() => _EmailNotificationsCardState();
}

class _EmailNotificationsCardState extends State<EmailNotificationsCard> {
  bool _saving = false;

  Future<void> _set(AppState state, bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await state.updateProfile(emailNotifications: value);
    } catch (error) {
      if (mounted) {
        AppSnackBar.error(
          context,
          'Could not change email notifications: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTest(AppState state) async {
    final result = await state.sendTestEmail();
    if (!mounted) return;
    if (result.ok) {
      AppSnackBar.success(
        context,
        result.message,
        duration: const Duration(seconds: 6),
      );
    } else {
      AppSnackBar.error(
        context,
        result.message,
        duration: const Duration(seconds: 6),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;
    if (user == null || user.role == 'Admin') return const SizedBox.shrink();
    final on = user.emailsOn;

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
            on ? Icons.mark_email_read_outlined : Icons.email_outlined,
            size: 18,
            color: on ? AppTheme.emerald500 : AppTheme.slate500,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Email notifications',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  on
                      ? 'We email ${user.email} when you have a new update, so '
                            'you hear about it even when you are signed out. '
                            'The email says what kind of update it is; sign in '
                            'to read it.'
                      : 'Off. Turn it on to get an email at ${user.email} '
                            'when you have a new update, even when you are '
                            'signed out.',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AppTheme.slate500,
                  ),
                ),
                if (on) ...[
                  const SizedBox(height: 8),
                  AsyncButton(
                    label: 'Send a test email',
                    busyLabel: 'Sending…',
                    kind: AsyncButtonKind.text,
                    onPressed: () => _sendTest(state),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Email notifications',
            child: Switch(
              value: on,
              onChanged: _saving ? null : (value) => _set(state, value),
              activeThumbColor: AppTheme.emerald500,
            ),
          ),
        ],
      ),
    );
  }
}
