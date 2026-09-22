import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/web_print_stub.dart'
    if (dart.library.html) '../../utils/web_print.dart'
    as web_print;
import '../../widgets/shared_widgets.dart';

void _showSnack(BuildContext ctx, String msg, Color color) {
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ),
  );
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _search = '';
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isStudent = state.role == 'Student Assistant';
    final active = state.activeAttendanceRecord;
    final records = state.filteredAttendance
        .where((record) => record.isArchived == _showArchived)
        .where(
          (r) => r.studentName.toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();

    // Header figures always describe the live log, not the current filter.
    final liveRecords = state.filteredAttendance
        .where((record) => !record.isArchived)
        .toList();
    final clockedInCount = liveRecords.where((r) => r.isActive).length;
    final invalidCount = liveRecords.where((r) => r.isInvalid).length;
    final totalHours = liveRecords.fold<double>(
      0,
      (running, r) => running + (r.totalHours ?? 0),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final hPad = isMobile ? 16.0 : 28.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main content ───────────────────────────────────────
            // NestedScrollView links the header with the tab lists so one
            // drag scrolls both: the header scrolls away first, and pulling
            // down past the top of a list brings it back. A plain scroll view
            // wrapping a fixed-height list trapped touch drags inside the list.
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (_, _) => [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 20),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          HeroBanner(
                            isMobile: isMobile,
                            icon: Icons.access_time_filled_rounded,
                            title: 'Attendance',
                            subtitle: 'Track and manage attendance records',
                            searchHint: isStudent
                                ? 'Search your records...'
                                : 'Search by student name...',
                            onSearch: (value) =>
                                setState(() => _search = value),
                            filters: [
                              if (!isStudent)
                                _toggleChip(
                                  label: _showArchived
                                      ? 'Viewing archived'
                                      : 'Archived',
                                  icon: _showArchived
                                      ? Icons.inventory_2_rounded
                                      : Icons.archive_outlined,
                                  selected: _showArchived,
                                  color: AppTheme.amber500,
                                  onTap: () => setState(
                                    () => _showArchived = !_showArchived,
                                  ),
                                ),
                              if (state.role == 'Head' ||
                                  state.role == 'Supervisor')
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final fixed = await state
                                        .recalculateAttendanceHours();
                                    if (!context.mounted) return;
                                    _snack(
                                      context,
                                      fixed == 0
                                          ? 'All completed records already have correct hours'
                                          : 'Recalculated hours for $fixed record(s)',
                                      AppTheme.emerald500,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.calculate_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Recalculate'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.maroon,
                                    side: const BorderSide(
                                      color: AppTheme.maroon,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                            stats: [
                              HeroStatData(
                                label: 'Records',
                                value: '${liveRecords.length}',
                                icon: Icons.list_alt_rounded,
                              ),
                              HeroStatData(
                                label: 'Clocked in',
                                value: '$clockedInCount',
                                icon: Icons.play_circle_fill_rounded,
                              ),
                              HeroStatData(
                                label: 'Hours',
                                value: '${totalHours.toStringAsFixed(0)}h',
                                icon: Icons.schedule_rounded,
                              ),
                              HeroStatData(
                                label: 'Missed out',
                                value: '$invalidCount',
                                icon: Icons.error_outline_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Mobile-only clock/QR card (desktop shows this in the right panel)
                          if (isMobile) ...[
                            _ClockCard(
                              isStudent: isStudent,
                              active: active,
                              onScanQr: isStudent
                                  ? () => _showQrScanner(context)
                                  : null,
                              onGenerateQr: !isStudent
                                  ? () => _showQrGenerator(context)
                                  : null,
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Tab bar
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.slate100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: TabBar(
                              controller: _tab,
                              indicator: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.07),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              dividerColor: Colors.transparent,
                              labelColor: AppTheme.maroon,
                              unselectedLabelColor: AppTheme.slate500,
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                              unselectedLabelStyle: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                              tabs: const [
                                Tab(text: 'Log'),
                                Tab(text: 'Schedule'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Tab content
                body: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      // Log tab
                      records.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.only(bottom: 28),
                              children: [_emptyState()],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 28),
                              itemCount: records.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final r = records[i];
                                return _RecordCard(
                                  record: r,
                                  canDelete:
                                      state.role == 'Head' ||
                                      state.role == 'Supervisor',
                                  onArchive: () async {
                                    final restoring = r.isArchived;
                                    // Archived records stop counting toward
                                    // verified hours, so taking one out of
                                    // the log is worth a second look.
                                    if (!restoring) {
                                      final ok = await showConfirmDialog(
                                        context,
                                        title: 'Archive Record',
                                        message:
                                            'Archive ${r.studentName}\'s record for ${r.date}? '
                                            'Its hours will no longer count toward their verified '
                                            'DTR hours or payroll. You can restore it later.',
                                        confirmLabel: 'Archive',
                                        confirmColor: AppTheme.amber500,
                                      );
                                      if (!ok || !context.mounted) return;
                                    }
                                    final saved = await state
                                        .setAttendanceArchived(
                                          r.id,
                                          !restoring,
                                        );
                                    if (!context.mounted) return;
                                    _snack(
                                      context,
                                      saved
                                          ? (restoring
                                                ? 'Record restored to the log'
                                                : 'Record archived')
                                          : 'Could not save that — the record is unchanged on the server.',
                                      saved
                                          ? AppTheme.emerald500
                                          : AppTheme.red500,
                                    );
                                  },
                                  onDelete: () async {
                                    final ok = await showConfirmDialog(
                                      context,
                                      title: 'Delete Record',
                                      message:
                                          'Remove this attendance record? '
                                          'Archive it instead if you only want it out of the log.',
                                      confirmLabel: 'Delete',
                                      confirmColor: AppTheme.red500,
                                    );
                                    if (!ok || !context.mounted) {
                                      return;
                                    }
                                    final deleted = await state
                                        .deleteAttendance(r.id);
                                    if (!context.mounted) return;
                                    _snack(
                                      context,
                                      deleted
                                          ? 'Attendance record deleted'
                                          : 'Could not delete that record on the server.',
                                      deleted
                                          ? AppTheme.red500
                                          : AppTheme.amber500,
                                    );
                                  },
                                  onSetTimeOut:
                                      r.isActive &&
                                          (state.role == 'Head' ||
                                              state.role == 'Supervisor')
                                      ? () async {
                                          final picked = await showTimePicker(
                                            context: context,
                                            initialTime: TimeOfDay.now(),
                                          );
                                          if (picked == null ||
                                              !context.mounted)
                                            return;
                                          final hour = picked.hourOfPeriod == 0
                                              ? 12
                                              : picked.hourOfPeriod;
                                          final minute = picked.minute
                                              .toString()
                                              .padLeft(2, '0');
                                          final period =
                                              picked.period == DayPeriod.am
                                              ? 'AM'
                                              : 'PM';
                                          final confirmed = await showConfirmDialog(
                                            context,
                                            title: 'Record Time-out',
                                            message:
                                                'Set ${r.studentName}\'s time-out to '
                                                '$hour:$minute $period on ${r.date} '
                                                '(timed in at ${r.timeIn})? The record '
                                                'will count as verified hours.',
                                            confirmLabel: 'Record',
                                            confirmColor: AppTheme.maroon,
                                          );
                                          if (!confirmed || !context.mounted) {
                                            return;
                                          }
                                          await state.setManualTimeOut(
                                            r.id,
                                            '$hour:$minute $period',
                                          );
                                          if (!context.mounted) return;
                                          _snack(
                                            context,
                                            'Time-out recorded and verified',
                                            AppTheme.emerald500,
                                          );
                                        }
                                      : null,
                                );
                              },
                            ),

                      // Schedule tab
                      _ScheduleTab(),
                    ],
                  ),
                ),
              ),
            ),

            // ── Right panel (desktop only) ─────────────────────────
            if (!isMobile)
              SizedBox(
                width: 300,
                height: constraints.maxHeight,
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(0, 24, 28, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ClockCard(
                        isStudent: isStudent,
                        active: active,
                        onScanQr: isStudent
                            ? () => _showQrScanner(context)
                            : null,
                        onGenerateQr: !isStudent
                            ? () => _showQrGenerator(context)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _WeeklySummaryCard(records: state.filteredAttendance),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Small on/off pill used among the header toolbar filters.
  Widget _toggleChip({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : AppTheme.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? color : AppTheme.slate400),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? color : AppTheme.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate100),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.slate50,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.access_time_outlined,
              size: 28,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No attendance records found',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.slate400,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Records will appear here once available',
            style: TextStyle(fontSize: 12, color: AppTheme.slate300),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext ctx, String msg, Color color) =>
      _showSnack(ctx, msg, color);

  void _showQrScanner(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _QrScanDialog(
        onScanned: (code) {
          Navigator.pop(context);
          _handleScannedCode(context, code);
        },
      ),
    );
  }

  /// Hands the scanned code to the server, which decides everything: that
  /// it's this session's QR, that the window is open by its own clock, and
  /// whether this scan is a clock-in or a clock-out. Nothing is checked
  /// here first — a local check would only ever be a slower way to reach
  /// the same answer, and a wrong one if the phone's clock is off.
  Future<void> _handleScannedCode(BuildContext context, String code) async {
    final result = await context.read<AppState>().clockViaQr(code);
    if (!context.mounted) return;
    _snack(
      context,
      result.ok
          ? (result.clockedIn
                ? 'QR Scan — Clocked in!'
                : 'QR Scan — Clocked out!')
          : result.message,
      result.ok ? AppTheme.emerald500 : AppTheme.red500,
    );
  }

  Future<void> _showQrGenerator(BuildContext context) async {
    final state = context.read<AppState>();
    if (!state.isWithinAttendanceQrWindow()) {
      _snack(
        context,
        'Attendance QR can only be generated 7:30 AM–12:00 PM and '
        '12:30 PM–5:00 PM.',
        AppTheme.amber500,
      );
      return;
    }
    // Returns the session's existing code when there already is one, so
    // re-opening the generator never invalidates a QR that's already posted.
    final token = await state.generateAttendanceQrToken();
    if (!context.mounted) return;
    if (token == null) {
      _snack(
        context,
        'The attendance session ended before the code could be generated.',
        AppTheme.amber500,
      );
      return;
    }
    showDialog(context: context, builder: (_) => const _QrGenerateDialog());
  }
}

// ── Clock card ────────────────────────────────────────────────────────
class _ClockCard extends StatefulWidget {
  final bool isStudent;
  final dynamic active;
  final VoidCallback? onScanQr;
  final VoidCallback? onGenerateQr;

  const _ClockCard({
    required this.isStudent,
    required this.active,
    this.onScanQr,
    this.onGenerateQr,
  });

  @override
  State<_ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<_ClockCard> {
  late final Stream<DateTime> _tick = Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.maroon.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Gradient top
          Container(
            height: 5,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.maroon, AppTheme.maroonDark],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Live clock
                StreamBuilder<DateTime>(
                  stream: _tick,
                  initialData: DateTime.now(),
                  builder: (_, snap) {
                    final now = snap.data!;
                    final h = now.hour > 12
                        ? now.hour - 12
                        : now.hour == 0
                        ? 12
                        : now.hour;
                    final m = now.minute.toString().padLeft(2, '0');
                    final s = now.second.toString().padLeft(2, '0');
                    final period = now.hour >= 12 ? 'PM' : 'AM';
                    final months = [
                      'January',
                      'February',
                      'March',
                      'April',
                      'May',
                      'June',
                      'July',
                      'August',
                      'September',
                      'October',
                      'November',
                      'December',
                    ];
                    const days = [
                      'Monday',
                      'Tuesday',
                      'Wednesday',
                      'Thursday',
                      'Friday',
                      'Saturday',
                      'Sunday',
                    ];
                    final dayName = days[now.weekday - 1].toUpperCase();
                    final dateStr = '${months[now.month - 1]} ${now.day}';

                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.maroon50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.access_time_rounded,
                            color: AppTheme.maroon,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                              fontFamily: 'Inter',
                            ),
                            children: [
                              TextSpan(
                                text: '$h:$m:$s',
                                style: const TextStyle(
                                  fontSize: 28,
                                  letterSpacing: -1,
                                ),
                              ),
                              TextSpan(
                                text: ' $period',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.maroon,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dayName, $dateStr',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.slate400,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                if (widget.isStudent) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: const Text(
                      'Please ensure you are within the campus premises.',
                      style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Status indicator
                  if (widget.active != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald500.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.emerald500.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppTheme.emerald500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'On duty since ${widget.active.timeIn}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.emerald500,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 10),

                  // QR scan button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onScanQr,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                      label: const Text(
                        'Scan QR Code',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.maroon,
                        side: const BorderSide(
                          color: AppTheme.maroon,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: const Text(
                      'Generate a QR code for student assistants to scan and log their attendance.',
                      style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onGenerateQr,
                      icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                      label: const Text(
                        'Generate QR Code',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Weekly summary card ───────────────────────────────────────────────
class _WeeklySummaryCard extends StatelessWidget {
  final List records;
  const _WeeklySummaryCard({required this.records});

  @override
  Widget build(BuildContext context) {
    // Calculate hours per weekday from records
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    final Map<String, double> hours = {for (final d in days) d: 0.0};
    // Simple mock: distribute completed records across days
    for (final r in records) {
      if (!r.isActive && r.totalHours != null) {
        // Try to match day abbreviation from date string
        for (final d in days) {
          if ((r.date as String).contains(_dayFull(d))) {
            hours[d] = (hours[d] ?? 0) + (r.totalHours as double);
          }
        }
      }
    }

    final maxHours = hours.values.fold<double>(0, (a, b) => b > a ? b : a);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.maroon50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  size: 16,
                  color: AppTheme.maroon,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Weekly Summary',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.slate900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...days.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxHours > 0 ? (hours[d]! / maxHours) : 0,
                        minHeight: 8,
                        backgroundColor: AppTheme.slate100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          hours[d]! > 0 ? AppTheme.maroon : AppTheme.slate200,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${hours[d]!.toStringAsFixed(0)}h',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate400,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dayFull(String abbr) {
    const m = {
      'Mon': 'Mon',
      'Tue': 'Tue',
      'Wed': 'Wed',
      'Thu': 'Thu',
      'Fri': 'Fri',
    };
    return m[abbr] ?? abbr;
  }
}

// ── Schedule tab ─────────────────────────────────────────────────────
// Reads the same [ClassScheduleEntry] rows as the DTR/Accomplishment
// Report's "Class Schedule" table (see app_state.classScheduleForStudent),
// so whatever the student/supervisor has filled in there — course, units,
// and per-weekday time ranges — is exactly what shows up here too.
class _ScheduleTab extends StatelessWidget {
  static final _weekdays = [
    ('Monday', (ClassScheduleEntry e) => e.monday),
    ('Tuesday', (ClassScheduleEntry e) => e.tuesday),
    ('Wednesday', (ClassScheduleEntry e) => e.wednesday),
    ('Thursday', (ClassScheduleEntry e) => e.thursday),
    ('Friday', (ClassScheduleEntry e) => e.friday),
    ('Saturday', (ClassScheduleEntry e) => e.saturday),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ownerName = state.currentUser?.name ?? '';
    final rows = state.classScheduleForStudent(ownerName);

    // Flatten each course row into one entry per weekday it actually meets.
    final slots = <({String day, String course, String time})>[];
    for (final row in rows) {
      for (final entry in _weekdays) {
        final time = entry.$2(row).trim();
        if (time.isEmpty) continue;
        slots.add((
          day: entry.$1,
          course: row.course.trim().isEmpty ? 'Untitled Subject' : row.course,
          time: time,
        ));
      }
    }
    slots.sort((a, b) {
      final dayA = _weekdays.indexWhere((e) => e.$1 == a.day);
      final dayB = _weekdays.indexWhere((e) => e.$1 == b.day);
      if (dayA != dayB) return dayA.compareTo(dayB);
      return a.time.compareTo(b.time);
    });

    if (slots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 50),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: AppTheme.slate100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.event_busy_outlined,
                  size: 30,
                  color: AppTheme.slate300,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No class schedule set yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Fill in the Class Schedule table on the\n'
                'DTR/Accomplishment Report to see it here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.slate400),
              ),
            ],
          ),
        ),
      );
    }

    final todayName = _weekdays[(DateTime.now().weekday - 1).clamp(0, 5)].$1;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: slots
          .map(
            (s) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(color: AppTheme.maroon, width: 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.maroon50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: AppTheme.maroon,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              s.day,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.slate900,
                              ),
                            ),
                            if (s.day == todayName) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppTheme.emerald500,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.course,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slate700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.time,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald500.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.emerald500,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Attendance record card ────────────────────────────────────────────
class _RecordCard extends StatelessWidget {
  final dynamic record;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onSetTimeOut;
  final VoidCallback? onArchive;

  const _RecordCard({
    required this.record,
    required this.canDelete,
    this.onDelete,
    this.onSetTimeOut,
    this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final isArchived = record.isArchived as bool;
    final isActive = record.isActive as bool;
    final isInvalid = record.isInvalid as bool;
    final color = isInvalid
        ? AppTheme.red500
        : (isActive ? AppTheme.emerald500 : AppTheme.slate400);
    final isMobile = MediaQuery.of(context).size.width < 400;

    final dateParts = (record.date as String).split(' ');
    final monthAbbr = dateParts.isNotEmpty
        ? dateParts[0].substring(0, 3).toUpperCase()
        : '—';
    final dayNum = dateParts.length > 1
        ? dateParts[1].replaceAll(',', '')
        : '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isMobile ? 50 : 58,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.maroon50,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  monthAbbr,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.maroon,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dayNum,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.maroon,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 14,
                vertical: isMobile ? 8 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Student name + status
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isMobile ? 120 : 180,
                        ),
                        child: Text(
                          record.studentName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isInvalid
                              ? AppTheme.red500.withValues(alpha: .1)
                              : (isActive
                                    ? AppTheme.emerald500.withValues(alpha: .1)
                                    : AppTheme.slate100),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isInvalid
                              ? "Invalid — Missed Time-Out"
                              : (isActive ? "On Duty" : "Completed"),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isInvalid
                                ? AppTheme.red500
                                : (isActive
                                      ? AppTheme.emerald500
                                      : AppTheme.slate500),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: isMobile ? 5 : 8),

                  /// Time chips
                  isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _timeChip(
                              Icons.login_rounded,
                              "IN",
                              record.timeIn,
                              AppTheme.emerald500,
                            ),

                            if (!isActive) ...[
                              const SizedBox(height: 6),
                              _timeChip(
                                Icons.logout_rounded,
                                "OUT",
                                record.timeOut,
                                AppTheme.red500,
                              ),
                            ],

                            if (!isActive && record.totalHours != null) ...[
                              const SizedBox(height: 6),
                              _timeChip(
                                Icons.access_time_rounded,
                                "",
                                "${(record.totalHours as double).toStringAsFixed(1)}h",
                                AppTheme.blue500,
                              ),
                            ],
                          ],
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _timeChip(
                              Icons.login_rounded,
                              "IN",
                              record.timeIn,
                              AppTheme.emerald500,
                            ),

                            if (!isActive)
                              _timeChip(
                                Icons.logout_rounded,
                                "OUT",
                                record.timeOut,
                                AppTheme.red500,
                              ),

                            if (!isActive && record.totalHours != null)
                              _timeChip(
                                Icons.access_time_rounded,
                                "",
                                "${(record.totalHours as double).toStringAsFixed(1)}h",
                                AppTheme.blue500,
                              ),
                          ],
                        ),

                  if (onSetTimeOut != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onSetTimeOut,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.red500,
                          side: const BorderSide(color: AppTheme.red500),
                        ),
                        icon: const Icon(
                          Icons.edit_calendar_outlined,
                          size: 14,
                        ),
                        label: const Text(
                          "Set Time-Out & Verify",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (canDelete && (onDelete != null || onArchive != null))
            SizedBox(
              width: isMobile ? 36 : 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Archiving keeps the record for the DTR and payroll trail
                  // while taking it out of the working log; deleting throws
                  // it away. They sit together so the gentler one is the
                  // easier reach.
                  if (onArchive != null)
                    IconButton(
                      onPressed: onArchive,
                      tooltip: isArchived
                          ? 'Restore to the log'
                          : 'Archive this record',
                      icon: Icon(
                        isArchived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        size: 18,
                        color: isArchived
                            ? AppTheme.amber500
                            : AppTheme.slate300,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: onDelete,
                      tooltip: 'Delete this record',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppTheme.slate300,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          if (label.isNotEmpty) ...[
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── QR Scanner dialog ─────────────────────────────────────────────────
class _QrScanDialog extends StatefulWidget {
  final ValueChanged<String> onScanned;
  const _QrScanDialog({required this.onScanned});

  @override
  State<_QrScanDialog> createState() => _QrScanDialogState();
}

class _QrScanDialogState extends State<_QrScanDialog> {
  bool _scanned = false;
  final MobileScannerController _ctrl = MobileScannerController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.maroon, AppTheme.maroonDark],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan QR Code',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Point camera at your attendance QR code',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Scanner viewport
            Container(
              margin: const EdgeInsets.all(20),
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.maroon, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _ctrl,
                      onDetect: (capture) {
                        if (_scanned) return;
                        final barcode = capture.barcodes.firstOrNull;
                        if (barcode?.rawValue != null) {
                          setState(() => _scanned = true);
                          widget.onScanned(barcode!.rawValue!);
                        }
                      },
                    ),
                    // Corner guides overlay
                    Positioned.fill(
                      child: CustomPaint(painter: _ScannerOverlayPainter()),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _scanned
                              ? AppTheme.emerald500
                              : AppTheme.gold400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _scanned ? 'QR code detected!' : 'Scanning...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _scanned
                              ? AppTheme.emerald500
                              : AppTheme.slate500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Torch toggle
                  OutlinedButton.icon(
                    onPressed: () => _ctrl.toggleTorch(),
                    icon: const Icon(Icons.flashlight_on_rounded, size: 15),
                    label: const Text(
                      'Toggle Torch',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.maroon,
                      side: const BorderSide(color: AppTheme.maroon),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

// Corner guides overlay painter
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.gold400
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    final corners = [
      Offset(0, 0),
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final dirs = [
      [Offset(len, 0), Offset(0, len)],
      [Offset(-len, 0), Offset(0, len)],
      [Offset(-len, 0), Offset(0, -len)],
      [Offset(len, 0), Offset(0, -len)],
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawLine(corners[i], corners[i] + dirs[i][0], paint);
      canvas.drawLine(corners[i], corners[i] + dirs[i][1], paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── QR Generator dialog (Supervisor / Admin) ──────────────────────────
class _QrGenerateDialog extends StatefulWidget {
  const _QrGenerateDialog();

  @override
  State<_QrGenerateDialog> createState() => _QrGenerateDialogState();
}

class _QrGenerateDialogState extends State<_QrGenerateDialog> {
  /// The QR only changes when the session does, so a slow tick is enough to
  /// notice the session ending.
  late final Stream<int> _tick = Stream.periodic(
    const Duration(seconds: 10),
    (i) => i,
  );

  /// Wraps the QR so it can be rasterised for printing.
  final GlobalKey _qrKey = GlobalKey();

  /// Set while the QR is being rasterised, so the button can say so.
  bool _preparingPrint = false;

  Future<void> _print(BuildContext context) async {
    if (_preparingPrint) return;

    final state = context.read<AppState>();
    final sessionLabel = state.attendanceQrSessionLabel();
    final sessionEnd = state.attendanceQrSessionEnd();

    if (!web_print.WebPrintUtils.isSupported) {
      _showSnack(
        context,
        'Printing is available from the web version of SAIS.',
        AppTheme.amber500,
      );
      return;
    }

    setState(() => _preparingPrint = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('The QR code is not on screen yet.');
      }
      final image = await boundary.toImage(pixelRatio: 4);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('The QR code could not be rendered.');

      await web_print.WebPrintUtils.printImage(
        data.buffer.asUint8List(),
        title: 'SAIS Attendance QR',
        captions: [
          if (sessionLabel != null) sessionLabel,
          _printableSessionRange(sessionEnd),
          'Scan to log in or out.',
        ],
      );
      if (!context.mounted) return;
      _showSnack(
        context,
        'Print dialog opened. If nothing appeared, check that your browser '
        'is not blocking it.',
        AppTheme.emerald500,
      );
    } catch (error) {
      if (!context.mounted) return;
      // The reason is shown rather than swallowed: a print that quietly does
      // nothing is impossible to tell apart from a stuck button.
      _showSnack(context, 'Could not print the QR: $error', AppTheme.red500);
    } finally {
      if (mounted) setState(() => _preparingPrint = false);
    }
  }

  /// Caption naming the day and the hours the printed code covers.
  String _printableSessionRange(DateTime? sessionEnd) {
    final now = DateTime.now();
    final date = _fmtPrintDate(now);
    if (sessionEnd == null) return date;
    final isMorning = sessionEnd.hour < 13;
    final hours = isMorning ? '7:30 AM – 12:00 PM' : '12:30 PM – 5:00 PM';
    return '$date · valid $hours';
  }

  static String _fmtPrintDate(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _fmtTime(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final token = state.currentQrToken ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.maroon, AppTheme.maroonDark],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance QR Code',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Have the student assistant scan this to log in/out',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // QR code
            Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.slate200),
                ),
                // Only the code itself is captured for printing, so the
                // printed sheet carries no dialog chrome.
                child: RepaintBoundary(
                  key: _qrKey,
                  child: QrImageView(
                    data: token,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppTheme.maroon,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppTheme.slate900,
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  StreamBuilder<int>(
                    stream: _tick,
                    builder: (_, __) {
                      final sessionLabel = state.attendanceQrSessionLabel();
                      final sessionEnd = state.attendanceQrSessionEnd();
                      final ended = sessionLabel == null || sessionEnd == null;
                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: ended
                                      ? AppTheme.red500
                                      : AppTheme.emerald500,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ended
                                    ? 'Session over — this code no longer works'
                                    : '$sessionLabel · valid until '
                                          '${_fmtTime(sessionEnd)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ended
                                      ? AppTheme.red500
                                      : AppTheme.slate500,
                                ),
                              ),
                            ],
                          ),
                          if (!ended) ...[
                            const SizedBox(height: 4),
                            Text(
                              'The same code works for everyone all session — '
                              'print it and post it.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.slate500.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: token.isEmpty || _preparingPrint
                          ? null
                          : () => _print(context),
                      icon: _preparingPrint
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.maroon,
                              ),
                            )
                          : const Icon(Icons.print_rounded, size: 15),
                      label: Text(
                        _preparingPrint ? 'Preparing print…' : 'Print QR Code',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.maroon,
                        side: const BorderSide(color: AppTheme.maroon),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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
