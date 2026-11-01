import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

/// A strip under the top bar saying that some live information could not be
/// loaded, with a Try again button. Shows nothing when all is well, and goes
/// away by itself once the data is back. Watches [AppState] itself: the
/// shells it sits in rebuild only for what they show.
class LoadProblemBanner extends StatelessWidget {
  const LoadProblemBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final retrying = state.isRetryingLoad;
    final message = retrying
        ? 'Trying to load the information again…'
        : state.loadProblemMessage;
    if (message == null) return const SizedBox.shrink();
    final isMobile = MediaQuery.of(context).size.width < 900;
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
        decoration: BoxDecoration(
          color: AppTheme.amber50,
          border: Border(
            bottom: BorderSide(color: AppTheme.amber500.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            retrying
                ? const BusyIcon(busy: true, size: 18, color: AppTheme.amber500)
                : const Icon(
                    Icons.cloud_off_outlined,
                    size: 18,
                    color: AppTheme.amber500,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
              ),
            ),
            if (!retrying) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: state.retryLoading,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
