import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shown instead of a blank page when the app can't start (Firebase or
/// Supabase didn't initialise, usually because there is no connection).
class StartupFailedApp extends StatelessWidget {
  /// Runs the start-up again.
  final VoidCallback onRetry;

  const StartupFailedApp({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAIS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: Scaffold(
        backgroundColor: AppTheme.slate50,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 44,
                    color: AppTheme.maroon,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "SAIS couldn't start",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your internet connection, then try again. If it '
                    'keeps happening, reload the page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.slate600, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.maroon,
                    ),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
