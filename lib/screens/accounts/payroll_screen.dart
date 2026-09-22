import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'payroll_sheet_editor.dart';

/// Admin screen: approve and release payroll for a pay period — a whole
/// semester, not a single month.
///
/// For every active Student Assistant, the System retrieves and verifies
/// their DTR (attendance) records and an approved accomplishment report
/// before they can be approved — anyone missing either is left
/// 'Incomplete'. The payable amount is computed from total hours rendered
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

  static const _semesters = ['1st Semester', '2nd Semester'];

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    // Payroll only runs for the two regular semesters; a Summer term in the
    // settings would otherwise match no dropdown option and crash it.
    _semester = _semesters.contains(state.academicSemester)
        ? state.academicSemester
        : _semesters.first;
    _academicYear = state.academicYear;
    _applyDefaultRange();
  }

  /// A reasonable default start/end for the chosen semester, parsed from
  /// the "YYYY-YYYY" academic year setting — always editable afterward in
  /// case the actual semester dates differ.
  void _applyDefaultRange() {
    final years = _academicYear.split('-');
    final y1 = int.tryParse(years.isNotEmpty ? years[0] : '') ?? DateTime.now().year;
    final y2 = years.length > 1
        ? (int.tryParse(years[1]) ?? y1 + 1)
        : y1 + 1;
    if (_semester == '1st Semester') {
      _start = DateTime(y1, 8, 1);
      _end = DateTime(y1, 12, 31);
    } else {
      _start = DateTime(y2, 1, 1);
      _end = DateTime(y2, 5, 31);
    }
  }

  String get _periodLabel => '$_semester, AY $_academicYear';

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 3),
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

  Future<void> _confirmApprove(
    BuildContext context,
    AppState state,
    List<PayrollRecord> preview,
  ) async {
    final ready = preview.where((p) => p.status == 'Ready').toList();
    if (ready.isEmpty) return;
    final total = ready.fold<double>(0, (sum, p) => sum + p.grossPay);

    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve Payroll',
      message:
          'This will approve and record pay for ${ready.length} Student '
          'Assistant(s) for $_periodLabel, totaling '
          '${_peso(total)}. Payout is not released to students '
          'until you separately click "Release".\n\n'
          '${preview.length - ready.length} student(s) with incomplete '
          'requirements will be skipped.',
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not approve payroll: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      final (count, releasedTotal) = await state.releasePayroll(
        start: _start,
        endInclusive: _end,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Released payout for $count Student Assistant(s) — '
            '${_peso(releasedTotal)} total. They\'ve been notified.',
          ),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not release payout: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  /// campuses. Incomplete students can't be paid, so they're left off.
  List<PayrollSheetEntry> _systemEntries(AppState state) {
    final start = _isoDate(_start);
    final end = _isoDate(_end);
    return PayrollSheet.fromRecords(
      periodStart: start,
      periodEnd: end,
      periodLabel: _periodLabel,
      records: state
          .buildPayrollPreview(
            start: _start,
            endInclusive: _end,
            periodLabel: _periodLabel,
          )
          .where((p) => p.status != 'Incomplete')
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
    ];
    if (!campusOptions.contains(_campusFilter)) _campusFilter = 'All';
    if (!departmentOptions.contains(_departmentFilter)) _departmentFilter = 'All';
    if (!officeOptions.contains(_officeFilter)) _officeFilter = 'All';

    final preview = allPreview.where((p) {
      if (_campusFilter != 'All' && (p.campus ?? '').trim() != _campusFilter) {
        return false;
      }
      if (_departmentFilter != 'All' && (p.department ?? '').trim() != _departmentFilter) {
        return false;
      }
      if (_officeFilter != 'All' && p.office.trim() != _officeFilter) {
        return false;
      }
      return true;
    }).toList();

    final ready = preview.where((p) => p.status == 'Ready').toList();
    final incomplete = preview.where((p) => p.status == 'Incomplete').toList();
    final approved = preview.where((p) => p.status == 'Approved').toList();
    final released = preview.where((p) => p.status == 'Released').toList();
    final readyTotal = ready.fold<double>(0, (sum, p) => sum + p.grossPay);
    final approvedTotal = approved.fold<double>(0, (sum, p) => sum + p.grossPay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: _header(),
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
                  preview: preview,
                  ready: ready,
                  incomplete: incomplete,
                  approved: approved,
                  released: released,
                  readyTotal: readyTotal,
                  approvedTotal: approvedTotal,
                  hasSavedSheet: hasSavedSheet,
                ),
                const SizedBox(height: 22),
                _listHeader(preview.length),
                const SizedBox(height: 10),
                if (preview.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No active Student Assistants found.',
                        style: TextStyle(color: AppTheme.slate400),
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
                          for (final p in preview)
                            SizedBox(
                              width: cardWidth,
                              child: _PayrollRow(record: p),
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

  Widget _header() => Row(
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
                Text(
                  'Payroll',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    letterSpacing: -0.3,
                    height: 1.1,
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
                color: AppTheme.slate400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.slate200),
    ),
    child: child,
  );

  Widget _cardLabel(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      color: AppTheme.slate400,
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
                o == 'All' ? 'All $plural' : o,
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

    return _card(
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
                    ].indexed) ...[
                      if (i > 0) const SizedBox(height: gap),
                      f,
                    ],
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
                            : AppTheme.slate400,
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
    );
  }

  Widget _dateField(String label, DateTime date, {required bool isStart}) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    required List<PayrollRecord> preview,
    required List<PayrollRecord> ready,
    required List<PayrollRecord> incomplete,
    required List<PayrollRecord> approved,
    required List<PayrollRecord> released,
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
    final approveButton = ElevatedButton.icon(
      onPressed: (_busyAction != null || ready.isEmpty)
          ? null
          : () => _confirmApprove(context, state, preview),
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

    Widget stage(
      String label,
      double amount,
      String note,
      Widget button,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardLabel(label),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _peso(amount),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          note,
          style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: button),
      ],
    );

    Widget count(String label, int value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate500,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: stage(
                    'To approve',
                    readyTotal,
                    '${ready.length} ready',
                    approveButton,
                  ),
                ),
                const VerticalDivider(
                  width: 28,
                  thickness: 1,
                  color: AppTheme.slate100,
                ),
                Expanded(
                  child: stage(
                    'To release',
                    approvedTotal,
                    '${approved.length} approved',
                    releaseButton,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              count('Ready', ready.length, AppTheme.slate600),
              const SizedBox(width: 6),
              count('Incomplete', incomplete.length, AppTheme.amber500),
              const SizedBox(width: 6),
              count('To release', approved.length, AppTheme.blue500),
              const SizedBox(width: 6),
              count('Released', released.length, AppTheme.emerald500),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busyAction != null ? null : () => _openSheet(state),
            icon: const Icon(Icons.edit_document, size: 16),
            label: Text(
              hasSavedSheet ? 'Edit Payroll Sheet' : 'Prepare Payroll Sheet',
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

  Widget _listHeader(int count) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Student Assistants',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
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
              style: const TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
          ],
        ),
      ),
    ],
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

class _PayrollRow extends StatelessWidget {
  final PayrollRecord record;
  const _PayrollRow({required this.record});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (record.status) {
      'Released' => AppTheme.emerald500,
      'Approved' => AppTheme.blue500,
      'Ready' => AppTheme.slate600,
      _ => AppTheme.amber500,
    };
    final capped = record.payableHours < record.hoursWorked;
    final anyMonthOff = record.monthlyBreakdown.any(
      (m) => !(m.meetsMinimumHours && m.withinMaximumHours),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Who ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (record.saId != null && record.saId!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.maroon.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              record.saId!,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.maroon,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            record.studentName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.office.isEmpty ? 'Unassigned office' : record.office,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  record.status,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Hours and pay ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _figure(
                  'Hours worked',
                  '${record.hoursWorked.toStringAsFixed(1)} hrs',
                  capped
                      ? '${record.payableHours.toStringAsFixed(1)} payable'
                      : null,
                  AppTheme.slate900,
                ),
              ),
              Expanded(
                child: _figure(
                  'Gross pay',
                  _peso(record.grossPay),
                  null,
                  AppTheme.maroon,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _check(
                record.dtrVerified,
                record.dtrVerified ? 'DTR verified' : 'No DTR records',
              ),
              _check(
                record.reportVerified,
                record.reportVerified ? 'Report verified' : 'No approved report',
              ),
            ],
          ),
          // ── Month by month ──
          if (record.monthlyBreakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 6.0;
                final n = record.monthlyBreakdown.length;
                // Share the row evenly, but never squeeze a month below a
                // readable width — past that the months wrap instead.
                final even = (constraints.maxWidth - gap * (n - 1)) / n;
                final cellWidth = even < 52 ? 52.0 : even;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final m in record.monthlyBreakdown)
                      SizedBox(width: cellWidth, child: _monthCell(m)),
                  ],
                );
              },
            ),
            if (anyMonthOff) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 13,
                    color: AppTheme.amber500,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Outside ${PayrollRecord.minimumMonthlyHours.toStringAsFixed(0)}–'
                      '${PayrollRecord.maximumMonthlyHours.toStringAsFixed(0)} hrs that month',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.amber500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (record.status == 'Approved' || record.status == 'Released') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  record.status == 'Released'
                      ? Icons.done_all_rounded
                      : Icons.lock_clock_outlined,
                  size: 13,
                  color: AppTheme.slate400,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    record.status == 'Released'
                        ? 'Released ${record.releasedAt ?? ''} by ${record.releasedBy ?? ''}'
                        : 'Approved ${record.approvedAt ?? ''} by ${record.approvedBy ?? ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _figure(String label, String value, String? note, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate400,
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

  Widget _check(bool ok, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
        size: 14,
        color: ok ? AppTheme.emerald500 : AppTheme.red500,
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ok ? AppTheme.slate600 : AppTheme.red500,
        ),
      ),
    ],
  );

  Widget _monthCell(PayrollMonthBreakdown m) {
    final ok = m.meetsMinimumHours && m.withinMaximumHours;
    final color = ok ? AppTheme.slate800 : AppTheme.amber500;
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
              color: ok ? AppTheme.slate400 : AppTheme.amber500,
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
