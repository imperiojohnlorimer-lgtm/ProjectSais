import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../models/task_duty.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'task_form_parts.dart';

/// The "Ongoing duties" card at the top of the Tasks page.
///
/// A Student Assistant sees their own duties and, on a day they've clocked
/// in, logs what they did for each one. A Supervisor (or the Head) sees the
/// duties they gave, whether today's was logged, and can stop or resume one.
class OngoingDutiesPanel extends StatelessWidget {
  const OngoingDutiesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isStudent = state.role == 'Student Assistant';
    final duties = isStudent ? state.dutiesToLog : state.filteredDuties;
    if (duties.isEmpty) return const SizedBox.shrink();
    final clockedIn = state.attendanceForToday() != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.blue500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.autorenew_rounded,
                  size: 18,
                  color: AppTheme.blue500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ongoing duties',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    Text(
                      isStudent
                          ? (clockedIn
                                ? "You're clocked in. Log what you did today."
                                : 'Clock in to log your work for today.')
                          : 'Student assistants log these on days they clock in.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < duties.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _DutyRow(
              duty: duties[i],
              isStudent: isStudent,
              clockedIn: clockedIn,
            ),
          ],
        ],
      ),
    );
  }
}

class _DutyRow extends StatelessWidget {
  final TaskDuty duty;
  final bool isStudent;
  final bool clockedIn;

  const _DutyRow({
    required this.duty,
    required this.isStudent,
    required this.clockedIn,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final todaysLog = state.dutyLogForToday(duty);
    final narrow = MediaQuery.of(context).size.width < 560;
    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  duty.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: duty.active ? AppTheme.slate900 : AppTheme.slate400,
                  ),
                ),
              ),
              if (!duty.active) ...[
                const SizedBox(width: 8),
                _pill('Stopped', AppTheme.slate500),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            isStudent
                ? (duty.description.isEmpty
                      ? '${duty.priority} priority'
                      : duty.description)
                : '${duty.assignedToName} · ${'${duty.priority} priority'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          if (todaysLog != null) ...[
            const SizedBox(height: 6),
            _logState(todaysLog),
          ],
        ],
      ),
    );
    final action = isStudent
        ? _studentAction(context, todaysLog)
        : _staffAction(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate100),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [info]),
                if (action != null) ...[const SizedBox(height: 10), action],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                info,
                if (action != null) ...[const SizedBox(width: 12), action],
              ],
            ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );

  /// What became of today's log: waiting, approved, or sent back.
  Widget _logState(Task log) {
    final (label, color, icon) = log.isApproved
        ? ('Today: approved', AppTheme.emerald500, Icons.verified_rounded)
        : log.status == 'Completed'
        ? (
            'Today: logged, waiting for approval',
            AppTheme.amber500,
            Icons.hourglass_top_rounded,
          )
        : (
            'Today: sent back. Finish it again from your tasks',
            AppTheme.red500,
            Icons.replay_rounded,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget? _studentAction(BuildContext context, Task? todaysLog) {
    if (todaysLog != null && todaysLog.wasRejected) {
      // Sent back: the note can be corrected before it goes again.
      return OutlinedButton.icon(
        onPressed: () => _logWork(context, resend: todaysLog),
        icon: const Icon(Icons.replay_rounded, size: 18),
        label: const Text('Fix and send again'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.maroon,
          side: const BorderSide(color: AppTheme.maroon200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );
    }
    if (todaysLog != null) return null;
    final ready = clockedIn && duty.active;
    return Tooltip(
      message: ready ? '' : 'Clock in first, then log your work for today',
      child: ElevatedButton.icon(
        onPressed: ready ? () => _logWork(context) : null,
        icon: const Icon(Icons.edit_note_rounded, size: 18),
        label: const Text("Log today's work"),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.maroon,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.slate200,
          disabledForegroundColor: AppTheme.slate400,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget? _staffAction(BuildContext context) {
    final state = context.read<AppState>();
    return OutlinedButton(
      onPressed: () async {
        final stopping = duty.active;
        if (stopping) {
          final ok = await showConfirmDialog(
            context,
            title: 'Stop Ongoing Duty',
            message:
                '${duty.assignedToName} will no longer be able to log '
                '"${duty.title}". Days already logged are kept.',
            confirmLabel: 'Stop',
            confirmColor: AppTheme.red500,
          );
          if (!ok) return;
        }
        final saved = await state.setTaskDutyActive(duty.id, !stopping);
        if (!context.mounted || saved) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't update the duty. Try again."),
            backgroundColor: AppTheme.red500,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: duty.active ? AppTheme.red500 : AppTheme.maroon,
        side: BorderSide(
          color: duty.active
              ? AppTheme.red500.withValues(alpha: 0.4)
              : AppTheme.maroon200,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
      child: Text(duty.active ? 'Stop' : 'Resume'),
    );
  }

  Future<void> _logWork(BuildContext context, {Task? resend}) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final note = await showDialog<String>(
      context: context,
      builder: (_) =>
          _LogWorkDialog(duty: duty, initialNote: resend?.description),
    );
    if (note == null) return;
    final problem = resend == null
        ? await state.logDutyWork(duty, note: note)
        : await state.resubmitDutyLog(resend, note: note);
    messenger.showSnackBar(
      SnackBar(
        content: Text(problem ?? 'Sent. Your supervisor will approve it.'),
        backgroundColor: problem == null
            ? AppTheme.emerald500
            : AppTheme.red500,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

/// Asks what the student did for a duty today. Pops with the note (which may
/// be empty), or null when cancelled.
class _LogWorkDialog extends StatefulWidget {
  final TaskDuty duty;
  final String? initialNote;

  const _LogWorkDialog({required this.duty, this.initialNote});

  @override
  State<_LogWorkDialog> createState() => _LogWorkDialogState();
}

class _LogWorkDialogState extends State<_LogWorkDialog> {
  late final _note = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaskFormHeader(
              icon: Icons.edit_note_rounded,
              title: "Log today's work",
              subtitle: widget.duty.title,
              onClose: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(inputDecorationTheme: taskInputTheme()),
                child: TextField(
                  controller: _note,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: TaskDuty.maxNote,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What did you do? (optional)',
                    hintText: 'e.g. Received and logged 12 documents',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Text(
                'This goes to your supervisor to approve. Once approved it '
                'shows on your DTR/Accomplishment Report for today.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppTheme.slate500,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.slate600,
                        side: const BorderSide(color: AppTheme.slate200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _note.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      child: const Text('Send for approval'),
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
