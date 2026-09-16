import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main content ───────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16.0 : 28.0,
                  24,
                  isMobile ? 16.0 : 28.0,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.maroon,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attendance',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              'Track and manage attendance records',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.slate400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Mobile-only clock/QR card (desktop shows this in the right panel)
                    if (isMobile) ...[
                      _ClockCard(
                        isStudent: isStudent,
                        active: active,
                        onClockIn: () async {
                          await context.read<AppState>().clockIn();
                          _snack(context, 'Clocked in!', AppTheme.emerald500);
                        },
                        onClockOut: active != null
                            ? () async {
                                await context.read<AppState>().clockOut(
                                  active.id,
                                );
                                _snack(
                                  context,
                                  'Clocked out!',
                                  AppTheme.emerald500,
                                );
                              }
                            : null,
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
                    const SizedBox(height: 20),

                    // Tab content
                    SizedBox(
                      height: 600,
                      child: TabBarView(
                        controller: _tab,
                        children: [
                          // Log tab
                          Column(
                            children: [
                              if (!isStudent) ...[
                                TextField(
                                  onChanged: (v) => setState(() => _search = v),
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Search by student name...',
                                    hintStyle: const TextStyle(
                                      color: AppTheme.slate400,
                                      fontSize: 13,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: AppTheme.slate400,
                                      size: 18,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slate200,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slate200,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.maroon,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => setState(
                                      () => _showArchived = !_showArchived,
                                    ),
                                    icon: Icon(
                                      _showArchived
                                          ? Icons.visibility_outlined
                                          : Icons.archive_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _showArchived
                                          ? 'Show active logs'
                                          : 'Show archived logs',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Expanded(
                                child: records.isEmpty
                                    ? _emptyState()
                                    : ListView.separated(
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
                                            onDelete: () async {
                                              final ok = await showConfirmDialog(
                                                context,
                                                title: 'Delete Record',
                                                message:
                                                    'Remove this attendance record?',
                                                confirmLabel: 'Delete',
                                                confirmColor: AppTheme.red500,
                                              );
                                              if (ok) {
                                                state.deleteAttendance(r.id);
                                                _snack(
                                                  context,
                                                  'Attendance record deleted',
                                                  AppTheme.red500,
                                                );
                                              }
                                            },
                                            onClockOut: r.isActive && isStudent
                                                ? () async {
                                                    await state.clockOut(r.id);
                                                    _snack(
                                                      context,
                                                      'Clocked out!',
                                                      AppTheme.emerald500,
                                                    );
                                                  }
                                                : null,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),

                          // Schedule tab
                          _ScheduleTab(),
                        ],
                      ),
                    ),
                  ],
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
                        onClockIn: () async {
                          await context.read<AppState>().clockIn();
                          _snack(context, 'Clocked in!', AppTheme.emerald500);
                        },
                        onClockOut: active != null
                            ? () async {
                                await context.read<AppState>().clockOut(
                                  active.id,
                                );
                                _snack(
                                  context,
                                  'Clocked out!',
                                  AppTheme.emerald500,
                                );
                              }
                            : null,
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

  void _snack(BuildContext ctx, String msg, Color color) {
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

  Future<void> _handleScannedCode(BuildContext context, String code) async {
    final state = context.read<AppState>();

    // Reject codes that aren't a valid, still-active attendance QR
    final valid = await state.isQrTokenValid(code);
    if (!valid) {
      // Try to fetch current Firestore token for diagnostics to help debugging.
      try {
        final fs = FirestoreService();
        final doc = await fs.getCurrentQrToken();
        String token = doc?['token']?.toString() ?? '<none>';
        final gen = doc?['generatedAt'];
        String genStr = '<unknown>';
        int age = -1;
        if (gen is Timestamp) {
          final dt = gen.toDate();
          genStr = dt.toString();
          age = DateTime.now().difference(dt).inSeconds;
        } else if (gen is String) {
          genStr = gen;
          final dt = DateTime.tryParse(gen);
          if (dt != null) age = DateTime.now().difference(dt).inSeconds;
        }

        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('QR Validation Failed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scanned: $code'),
                const SizedBox(height: 6),
                Text('Current token: $token'),
                const SizedBox(height: 6),
                Text('Generated at: $genStr'),
                const SizedBox(height: 6),
                Text('Token age (s): ${age >= 0 ? age.toString() : "unknown"}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } catch (e) {
        _snack(
          context,
          'Invalid or expired QR code. Ask your supervisor to generate a new one.',
          AppTheme.red500,
        );
      }
      return;
    }

    if (state.activeAttendanceRecord != null) {
      await state.clockOut(state.activeAttendanceRecord!.id);
      _snack(context, 'QR Scan — Clocked out!', AppTheme.emerald500);
    } else {
      await state.clockIn();
      _snack(context, 'QR Scan — Clocked in!', AppTheme.emerald500);
    }
  }

  Future<void> _showQrGenerator(BuildContext context) async {
    final state = context.read<AppState>();
    await state.generateAttendanceQrToken();
    showDialog(context: context, builder: (_) => const _QrGenerateDialog());
  }
}

// ── Clock card ────────────────────────────────────────────────────────
class _ClockCard extends StatefulWidget {
  final bool isStudent;
  final dynamic active;
  final VoidCallback onClockIn;
  final VoidCallback? onClockOut;
  final VoidCallback? onScanQr;
  final VoidCallback? onGenerateQr;

  const _ClockCard({
    required this.isStudent,
    required this.active,
    required this.onClockIn,
    this.onClockOut,
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
  final VoidCallback? onClockOut;

  const _RecordCard({
    required this.record,
    required this.canDelete,
    this.onDelete,
    this.onClockOut,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = record.isActive as bool;
    final color = isActive ? AppTheme.emerald500 : AppTheme.slate400;
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
                          color: isActive
                              ? AppTheme.emerald500.withValues(alpha: .1)
                              : AppTheme.slate100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? "On Duty" : "Completed",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppTheme.emerald500
                                : AppTheme.slate500,
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

                  if (onClockOut != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onClockOut,
                        icon: const Icon(Icons.logout_rounded, size: 14),
                        label: const Text(
                          "Clock Out",
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

          if (canDelete && onDelete != null)
            SizedBox(
              width: isMobile ? 36 : 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppTheme.slate300,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.slate300,
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
  static const _validitySeconds = 60;
  late final Stream<int> _tick = Stream.periodic(
    const Duration(seconds: 1),
    (i) => i,
  );

  int _secondsLeft(AppState state) {
    if (state.qrGeneratedAt == null) return 0;
    final elapsed = DateTime.now().difference(state.qrGeneratedAt!).inSeconds;
    final left = _validitySeconds - elapsed;
    return left < 0 ? 0 : left;
  }

  Future<void> _regenerate(BuildContext context) async {
    await context.read<AppState>().generateAttendanceQrToken();
    setState(() {});
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

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  StreamBuilder<int>(
                    stream: _tick,
                    builder: (_, __) {
                      final left = _secondsLeft(state);
                      final expired = left <= 0;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: expired
                                  ? AppTheme.red500
                                  : AppTheme.emerald500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            expired
                                ? 'Expired — generate a new code'
                                : 'Valid for ${left}s',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: expired
                                  ? AppTheme.red500
                                  : AppTheme.slate500,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _regenerate(context),
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text(
                        'Generate New Code',
                        style: TextStyle(
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