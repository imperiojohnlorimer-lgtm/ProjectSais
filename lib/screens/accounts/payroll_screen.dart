import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/csv.dart';
import '../../utils/csv_export.dart';
import '../../widgets/export_csv_button.dart';
import '../../widgets/shared_widgets.dart';
import 'payroll_sheet_editor.dart';

/// Admin screen: approve and release payroll for a pay period — a whole
/// semester, not a single month.
///
/// For every active Student Assistant — and anyone else with hours in the
/// period, such as a student not rehired before payroll ran — the System
/// retrieves their DTR (attendance) hours and the Head's check of their
/// payroll requirements (application requirements, Endorsement Letter,
/// Contract of Appointment, a DTR/Accomplishment Report for each month
/// worked). Anyone with a requirement not yet checked, or already paid for
/// some of these days under another period, is 'Incomplete' — and the
/// period's payroll, approved for everyone at once, waits for them unless
/// the Head leaves them out. The payable amount is computed from total hours rendered
/// at a flat ₱25.00/hour; since a semester spans several months, the
/// 25.0–40.0 hour/month rule (see [PayrollRecord]) is applied one calendar
/// month at a time and the capped monthly amounts are summed into the
/// semester total — working below the minimum in any month is flagged with
/// a warning rather than blocked outright.
///
/// Payroll moves through two Admin-driven steps:
///  1. Approve — locks in and records the computed amount ('Approved').
///  2. Release — the actual payout moment ('Released'), which is when the
///     Student Assistant is notified.
///
/// The printed Hourly Wage Payroll is prepared separately, in the
/// [PayrollSheetEditor]: an editable copy of the period's payroll that the
/// Admin can correct, save, and download.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  late String _semester;
  late String _academicYear;
  late DateTime _start;
  late DateTime _end;

  /// 'approve' or 'release' while that step is saving — the button shows a
  /// spinner and the rest of the actions wait.
  String? _busyAction;

  /// Whether the filters are unfolded on a phone.
  bool _filtersOpen = false;

  /// The payroll sheet open in the editor, if any.
  PayrollSheet? _sheet;

  String _campusFilter = 'All';
  String _departmentFilter = 'All';
  String _officeFilter = 'All';

  /// The cards that are opened. A card belongs to its pay period, so
  /// choosing another one starts them all closed.
  final Set<String> _openCards = {};

  String _openKey(PayrollRecord p) =>
      '${p.studentId}|${_isoDate(_start)}|${_isoDate(_end)}';

  /// The status tab picking which cards the list shows ('All' or a status).
  /// Only the list follows it: Approve and Release do not.
  String _statusTab = 'All';

  /// The Office filter's choice for assistants not in an office: their
  /// records' office is blank.
  static const _unassignedOffice = '';

  static const _semesters = RehireRecord.terms;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    // A term the dropdown doesn't list would crash it.
    _semester = _semesters.contains(state.academicSemester)
        ? state.academicSemester
        : _semesters.first;
    _academicYear = state.academicYear;
    final year = DateTime.now().year;
    _start = DateTime(year, 8, 1);
    _end = DateTime(year, 12, 31);
    _applyDefaultRange();
  }

  /// The chosen term's usual dates in the academic year — Aug–Dec, Jan–May,
  /// or Jun–Jul for Summer — always editable afterward in case the actual
  /// dates differ. Left alone until the year reads as one, so typing it
  /// doesn't move the dates through year 2 on the way.
  void _applyDefaultRange() {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(_academicYear.trim());
    if (match == null) return;
    final y1 = int.parse(match.group(1)!);
    final y2 = int.parse(match.group(2)!);
    switch (_semester) {
      case '1st Semester':
        _start = DateTime(y1, 8, 1);
        _end = DateTime(y1, 12, 31);
      case '2nd Semester':
        _start = DateTime(y2, 1, 1);
        _end = DateTime(y2, 5, 31);
      default:
        _start = DateTime(y2, 6, 1);
        _end = DateTime(y2, 7, 31);
    }
  }

  String get _periodLabel => '$_semester, AY $_academicYear';

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : _end;
    // Wide enough to always include the date already set — the picker
    // refuses an initial date outside its range.
    final now = DateTime.now();
    final first = DateTime(now.year - 3);
    final last = DateTime(now.year + 3, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: current.isBefore(first) ? current : first,
      lastDate: current.isAfter(last) ? current : last,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  /// [preview] is the whole period, whatever the filters show: the payroll
  /// is approved for everyone in it at once.
  Future<void> _confirmApprove(
    BuildContext context,
    AppState state,
    List<PayrollRecord> preview,
  ) async {
    final ready = preview.where((p) => p.status == 'Ready').toList();
    if (ready.isEmpty || AppState.payrollHeldBy(preview).isNotEmpty) return;
    final total = ready.fold<double>(0, (sum, p) => sum + p.grossPay);
    final excluded = preview.where((p) => p.status == 'Excluded').length;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve Payroll',
      message:
          'This will approve and record pay for all ${ready.length} '
          'Student Assistant(s) in $_periodLabel, every campus and office, '
          'totaling ${_peso(total)}. Payout is not released to students '
          'until you separately click "Release".'
          '${excluded == 0 ? '' : '\n\n$excluded student(s) the Head left '
                    'out of this payroll won\'t be paid in it.'}',
      confirmLabel: 'Approve',
      confirmColor: AppTheme.maroon,
    );
    if (!confirmed || !context.mounted) return;

    setState(() => _busyAction = 'approve');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (count, approvedTotal) = await state.approvePayroll(preview);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Approved payroll for $count Student Assistant(s) — '
            '${_peso(approvedTotal)} total. Release it when ready.',
          ),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not approve payroll: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _confirmRelease(
    BuildContext context,
    AppState state,
    List<PayrollRecord> approved,
  ) async {
    if (approved.isEmpty) return;
    final total = approved.fold<double>(0, (sum, p) => sum + p.grossPay);

    final confirmed = await showConfirmDialog(
      context,
      title: 'Release Payout',
      message:
          'This will release payout to ${approved.length} Student '
          'Assistant(s) for $_periodLabel, totaling '
          '${_peso(total)}, and notify each of them. This '
          'cannot be undone.',
      confirmLabel: 'Release',
      confirmColor: AppTheme.emerald500,
    );
    if (!confirmed || !context.mounted) return;

    setState(() => _busyAction = 'release');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (count, releasedTotal) = await state.releasePayroll(approved);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Released payout for $count Student Assistant(s) — '
            '${_peso(releasedTotal)} total. They\'ve been notified.',
          ),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not release payout: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Rows for the printed payroll, straight from the system: every student
  /// in the period who can be paid (Ready, Approved or Released), across all
  /// campuses. Anyone not ready, left out, or with no hours isn't on it.
  /// Names are surname first, "Dela Cruz, Juan S.", from each account's
  /// name parts; an account whose name isn't split yet, or that's gone,
  /// keeps its name as saved.
  List<PayrollSheetEntry> _systemEntries(AppState state) {
    final start = _isoDate(_start);
    final end = _isoDate(_end);
    final usersById = {for (final u in state.users) u.id: u};
    return PayrollSheet.fromRecords(
      periodStart: start,
      periodEnd: end,
      periodLabel: _periodLabel,
      nameOf: (record) =>
          usersById[record.studentId]?.surnameFirstName ?? record.studentName,
      records: state
          .buildPayrollPreview(
            start: _start,
            endInclusive: _end,
            periodLabel: _periodLabel,
          )
          .where((p) => p.isPayable)
          .toList(),
    ).entries;
  }

  /// Opens the period's saved payroll sheet, or starts one from the system's
  /// payroll data — keeping the header fields and signatories of the last
  /// sheet the Admin saved.
  void _openSheet(AppState state) {
    final start = _isoDate(_start);
    final end = _isoDate(_end);
    final saved = state.payrollSheetFor(start, end);
    setState(() {
      _sheet =
          saved?.copyWith(periodLabel: _periodLabel) ??
          PayrollSheet.fromRecords(
            periodStart: start,
            periodEnd: end,
            periodLabel: _periodLabel,
            records: const [],
            previous: state.latestPayrollSheet,
          ).copyWith(entries: _systemEntries(state));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sheet = _sheet;
    if (sheet != null) {
      return PayrollSheetEditor(
        key: ValueKey(sheet.id),
        sheet: sheet,
        systemEntries: () => _systemEntries(context.read<AppState>()),
        onClose: () => setState(() => _sheet = null),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    final hasSavedSheet =
        state.payrollSheetFor(_isoDate(_start), _isoDate(_end)) != null;

    final allPreview = state.buildPayrollPreview(
      start: _start,
      endInclusive: _end,
      periodLabel: _periodLabel,
    );

    final campusOptions = [
      'All',
      ...{
        for (final p in allPreview)
          if ((p.campus ?? '').trim().isNotEmpty) p.campus!.trim(),
      }.toList()..sort(),
    ];
    final departmentOptions = [
      'All',
      ...{
        for (final p in allPreview)
          if ((p.department ?? '').trim().isNotEmpty) p.department!.trim(),
      }.toList()..sort(),
    ];
    final officeOptions = [
      'All',
      ...{
        for (final p in allPreview)
          if (p.office.trim().isNotEmpty) p.office.trim(),
      }.toList()..sort(),
      if (allPreview.any((p) => p.office.trim().isEmpty)) _unassignedOffice,
    ];
    if (!campusOptions.contains(_campusFilter)) _campusFilter = 'All';
    if (!departmentOptions.contains(_departmentFilter))
      _departmentFilter = 'All';
    if (!officeOptions.contains(_officeFilter)) _officeFilter = 'All';

    final preview = allPreview.where((p) {
      if (_campusFilter != 'All' && (p.campus ?? '').trim() != _campusFilter) {
        return false;
      }
      if (_departmentFilter != 'All' &&
          (p.department ?? '').trim() != _departmentFilter) {
        return false;
      }
      if (_officeFilter != 'All' && p.office.trim() != _officeFilter) {
        return false;
      }
      return true;
    }).toList();

    // Approving is for the whole period at once, so it goes by everyone in
    // it whatever the filters show; releasing goes by what's listed.
    final allReady = allPreview.where((p) => p.status == 'Ready').toList();
    final held = AppState.payrollHeldBy(allPreview);
    final ready = preview.where((p) => p.status == 'Ready').toList();
    final incomplete = preview.where((p) => p.status == 'Incomplete').toList();
    final excluded = preview.where((p) => p.status == 'Excluded').toList();
    final approved = preview.where((p) => p.status == 'Approved').toList();
    final released = preview.where((p) => p.status == 'Released').toList();
    final readyTotal = allReady.fold<double>(0, (sum, p) => sum + p.grossPay);
    final approvedTotal = approved.fold<double>(
      0,
      (sum, p) => sum + p.grossPay,
    );
    final noHours = preview.where((p) => p.status == 'No hours').length;

    // The tabs count what the campus / department / office filters leave, and
    // only choose which of those cards are listed.
    final counts = <String, int>{
      'All': preview.length,
      for (final status in _tabStatuses)
        status: preview.where((p) => p.status == status).length,
    };
    final tab = _statusTab == 'No hours' && noHours == 0 ? 'All' : _statusTab;
    final shown = tab == 'All'
        ? preview
        : preview.where((p) => p.status == tab).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: _header(preview),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _periodCard(
                  isMobile: isMobile,
                  campusOptions: campusOptions,
                  departmentOptions: departmentOptions,
                  officeOptions: officeOptions,
                ),
                const SizedBox(height: 12),
                _summaryCard(
                  state: state,
                  allPreview: allPreview,
                  allReady: allReady,
                  held: held,
                  ready: ready,
                  incomplete: incomplete,
                  excluded: excluded,
                  approved: approved,
                  released: released,
                  noHours: noHours,
                  readyTotal: readyTotal,
                  approvedTotal: approvedTotal,
                  hasSavedSheet: hasSavedSheet,
                ),
                if (held.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _HeldUpCard(held: held),
                ],
                const SizedBox(height: 22),
                _listHeader(shown.length),
                const SizedBox(height: 10),
                _statusTabs(counts, tab),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        preview.isEmpty
                            ? 'No active Student Assistants found.'
                            : 'No Student Assistants with this status.',
                        style: const TextStyle(color: AppTheme.slate500),
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Two cards per row once there's room, so a desktop
                      // screen isn't one long narrow column.
                      const gap = 12.0;
                      final columns = constraints.maxWidth >= 1000 ? 2 : 1;
                      final cardWidth =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final p in shown)
                            SizedBox(
                              key: ValueKey(p.studentId),
                              width: cardWidth,
                              child: _PayrollRow(
                                record: p,
                                open: _openCards.contains(_openKey(p)),
                                onToggle: () => setState(() {
                                  if (!_openCards.remove(_openKey(p))) {
                                    _openCards.add(_openKey(p));
                                  }
                                }),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// What the page lists for the period, as a spreadsheet: hours, pay and
  /// whatever still holds each person up.
  void _export(List<PayrollRecord> rows) {
    saveCsv('payroll-${csvFileSafe(_periodLabel)}.csv', [
      [
        'Student Assistant',
        'SA ID',
        'Office',
        'Campus',
        'Department',
        'Period',
        'Status',
        'Hours worked',
        'Payable hours',
        'Gross pay (PHP)',
        'Still to be checked',
      ],
      for (final p in rows)
        [
          p.studentName,
          p.saId,
          p.office,
          p.campus,
          p.department,
          _periodLabel,
          switch (p.status) {
            'Incomplete' => 'Not ready',
            'Excluded' => 'Left out',
            final other => other,
          },
          double.parse(p.hoursWorked.toStringAsFixed(2)),
          double.parse(p.payableHours.toStringAsFixed(2)),
          double.parse(p.grossPay.toStringAsFixed(2)),
          p.unchecked.map((r) => r.label).join('; '),
        ],
    ]);
  }

  Widget _header(List<PayrollRecord> rows) => Row(
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
                Icon(Icons.payments_rounded, size: 17, color: AppTheme.maroon),
                SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Payroll',
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
              'Approve and release each semester\'s pay · '
              '${_peso(PayrollRecord.ratePerHour)}/hr · '
              '${PayrollRecord.minimumMonthlyHours.toStringAsFixed(0)}–'
              '${PayrollRecord.maximumMonthlyHours.toStringAsFixed(0)} hrs a month',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.slate500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      ExportCsvButton(onPressed: rows.isEmpty ? null : () => _export(rows)),
    ],
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
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
    child: child,
  );

  Widget _cardLabel(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      color: AppTheme.slate500,
      letterSpacing: 0.6,
    ),
  );

  Widget _periodCard({
    required bool isMobile,
    required List<String> campusOptions,
    required List<String> departmentOptions,
    required List<String> officeOptions,
  }) {
    const gap = 12.0;
    final semesterField = DropdownButtonFormField<String>(
      key: ValueKey('semester-$_semester'),
      initialValue: _semester,
      isExpanded: true,
      style: _fieldText,
      decoration: _field('Semester'),
      items: _semesters
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(s, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() {
        _semester = v ?? _semester;
        _applyDefaultRange();
      }),
    );
    final yearField = TextFormField(
      initialValue: _academicYear,
      style: _fieldText,
      decoration: _field('Academic Year', hint: 'e.g. 2026-2027'),
      onChanged: (v) => setState(() {
        _academicYear = v;
        _applyDefaultRange();
      }),
    );
    final startField = _dateField('Start', _start, isStart: true);
    final endField = _dateField('End', _end, isStart: false);

    Widget filter(
      String label,
      String plural,
      String value,
      List<String> options,
      ValueChanged<String> onChanged,
    ) => DropdownButtonFormField<String>(
      // Keyed on the value so a filter reset to "All" (its option went
      // away) shows as reset.
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      style: _fieldText,
      decoration: _field(label),
      items: options
          .map(
            (o) => DropdownMenuItem(
              value: o,
              child: Text(
                o == 'All'
                    ? 'All $plural'
                    : o == _unassignedOffice
                    ? 'Unassigned'
                    : o,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => onChanged(v ?? 'All')),
    );

    final filters = [
      filter(
        'Campus',
        'campuses',
        _campusFilter,
        campusOptions,
        (v) => _campusFilter = v,
      ),
      filter(
        'Department',
        'departments',
        _departmentFilter,
        departmentOptions,
        (v) => _departmentFilter = v,
      ),
      filter(
        'Office',
        'offices',
        _officeFilter,
        officeOptions,
        (v) => _officeFilter = v,
      ),
    ];
    final activeFilters = [
      _campusFilter,
      _departmentFilter,
      _officeFilter,
    ].where((f) => f != 'All').length;

    // The fields read as light toolbar chips rather than heavy form boxes.
    final lighterFields = Theme.of(context).copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        labelStyle: const TextStyle(fontSize: 13, color: AppTheme.slate500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.maroon, width: 1.5),
        ),
      ),
    );

    return Theme(
      data: lighterFields,
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardLabel('Pay period'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                // One row when there's room, a 2×2 grid on a phone, and a
                // single column on the narrowest ones — where two across
                // would cut off "1st Semester" and the dates.
                if (constraints.maxWidth < 280) {
                  return Column(
                    children: [
                      for (final (i, f) in [
                        semesterField,
                        yearField,
                        startField,
                        endField,
                      ].indexed) ...[if (i > 0) const SizedBox(height: gap), f],
                    ],
                  );
                }
                if (constraints.maxWidth >= 640) {
                  return Row(
                    children: [
                      Expanded(child: semesterField),
                      const SizedBox(width: gap),
                      Expanded(child: yearField),
                      const SizedBox(width: gap),
                      Expanded(child: startField),
                      const SizedBox(width: gap),
                      Expanded(child: endField),
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: semesterField),
                        const SizedBox(width: gap),
                        Expanded(child: yearField),
                      ],
                    ),
                    const SizedBox(height: gap),
                    Row(
                      children: [
                        Expanded(child: startField),
                        const SizedBox(width: gap),
                        Expanded(child: endField),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppTheme.slate100),
            if (isMobile) ...[
              // On a phone the three filters fold away behind one row, since
              // most of the time they stay on "All".
              InkWell(
                onTap: () => setState(() => _filtersOpen = !_filtersOpen),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.filter_list_rounded,
                        size: 18,
                        color: activeFilters > 0
                            ? AppTheme.maroon
                            : AppTheme.slate500,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate700,
                          ),
                        ),
                      ),
                      Text(
                        activeFilters == 0 ? 'All' : '$activeFilters applied',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: activeFilters > 0
                              ? AppTheme.maroon
                              : AppTheme.slate500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _filtersOpen
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppTheme.slate400,
                      ),
                    ],
                  ),
                ),
              ),
              if (_filtersOpen)
                for (final (i, f) in filters.indexed) ...[
                  if (i > 0) const SizedBox(height: gap),
                  f,
                ],
            ] else ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final (i, f) in filters.indexed) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(child: f),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateField(String label, DateTime date, {required bool isStart}) {
    const months = [
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
    return InkWell(
      onTap: () => _pickDate(isStart: isStart),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _field(
          label,
          prefixIcon: const Icon(Icons.event_outlined, size: 16),
        ),
        child: Text(
          '${months[date.month - 1]} ${date.day}, ${date.year}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _fieldText,
        ),
      ),
    );
  }

  static const _fieldText = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppTheme.slate800,
  );

  /// Tighter than the theme's default input padding, so two fields fit side
  /// by side on a phone without cutting off "1st Semester" or a date.
  InputDecoration _field(String label, {String? hint, Widget? prefixIcon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        prefixIcon: prefixIcon,
        prefixIconConstraints: prefixIcon == null
            ? null
            : const BoxConstraints(minWidth: 32, minHeight: 20),
      );

  Widget _summaryCard({
    required AppState state,
    required List<PayrollRecord> allPreview,
    required List<PayrollRecord> allReady,
    required List<PayrollRecord> held,
    required List<PayrollRecord> ready,
    required List<PayrollRecord> incomplete,
    required List<PayrollRecord> excluded,
    required List<PayrollRecord> approved,
    required List<PayrollRecord> released,
    required int noHours,
    required double readyTotal,
    required double approvedTotal,
    required bool hasSavedSheet,
  }) {
    Widget spinner() => const SizedBox(
      width: 15,
      height: 15,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
    ButtonStyle filled(Color color) => ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      disabledBackgroundColor: _busyAction != null
          ? color.withValues(alpha: 0.55)
          : AppTheme.slate100,
      disabledForegroundColor: _busyAction != null
          ? Colors.white
          : AppTheme.slate400,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 13.5,
      ),
    );

    final approving = _busyAction == 'approve';
    final releasing = _busyAction == 'release';
    // Until the saved payroll records load, the preview can't tell who's
    // been paid already.
    final loaded = state.payrollRecordsLoaded;
    final approveButton = ElevatedButton.icon(
      onPressed:
          (_busyAction != null ||
              allReady.isEmpty ||
              held.isNotEmpty ||
              !loaded)
          ? null
          : () => _confirmApprove(context, state, allPreview),
      icon: approving
          ? spinner()
          : const Icon(Icons.check_circle_outline, size: 17),
      label: Text(approving ? 'Approving...' : 'Approve'),
      style: filled(AppTheme.maroon),
    );
    final releaseButton = ElevatedButton.icon(
      onPressed: (_busyAction != null || approved.isEmpty)
          ? null
          : () => _confirmRelease(context, state, approved),
      icon: releasing
          ? spinner()
          : const Icon(Icons.payments_outlined, size: 17),
      label: Text(releasing ? 'Releasing...' : 'Release'),
      style: filled(AppTheme.emerald500),
    );

    // One step of the payout: what it comes to, who it covers, and its button.
    Widget stage({
      required IconData icon,
      required Color tint,
      required String label,
      required double amount,
      required String note,
      required Widget button,
    }) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: tint),
              ),
              const SizedBox(width: 8),
              _cardLabel(label),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _peso(amount),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: button),
        ],
      ),
    );

    final approveStage = stage(
      icon: Icons.fact_check_outlined,
      tint: AppTheme.maroon,
      label: 'To approve',
      amount: readyTotal,
      note: !loaded
          ? 'Loading payroll…'
          : held.isNotEmpty
          ? 'Waiting on ${held.length} not ready'
          : '${allReady.length} ready · whole period',
      button: approveButton,
    );
    final releaseStage = stage(
      icon: Icons.payments_outlined,
      tint: AppTheme.emerald500,
      label: 'To release',
      amount: approvedTotal,
      note: '${approved.length} approved',
      button: releaseButton,
    );

    final total =
        ready.length +
        incomplete.length +
        excluded.length +
        approved.length +
        released.length +
        noHours;
    final done = approved.length + released.length;
    final parts = <(int, Color, String)>[
      (released.length, AppTheme.emerald500, 'Released'),
      (approved.length, AppTheme.blue500, 'Approved'),
      (ready.length, AppTheme.maroon, 'Ready'),
      (incomplete.length, AppTheme.amber500, 'Not ready'),
      (excluded.length, AppTheme.slate300, 'Left out'),
      (noHours, AppTheme.slate200, 'No hours'),
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Side by side when there's room, stacked on a phone. Not in an
          // IntrinsicHeight: the cards below hold LayoutBuilders.
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 560
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: approveStage),
                      const SizedBox(width: 12),
                      Expanded(child: releaseStage),
                    ],
                  )
                : Column(
                    children: [
                      approveStage,
                      const SizedBox(height: 12),
                      releaseStage,
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _cardLabel('Progress'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$done of $total approved or released',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SplitBar(parts: parts),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (value, color, label) in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$label $value',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            // The sheet copies in what is loaded now: not before it has all
            // arrived, or it would hold part of the pay.
            onPressed: _busyAction != null || !state.payrollSheetsLoaded
                ? null
                : () => _openSheet(state),
            icon: const Icon(Icons.edit_document, size: 16),
            label: Text(
              !state.payrollSheetsLoaded
                  ? 'Loading payroll data…'
                  : hasSavedSheet
                  ? 'Edit Payroll Sheet'
                  : 'Prepare Payroll Sheet',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.maroon,
              side: const BorderSide(color: AppTheme.maroon200),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The statuses the list can be narrowed to, in the order of the tabs.
  /// A tab only picks which cards are listed: Approve and Release are worked
  /// out from the whole period and the filters above, never from the tab.
  static const _tabStatuses = [
    'Ready',
    'Incomplete',
    'Approved',
    'Released',
    'Excluded',
    'No hours',
  ];

  static const _tabLabels = {
    'All': 'All',
    'Ready': 'Ready',
    'Incomplete': 'Not ready',
    'Approved': 'Approved',
    'Released': 'Released',
    'Excluded': 'Left out',
    'No hours': 'No hours',
  };

  Widget _statusTabs(Map<String, int> counts, String selected) {
    final keys = [
      'All',
      for (final s in _tabStatuses)
        if (s != 'No hours' || (counts[s] ?? 0) > 0 || s == selected) s,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _StatusTab(
                label: _tabLabels[key]!,
                count: counts[key] ?? 0,
                selected: key == selected,
                onTap: () => setState(() => _statusTab = key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listHeader(int count) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Flexible(
                  child: Text(
                    'Student Assistants',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.slate100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _periodLabel,
              style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Who the period's payroll is waiting for, and on what. Shown above the
/// list while anyone in the period isn't ready.
class _HeldUpCard extends StatefulWidget {
  final List<PayrollRecord> held;
  const _HeldUpCard({required this.held});

  @override
  State<_HeldUpCard> createState() => _HeldUpCardState();
}

class _HeldUpCardState extends State<_HeldUpCard> {
  static const _shown = 6;
  bool _all = false;

  /// The people whose line is opened to show what they are missing.
  final Set<String> _openPeople = {};

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return '${parts.first[0]}${parts.length > 1 ? parts.last[0] : ''}'
        .toUpperCase();
  }

  /// What is holding [p] up, in a few words: "4 to check · 1 returned".
  /// [urgent] when something was returned or days were already paid.
  static ({String text, bool urgent}) _summary(PayrollRecord p) {
    final returned = p.unchecked.where((r) => r.isReturned).length;
    final overlap = p.overlappingPayroll != null;
    final parts = [
      if (p.unchecked.isNotEmpty) '${p.unchecked.length} to check',
      if (returned > 0) '$returned returned',
      if (overlap) 'days already paid',
    ];
    return (
      text: parts.isEmpty ? 'Not ready' : parts.join(' · '),
      urgent: returned > 0 || overlap,
    );
  }

  /// One person: a slim line that opens, on a tap, to what they are missing.
  Widget _personRow(PayrollRecord p) {
    final open = _openPeople.contains(p.studentId);
    final summary = _summary(p);
    void toggle() => setState(() {
      if (!_openPeople.remove(p.studentId)) _openPeople.add(p.studentId);
    });

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '${p.studentName}, ${summary.text}',
            onTap: toggle,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.maroon.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _initials(p.studentName),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.maroon,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.studentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: summary.urgent
                              ? AppTheme.red50
                              : AppTheme.amber50,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          summary.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: summary.urgent
                                ? AppTheme.red500
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(42, 2, 0, 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (p.overlappingPayroll != null)
                          const _RequirementPill(
                            label: 'Some days already paid',
                            returned: true,
                          ),
                        for (final r in p.unchecked)
                          _RequirementPill(
                            label: r.label,
                            returned: r.isReturned,
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final held = widget.held;
    final visible = _all ? held : held.take(_shown).toList();
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppTheme.amber50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 18,
                  color: AppTheme.amber500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waiting on ${held.length} Student '
                      'Assistant${held.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Payroll is approved for everyone at once, once the Head '
                      'has checked these or left the student out.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in visible) ...[
            const Divider(height: 8, color: AppTheme.slate100),
            _personRow(p),
          ],
          if (held.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _all = !_all),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.maroon,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(
                    _all ? 'Show fewer' : 'Show all ${held.length}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A requirement the Head hasn't checked: amber while it waits, red once
/// returned.
class _RequirementPill extends StatelessWidget {
  final String label;
  final bool returned;
  const _RequirementPill({required this.label, required this.returned});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: returned ? AppTheme.red50 : AppTheme.amber50,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          returned ? Icons.reply_rounded : Icons.hourglass_top_rounded,
          size: 12,
          color: returned ? AppTheme.red500 : AppTheme.amber500,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            returned ? '$label · returned' : label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// "₱3,937.50" — pesos with thousands separators.
String _peso(double amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '₱$whole.${parts[1]}';
}

/// A tab above the list: a status and how many people have it.
class _StatusTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _StatusTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label, $count',
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
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
    ),
  );
}

/// A 10px bar split by count, each segment rounded and kept apart by a 2px
/// gap; an empty grey track when there's nothing to show. Each segment names
/// itself on hover.
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

class _PayrollRow extends StatelessWidget {
  final PayrollRecord record;

  /// Whether the card is opened to show everything about this person. The
  /// screen keeps it, so a card stays open through tab and filter changes.
  final bool open;
  final VoidCallback onToggle;

  const _PayrollRow({
    required this.record,
    required this.open,
    required this.onToggle,
  });

  bool get _open => open;
  void _toggle() => onToggle();

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

  static const _green = Color(0xFF047857);
  static const _blue = Color(0xFF1D4ED8);
  static const _amber = Color(0xFFB45309);

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return '${parts.first[0]}${parts.length > 1 ? parts.last[0] : ''}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Released keeps its green and Approved its blue; Ready, the step that
    // waits for the Admin, takes the brand colour.
    final (
      statusLabel,
      statusFg,
      statusBg,
      statusIcon,
    ) = switch (record.status) {
      'Released' => (
        'Released',
        _green,
        AppTheme.emerald50,
        Icons.done_all_rounded,
      ),
      'Approved' => (
        'Approved',
        _blue,
        AppTheme.blue50,
        Icons.lock_clock_outlined,
      ),
      'Ready' => (
        'Ready',
        AppTheme.maroon,
        AppTheme.maroon50,
        Icons.check_circle_outline,
      ),
      'Excluded' => (
        'Left out',
        AppTheme.slate600,
        AppTheme.slate100,
        Icons.remove_circle_outline,
      ),
      'No hours' => (
        'No hours',
        AppTheme.slate600,
        AppTheme.slate100,
        Icons.schedule,
      ),
      _ => ('Not ready', _amber, AppTheme.amber50, Icons.hourglass_top_rounded),
    };
    final unchecked = record.unchecked;
    final capped = record.payableHours < record.hoursWorked;
    final anyMonthOff = record.monthlyBreakdown.any(
      (m) => !(m.meetsMinimumHours && m.withinMaximumHours),
    );
    final hasSaId = record.saId != null && record.saId!.isNotEmpty;

    // Shown under the name while the card is closed: why a "Not ready"
    // person is holding the payroll up.
    final hint = record.status == 'Incomplete' && unchecked.isNotEmpty
        ? '${unchecked.length} requirement'
              '${unchecked.length == 1 ? '' : 's'} not checked'
        : null;
    final radius = BorderRadius.circular(18);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── The closed card: who, their pay and where they stand ──
            Semantics(
              button: true,
              expanded: _open,
              label:
                  '${record.studentName}, '
                  '${hasSaId ? '${record.saId}, ' : ''}'
                  '${record.office.isEmpty ? 'Unassigned office' : record.office}, '
                  '$statusLabel, ${_peso(record.grossPay)}'
                  '${hint == null ? '' : ', $hint'}',
              onTap: _toggle,
              excludeSemantics: true,
              child: InkWell(
                borderRadius: radius,
                onTap: _toggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                            _initials(record.studentName),
                            style: const TextStyle(
                              fontSize: 13.5,
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
                              Text(
                                record.studentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // One Text, so the ID and office shorten together
                              // instead of the ID forcing an overflow.
                              Text.rich(
                                TextSpan(
                                  children: [
                                    if (hasSaId) ...[
                                      TextSpan(
                                        text: record.saId,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.maroon,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: '  ·  ',
                                        style: TextStyle(
                                          color: AppTheme.slate400,
                                        ),
                                      ),
                                    ],
                                    TextSpan(
                                      text: record.office.isEmpty
                                          ? 'Unassigned office'
                                          : record.office,
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate500,
                                ),
                              ),
                              if (hint != null && !_open) ...[
                                const SizedBox(height: 2),
                                Text(
                                  hint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _amber,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _peso(record.grossPay),
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 12, color: statusFg),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: statusFg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 22,
                            color: AppTheme.slate400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Everything else, once it is opened ──
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1, color: AppTheme.slate100),
                          const SizedBox(height: 14),
                          // ── Hours and pay ──
                          LayoutBuilder(
                            builder: (context, constraints) {
                              // Three across when there's room, else the third wraps under.
                              const padding = 12.0;
                              const gap = 12.0;
                              final inner = constraints.maxWidth - padding * 2;
                              final columns = inner >= 270 ? 3 : 2;
                              final width =
                                  (inner - gap * (columns - 1)) / columns;
                              Widget cell(Widget child) =>
                                  SizedBox(width: width, child: child);
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(padding),
                                decoration: BoxDecoration(
                                  color: AppTheme.slate50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Wrap(
                                  spacing: gap,
                                  runSpacing: 10,
                                  children: [
                                    cell(
                                      _figure(
                                        'Hours worked',
                                        '${record.hoursWorked.toStringAsFixed(1)} hrs',
                                        null,
                                        AppTheme.slate900,
                                      ),
                                    ),
                                    cell(
                                      _figure(
                                        'Payable hours',
                                        '${record.payableHours.toStringAsFixed(1)} hrs',
                                        capped
                                            ? 'after the monthly limit'
                                            : null,
                                        AppTheme.slate900,
                                      ),
                                    ),
                                    cell(
                                      _figure(
                                        'Gross pay',
                                        _peso(record.grossPay),
                                        null,
                                        AppTheme.maroon,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _check(
                                record.dtrVerified,
                                record.dtrVerified
                                    ? 'DTR verified'
                                    : 'No DTR records',
                              ),
                              if (record.status != 'No hours' &&
                                  record.status != 'Excluded')
                                _check(
                                  record.reportVerified,
                                  record.reportVerified
                                      ? 'Requirements checked'
                                      : '${unchecked.length} requirement'
                                            '${unchecked.length == 1 ? '' : 's'} not checked',
                                ),
                            ],
                          ),
                          if (record.status == 'Incomplete' &&
                              unchecked.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final r in unchecked)
                                  Tooltip(
                                    message:
                                        r.isReturned &&
                                            (r.mark?.note ?? '').isNotEmpty
                                        ? 'Returned: "${r.mark!.note}"'
                                        : r.shortStatus,
                                    child: _RequirementPill(
                                      label: r.label,
                                      returned: r.isReturned,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (record.exclusion case final left?) ...[
                            const SizedBox(height: 10),
                            _callout(
                              Icons.remove_circle_outline,
                              AppTheme.slate600,
                              AppTheme.slate100,
                              'Left out by ${left.by}: "${left.reason}"',
                            ),
                          ],
                          if (record.overlappingPayroll case final paid?) ...[
                            const SizedBox(height: 10),
                            _callout(
                              Icons.block_rounded,
                              AppTheme.red500,
                              AppTheme.red50,
                              'Already ${paid.status.toLowerCase()} for '
                              '${_range(paid.periodStart, paid.periodEnd)}, which '
                              'shares days with this period.',
                            ),
                          ],
                          // ── Month by month ──
                          if (record.monthlyBreakdown.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                const gap = 6.0;
                                final n = record.monthlyBreakdown.length;
                                // Share the row evenly, but never squeeze a month below a
                                // readable width — past that the months wrap instead.
                                final even =
                                    (constraints.maxWidth - gap * (n - 1)) / n;
                                final cellWidth = even < 52 ? 52.0 : even;
                                return Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    for (final m in record.monthlyBreakdown)
                                      SizedBox(
                                        width: cellWidth,
                                        child: _monthCell(m),
                                      ),
                                  ],
                                );
                              },
                            ),
                            if (anyMonthOff) ...[
                              const SizedBox(height: 8),
                              _callout(
                                Icons.warning_amber_rounded,
                                _amber,
                                AppTheme.amber50,
                                'Outside ${PayrollRecord.minimumMonthlyHours.toStringAsFixed(0)}–'
                                '${PayrollRecord.maximumMonthlyHours.toStringAsFixed(0)} hrs that month',
                              ),
                            ],
                          ],
                          if (record.status == 'Approved' ||
                              record.status == 'Released') ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  record.status == 'Released'
                                      ? Icons.done_all_rounded
                                      : Icons.lock_clock_outlined,
                                  size: 13,
                                  color: AppTheme.slate500,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    record.status == 'Released'
                                        ? 'Released ${record.releasedAt ?? ''} by ${record.releasedBy ?? ''}'
                                        : 'Approved ${record.approvedAt ?? ''} by ${record.approvedBy ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.slate500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  /// "Aug 1 – Dec 31, 2026" from two ISO dates.
  static String _range(String isoStart, String isoEnd) {
    final start = DateTime.tryParse(isoStart);
    final end = DateTime.tryParse(isoEnd);
    if (start == null || end == null) return '$isoStart – $isoEnd';
    final from = '${_months[start.month - 1]} ${start.day}';
    final to = '${_months[end.month - 1]} ${end.day}, ${end.year}';
    return start.year == end.year
        ? '$from – $to'
        : '$from, ${start.year} – $to';
  }

  /// A tinted note with an icon, for a warning or a reason.
  Widget _callout(IconData icon, Color color, Color background, String text) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _figure(String label, String value, String? note, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          if (note != null)
            Text(
              note,
              style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
        ],
      );

  /// A check as a small pill: green when it holds, red when it doesn't.
  Widget _check(bool ok, String label) => Container(
    padding: const EdgeInsets.fromLTRB(7, 4, 10, 4),
    decoration: BoxDecoration(
      color: ok ? AppTheme.emerald50 : AppTheme.red50,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 13,
          color: ok ? AppTheme.emerald500 : AppTheme.red500,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ok ? _green : AppTheme.red500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _monthCell(PayrollMonthBreakdown m) {
    final ok = m.meetsMinimumHours && m.withinMaximumHours;
    final color = ok ? AppTheme.slate800 : _amber;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: ok ? AppTheme.slate50 : AppTheme.amber50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ok
              ? AppTheme.slate200
              : AppTheme.amber500.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            _months[m.month - 1],
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ok ? AppTheme.slate500 : _amber,
            ),
          ),
          Text(
            m.hoursWorked.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
