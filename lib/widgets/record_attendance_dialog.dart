import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

/// Opens the dialog a Supervisor or the Head uses to record a stretch of
/// attendance by hand, when there was no code to scan. [assistant] fixes
/// the student assistant; without it the dialog offers a list. Returns
/// whether a record was saved.
Future<bool> showRecordAttendanceDialog(
  BuildContext context, {
  User? assistant,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RecordAttendanceDialog(assistant: assistant),
  );
  return saved == true;
}

class RecordAttendanceDialog extends StatefulWidget {
  final User? assistant;

  const RecordAttendanceDialog({super.key, this.assistant});

  @override
  State<RecordAttendanceDialog> createState() => _RecordAttendanceDialogState();
}

class _RecordAttendanceDialogState extends State<RecordAttendanceDialog> {
  User? _assistant;
  DateTime? _day;
  TimeOfDay? _timeIn;
  TimeOfDay? _timeOut;
  String? _error;
  bool _saving = false;

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

  @override
  void initState() {
    super.initState();
    _assistant = widget.assistant;
  }

  static String _clock(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    return '$hour:${time.minute.toString().padLeft(2, '0')} '
        '${time.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  String _dayLabel(DateTime day, int index) {
    final date = '${_months[day.month - 1]} ${day.day}';
    if (index == 0) return 'Today ($date)';
    if (index == 1) return 'Yesterday ($date)';
    return '$date, ${day.year}';
  }

  Future<void> _pick(bool isTimeIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (isTimeIn ? _timeIn : _timeOut) ??
          (isTimeIn
              ? const TimeOfDay(hour: 8, minute: 0)
              : const TimeOfDay(hour: 11, minute: 0)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isTimeIn) {
        _timeIn = picked;
      } else {
        _timeOut = picked;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    // A choice that dropped off its list while the dialog was open (past
    // midnight, or the student left the office) no longer counts.
    final assistant =
        widget.assistant ??
        state.manualAttendanceAssistants
            .where((user) => user.id == _assistant?.id)
            .firstOrNull;
    final day = state.manualAttendanceDayChoices().contains(_day) ? _day : null;
    if (assistant == null || day == null || _timeIn == null || _timeOut == null) {
      setState(
        () => _error = 'Choose the student assistant, the day, the time-in '
            'and the time-out.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final problem = await state.recordManualAttendance(
      assistant: assistant,
      day: day,
      timeIn: _clock(_timeIn!),
      timeOut: _clock(_timeOut!),
    );
    if (!mounted) return;
    if (problem == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _saving = false;
      _error = problem;
    });
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppTheme.slate500,
      ),
    ),
  );

  Widget _timeButton(String label, TimeOfDay? value, bool isTimeIn) =>
      OutlinedButton.icon(
        onPressed: _saving ? null : () => _pick(isTimeIn),
        icon: const Icon(Icons.schedule_rounded, size: 16),
        label: Text(
          value == null ? label : _clock(value),
          style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: value == null ? AppTheme.slate500 : AppTheme.slate800,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final assistants = state.manualAttendanceAssistants;
    final days = state.manualAttendanceDayChoices();
    final fixed = widget.assistant;
    // Only a value still in its list is shown as chosen.
    final assistantId = assistants.any((user) => user.id == _assistant?.id)
        ? _assistant!.id
        : null;
    final dayIndex = _day == null ? -1 : days.indexOf(_day!);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LightDialogHeader(
                icon: Icons.edit_calendar_rounded,
                title: 'Record Attendance',
                subtitle: fixed == null
                    ? 'For time worked when there was no code to scan'
                    : 'For ${fixed.name}, when there was no code to scan',
                onClose: _saving ? null : () => Navigator.pop(context, false),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fixed == null) ...[
                      _label('STUDENT ASSISTANT'),
                      if (assistants.isEmpty)
                        const Text(
                          'No student assistants in your offices yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.slate500,
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: assistantId,
                          isExpanded: true,
                          hint: const Text('Choose'),
                          items: [
                            for (final user in assistants)
                              DropdownMenuItem(
                                value: user.id,
                                child: Text(
                                  user.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (id) => setState(() {
                                  _assistant = assistants
                                      .where((user) => user.id == id)
                                      .firstOrNull;
                                  _error = null;
                                }),
                        ),
                      const SizedBox(height: 14),
                    ],
                    _label('DAY'),
                    DropdownButtonFormField<int>(
                      initialValue: dayIndex < 0 ? null : dayIndex,
                      isExpanded: true,
                      hint: const Text('Choose'),
                      items: [
                        for (var i = 0; i < days.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(_dayLabel(days[i], i)),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (i) => setState(() {
                              _day = i == null ? null : days[i];
                              _error = null;
                            }),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _label('TIME-IN'),
                              _timeButton('Pick', _timeIn, true),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _label('TIME-OUT'),
                              _timeButton('Pick', _timeOut, false),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'One session at a time (7:30 AM–12:00 PM or '
                      '12:30 PM–5:00 PM), up to 7 days back. The weekly '
                      'hours limit applies, the record shows you entered '
                      'it, and the student assistant is notified.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.slate500),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.red500.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.red500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
