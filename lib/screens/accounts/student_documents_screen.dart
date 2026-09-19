import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';

/// Head-only screen that consolidates every document tied to a student
/// assistant in one place: files submitted with their application
/// (resume/requirements, generated Contract of Appointment, generated
/// Endorsement Letter) plus everything supervisors have forwarded (reports,
/// performance evaluations, DTR/Accomplishment reports). Grouped by student
/// with type + search filters.
class StudentDocumentsScreen extends StatefulWidget {
  const StudentDocumentsScreen({super.key});

  @override
  State<StudentDocumentsScreen> createState() => _StudentDocumentsScreenState();
}

enum _DocKind { requirement, contract, endorsement, report, evaluation, dtrReport, uploaded }

class _DocEntry {
  final String studentKey;
  final String studentName;
  final String campus;
  final String department;
  final String office;
  final _DocKind kind;
  final String title;
  final String subtitle;
  final String? downloadUrl;
  final String? storagePath;
  final bool? reviewed;
  final DateTime sortDate;
  final String? documentId;

  _DocEntry({
    required this.studentKey,
    required this.studentName,
    required this.campus,
    required this.department,
    required this.office,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.sortDate,
    this.downloadUrl,
    this.storagePath,
    this.reviewed,
    this.documentId,
  });
}

const String _unassignedLabel = 'Unassigned';

/// Looks up a student's campus/department/office by matching the various
/// id/name fields that Applications and HeadForwards carry against the
/// Students and Offices lists (the same join logic students_screen uses).
({String campus, String department, String office}) _studentMeta(
  AppState state,
  String studentKey,
  String studentName,
) {
  Student? student;
  for (final s in state.students) {
    if (s.id == studentKey || s.userId == studentKey || s.name.trim().toLowerCase() == studentName.trim().toLowerCase()) {
      student = s;
      break;
    }
  }

  String office = _unassignedLabel;
  for (final o in state.offices) {
    final matches = o.assistantIds.contains(studentKey) ||
        (student != null && o.assistantIds.contains(student.id)) ||
        (student?.userId != null && o.assistantIds.contains(student!.userId)) ||
        o.assistantNames.any((n) => n.trim().toLowerCase() == studentName.trim().toLowerCase());
    if (matches) {
      office = o.name;
      break;
    }
  }

  return (
    campus: student?.campus?.trim().isNotEmpty == true ? student!.campus!.trim() : _unassignedLabel,
    department: student?.department.trim().isNotEmpty == true ? student!.department.trim() : _unassignedLabel,
    office: office,
  );
}

const Map<_DocKind, String> _kindLabels = {
  _DocKind.requirement: 'Requirement',
  _DocKind.contract: 'Contract of Appointment',
  _DocKind.endorsement: 'Endorsement Letter',
  _DocKind.report: 'Report',
  _DocKind.evaluation: 'Performance Evaluation',
  _DocKind.dtrReport: 'DTR/Accomplishment Report',
  _DocKind.uploaded: 'Uploaded File',
};

const Map<_DocKind, IconData> _kindIcons = {
  _DocKind.requirement: Icons.folder_copy_outlined,
  _DocKind.contract: Icons.assignment_turned_in_outlined,
  _DocKind.endorsement: Icons.mail_outline_rounded,
  _DocKind.report: Icons.description_outlined,
  _DocKind.evaluation: Icons.fact_check_outlined,
  _DocKind.dtrReport: Icons.event_note_outlined,
  _DocKind.uploaded: Icons.upload_file_rounded,
};

const Map<_DocKind, Color> _kindColors = {
  _DocKind.requirement: AppTheme.slate500,
  _DocKind.contract: AppTheme.maroon,
  _DocKind.endorsement: AppTheme.amber500,
  _DocKind.report: AppTheme.blue500,
  _DocKind.evaluation: AppTheme.blue500,
  _DocKind.dtrReport: AppTheme.emerald500,
  _DocKind.uploaded: AppTheme.slate700,
};

class _StudentDocumentsScreenState extends State<StudentDocumentsScreen> {
  // null = All
  _DocKind? _kindFilter;
  String _campusFilter = 'All Campuses';
  String _departmentFilter = 'All Departments';
  String _officeFilter = 'All Offices';
  final _searchCtrl = TextEditingController();
  String? _downloadingId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_DocEntry> _collectEntries(AppState state) {
    final entries = <_DocEntry>[];

    for (final app in state.applications) {
      if (app.status == 'Rejected') continue;
      final key = app.applicantId.isNotEmpty ? app.applicantId : app.applicantName;
      final meta = _studentMeta(state, key, app.applicantName);
      for (final doc in app.submittedDocuments) {
        final fileName = doc.fileName.toLowerCase();
        final kind = fileName.contains('contract-of-appointment')
            ? _DocKind.contract
            : fileName.contains('endorsement-letter')
                ? _DocKind.endorsement
                : _DocKind.requirement;
        entries.add(
          _DocEntry(
            studentKey: key,
            studentName: app.applicantName,
            campus: meta.campus,
            department: meta.department,
            office: meta.office,
            kind: kind,
            title: doc.fileName,
            subtitle: doc.requirementName.isNotEmpty
                ? doc.requirementName
                : 'Uploaded ${doc.uploadedAt}',
            sortDate: DateTime.tryParse(doc.uploadedAt) ?? DateTime(2000),
            downloadUrl: doc.downloadUrl,
            storagePath: doc.storagePath,
          ),
        );
      }
    }

    for (final fwd in state.headForwards) {
      final kind = fwd.type == 'evaluation'
          ? _DocKind.evaluation
          : fwd.type == 'dtr_report'
              ? _DocKind.dtrReport
              : _DocKind.report;
      final key = fwd.studentId.isNotEmpty ? fwd.studentId : fwd.studentName;
      final meta = _studentMeta(state, key, fwd.studentName);
      entries.add(
        _DocEntry(
          studentKey: key,
          studentName: fwd.studentName,
          campus: meta.campus,
          department: meta.department,
          office: meta.office,
          kind: kind,
          title: fwd.title,
          subtitle: 'From ${fwd.sentByName} · ${fwd.sentAt}',
          sortDate: DateTime.tryParse(fwd.sentAt) ?? DateTime(2000),
          downloadUrl: fwd.downloadUrl,
          reviewed: fwd.reviewed,
        ),
      );
    }

    for (final doc in state.documents) {
      if (doc.folderId != null || doc.studentId == null || doc.studentId!.isEmpty) continue;
      final key = doc.studentId!;
      final name = doc.studentName ?? '';
      final meta = _studentMeta(state, key, name);
      entries.add(
        _DocEntry(
          studentKey: key,
          studentName: name,
          campus: meta.campus,
          department: meta.department,
          office: meta.office,
          kind: _DocKind.uploaded,
          title: doc.fileName,
          subtitle: 'Uploaded by ${doc.uploadedBy.isEmpty ? 'Head' : doc.uploadedBy}',
          sortDate: DateTime.tryParse(doc.uploadedAt) ?? DateTime(2000),
          downloadUrl: doc.downloadUrl,
          storagePath: doc.filePath,
          documentId: doc.id,
        ),
      );
    }

    entries.sort((a, b) => b.sortDate.compareTo(a.sortDate));
    return entries;
  }

  Future<void> _uploadForStudent(AppState state, String studentKey, String studentName) async {
    final messenger = ScaffoldMessenger.of(context);
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
        throw Exception('This file type is not available for upload in the current browser session.');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid ?? state.currentUser?.id ?? 'user';
      final storagePath = 'reports/$uid/$timestamp/$sanitizedName';
      final extension = file.extension?.toLowerCase();
      final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
        bytes: bytes,
        path: storagePath,
        contentType: extension == null ? null : SupabaseStorageService.contentTypeForExtension(extension),
      );

      await state.uploadManualDocument(
        studentId: studentKey,
        studentName: studentName,
        fileName: file.name,
        storagePath: storagePath,
        downloadUrl: downloadUrl,
        fileSize: file.size / (1024 * 1024),
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Uploaded ${file.name}'),
            backgroundColor: AppTheme.emerald500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _deleteUpload(AppState state, _DocEntry entry) async {
    if (entry.documentId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete "${entry.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red500),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.deleteManualDocument(entry.documentId!);
    }
  }

  Future<void> _download(_DocEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloadingId = '${entry.studentKey}-${entry.title}-${entry.sortDate}');
    try {
      String? url = entry.downloadUrl;
      if ((url == null || url.isEmpty) && entry.storagePath != null && entry.storagePath!.isNotEmpty) {
        url = await SupabaseStorageService.instance.getDocumentUrl(entry.storagePath!);
      }
      if (url == null || url.isEmpty) {
        throw Exception('This document has no file content or storage path.');
      }
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('The browser could not open the document.');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Unable to download: $e'),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = _searchCtrl.text.trim().toLowerCase();

    final allEntries = _collectEntries(state);

    final campusOptions = [
      'All Campuses',
      ...allEntries.map((e) => e.campus).toSet().toList()..sort(),
    ];
    final departmentOptions = [
      'All Departments',
      ...allEntries.map((e) => e.department).toSet().toList()..sort(),
    ];
    final officeOptions = [
      'All Offices',
      ...allEntries.map((e) => e.office).toSet().toList()..sort(),
    ];

    final filtered = allEntries.where((e) {
      if (_kindFilter != null && e.kind != _kindFilter) return false;
      if (_campusFilter != 'All Campuses' && e.campus != _campusFilter) return false;
      if (_departmentFilter != 'All Departments' && e.department != _departmentFilter) return false;
      if (_officeFilter != 'All Offices' && e.office != _officeFilter) return false;
      if (query.isNotEmpty && !e.studentName.toLowerCase().contains(query)) return false;
      return true;
    }).toList();

    final byStudent = <String, List<_DocEntry>>{};
    final studentDisplayName = <String, String>{};
    for (final e in filtered) {
      byStudent.putIfAbsent(e.studentKey, () => []).add(e);
      studentDisplayName[e.studentKey] = e.studentName;
    }
    final studentKeys = byStudent.keys.toList()
      ..sort((a, b) => studentDisplayName[a]!.compareTo(studentDisplayName[b]!));

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 420;
    final horizontalPadding = isCompact ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(color: AppTheme.maroon, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Student Documents',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.slate900, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${allEntries.length} document${allEntries.length == 1 ? '' : 's'} across ${byStudent.length} student${byStudent.length == 1 ? '' : 's'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.slate400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by student name...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.slate400),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _searchCtrl.clear()),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
        ),
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [null, ..._kindLabels.keys].map((k) {
                final selected = _kindFilter == k;
                final label = k == null ? 'All' : _kindLabels[k]!;
                final icon = k == null ? Icons.apps_rounded : _kindIcons[k]!;
                return GestureDetector(
                  onTap: () => setState(() => _kindFilter = k),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: selected ? AppTheme.maroon : AppTheme.slate200),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: AppTheme.maroon.withValues(alpha: 0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: selected ? Colors.white : AppTheme.slate400),
                        const SizedBox(width: 6),
                        Text(
                          label,
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
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FilterDropdown(
                value: _campusFilter,
                options: campusOptions,
                icon: Icons.location_city_outlined,
                onChanged: (v) => setState(() => _campusFilter = v),
              ),
              _FilterDropdown(
                value: _departmentFilter,
                options: departmentOptions,
                icon: Icons.business_outlined,
                onChanged: (v) => setState(() => _departmentFilter = v),
              ),
              _FilterDropdown(
                value: _officeFilter,
                options: officeOptions,
                icon: Icons.account_balance_outlined,
                onChanged: (v) => setState(() => _officeFilter = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (filtered.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(color: AppTheme.slate100, shape: BoxShape.circle),
                            child: Icon(
                              allEntries.isEmpty ? Icons.folder_off_outlined : Icons.search_off_rounded,
                              size: 36,
                              color: AppTheme.slate300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            allEntries.isEmpty ? 'No documents yet' : 'No matches found',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate400),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            allEntries.isEmpty
                                ? 'Application requirements, contracts, endorsement\n'
                                    'letters, reports, evaluations, and DTR files will\n'
                                    'appear here, per student.'
                                : 'Try a different search term or filter.',
                            style: const TextStyle(fontSize: 13, color: AppTheme.slate500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final key in studentKeys)
                    _StudentDocGroup(
                      studentKey: key,
                      studentName: studentDisplayName[key]!,
                      items: byStudent[key]!,
                      downloadingId: _downloadingId,
                      onDownload: _download,
                      onUpload: () => _uploadForStudent(state, key, studentDisplayName[key]!),
                      onDelete: (entry) => _deleteUpload(state, entry),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.options,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = options.isNotEmpty && value != options.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? AppTheme.maroon : AppTheme.slate200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppTheme.slate400),
          isDense: true,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isActive ? AppTheme.maroon : AppTheme.slate600,
          ),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _StudentDocGroup extends StatefulWidget {
  final String studentKey;
  final String studentName;
  final List<_DocEntry> items;
  final String? downloadingId;
  final void Function(_DocEntry) onDownload;
  final VoidCallback onUpload;
  final void Function(_DocEntry) onDelete;

  const _StudentDocGroup({
    required this.studentKey,
    required this.studentName,
    required this.items,
    required this.downloadingId,
    required this.onDownload,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  State<_StudentDocGroup> createState() => _StudentDocGroupState();
}

class _StudentDocGroupState extends State<_StudentDocGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.maroon, AppTheme.maroon.withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.studentName.trim().isNotEmpty ? widget.studentName.trim()[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.studentName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${widget.items.length} item${widget.items.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.slate400, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Upload a file for this student',
                    onPressed: widget.onUpload,
                    icon: const Icon(Icons.upload_file_rounded, size: 17, color: AppTheme.maroon),
                    splashRadius: 18,
                  ),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppTheme.slate400,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: widget.items
                    .map((e) => _DocTile(
                          entry: e,
                          downloading: widget.downloadingId == '${e.studentKey}-${e.title}-${e.sortDate}',
                          onDownload: () => widget.onDownload(e),
                          onDelete: e.documentId != null ? () => widget.onDelete(e) : null,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final _DocEntry entry;
  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;

  const _DocTile({required this.entry, required this.downloading, required this.onDownload, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final accent = _kindColors[entry.kind]!;
    final hasFile = (entry.downloadUrl != null && entry.downloadUrl!.isNotEmpty) ||
        (entry.storagePath != null && entry.storagePath!.isNotEmpty);

    // A BoxDecoration can't combine borderRadius with a Border whose sides
    // have different colors/widths (Flutter throws "A borderRadius can only
    // be given on borders with uniform colors" and fails to paint the whole
    // decoration+child) — so the accent left edge is a Positioned overlay
    // in a Stack instead of part of this Container's border. (Deliberately
    // not a stretched Row sibling either, to keep this tile's height
    // resolution simple and unambiguous regardless of the parent's
    // constraints.)
    return Container(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_kindIcons[entry.kind], size: 15, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _kindLabels[entry.kind]!,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.3),
                            ),
                          ),
                          if (entry.reviewed == false)
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(color: AppTheme.red500, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.slate800),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.subtitle,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (hasFile)
                            ElevatedButton.icon(
                              onPressed: downloading ? null : onDownload,
                              icon: downloading
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.download_rounded, size: 13),
                              label: Text(downloading ? 'Opening...' : 'Download'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.emerald500,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          if (onDelete != null)
                            OutlinedButton.icon(
                              onPressed: onDelete,
                              icon: const Icon(Icons.delete_outline_rounded, size: 13),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.red500,
                                side: const BorderSide(color: AppTheme.red500),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: Container(color: accent),
          ),
        ],
      ),
    );
  }
}
