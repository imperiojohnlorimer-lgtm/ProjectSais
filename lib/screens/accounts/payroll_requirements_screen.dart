import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Head-only screen: check each Student Assistant's payroll requirements
/// for a term — application requirements, Endorsement Letter, the term's
/// Contract of Appointment, and a DTR/Accomplishment Report for every month
/// they worked. The Admin's payroll for the term can only be approved once
/// everyone in it is checked, so a requirement with a mistake is returned
/// on its own, with a note, and the rest stay checked. A student who can't
/// complete theirs can be left out of the term's payroll.
class PayrollRequirementsScreen extends StatefulWidget {
  const PayrollRequirementsScreen({super.key});

  @override
  State<PayrollRequirementsScreen> createState() =>
      _PayrollRequirementsScreenState();
}

enum _Show { notReady, ready, leftOut, noHours, all }

// Darker than emerald500, so a check mark and "Check" read on their tints.
const _green = Color(0xFF047857);

const _monthAbbr = [
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

/// "Dec 1, 2026" from an ISO timestamp; anything else as it is.
String _when(String raw) {
  final at = DateTime.tryParse(raw)?.toLocal();
  if (at == null) return raw;
  return '${_monthAbbr[at.month - 1]} ${at.day}, ${at.year}';
}

/// A requirement's state: its icon, color and one-line wording.
({IconData icon, Color color, String label}) _lookOf(PayrollRequirement r) {
  if (r.isChecked) {
    return (icon: Icons.check_rounded, color: _green, label: 'Checked');
  }
  if (r.isResent) {
    return (
      icon: Icons.autorenew_rounded,
      color: AppTheme.blue500,
      label: 'New copy to check',
    );
  }
  if (r.isReturned) {
    return (
      icon: Icons.reply_rounded,
      color: AppTheme.red500,
      label: 'Returned',
    );
  }
  if (r.files.isEmpty) {
    return (
      icon: Icons.remove_rounded,
      color: AppTheme.slate400,
      label: 'Not on file',
    );
  }
  return (
    icon: Icons.hourglass_top_rounded,
    color: AppTheme.amber500,
    label: 'Waiting for your check',
  );
}

class _PayrollRequirementsScreenState extends State<PayrollRequirementsScreen> {
  late String _semester;
  late String _academicYear;
  _Show _show = _Show.notReady;
  String _search = '';
  bool _reminding = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _semester = RehireRecord.terms.contains(state.academicSemester)
        ? state.academicSemester
        : RehireRecord.terms.first;
    _academicYear = state.academicYear;
  }

  String get _termLabel => RehireRecord.termLabelFor(_academicYear, _semester);

  static bool _shows(_Show show, PayrollRecord row) => switch (show) {
    _Show.notReady => row.status == 'Incomplete',
    _Show.ready => row.isPayable,
    _Show.leftOut => row.status == 'Excluded',
    _Show.noHours => row.status == 'No hours',
    _Show.all => true,
  };

  /// The academic year in effect, the next one, and the three before it.
  List<String> _yearOptions(AppState state) {
    final years = [
      for (var shift = 1; shift >= -3; shift--)
        RehireRecord.shiftAcademicYear(state.academicYear, shift),
    ];
    return {...years, _academicYear}.toList()..sort((a, b) => b.compareTo(a));
  }

  Future<void> _remind(AppState state, List<PayrollRecord> rows) async {
    final notReady = rows.where((r) => r.status == 'Incomplete').toList();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Send Reminders',
      message:
          'Each Student Assistant who isn\'t ready for the $_termLabel '
          'payroll, and their supervisor, will be told what\'s still '
          'missing or returned. Requirements only waiting for your own '
          'check aren\'t mentioned.',
      confirmLabel: 'Send',
      confirmColor: AppTheme.maroon,
    );
    if (!confirmed || !mounted) return;
    setState(() => _reminding = true);
    final reminded = state.remindPayrollRequirements(notReady);
    setState(() => _reminding = false);
    AppSnackBar.show(
      context,
      reminded == 0
          ? 'Nothing to remind them of: what\'s left is waiting for your check.'
          : 'Reminded $reminded Student Assistant${reminded == 1 ? '' : 's'} '
                'and their supervisors.',
      type: reminded == 0 ? SnackType.info : SnackType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    final start = RehireRecord.termStart(_academicYear, _semester);
    final end = RehireRecord.termEnd(_academicYear, _semester);

    final rows = start == null || end == null
        ? <PayrollRecord>[]
        : (state.buildPayrollPreview(
            start: start,
            endInclusive: end,
            periodLabel: _termLabel,
          )..sort((a, b) => a.studentName.compareTo(b.studentName)));
    final query = _search.trim().toLowerCase();
    final shown = rows
        .where(
          (r) =>
              _shows(_show, r) &&
              (query.isEmpty ||
                  r.studentName.toLowerCase().contains(query) ||
                  (r.saId ?? '').toLowerCase().contains(query) ||
                  r.office.toLowerCase().contains(query)),
        )
        .toList();
    int count(_Show show) => rows.where((r) => _shows(show, r)).length;
    final notReady = count(_Show.notReady);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 18),
              _toolbar(state, isMobile),
              const SizedBox(height: 14),
              _Overview(
                termLabel: _termLabel,
                range: start == null || end == null
                    ? null
                    : '${_monthAbbr[start.month - 1]} ${start.day} – '
                          '${_monthAbbr[end.month - 1]} ${end.day}, ${end.year}',
                ready: count(_Show.ready),
                notReady: notReady,
                leftOut: count(_Show.leftOut),
                reminding: _reminding,
                onRemind: () => _remind(state, rows),
              ),
              const SizedBox(height: 22),
              _tabs(count),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                _empty(rows.isEmpty, notReady)
              else
                for (final row in shown)
                  _StudentCard(
                    key: ValueKey('${row.studentId}|$_termLabel'),
                    row: row,
                    state: state,
                    initiallyOpen: _show == _Show.notReady,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 3,
        height: 34,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: AppTheme.maroon,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payroll Requirements',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
                letterSpacing: -0.4,
                height: 1.1,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Check each Student Assistant\'s requirements. The Admin can '
              'approve the term\'s payroll once everyone is checked.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.slate500,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// Term (a segmented switch), academic year and search, in one row on a
  /// wide screen.
  Widget _toolbar(AppState state, bool isMobile) {
    final terms = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.slate100,
        borderRadius: BorderRadius.circular(12),
      ),
      // On a phone the three share the full width; on a wide screen each
      // takes its own (the toolbar Row gives no width to share).
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final term in RehireRecord.terms)
            if (isMobile)
              Expanded(
                child: _SegmentButton(
                  label: term.replaceAll('Semester', 'Sem'),
                  selected: _semester == term,
                  onTap: () => setState(() => _semester = term),
                ),
              )
            else
              _SegmentButton(
                label: term,
                selected: _semester == term,
                onTap: () => setState(() => _semester = term),
              ),
        ],
      ),
    );

    final year = PopupMenuButton<String>(
      tooltip: 'Academic year',
      initialValue: _academicYear,
      onSelected: (value) => setState(() => _academicYear = value),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        for (final option in _yearOptions(state))
          PopupMenuItem(
            value: option,
            child: Text(
              'AY $option',
              style: TextStyle(
                fontWeight: option == _academicYear
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              size: 16,
              color: AppTheme.slate500,
            ),
            const SizedBox(width: 8),
            Text(
              'AY $_academicYear',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: AppTheme.slate400,
            ),
          ],
        ),
      ),
    );

    final search = SizedBox(
      height: 42,
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AppTheme.slate800,
        ),
        decoration: InputDecoration(
          hintText: 'Search name, SA ID or office',
          hintStyle: const TextStyle(fontSize: 13, color: AppTheme.slate400),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: AppTheme.slate400,
          ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.slate200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.maroon200, width: 1.5),
          ),
        ),
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          terms,
          const SizedBox(height: 10),
          Row(
            children: [
              year,
              const SizedBox(width: 10),
              Expanded(child: search),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        terms,
        const SizedBox(width: 10),
        year,
        const Spacer(),
        SizedBox(width: 300, child: search),
      ],
    );
  }

  Widget _tabs(int Function(_Show) count) {
    const labels = {
      _Show.notReady: 'Not ready',
      _Show.ready: 'Ready',
      _Show.leftOut: 'Left out',
      _Show.noHours: 'No hours',
      _Show.all: 'All',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final show in _Show.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _TabPill(
                label: labels[show]!,
                count: count(show),
                selected: _show == show,
                onTap: () => setState(() => _show = show),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(bool nobody, int notReady) {
    final (icon, title, body) = nobody
        ? (
            Icons.people_outline,
            'No Student Assistants this term',
            'Active Student Assistants, and anyone with hours in the term, '
                'are listed here.',
          )
        : _show == _Show.notReady && notReady == 0
        ? (
            Icons.task_alt_rounded,
            'Everyone is checked',
            'No one is holding up the $_termLabel payroll.',
          )
        : (
            Icons.search_off_rounded,
            'No matches',
            'Try another filter or search.',
          );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: icon == Icons.task_alt_rounded
                  ? AppTheme.emerald50
                  : AppTheme.slate100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 28,
              color: icon == Icons.task_alt_rounded
                  ? _green
                  : AppTheme.slate400,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppTheme.maroon : AppTheme.slate500,
        ),
      ),
    ),
  );
}

class _TabPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.maroon : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.maroon : AppTheme.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppTheme.slate600,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : AppTheme.slate100,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppTheme.slate500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// How far along the term's payroll is: the count ready, a bar split by
/// Ready / Not ready / Left out, and the reminder button.
class _Overview extends StatelessWidget {
  final String termLabel;
  final String? range;
  final int ready;
  final int notReady;
  final int leftOut;
  final bool reminding;
  final VoidCallback onRemind;

  const _Overview({
    required this.termLabel,
    required this.range,
    required this.ready,
    required this.notReady,
    required this.leftOut,
    required this.reminding,
    required this.onRemind,
  });

  @override
  Widget build(BuildContext context) {
    final inPayroll = ready + notReady;
    final allSet = inPayroll > 0 && notReady == 0;
    final status = inPayroll == 0
        ? 'No one has hours in this term yet.'
        : allSet
        ? 'Everyone is checked. The Admin can approve this payroll.'
        : 'The payroll is waiting on $notReady Student '
              'Assistant${notReady == 1 ? '' : 's'}.';

    final remind = OutlinedButton.icon(
      onPressed: notReady == 0 || reminding ? null : onRemind,
      icon: const Icon(Icons.notifications_active_outlined, size: 16),
      label: const Text('Remind those not ready'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.maroon,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppTheme.maroon200),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    Widget legend(Color color, String label, int value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
        const SizedBox(width: 5),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.slate800,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final headline = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${termLabel.toUpperCase()} PAYROLL',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate400,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$ready',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        letterSpacing: -1,
                        height: 1,
                      ),
                    ),
                    TextSpan(
                      text: ' of $inPayroll ready',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    allSet
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    size: 15,
                    color: allSet ? _green : AppTheme.amber500,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      status,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (narrow)
                headline
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: headline),
                    const SizedBox(width: 16),
                    remind,
                  ],
                ),
              const SizedBox(height: 18),
              _SplitBar(
                parts: [
                  (ready, AppTheme.emerald500, 'Ready'),
                  (notReady, AppTheme.amber500, 'Not ready'),
                  (leftOut, AppTheme.slate300, 'Left out'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  legend(AppTheme.emerald500, 'Ready', ready),
                  legend(AppTheme.amber500, 'Not ready', notReady),
                  legend(AppTheme.slate300, 'Left out', leftOut),
                  if (range != null)
                    Text(
                      '$range · a DTR for each month worked',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate400,
                      ),
                    ),
                ],
              ),
              if (narrow) ...[
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: remind),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A 10px bar split into [parts] by count, each segment rounded and kept
/// apart by a 2px gap; an empty grey track when there's nothing to show.
/// Each segment names itself on hover.
class _SplitBar extends StatelessWidget {
  final List<(int, Color, String)> parts;
  const _SplitBar({required this.parts});

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.$1 > 0).toList();
    if (shown.isEmpty) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: AppTheme.slate100,
          borderRadius: BorderRadius.circular(5),
        ),
      );
    }
    return SizedBox(
      height: 10,
      child: Row(
        children: [
          for (final (i, (value, color, label)) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              flex: value,
              child: Tooltip(
                message: '$label: $value',
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One Student Assistant's checklist for the term.
class _StudentCard extends StatefulWidget {
  final PayrollRecord row;
  final AppState state;
  final bool initiallyOpen;

  const _StudentCard({
    super.key,
    required this.row,
    required this.state,
    required this.initiallyOpen,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  late bool _open = widget.initiallyOpen;
  bool _saving = false;

  PayrollRecord get row => widget.row;

  String get _initials {
    final parts = row.studentName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return '$first$last'.toUpperCase();
  }

  Future<void> _leaveOut() async {
    final reason = await _askForNote(
      context,
      title: 'Leave Out of This Payroll',
      intro:
          '${row.studentName} won\'t be paid in the ${row.periodLabel} '
          'payroll, and it will no longer wait for them. They\'re told why.',
      label: 'Reason',
      hint: 'e.g. Resigned in October; requirements not completed',
      confirmLabel: 'Leave Out',
    );
    if (reason == null || !mounted) return;
    await _run(
      () => widget.state.excludeFromPayroll(row, reason),
      done: '${row.studentName} was left out of this payroll.',
    );
  }

  Future<void> _putBack() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Put Back in the Payroll',
      message:
          '${row.studentName} will be paid in the ${row.periodLabel} payroll '
          'once their requirements are checked, and the payroll will wait '
          'for them again.',
      confirmLabel: 'Put Back',
      confirmColor: AppTheme.maroon,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => widget.state.includeInPayroll(row),
      done: '${row.studentName} is back in this payroll.',
    );
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted && done != null) {
        AppSnackBar.show(context, done, type: SnackType.success);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(context, 'Could not save: $e', type: SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requirements = row.requirements;
    final checked = requirements.where((r) => r.isChecked).length;
    final (statusText, statusColor, statusTint) = switch (row.status) {
      'Excluded' => ('Left out', AppTheme.slate500, AppTheme.slate100),
      'No hours' => ('No hours', AppTheme.slate500, AppTheme.slate100),
      'Incomplete' => ('Not ready', const Color(0xFFB45309), AppTheme.amber50),
      _ => ('Ready', _green, AppTheme.emerald50),
    };
    final hiring = requirements
        .where((r) => r.kind != PayrollRequirementKind.dtr)
        .toList();
    final monthly = requirements
        .where((r) => r.kind == PayrollRequirementKind.dtr)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _open ? 0.05 : 0.02),
            blurRadius: _open ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.maroon.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.maroon,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                row.studentName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                ),
                              ),
                            ),
                            if ((row.saId ?? '').isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                row.saId!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate400,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row.office.isEmpty ? 'Unassigned office' : row.office,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
                                child: _ItemStrip(requirements: requirements),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$checked/${requirements.length}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slate500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: AppTheme.slate400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: AppTheme.slate100),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (row.exclusion case final left?)
                    _Callout(
                      icon: Icons.person_off_outlined,
                      color: AppTheme.slate500,
                      tint: AppTheme.slate50,
                      text:
                          'Left out of this payroll by ${left.by}: '
                          '"${left.reason}"',
                    ),
                  if (row.status == 'No hours')
                    const _Callout(
                      icon: Icons.info_outline_rounded,
                      color: AppTheme.slate500,
                      tint: AppTheme.slate50,
                      text:
                          'No hours in this term yet, so nothing to pay. '
                          'Their requirements can still be checked.',
                    ),
                  _sectionLabel('Hiring documents'),
                  for (final (i, r) in hiring.indexed) ...[
                    if (i > 0)
                      const Divider(height: 1, color: AppTheme.slate100),
                    _RequirementTile(
                      key: ValueKey(r.key),
                      row: row,
                      requirement: r,
                      state: widget.state,
                    ),
                  ],
                  if (monthly.isNotEmpty) ...[
                    _sectionLabel('Monthly DTR/Accomplishment Reports'),
                    for (final (i, r) in monthly.indexed) ...[
                      if (i > 0)
                        const Divider(height: 1, color: AppTheme.slate100),
                      _RequirementTile(
                        key: ValueKey(r.key),
                        row: row,
                        requirement: r,
                        state: widget.state,
                      ),
                    ],
                  ],
                  const SizedBox(height: 6),
                  const Divider(height: 1, color: AppTheme.slate100),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : row.exclusion == null
                          ? _leaveOut
                          : _putBack,
                      icon: Icon(
                        row.exclusion == null
                            ? Icons.person_remove_outlined
                            : Icons.person_add_alt_outlined,
                        size: 16,
                      ),
                      label: Text(
                        row.exclusion == null
                            ? 'Leave out of this payroll'
                            : 'Put back in this payroll',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.slate500,
                        textStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: AppTheme.slate400,
        letterSpacing: 0.7,
      ),
    ),
  );
}

/// One short segment per requirement, colored by its state, so a collapsed
/// card shows at a glance what's done. Each names itself on hover.
class _ItemStrip extends StatelessWidget {
  final List<PayrollRequirement> requirements;
  const _ItemStrip({required this.requirements});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 6,
    child: Row(
      children: [
        for (final (i, r) in requirements.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: Tooltip(
              message: '${r.label}: ${_lookOf(r).label}',
              child: Container(
                decoration: BoxDecoration(
                  color: r.isChecked
                      ? AppTheme.emerald500
                      : r.files.isEmpty && !r.isReturned
                      ? AppTheme.slate200
                      : _lookOf(r).color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color tint;
  final String text;

  const _Callout({
    required this.icon,
    required this.color,
    required this.tint,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.slate700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One requirement: its state, files, and Check / Return.
class _RequirementTile extends StatefulWidget {
  final PayrollRecord row;
  final PayrollRequirement requirement;
  final AppState state;

  const _RequirementTile({
    super.key,
    required this.row,
    required this.requirement,
    required this.state,
  });

  @override
  State<_RequirementTile> createState() => _RequirementTileState();
}

class _RequirementTileState extends State<_RequirementTile> {
  bool _saving = false;
  String? _opening;

  PayrollRequirement get r => widget.requirement;

  /// Where a missing file comes from.
  String get _missingText => switch (r.kind) {
    PayrollRequirementKind.requirements =>
      'No files from an approved application in SAIS.',
    PayrollRequirementKind.endorsement =>
      'Not generated yet. Make it from the student\'s application on '
          'Applications.',
    PayrollRequirementKind.contract =>
      'No contract for this term yet. It\'s made on Applications, or on '
          'Rehiring for a rehired student.',
    PayrollRequirementKind.dtr =>
      'Not sent yet. The supervisor sends it from DTR/Accomplishment Report.',
  };

  Future<void> _open(PayrollRequirementFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _opening = file.ref);
    try {
      final url = await SupabaseStorageService.instance.openableUrl(
        path: file.storagePath,
        storedUrl: file.downloadUrl,
      );
      if (url == null) throw Exception('No file is attached.');
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('The browser could not open the file.');
    } catch (e) {
      AppSnackBar.showWithMessenger(
        messenger,
        'Could not open ${file.name}: $e',
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  /// Whether it saved.
  Future<bool> _save(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(context, 'Could not save: $e', type: SnackType.error);
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _check() async {
    if (r.files.isEmpty) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'No Copy in SAIS',
        message:
            'There\'s no copy of ${r.label} in SAIS. Check it only if you '
            'have the paper copy and it\'s in order.',
        confirmLabel: 'Check',
        confirmColor: AppTheme.maroon,
      );
      if (!confirmed || !mounted) return;
    }
    await _save(() => widget.state.checkPayrollRequirement(widget.row, r));
  }

  Future<void> _return() async {
    final note = await _askForNote(
      context,
      title: 'Return ${r.label}',
      intro:
          'Only this requirement goes back; the others stay as they are. '
          '${widget.row.studentName} and their supervisor are told what to '
          'correct.',
      label: 'What needs correcting',
      hint: r.kind == PayrollRequirementKind.dtr
          ? 'e.g. Sep 12 is missing its time-out; no supervisor signature'
          : 'e.g. The contract isn\'t signed by the student',
      confirmLabel: 'Return',
    );
    if (note == null || !mounted) return;
    final saved = await _save(
      () => widget.state.returnPayrollRequirement(widget.row, r, note),
    );
    if (saved && mounted) {
      AppSnackBar.show(
        context,
        'Returned ${r.label}. ${widget.row.studentName} and their '
        'supervisor were told.',
        type: SnackType.success,
      );
    }
  }

  ButtonStyle _style(
    Color background,
    Color foreground, {
    Color? border,
  }) => ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(background),
    foregroundColor: WidgetStatePropertyAll(foreground),
    iconColor: WidgetStatePropertyAll(foreground),
    overlayColor: WidgetStatePropertyAll(foreground.withValues(alpha: 0.08)),
    side: border == null
        ? null
        : WidgetStatePropertyAll(BorderSide(color: border)),
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    iconSize: const WidgetStatePropertyAll(15),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontFamily: 'Inter',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  List<Widget> _actions() {
    if (r.isChecked) {
      return [
        TextButton.icon(
          onPressed: _saving
              ? null
              : () => _save(
                  () => widget.state.clearPayrollRequirement(widget.row, r),
                ),
          icon: const Icon(Icons.undo_rounded),
          label: const Text('Undo'),
          style: _style(Colors.transparent, AppTheme.slate500),
        ),
      ];
    }
    return [
      FilledButton.icon(
        onPressed: _saving ? null : _check,
        icon: _saving
            ? SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: r.files.isEmpty ? _green : Colors.white,
                ),
              )
            : const Icon(Icons.check_rounded),
        label: const Text('Check'),
        // With nothing on file, checking is the exception (a paper copy),
        // so it doesn't look like the obvious next step.
        style: r.files.isEmpty
            ? _style(Colors.white, _green, border: AppTheme.slate200)
            : _style(_green, Colors.white),
      ),
      // Nothing on file means nothing to send back.
      if (r.files.isNotEmpty && (!r.isReturned || r.isResent))
        OutlinedButton.icon(
          onPressed: _saving ? null : _return,
          icon: const Icon(Icons.reply_rounded),
          label: const Text('Return'),
          style: _style(
            Colors.white,
            AppTheme.red500,
            border: AppTheme.slate200,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final look = _lookOf(r);
    final mark = r.mark;
    final detail = r.isChecked
        ? 'Checked by ${mark!.by} · ${_when(mark.at)}'
        : r.isResent
        ? 'A new copy came in after you returned it. Check it again.'
        : r.isReturned
        ? 'Returned ${_when(mark!.at)}'
        : r.files.isEmpty
        ? _missingText
        : 'Waiting for your check.';

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          r.label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: AppTheme.slate500,
          ),
        ),
        if (r.isReturned && !r.isResent && (mark?.note ?? '').isNotEmpty)
          _Callout(
            icon: Icons.chat_bubble_outline_rounded,
            color: AppTheme.red500,
            tint: AppTheme.red50,
            text: '"${mark!.note}"',
          ),
        if (r.files.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, file) in r.files.indexed)
                _FileChip(
                  file: file,
                  note: r.kind == PayrollRequirementKind.dtr && i > 0
                      ? 'earlier copy'
                      : null,
                  opening: _opening == file.ref,
                  onOpen: file.canOpen && _opening == null
                      ? () => _open(file)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: look.label,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: r.isChecked
                        ? _green
                        : look.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    look.icon,
                    size: 16,
                    color: r.isChecked ? Colors.white : look.color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: wide
                    ? body
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          body,
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: _actions()),
                        ],
                      ),
              ),
              if (wide) ...[
                const SizedBox(width: 12),
                Wrap(spacing: 8, runSpacing: 8, children: _actions()),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A file on record, as a chip that opens it.
class _FileChip extends StatelessWidget {
  final PayrollRequirementFile file;
  final String? note;
  final bool opening;
  final VoidCallback? onOpen;

  const _FileChip({
    required this.file,
    required this.note,
    required this.opening,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final extra = [?note, ?file.date].join(' · ');
    return Material(
      color: AppTheme.slate50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: AppTheme.slate200),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 14,
                color: AppTheme.slate500,
              ),
              const SizedBox(width: 6),
              // Both shrink on a narrow screen rather than overflow.
              Flexible(
                flex: 3,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
              ),
              if (extra.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  flex: 2,
                  child: Text(
                    extra,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.slate400,
                    ),
                  ),
                ),
              ],
              if (file.canOpen) ...[
                const SizedBox(width: 6),
                opening
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: AppTheme.maroon,
                        ),
                      )
                    : const Icon(
                        Icons.open_in_new_rounded,
                        size: 13,
                        color: AppTheme.maroon,
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a required note (a reason to return or leave out). Returns
/// null if cancelled.
Future<String?> _askForNote(
  BuildContext context, {
  required String title,
  required String intro,
  required String label,
  required String hint,
  required String confirmLabel,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _NoteDialog(
    title: title,
    intro: intro,
    label: label,
    hint: hint,
    confirmLabel: confirmLabel,
  ),
);

class _NoteDialog extends StatefulWidget {
  final String title;
  final String intro;
  final String label;
  final String hint;
  final String confirmLabel;

  const _NoteDialog({
    required this.title,
    required this.intro,
    required this.label,
    required this.hint,
    required this.confirmLabel,
  });

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please write a short note.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    title: Text(
      widget.title,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
    ),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.intro,
            style: const TextStyle(
              color: AppTheme.slate600,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              errorText: _error,
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.maroon,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
