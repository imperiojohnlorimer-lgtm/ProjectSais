import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';

/// A strip under the Head's top bar while staff sign-ups wait for approval,
/// with a Review button. Shows nothing otherwise, and on the Staff Requests
/// page itself.
class StaffRequestBanner extends StatelessWidget {
  const StaffRequestBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final (count, tab) = context.select<AppState, (int, String)>(
      (s) => (s.staffRequestCount, s.activeTab),
    );
    if (count == 0 || tab == 'staff_requests') return const SizedBox.shrink();
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
            const Icon(
              Icons.how_to_reg_outlined,
              size: 18,
              color: AppTheme.amber500,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 1
                    ? '1 staff sign-up is waiting for your approval.'
                    : '$count staff sign-ups are waiting for your approval.',
                style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () =>
                  context.read<AppState>().setTab('staff_requests'),
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }
}
