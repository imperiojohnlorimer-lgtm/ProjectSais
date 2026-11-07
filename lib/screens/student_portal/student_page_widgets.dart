import 'package:flutter/material.dart';
import '../../models/app_state.dart';
import '../../theme/app_theme.dart';

// Pieces the Student portal's pages share: the light page header, the
// section label, the card look, the application status track, and the
// reason applying is closed.

/// Why the student can't apply right now, or null when applying is possible
/// as far as the account and the academic year go. The Apply page and the
/// Home page both use it, so they never disagree.
String? applicationClosedReason(AppState state) {
  final call = state.currentHiringCall;
  final isStudentAssistant = state.currentUser?.role == 'Student Assistant';
  return isStudentAssistant
      ? 'You are already a Student Assistant.'
      : !state.allowAcademicApplications
      ? 'Applications are closed for this academic year.'
      : call == null
      ? "Applications aren't open yet. The Head of Student Assistantship "
            'will announce when they are.'
      : call.isPastDeadline()
      ? 'Applications closed on ${call.deadline}.'
      : !call.isOpen
      ? 'Applications are closed.'
      : null;
}

class StudentPageTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const StudentPageTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: AppTheme.slate500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StudentSectionLabel extends StatelessWidget {
  final String text;
  const StudentSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: AppTheme.slate500,
      letterSpacing: 1.0,
    ),
  );
}

BoxDecoration studentCardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: AppTheme.slate200),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ],
);

class TrackStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;

  /// Finished, but not the way they hoped: a cross instead of a tick.
  final bool failed;
  final Color color;
  const TrackStep({
    super.key,
    required this.label,
    required this.done,
    required this.color,
    this.current = false,
    this.failed = false,
  });

  @override
  Widget build(BuildContext context) {
    final on = done || current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: on ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: on ? color : AppTheme.slate300, width: 2),
          ),
          // The step under way shows a dot; finished ones a tick.
          child: done
              ? Icon(
                  failed ? Icons.close_rounded : Icons.check_rounded,
                  size: 13,
                  color: Colors.white,
                )
              : current
              ? Center(
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: on ? AppTheme.slate800 : AppTheme.slate500,
          ),
        ),
      ],
    );
  }
}

class TrackLine extends StatelessWidget {
  final bool done;
  final Color color;
  const TrackLine({super.key, required this.done, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 18, left: 4, right: 4),
      color: done ? color : AppTheme.slate200,
    ),
  );
}
