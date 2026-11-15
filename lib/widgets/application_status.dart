import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

/// The colour an application's status shows in, the same on every screen.
Color applicationStatusColor(String status) => switch (status) {
  Application.approved || 'Accepted' => AppTheme.emerald500,
  Application.forScreening => AppTheme.violet500,
  Application.waitlisted => AppTheme.blue500,
  Application.rejected => AppTheme.red500,
  _ => AppTheme.amber500,
};

/// The status as a small rounded pill.
class ApplicationStatusPill extends StatelessWidget {
  final String status;

  /// What the pill says, when not the status itself (a student sees a
  /// rejected application as "Not accepted").
  final String? label;
  const ApplicationStatusPill(this.status, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final color = applicationStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label ?? status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// What each application status means, worded for the Head or for the
/// student. A student sees a rejected application as "Not accepted".
List<(String status, String label, String meaning)> applicationStatusGuide({
  required bool forStudent,
}) => forStudent
    ? const [
        (
          Application.pending,
          Application.pending,
          'Submitted. The Head is reviewing applicants and will pick who goes '
              'to screening.',
        ),
        (
          Application.forScreening,
          Application.forScreening,
          'You were picked for an interview and assessment.',
        ),
        (
          Application.approved,
          Application.approved,
          'You are a Student Assistant. The Head will place you in an office.',
        ),
        (
          Application.waitlisted,
          Application.waitlisted,
          'Not yet. The Head may still approve you when an office needs '
              'someone.',
        ),
        (
          Application.rejected,
          'Not accepted',
          'Something needs fixing, such as a wrong file. Read the reason and '
              'apply again while applications are open.',
        ),
      ]
    : const [
        (
          Application.pending,
          Application.pending,
          'Applied. Waiting for you to send them to screening or to reject '
              'the application.',
        ),
        (
          Application.forScreening,
          Application.forScreening,
          'Picked for the interview and assessment. The screening decides '
              'the result.',
        ),
        (
          Application.approved,
          Application.approved,
          'Highly Recommended or Recommended at screening, or approved anyway. '
              'Now a Student Assistant with an SA ID, ready to be placed in '
              'an office.',
        ),
        (
          Application.waitlisted,
          Application.waitlisted,
          'With Reservations or Not Recommended at screening. You can still '
              'Approve Anyway when an office needs someone.',
        ),
        (
          Application.rejected,
          Application.rejected,
          'Sent back with a reason, such as a wrong file. The student sees '
              '"Not accepted" and can apply again while the hiring call takes '
              'applications.',
        ),
      ];

/// A small "What … mean?" link that opens the status guide.
class StatusGuideLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const StatusGuideLink({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.maroon,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        minimumSize: const Size(0, 36),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: const Icon(Icons.help_outline_rounded, size: 16),
      label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Opens a small dialog listing each application status with its pill and
/// one sentence on what it means.
Future<void> showApplicationStatusGuide(
  BuildContext context, {
  required bool forStudent,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LightDialogHeader(
            icon: Icons.flag_outlined,
            title: 'What the statuses mean',
            subtitle: forStudent
                ? 'Where your application can stand.'
                : 'Where an application can stand.',
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (status, label, meaning) in applicationStatusGuide(
                    forStudent: forStudent,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ApplicationStatusPill(status, label: label),
                          const SizedBox(height: 5),
                          Text(
                            meaning,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: AppTheme.slate700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
