import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_state.dart';
import '../../models/class_schedule.dart';
import '../../models/recurring_schedule.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/philippine_dates.dart';
import '../../widgets/class_schedule_dialog.dart';
import '../../widgets/class_schedule_summary.dart';
import '../../widgets/document_preview.dart';

/// Dark amber: readable on white.
const _amberText = Color(0xFFB45309);

/// A Student Assistant's class schedule on the Calendar: the one in effect,
/// its file, and what can be done with it. The Student Assistant uploads a
/// new one (it waits for the Head); the Head can change the classes
/// directly; a Supervisor sees it.
class ClassScheduleCard extends StatefulWidget {
  final String ownerId;
  final String ownerName;

  /// The Student Assistant's own calendar.
  final bool isOwn;

  const ClassScheduleCard({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.isOwn,
  });

  @override
  State<ClassScheduleCard> createState() => _ClassScheduleCardState();
}

class _ClassScheduleCardState extends State<ClassScheduleCard> {
  bool _showClasses = false;
  bool _withdrawing = false;

  String _day(String key) => philippineDayText('${key}T04:00:00Z') ?? key;

  Future<void> _upload(ClassScheduleVersion? current) async {
    final sent = await showClassScheduleDialog(
      context,
      ownerId: widget.ownerId,
      ownerName: widget.ownerName,
      mode: ClassScheduleDialogMode.request,
      earliest: current?.startDay,
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sent. The Head will check your new schedule.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _edit(
    ClassScheduleVersion? current,
    List<RecurringScheduleRule> legacy,
  ) async {
    final saved = await showClassScheduleDialog(
      context,
      ownerId: widget.ownerId,
      ownerName: widget.ownerName,
      mode: ClassScheduleDialogMode.head,
      current: current?.subjects ?? legacy,
      earliest: current?.startDay,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Classes saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _withdraw(String id) async {
    setState(() => _withdrawing = true);
    final problem = await context.read<AppState>().cancelScheduleRequest(id);
    if (!mounted) return;
    setState(() => _withdrawing = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final schedules = context.watch<ScheduleService>();
    final owner = schedules.scheduleOf(widget.ownerId);
    final isHead = state.role == 'Head';
    final today = state.philippineClock();
    final versions = owner?.versions ?? const <ClassScheduleVersion>[];
    final current = ClassScheduleVersion.inEffect(
      versions,
      today,
      academicYear: state.academicYear,
    );
    final todayKey = ClassScheduleVersion.dayKey(today);
    final upcoming =
        versions.where((v) => v.effectiveFrom.compareTo(todayKey) > 0).toList()
          ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    final next = upcoming.isEmpty ? null : upcoming.first;
    final legacy = <RecurringScheduleRule>[
      for (final r in owner?.rules ?? const <RecurringScheduleRule>[])
        if (r.isSubject) r,
    ];

    final ScheduleRequest? myRequest = widget.isOwn
        ? state.myLatestScheduleRequest
        : null;
    final waitingForHead = isHead
        ? state.pendingScheduleRequests
              .where((r) => r.studentId == widget.ownerId)
              .firstOrNull
        : null;

    final shown = current ?? next;
    final title = shown == null
        ? 'Class schedule'
        : 'Class schedule · ${shown.subjectCount} '
              '${shown.subjectCount == 1 ? 'subject' : 'subjects'}';
    final String subtitle;
    if (current != null) {
      subtitle =
          'In effect since ${_day(current.effectiveFrom)}'
          '${current.approvedBy.isEmpty ? '' : ' · approved by ${current.approvedBy}'}';
    } else if (next != null) {
      subtitle = 'Starts ${_day(next.effectiveFrom)}';
    } else if (legacy.isNotEmpty) {
      subtitle = widget.isOwn
          ? 'Your classes were typed in. Upload your class schedule so the '
                'Head can approve it.'
          : 'Typed in, not approved from a schedule file yet.';
    } else {
      subtitle = widget.isOwn
          ? 'Upload your class schedule so your classes show here and in '
                'your DTR.'
          : 'No approved class schedule yet.';
    }

    final buttons = <Widget>[
      if (shown != null && shown.filePath.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => showDocumentPreview(
            context,
            fileName: shown.fileName.isEmpty
                ? 'Class schedule'
                : shown.fileName,
            storagePath: shown.filePath,
          ),
          icon: const Icon(Icons.image_outlined, size: 16),
          label: const Text('View file'),
        ),
      if (shown != null)
        OutlinedButton.icon(
          onPressed: () => setState(() => _showClasses = !_showClasses),
          icon: Icon(
            _showClasses ? Icons.expand_less : Icons.expand_more,
            size: 16,
          ),
          label: Text(_showClasses ? 'Hide classes' : 'See classes'),
        ),
      if (widget.isOwn && state.role == 'Student Assistant')
        ElevatedButton.icon(
          onPressed: () => _upload(current),
          icon: const Icon(Icons.upload_file_outlined, size: 16),
          label: Text(
            shown == null ? 'Upload schedule' : 'Upload new schedule',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.maroon,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
      if (isHead)
        OutlinedButton.icon(
          onPressed: () => _edit(current, legacy),
          icon: const Icon(Icons.edit_calendar_outlined, size: 16),
          label: const Text('Edit classes'),
        ),
      if (waitingForHead != null)
        ElevatedButton.icon(
          onPressed: () => state.setTab('schedule_requests'),
          icon: const Icon(Icons.fact_check_outlined, size: 16),
          label: const Text('Review the new schedule'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.maroon,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: AppTheme.maroon,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                        height: 1.4,
                      ),
                    ),
                    if (current != null && next != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'A new schedule starts ${_day(next.effectiveFrom)}.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.blue500,
                        ),
                      ),
                    ],
                    if (myRequest != null) _requestLine(myRequest),
                    if (waitingForHead != null) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'A new schedule from this student is waiting for you.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _amberText,
                        ),
                      ),
                    ],
                    if (buttons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: buttons),
                    ],
                    if (_showClasses && shown != null) ...[
                      const SizedBox(height: 12),
                      ClassScheduleSummary(subjects: shown.subjects),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestLine(ScheduleRequest request) {
    final String text;
    final Color colour;
    switch (request.status) {
      case ScheduleRequest.pending:
        text =
            'Your new schedule is waiting for the Head'
            '${request.submittedAt == null ? '' : ' (sent ${philippineDayText(request.submittedAt!.toUtc().toIso8601String())})'}.';
        colour = _amberText;
      case ScheduleRequest.rejected:
        text = request.reviewNote.isEmpty
            ? 'Your last schedule was not approved.'
            : 'Your last schedule was not approved: ${request.reviewNote}';
        colour = AppTheme.red500;
      default:
        return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
          if (request.isPending)
            TextButton(
              onPressed: _withdrawing ? null : () => _withdraw(request.id),
              child: Text(_withdrawing ? 'Withdrawing...' : 'Withdraw'),
            ),
        ],
      ),
    );
  }
}
