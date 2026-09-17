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

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final announcements = state.studentVisibleAnnouncements;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isCompact = screenWidth < 380;
    final hPad = isMobile ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: isCompact ? 44 : 32,
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
                    const Text(
                      'Announcements',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Open positions for Student Assistants',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate400,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          if (announcements.isEmpty)
            _EmptyAnnouncements()
          else
            ...announcements.map(
              (a) => _AnnouncementCard(announcement: a, state: state),
            ),
        ],
      ),
    );
  }
}

class _EmptyAnnouncements extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.slate100,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.campaign_outlined,
              size: 32,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No announcements yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Check back later for hiring announcements.',
            style: TextStyle(fontSize: 13, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final AppState state;
  const _AnnouncementCard({required this.announcement, required this.state});

  @override
  Widget build(BuildContext context) {
    final hasApplied = state.hasApplied(announcement.id);
    final myApp = state.myApplicationFor(announcement.id);
    final isOpen = announcement.isOpen;
    final acceptsApplications = announcement.acceptsApplications;
    final isStudentAssistant = state.currentUser?.role == 'Student Assistant';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOpen ? AppTheme.maroon : AppTheme.slate400,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            announcement.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isOpen ? AppTheme.emerald50 : AppTheme.slate100,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: isOpen ? AppTheme.emerald500 : AppTheme.slate400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOpen ? 'Open' : 'Closed',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isOpen ? AppTheme.emerald500 : AppTheme.slate600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Posted by ${announcement.postedBy} · ${announcement.postedAt}',
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
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    announcement.body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.slate600,
                      height: 1.6,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (announcement.deadline != null)
                        _MetaChip(
                          icon: Icons.event_rounded,
                          label: 'Due ${announcement.deadline!}',
                          color: AppTheme.amber500,
                        ),
                      if (announcement.slots != null)
                        _MetaChip(
                          icon: Icons.people_rounded,
                          label: '${announcement.slots} slots',
                          color: AppTheme.blue500,
                        ),
                    ],
                  ),

                  if (announcement.requirements.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: announcement.requirements
                          .map((req) => RequirementChip(label: req))
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 14),
                  Divider(color: AppTheme.slate100, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              showAnnouncementDetailsDialog(context, announcement),
                          icon: const Icon(Icons.visibility_outlined, size: 14),
                          label: const Text(
                            'View Details',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.slate600,
                            side: const BorderSide(color: AppTheme.slate300),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (hasApplied && myApp != null)
                    _StatusBanner(application: myApp)
                  else if (isOpen && acceptsApplications && !isStudentAssistant)
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.maroon, AppTheme.maroonDark],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.maroon.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () =>
                            _showApplyDialog(context, announcement, state),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.send_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Apply Now',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (isOpen && !acceptsApplications)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: const Center(
                        child: Text(
                          'Announcement only · Applications not required',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.slate400,
                          ),
                        ),
                      ),
                    )
                  else if (isStudentAssistant)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: AppTheme.slate400,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Student Assistants cannot apply',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.slate400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: AppTheme.slate400,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Applications Closed',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate400,
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
      ),
    );
  }

  void _showApplyDialog(
    BuildContext context,
    Announcement ann,
    AppState state,
  ) {
    if (state.currentUser?.role == 'Student Assistant') return;
    final skillsCtrl = TextEditingController();
    final selectedSkills = <String>{};
    final Map<String, Map<String, dynamic>> uploadedDocuments = {};

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AnnouncementDialog(
          title: 'Submit Application',
          subtitle: 'Fill out the form below to apply',
          icon: Icons.send_outlined,
          onClose: () => Navigator.pop(context),
          fields: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'APPLYING FOR',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate400,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ann.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (ann.requirements.isNotEmpty) ...[
              const Text(
                'REQUIRED DOCUMENTS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate400,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              ...ann.requirements.map(
                (req) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      border: Border.all(
                        color: uploadedDocuments.containsKey(req)
                            ? AppTheme.emerald500
                            : AppTheme.slate200,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    RequirementSpec.parse(req).label,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.slate800,
                                    ),
                                  ),
                                  if (RequirementSpec.parse(req).fileTypeLabel != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Only ${RequirementSpec.parse(req).fileTypeLabel} accepted',
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
                            if (uploadedDocuments.containsKey(req))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.emerald50,
                                  border: Border.all(
                                    color: AppTheme.emerald500,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '✓ Uploaded',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.emerald500,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (uploadedDocuments.containsKey(req))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  uploadedDocuments[req]!['fileName'] ??
                                      'Unknown',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.slate600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (uploadedDocuments[req]!['fileSize'] != null)
                                  Text(
                                    '${(uploadedDocuments[req]!['fileSize'] / 1024 / 1024).toStringAsFixed(2)} MB',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.slate500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final spec = RequirementSpec.parse(req);
                            try {
                              final result = await FilePicker.platform
                                  .pickFiles(
                                    type: spec.allowedExtensions.isEmpty
                                        ? FileType.any
                                        : FileType.custom,
                                    allowedExtensions: spec.allowedExtensions.isEmpty
                                        ? null
                                        : spec.allowedExtensions,
                                    allowMultiple: false,
                                    withData: true,
                                  );
                              if (result != null && result.files.isNotEmpty) {
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
                                    'This file is not available in the browser session. Please choose the file again.',
                                  );
                                }
                                final timestamp =
                                    DateTime.now().millisecondsSinceEpoch;
                                final safeName = file.name.replaceAll(
                                  RegExp(r'[^a-zA-Z0-9._-]'),
                                  '_',
                                );
                                final storagePath =
                                  'applications/${fb_auth.FirebaseAuth.instance.currentUser?.uid ?? state.currentUser?.id ?? 'user'}/$timestamp/$safeName';
                                final downloadUrl = await SupabaseStorageService
                                    .instance
                                    .uploadDocument(
                                      bytes: fileBytes,
                                      path: storagePath,
                                      contentType:
                                          SupabaseStorageService.contentTypeForExtension(
                                            file.extension ?? '',
                                          ),
                                    );
                                setState(() {
                                  uploadedDocuments[req] = {
                                    'fileName': file.name,
                                    'fileSize': file.size,
                                    if (!kIsWeb) 'filePath': file.path,
                                    'bytes': fileBytes,
                                    'storagePath': storagePath,
                                    'downloadUrl': downloadUrl,
                                  };
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${spec.label} uploaded: ${file.name}',
                                      ),
                                      backgroundColor: AppTheme.emerald500,
                                      duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error uploading file: $e'),
        backgroundColor: AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                                );
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.upload_file_outlined,
                            size: 16,
                          ),
                          label: Text(
                            uploadedDocuments.containsKey(req)
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
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'SKILLS / QUALIFICATIONS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate400,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            if (state.skills.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: state.skills.map((skill) {
                  final selected = selectedSkills.contains(skill);
                  return FilterChip(
                    label: Text(skill),
                    selected: selected,
                    onSelected: (value) => setState(() {
                      if (value) {
                        selectedSkills.add(skill);
                      } else {
                        selectedSkills.remove(skill);
                      }
                    }),
                    selectedColor: AppTheme.maroon50,
                    checkmarkColor: AppTheme.maroon,
                  );
                }).toList(),
              ),
            if (state.skills.isNotEmpty) const SizedBox(height: 8),
            if (selectedSkills.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: selectedSkills
                      .map(
                        (skill) => Chip(
                          label: Text(skill),
                          deleteIcon: const Icon(Icons.close, size: 15),
                          onDeleted: () =>
                              setState(() => selectedSkills.remove(skill)),
                          backgroundColor: AppTheme.maroon50,
                          side: BorderSide(
                            color: AppTheme.maroon.withValues(alpha: 0.2),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: skillsCtrl,
                    maxLines: 1,
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
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final values = skillsCtrl.text
                          .split(',')
                          .map((skill) => skill.trim())
                          .where((skill) => skill.isNotEmpty);
                      setState(() {
                        for (final value in values) {
                          if (!selectedSkills.any(
                            (skill) =>
                                skill.toLowerCase() == value.toLowerCase(),
                          )) {
                            selectedSkills.add(value);
                          }
                        }
                        skillsCtrl.clear();
                      });
                    },
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
            const SizedBox(height: 12),
            if (ann.requirements.isNotEmpty)
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
                        '${uploadedDocuments.length}/${ann.requirements.length} required documents uploaded',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.blue500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text(
                'By submitting you confirm you meet the requirements.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.slate400,
                  height: 1.5,
                ),
              ),
          ],
          submitButton: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.maroon, AppTheme.maroonDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () async {
                if (ann.requirements.isNotEmpty &&
                    uploadedDocuments.length < ann.requirements.length) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please upload all required documents before submitting',
                      ),
                      backgroundColor: AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                  );
                  return;
                }
                final typedSkills = skillsCtrl.text.trim().isEmpty
                    ? <String>[]
                    : skillsCtrl.text
                          .trim()
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                final skills = {...selectedSkills, ...typedSkills}.toList();
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
                final docs = uploadedDocuments.entries
                    .map(
                      (e) => ApplicationDocument(
                        id: 'appdoc_${DateTime.now().millisecondsSinceEpoch}_${e.key.hashCode}',
                        applicationId:
                            'app_${DateTime.now().millisecondsSinceEpoch}',
                        requirementName: e.key,
                        fileName: e.value['fileName'] ?? 'document',
                        uploadedAt:
                            '${months[now.month - 1]} ${now.day}, ${now.year}',
                        fileSize: (e.value['fileSize'] ?? 0) / 1024 / 1024,
                        bytes: e.value['bytes'] as Uint8List?,
                        storagePath: e.value['storagePath'],
                        downloadUrl: e.value['downloadUrl'],
                      ),
                    )
                    .toList();
                final app = Application(
                  id: 'app_${DateTime.now().millisecondsSinceEpoch}',
                  announcementId: ann.id,
                  announcementTitle: ann.title,
                  applicantId: state.currentUser!.id,
                  applicantName: state.currentUser!.name,
                  appliedAt: '${months[now.month - 1]} ${now.day}, ${now.year}',
                  skills: skills,
                  submittedDocuments: docs,
                );
                final submitted = await state.submitApplication(app);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      submitted
                          ? 'Application submitted successfully!'
                          : 'Application could not be saved. Please try again.',
                    ),
                    backgroundColor: submitted
                        ? AppTheme.emerald500
                        : Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Submit Application',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle diagonal dot texture used behind announcement card banners.
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

class _StatusBanner extends StatelessWidget {
  final Application application;
  const _StatusBanner({required this.application});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String message;
    switch (application.status) {
      case 'Approved':
        color = AppTheme.emerald500;
        icon = Icons.check_circle_rounded;
        message = 'Your application has been approved!';
        break;
      case 'Waitlisted':
        color = AppTheme.blue500;
        icon = Icons.schedule_rounded;
        message = 'Your application has been placed on the waitlist.';
        break;
      case 'Rejected':
        color = AppTheme.red500;
        icon = Icons.cancel_rounded;
        message = 'Your application was not accepted.';
        break;
      default:
        color = AppTheme.amber500;
        icon = Icons.hourglass_top_rounded;
        message = 'Your application is under review.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Application ${application.status}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Submitted ${application.appliedAt}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  ),
                ),
                if (application.remarks != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Remarks: ${application.remarks!}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}