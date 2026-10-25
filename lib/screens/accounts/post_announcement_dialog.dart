import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/file_names.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/app_theme.dart';

/// Opens the Head's Post Announcement form.
Future<void> showPostAnnouncementDialog(BuildContext context) {
  final state = context.read<AppState>();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: const PostAnnouncementDialog(),
    ),
  );
}

/// The Head's Post Announcement form. A hiring call is how students apply
/// to be a Student Assistant: it sets the documents they upload and the
/// last day to apply, and names no office or number of slots (applicants
/// are matched to the offices' requests by skill afterwards). A notice is
/// information only.
class PostAnnouncementDialog extends StatefulWidget {
  const PostAnnouncementDialog({super.key});

  @override
  State<PostAnnouncementDialog> createState() => _PostAnnouncementDialogState();
}

class _PostAnnouncementDialogState extends State<PostAnnouncementDialog> {
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
  static const _fileTypes = [
    ('any', 'Any file'),
    ('pdf', 'PDF'),
    ('word', 'Word'),
    ('image', 'Image'),
  ];

  final _title = TextEditingController();
  final _body = TextEditingController();
  final _requirement = TextEditingController();
  final _requirementFocus = FocusNode();

  /// True for a hiring call, false for a notice.
  bool _hiringCall = true;

  /// "Oct 30, 2026", the only form the deadline check reads; null for none.
  String? _deadline;
  final _requirements = <String>[];
  String _fileType = 'any';
  PlatformFile? _attachment;

  // Kept once uploaded, so trying again after a failed post doesn't upload
  // the file twice.
  String? _attachmentUrl;
  String? _attachmentPath;
  bool _posting = false;
  final _errors = <String, String>{};
  String _mentionTab = 'All';

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _requirement.dispose();
    _requirementFocus.dispose();
    super.dispose();
  }

  // ── Mentions ──────────────────────────────────────────────

  /// What follows the "@" being typed at the cursor, or null when the
  /// cursor isn't in a mention.
  String? _mentionFragment() {
    final text = _body.text;
    final cursor = _body.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    final fragment = before.substring(at + 1);
    return RegExp(r'\s').hasMatch(fragment) ? null : fragment;
  }

  void _applyMention(String mention) {
    final text = _body.text;
    final cursor = _body.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return;
    final prefix = before.substring(0, at);
    final insert = '$mention ';
    _body.value = TextEditingValue(
      text: '$prefix$insert${text.substring(cursor)}',
      selection: TextSelection.collapsed(offset: prefix.length + insert.length),
    );
    setState(() {});
  }

  // ── Requirements ──────────────────────────────────────────

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
    _requirementFocus.requestFocus();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _deadline =
          '${_months[picked.month - 1]} ${picked.day}, ${picked.year}',
    );
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null || !mounted) return;
    setState(() {
      _attachment = file;
      _attachmentUrl = null;
      _attachmentPath = null;
    });
  }

  // ── Posting ───────────────────────────────────────────────

  bool _validate() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    _errors.clear();
    if (title.length < 3) {
      _errors['title'] = 'Enter a title of at least 3 characters.';
    } else if (title.length > 100) {
      _errors['title'] = 'Keep the title to 100 characters.';
    }
    if (body.length < 10) {
      _errors['body'] = 'Write at least 10 characters.';
    } else if (body.length > 2000) {
      _errors['body'] = 'Keep it to 2,000 characters.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _post() async {
    if (!_validate()) return;
    // What was checked is what's posted, whatever happens to the form
    // while the attachment uploads (it's locked then too).
    final title = _title.text.trim();
    final body = _body.text.trim();
    final hiringCall = _hiringCall;
    final deadline = hiringCall ? _deadline : null;
    final requirements = hiringCall ? List.of(_requirements) : <String>[];
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _posting = true);

    final file = _attachment;
    if (file != null && _attachmentUrl == null) {
      try {
        final uid =
            fb_auth.FirebaseAuth.instance.currentUser?.uid ??
            state.currentUser?.id ??
            'user';
        // 'announcements' is a public root in the upload-document function:
        // any signed-in user can refresh the download link once the signed
        // one expires, which students need for the Head's files.
        final path =
            'announcements/$uid/${DateTime.now().millisecondsSinceEpoch}/${randomObjectName(file.name)}';
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
        setState(() => _posting = false);
        AppSnackBar.showWithMessenger(
          messenger,
          'The attachment could not be uploaded: $e',
          type: SnackType.error,
        );
        return;
      }
    }

    final now = DateTime.now();
    final ok = await state.postAnnouncement(
      Announcement(
        id: 'ann_${now.millisecondsSinceEpoch}',
        title: title,
        body: body,
        postedBy: state.currentUser?.name ?? 'Head',
        postedAt: '${now.month}/${now.day}/${now.year}',
        deadline: deadline,
        requirements: requirements,
        acceptsApplications: hiringCall,
        attachmentName: file?.name,
        attachmentUrl: _attachmentUrl,
        attachmentPath: _attachmentPath,
        attachmentSize: file == null ? null : file.size / (1024 * 1024),
      ),
    );
    if (!mounted) return;
    if (!ok) {
      // Keep the form open so nothing typed is lost.
      setState(() => _posting = false);
      AppSnackBar.showWithMessenger(
        messenger,
        'The announcement could not be posted. Please try again.',
        type: SnackType.error,
      );
      return;
    }
    navigator.pop();
    AppSnackBar.showWithMessenger(
      messenger,
      hiringCall
          ? 'Hiring call posted. Students can now apply to be a Student '
                'Assistant.'
          : 'Announcement posted. Students have been notified.',
      type: SnackType.success,
    );
  }

  // ── Layout ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 520;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 12 : 24,
        vertical: 24,
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 16 : 24,
                  20,
                  narrow ? 16 : 24,
                  24,
                ),
                // Nothing changes while it posts.
                child: IgnorePointer(
                  ignoring: _posting,
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(inputDecorationTheme: _inputTheme()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('TYPE'),
                        const SizedBox(height: 10),
                        _typePicker(narrow),
                        const SizedBox(height: 24),
                        _label('DETAILS'),
                        const SizedBox(height: 10),
                        _titleField(),
                        const SizedBox(height: 14),
                        _bodyField(),
                        if (_hiringCall) ...[
                          const SizedBox(height: 24),
                          _label('APPLICATION'),
                          const SizedBox(height: 10),
                          _applicationSection(narrow),
                        ],
                        const SizedBox(height: 24),
                        _label('ATTACHMENT', optional: true),
                        const SizedBox(height: 10),
                        _attachmentBox(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _footer(narrow),
          ],
        ),
      ),
    );
  }

  InputDecorationTheme _inputTheme() {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(
        color: AppTheme.slate600,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      hintStyle: const TextStyle(color: AppTheme.slate500, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AppTheme.slate200),
      enabledBorder: border(AppTheme.slate200),
      focusedBorder: border(AppTheme.maroon, 1.6),
      errorBorder: border(AppTheme.red500),
      focusedErrorBorder: border(AppTheme.red500, 1.6),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.slate100)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.maroon50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: AppTheme.maroon,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Post Announcement',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _hiringCall
                      ? 'Open Student Assistant applications'
                      : 'Share a notice with students and staff',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _posting ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, {bool optional = false}) => Row(
    children: [
      Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppTheme.slate500,
          letterSpacing: 1.0,
        ),
      ),
      if (optional) ...[
        const SizedBox(width: 6),
        const Text(
          'Optional',
          style: TextStyle(fontSize: 10.5, color: AppTheme.slate500),
        ),
      ],
    ],
  );

  Widget _typePicker(bool narrow) {
    final options = [
      _TypeOption(
        icon: Icons.how_to_reg_outlined,
        title: 'Hiring call',
        text: 'Students apply to be a Student Assistant through it.',
        selected: _hiringCall,
        onTap: () => setState(() => _hiringCall = true),
      ),
      _TypeOption(
        icon: Icons.info_outline_rounded,
        title: 'Notice',
        text: 'Information only; nothing to apply to.',
        selected: !_hiringCall,
        onTap: () => setState(() => _hiringCall = false),
      ),
    ];
    return narrow
        ? Column(children: [options[0], const SizedBox(height: 10), options[1]])
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: options[0]),
                const SizedBox(width: 12),
                Expanded(child: options[1]),
              ],
            ),
          );
  }

  Widget _titleField() => TextField(
    controller: _title,
    onChanged: (_) {
      if (_errors.remove('title') != null) setState(() {});
    },
    decoration: InputDecoration(
      labelText: 'Title',
      hintText: _hiringCall
          ? 'e.g. Hiring of Student Assistants, 1st Semester'
          : 'e.g. Orientation for new Student Assistants',
      errorText: _errors['title'],
      prefixIcon: const Icon(
        Icons.title_rounded,
        color: AppTheme.maroon,
        size: 18,
      ),
    ),
  );

  Widget _bodyField() {
    final state = context.watch<AppState>();
    final fragment = _mentionFragment();
    const roles = ['Student', 'Student Assistant', 'Supervisor'];
    final people = <String, String>{
      for (final user in state.users)
        if (roles.contains(user.role)) '@${user.name}': user.role,
    };
    final tabs = {
      'All': people.keys.toList(),
      'Students': [
        for (final e in people.entries)
          if (e.value == 'Student') e.key,
      ],
      'Student Assistants': [
        for (final e in people.entries)
          if (e.value == 'Student Assistant') e.key,
      ],
      'Supervisors': [
        for (final e in people.entries)
          if (e.value == 'Supervisor') e.key,
      ],
    };
    final suggestions = fragment == null
        ? const <String>[]
        : ((tabs[_mentionTab] ?? const <String>[])
                  .where(
                    (m) => m.toLowerCase().contains(fragment.toLowerCase()),
                  )
                  .toList()
                ..sort())
              .take(6)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _body,
          minLines: 4,
          maxLines: 8,
          onChanged: (_) {
            _errors.remove('body');
            setState(() {});
          },
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: _hiringCall
                ? 'Who can apply, what the work is like, and how to apply.'
                : 'What students and staff need to know.',
            alignLabelWithHint: true,
            errorText: _errors['body'],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 2),
          child: Text(
            'Type @ to mention a student, assistant or supervisor by name.',
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ),
        if (suggestions.isNotEmpty || (fragment != null && people.isNotEmpty))
          Container(
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.slate200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      for (final tab in tabs.keys)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text('$tab (${tabs[tab]!.length})'),
                            selected: _mentionTab == tab,
                            onSelected: (_) =>
                                setState(() => _mentionTab = tab),
                            selectedColor: AppTheme.maroon,
                            labelStyle: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _mentionTab == tab
                                  ? Colors.white
                                  : AppTheme.slate600,
                            ),
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.slate100),
                if (suggestions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No one by that name.',
                      style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                    ),
                  )
                else
                  for (final mention in suggestions)
                    InkWell(
                      onTap: () => _applyMention(mention),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.maroon50,
                              child: Text(
                                mention.length > 1
                                    ? mention[1].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.maroon,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                mention,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slate800,
                                ),
                              ),
                            ),
                            Text(
                              people[mention] ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _applicationSection(bool narrow) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: AppTheme.slate500),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Students apply to be a Student Assistant, not to an '
                  'office, so there are no slots to set: you match '
                  "applicants' skills to the supervisors' requests on "
                  'Applications.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.slate600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Last day to apply.
          InkWell(
            onTap: _pickDeadline,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Last day to apply',
                prefixIcon: const Icon(
                  Icons.event_rounded,
                  color: AppTheme.maroon,
                  size: 18,
                ),
                suffixIcon: _deadline == null
                    ? null
                    : IconButton(
                        tooltip: 'No deadline',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _deadline = null),
                      ),
              ),
              child: Text(
                _deadline ?? 'No deadline',
                style: TextStyle(
                  fontSize: 14,
                  color: _deadline == null
                      ? AppTheme.slate400
                      : AppTheme.slate800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Documents to upload',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Each applicant uploads one file for each.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.slate500),
          ),
          const SizedBox(height: 10),
          if (_requirements.isEmpty)
            const Text(
              'None yet: students would only list their skills.',
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, raw) in _requirements.indexed)
                  _requirementChip(RequirementSpec.parse(raw), index),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _requirement,
                  focusNode: _requirementFocus,
                  onSubmitted: (_) => _addRequirement(),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Certificate of Registration',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Add requirement',
                onPressed: _addRequirement,
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.maroon,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'File type',
                style: TextStyle(fontSize: 11.5, color: AppTheme.slate500),
              ),
              for (final (value, label) in _fileTypes)
                ChoiceChip(
                  label: Text(label),
                  selected: _fileType == value,
                  onSelected: (_) => setState(() => _fileType = value),
                  selectedColor: AppTheme.maroon50,
                  side: BorderSide(
                    color: _fileType == value
                        ? AppTheme.maroon200
                        : AppTheme.slate200,
                  ),
                  labelStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _fileType == value
                        ? AppTheme.maroon
                        : AppTheme.slate600,
                  ),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _requirementChip(RequirementSpec spec, int index) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.maroon200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            spec.fileType == 'image'
                ? Icons.image_outlined
                : Icons.description_outlined,
            size: 13,
            color: AppTheme.maroon,
          ),
          const SizedBox(width: 5),
          // A long name is cut short instead of running off a phone.
          Flexible(
            child: Text(
              spec.fileTypeLabel == null
                  ? spec.label
                  : '${spec.label} (${spec.fileTypeLabel})',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.maroon,
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => setState(() => _requirements.removeAt(index)),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: AppTheme.maroon,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentBox() {
    final file = _attachment;
    if (file == null) {
      return OutlinedButton.icon(
        onPressed: _posting ? null : _pickAttachment,
        icon: const Icon(Icons.attach_file_rounded, size: 17),
        label: const Text('Attach a file for download'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.slate700,
          side: const BorderSide(color: AppTheme.slate300),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            size: 18,
            color: AppTheme.maroon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate800,
                  ),
                ),
                Text(
                  '${(file.size / (1024 * 1024)).toStringAsFixed(2)} MB',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: _posting
                ? null
                : () => setState(() {
                    _attachment = null;
                    _attachmentUrl = null;
                    _attachmentPath = null;
                  }),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppTheme.slate400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(bool narrow) {
    final post = ElevatedButton.icon(
      onPressed: _posting ? null : _post,
      icon: _posting
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
        _posting
            ? 'Posting...'
            : _hiringCall
            ? 'Post Hiring Call'
            : 'Post Notice',
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.maroon,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.maroon.withValues(alpha: 0.7),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final cancel = TextButton(
      onPressed: _posting ? null : () => Navigator.pop(context),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.slate600,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: const Text('Cancel'),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 12, narrow ? 16 : 24, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.slate100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          cancel,
          const SizedBox(width: 8),
          if (narrow) Expanded(child: post) else post,
        ],
      ),
    );
  }
}

/// One of the two kinds of announcement, as a selectable card.
class _TypeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.icon,
    required this.title,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.maroon50 : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.maroon : AppTheme.slate200,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppTheme.maroon : AppTheme.slate500,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppTheme.maroon : AppTheme.slate800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.slate500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? AppTheme.maroon : AppTheme.slate300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
