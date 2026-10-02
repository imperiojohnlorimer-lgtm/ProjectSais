import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../theme/app_theme.dart';

/// Opens [AcademicYearArchiveDialog] for [year].
Future<void> showAcademicYearArchiveDialog(BuildContext context, String year) =>
    showDialog<void>(
      context: context,
      builder: (_) => AcademicYearArchiveDialog(year: year),
    );

/// What archiving an academic year saves. Before it happens, a preview:
/// when it will, the records it will copy and — for the Head — what's still
/// open, which is archived as it stands. Afterwards, a summary of the
/// archive: when it was made, what it holds, the headcount per campus and
/// the year's settings.
class AcademicYearArchiveDialog extends StatefulWidget {
  const AcademicYearArchiveDialog({super.key, required this.year});

  final String year;

  @override
  State<AcademicYearArchiveDialog> createState() =>
      _AcademicYearArchiveDialogState();
}

class _AcademicYearArchiveDialogState extends State<AcademicYearArchiveDialog> {
  /// Null when this role can't count them: the Admin can't read a year's
  /// records until the Head's session has copied them into the archive.
  Future<Map<String, int>>? _counts;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final archive = state.academicYearArchive(widget.year);
    final archived = archive != null && archive['dataArchived'] != false;
    if (state.role == 'Head' || (state.role == 'Admin' && archived)) {
      _counts = state.countArchiveRecords(widget.year);
    }
  }

  static String _fullDate(DateTime date) =>
      '${AppState.monthDay(date)}, ${date.year}';

  static String _plural(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final year = widget.year;
    final archive = state.academicYearArchive(year);
    final archived = archive != null && archive['dataArchived'] != false;
    final isCurrent = archive == null && year == state.academicYear;

    final start = isCurrent
        ? state.academicYearStart
        : AppState.dateOf(archive?['startDate']);
    final end = isCurrent
        ? state.academicYearEnd
        : AppState.dateOf(archive?['endDate']);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 40,
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
                        Text(
                          'AY $year',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                        ),
                        if (start != null && end != null)
                          Text(
                            '${_fullDate(start)} – ${_fullDate(end)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.slate500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    color: AppTheme.slate500,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _status(state, archive, archived, isCurrent),
                    _section(
                      archived ? 'RECORDS SAVED' : 'WILL BE SAVED',
                      _recordCounts(state, archived),
                    ),
                    if (state.role == 'Head' && !archived)
                      _section(
                        'STILL OPEN',
                        _openItems(state),
                        note:
                            'These are archived as they stand, so finish them '
                            'first.',
                      ),
                    _section(
                      archive == null
                          ? 'STUDENT ASSISTANTS NOW'
                          : 'STUDENT ASSISTANTS AT CLOSE',
                      _headcount(
                        archive == null
                            ? state.studentsPerCampus
                            : archive['headcountByCampus'],
                      ),
                    ),
                    if (archive != null)
                      _section('SETTINGS THAT YEAR', _settings(archive)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(
    AppState state,
    Map<String, dynamic>? archive,
    bool archived,
    bool isCurrent,
  ) {
    final year = widget.year;
    final IconData icon;
    final String text;
    var waiting = true;
    if (archived) {
      waiting = false;
      icon = Icons.inventory_2_outlined;
      final at = AppState.dateOf(archive!['dataArchivedAt']);
      text = at == null
          ? 'Archived.'
          : 'Archived on ${_fullDate(at)} at ${AppState.clockTime(at)}.';
    } else if (archive != null) {
      icon = Icons.hourglass_top_rounded;
      final due = state.archiveDueAt(archive)!;
      final undoable =
          state.canUndoTermChange &&
          (state.previousTermLabel?.endsWith('AY $year') ?? false);
      text =
          'Will be archived after ${AppState.monthDayTime(due)}'
          '${state.role == 'Head' ? '' : ', the next time the Head opens SAIS'}.'
          '${undoable ? ' The Admin can undo the switch until then.' : ''}';
    } else if (isCurrent) {
      icon = Icons.event_outlined;
      final days = state.daysUntilAcademicYearEnds;
      final end = state.academicYearEnd;
      text = days < 0
          ? 'Ended on ${AppState.monthDay(end)}. Its records will be archived '
                'soon.'
          : days <= AppState.archiveNoticeDays
          ? 'Ends ${AppState.daysAwayLabel(days)} (${AppState.monthDay(end)}). '
                'Its records will be archived after that.'
          : 'Ends on ${_fullDate(end)}. Its records will be archived after '
                'that.';
    } else {
      waiting = false;
      icon = Icons.info_outline;
      text = 'This year isn\'t on the archive list.';
    }
    final color = waiting ? AppTheme.amber500 : AppTheme.slate500;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: waiting ? AppTheme.amber50 : AppTheme.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.slate700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget body, {String? note}) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppTheme.slate500,
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              note,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
            ),
          ),
        const SizedBox(height: 8),
        body,
      ],
    ),
  );

  static const _bodyStyle = TextStyle(fontSize: 12.5, color: AppTheme.slate600);

  Widget _recordCounts(AppState state, bool archived) {
    final counts = _counts;
    if (counts == null) {
      return const Text(
        'They\'re counted once the Head\'s session has archived them.',
        style: _bodyStyle,
      );
    }
    return FutureBuilder<Map<String, int>>(
      future: counts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Couldn\'t count the records right now. Try again later.',
            style: _bodyStyle,
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Counting…', style: _bodyStyle),
            ],
          );
        }
        final withAttendance = state.archivesAttendance(widget.year);
        final cells = [
          for (final kind in AppState.archiveRecordKinds)
            (
              label: kind.label,
              value: kind.key == 'attendance' && !withAttendance
                  ? 'Not archived'
                  : '${data[kind.key] ?? 0}',
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 20.0;
                final columns = constraints.maxWidth >= 380 ? 2 : 1;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: 6,
                  children: [
                    for (final cell in cells)
                      SizedBox(
                        width: width,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(cell.label, style: _bodyStyle),
                            ),
                            Text(
                              cell.value,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slate900,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            if (!withAttendance)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  archived
                      ? 'Auto-archive Logs was off, so the attendance logs '
                            'stayed in place.'
                      : 'Auto-archive Logs is off, so the attendance logs '
                            'stay in place.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.slate500,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _openItems(AppState state) {
    final open = state.archiveOpenItems(widget.year);
    final items = [
      if (open.applications > 0)
        (
          text: '${_plural(open.applications, 'application')} not decided yet',
          tab: 'applications',
          action: 'Open Applications',
        ),
      if (open.requests > 0)
        (
          text:
              '${_plural(open.requests, 'student assistant request')} waiting '
              'for your approval',
          tab: 'announcements_admin',
          action: 'Open Announcements',
        ),
      if (open.reports > 0)
        (
          text:
              '${_plural(open.reports, 'report')} waiting for a supervisor\'s '
              'review',
          tab: null,
          action: null,
        ),
      if (open.tasks > 0)
        (
          text:
              '${_plural(open.tasks, 'completed task')} waiting for a '
              'supervisor\'s approval',
          tab: 'tasks',
          action: 'Open Tasks',
        ),
    ];
    if (items.isEmpty) {
      return const Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: AppTheme.emerald500,
          ),
          SizedBox(width: 8),
          Expanded(child: Text('Nothing is left open.', style: _bodyStyle)),
        ],
      );
    }
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.radio_button_unchecked,
                    size: 14,
                    color: AppTheme.amber500,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.text, style: _bodyStyle),
                      if (item.tab != null)
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            state.setTab(item.tab!);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 4,
                            ),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            // Replaces the theme's, font included.
                            textStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(item.action!),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _headcount(Object? saved) {
    if (saved is! Map || saved.isEmpty) {
      return const Text('Not recorded for this year.', style: _bodyStyle);
    }
    final counts = {
      for (final entry in saved.entries)
        if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
    };
    final total = counts.values.fold(0, (sum, count) => sum + count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            for (final entry in counts.entries)
              Text.rich(
                TextSpan(
                  style: _bodyStyle,
                  children: [
                    TextSpan(text: '${entry.key} '),
                    TextSpan(
                      text: '${entry.value}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$total in all',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
          ),
        ),
      ],
    );
  }

  Widget _settings(Map<String, dynamic> archive) {
    String onOff(Object? value) => value == true ? 'On' : 'Off';
    final rows = [
      if (archive['semester'] != null)
        (label: 'Term when it closed', value: '${archive['semester']}'),
      if (archive['allowApplications'] != null)
        (
          label: 'Open applications',
          value: onOff(archive['allowApplications']),
        ),
      if (archive['enforceHourCap'] != null)
        (label: 'Weekly hours cap', value: onOff(archive['enforceHourCap'])),
    ];
    final milestones = [
      for (final milestone in archive['milestones'] as List? ?? const [])
        if (milestone is Map && milestone['title'] != null)
          (
            title: '${milestone['title']}',
            date: AppState.dateOf(milestone['date']),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(child: Text(row.label, style: _bodyStyle)),
                Text(
                  row.value,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
              ],
            ),
          ),
        if (milestones.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text('Milestones', style: _bodyStyle),
          for (final milestone in milestones)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 10),
              child: Text(
                milestone.date == null
                    ? milestone.title
                    : '${milestone.title} · ${_fullDate(milestone.date!)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
              ),
            ),
        ],
      ],
    );
  }
}
