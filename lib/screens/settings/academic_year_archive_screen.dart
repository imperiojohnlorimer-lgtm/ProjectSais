import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../theme/app_theme.dart';

/// The Academic Year page: what archiving [AppState.academicYearShown]
/// saves. Before it happens, a preview: when it will, the records it will
/// copy and — for the Head — what's still open, which is archived as it
/// stands. Afterwards, a summary of the archive: when it was made, what it
/// holds, the headcount per campus and the year's settings.
///
/// Opened from an academic year notification, the Head's banner, or the
/// Admin's list of archived years in Settings; its address is
/// /academic-year/2026-2027 and so on.
class AcademicYearArchiveScreen extends StatelessWidget {
  const AcademicYearArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final year = state.academicYearShown;
    final archive = state.academicYearArchive(year);
    final archived = archive != null && archive['dataArchived'] != false;
    // Counted afresh for another year, and once its records are copied in.
    return _AcademicYearView(key: ValueKey('$year/$archived'), year: year);
  }
}

class _AcademicYearView extends StatefulWidget {
  const _AcademicYearView({super.key, required this.year});

  final String year;

  @override
  State<_AcademicYearView> createState() => _AcademicYearViewState();
}

class _AcademicYearViewState extends State<_AcademicYearView> {
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

  static const _bodyStyle = TextStyle(fontSize: 13, color: AppTheme.slate600);
  static const _noteStyle = TextStyle(fontSize: 12, color: AppTheme.slate500);
  static const _valueStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppTheme.slate900,
  );

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

    final padding = MediaQuery.of(context).size.width < 420 ? 16.0 : 28.0;

    final headcount = archive == null
        ? state.studentsPerCampus
        : archive['headcountByCampus'];
    final total = _total(headcount);
    final records = _card(
      icon: Icons.inventory_2_outlined,
      title: archived ? 'Records saved' : 'Will be saved',
      subtitle: archived
          ? 'What its archive holds'
          : 'The records filed under AY $year, copied into its archive',
      child: _recordCounts(state, archived),
    );
    final open = state.role == 'Head' && !archived
        ? _card(
            icon: Icons.pending_actions_outlined,
            title: 'Still open',
            subtitle: 'These are archived as they stand, so finish them first.',
            child: _openItems(state),
          )
        : null;
    final students = _card(
      icon: Icons.groups_outlined,
      title: archive == null
          ? 'Student assistants now'
          : 'Student assistants at close',
      subtitle: total == null ? null : '$total in all, by campus',
      child: _headcount(headcount),
    );
    final settings = archive == null
        ? null
        : _card(
            icon: Icons.tune_rounded,
            title: 'Settings that year',
            child: _settings(archive),
          );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding, 14, padding, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () =>
                state.setTab(state.academicYearOpenedFrom ?? 'dashboard'),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.slate600,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              // Replaces the theme's, font included.
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.maroon,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'AY $year',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          if (start != null && end != null)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 4),
              child: Text(
                '${_fullDate(start)} – ${_fullDate(end)}',
                style: const TextStyle(fontSize: 13, color: AppTheme.slate400),
              ),
            ),
          const SizedBox(height: 18),
          _status(state, archive, archived, isCurrent),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = SizedBox(height: 16, width: 16);
              if (constraints.maxWidth < 860) {
                return Column(
                  children: [
                    records,
                    if (open != null) ...[gap, open],
                    gap,
                    students,
                    if (settings != null) ...[gap, settings],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        records,
                        if (open != null) ...[gap, open],
                      ],
                    ),
                  ),
                  gap,
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        students,
                        if (settings != null) ...[gap, settings],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: waiting ? AppTheme.amber50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: waiting ? color.withValues(alpha: 0.3) : AppTheme.slate200,
        ),
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
                fontSize: 13,
                height: 1.4,
                color: AppTheme.slate700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.slate200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.maroon),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(subtitle, style: _noteStyle),
          ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

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
                  ? null
                  : '${data[kind.key] ?? 0}',
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                final columns = constraints.maxWidth >= 480 ? 4 : 2;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: 16,
                  children: [
                    for (final cell in cells)
                      SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 30,
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  cell.value ?? 'Not archived',
                                  style: cell.value == null
                                      ? const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.slate400,
                                        )
                                      : const TextStyle(
                                          fontSize: 24,
                                          height: 1.1,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.slate900,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(cell.label, style: _noteStyle),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            if (!withAttendance)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  archived
                      ? 'Auto-archive Logs was off, so the attendance logs '
                            'stayed in place.'
                      : 'Auto-archive Logs is off, so the attendance logs '
                            'stay in place.',
                  style: _noteStyle,
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
            size: 18,
            color: AppTheme.emerald500,
          ),
          SizedBox(width: 8),
          Expanded(child: Text('Nothing is left open.', style: _bodyStyle)),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a phone the button goes under its line, not beside it.
        final narrow = constraints.maxWidth < 420;
        return Column(
          children: [
            for (final (index, item) in items.indexed) ...[
              if (index > 0)
                const Divider(
                  height: 17,
                  thickness: 1,
                  color: AppTheme.slate100,
                ),
              Row(
                // Beside the line, the taller button lines up with it.
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: narrow ? 2 : 0),
                    child: const Icon(
                      Icons.radio_button_unchecked,
                      size: 15,
                      color: AppTheme.amber500,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.text, style: _bodyStyle),
                        if (narrow && item.tab != null)
                          _openButton(state, item.tab!, item.action!),
                      ],
                    ),
                  ),
                  if (!narrow && item.tab != null) ...[
                    const SizedBox(width: 12),
                    _openButton(state, item.tab!, item.action!),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _openButton(AppState state, String tab, String label) => TextButton(
    onPressed: () => state.setTab(tab),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      minimumSize: const Size(0, 24),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      // Replaces the theme's, font included.
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    ),
    child: Text(label),
  );

  static Map<String, int>? _campusCounts(Object? saved) {
    if (saved is! Map || saved.isEmpty) return null;
    return {
      for (final entry in saved.entries)
        if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
    };
  }

  static int? _total(Object? saved) =>
      _campusCounts(saved)?.values.fold<int>(0, (all, count) => all + count);

  Widget _headcount(Object? saved) {
    final counts = _campusCounts(saved);
    if (counts == null) {
      return const Text('Not recorded for this year.', style: _bodyStyle);
    }
    return Column(
      children: [
        for (final (index, entry) in counts.entries.indexed) ...[
          if (index > 0)
            const Divider(height: 15, thickness: 1, color: AppTheme.slate100),
          Row(
            children: [
              Expanded(child: Text(entry.key, style: _bodyStyle)),
              Text('${entry.value}', style: _valueStyle),
            ],
          ),
        ],
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
    if (rows.isEmpty && milestones.isEmpty) {
      return const Text('Not recorded for this year.', style: _bodyStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(row.label, style: _bodyStyle)),
                Text(row.value, style: _valueStyle),
              ],
            ),
          ),
        if (milestones.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'MILESTONES',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppTheme.slate500,
            ),
          ),
          for (final milestone in milestones)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                milestone.date == null
                    ? milestone.title
                    : '${milestone.title} · ${_fullDate(milestone.date!)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.slate700,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
