import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/announcement_widgets.dart';
import '../../widgets/application_status.dart';

/// The student's page: one application to be a Student Assistant, then
/// the Head's announcements to read. A student doesn't apply to an office;
/// the Head matches applicants' skills to the offices that asked for help.
class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

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
              const _PageTitle(
                title: 'Become a Student Assistant',
                subtitle:
                    'Apply once. The Head matches your skills to the offices '
                    'that need help.',
              ),
              const SizedBox(height: 24),
              if (myApplication != null)
                _MyApplicationCard(application: myApplication, state: state)
              else
                _ApplyCard(state: state),
              if (notices.isNotEmpty) ...[
                const SizedBox(height: 32),
                const _SectionLabel('ANNOUNCEMENTS'),
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

class _PageTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _PageTitle({required this.title, required this.subtitle});

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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: AppTheme.slate400,
      letterSpacing: 1.0,
    ),
  );
}

BoxDecoration _cardDecoration() => BoxDecoration(
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

/// Opens the application form for [call]; [previous] is a rejected
/// application it starts from.
void _openApplyDialog(
  BuildContext context,
  AppState state,
  Announcement call, {
  Application? previous,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: ApplyDialog(call: call, previous: previous),
    ),
  );
}

/// The way in: the Head's current hiring call, with what to submit and an
/// Apply button — or why applying isn't possible right now.
class _ApplyCard extends StatelessWidget {
  final AppState state;
  const _ApplyCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final call = state.currentHiringCall;
    final isStudentAssistant = state.currentUser?.role == 'Student Assistant';
    final open = state.hiringCallTakesApplications(call);
    final String? closedReason = isStudentAssistant
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
    final canApply = open && closedReason == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
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
            const _SectionLabel("WHAT YOU'LL SUBMIT"),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _Step(
                  icon: Icons.psychology_outlined,
                  label: 'Your skills',
                ),
                if (call.requirements.isEmpty)
                  const _Step(
                    icon: Icons.description_outlined,
                    label: 'No documents needed',
                  )
                else
                  for (final req in call.requirements)
                    RequirementChip(label: req),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: AppTheme.slate500),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You don't choose an office. The Head of Student "
                    'Assistantship compares your skills with what the offices '
                    'need, picks who goes to screening, and places those '
                    'approved in an office.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.slate600,
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
                onPressed: () => _openApplyDialog(context, state, call!),
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
  const _MyApplicationCard({required this.application, required this.state});

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
      decoration: _cardDecoration(),
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
              ApplicationStatusPill(status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            application.announcementTitle == Application.generalTitle ||
                    application.announcementTitle.isEmpty
                ? 'Student Assistant · submitted ${application.appliedAt}'
                : '${application.announcementTitle} · submitted '
                      '${application.appliedAt}',
            style: const TextStyle(fontSize: 12, color: AppTheme.slate400),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _TrackStep(label: 'Applied', done: true, color: color),
              // A rejection comes before screening.
              _TrackLine(
                done: status != Application.pending && !rejected,
                color: color,
              ),
              _TrackStep(
                label: 'Screening',
                done: decided && !rejected,
                current: status == Application.forScreening,
                color: color,
              ),
              _TrackLine(done: decided, color: color),
              _TrackStep(
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
            const _SectionLabel('YOUR SKILLS'),
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

class _TrackStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;

  /// Finished, but not the way they hoped: a cross instead of a tick.
  final bool failed;
  final Color color;
  const _TrackStep({
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
            color: on ? AppTheme.slate800 : AppTheme.slate400,
          ),
        ),
      ],
    );
  }
}

class _TrackLine extends StatelessWidget {
  final bool done;
  final Color color;
  const _TrackLine({required this.done, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 18, left: 4, right: 4),
      color: done ? color : AppTheme.slate200,
    ),
  );
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
      decoration: _cardDecoration(),
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
                      'Posted by ${notice.postedBy} · ${notice.postedAt}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate400,
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

/// The application form: the student's skills (picked from the Head's
/// list or typed in) and a file for each of the hiring call's
/// requirements. No office is asked for.
class ApplyDialog extends StatefulWidget {
  final Announcement call;

  /// The rejected application this replaces: its skills, and its files for
  /// requirements the call still asks for, are filled in to start from.
  final Application? previous;
  const ApplyDialog({super.key, required this.call, this.previous});

  @override
  State<ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends State<ApplyDialog> {
  final _skillsCtrl = TextEditingController();
  final _selectedSkills = <String>{};
  final Map<String, Map<String, dynamic>> _uploaded = {};

  /// Requirements uploading now. Snackbars would be hidden behind the
  /// dialog, so feedback is shown inside it.
  final _uploading = <String>{};
  String? _notice;
  var _noticeIsError = false;
  var _submitting = false;

  Announcement get call => widget.call;

  /// Requirements still holding the file from the rejected application.
  final _kept = <String>{};

  @override
  void initState() {
    super.initState();
    final previous = widget.previous;
    if (previous == null) return;
    _selectedSkills.addAll(previous.skills);
    for (final doc in previous.submittedDocuments) {
      if (!call.requirements.contains(doc.requirementName)) continue;
      _uploaded[doc.requirementName] = {
        'fileName': doc.fileName,
        // Saved in MB; the form counts bytes.
        'fileSize': doc.fileSize == null ? null : doc.fileSize! * 1024 * 1024,
        'storagePath': doc.storagePath,
        'downloadUrl': doc.downloadUrl,
      };
      _kept.add(doc.requirementName);
    }
  }

  @override
  void dispose() {
    _skillsCtrl.dispose();
    super.dispose();
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

  Future<void> _upload(String req, AppState state) async {
    final spec = RequirementSpec.parse(req);
    var uploadStarted = false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: spec.allowedExtensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: spec.allowedExtensions.isEmpty
            ? null
            : spec.allowedExtensions,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final extension = (file.extension ?? '').toLowerCase();
      if (spec.allowedExtensions.isNotEmpty &&
          !spec.allowedExtensions.contains(extension)) {
        throw Exception(
          'Only ${spec.fileTypeLabel} files are accepted for this requirement.',
        );
      }
      final fileBytes = file.bytes;
      if (fileBytes == null) {
        throw Exception(
          'This file is not available in the browser session. Please choose '
          'the file again.',
        );
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath =
          'applications/${fb_auth.FirebaseAuth.instance.currentUser?.uid ?? state.currentUser?.id ?? 'user'}/$timestamp/$safeName';
      if (!mounted) return;
      setState(() {
        uploadStarted = true;
        _uploading.add(req);
        _notice = null;
      });
      final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
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
        _noticeIsError = false;
        _notice = '${spec.label} uploaded: ${file.name}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (uploadStarted) _uploading.remove(req);
          _noticeIsError = true;
          _notice = 'Error uploading file: $e';
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
    if (_uploaded.length < call.requirements.length) {
      setState(() {
        _noticeIsError = true;
        _notice = 'Please upload all required documents before submitting.';
      });
      return;
    }
    _addTypedSkills();
    setState(() {
      _submitting = true;
      _notice = null;
    });
    final user = state.currentUser!;
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final today = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final id = Application.idFor(user.id, state.academicYear);
    final app = Application(
      id: id,
      announcementId: call.id,
      announcementTitle: Application.generalTitle,
      applicantId: user.id,
      applicantName: user.name,
      appliedAt: today,
      skills: _selectedSkills.toList(),
      academicYear: state.academicYear,
      submittedDocuments: [
        for (final e in _uploaded.entries)
          ApplicationDocument(
            id: 'appdoc_${now.millisecondsSinceEpoch}_${e.key.hashCode}',
            applicationId: id,
            requirementName: e.key,
            fileName: e.value['fileName'] ?? 'document',
            uploadedAt: today,
            fileSize: (e.value['fileSize'] ?? 0) / 1024 / 1024,
            bytes: e.value['bytes'] as Uint8List?,
            storagePath: e.value['storagePath'],
            downloadUrl: e.value['downloadUrl'],
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
    final busy = _uploading.isNotEmpty || _submitting;
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
                  color: AppTheme.slate400,
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
        const _SectionLabel('YOUR SKILLS'),
        const SizedBox(height: 4),
        const Text(
          'Pick the ones you have, or add your own.',
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
        const SizedBox(height: 10),
        if (state.skills.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in state.skills)
                FilterChip(
                  label: Text(skill),
                  selected: _selectedSkills.any(
                    (s) => s.toLowerCase() == skill.toLowerCase(),
                  ),
                  onSelected: _submitting
                      ? null
                      : (value) => setState(() {
                          _selectedSkills.removeWhere(
                            (s) => s.toLowerCase() == skill.toLowerCase(),
                          );
                          if (value) _selectedSkills.add(skill);
                        }),
                  selectedColor: AppTheme.maroon50,
                  checkmarkColor: AppTheme.maroon,
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        // Typed skills that aren't on the Head's list.
        if (_selectedSkills.any(
          (s) => !state.skills.any((k) => k.toLowerCase() == s.toLowerCase()),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final skill in _selectedSkills)
                  if (!state.skills.any(
                    (k) => k.toLowerCase() == skill.toLowerCase(),
                  ))
                    Chip(
                      label: Text(skill),
                      deleteIcon: const Icon(Icons.close, size: 15),
                      onDeleted: () =>
                          setState(() => _selectedSkills.remove(skill)),
                      backgroundColor: AppTheme.maroon50,
                      side: BorderSide(
                        color: AppTheme.maroon.withValues(alpha: 0.2),
                      ),
                    ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _skillsCtrl,
                onSubmitted: (_) => _addTypedSkills(),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.slate800,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Add another skill',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate400,
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
        const SizedBox(height: 22),
        const _SectionLabel('REQUIREMENTS'),
        const SizedBox(height: 10),
        if (call.requirements.isEmpty)
          const Text(
            'No documents are needed for this call.',
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          )
        else ...[
          for (final req in call.requirements) _requirementTile(req, state),
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
                    '${_uploaded.length}/${call.requirements.length} '
                    'required documents uploaded',
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
                    : _uploading.isNotEmpty
                    ? 'Uploading file...'
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

  Widget _requirementTile(String req, AppState state) {
    final spec = RequirementSpec.parse(req);
    final uploaded = _uploaded[req];
    final uploading = _uploading.contains(req);
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
                        spec.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate800,
                        ),
                      ),
                      if (spec.fileTypeLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Only ${spec.fileTypeLabel} accepted',
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
              onPressed: uploading || _submitting
                  ? null
                  : () => _upload(req, state),
              icon: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined, size: 16),
              label: Text(
                uploading
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
