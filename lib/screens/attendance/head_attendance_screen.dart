import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/assistant_attendance.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// The periods the Head's summary covers.
enum _Period { thisWeek, thisMonth, lastMonth, schoolYear, custom }

/// The Head's Attendance page: a summary of every Student Assistant's
/// attendance, filtered by period, office, department and status. There's
/// no QR code here: supervisors run attendance for their offices.
class HeadAttendanceScreen extends StatefulWidget {
  const HeadAttendanceScreen({super.key});

  @override
  State<HeadAttendanceScreen> createState() => _HeadAttendanceScreenState();
}

class _HeadAttendanceScreenState extends State<HeadAttendanceScreen> {
  static const _all = 'All';
  static const _unassigned = '';
  static const _statuses = [
    _all,
    'Clocked in now',
    'Missed time-outs',
    'No attendance',
  ];
  static const _sorts = ['Name', 'Most hours', 'Fewest hours'];
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

  String _search = '';
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;

  /// [_all], [_unassigned] or an office id.
  String _office = _all;
  String _department = _all;
  String _status = _all;
  String _sort = 'Name';
  bool _showArchived = false;
  final _expanded = <String>{};

  /// The first and last day the period covers; null ends are open.
  (DateTime?, DateTime?) _range(AppState state) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.thisWeek => (
        today.subtract(Duration(days: today.weekday - 1)),
        today.add(Duration(days: 7 - today.weekday)),
      ),
      _Period.thisMonth => (
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1, 0),
      ),
      _Period.lastMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
      ),
      _Period.schoolYear => (state.academicYearStart, state.academicYearEnd),
      _Period.custom => (_custom?.start, _custom?.end),
    };
  }

  String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  String _periodLabel(_Period period) => switch (period) {
    _Period.thisWeek => 'This week',
    _Period.thisMonth => 'This month',
    _Period.lastMonth => 'Last month',
    _Period.schoolYear => 'School year',
    _Period.custom =>
      _custom == null
          ? 'Pick dates…'
          : '${_day(_custom!.start)} – ${_day(_custom!.end)}',
  };

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _custom,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = picked;
      _period = _Period.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final (from, to) = _range(state);
    final everyone = state.assistantAttendance(
      from: from,
      to: to,
      includeArchived: _showArchived,
    );

    final departments = {
      for (final row in everyone)
        if ((row.assistant.department ?? '').trim().isNotEmpty)
          row.assistant.department!.trim(),
    }.toList()..sort();
    final activeOffices = state.offices.where((o) => o.isActive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (_department != _all && !departments.contains(_department)) {
      _department = _all;
    }
    if (_office != _all &&
        _office != _unassigned &&
        !activeOffices.any((o) => o.id == _office)) {
      _office = _all;
    }

    final query = _search.trim().toLowerCase();
    final rows = everyone.where((row) {
      if (query.isNotEmpty &&
          !row.assistant.name.toLowerCase().contains(query)) {
        return false;
      }
      if (_office == _unassigned && row.offices.isNotEmpty) return false;
      if (_office != _all &&
          _office != _unassigned &&
          !row.offices.any((o) => o.id == _office)) {
        return false;
      }
      if (_department != _all &&
          (row.assistant.department ?? '').trim() != _department) {
        return false;
      }
      return switch (_status) {
        'Clocked in now' => row.clockedIn,
        'Missed time-outs' => row.missedTimeOuts > 0,
        'No attendance' => !row.hasAttendance,
        _ => true,
      };
    }).toList();
    switch (_sort) {
      case 'Most hours':
        rows.sort((a, b) => b.hours.compareTo(a.hours));
      case 'Fewest hours':
        rows.sort((a, b) => a.hours.compareTo(b.hours));
    }
    final maxHours = rows.fold<double>(
      0,
      (most, row) => row.hours > most ? row.hours : most,
    );
    final totalHours = rows.fold<double>(0, (sum, row) => sum + row.hours);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final hPad = isMobile ? 16.0 : 28.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroBanner(
                isMobile: isMobile,
                icon: Icons.access_time_filled_rounded,
                title: 'Attendance',
                subtitle: "A summary of every Student Assistant's attendance",
                searchHint: 'Search student assistants...',
                onSearch: (value) => setState(() => _search = value),
                filters: [_archivedToggle()],
                stats: [
                  HeroStatData(
                    label: 'Student Assistants',
                    value: '${rows.length}',
                    icon: Icons.groups_rounded,
                  ),
                  HeroStatData(
                    label: 'Clocked in now',
                    value: '${rows.where((r) => r.clockedIn).length}',
                    icon: Icons.play_circle_fill_rounded,
                  ),
                  HeroStatData(
                    label: 'Verified hours',
                    value: _hours(totalHours),
                    icon: Icons.schedule_rounded,
                  ),
                  HeroStatData(
                    label: 'Missed time-outs',
                    value:
                        '${rows.fold<int>(0, (sum, r) => sum + r.missedTimeOuts)}',
                    icon: Icons.error_outline_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _filters(departments, activeOffices),
              const SizedBox(height: 16),
              if (rows.isEmpty &&
                  !(state.isLoaded('Users') && state.isLoaded('Attendance')))
                const LoadingState()
              else if (rows.isEmpty)
                EmptyState(
                  icon: everyone.isEmpty
                      ? Icons.groups_outlined
                      : Icons.search_off_rounded,
                  message: everyone.isEmpty
                      ? 'No Student Assistants yet'
                      : 'No Student Assistants match these filters',
                )
              else
                for (final row in rows)
                  _AssistantRow(
                    key: ValueKey(row.assistant.id),
                    row: row,
                    maxHours: maxHours,
                    compact: isMobile,
                    expanded: _expanded.contains(row.assistant.id),
                    onToggle: () => setState(() {
                      if (!_expanded.remove(row.assistant.id)) {
                        _expanded.add(row.assistant.id);
                      }
                    }),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Archived records count in no total; shown, they can be restored.
  Widget _archivedToggle() => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () => setState(() => _showArchived = !_showArchived),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: _showArchived
            ? AppTheme.amber500.withValues(alpha: 0.1)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _showArchived
              ? AppTheme.amber500.withValues(alpha: 0.5)
              : AppTheme.slate200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _showArchived ? Icons.inventory_2_rounded : Icons.archive_outlined,
            size: 16,
            color: _showArchived ? AppTheme.amber500 : AppTheme.slate400,
          ),
          const SizedBox(width: 7),
          Text(
            _showArchived ? 'Showing archived' : 'Show archived',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _showArchived ? AppTheme.amber500 : AppTheme.slate500,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _filters(List<String> departments, List<Office> offices) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 14,
        children: [
          _group(
            'Period',
            Icons.date_range_rounded,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final period in _Period.values)
                  _chip(
                    _periodLabel(period),
                    selected: _period == period,
                    onTap: period == _Period.custom
                        ? _pickCustom
                        : () => setState(() => _period = period),
                  ),
              ],
            ),
          ),
          _group(
            'Status',
            Icons.flag_outlined,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final status in _statuses)
                  _chip(
                    status,
                    selected: _status == status,
                    onTap: () => setState(() => _status = status),
                  ),
              ],
            ),
          ),
          _group(
            'Office',
            Icons.account_balance_outlined,
            _dropdown(
              value: _office,
              items: {
                _all: 'All offices',
                _unassigned: 'No office yet',
                for (final office in offices) office.id: office.name,
              },
              onChanged: (value) => setState(() => _office = value),
            ),
          ),
          _group(
            'Department',
            Icons.apartment_outlined,
            _dropdown(
              value: _department,
              items: {
                _all: 'All departments',
                for (final department in departments) department: department,
              },
              onChanged: (value) => setState(() => _department = value),
            ),
          ),
          _group(
            'Sort',
            Icons.sort_rounded,
            _dropdown(
              value: _sort,
              items: {for (final sort in _sorts) sort: sort},
              onChanged: (value) => setState(() => _sort = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String label, IconData icon, Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.slate400),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      child,
    ],
  );

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppTheme.maroon : AppTheme.slate100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.slate600,
        ),
      ),
    ),
  );

  Widget _dropdown({
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) => Container(
    constraints: const BoxConstraints(minWidth: 170, maxWidth: 280),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppTheme.slate100,
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        isExpanded: true,
        icon: const Icon(Icons.expand_more, size: 16, color: AppTheme.slate400),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.slate700,
        ),
        borderRadius: BorderRadius.circular(10),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => onChanged(value ?? _all),
      ),
    ),
  );
}

String _hours(double hours) {
  final rounded = (hours * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.toInt()}h'
      : '${rounded.toStringAsFixed(1)}h';
}

/// One Student Assistant: their figures for the period, and their records
/// when opened.
class _AssistantRow extends StatelessWidget {
  final AssistantAttendance row;
  final double maxHours;
  final bool compact;
  final bool expanded;
  final VoidCallback onToggle;

  const _AssistantRow({
    super.key,
    required this.row,
    required this.maxHours,
    required this.compact,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final user = row.assistant;
    final department = (user.department ?? '').trim();
    final figures = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Figure(label: 'Verified days', value: '${row.verifiedDays}'),
        _Figure(label: 'Verified hours', value: _hours(row.hours)),
        _Figure(
          label: 'Missed',
          value: '${row.missedTimeOuts}',
          color: row.missedTimeOuts > 0 ? AppTheme.red500 : null,
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? AppTheme.maroon200 : AppTheme.slate200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        avatarUrl: user.avatar,
                        initials: user.initials,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  user.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.slate900,
                                  ),
                                ),
                                if (row.clockedIn)
                                  const _Badge(
                                    'Clocked in',
                                    AppTheme.emerald500,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                row.officeLabel,
                                if (department.isNotEmpty) department,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!compact) ...[const SizedBox(width: 12), figures],
                      const SizedBox(width: 4),
                      Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppTheme.slate400,
                      ),
                    ],
                  ),
                  if (compact) ...[const SizedBox(height: 10), figures],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: maxHours <= 0 ? 0 : row.hours / maxHours,
                            minHeight: 6,
                            backgroundColor: AppTheme.slate100,
                            color: AppTheme.maroon,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        row.lastDate == null
                            ? 'No attendance in this period'
                            : 'Last: ${row.lastDate}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: AppTheme.slate100),
            if (row.records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No attendance in this period.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.slate500),
                ),
              )
            else
              for (final record in row.records)
                _RecordLine(record: record, compact: compact),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Figure({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 70),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? AppTheme.slate500).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color ?? AppTheme.slate800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

/// One attendance record under an opened Student Assistant, with what the
/// Head can do about it.
class _RecordLine extends StatelessWidget {
  final AttendanceRecord record;
  final bool compact;
  const _RecordLine({required this.record, required this.compact});

  @override
  Widget build(BuildContext context) {
    final (label, color) = record.isArchived
        ? ('Archived', AppTheme.amber500)
        : record.isInvalid
        ? ('Missed time-out', AppTheme.red500)
        : record.isActive
        ? ('Clocked in', AppTheme.emerald500)
        : ('Verified', AppTheme.slate500);
    final times = Text(
      record.isActive
          ? 'In ${record.timeIn}'
          : 'In ${record.timeIn} · Out ${record.timeOut}',
      style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 78 : 110,
            child: Text(
              record.date,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
              ),
            ),
          ),
          Expanded(
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      times,
                      const SizedBox(height: 4),
                      _Badge(label, color),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: times),
                      _Badge(label, color),
                    ],
                  ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              record.countsTowardHours ? _hours(record.totalHours ?? 0) : '—',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate700,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Record options',
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: AppTheme.slate400,
            ),
            onSelected: (action) => _act(context, action),
            itemBuilder: (_) => [
              if (record.isActive && !record.isArchived)
                const PopupMenuItem(
                  value: 'timeout',
                  child: Text('Record time-out'),
                ),
              if (record.isArchived)
                const PopupMenuItem(value: 'restore', child: Text('Restore'))
              else
                const PopupMenuItem(value: 'archive', child: Text('Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, String action) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    void say(String message, Color color) => messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
    switch (action) {
      case 'timeout':
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (picked == null || !context.mounted) return;
        final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
        final time =
            '$hour:${picked.minute.toString().padLeft(2, '0')} '
            '${picked.period == DayPeriod.am ? 'AM' : 'PM'}';
        final confirmed = await showConfirmDialog(
          context,
          title: 'Record Time-out',
          message:
              "Set ${record.studentName}'s time-out to $time on ${record.date} "
              '(timed in at ${record.timeIn})? The record will count as '
              'verified hours.',
          confirmLabel: 'Record',
          confirmColor: AppTheme.maroon,
        );
        if (!confirmed) return;
        final saved = await state.setManualTimeOut(record.id, time);
        say(
          saved
              ? 'Time-out recorded and verified'
              : "Couldn't save the time-out. Check your connection and try "
                    'again.',
          saved ? AppTheme.emerald500 : AppTheme.red500,
        );
      case 'archive':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Archive Record',
          message:
              "Archive ${record.studentName}'s record for ${record.date}? Its "
              'hours will no longer count toward their verified DTR hours or '
              'payroll. You can restore it from "Show archived".',
          confirmLabel: 'Archive',
          confirmColor: AppTheme.amber500,
        );
        if (!confirmed) return;
        final saved = await state.setAttendanceArchived(record.id, true);
        say(
          saved
              ? 'Record archived'
              : 'Could not save that; the record is unchanged.',
          saved ? AppTheme.emerald500 : AppTheme.red500,
        );
      case 'restore':
        final saved = await state.setAttendanceArchived(record.id, false);
        say(
          saved
              ? 'Record restored; it counts again'
              : 'Could not save that; the record is unchanged.',
          saved ? AppTheme.emerald500 : AppTheme.red500,
        );
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete Record',
          message:
              'Remove this attendance record? Archive it instead if you only '
              'want it out of the totals.',
          confirmLabel: 'Delete',
          confirmColor: AppTheme.red500,
        );
        if (!confirmed) return;
        final deleted = await state.deleteAttendance(record.id);
        say(
          deleted
              ? 'Attendance record deleted'
              : 'Could not delete that record.',
          deleted ? AppTheme.red500 : AppTheme.amber500,
        );
    }
  }
}
