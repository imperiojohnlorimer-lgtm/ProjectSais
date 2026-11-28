import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/philippine_dates.dart';
import '../../widgets/class_schedule_summary.dart';
import '../../widgets/document_preview.dart';
import '../../widgets/shared_widgets.dart';

/// Head-only page: new class schedules Student Assistants sent from the
/// Calendar. Approving one makes it their schedule from the day they chose
/// (Calendar and DTR); rejecting keeps the old one and tells them why.
class ScheduleRequestsScreen extends StatefulWidget {
  const ScheduleRequestsScreen({super.key});

  @override
  State<ScheduleRequestsScreen> createState() => _ScheduleRequestsScreenState();
}

class _ScheduleRequestsScreenState extends State<ScheduleRequestsScreen> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final waiting = state.pendingScheduleRequests;
    final decided = state.decidedScheduleRequests;
    final shown = _history ? decided : waiting;
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    // The current schedules, to compare with.
    final schedules = context.read<ScheduleService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in waiting) {
        schedules.ensureLoaded(r.studentId);
      }
    });

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(waiting.length),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('Waiting (${waiting.length})'),
                selected: !_history,
                onSelected: (_) => setState(() => _history = false),
              ),
              ChoiceChip(
                label: Text('History (${decided.length})'),
                selected: _history,
                onSelected: (_) => setState(() => _history = true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!state.isLoaded('Schedule requests') &&
              state.scheduleRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: EmptyState(
                icon: Icons.event_available_outlined,
                message: _history
                    ? 'No decided requests yet.'
                    : 'No new class schedules are waiting.',
              ),
            )
          else
            for (final request in shown) ...[
              _RequestCard(key: ValueKey(request.id), request: request),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _header(int count) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 3,
        height: 32,
        margin: const EdgeInsets.only(top: 3),
        decoration: BoxDecoration(
          color: AppTheme.maroon,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.edit_calendar_outlined,
                  size: 17,
                  color: AppTheme.maroon,
                ),
                SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Schedule Requests',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                      letterSpacing: -0.3,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              count == 0
                  ? 'New class schedules from Student Assistants wait here'
                  : '$count waiting for you. Compare each with its file '
                        'before approving.',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.slate500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RequestCard extends StatefulWidget {
  final ScheduleRequest request;
  const _RequestCard({super.key, required this.request});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  /// Cards start closed (name, dates and a one-line summary); a tap opens
  /// the classes and the buttons. Kept per card by its key.
  bool _open = false;

  ScheduleRequest get request => widget.request;

  String _day(String key) => philippineDayText('${key}T04:00:00Z') ?? key;

  void _say(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppTheme.red500 : AppTheme.emerald500,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve this schedule?'),
        content: Text(
          "It becomes ${request.studentName}'s class schedule from "
          '${_day(request.effectiveFrom)}, on the Calendar and in the DTR. '
          'Check the classes against the file first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final problem = await context.read<AppState>().approveScheduleRequest(
      request.id,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _say(problem ?? 'Approved.', error: problem != null);
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final problem = await context.read<AppState>().rejectScheduleRequest(
      request.id,
      reason,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      problem ?? 'Rejected. The student was told why.',
      error: problem != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final schedules = context.watch<ScheduleService>();
    final student = state.users
        .where((u) => u.id == request.studentId)
        .firstOrNull;
    final offices = student == null
        ? const <String>[]
        : state.officesForUser(student).map((o) => o.name).toList();
    final current = ClassScheduleVersion.inEffect(
      schedules.scheduleOf(request.studentId)?.versions ?? const [],
      state.philippineClock(),
      academicYear: state.academicYear,
    );
    final changed = current == null
        ? const <String>{}
        : ClassScheduleSummary.changedSubjects(
            current.subjects,
            request.subjects,
          );
    final sent = request.submittedAt == null
        ? ''
        : philippineDayText(request.submittedAt!.toUtc().toIso8601String()) ??
              '';
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final subjectCount = ClassScheduleSummary.grouped(request.subjects).length;
    final summary = [
      '$subjectCount subject${subjectCount == 1 ? '' : 's'}',
      if (request.isPending && changed.isNotEmpty)
        '${changed.length} new or changed',
    ].join(' · ');

    final newer = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('NEW SCHEDULE'),
        const SizedBox(height: 6),
        ClassScheduleSummary(subjects: request.subjects, highlight: changed),
      ],
    );
    final older = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('NOW'),
        const SizedBox(height: 6),
        if (current == null)
          const Text(
            'No approved class schedule yet.',
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          )
        else
          ClassScheduleSummary(subjects: current.subjects),
      ],
    );

    final header = Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          // Less below when open: the details start with their own gap.
          padding: EdgeInsets.fromLTRB(16, 16, 16, _open ? 4 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.studentName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (offices.isNotEmpty)
                          offices.join(', ')
                        else
                          'No office yet',
                        if (sent.isNotEmpty) 'sent $sent',
                        'starts ${_day(request.effectiveFrom)}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate700,
                      ),
                    ),
                  ],
                ),
              ),
              if (!request.isPending) ...[
                _StatusPill(request.status),
                const SizedBox(width: 6),
              ],
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.expand_more_rounded,
                  color: AppTheme.slate500,
                  semanticLabel: _open ? 'Hide classes' : 'Show classes',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _details(newer, older, wide),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  /// What a tap opens: the note, the reason, the classes and the buttons.
  Widget _details(Widget newer, Widget older, bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (request.note.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          'Note: ${request.note}',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.slate700),
        ),
      ],
      if (request.status == ScheduleRequest.rejected &&
          request.reviewNote.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          'Reason: ${request.reviewNote}',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.red500),
        ),
      ],
      const SizedBox(height: 12),
      if (request.isPending && wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: newer),
            const SizedBox(width: 20),
            Expanded(child: older),
          ],
        )
      else ...[
        newer,
        if (request.isPending) ...[const SizedBox(height: 12), older],
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: request.filePath.isEmpty
                ? null
                : () => showDocumentPreview(
                    context,
                    fileName: request.fileName,
                    storagePath: request.filePath,
                  ),
            icon: const Icon(Icons.image_outlined, size: 16),
            label: const Text('View file'),
          ),
          if (request.isPending) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.red500),
            ),
            ElevatedButton.icon(
              onPressed: _busy ? null : _approve,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 16),
              label: Text(_busy ? 'Saving...' : 'Approve'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.maroon,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.maroon.withValues(alpha: 0.7),
                disabledForegroundColor: Colors.white,
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: AppTheme.slate500,
      letterSpacing: 1,
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final colour = switch (status) {
      ScheduleRequest.approved => AppTheme.emerald500,
      ScheduleRequest.rejected => AppTheme.red500,
      _ => AppTheme.slate500,
    };
    final label = status == ScheduleRequest.cancelled ? 'Withdrawn' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colour,
        ),
      ),
    );
  }
}

/// Asks why; the student sees the reason.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  String? _error;

  static const _quick = [
    "The classes don't match the file.",
    'The file is not a class schedule.',
    'The file cannot be read clearly.',
    'Wrong semester.',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject this schedule?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Their schedule stays as it is. Say why, so they can fix it.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.slate600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 11.5)),
                    onPressed: () => setState(() {
                      _reason.text = q;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              maxLength: 300,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final text = _reason.text.trim();
            if (text.isEmpty) {
              setState(() => _error = 'Say why.');
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
