import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Head-only page: the Supervisors and Heads who signed themselves up, waiting
/// for a Head to approve or decline. Until one is approved the person cannot
/// sign in and holds no staff access; approving gives them the role they
/// asked for.
class StaffRequestsScreen extends StatelessWidget {
  const StaffRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final requests = state.staffRequests;
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(requests.length),
          const SizedBox(height: 16),
          if (requests.isEmpty)
            const _EmptyRequests()
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Approving gives the person the role they asked for. They '
                'still have to verify their email before they can log in. '
                'Decline anyone you do not recognise.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppTheme.slate600,
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final request in requests) ...[
              _RequestCard(request: request),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header(int count) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 3,
        height: 32,
        margin: const EdgeInsets.only(top: 3),
        decoration: BoxDecoration(
          color: AppTheme.maroon,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.how_to_reg_rounded,
                  size: 17,
                  color: AppTheme.maroon,
                ),
                SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Staff Requests',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                      letterSpacing: -0.3,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              count == 0
                  ? 'Supervisors and Heads who sign up wait here for approval'
                  : '$count waiting for approval',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.slate500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: EmptyState(
      icon: Icons.how_to_reg_outlined,
      message: 'No staff sign-ups are waiting.',
    ),
  );
}

class _RequestCard extends StatelessWidget {
  final User request;
  const _RequestCard({required this.request});

  static String _roleLabel(String? role) =>
      role == 'Head' ? 'Head, Student Assistantship' : (role ?? 'Staff');

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return '${parts.first[0]}${parts.length > 1 ? parts.last[0] : ''}'
        .toUpperCase();
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final error = approve
        ? await state.approveStaffRequest(request)
        : await state.declineStaffRequest(request);
    AppSnackBar.showWithMessenger(
      messenger,
      error ??
          (approve
              ? '${request.name} can now log in as '
                    '${_roleLabel(request.requestedRole)}, once their email '
                    'is verified.'
              : '${request.name}\'s request was declined.'),
      type: error == null ? SnackType.success : SnackType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = <(IconData, String)>[
      (Icons.email_outlined, request.email),
      if ((request.phone ?? '').isNotEmpty)
        (Icons.phone_outlined, request.phone!),
      if ((request.department ?? '').isNotEmpty)
        (Icons.business_outlined, request.department!),
      if ((request.campus ?? '').isNotEmpty)
        (Icons.location_city_outlined, request.campus!),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final approve = AsyncButton(
            label: 'Approve',
            busyLabel: 'Approving…',
            icon: Icons.check_circle_outline,
            kind: AsyncButtonKind.filled,
            confirm: () => showConfirmDialog(
              context,
              title: 'Approve ${request.name}?',
              message:
                  '${request.name} will become a '
                  '${_roleLabel(request.requestedRole)} and can log in once '
                  'their email is verified.',
              confirmLabel: 'Approve',
              confirmColor: AppTheme.maroon,
            ),
            onPressed: () => _decide(context, approve: true),
          );
          final decline = AsyncButton(
            label: 'Decline',
            busyLabel: 'Declining…',
            icon: Icons.close_rounded,
            kind: AsyncButtonKind.outlined,
            confirm: () => showConfirmDialog(
              context,
              title: 'Decline ${request.name}?',
              message:
                  'They will not be able to log in. This request will '
                  'be closed.',
              confirmLabel: 'Decline',
            ),
            onPressed: () => _decide(context, approve: false),
          );

          final who = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.maroon.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(request.name),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.maroon,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          request.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                        ),
                        StatusBadge(
                          label: _roleLabel(request.requestedRole),
                          bgColor: AppTheme.maroon50,
                          textColor: AppTheme.maroon,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final (icon, text) in details)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(icon, size: 14, color: AppTheme.slate400),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                text,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.slate600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                who,
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [approve, decline]),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: who),
              const SizedBox(width: 16),
              decline,
              const SizedBox(width: 8),
              approve,
            ],
          );
        },
      ),
    );
  }
}
