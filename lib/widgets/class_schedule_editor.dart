import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/class_schedule.dart';
import '../models/recurring_schedule.dart';
import '../services/supabase_storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/file_names.dart';
import '../utils/schedule_reader/schedule_reader.dart';
import 'class_schedule_summary.dart';
import 'document_preview.dart';

/// Uploads a file to storage; tests pass their own.
typedef ScheduleUploader =
    Future<void> Function(Uint8List bytes, String path, String extension);

/// Reads a schedule file; tests pass their own.
typedef ScheduleFileReader =
    Future<ScheduleReadResult> Function(Uint8List bytes, String mimeType);

/// What the class schedule editor holds: the file (picked now, or kept from
/// before) and the class rows. The form that shows the editor sends these.
class ClassScheduleController extends ChangeNotifier {
  ClassScheduleController({
    List<ClassMeetingRow>? rows,
    this.fileName,
    this.filePath,
  }) : rows = rows ?? [];

  final List<ClassMeetingRow> rows;
  String? fileName;

  /// Where the file is in storage, once uploaded (or kept from before).
  String? filePath;
  Uint8List? fileBytes;
  bool uploading = false;
  bool reading = false;
  String? uploadError;

  /// What the reader made of the file, for the callout above the rows.
  String? readMessage;
  bool readFailed = false;

  /// Counts files picked, so a slow upload of an earlier one is dropped.
  int _pick = 0;

  /// Counts reads, so a stopped or earlier one is dropped (separately from
  /// [_pick]: stopping a read must not drop the file's upload).
  int _readToken = 0;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get busy => uploading || reading;
  bool get hasFile => (filePath ?? '').isNotEmpty;

  /// Problems that stop the schedule being sent; empty when it can be.
  List<String> problems({bool requireFile = true}) => [
    if (requireFile && !hasFile)
      uploadError != null
          ? 'Your schedule file did not upload. Choose it again.'
          : 'Choose your class schedule file.',
    ...classScheduleProblems(rows),
  ];

  /// The rows as subject rules.
  List<RecurringScheduleRule> subjects({
    required String ownerName,
    required String? academicYear,
  }) => classSubjectRules(
    rows: rows,
    ownerName: ownerName,
    academicYear: academicYear,
    idPrefix: 'subj_${DateTime.now().millisecondsSinceEpoch}',
  );

  /// Tells the editor and the form; a no-op once the form is closed (an
  /// upload or read may finish after that).
  void changed() {
    if (!_disposed) notifyListeners();
  }
}

/// Picks a class schedule file, reads it on this device and shows the
/// classes found as rows the student checks and fixes. Without a reader
/// (the Android app) or when reading fails, the rows are typed in.
class ClassScheduleEditor extends StatefulWidget {
  final ClassScheduleController controller;

  /// The account the file is stored under (`schedules/<ownerId>/...`).
  final String ownerId;
  final bool enabled;

  /// Whether a file is needed at all (the Head editing subjects keeps the
  /// file there is).
  final bool withFile;

  /// When true (student uploads), the file must scan into valid, complete
  /// classes before it is uploaded, and the scanned classes are shown
  /// read-only (no adding, editing, or removing rows). Where nothing can
  /// read the file (the Android app) the student types the classes instead,
  /// and the Head checks them against the file.
  final bool readOnly;

  @visibleForTesting
  final ScheduleUploader? uploader;
  @visibleForTesting
  final ScheduleFileReader? reader;

  /// Picks the file; tests pass their own.
  @visibleForTesting
  final Future<PlatformFile?> Function()? picker;

  const ClassScheduleEditor({
    super.key,
    required this.controller,
    required this.ownerId,
    this.enabled = true,
    this.withFile = true,
    this.readOnly = false,
    this.uploader,
    this.reader,
    this.picker,
  });

  /// Whether a schedule file can be read on this device (with [reader] for
  /// tests): the web app reads it, the Android app can't.
  static bool canScan([ScheduleFileReader? reader]) =>
      reader != null || ScheduleReader.isSupported;

  @override
  State<ClassScheduleEditor> createState() => _ClassScheduleEditorState();
}

class _ClassScheduleEditorState extends State<ClassScheduleEditor> {
  ClassScheduleController get c => widget.controller;

  /// Read-only only where the file can be read: otherwise the classes are
  /// typed (see [ClassScheduleEditor.readOnly]).
  bool get _locked =>
      widget.readOnly && ClassScheduleEditor.canScan(widget.reader);

  @override
  void initState() {
    super.initState();
    c.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(ClassScheduleEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    c.removeListener(_rebuild);
    if (c.reading) ScheduleReader.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  static String _mimeFor(String extension) => switch (extension) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    _ => 'image/jpeg',
  };

  Future<PlatformFile?> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
      return result == null || result.files.isEmpty
          ? null
          : result.files.single;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickFile() async {
    final file = await (widget.picker ?? _pick)();
    if (file == null) return;
    final bytes = file.bytes;
    final extension = (file.extension ?? '').toLowerCase();
    if (bytes == null || bytes.isEmpty) {
      c.uploadError = 'This file could not be opened. Choose it again.';
      c.changed();
      return;
    }
    if (bytes.length > SupabaseStorageService.maxUploadBytes) {
      c.uploadError = 'The file must be 10 MB or smaller.';
      c.changed();
      return;
    }
    if (!const ['jpg', 'jpeg', 'png', 'pdf'].contains(extension)) {
      c.uploadError = 'Choose a JPG, PNG or PDF file.';
      c.changed();
      return;
    }
    if (_locked) {
      // The file in use (and its upload) stays until a new one scans well.
      final token = ++c._readToken;
      await _scanThenUpload(token, bytes, file.name, extension);
      return;
    }
    final pick = ++c._pick;
    c
      ..fileName = file.name
      ..fileBytes = bytes
      ..filePath = null
      ..uploadError = null;
    c.changed();
    await Future.wait([
      _upload(pick, bytes, file.name, extension),
      _read(bytes, extension),
    ]);
  }

  /// Read-only mode: scans the file first, and only a file that scans into
  /// a complete schedule replaces the one in use (then uploads). A file that
  /// fails leaves the previous file and classes as they were.
  Future<void> _scanThenUpload(
    int token,
    Uint8List bytes,
    String name,
    String extension,
  ) async {
    final read =
        widget.reader ??
        (ScheduleReader.isSupported ? ScheduleReader.read : null);
    if (read == null) {
      c
        ..fileName = null
        ..filePath = null
        ..fileBytes = null
        ..rows.clear()
        ..reading = false
        ..readFailed = true
        ..readMessage = 'Scanning a class schedule requires the web app.';
      c.changed();
      return;
    }
    c
      ..reading = true
      ..uploadError = null
      ..readMessage = null
      ..readFailed = false;
    c.changed();
    final int pick;
    try {
      final result = await read(bytes, _mimeFor(extension));
      if (token != c._readToken) return;
      final found = [
        for (final m in result.meetings) ClassMeetingRow.fromMeeting(m),
      ];
      final isValid =
          result.ok &&
          found.isNotEmpty &&
          result.warnings.isEmpty &&
          classScheduleProblems(found).isEmpty;
      if (!isValid) {
        c
          ..reading = false
          ..readFailed = true
          ..readMessage =
              "This file was not accepted because it doesn't look like a "
              'clear, readable class schedule. Upload a screenshot or PDF of '
              'your class schedule.${c.fileName != null ? ' Your previous '
                        'schedule is kept.' : ''}';
        c.changed();
        return;
      }
      // This file takes over: an earlier file's upload still running is
      // dropped from here on.
      pick = ++c._pick;
      c.rows
        ..clear()
        ..addAll(found);
      c
        ..fileName = name
        ..fileBytes = bytes
        ..filePath = null
        ..uploadError = null
        ..reading = false
        ..readFailed = false
        ..readMessage =
            'Scanned ${found.length} ${found.length == 1 ? 'class' : 'classes'} '
            'from your schedule.';
      c.changed();
    } catch (error) {
      if (token != c._readToken) return;
      c
        ..reading = false
        ..readFailed = true
        ..readMessage =
            '$error${c.fileName != null ? ' Your previous schedule is kept.' : ''}';
      c.changed();
      return;
    }
    await _upload(pick, bytes, name, extension);
  }

  Future<void> _upload(
    int pick,
    Uint8List bytes,
    String name,
    String extension,
  ) async {
    final path =
        'schedules/${widget.ownerId}/${DateTime.now().millisecondsSinceEpoch}/'
        '${randomObjectName(name)}';
    c.uploading = true;
    c.changed();
    try {
      final upload =
          widget.uploader ??
          (Uint8List b, String p, String ext) =>
              SupabaseStorageService.instance.uploadDocument(
                bytes: b,
                path: p,
                contentType: SupabaseStorageService.contentTypeForExtension(
                  ext,
                ),
              );
      await upload(bytes, path, extension);
      if (pick != c._pick) return;
      c.filePath = path;
    } catch (error) {
      if (pick != c._pick) return;
      c.uploadError = 'The file did not upload: $error';
    } finally {
      if (pick == c._pick) {
        c.uploading = false;
        c.changed();
      }
    }
  }

  Future<void> _read(Uint8List bytes, String extension) async {
    final token = ++c._readToken;
    final read =
        widget.reader ??
        (ScheduleReader.isSupported ? ScheduleReader.read : null);
    if (read == null) {
      c.readFailed = true;
      c.readMessage =
          'Type your classes below, the same as on your schedule. (Reading '
          'the file for you works in the web app.)';
      if (c.rows.isEmpty) c.rows.add(ClassMeetingRow());
      c.changed();
      return;
    }
    c
      ..reading = true
      ..readMessage = null
      ..readFailed = false;
    c.changed();
    try {
      final result = await read(bytes, _mimeFor(extension));
      if (token != c._readToken) return;
      final found = [
        for (final m in result.meetings) ClassMeetingRow.fromMeeting(m),
      ];
      c.rows
        ..clear()
        ..addAll(found);
      if (found.isEmpty) {
        c.readFailed = true;
        c.readMessage =
            "We couldn't find the classes in this file. Please type them "
            'below, the same as on your schedule.';
        c.rows.add(ClassMeetingRow());
      } else {
        final unsure = found.where((r) => r.check).length;
        c.readFailed = false;
        c.readMessage =
            'We read ${found.length} ${found.length == 1 ? 'class' : 'classes'} '
            'from your file. Check every row against your schedule'
            '${unsure > 0 ? ': $unsure marked "Check" may be wrong' : ''}. '
            'Add the units, and fix anything that differs.';
      }
    } catch (error) {
      if (token != c._readToken) return;
      c.readFailed = true;
      c.readMessage = '$error';
      if (c.rows.isEmpty) c.rows.add(ClassMeetingRow());
    } finally {
      if (token == c._readToken) {
        c.reading = false;
        c.changed();
      }
    }
  }

  void _cancelRead() {
    ScheduleReader.cancel();
    c._readToken++;
    if (_locked) {
      // The file in use (if any) stays, its upload included.
      c
        ..reading = false
        ..readFailed = true
        ..readMessage =
            'Scanning cancelled. Choose your class schedule file to try again.';
      c.changed();
      return;
    }
    // Drops the read only; the file's upload carries on.
    c
      ..reading = false
      ..readFailed = true
      ..readMessage = 'Reading stopped. Type your classes below.';
    if (c.rows.isEmpty) c.rows.add(ClassMeetingRow());
    c.changed();
  }

  /// Reads the same file again (its rows are replaced).
  void _readAgain() {
    final bytes = c.fileBytes;
    final name = c.fileName;
    if (bytes == null || name == null) return;
    final dot = name.lastIndexOf('.');
    _read(bytes, dot < 0 ? 'jpg' : name.substring(dot + 1).toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.withFile) ...[_fileRow(enabled), const SizedBox(height: 10)],
        if (c.reading) _readingBox() else if (c.readMessage != null) _callout(),
        if (_locked) ...[
          if (c.rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: ClassScheduleSummary(
                subjects: c.subjects(ownerName: '', academicYear: null),
              ),
            ),
          ],
        ] else if (c.rows.isNotEmpty || !widget.withFile) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < c.rows.length; i++)
            _MeetingRowCard(
              key: ObjectKey(c.rows[i]),
              row: c.rows[i],
              index: i,
              enabled: enabled && !c.reading,
              onChanged: c.changed,
              onDelete: () {
                c.rows.removeAt(i);
                c.changed();
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: enabled && !c.reading
                  ? () {
                      c.rows.add(ClassMeetingRow());
                      c.changed();
                    }
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add a class'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.maroon),
            ),
          ),
        ],
      ],
    );
  }

  Widget _fileRow(bool enabled) {
    final name = c.fileName;
    if (name == null) {
      final choose = OutlinedButton.icon(
        // Not while a first file is still being read and uploaded.
        onPressed: enabled && !c.busy ? _pickFile : null,
        icon: const Icon(Icons.upload_file_outlined, size: 18),
        label: const Text('Choose your class schedule (JPG, PNG or PDF)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.maroon,
          side: const BorderSide(color: AppTheme.slate200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      final error = c.uploadError;
      // A file refused before anything was read (too big, wrong type).
      if (error == null) return choose;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          choose,
          const SizedBox(height: 6),
          Text(
            error,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.red500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    final status = c.uploading
        ? 'Uploading...'
        : c.uploadError != null
        ? c.uploadError!
        : c.hasFile
        ? 'Uploaded'
        : '';
    final statusColor = c.uploadError != null
        ? AppTheme.red500
        : c.hasFile
        ? AppTheme.emerald500
        : AppTheme.slate500;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 20,
            color: AppTheme.maroon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate800,
                  ),
                ),
                if (status.isNotEmpty)
                  Text(
                    status,
                    style: TextStyle(fontSize: 11, color: statusColor),
                  ),
              ],
            ),
          ),
          if (c.uploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (c.fileBytes != null || c.hasFile)
            TextButton(
              onPressed: () => showDocumentPreview(
                context,
                fileName: name,
                bytes: c.fileBytes,
                storagePath: c.filePath,
              ),
              child: const Text('View'),
            ),
          if (c.fileBytes != null &&
              !c.reading &&
              !_locked &&
              ClassScheduleEditor.canScan(widget.reader))
            TextButton(
              onPressed: enabled ? _readAgain : null,
              child: const Text('Read again'),
            ),
          TextButton(
            onPressed: enabled && !c.busy ? _pickFile : null,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _readingBox() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.slate50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.slate200),
    ),
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Reading your schedule on this device... The first time, the '
            'reader downloads about 7 MB.',
            style: TextStyle(fontSize: 12, color: AppTheme.slate600),
          ),
        ),
        TextButton(onPressed: _cancelRead, child: const Text('Stop')),
      ],
    ),
  );

  Widget _callout() {
    final bad = c.readFailed;
    final rejected = bad && _locked;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rejected
            ? AppTheme.red50
            : bad
            ? AppTheme.amber50
            : AppTheme.blue50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (rejected
                  ? AppTheme.red500
                  : bad
                  ? AppTheme.amber500
                  : AppTheme.blue500)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            rejected
                ? Icons.error_outline_rounded
                : bad
                ? Icons.edit_note_outlined
                : Icons.fact_check_outlined,
            size: 18,
            color: rejected
                ? AppTheme.red500
                : bad
                ? _amberText
                : AppTheme.blue500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              c.readMessage!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.slate700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark amber, readable on the light amber of a row to check.
const _amberText = Color(0xFFB45309);

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// One class: subject, day, times, mode, units and room, editable.
class _MeetingRowCard extends StatefulWidget {
  final ClassMeetingRow row;
  final int index;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _MeetingRowCard({
    super.key,
    required this.row,
    required this.index,
    required this.enabled,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_MeetingRowCard> createState() => _MeetingRowCardState();
}

class _MeetingRowCardState extends State<_MeetingRowCard> {
  late final _title = TextEditingController(text: widget.row.title);
  late final _units = TextEditingController(text: widget.row.units);
  late final _room = TextEditingController(text: widget.row.room);

  ClassMeetingRow get row => widget.row;

  @override
  void dispose() {
    _title.dispose();
    _units.dispose();
    _room.dispose();
    super.dispose();
  }

  void _edited() {
    // A row the student has touched is theirs now.
    row.check = false;
    widget.onChanged();
  }

  Future<void> _pickTime(bool start) async {
    final initial =
        (start ? row.start : row.end) ??
        (start
            ? const TimeOfDay(hour: 8, minute: 0)
            : TimeOfDay(
                hour: ((row.start?.hour ?? 8) + 1) % 24,
                minute: row.start?.minute ?? 0,
              ));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (start) {
        row.start = picked;
      } else {
        row.end = picked;
      }
    });
    _edited();
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppTheme.slate200),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppTheme.slate200),
    ),
  );

  Widget _timeButton(String label, TimeOfDay? value, bool start) {
    return OutlinedButton(
      onPressed: widget.enabled ? () => _pickTime(start) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: value == null ? AppTheme.slate500 : AppTheme.slate800,
        side: BorderSide(
          color: value == null ? AppTheme.amber500 : AppTheme.slate200,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        value == null
            ? label
            : '$label ${RecurringScheduleRule.formatTime(value)}',
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = row.problem;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(
        color: row.check ? AppTheme.amber50 : AppTheme.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: row.check ? AppTheme.amber500 : AppTheme.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Class ${widget.index + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                  letterSpacing: 0.4,
                ),
              ),
              if (row.check) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.amber500.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Check',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _amberText,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Remove this class',
                visualDensity: VisualDensity.compact,
                onPressed: widget.enabled ? widget.onDelete : null,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppTheme.slate500,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextField(
              controller: _title,
              enabled: widget.enabled,
              style: const TextStyle(fontSize: 13),
              decoration: _decoration('Subject'),
              onChanged: (v) {
                row.title = v;
                _edited();
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<int>(
                    initialValue: row.weekday,
                    isExpanded: true,
                    decoration: _decoration('Day'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.slate800,
                      fontFamily: 'Inter',
                    ),
                    items: [
                      for (var d = 1; d <= 6; d++)
                        DropdownMenuItem(
                          value: d,
                          child: Text(_dayNames[d - 1]),
                        ),
                    ],
                    onChanged: widget.enabled
                        ? (v) {
                            row.weekday = v;
                            _edited();
                          }
                        : null,
                  ),
                ),
                _timeButton('Starts', row.start, true),
                _timeButton('Ends', row.end, false),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: row.mode,
                    isExpanded: true,
                    decoration: _decoration('Mode'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.slate800,
                      fontFamily: 'Inter',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Face-to-Face',
                        child: Text('Face-to-Face'),
                      ),
                      DropdownMenuItem(value: 'Online', child: Text('Online')),
                    ],
                    onChanged: widget.enabled
                        ? (v) {
                            row.mode = v ?? 'Face-to-Face';
                            _edited();
                          }
                        : null,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _units,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: _decoration('Units'),
                    onChanged: (v) {
                      row.units = v;
                      widget.onChanged();
                    },
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _room,
                    enabled: widget.enabled,
                    style: const TextStyle(fontSize: 13),
                    decoration: _decoration('Room'),
                    onChanged: (v) {
                      row.room = v;
                      widget.onChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (row.instructor.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Instructor: ${row.instructor}',
              style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          ],
          if (problem != null &&
              (row.title.isNotEmpty || row.weekday != null)) ...[
            const SizedBox(height: 6),
            Text(
              problem,
              style: const TextStyle(fontSize: 11, color: AppTheme.red500),
            ),
          ],
        ],
      ),
    );
  }
}
