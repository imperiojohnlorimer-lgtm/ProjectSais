import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';

/// A strip saying the device is offline, and what still works. Shows nothing
/// with a connection. On the sign-in pages it also offers Try again (and
/// Sign out) when a signed-in session couldn't be reopened because the
/// account couldn't be reached. Watches [AppState] itself: the shells it
/// sits in rebuild only for what they show.
class OfflineBanner extends StatelessWidget {
  /// On the login, register and other sign-in pages.
  final bool onAuthPage;

  const OfflineBanner({super.key, this.onAuthPage = false});

  @override
  Widget build(BuildContext context) {
    // A page shown on its own (a screen test, say) has no AppState: nothing
    // to say then.
    final AppState state;
    try {
      state = Provider.of<AppState>(context);
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final offline = state.isOffline;
    final restoreFailed = onAuthPage && state.sessionRestoreFailed;
    if (!offline && !restoreFailed) return const SizedBox.shrink();

    final String message;
    if (restoreFailed) {
      message = offline
          ? "You're offline, so SAIS can't open your account. It will try "
                'again when you are back online.'
          : "SAIS couldn't open your account. Check your connection and "
                'try again.';
    } else if (onAuthPage) {
      message = "You're offline. Signing in needs a connection.";
    } else {
      message = "You're offline. You can still see what's open; changes, "
          'scans and uploads need a connection.';
    }
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          isMobile ? 16 : 32,
          8,
          isMobile ? 8 : 24,
          8,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.slate100,
          border: Border(bottom: BorderSide(color: AppTheme.slate200)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: AppTheme.slate600,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
              ),
            ),
            if (restoreFailed) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    context.read<AppState>().retrySessionRestore(),
                child: const Text('Try again'),
              ),
              TextButton(
                onPressed: () => context.read<AppState>().signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
