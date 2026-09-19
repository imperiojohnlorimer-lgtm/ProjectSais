import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

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
  bool _busy = false;

  String _campusFilter = 'All';
  String _departmentFilter = 'All';
  String _officeFilter = 'All';

  static const _semesters = ['1st Semester', '2nd Semester'];

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _semester = state.academicSemester;
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
          '₱${total.toStringAsFixed(2)}. Payout is not released to students '
          'until you separately click "Release Payout".\n\n'
          '${preview.length - ready.length} student(s) with incomplete '
          'requirements will be skipped.',
      confirmLabel: 'Approve',
      confirmColor: AppTheme.maroon,
    );
    if (!confirmed || !context.mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (count, approvedTotal) = await state.approvePayroll(preview);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Approved payroll for $count Student Assistant(s) — '
            '₱${approvedTotal.toStringAsFixed(2)} total. Release it when ready.',
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
      if (mounted) setState(() => _busy = false);
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
          '₱${total.toStringAsFixed(2)}, and notify each of them. This '
          'cannot be undone.',
      confirmLabel: 'Release',
      confirmColor: AppTheme.emerald500,
    );
    if (!confirmed || !context.mounted) return;

    setState(() => _busy = true);
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
            '₱${releasedTotal.toStringAsFixed(2)} total. They\'ve been notified.',
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

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
          child: Row(
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
              const Text(
                'Payroll',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad + 14, 4, hPad, 0),
          child: const Text(
            'Approve and release payroll for a semester. ₱25.00/hr, '
            '25–40 hrs/month.',
            style: TextStyle(fontSize: 13, color: AppTheme.slate400),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Period picker ──────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 170,
                        child: DropdownButtonFormField<String>(
                          initialValue: _semester,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Semester',
                            isDense: true,
                          ),
                          items: _semesters
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _semester = v ?? _semester;
                            _applyDefaultRange();
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: TextFormField(
                          initialValue: _academicYear,
                          decoration: const InputDecoration(
                            labelText: 'Academic Year',
                            hintText: 'e.g. 2026-2027',
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() {
                            _academicYear = v;
                            _applyDefaultRange();
                          }),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _pickDate(isStart: true),
                        child: _dateChip('Start', _start),
                      ),
                      GestureDetector(
                        onTap: () => _pickDate(isStart: false),
                        child: _dateChip('End', _end),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Filters ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _campusFilter,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Campus',
                            isDense: true,
                          ),
                          items: campusOptions
                              .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => _campusFilter = v ?? 'All'),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _departmentFilter,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                            isDense: true,
                          ),
                          items: departmentOptions
                              .map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => _departmentFilter = v ?? 'All'),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _officeFilter,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Office',
                            isDense: true,
                          ),
                          items: officeOptions
                              .map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => _officeFilter = v ?? 'All'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Actions ─────────────────────────────────
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_busy || ready.isEmpty)
                          ? null
                          : () => _confirmApprove(context, state, preview),
                      icon: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline, size: 16),
                      label: Text('Approve Payroll (${ready.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: (_busy || approved.isEmpty)
                          ? null
                          : () => _confirmRelease(context, state, approved),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: Text('Release Payout (${approved.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ── Summary ─────────────────────────────────
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryTile('Ready to Approve', '${ready.length}', AppTheme.slate600, Icons.hourglass_empty_rounded),
                    _summaryTile('Incomplete', '${incomplete.length}', AppTheme.amber500, Icons.error_outline),
                    _summaryTile('Awaiting Release', '${approved.length}', AppTheme.blue500, Icons.lock_clock_outlined),
                    _summaryTile('Released', '${released.length}', AppTheme.emerald500, Icons.done_all),
                    _summaryTile('Pending Approval Total', '₱${readyTotal.toStringAsFixed(2)}', AppTheme.slate600, Icons.pending_actions_outlined),
                    _summaryTile('Pending Release Total', '₱${approvedTotal.toStringAsFixed(2)}', AppTheme.maroon, Icons.payments_outlined),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '$_periodLabel — Student Assistants (${preview.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                if (preview.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No active Student Assistants found.',
                        style: TextStyle(color: AppTheme.slate400),
                      ),
                    ),
                  )
                else
                  ...preview.map((p) => _PayrollRow(record: p)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateChip(String label, DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_outlined, size: 15, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 9.5, color: AppTheme.slate400, fontWeight: FontWeight.w700),
              ),
              Text(
                '${months[date.month - 1]} ${date.day}, ${date.year}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.slate800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value, Color color, IconData icon) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (record.saId != null && record.saId!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    record.saId!,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.maroon),
                  ),
                ),
              Expanded(
                child: Text(
                  record.studentName,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.slate800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  record.status,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            record.office.isEmpty ? 'Unassigned office' : record.office,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
          ),
          if (record.status == 'Approved' || record.status == 'Released') ...[
            const SizedBox(height: 4),
            Text(
              record.status == 'Released'
                  ? 'Released ${record.releasedAt ?? ''} by ${record.releasedBy ?? ''}'
                  : 'Approved ${record.approvedAt ?? ''} by ${record.approvedBy ?? ''}',
              style: const TextStyle(fontSize: 10.5, color: AppTheme.slate400, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                Icons.access_time_rounded,
                '${record.hoursWorked.toStringAsFixed(1)} hrs worked total',
                AppTheme.slate600,
              ),
              _chip(
                Icons.payments_outlined,
                '₱${record.grossPay.toStringAsFixed(2)}',
                AppTheme.maroon,
              ),
              _chip(
                record.dtrVerified ? Icons.check_circle_outline : Icons.cancel_outlined,
                record.dtrVerified ? 'DTR verified' : 'No DTR records',
                record.dtrVerified ? AppTheme.emerald500 : AppTheme.red500,
              ),
              _chip(
                record.reportVerified ? Icons.check_circle_outline : Icons.cancel_outlined,
                record.reportVerified ? 'Report verified' : 'No approved report',
                record.reportVerified ? AppTheme.emerald500 : AppTheme.red500,
              ),
            ],
          ),
          if (record.monthlyBreakdown.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: record.monthlyBreakdown.map((m) {
                final ok = m.meetsMinimumHours && m.withinMaximumHours;
                return _chip(
                  ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  '${_months[m.month - 1]} ${m.year}: ${m.hoursWorked.toStringAsFixed(1)} hrs',
                  ok ? AppTheme.slate500 : AppTheme.amber500,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );
}
