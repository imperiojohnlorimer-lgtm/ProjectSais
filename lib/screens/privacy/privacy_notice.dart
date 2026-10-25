import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The Privacy Notice people accept when they register, and the page at
/// /privacy.
///
/// DRAFT: written from what SAIS actually collects and does, for the school's
/// Data Protection Officer to review and correct before it is relied on. The
/// contact line below is a placeholder to fill in. When the wording changes in
/// a way that matters, change [version]: the version a person accepted is
/// saved with their profile.
abstract final class PrivacyNotice {
  static const version = '2026-10-draft';

  /// Who people write to about their data. To be filled in by the school.
  static const contact =
      "[Name and email of the school's Data Protection Officer]";

  static const sections = <({String heading, List<String> body})>[
    (
      heading: 'Who this is from',
      body: [
        'SAIS, the Student Assistant Information System of Marinduque State '
            'University (MarSU), runs the Student Assistant program: hiring, '
            'screening, offices, attendance, tasks, reports, evaluations and '
            'payroll. This notice says what the system keeps about you and '
            'why. It follows the Data Privacy Act of 2012 (Republic Act '
            '10173).',
      ],
    ),
    (
      heading: 'What SAIS collects',
      body: [
        'When you register: your name, email address, mobile number, Student '
            'ID (if you give one), campus, department, course/program and '
            'year level.',
        'When you apply or work as a Student Assistant: your skills, the '
            'documents you upload for your requirements, your screening and '
            'evaluation results, your duty schedule, the times you clock in '
            'and out, your tasks and reports, and the hours and pay worked '
            'out for you.',
        'To keep the system working: the notifications sent to you, and, '
            'only if you turn on phone notifications, a code that identifies '
            'your browser or phone.',
      ],
    ),
    (
      heading: 'Why, and who can see it',
      body: [
        'It is used only to run the program above. The Head of Student '
            'Assistantship sees applications, attendance, reports, '
            'evaluations and payroll requirements. Your Supervisor sees what '
            'belongs to the office you work in. The Administrator manages '
            'accounts and payroll. You see your own records.',
        'Your data is not sold or used for advertising.',
      ],
    ),
    (
      heading: 'Where it is kept',
      body: [
        'Records are stored with Google Firebase (Firestore and sign-in), and '
            'uploaded files with Supabase, both cloud services. Files are '
            'private: they open only through links that expire after an '
            'hour.',
      ],
    ),
    (
      heading: 'How long',
      body: [
        'While you are in the program, and afterwards for as long as the '
            'school must keep payroll, attendance and accomplishment records '
            'for its own accounting and audit. Records are kept by academic '
            'year.',
      ],
    ),
    (
      heading: 'Your rights',
      body: [
        'You may ask to see what is kept about you, to have mistakes '
            'corrected, to object to how it is used, and to have it erased. '
            'Records the school is required to keep (for example what was '
            'paid to you) cannot be erased while that requirement lasts, but '
            'they will not be used for anything else.',
        'To ask, write to: $contact',
      ],
    ),
  ];
}

/// The notice's text, for a page or a dialog.
class PrivacyNoticeBody extends StatelessWidget {
  const PrivacyNoticeBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.amber500.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Draft: this wording is waiting for review by the school\'s Data '
            'Protection Officer.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
          ),
        ),
        for (final section in PrivacyNotice.sections) ...[
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text(
              section.heading,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate900,
              ),
            ),
          ),
          for (final paragraph in section.body) ...[
            const SizedBox(height: 8),
            Text(
              paragraph,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.slate700,
              ),
            ),
          ],
        ],
        const SizedBox(height: 20),
        Text(
          'Version ${PrivacyNotice.version}',
          style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
      ],
    );
  }
}

/// The notice as a window, opened from the registration form so what the
/// person typed there isn't lost.
Future<void> showPrivacyNoticeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Privacy Notice',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
            ),
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: PrivacyNoticeBody(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The notice on its own page, for the address /privacy.
class PrivacyScreen extends StatelessWidget {
  /// Where Back goes.
  final VoidCallback onBack;

  const PrivacyScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        title: const Text(
          'Privacy Notice',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.slate900,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 40),
            child: PrivacyNoticeBody(),
          ),
        ),
      ),
    );
  }
}
