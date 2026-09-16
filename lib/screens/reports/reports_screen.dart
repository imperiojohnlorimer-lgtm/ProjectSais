import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _filterStatus = 'All';
  String? _reportYear;

  static const Map<String, IconData> _filterIcons = {
    'All': Icons.apps_rounded,
    'Pending': Icons.hourglass_top_rounded,
    'Approved': Icons.check_circle_rounded,
    'Rejected': Icons.cancel_rounded,
  };

  Color _filterColor(String s) {
    switch (s) {
      case 'Pending':
        return AppTheme.amber500;
      case 'Approved':
        return AppTheme.emerald500;
      case 'Rejected':
        return AppTheme.red500;
      default:
        return AppTheme.maroon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final role = state.role;

    final reports = state.filteredReports.where((r) {
      if (_reportYear != null && r.academicYear != _reportYear) return false;
      if (role == 'Student Assistant') {
        return r.studentName == state.currentUser?.name &&
            (_filterStatus == 'All' || r.status == _filterStatus);
      }
      return _filterStatus == 'All' || r.status == _filterStatus;
    }).toList();

    final pendingCount = state.filteredReports
        .where((r) => _reportYear == null || r.academicYear == _reportYear)
        .where((r) => role != 'Student Assistant' || r.studentName == state.currentUser?.name)
        .where((r) => r.status == 'Pending')
        .length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.slate50, Colors.white],
          stops: [0.0, 0.22],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppTheme.maroon, AppTheme.maroonDark],
                        ).createShader(bounds),
                        child: const Text(
                          'Reports',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${reports.length} report${reports.length != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                ),
                if (pendingCount > 0 && role != 'Student Assistant') ...[
                  const SizedBox(width: 12),
                  _pendingBadge(pendingCount),
                ],
                if (role == 'Student Assistant') ...[
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.maroon.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _showSubmitDialog(context, state),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Submit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),

            if (role != 'Student Assistant') ...[
              DropdownButtonFormField<String?>(
                initialValue: _reportYear,
                icon: const Icon(Icons.expand_more_rounded, color: AppTheme.slate400),
                decoration: InputDecoration(
                  labelText: 'Academic year',
                  prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.slate200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.slate200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.maroon, width: 1.6),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All academic years'),
                  ),
                  DropdownMenuItem<String?>(
                    value: state.academicYear,
                    child: Text('Active: ${state.academicYear}'),
                  ),
                  ...state.academicYearArchives.map((archive) {
                    final year = archive['academicYear']?.toString();
                    return DropdownMenuItem<String?>(
                      value: year,
                      child: Text('Archived: $year'),
                    );
                  }),
                ],
                onChanged: (value) => setState(() => _reportYear = value),
              ),
              const SizedBox(height: 14),
            ],

            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Pending', 'Approved', 'Rejected'].map((s) {
                  final selected = _filterStatus == s;
                  final color = _filterColor(s);
                  return GestureDetector(
                    onTap: () => setState(() => _filterStatus = s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? color : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: selected ? color : AppTheme.slate200,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.28),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _filterIcons[s],
                            size: 14,
                            color: selected ? Colors.white : AppTheme.slate400,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            s,
                            style: TextStyle(
                              color: selected ? Colors.white : AppTheme.slate600,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            Expanded(
              child: reports.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      itemCount: reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _ReportCard(
                        report: reports[i],
                        role: role,
                        onReview: role == 'Supervisor'
                            ? () => _showReviewDialog(context, state, reports[i])
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingBadge(int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.amber50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.amber500.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.hourglass_top_rounded, size: 15, color: AppTheme.amber500),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.amber500,
                height: 1.0,
              ),
            ),
            const Text(
              'pending',
              style: TextStyle(fontSize: 10, color: AppTheme.amber500),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.slate100, AppTheme.slate50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 38,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No reports found',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try a different filter or academic year.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.slate400),
          ),
        ],
      ),
    ),
  );

  /// Tasks this user has marked Completed and hasn't archived — these are
  /// the candidates offered to auto-fill the report's "Content /
  /// Accomplishments" field, newest completion first. Tasks that were
  /// already written into a report the supervisor has since Approved are
  /// left out, since they've already been credited and shouldn't be
  /// offered again.
  List<Task> _completedTasksFor(AppState state) {
    final creditedTitles = _titlesInApprovedReports(state);
    final list = state.filteredTasks
        .where(
          (t) =>
              t.status == 'Completed' &&
              !t.isArchived &&
              !creditedTitles.contains(t.title.trim().toLowerCase()),
        )
        .toList();
    list.sort((a, b) => (b.completedAt ?? '').compareTo(a.completedAt ?? ''));
    return list;
  }

  /// Task titles (lower-cased) that appear in the bulleted content of any
  /// of this student's already-Approved reports — built by parsing each
  /// "• Title" / "• Title — description" line the same way
  /// [_composeAccomplishments] originally wrote it.
  Set<String> _titlesInApprovedReports(AppState state) {
    final studentName = state.currentUser?.name ?? '';
    final approved = state.approvedReportsForStudent(studentName);
    final titles = <String>{};
    for (final report in approved) {
      for (final rawLine in report.content.split('\n')) {
        final line = rawLine.trim();
        if (!line.startsWith('•')) continue;
        final withoutBullet = line.substring(1).trim();
        final title = withoutBullet.split(' — ').first.trim();
        if (title.isNotEmpty) titles.add(title.toLowerCase());
      }
    }
    return titles;
  }

  /// Renders the currently-checked completed tasks as a bullet list, e.g.
  /// "• Finished the report (General)" — this is what gets written into
  /// the Content / Accomplishments field.
  String _composeAccomplishments(List<Task> completed, Set<String> includedIds) {
    final chosen = completed.where((t) => includedIds.contains(t.id));
    return chosen.map((t) {
      final desc = t.description.trim();
      final suffix = desc.isEmpty || desc == t.title ? '' : ' — $desc';
      return '• ${t.title}$suffix';
    }).join('\n');
  }

  void _showSubmitDialog(BuildContext context, AppState state) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final List<ReportAttachment> attachments = [];

    final completedTasks = _completedTasksFor(state);
    final includedTaskIds = completedTasks.map((t) => t.id).toSet();
    if (completedTasks.isNotEmpty) {
      contentCtrl.text = _composeAccomplishments(completedTasks, includedTaskIds);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              14,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.slate200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppTheme.maroon50,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.note_add_rounded, color: AppTheme.maroon, size: 19),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Submit Report',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.slate100,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Report Title',
                      filled: true,
                      fillColor: AppTheme.slate50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.maroon, width: 1.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Content / Accomplishments',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: AppTheme.slate50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.maroon, width: 1.6),
                      ),
                    ),
                  ),
                  if (completedTasks.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 15, color: AppTheme.emerald500),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'COMPLETED TASKS — INCLUDED ABOVE',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.slate500,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...completedTasks.map((task) {
                            final checked = includedTaskIds.contains(task.id);
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  if (checked) {
                                    includedTaskIds.remove(task.id);
                                  } else {
                                    includedTaskIds.add(task.id);
                                  }
                                  contentCtrl.text =
                                      _composeAccomplishments(completedTasks, includedTaskIds);
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Icon(
                                      checked
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      size: 18,
                                      color: checked ? AppTheme.emerald500 : AppTheme.slate300,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        task.title,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: checked ? AppTheme.slate700 : AppTheme.slate400,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'ATTACHMENTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate400,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.slate200),
                      borderRadius: BorderRadius.circular(14),
                      color: AppTheme.slate50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (attachments.isEmpty)
                          Row(
                            children: const [
                              Icon(Icons.insert_drive_file_outlined, size: 15, color: AppTheme.slate400),
                              SizedBox(width: 8),
                              Text(
                                'No document attached yet',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate500,
                                ),
                              ),
                            ],
                          )
                        else
                          ...attachments.map(
                            (attachment) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.maroon50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.attach_file_rounded,
                                      size: 14,
                                      color: AppTheme.maroon,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      attachment.fileName,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.slate700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final result = await FilePicker.platform.pickFiles(
                                type: FileType.any,
                                allowMultiple: false,
                                withData: true,
                              );
                              if (result == null || result.files.isEmpty) return;

                              final file = result.files.single;
                              final bytes = file.bytes;
                              if (bytes == null) {
                                throw Exception(
                                  'This file type is not available for upload in the current browser session.',
                                );
                              }

                              final timestamp =
                                  DateTime.now().millisecondsSinceEpoch;
                              final sanitizedName = file.name.replaceAll(
                                RegExp(r'[^a-zA-Z0-9._-]'),
                                '_',
                              );
                              final storagePath =
                                  'reports/${fb_auth.FirebaseAuth.instance.currentUser?.uid ?? state.currentUser?.id ?? 'user'}/$timestamp/$sanitizedName';
                              final downloadUrl = await SupabaseStorageService
                                  .instance
                                  .uploadDocument(
                                    bytes: bytes,
                                    path: storagePath,
                                    contentType: file.extension == null
                                        ? null
                                        : _contentType(file.extension!),
                                  );

                              setState(() {
                                attachments.clear();
                                attachments.add(
                                  ReportAttachment(
                                    id: 'att_$timestamp',
                                    fileName: file.name,
                                    storagePath: storagePath,
                                    downloadUrl: downloadUrl,
                                    fileSize: file.size,
                                  ),
                                );
                              });

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Document uploaded: ${file.name}',
                                    ),
                                    backgroundColor: AppTheme.emerald500,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error uploading document: $e'),
                                    backgroundColor: AppTheme.red500,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.upload_file_rounded, size: 16),
                          label: const Text('Upload Document'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.maroon,
                            side: const BorderSide(color: AppTheme.maroon, width: 1.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.maroon.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          if (titleCtrl.text.trim().isEmpty) return;
                          final now = DateTime.now();
                          final report = Report(
                            id: 'r_${now.millisecondsSinceEpoch}',
                            applicantId: state.currentUser?.id,
                            title: titleCtrl.text.trim(),
                            content: contentCtrl.text.trim(),
                            studentName: state.currentUser?.name ?? '',
                            status: 'Pending',
                            submittedAt: '${now.month}/${now.day}/${now.year}',
                            attachments: attachments,
                            academicYear: state.academicYear,
                          );
                          final ok = await state.submitReport(report);
                          if (context.mounted) Navigator.pop(context);
                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Report submitted successfully!'),
                                backgroundColor: AppTheme.emerald500,
                                behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to submit report. Please try again.',
                                ),
                                backgroundColor: AppTheme.red500,
                                behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text(
                          'Submit Report',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _contentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  void _showReviewDialog(BuildContext context, AppState state, Report report) {
    final feedbackCtrl = TextEditingController(text: report.feedback ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            14,
            24,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.slate200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppTheme.maroon50,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.rate_review_rounded, color: AppTheme.maroon, size: 19),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Review Report',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.slate100,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppTheme.slate800,
                      ),
                    ),
                  ),
                  StatusBadge.fromStatus(report.status),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person_rounded, size: 13, color: AppTheme.slate400),
                  const SizedBox(width: 4),
                  Text(
                    'By ${report.studentName}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.slate50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.slate200),
                ),
                child: Text(
                  report.content,
                  style: const TextStyle(fontSize: 13, color: AppTheme.slate700, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: feedbackCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Feedback (optional)',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: AppTheme.slate50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.slate200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.slate200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.maroon, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await state.updateReportStatus(
                          report.id,
                          'Rejected',
                          feedback: feedbackCtrl.text.trim(),
                        );
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok ? 'Report rejected' : 'Failed to reject report',
                            ),
                            backgroundColor: ok ? AppTheme.red500 : AppTheme.red500,
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                        );
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.red500,
                        side: const BorderSide(color: AppTheme.red500, width: 1.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.emerald500.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final ok = await state.updateReportStatus(
                            report.id,
                            'Approved',
                            feedback: feedbackCtrl.text.trim(),
                          );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? 'Report approved' : 'Failed to approve report',
                              ),
                              backgroundColor: ok ? AppTheme.emerald500 : AppTheme.red500,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                          );
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald500,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final Report report;
  final String role;
  final VoidCallback? onReview;

  const _ReportCard({required this.report, required this.role, this.onReview});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _downloading = false;

  Report get report => widget.report;
  String get role => widget.role;
  VoidCallback? get onReview => widget.onReview;

  Color get _statusColor {
    switch (report.status) {
      case 'Approved':
        return AppTheme.emerald500;
      case 'Rejected':
        return AppTheme.red500;
      default:
        return AppTheme.amber500;
    }
  }

  IconData get _statusIcon {
    switch (report.status) {
      case 'Approved':
        return Icons.check_circle_rounded;
      case 'Rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _statusColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              color: _statusColor,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          report.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppTheme.slate900,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _statusColor.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_statusIcon, size: 12, color: _statusColor),
                            const SizedBox(width: 4),
                            Text(
                              report.status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_rounded,
                        size: 13,
                        color: AppTheme.slate400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        report.studentName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (report.submittedAt != null) ...[
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 12,
                          color: AppTheme.slate400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          report.submittedAt!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    report.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppTheme.slate500, height: 1.35),
                  ),
                  if (report.attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: report.attachments
                            .map(
                              (attachment) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: AppTheme.maroon50,
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: const Icon(
                                        Icons.attach_file_rounded,
                                        size: 13,
                                        color: AppTheme.maroon,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        attachment.fileName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.slate600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _downloading
                                          ? null
                                          : () async {
                                        setState(() => _downloading = true);
                                        try {
                                          final url =
                                              await SupabaseStorageService
                                                  .instance
                                                  .getDocumentUrl(
                                                    attachment.storagePath,
                                                  );
                                          final opened = await launchUrl(
                                            Uri.parse(url),
                                            mode: LaunchMode.externalApplication,
                                          );
                                          if (!opened && context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Unable to open document',
                                                ),
        backgroundColor: AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                                            );
                                          }
                                        } catch (error) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Unable to open document: $error',
                                                ),
        backgroundColor: AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _downloading = false);
                                          }
                                        }
                                      },
                                      icon: _downloading
                                          ? const SizedBox(
                                              width: 13,
                                              height: 13,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                      Colors.white,
                                                    ),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.download_outlined,
                                              size: 13,
                                            ),
                                      label: Text(
                                        _downloading
                                            ? 'Downloading...'
                                            : 'Download',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.emerald500,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: AppTheme.slate200,
                                        disabledForegroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                  if (report.feedback != null && report.feedback!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.gold50, AppTheme.gold50.withValues(alpha: 0.5)],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppTheme.gold100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Icon(
                              Icons.comment_rounded,
                              size: 13,
                              color: AppTheme.gold400,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              report.feedback!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.slate700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (onReview != null && report.status == 'Pending') ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onReview,
                        icon: const Icon(Icons.rate_review_rounded, size: 16),
                        label: const Text('Review'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}