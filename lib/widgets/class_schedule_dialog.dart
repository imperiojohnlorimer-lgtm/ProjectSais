import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/class_schedule.dart';
import '../models/recurring_schedule.dart';
import '../theme/app_theme.dart';
import 'class_schedule_editor.dart';
import 'shared_widgets.dart';

/// Who is changing the schedule: a Student Assistant sending a new file to
/// the Head, or the Head changing the classes directly.
enum ClassScheduleDialogMode { request, head }

/// Opens the class schedule form. Resolves to true once sent or saved.
Future<bool?> showClassScheduleDialog(
  BuildContext context, {
  required String ownerId,
  required String ownerName,
  required ClassScheduleDialogMode mode,
  List<RecurringScheduleRule> current = const [],
  DateTime? earliest,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ClassScheduleDialog(
      ownerId: ownerId,
      ownerName: ownerName,
      mode: mode,
      current: current,
      earliest: earliest,
    ),
  );
}

class ClassScheduleDialog extends StatefulWidget {
  final String ownerId;
  final String ownerName;
  final ClassScheduleDialogMode mode;

  /// The classes now, filled in for the Head to change.
  final List<RecurringScheduleRule> current;

  /// The first day the new schedule may start (the current one's start).
  final DateTime? earliest;

  const ClassScheduleDialog({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.mode,
    this.current = const [],
    this.earliest,
  });

  @override
  State<ClassScheduleDialog> createState() => _ClassScheduleDialogState();
}

class _ClassScheduleDialogState extends State<ClassScheduleDialog> {
  late final ClassScheduleController _controller = ClassScheduleController(
    rows: widget.mode == ClassScheduleDialogMode.head
        ? [for (final r in widget.current) ClassMeetingRow.fromRule(r)]
        : null,
  );
  final _note = TextEditingController();
  late DateTime _startsOn;
  bool _saving = false;
  List<String> _problems = const [];

  bool get _isRequest => widget.mode == ClassScheduleDialogMode.request;

  @override
  void initState() {
    super.initState();
    final today = context.read<AppState>().philippineClock();
    _startsOn = DateTime(today.year, today.month, today.day);
    final earliest = widget.earliest;
    if (earliest != null && earliest.isAfter(_startsOn)) _startsOn = earliest;
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Problems shown after a try clear as they are fixed.
    if (_problems.isNotEmpty) {
      setState(() => _problems = _controller.problems(requireFile: _isRequest));
    }
  }

  DateTime get _firstDay {
    final today = context.read<AppState>().philippineClock();
    final earliest = widget.earliest;
    final monthAgo = DateTime(today.year, today.month - 1, today.day);
    if (earliest == null) return monthAgo;
    return earliest.isAfter(monthAgo) ? earliest : monthAgo;
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn,
      firstDate: _firstDay,
      lastDate: context.read<AppState>().philippineClock().add(
        const Duration(days: 200),
      ),
      helpText: 'The first day of this schedule',
    );
    if (picked != null) setState(() => _startsOn = picked);
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    if (_controller.busy) {
      setState(
        () =>
            _problems = ['Wait for the file to finish uploading and reading.'],
      );
      return;
    }
    final problems = _controller.problems(requireFile: _isRequest);
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    setState(() {
      _saving = true;
      _problems = const [];
    });
    final subjects = _controller.subjects(
      ownerName: widget.ownerName,
      academicYear: state.academicYear,
    );
    final startsOn = ClassScheduleVersion.dayKey(_startsOn);
    final problem = _isRequest
        ? await state.submitScheduleRequest(
            fileName: _controller.fileName ?? 'schedule',
            filePath: _controller.filePath!,
            subjects: subjects,
            effectiveFrom: startsOn,
            note: _note.text,
          )
        : await state.saveClassScheduleByHead(
            studentId: widget.ownerId,
            studentName: widget.ownerName,
            subjects: subjects,
            effectiveFrom: startsOn,
          );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _saving = false;
        _problems = [problem];
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 500 ? 12 : 24,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LightDialogHeader(
              icon: _isRequest
                  ? Icons.upload_file_outlined
                  : Icons.edit_calendar_outlined,
              title: _isRequest ? 'Upload new schedule' : 'Edit classes',
              subtitle: _isRequest
                  ? 'The Head checks it before it replaces your schedule'
                  : widget.ownerName,
              onClose: _saving ? null : () => Navigator.of(context).pop(false),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isRequest)
                      const Text(
                        'Upload your new class schedule (a screenshot, a PDF or '
                        'a photo of the printed copy). Your classes are scanned '
                        'automatically and cannot be edited manually. Your '
                        'schedule stays as it is until the Head approves this '
                        'one.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.slate600,
                          height: 1.45,
                        ),
                      )
                    else
                      const Text(
                        'Change the classes below. They apply from the day you '
                        'pick, on the Calendar and in the DTR; the schedule '
                        'file stays as it is.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.slate600,
                          height: 1.45,
                        ),
                      ),
                    const SizedBox(height: 14),
                    ClassScheduleEditor(
                      controller: _controller,
                      ownerId: widget.ownerId,
                      enabled: !_saving,
                      withFile: _isRequest,
                      readOnly: _isRequest,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Starts on',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slate700,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _pickStart,
                          icon: const Icon(Icons.event_outlined, size: 16),
                          label: Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_startsOn),
                          ),
                        ),
                      ],
                    ),
                    if (_isRequest) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _note,
                        enabled: !_saving,
                        maxLength: 300,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Note for the Head (optional)',
                          hintText:
                              'For example: new semester, or a section change',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                    if (_problems.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.red50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in _problems.take(6))
                              Text(
                                p,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.red500,
                                  height: 1.4,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isRequest
                                ? Icons.send_outlined
                                : Icons.save_outlined,
                            size: 16,
                          ),
                    label: Text(
                      _saving
                          ? (_isRequest ? 'Sending...' : 'Saving...')
                          : (_isRequest ? 'Send to the Head' : 'Save classes'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.maroon,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.maroon.withValues(
                        alpha: 0.7,
                      ),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
