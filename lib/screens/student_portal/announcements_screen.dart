import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:provider/provider.dart';
import '../../utils/file_names.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/application_form_document_service.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/input_formats.dart';
import '../../utils/schedule_reader/schedule_reader.dart';
import '../../widgets/announcement_widgets.dart';
import '../../widgets/application_form_actions.dart';
import '../../widgets/application_form_dialog.dart';
import '../../widgets/application_status.dart';
import '../../widgets/class_schedule_editor.dart';
import '../../widgets/document_preview.dart';
import '../../widgets/shared_widgets.dart';
import 'student_page_widgets.dart';

/// Reads a school ID file; tests pass their own.
typedef SchoolIdFileReader =
    Future<SchoolIdReadResult> Function(Uint8List bytes, String mimeType);

/// Picks a requirement file; tests pass their own.
typedef RequirementFilePicker = Future<PlatformFile?> Function(String req);

/// Uploads a requirement file and returns its URL; tests pass their own.
typedef RequirementFileUploader =
    Future<String> Function(Uint8List bytes, String path, String extension);

/// The student's page: one application to be a Student Assistant, then
/// the Head's announcements to read. A student doesn't apply to an office;
/// the Head matches applicants' skills to the offices that asked for help.
class AnnouncementsScreen extends StatelessWidget {
  @visibleForTesting
  final SchoolIdFileReader? schoolIdReader;
  @visibleForTesting
  final ScheduleFileReader? scheduleReader;
  @visibleForTesting
  final RequirementFilePicker? filePicker;
  @visibleForTesting
  final RequirementFileUploader? fileUploader;

  const AnnouncementsScreen({
    super.key,
    this.schoolIdReader,
    this.scheduleReader,
    this.filePicker,
    this.fileUploader,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notices = state.studentNotices;
    final myApplication = state.myCurrentApplication;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final hPad = isMobile ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StudentPageTitle(
                title: 'Become a Student Assistant',
                subtitle:
                    'Apply once. The Head matches your skills to the offices '
                    'that need help.',
              ),
              const SizedBox(height: 24),
              if (myApplication != null)
                _MyApplicationCard(
                  application: myApplication,
                  state: state,
                  schoolIdReader: schoolIdReader,
                  scheduleReader: scheduleReader,
                  filePicker: filePicker,
                  fileUploader: fileUploader,
                )
              else
                _ApplyCard(
                  state: state,
                  schoolIdReader: schoolIdReader,
                  scheduleReader: scheduleReader,
                  filePicker: filePicker,
                  fileUploader: fileUploader,
                ),
              if (notices.isNotEmpty) ...[
                const SizedBox(height: 32),
                const StudentSectionLabel('ANNOUNCEMENTS'),
                const SizedBox(height: 12),
                for (final notice in notices) _NoticeCard(notice: notice),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the application form for [call]; [previous] is a rejected
/// application it starts from.
void _openApplyDialog(
  BuildContext context,
  AppState state,
  Announcement call, {
  Application? previous,
  SchoolIdFileReader? schoolIdReader,
  ScheduleFileReader? scheduleReader,
  RequirementFilePicker? filePicker,
  RequirementFileUploader? fileUploader,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: ApplyDialog(
        call: call,
        previous: previous,
        schoolIdReader: schoolIdReader,
        scheduleReader: scheduleReader,
        filePicker: filePicker,
        fileUploader: fileUploader,
      ),
    ),
  );
}

/// The way in: the Head's current hiring call, with what to submit and an
/// Apply button — or why applying isn't possible right now.
class _ApplyCard extends StatelessWidget {
  final AppState state;
  final SchoolIdFileReader? schoolIdReader;
  final ScheduleFileReader? scheduleReader;
  final RequirementFilePicker? filePicker;
  final RequirementFileUploader? fileUploader;
  const _ApplyCard({
    required this.state,
    this.schoolIdReader,
    this.scheduleReader,
    this.filePicker,
    this.fileUploader,
  });

  @override
  Widget build(BuildContext context) {
    final call = state.currentHiringCall;
    final open = state.hiringCallTakesApplications(call);
    final closedReason = applicationClosedReason(state);
    final canApply = open && closedReason == null;
    final offices = state.officesNeedingAssistants;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: studentCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: canApply ? AppTheme.maroon : AppTheme.slate400,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Apply to be a Student Assistant',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    if (call != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        call.title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _OpenPill(open: canApply),
            ],
          ),
          if (call != null) ...[
            if (call.body.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                call.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.slate600,
                  height: 1.6,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (call.deadline != null)
                  _MetaChip(
                    icon: Icons.event_rounded,
                    label: 'Apply by ${call.deadline!}',
                    color: AppTheme.amber500,
                  ),
                // No slots: applicants aren't hired for a number of places
                // but matched to the offices' requests.
                TextButton.icon(
                  onPressed: () => showAnnouncementDetailsDialog(context, call),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('Full details'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.slate600,
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const StudentSectionLabel("WHAT YOU'LL SUBMIT"),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // The Head checks one against the other before screening.
                const _Step(
                  icon: Icons.badge_outlined,
                  label: 'Student ID + school ID photo',
                ),
                const _Step(
                  icon: Icons.assignment_outlined,
                  label: 'Application form',
                ),
                const _Step(
                  icon: Icons.psychology_outlined,
                  label: 'Your skills',
                ),
                // Every call asks for it: it becomes the Calendar and DTR
                // schedule of those approved.
                const _Step(
                  icon: Icons.calendar_month_outlined,
                  label: 'Your class schedule',
                ),
                for (final req in call.requirements)
                  if (!Application.isSchoolIdRequirement(req) &&
                      !Application.isApplicationFormRequirement(req))
                    RequirementChip(label: req),
              ],
            ),
          ],
          // Shown even when applying is closed: where help is wanted.
          if (offices.isNotEmpty) ...[
            const SizedBox(height: 16),
            const StudentSectionLabel('OFFICES THAT NEED STUDENT ASSISTANTS'),
            const SizedBox(height: 8),
            _OfficesNeedHelp(offices: offices),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppTheme.slate500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    offices.isEmpty
                        ? "You don't choose an office. The Head of Student "
                              'Assistantship compares your skills with what '
                              'the offices need, picks who goes to screening, '
                              'and places those approved in an office.'
                        : "You don't choose an office. These offices have "
                              'asked for help, but the Head of Student '
                              'Assistantship compares your skills with what '
                              'they need, picks who goes to screening, and '
                              'decides where those approved are placed.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.slate600,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.amber50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.amber500.withValues(alpha: 0.35),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 16,
                  color: AppTheme.amber500,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Important: Please prepare and bring physical copies of '
                    'any requirements mentioned in the announcement. '
                    'Shortlisted applicants will be scheduled for an interview '
                    'with the Head of Student Assistantship.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (canApply)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _openApplyDialog(
                  context,
                  state,
                  call!,
                  schoolIdReader: schoolIdReader,
                  scheduleReader: scheduleReader,
                  filePicker: filePicker,
                  fileUploader: fileUploader,
                ),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Apply Now'),
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
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: AppTheme.slate400,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      closedReason ?? 'Applications are closed.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate500,
                      ),
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

/// The offices that asked for a Student Assistant and the skills each
/// needs. Information only: the Head decides where students are placed.
/// Past [_shownAtFirst] offices, the rest wait behind "Show more".
class _OfficesNeedHelp extends StatefulWidget {
  final List<({String office, List<String> skills})> offices;
  const _OfficesNeedHelp({required this.offices});

  static const _shownAtFirst = 4;
  static const _skillsShown = 4;

  @override
  State<_OfficesNeedHelp> createState() => _OfficesNeedHelpState();
}

class _OfficesNeedHelpState extends State<_OfficesNeedHelp> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final offices = widget.offices;
    final hidden = offices.length - _OfficesNeedHelp._shownAtFirst;
    final shown = _all || hidden <= 0
        ? offices
        : offices.take(_OfficesNeedHelp._shownAtFirst).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in shown)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.maroon50,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.apartment_outlined,
                    size: 16,
                    color: AppTheme.maroon,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.office,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                        ),
                      ),
                      if (entry.skills.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final skill in entry.skills.take(
                              _OfficesNeedHelp._skillsShown,
                            ))
                              _SkillChip(skill),
                            if (entry.skills.length >
                                _OfficesNeedHelp._skillsShown)
                              _SkillChip(
                                '+${entry.skills.length - _OfficesNeedHelp._skillsShown}',
                                muted: true,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (hidden > 0)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.slate600,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(_all ? 'Show less' : 'Show $hidden more'),
          ),
      ],
    );
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool muted;
  const _SkillChip(this.label, {this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: muted ? AppTheme.slate100 : AppTheme.maroon50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted ? AppTheme.slate600 : AppTheme.maroon,
        ),
      ),
    );
  }
}

class _OpenPill extends StatelessWidget {
  final bool open;
  const _OpenPill({required this.open});

  @override
  Widget build(BuildContext context) {
    final color = open ? AppTheme.emerald500 : AppTheme.slate500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: open ? AppTheme.emerald50 : AppTheme.slate100,
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
            open ? 'Open' : 'Closed',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Step({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.slate100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.slate600),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the student's application stands: a three-step track (applied,
/// screening, decision) and what happens next.
class _MyApplicationCard extends StatelessWidget {
  final Application application;
  final AppState state;
  final SchoolIdFileReader? schoolIdReader;
  final ScheduleFileReader? scheduleReader;
  final RequirementFilePicker? filePicker;
  final RequirementFileUploader? fileUploader;
  const _MyApplicationCard({
    required this.application,
    required this.state,
    this.schoolIdReader,
    this.scheduleReader,
    this.filePicker,
    this.fileUploader,
  });

  @override
  Widget build(BuildContext context) {
    final status = application.status;
    final color = applicationStatusColor(status);
    final decided = !application.isUndecided;
    final rejected = status == Application.rejected;
    final call = state.currentHiringCall;
    final canApplyAgain = rejected && state.hiringCallTakesApplications(call);
    final message = switch (status) {
      Application.forScreening =>
        'You were selected for screening. The Head of Student Assistantship '
            'will set your interview.',
      Application.approved || 'Accepted' =>
        'You are now a Student Assistant. The Head will place you in an '
            'office that fits your skills.',
      Application.waitlisted =>
        'You are on the waitlist. The Head may still approve you when an '
            'office needs someone.',
      Application.rejected =>
        'Your application was not accepted. Fix what the Head pointed out '
            'below and apply again: your skills and files are kept, so you '
            'only replace what was wrong.',
      _ =>
        'Submitted. The Head is matching applicants\' skills to the offices '
            'that need help, and will pick who goes to screening.',
    };
    final decisionLabel = switch (status) {
      Application.approved || 'Accepted' => 'Approved',
      Application.waitlisted => 'Waitlisted',
      Application.rejected => 'Not accepted',
      _ => 'Decision',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: studentCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Your application',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
              ),
              // Named as the track names it.
              ApplicationStatusPill(
                status,
                label: rejected ? 'Not accepted' : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            application.announcementTitle == Application.generalTitle ||
                    application.announcementTitle.isEmpty
                ? 'Student Assistant · submitted ${application.appliedAt}'
                : '${application.announcementTitle} · submitted '
                      '${application.appliedAt}',
            style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TrackStep(label: 'Applied', done: true, color: color),
              // A rejection comes before screening.
              TrackLine(
                done: status != Application.pending && !rejected,
                color: color,
              ),
              TrackStep(
                label: 'Screening',
                done: decided && !rejected,
                current: status == Application.forScreening,
                color: color,
              ),
              TrackLine(done: decided, color: color),
              TrackStep(
                label: decisionLabel,
                done: decided,
                failed: rejected,
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
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.slate700,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          StatusGuideLink(
            label: 'What does this mean?',
            onTap: () => showApplicationStatusGuide(context, forStudent: true),
          ),
          if (status == Application.pending ||
              status == Application.forScreening) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.amber50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.amber500.withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 15,
                    color: AppTheme.amber500,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Remember to bring physical copies of any requirements '
                      'mentioned in the announcement and be ready for your '
                      'interview.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.slate700,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (application.applicationFormDoc != null ||
              application.applicationForm != null) ...[
            const SizedBox(height: 14),
            const StudentSectionLabel('APPLICATION FORM'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your filled Application Form for Student Assistantship '
                    'is ready to preview or download.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => previewFilledApplicationForm(
                          context,
                          application,
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 15),
                        label: const Text('Preview Form'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.maroon,
                          side: const BorderSide(color: AppTheme.maroon200),
                        ),
                      ),
                      AsyncButton(
                        kind: AsyncButtonKind.elevated,
                        onPressed: () => downloadFilledApplicationForm(
                          context,
                          application,
                        ),
                        icon: Icons.download_rounded,
                        label: 'Download Form',
                        busyLabel: 'Downloading…',
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (application.remarks?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              rejected
                  ? 'Reason: ${application.remarks!}'
                  : 'Remarks: ${application.remarks!}',
              style: TextStyle(
                fontSize: rejected ? 13 : 12,
                fontWeight: rejected ? FontWeight.w700 : FontWeight.w400,
                color: rejected ? AppTheme.red500 : AppTheme.slate600,
                fontStyle: rejected ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ],
          if (rejected) ...[
            const SizedBox(height: 14),
            if (canApplyAgain)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _openApplyDialog(
                    context,
                    state,
                    call!,
                    previous: application,
                    schoolIdReader: schoolIdReader,
                    scheduleReader: scheduleReader,
                    filePicker: filePicker,
                    fileUploader: fileUploader,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Apply Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.maroon,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              const Text(
                'You can apply again once applications are open.',
                style: TextStyle(fontSize: 12, color: AppTheme.slate500),
              ),
          ],
          if (application.skills.isNotEmpty) ...[
            const SizedBox(height: 14),
            const StudentSectionLabel('YOUR SKILLS'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final skill in application.skills)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.maroon50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      skill,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.maroon,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (application.submittedDocuments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${application.submittedDocuments.length} '
              'document${application.submittedDocuments.length == 1 ? '' : 's'} '
              'submitted',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the Head's announcements, to read.
class _NoticeCard extends StatelessWidget {
  final Announcement notice;
  const _NoticeCard({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: studentCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.maroon50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: AppTheme.maroon,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Posted by ${notice.postedBy} · ${notice.postedOn}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (notice.body.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              notice.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.slate600,
                height: 1.6,
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showAnnouncementDetailsDialog(context, notice),
              icon: const Icon(Icons.visibility_outlined, size: 14),
              label: const Text('View details'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.slate600,
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The application form: the student's Student ID with a photo of their
/// school ID (the Head checks one against the other), their skills (picked
/// from the Head's list or typed in), their class schedule, and a file for
/// each of the hiring call's requirements. No office is asked for.
class ApplyDialog extends StatefulWidget {
  final Announcement call;

  /// The rejected application this replaces: its skills, and its files for
  /// requirements the call still asks for, are filled in to start from.
  final Application? previous;
  @visibleForTesting
  final SchoolIdFileReader? schoolIdReader;
  @visibleForTesting
  final ScheduleFileReader? scheduleReader;
  @visibleForTesting
  final RequirementFilePicker? filePicker;
  @visibleForTesting
  final RequirementFileUploader? fileUploader;

  const ApplyDialog({
    super.key,
    required this.call,
    this.previous,
    this.schoolIdReader,
    this.scheduleReader,
    this.filePicker,
    this.fileUploader,
  });

  @override
  State<ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends State<ApplyDialog> {
  static const int _initialVisibleSkills = 8;

  final _skillsCtrl = TextEditingController();
  final _skillsScrollCtrl = ScrollController();
  final _selectedSkills = <String>{};
  bool _showAllSkills = false;
  final Map<String, Map<String, dynamic>> _uploaded = {};

  /// Requirements uploading now. Snackbars would be hidden behind the
  /// dialog, so feedback is shown inside it.
  final _uploading = <String>{};
  bool _scanningId = false;
  String? _idScanError;
  int _idScanToken = 0;
  String? _notice;
  var _noticeIsError = false;
  var _submitting = false;

  Announcement get call => widget.call;

  /// Requirements still holding the file from the rejected application.
  final _kept = <String>{};

  /// The Student ID typed here. Locked to the profile's when the profile
  /// already holds one in the 23B0626 shape (the rules allow only that).
  final _studentIdCtrl = TextEditingController();
  String? _lockedStudentId;

  /// Where the photo of the school ID is kept among [_uploaded]: the call's
  /// own "School ID" requirement when it lists one, else its own entry
  /// (which isn't one of the call's requirements, so it isn't counted
  /// with them).
  late final String _schoolIdKey = call.requirements.firstWhere(
    Application.isSchoolIdRequirement,
    orElse: () => Application.schoolIdDocument,
  );

  /// The call's requirements other than the school ID and the official
  /// Application Form, which each have their own section on the form.
  List<String> get _otherRequirements => call.requirements
      .where(
        (r) =>
            !Application.isSchoolIdRequirement(r) &&
            !Application.isApplicationFormRequirement(r),
      )
      .toList();

  /// Structured responses for the official MarSU Application Form.
  ApplicationFormData? _applicationForm;
  bool _formFromLastTime = false;
  Uint8List? _photoBytes;
  String? _photoExt;

  /// The class schedule: its file and the classes read from it. Asked on
  /// every application; approved, it becomes the student's schedule on the
  /// Calendar and in the DTR/Accomplishment Report.
  late final ClassScheduleController _schedule = ClassScheduleController(
    rows: [
      for (final r in widget.previous?.classSchedule?.subjects ?? const [])
        ClassMeetingRow.fromRule(r),
    ],
    fileName: widget.previous?.classSchedule?.fileName,
    filePath: widget.previous?.classSchedule?.filePath,
  );
  List<String> _scheduleProblems = const [];

  @override
  void initState() {
    super.initState();
    _schedule.addListener(_onScheduleChanged);
    _studentIdCtrl.addListener(_onStudentIdChanged);
    final savedUser = context.read<AppState>().currentUser;
    final saved = (savedUser?.studentId ?? '').trim().toUpperCase();
    final avatar = ApplicationFormDocumentService.decodeAvatarDataUri(
      savedUser?.avatar,
    );
    if (avatar != null) {
      _photoBytes = avatar.bytes;
      _photoExt = avatar.ext;
    }
    if (isValidStudentId(saved)) {
      _lockedStudentId = saved;
      _studentIdCtrl.text = saved;
    }
    final previous = widget.previous;
    if (previous == null) return;
    if (previous.applicationForm != null) {
      _applicationForm = previous.applicationForm;
      _formFromLastTime = true;
    }
    _selectedSkills.addAll(previous.skills);
    for (final doc in previous.submittedDocuments) {
      // The school ID photo, whatever it was listed as, goes back in its
      // place; other files only for requirements the call still asks for.
      if (Application.isApplicationFormRequirement(doc.requirementName)) {
        continue;
      }
      final key = Application.isSchoolIdRequirement(doc.requirementName)
          ? _schoolIdKey
          : doc.requirementName;
      if (key != _schoolIdKey && !call.requirements.contains(key)) continue;
      _uploaded[key] = {
        'fileName': doc.fileName,
        // Saved in MB; the form counts bytes.
        'fileSize': doc.fileSize == null ? null : doc.fileSize! * 1024 * 1024,
        'storagePath': doc.storagePath,
        'downloadUrl': doc.downloadUrl,
      };
      _kept.add(key);
    }
    if (_lockedStudentId == null && _uploaded.containsKey(_schoolIdKey)) {
      _studentIdCtrl.text = (previous.studentNumber ?? saved)
          .trim()
          .toUpperCase();
    }
  }

  /// Whether the school ID photo can be read here. The Android app can't:
  /// the student types the Student ID and the Head checks it against the
  /// photo, as for every application.
  bool get _canScanId =>
      widget.schoolIdReader != null || SchoolIdReader.isSupported;

  @override
  void dispose() {
    if (_scanningId) SchoolIdReader.cancel();
    _schedule.removeListener(_onScheduleChanged);
    _schedule.dispose();
    _skillsCtrl.dispose();
    _skillsScrollCtrl.dispose();
    _studentIdCtrl.removeListener(_onStudentIdChanged);
    _studentIdCtrl.dispose();
    super.dispose();
  }

  void _onStudentIdChanged() {
    final form = _applicationForm;
    if (form == null) return;
    final id = _studentIdCtrl.text.trim().toUpperCase();
    if (form.studentNumber != id) {
      setState(() => _applicationForm = form.copyWith(studentNumber: id));
    }
  }

  void _toggleSkill(String skill, bool selected) {
    setState(() {
      _selectedSkills.removeWhere(
        (s) => s.toLowerCase() == skill.toLowerCase(),
      );
      if (selected) {
        _selectedSkills.add(skill);
        _skillsCtrl.clear();
      }
    });
  }

  void _onScheduleChanged() {
    // Problems shown after a try clear as they are fixed.
    if (_scheduleProblems.isNotEmpty) {
      setState(() => _scheduleProblems = _schedule.problems());
    } else {
      setState(() {});
    }
  }

  void _addTypedSkills() {
    final state = context.read<AppState>();
    // A skill already on the Head's list, typed in any case, is that one:
    // "communication skills" picks "Communication Skills".
    final values = _skillsCtrl.text
        .split(',')
        .map((skill) => skill.trim())
        .where((skill) => skill.isNotEmpty)
        .map((skill) => state.findSkill(skill) ?? skill);
    setState(() {
      for (final value in values) {
        if (!_selectedSkills.any(
          (skill) => skill.toLowerCase() == value.toLowerCase(),
        )) {
          _selectedSkills.add(value);
        }
      }
      _skillsCtrl.clear();
    });
  }

  /// File types the school ID photo may be: a photo or a scan.
  static const _schoolIdTypes = ['jpg', 'jpeg', 'png', 'pdf'];

  Future<void> _upload(String req, AppState state) async {
    final spec = RequirementSpec.parse(req);
    final isSchoolId = req == _schoolIdKey;
    // The school ID photo takes a photo or a PDF, whatever its spec says.
    final allowed = isSchoolId ? _schoolIdTypes : spec.allowedExtensions;
    var uploadStarted = false;
    var scanStarted = false;
    try {
      final file = widget.filePicker != null
          ? await widget.filePicker!(req)
          : await () async {
              final result = await FilePicker.platform.pickFiles(
                type: allowed.isEmpty ? FileType.any : FileType.custom,
                allowedExtensions: allowed.isEmpty ? null : allowed,
                allowMultiple: false,
                withData: true,
              );
              return result == null || result.files.isEmpty
                  ? null
                  : result.files.single;
            }();
      if (file == null) return;
      final extension = (file.extension ?? '').toLowerCase();
      if (allowed.isNotEmpty && !allowed.contains(extension)) {
        throw Exception(
          isSchoolId
              ? 'The school ID must be a JPG, PNG or PDF file.'
              : 'Only ${spec.fileTypeLabel} files are accepted for this requirement.',
        );
      }
      final fileBytes = file.bytes;
      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception(
          'This file is not available in the browser session. Please choose '
          'the file again.',
        );
      }
      if (fileBytes.length > SupabaseStorageService.maxUploadBytes) {
        throw Exception('The file must be 10 MB or smaller.');
      }

      String? scannedId;
      final reader = !isSchoolId
          ? null
          : widget.schoolIdReader ??
                (SchoolIdReader.isSupported ? SchoolIdReader.read : null);
      // Without a reader the photo is simply uploaded, and the Student ID
      // is typed.
      if (reader != null) {
        final token = ++_idScanToken;
        if (!mounted) return;
        setState(() {
          scanStarted = true;
          _scanningId = true;
          _idScanError = null;
          _notice = null;
        });
        final mime = switch (extension) {
          'pdf' => 'application/pdf',
          'png' => 'image/png',
          _ => 'image/jpeg',
        };
        final scan = await reader(fileBytes, mime);
        if (!mounted || token != _idScanToken) return;
        if (!scan.ok || !isValidStudentId(scan.studentId ?? '')) {
          setState(() {
            _scanningId = false;
            _idScanError =
                scan.reason ??
                'This file was not accepted. Upload a clear photo of the front '
                    'of your MarSU school ID.';
          });
          return;
        }
        scannedId = scan.studentId!.trim().toUpperCase();
        if (_lockedStudentId != null && scannedId != _lockedStudentId) {
          setState(() {
            _scanningId = false;
            _idScanError =
                'The Student ID on this photo ($scannedId) does not match your '
                'account Student ID ($_lockedStudentId).';
          });
          return;
        }
        setState(() => _scanningId = false);
        scanStarted = false;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String? authUid;
      try {
        authUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
      final storagePath =
          'applications/${authUid ?? state.currentUser?.id ?? 'user'}/$timestamp/${randomObjectName(file.name)}';
      if (!mounted) return;
      setState(() {
        uploadStarted = true;
        _uploading.add(req);
        _notice = null;
      });
      final downloadUrl = widget.fileUploader != null
          ? await widget.fileUploader!(
              fileBytes,
              storagePath,
              file.extension ?? '',
            )
          : await SupabaseStorageService.instance.uploadDocument(
              bytes: fileBytes,
              path: storagePath,
              contentType: SupabaseStorageService.contentTypeForExtension(
                file.extension ?? '',
              ),
            );
      if (!mounted) return;
      setState(() {
        _uploading.remove(req);
        _kept.remove(req);
        _uploaded[req] = {
          'fileName': file.name,
          'fileSize': file.size,
          if (!kIsWeb) 'filePath': file.path,
          'bytes': fileBytes,
          'storagePath': storagePath,
          'downloadUrl': downloadUrl,
        };
        if (isSchoolId && scannedId != null) {
          _studentIdCtrl.text = scannedId;
          _idScanError = null;
          _noticeIsError = false;
          _notice = 'School ID verified ($scannedId) and uploaded: ${file.name}';
        } else {
          _noticeIsError = false;
          _notice = '${spec.label} uploaded: ${file.name}';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (scanStarted) {
            _scanningId = false;
            _idScanError = '$e';
          }
          if (uploadStarted) _uploading.remove(req);
          if (!scanStarted) {
            _noticeIsError = true;
            _notice = 'Error uploading file: $e';
          }
        });
      }
    }
  }

  Future<void> _submit(AppState state) async {
    // The form may have been open since the call closed or its deadline
    // passed.
    final current = state.currentHiringCall;
    if (current?.id != call.id || !state.hiringCallTakesApplications(current)) {
      setState(() {
        _noticeIsError = true;
        _notice = call.isPastDeadline()
            ? 'The deadline (${call.deadline}) has passed, so applications '
                  'are closed.'
            : 'Applications have closed, so this form can no longer be sent.';
      });
      return;
    }
    if (_scanningId) {
      setState(() {
        _noticeIsError = true;
        _notice = 'Wait for your school ID to finish scanning.';
      });
      return;
    }
    if (_schedule.busy) {
      setState(() {
        _noticeIsError = true;
        _notice =
            'Wait for your class schedule to finish uploading and reading.';
      });
      return;
    }
    final scheduleProblems = _schedule.problems();
    if (scheduleProblems.isNotEmpty) {
      setState(() {
        _scheduleProblems = scheduleProblems;
        _noticeIsError = true;
        _notice = 'Check your class schedule: ${scheduleProblems.first}';
      });
      return;
    }
    final studentId = _studentIdCtrl.text.trim().toUpperCase();
    if (!_uploaded.containsKey(_schoolIdKey) || !isValidStudentId(studentId)) {
      setState(() {
        _noticeIsError = true;
        _notice = _canScanId
            ? 'Upload a clear photo of the front of your MarSU school ID so '
                  'your Student ID can be scanned.'
            : !_uploaded.containsKey(_schoolIdKey)
            ? 'Upload a clear photo of the front of your MarSU school ID.'
            : 'Type your Student ID as printed on your school ID '
                  '(like 23B0626).';
      });
      return;
    }
    if (!call.requirements
        .where((r) => !Application.isApplicationFormRequirement(r))
        .every(_uploaded.containsKey)) {
      setState(() {
        _noticeIsError = true;
        _notice = 'Please upload all required documents before submitting.';
      });
      return;
    }
    if (_applicationForm == null || _applicationForm!.problems().isNotEmpty) {
      setState(() {
        _noticeIsError = true;
        _notice = 'Please fill out the Application Form before submitting.';
      });
      return;
    }
    _addTypedSkills();
    setState(() {
      _submitting = true;
      _notice = null;
    });
    // Another account holding this ID: the Head would have to sort it out,
    // so say so now rather than after the Head looks.
    if (_lockedStudentId == null &&
        await state.studentIdTakenByAnother(studentId)) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _noticeIsError = true;
        _notice =
            'This Student ID is already registered to another account. If '
            "it's yours, contact the Head of Student Assistantship.";
      });
      return;
    }
    if (!mounted) return;
    final user = state.currentUser!;
    final now = state.philippineClock();
    final today = state.philippineToday(now);
    final id = Application.idFor(user.id, state.academicYear);
    final scheduleName = _schedule.fileName ?? 'Class schedule';
    final syncedForm = _applicationForm!.copyWith(
      academicYear: state.academicYear,
      studentNumber: studentId,
      dateSubmitted: today,
    );

    String? authUid;
    try {
      authUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {}
    final uploadStamp = DateTime.now().millisecondsSinceEpoch;
    late final ApplicationDocument uploadedFormDoc;
    try {
      final generatedForm = await const ApplicationFormDocumentService()
          .generateApplicationForm(
            data: syncedForm,
            applicationId: id,
            photoBytes: _photoBytes,
            photoExtension: _photoExt,
          );
      final formBytes = generatedForm.bytes!;
      final formStoragePath =
          'applications/${authUid ?? user.id}/$uploadStamp/${randomObjectName(generatedForm.fileName)}';
      final formUrl = widget.fileUploader != null
          ? await widget.fileUploader!(formBytes, formStoragePath, 'docx')
          : await SupabaseStorageService.instance.uploadDocument(
              bytes: formBytes,
              path: formStoragePath,
              contentType: SupabaseStorageService.contentTypeForExtension(
                'docx',
              ),
            );
      uploadedFormDoc = ApplicationDocument(
        id: 'appdoc_${uploadStamp}_form',
        applicationId: id,
        requirementName: Application.applicationFormDocument,
        fileName: generatedForm.fileName,
        uploadedAt: today,
        description: generatedForm.description,
        fileSize: formBytes.length / 1024 / 1024,
        storagePath: formStoragePath,
        downloadUrl: formUrl,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _noticeIsError = true;
        _notice =
            'Could not upload your filled Application Form. Please try again.';
      });
      return;
    }

    final app = Application(
      classSchedule: ClassScheduleSubmission(
        fileName: scheduleName,
        filePath: _schedule.filePath!,
        subjects: _schedule.subjects(
          ownerName: user.name,
          academicYear: state.academicYear,
        ),
      ),
      id: id,
      announcementId: call.id,
      announcementTitle: Application.generalTitle,
      applicantId: user.id,
      applicantName: user.name,
      appliedAt: today,
      skills: _selectedSkills.toList(),
      academicYear: state.academicYear,
      studentNumber: studentId,
      applicationForm: syncedForm,
      submittedDocuments: [
        for (final e in _uploaded.entries)
          ApplicationDocument(
            id: 'appdoc_${uploadStamp}_${e.key.hashCode}',
            applicationId: id,
            requirementName: e.key,
            fileName: e.value['fileName'] ?? 'document',
            uploadedAt: today,
            fileSize: (e.value['fileSize'] ?? 0) / 1024 / 1024,
            bytes: e.value['bytes'] as Uint8List?,
            storagePath: e.value['storagePath'],
            downloadUrl: e.value['downloadUrl'],
          ),
        uploadedFormDoc,
        // The schedule file too, so it opens wherever the Head sees the
        // other documents.
        ApplicationDocument(
          id: 'appdoc_${uploadStamp}_schedule',
          applicationId: id,
          requirementName: ClassScheduleSubmission.requirementName,
          fileName: scheduleName,
          uploadedAt: today,
          fileSize: (_schedule.fileBytes?.length ?? 0) / 1024 / 1024,
          storagePath: _schedule.filePath,
        ),
      ],
    );
    final submitted = await state.submitApplication(app);
    if (!mounted) return;
    if (!submitted) {
      // Keep the dialog open so the uploaded files aren't lost.
      setState(() {
        _submitting = false;
        _noticeIsError = true;
        _notice = 'Application could not be saved. Please try again.';
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Application submitted!'),
        backgroundColor: AppTheme.emerald500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final busy =
        _uploading.isNotEmpty || _scanningId || _submitting || _schedule.busy;
    final reason = widget.previous?.remarks?.trim() ?? '';
    return AnnouncementDialog(
      title: widget.previous == null
          ? 'Apply to be a Student Assistant'
          : 'Apply Again',
      subtitle: widget.previous == null
          ? 'Add your skills and upload the requirements'
          : 'Replace what was wrong, then send it again',
      icon: Icons.send_outlined,
      onClose: _submitting ? () {} : () => Navigator.pop(context),
      notice: _notice == null ? null : _noticeBox(),
      fields: [
        if (widget.previous != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.red50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.red500.withValues(alpha: 0.4)),
            ),
            child: Text(
              reason.isEmpty
                  ? 'Your last application was not accepted.'
                  : 'Why it was not accepted: $reason',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.red500,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'APPLYING FOR',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                  letterSpacing: 1.0,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Student Assistant',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate800,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'No office to pick: your skills are matched to the offices '
                'that need help.',
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const StudentSectionLabel('YOUR STUDENT ID'),
        const SizedBox(height: 4),
        const Text(
          'Upload a clear photo of the front of your MarSU school ID. Your '
          'Student ID number is scanned automatically and cannot be edited.',
          style: TextStyle(fontSize: 11, color: AppTheme.slate500, height: 1.4),
        ),
        const SizedBox(height: 10),
        _requirementTile(
          _schoolIdKey,
          state,
          title: 'Photo of your school ID (front)',
          hint: 'JPG, PNG or PDF, up to 10 MB',
        ),
        if (_idScanError != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.red50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.red500.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppTheme.red500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _idScanError!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.red500,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        TextField(
          controller: _studentIdCtrl,
          readOnly: _lockedStudentId != null || _canScanId,
          enabled: !_submitting,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [StudentIdFormatter()],
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.slate800,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            labelText: 'Student ID',
            hintText: _canScanId
                ? 'Scanned from your school ID photo'
                : 'e.g. 23B0626',
            helperText: _lockedStudentId != null
                ? "From your profile. If it's wrong, ask the Admin to correct it."
                : _canScanId
                ? 'Filled automatically from your school ID photo.'
                : 'Type the Student ID printed on your school ID. The Head '
                      'checks it against the photo.',
            helperMaxLines: 2,
            filled: true,
            fillColor: _lockedStudentId != null || _canScanId
                ? AppTheme.slate100
                : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.slate200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.slate200),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _applicationFormSection(state),
        const SizedBox(height: 18),
        ..._buildSkillsSection(state),
        const SizedBox(height: 22),
        const StudentSectionLabel('YOUR CLASS SCHEDULE'),
        const SizedBox(height: 4),
        Text(
          ClassScheduleEditor.canScan(widget.scheduleReader)
              ? 'Upload your class schedule (a screenshot, a PDF or a photo of '
                    'the printed copy). Your classes are scanned automatically '
                    'and cannot be edited manually. If you are approved, it '
                    'becomes your schedule in SAIS.'
              : 'Upload your class schedule (a screenshot, a PDF or a photo of '
                    'the printed copy), then type your classes as they appear '
                    'on it. The Head checks them against the file. If you are '
                    'approved, it becomes your schedule in SAIS.',
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.slate500,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        ClassScheduleEditor(
          controller: _schedule,
          // The account id is the Firebase uid the upload is checked
          // against.
          ownerId: state.currentUser?.id ?? '',
          // One file is read at a time: starting one read stops the other.
          enabled: !_submitting && !_scanningId,
          readOnly: true,
          reader: widget.scheduleReader,
        ),
        if (_scheduleProblems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _scheduleProblems.take(4).join('\n'),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.red500,
                height: 1.4,
              ),
            ),
          ),
        const SizedBox(height: 22),
        const StudentSectionLabel('REQUIREMENTS'),
        const SizedBox(height: 10),
        if (_otherRequirements.isEmpty)
          const Text(
            'No other documents are needed for this call.',
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          )
        else ...[
          for (final req in _otherRequirements) _requirementTile(req, state),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.blue50,
              border: Border.all(color: AppTheme.blue500),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppTheme.blue500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_otherRequirements.where(_uploaded.containsKey).length}'
                    '/${_otherRequirements.length} required documents uploaded',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.blue500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.amber50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.amber500.withValues(alpha: 0.35),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.record_voice_over_outlined,
                size: 16,
                color: AppTheme.amber500,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reminder: Bring physical copies of any requirements '
                  'mentioned in the announcement. Shortlisted applicants will '
                  'be interviewed.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate700,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      submitButton: SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: busy ? null : () => _submit(state),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.maroon,
            disabledBackgroundColor: AppTheme.maroon.withValues(alpha: 0.7),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _submitting
                    ? 'Submitting...'
                    : _scanningId
                    ? 'Scanning school ID...'
                    : _uploading.isNotEmpty || _schedule.uploading
                    ? 'Uploading file...'
                    : _schedule.reading
                    ? 'Reading schedule...'
                    : 'Submit Application',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSkillsSection(AppState state) {
    final rawQuery = _skillsCtrl.text.trim();
    final query = rawQuery.toLowerCase();
    final unselected = state.skills
        .where(
          (skill) => !_selectedSkills.any(
            (selected) => selected.toLowerCase() == skill.toLowerCase(),
          ),
        )
        .toList();
    final matching = query.isEmpty
        ? unselected
        : unselected
              .where((skill) => skill.toLowerCase().contains(query))
              .toList();
    final isCapped =
        query.isEmpty &&
        !_showAllSkills &&
        matching.length > _initialVisibleSkills;
    final visible = isCapped
        ? matching.take(_initialVisibleSkills).toList()
        : matching;
    final useScrollBox =
        _showAllSkills || (query.isNotEmpty && visible.length > _initialVisibleSkills);

    return [
      Row(
        children: [
          const Expanded(child: StudentSectionLabel('YOUR SKILLS')),
          if (_selectedSkills.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.maroon50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.maroon.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                '${_selectedSkills.length} selected',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.maroon,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'Pick the ones you have, or add your own.',
        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
      ),
      if (_selectedSkills.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final skill in _selectedSkills)
              _SkillPill(
                label: skill,
                selected: true,
                onTap: _submitting ? null : () => _toggleSkill(skill, false),
              ),
          ],
        ),
      ],
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _skillsCtrl,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _addTypedSkills(),
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.slate800,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search skills or add your own...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.slate500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppTheme.slate500,
                ),
                suffixIcon: _skillsCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _skillsCtrl.clear()),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppTheme.slate500,
                        ),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.slate200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.maroon,
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _addTypedSkills,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.maroon,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
      if (state.skills.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      query.isNotEmpty
                          ? '${matching.length} matching "$rawQuery"'
                          : 'Available skills (${unselected.length})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate600,
                      ),
                    ),
                  ),
                  if (query.isEmpty &&
                      unselected.length > _initialVisibleSkills)
                    InkWell(
                      onTap: () =>
                          setState(() => _showAllSkills = !_showAllSkills),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          _showAllSkills
                              ? 'Show less'
                              : 'Show all (${unselected.length})',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.maroon,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (unselected.isEmpty && query.isEmpty)
                const Text(
                  'All listed skills selected. Type above to add another.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.slate500),
                )
              else if (matching.isEmpty)
                Text(
                  'No listed skills match "$rawQuery" — click Add to include it.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.slate500,
                  ),
                )
              else if (useScrollBox)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 196),
                  child: Scrollbar(
                    controller: _skillsScrollCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _skillsScrollCtrl,
                      padding: const EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final skill in visible)
                              _SkillPill(
                                label: skill,
                                selected: false,
                                onTap: _submitting
                                    ? null
                                    : () => _toggleSkill(skill, true),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final skill in visible)
                      _SkillPill(
                        label: skill,
                        selected: false,
                        onTap: _submitting
                            ? null
                            : () => _toggleSkill(skill, true),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ];
  }

  Future<void> _openApplicationForm(AppState state) async {
    final user = state.currentUser;
    if (user == null) return;
    final draft = await showApplicationFormDialog(
      context,
      user: user,
      academicYear: state.academicYear,
      semester: state.academicSemester,
      studentNumber: _studentIdCtrl.text.trim().toUpperCase(),
      initialData: _applicationForm,
      initialPhotoBytes: _photoBytes,
      initialPhotoExt: _photoExt,
    );
    if (draft == null || !mounted) return;
    setState(() {
      _applicationForm = draft.data;
      _photoBytes = draft.photoBytes;
      _photoExt = draft.photoExtension;
      _formFromLastTime = false;
      _notice = null;
    });
  }

  Future<void> _previewFilledForm(AppState state) async {
    final form = _applicationForm;
    final user = state.currentUser;
    if (form == null || user == null) return;
    final synced = form.copyWith(
      academicYear: state.academicYear,
      studentNumber: _studentIdCtrl.text.trim().toUpperCase(),
      dateSubmitted: form.dateSubmitted.isNotEmpty
          ? form.dateSubmitted
          : state.philippineToday(),
    );
    final doc = await const ApplicationFormDocumentService()
        .generateApplicationForm(
          data: synced,
          applicationId: Application.idFor(user.id, state.academicYear),
          photoBytes: _photoBytes,
          photoExtension: _photoExt,
        );
    if (!mounted) return;
    await showDocumentPreview(
      context,
      fileName: doc.fileName,
      bytes: doc.bytes,
    );
  }

  Widget _applicationFormSection(AppState state) {
    final filled = _applicationForm != null;
    final pillText = !filled
        ? 'Not filled yet'
        : _formFromLastTime
        ? 'From last time'
        : '✓ Filled';
    final pillColor = !filled
        ? AppTheme.amber500
        : _formFromLastTime
        ? AppTheme.slate600
        : AppTheme.emerald500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StudentSectionLabel('APPLICATION FORM'),
        const SizedBox(height: 4),
        const Text(
          'Fill out the official MarSU Application Form for Student '
          'Assistantship. It will be saved as a filled Word document.',
          style: TextStyle(fontSize: 11, color: AppTheme.slate500, height: 1.4),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: !filled || _formFromLastTime
                  ? AppTheme.slate200
                  : AppTheme.emerald500,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Application Form for Student Assistantship',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pillColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: pillColor),
                    ),
                    child: Text(
                      pillText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: pillColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (filled) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (_studentIdCtrl.text.trim().isNotEmpty)
                      _studentIdCtrl.text.trim().toUpperCase(),
                    _applicationForm!.fullNameDisplay,
                    _applicationForm!.programAndYear,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _openApplicationForm(state),
                    icon: Icon(
                      filled ? Icons.edit_outlined : Icons.assignment_outlined,
                      size: 16,
                    ),
                    label: Text(
                      filled
                          ? 'Edit Application Form'
                          : 'Fill Out Application Form',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.maroon,
                      side: const BorderSide(color: AppTheme.maroon200),
                    ),
                  ),
                  if (filled)
                    AsyncButton(
                      kind: AsyncButtonKind.outlined,
                      onPressed: _submitting
                          ? null
                          : () => _previewFilledForm(state),
                      icon: Icons.visibility_outlined,
                      label: 'Preview Filled Form',
                      busyLabel: 'Preparing…',
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.slate700,
                        side: const BorderSide(color: AppTheme.slate300),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _noticeBox() {
    final color = _noticeIsError ? AppTheme.red500 : AppTheme.emerald500;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _noticeIsError
            ? AppTheme.red500.withValues(alpha: 0.08)
            : AppTheme.emerald50,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _noticeIsError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _notice!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requirementTile(
    String req,
    AppState state, {
    String? title,
    String? hint,
  }) {
    final spec = RequirementSpec.parse(req);
    final typesNote =
        hint ??
        (spec.fileTypeLabel == null
            ? null
            : 'Only ${spec.fileTypeLabel} accepted');
    final uploaded = _uploaded[req];
    final scanning = req == _schoolIdKey && _scanningId;
    final uploading = _uploading.contains(req);
    final busyTile = scanning || uploading;
    final kept = _kept.contains(req);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.slate50,
          border: Border.all(
            color: uploaded == null || kept
                ? AppTheme.slate200
                : AppTheme.emerald500,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? spec.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate800,
                        ),
                      ),
                      if (typesNote != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            typesNote,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.slate500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (uploaded != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kept ? AppTheme.slate100 : AppTheme.emerald50,
                      border: Border.all(
                        color: kept ? AppTheme.slate300 : AppTheme.emerald500,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      kept ? 'From last time' : '✓ Uploaded',
                      style: TextStyle(
                        fontSize: 10,
                        color: kept ? AppTheme.slate600 : AppTheme.emerald500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            if (uploaded != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${uploaded['fileName'] ?? 'Unknown'}'
                  '${uploaded['fileSize'] == null ? '' : ' · ${(uploaded['fileSize'] / 1024 / 1024).toStringAsFixed(2)} MB'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              // The school ID waits while the class schedule is being read:
              // one read at a time.
              onPressed:
                  busyTile ||
                      _submitting ||
                      (req == _schoolIdKey && _schedule.reading)
                  ? null
                  : () => _upload(req, state),
              icon: busyTile
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined, size: 16),
              label: Text(
                scanning
                    ? 'Scanning ID...'
                    : uploading
                    ? 'Uploading...'
                    : uploaded != null
                    ? 'Replace File'
                    : 'Upload Document',
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.slate300),
                foregroundColor: AppTheme.slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _SkillPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = selected ? AppTheme.maroon50 : Colors.white;
    final border = selected
        ? AppTheme.maroon.withValues(alpha: 0.25)
        : AppTheme.slate200;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_rounded : Icons.add_rounded,
                size: 14,
                color: selected ? AppTheme.maroon : AppTheme.slate400,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppTheme.maroon : AppTheme.slate700,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Remove $label',
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppTheme.maroon,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
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
