import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/announcement_widgets.dart';
import '../../widgets/shared_widgets.dart';

class SvAnnouncementsScreen extends StatelessWidget {
  const SvAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mine = state.myAnnouncements;
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    final pending = mine.where((a) => a.approvalStatus == 'Pending').length;
    final approved = mine.where((a) => a.approvalStatus == 'Approved').length;
    final rejected = mine.where((a) => a.approvalStatus == 'Rejected').length;
    final reviewedFraction = mine.isEmpty
        ? 0.0
        : (mine.length - pending) / mine.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: HeroBanner(
            isMobile: isMobile,
            icon: Icons.campaign_rounded,
            title: 'Request Student Assistant',
            subtitle:
                'Request a student assistant for your office — sent to '
                'the Head for approval',
            addLabel: 'New Request',
            onAdd: () => showDialog(
              context: context,
              // A long form: only Close or a sent request dismisses it.
              barrierDismissible: false,
              builder: (_) => const _RequestDialog(),
            ),
            stats: [
              HeroStatData(
                label: 'Requests',
                value: '${mine.length}',
                icon: Icons.inbox_rounded,
              ),
              HeroStatData(
                label: 'Pending',
                value: '$pending',
                icon: Icons.hourglass_top_rounded,
              ),
              HeroStatData(
                label: 'Approved',
                value: '$approved',
                icon: Icons.check_circle_rounded,
              ),
              HeroStatData(
                label: 'Rejected',
                value: '$rejected',
                icon: Icons.cancel_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Content ─────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mine.isNotEmpty) ...[
                  ProgressStrip(
                    label: 'Reviewed',
                    icon: Icons.fact_check_rounded,
                    progress: reviewedFraction,
                    trailing: '${mine.length - pending}/${mine.length}',
                  ),
                  const SizedBox(height: 14),
                ],
                if (mine.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: AppTheme.slate100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.campaign_outlined,
                              size: 36,
                              color: AppTheme.slate300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No requests submitted yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate400,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Request a student assistant for your office; the Head approves it before students see it.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.slate300,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...mine.map(
                    (a) => AnnouncementCard(
                      announcement: a,
                      showActions: true,
                      footerActions: [
                        TextButton(
                          onPressed: () =>
                              showAnnouncementDetailsDialog(context, a),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.maroon,
                          ),
                          child: const Text('View Details'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The supervisor's request for a student assistant, laid out like the
/// Head's Post Announcement dialog. It's saved as a Pending announcement;
/// once the Head approves it, students see it and can apply.
class _RequestDialog extends StatefulWidget {
  const _RequestDialog();

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  // What the upload-document function accepts.
  static const _attachmentTypes = ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'];
  static const _maxAttachmentBytes = 10 * 1024 * 1024;
  static const _months = [
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

  final _title = TextEditingController();
  final _body = TextEditingController();
  final _deadline = TextEditingController();
  final _slots = TextEditingController();
  final _requirement = TextEditingController();
  final _requirements = <String>[];
  final _office = _OfficeSelection();
  late final List<Office> _offices;
  String _fileType = 'any'; // 'any' | 'word' | 'pdf' | 'image'
  bool _acceptsApplications = true;
  PlatformFile? _attachment;
  // Kept once uploaded, so trying again after a failed send doesn't
  // upload the file twice.
  String? _attachmentUrl;
  String? _attachmentPath;
  bool _submitting = false;
  Map<String, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    _offices = context.read<AppState>().currentUserOffices;
    if (_offices.length == 1) _office.office = _offices.first;
  }

  @override
  void dispose() {
    for (final controller in [_title, _body, _deadline, _slots, _requirement]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors = {..._errors}..remove(field));
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _deadline.text =
          '${_months[picked.month - 1]} ${picked.day}, ${picked.year}',
    );
  }

  void _addRequirement() {
    final label = _requirement.text.trim();
    if (label.isEmpty) return;
    final spec = RequirementSpec(label, _fileType == 'any' ? null : _fileType);
    setState(() {
      if (!_requirements.contains(spec.encoded)) {
        _requirements.add(spec.encoded);
      }
      _requirement.clear();
      _fileType = 'any';
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _attachmentTypes,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    if (file.bytes == null) return;
    if (file.size > _maxAttachmentBytes) {
      setState(
        () => _errors = {
          ..._errors,
          'attachment': '${file.name} is over 10 MB. Choose a smaller file.',
        },
      );
      return;
    }
    setState(() {
      _attachment = file;
      _attachmentUrl = null;
      _attachmentPath = null;
      _errors = {..._errors}..remove('attachment');
    });
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    final office = _office.resolvedName;
    if (office == null || office.isEmpty) {
      errors['office'] = _offices.isEmpty
          ? 'Enter the name of your office.'
          : 'Choose your office, or add a new one.';
    }
    final title = _title.text.trim();
    if (title.length < 3) {
      errors['title'] = title.isEmpty
          ? 'Enter a position title.'
          : 'Use at least 3 characters.';
    } else if (title.length > 100) {
      errors['title'] = 'Use at most 100 characters.';
    }
    final body = _body.text.trim();
    if (body.length < 10) {
      errors['body'] = body.isEmpty
          ? 'Say what the student assistant will do.'
          : 'Use at least 10 characters.';
    } else if (body.length > 2000) {
      errors['body'] = 'Use at most 2,000 characters.';
    }
    final slots = _slots.text.trim();
    if (slots.isNotEmpty && (int.tryParse(slots) ?? 0) <= 0) {
      errors['slots'] = 'Enter a number above 0.';
    }
    return errors;
  }

  Future<void> _submit() async {
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _submitting = true);

    final file = _attachment;
    if (file != null && _attachmentUrl == null) {
      try {
        final uid =
            fb_auth.FirebaseAuth.instance.currentUser?.uid ??
            state.currentUser?.id ??
            'user';
        final name = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        // The same public root as the Head's announcement attachments, so
        // students can download it once the request is approved.
        final path =
            'announcements/$uid/${DateTime.now().millisecondsSinceEpoch}/$name';
        final extension = file.extension?.toLowerCase();
        _attachmentUrl = await SupabaseStorageService.instance.uploadDocument(
          bytes: file.bytes!,
          path: path,
          contentType: extension == null
              ? null
              : SupabaseStorageService.contentTypeForExtension(extension),
        );
        _attachmentPath = path;
      } catch (e) {
        if (!mounted) return;
        setState(() => _submitting = false);
        AppSnackBar.showWithMessenger(
          messenger,
          'The attachment could not be uploaded: $e',
          type: SnackType.error,
        );
        return;
      }
    }

    final now = DateTime.now();
    final deadline = _deadline.text.trim();
    final slots = _slots.text.trim();
    final ok = await state.submitAnnouncementForApproval(
      Announcement(
        id: 'ann_${now.millisecondsSinceEpoch}',
        title: _title.text.trim(),
        body: _body.text.trim(),
        postedBy: state.currentUser?.name ?? 'Supervisor',
        postedByRole: 'Supervisor',
        postedById: state.currentUser?.id,
        postedAt: '${now.month}/${now.day}/${now.year}',
        deadline: deadline.isEmpty ? null : deadline,
        slots: slots.isEmpty ? null : slots,
        requirements: List.of(_requirements),
        acceptsApplications: _acceptsApplications,
        isOpen: false,
        officeId: _office.office?.id,
        officeName: _office.resolvedName,
        approvalStatus: 'Pending',
        attachmentName: file?.name,
        attachmentUrl: _attachmentUrl,
        attachmentPath: _attachmentPath,
        attachmentSize: file == null ? null : file.size / (1024 * 1024),
      ),
    );
    if (!mounted) return;
    if (!ok) {
      // Keep the dialog open so nothing typed is lost.
      setState(() => _submitting = false);
      AppSnackBar.showWithMessenger(
        messenger,
        'The request could not be sent. Please try again.',
        type: SnackType.error,
      );
      return;
    }
    navigator.pop();
    AppSnackBar.showWithMessenger(
      messenger,
      'Request sent. The Head will review it before students see it.',
      type: SnackType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 760),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: AppTheme.maroon.withValues(alpha: 0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(inputDecorationTheme: _inputTheme),
                    child: _form(),
                  ),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  static final _inputTheme = InputDecorationTheme(
    filled: true,
    fillColor: AppTheme.slate50,
    labelStyle: const TextStyle(
      color: AppTheme.slate600,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    ),
    hintStyle: const TextStyle(color: AppTheme.slate400, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: _border(AppTheme.slate200),
    enabledBorder: _border(AppTheme.slate200),
    focusedBorder: _border(AppTheme.maroon, width: 1.7),
    errorBorder: _border(AppTheme.red500),
    focusedErrorBorder: _border(AppTheme.red500, width: 1.7),
  );

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _header() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.maroon, AppTheme.maroonDark],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request Student Assistant',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Sent to the Head for approval before students see it',
                        style: TextStyle(fontSize: 12.5, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Close',
                  child: GestureDetector(
                    onTap: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: -30,
            top: -30,
            child: IgnorePointer(
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    final deadlineField = TextField(
      controller: _deadline,
      readOnly: true,
      onTap: _pickDeadline,
      decoration: InputDecoration(
        labelText: 'Deadline',
        hintText: 'Optional',
        prefixIcon: const Icon(
          Icons.event_rounded,
          color: AppTheme.maroon,
          size: 18,
        ),
        suffixIcon: _deadline.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear deadline',
                onPressed: () => setState(_deadline.clear),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppTheme.slate400,
                ),
              ),
      ),
    );
    final slotsField = TextField(
      controller: _slots,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => _clearError('slots'),
      decoration: InputDecoration(
        labelText: 'Available Slots',
        hintText: 'Optional',
        errorText: _errors['slots'],
        prefixIcon: const Icon(
          Icons.people_outline_rounded,
          color: AppTheme.maroon,
          size: 18,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('BASIC INFORMATION'),
        const SizedBox(height: 10),
        TextField(
          controller: _title,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('title'),
          decoration: InputDecoration(
            labelText: 'Position Title',
            hintText: 'e.g. Office Assistant',
            errorText: _errors['title'],
            prefixIcon: const Icon(
              Icons.work_outline_rounded,
              color: AppTheme.maroon,
              size: 18,
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _body,
          maxLines: 5,
          onChanged: (_) => _clearError('body'),
          decoration: InputDecoration(
            labelText: 'Description / Reason',
            hintText:
                'What the student assistant will do, and why your office '
                'needs one',
            hintMaxLines: 3,
            alignLabelWithHint: true,
            errorText: _errors['body'],
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 90),
              child: Icon(
                Icons.description_outlined,
                color: AppTheme.maroon,
                size: 18,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('OFFICE & SCHEDULE'),
        const SizedBox(height: 10),
        _OfficePickerField(
          offices: _offices,
          selection: _office,
          errorText: _errors['office'],
          onChanged: () => _clearError('office'),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 360
              ? Column(
                  children: [
                    deadlineField,
                    const SizedBox(height: 14),
                    slotsField,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: deadlineField),
                    const SizedBox(width: 12),
                    Expanded(child: slotsField),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        _acceptApplicationsCard(),
        const SizedBox(height: 20),
        _sectionLabel('REQUIREMENTS'),
        const SizedBox(height: 10),
        _requirementsBox(),
        const SizedBox(height: 20),
        _sectionLabel('ATTACHMENT'),
        const SizedBox(height: 10),
        _attachmentBox(),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: AppTheme.slate500,
      letterSpacing: 1,
    ),
  );

  Widget _acceptApplicationsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _acceptsApplications
            ? AppTheme.maroon.withValues(alpha: 0.06)
            : AppTheme.slate50,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _acceptsApplications
              ? AppTheme.maroon.withValues(alpha: 0.25)
              : AppTheme.slate200,
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accept applications',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate800,
                  ),
                ),
                Text(
                  'Turn off for a normal announcement',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
          Switch(
            value: _acceptsApplications,
            activeThumbColor: AppTheme.maroon,
            onChanged: (value) => setState(() => _acceptsApplications = value),
          ),
        ],
      ),
    );
  }

  Widget _requirementsBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_requirements.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, raw) in _requirements.indexed)
                  _requirementChip(RequirementSpec.parse(raw), index),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _requirement,
            onSubmitted: (_) => _addRequirement(),
            decoration: InputDecoration(
              hintText: 'Add requirement (press Enter)',
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: _smallBorder(AppTheme.slate200),
              enabledBorder: _smallBorder(AppTheme.slate200),
              focusedBorder: _smallBorder(AppTheme.maroon, width: 1.5),
              suffixIcon: IconButton(
                tooltip: 'Add requirement',
                onPressed: _addRequirement,
                icon: const Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: AppTheme.maroon,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'File type:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (value, label) in const [
                        ('any', 'Any file'),
                        ('word', 'Word (.doc/.docx)'),
                        ('pdf', 'PDF'),
                        ('image', 'Image'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _fileTypeChip(value, label),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _smallBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _requirementChip(RequirementSpec spec, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.maroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.maroon.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              spec.fileTypeLabel == null
                  ? spec.label
                  : '${spec.label} (${spec.fileTypeLabel})',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.maroon,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Remove',
            child: GestureDetector(
              onTap: () => setState(() => _requirements.removeAt(index)),
              child: const Icon(
                Icons.close_rounded,
                size: 12,
                color: AppTheme.maroon,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileTypeChip(String value, String label) {
    final selected = _fileType == value;
    return GestureDetector(
      onTap: () => setState(() => _fileType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.maroon : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.maroon : AppTheme.slate200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppTheme.slate600,
          ),
        ),
      ),
    );
  }

  Widget _attachmentBox() {
    final file = _attachment;
    final error = _errors['attachment'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: error == null ? AppTheme.slate200 : AppTheme.red500,
            ),
          ),
          child: file == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickAttachment,
                      icon: const Icon(Icons.attach_file_rounded, size: 16),
                      label: const Text('Attach a file for download'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.maroon,
                        side: const BorderSide(color: AppTheme.maroon),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Optional. PDF, Word or image, up to 10 MB.',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: AppTheme.maroon,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file.name,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!_submitting)
                      IconButton(
                        tooltip: 'Remove attachment',
                        onPressed: () => setState(() {
                          _attachment = null;
                          _attachmentUrl = null;
                          _attachmentPath = null;
                        }),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppTheme.slate400,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              error,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.red500),
            ),
          ),
      ],
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.slate100)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.maroon.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(
              _submitting ? 'Sending…' : 'Submit Request',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.maroon,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.maroon.withValues(alpha: 0.7),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Holds the supervisor's office choice for the request dialog: either an
/// existing office from [currentUserOffices], or a freshly-typed office
/// name when their office isn't in the system yet.
class _OfficeSelection {
  Office? office;
  String customName = '';

  String? get resolvedName {
    if (office != null) return office!.name;
    final trimmed = customName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Office picker: a dropdown of the supervisor's offices plus an
/// "Add a new office" option that reveals a text field for a custom name.
/// Styled by the dialog's input theme.
class _OfficePickerField extends StatefulWidget {
  final List<Office> offices;
  final _OfficeSelection selection;
  final String? errorText;
  final VoidCallback onChanged;

  const _OfficePickerField({
    required this.offices,
    required this.selection,
    required this.errorText,
    required this.onChanged,
  });

  @override
  State<_OfficePickerField> createState() => _OfficePickerFieldState();
}

class _OfficePickerFieldState extends State<_OfficePickerField> {
  static const _addNewSentinel = '__add_new_office__';
  late bool _isAddingNew = widget.offices.isEmpty;
  late final _customCtrl = TextEditingController(
    text: widget.selection.customName,
  );

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    errorText: widget.errorText,
    prefixIcon: const Icon(
      Icons.account_balance_outlined,
      color: AppTheme.maroon,
      size: 18,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_isAddingNew) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _customCtrl,
            onChanged: (value) {
              widget.selection.customName = value;
              widget.onChanged();
            },
            decoration: _decoration('New Office Name'),
          ),
          if (widget.offices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _isAddingNew = false;
                  widget.selection.customName = '';
                  _customCtrl.clear();
                }),
                icon: const Icon(Icons.arrow_back_rounded, size: 14),
                label: const Text('Choose from my offices instead'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.maroon,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'This office will be set up by the Head once your request is approved.',
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
            ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: widget.selection.office?.id,
      isExpanded: true,
      icon: const Icon(Icons.expand_more_rounded, color: AppTheme.slate400),
      decoration: _decoration('Office'),
      hint: const Text('Select your office'),
      items: [
        for (final o in widget.offices)
          DropdownMenuItem(
            value: o.id,
            child: Text(
              o.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.slate800),
            ),
          ),
        const DropdownMenuItem(
          value: _addNewSentinel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: AppTheme.maroon),
              SizedBox(width: 6),
              Text(
                'Add a new office',
                style: TextStyle(
                  color: AppTheme.maroon,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
      onChanged: (value) {
        widget.onChanged();
        if (value == _addNewSentinel) {
          setState(() {
            _isAddingNew = true;
            widget.selection.office = null;
          });
          return;
        }
        setState(() {
          widget.selection.office = widget.offices.firstWhere(
            (o) => o.id == value,
          );
        });
      },
    );
  }
}
