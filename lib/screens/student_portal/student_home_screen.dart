import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/application_status.dart';
import 'student_page_widgets.dart';

/// The student's first page: a welcome, how becoming a Student Assistant
/// works, and where their own application stands. Applying itself happens
/// on the Apply page; this page only points there.
class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key});

  /// "Welcome, Juan" from the first name, else the first word of the display
  /// name, else just "Welcome".
  static String greeting(User? user) {
    var first = user?.firstName.trim() ?? '';
    if (first.isEmpty) {
      final parts = (user?.name ?? '').trim().split(RegExp(r'\s+'));
      first = parts.first;
    }
    return first.isEmpty ? 'Welcome' : 'Welcome, $first';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final application = state.myCurrentApplication;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hPad = isMobile ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudentPageTitle(
                title: greeting(state.currentUser),
                subtitle:
                    'This is your Student Portal for the Student Assistant '
                    'Information System.',
              ),
              const SizedBox(height: 24),
              const _IntroCard(),
              const SizedBox(height: 16),
              _HowItWorksCard(state: state, application: application),
              const SizedBox(height: 16),
              _ReadyCard(state: state, application: application),
              const SizedBox(height: 20),
              _ContinueButton(state: state, application: application),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: studentCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.maroon,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.waving_hand_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Work in a MarSU office while you study',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Student Assistants support the university\'s offices '
                  'part-time, are supervised by the office head, and are paid '
                  'for their verified hours. You apply once; the Head of '
                  'Student Assistantship matches your skills to the offices '
                  'that need help.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.slate600,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The four steps, with the student's place on them, and one line on what
/// happens next.
class _HowItWorksCard extends StatelessWidget {
  final AppState state;
  final Application? application;
  const _HowItWorksCard({required this.state, required this.application});

  @override
  Widget build(BuildContext context) {
    final status = application?.status;
    final rejected = status == Application.rejected;
    final approved = status == Application.approved || status == 'Accepted';
    final waitlisted = status == Application.waitlisted;
    final decided = application != null && !application!.isUndecided;
    final color = status == null
        ? AppTheme.maroon
        : applicationStatusColor(status);
    final closedReason = applicationClosedReason(state);
    final canApply =
        state.hiringCallTakesApplications(state.currentHiringCall) &&
        closedReason == null;

    final message = switch (status) {
      null =>
        canApply
            ? _openLine(state.currentHiringCall)
            : (closedReason ?? 'Applications are closed.'),
      Application.forScreening =>
        'You were selected for screening. The Head of Student Assistantship '
            'will set your interview.',
      Application.waitlisted =>
        'You are on the waitlist. The Head may still approve you when an '
            'office needs someone.',
      Application.rejected =>
        'Your application was not accepted. Open Apply to see why and apply '
            'again.',
      Application.approved || 'Accepted' =>
        'You are now a Student Assistant. The Head will place you in an '
            'office that fits your skills.',
      _ =>
        'Submitted. The Head is matching applicants\' skills to the offices '
            'that need help, and will pick who goes to screening.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: studentCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StudentSectionLabel('HOW IT WORKS'),
          const SizedBox(height: 16),
          Row(
            children: [
              TrackStep(label: 'Account', done: true, color: color),
              TrackLine(done: application != null, color: color),
              TrackStep(
                label: rejected ? 'Not accepted' : 'Apply',
                done: application != null,
                failed: rejected,
                current: application == null && canApply,
                color: color,
              ),
              TrackLine(
                done:
                    application != null &&
                    status != Application.pending &&
                    !rejected,
                color: color,
              ),
              TrackStep(
                label: 'Screening',
                done: decided && !rejected,
                current: status == Application.forScreening,
                color: color,
              ),
              TrackLine(done: approved || waitlisted, color: color),
              TrackStep(
                label: waitlisted ? 'Waitlisted' : 'Working',
                done: approved,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.slate700,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _StepLine(
            number: '1',
            title: 'Create your account',
            text: 'Done: you are signed in.',
          ),
          const _StepLine(
            number: '2',
            title: 'Apply when hiring is open',
            text:
                'Send your skills and the documents the hiring call asks for.',
          ),
          const _StepLine(
            number: '3',
            title: 'Get screened',
            text:
                'The Head picks who goes to screening and rates each '
                'applicant.',
          ),
          const _StepLine(
            number: '4',
            title: 'Start working',
            text:
                'Approved students become Student Assistants and are '
                'placed in an office.',
            last: true,
          ),
        ],
      ),
    );
  }

  static String _openLine(Announcement? call) {
    final deadline = call?.deadline;
    return deadline == null || deadline.isEmpty
        ? 'Hiring is open. You can apply now.'
        : 'Hiring is open. Apply by $deadline.';
  }
}

class _StepLine extends StatelessWidget {
  final String number;
  final String title;
  final String text;
  final bool last;
  const _StepLine({
    required this.number,
    required this.title,
    required this.text,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.maroon50,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One compact line on what to prepare. Hidden once the student has applied.
class _ReadyCard extends StatelessWidget {
  final AppState state;
  final Application? application;
  const _ReadyCard({required this.state, required this.application});

  @override
  Widget build(BuildContext context) {
    if (application != null) return const SizedBox.shrink();
    final call = state.currentHiringCall;
    final documents = call == null
        ? const <String>[]
        : [for (final r in call.requirements) RequirementSpec.parse(r).label];
    final text = documents.isEmpty
        ? 'Have ready: your skills and any documents the hiring call lists.'
        : 'Have ready: your skills and ${documents.join(', ')}.';
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
          const Icon(
            Icons.checklist_rounded,
            size: 16,
            color: AppTheme.slate500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.slate600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final AppState state;
  final Application? application;
  const _ContinueButton({required this.state, required this.application});

  @override
  Widget build(BuildContext context) {
    final rejected = application?.status == Application.rejected;
    final label = application == null
        ? 'Continue to Apply'
        : rejected && state.hiringCallTakesApplications(state.currentHiringCall)
        ? 'Apply Again'
        : 'View my application';
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () => context.read<AppState>().setTab('announcements'),
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
