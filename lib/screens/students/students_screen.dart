import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});
  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  String _search = '';
  String _dept = 'All Departments';
  String _office = 'All Offices';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Use effectiveStudents so fallback Student Assistant users without a
    // precise student document still appear in the student list.
    final roleScoped = state.filteredStudents;
    final officeOptions = [
      'All Offices',
      ...state.currentUserOffices.map((office) => office.name),
    ];
    final selectedOffice = _office == 'All Offices'
        ? null
        : state.currentUserOffices
              .where((office) => office.name == _office)
              .firstOrNull;

    final students = roleScoped.where((s) {
      final q = _search.toLowerCase();
      final matchSearch =
          q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.email.toLowerCase().contains(q);
      final matchDept = _dept == 'All Departments' || s.department == _dept;
      final matchOffice =
          selectedOffice == null ||
          selectedOffice.assistantIds.contains(s.userId ?? s.id) ||
          selectedOffice.assistantIds.contains(s.id) ||
          (s.userId != null && selectedOffice.assistantIds.contains(s.userId)) ||
          selectedOffice.assistantNames.any(
            (name) => name.trim().toLowerCase() == s.name.trim().toLowerCase(),
          );
      final matchArchived = _showArchived
          ? s.status == 'Archived'
          : s.status != 'Archived';
      return matchSearch && matchDept && matchOffice && matchArchived;
    }).toList();

    final filterDepartments = [
      'All Departments',
      ...roleScoped.map((student) => student.department).toSet().toList()
        ..sort(),
    ];

    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    // Max hours for progress bar scaling
    final maxHours = students.fold<double>(
      1,
      (m, s) => s.totalHours > m ? s.totalHours : m,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────
          // Title
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
              const Text(
                'Students',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Text(
              'Manage student assistants',
              style: TextStyle(fontSize: 13, color: AppTheme.slate400),
            ),
          ),
          const SizedBox(height: 16),
          // Search + filter
          if (isMobile) ...[
            TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                hintStyle: const TextStyle(
                  color: AppTheme.slate400,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.slate400,
                  size: 18,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.slate200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.slate200),
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
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: state.role == 'Supervisor' ? _office : _dept,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate700,
                    fontWeight: FontWeight.w500,
                  ),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.slate400,
                    size: 18,
                  ),
                  items:
                      (state.role == 'Supervisor'
                              ? officeOptions
                              : filterDepartments)
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(d, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() {
                    if (state.role == 'Supervisor') {
                      _office = v!;
                    } else {
                      _dept = v!;
                    }
                  }),
                ),
              ),
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search by name or email...',
                      hintStyle: const TextStyle(
                        color: AppTheme.slate400,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.slate400,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
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
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: state.role == 'Supervisor' ? _office : _dept,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate700,
                        fontWeight: FontWeight.w500,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.slate400,
                        size: 18,
                      ),
                      items:
                          (state.role == 'Supervisor'
                                  ? officeOptions
                                  : filterDepartments)
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d,
                                  child: Text(
                                    d,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (v) => setState(() {
                        if (state.role == 'Supervisor') {
                          _office = v!;
                        } else {
                          _dept = v!;
                        }
                      }),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          // Archived toggle
          GestureDetector(
            onTap: () => setState(() => _showArchived = !_showArchived),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _showArchived ? AppTheme.amber50 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showArchived
                      ? AppTheme.amber500.withValues(alpha: 0.4)
                      : AppTheme.slate200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 15,
                    color: _showArchived
                        ? AppTheme.amber500
                        : AppTheme.slate400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showArchived
                        ? 'Showing archived students'
                        : 'Show archived students',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _showArchived
                          ? AppTheme.amber500
                          : AppTheme.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Table card ───────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              children: [
                // Gradient top strip
                Container(
                  height: 5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                ),

                // Table header (desktop only)
                if (!isMobile)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      border: Border(
                        bottom: BorderSide(color: AppTheme.slate100),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 44),
                        const SizedBox(width: 12),
                        const Expanded(flex: 3, child: _ColHeader('Student')),
                        const Expanded(
                          flex: 3,
                          child: _ColHeader('Department'),
                        ),
                        const SizedBox(
                          width: 90,
                          child: _ColHeader('Status', center: true),
                        ),
                        const SizedBox(width: 140, child: _ColHeader('Hours')),
                        const SizedBox(
                          width: 48,
                          child: _ColHeader('Actions', center: true),
                        ),
                      ],
                    ),
                  ),

                // Rows
                if (students.isEmpty)
                  _emptyState()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: students.length,
                    separatorBuilder: (context, index) =>
                        Container(height: 1, color: AppTheme.slate100),
                    itemBuilder: (_, i) => _StudentRow(
                      student: students[i],
                      state: state,
                      maxHours: maxHours,
                      isMobile: isMobile,
                    ),
                  ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.slate50,
                    border: Border(top: BorderSide(color: AppTheme.slate100)),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${students.length} student${students.length != 1 ? 's' : ''} found',
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.slate50,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              size: 28,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No students found',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.slate400,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try adjusting your search or filter',
            style: TextStyle(fontSize: 12, color: AppTheme.slate300),
          ),
        ],
      ),
    );
  }
}

/// Subtle diagonal dot pattern used behind the student-detail dialog avatar banner.
class _BannerPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    const spacing = 16.0;
    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final offsetX = (y ~/ spacing).isEven ? x : x + spacing / 2;
        canvas.drawCircle(Offset(offsetX, y), 1.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ColHeader extends StatelessWidget {
  final String text;
  final bool center;
  const _ColHeader(this.text, {this.center = false});

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.left,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.slate400,
      letterSpacing: 0.6,
    ),
  );
}

class _StudentRow extends StatefulWidget {
  final Student student;
  final AppState state;
  final double maxHours;
  final bool isMobile;
  const _StudentRow({
    required this.student,
    required this.state,
    required this.maxHours,
    this.isMobile = false,
  });

  @override
  State<_StudentRow> createState() => _StudentRowState();
}

class _StudentRowState extends State<_StudentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final isActive = s.status == 'Active';
    final progress = widget.maxHours > 0
        ? (s.totalHours / widget.maxHours).clamp(0.0, 1.0)
        : 0.0;

    if (widget.isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(avatarUrl: s.avatar, initials: s.initials, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppTheme.slate900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.emerald500.withValues(alpha: 0.1)
                              : AppTheme.slate100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          s.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: isActive
                                ? AppTheme.emerald500
                                : AppTheme.slate400,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.email,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.department,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 12,
                        color: AppTheme.maroon.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${s.totalHours.toStringAsFixed(0)}h',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: AppTheme.slate100,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isActive ? AppTheme.maroon : AppTheme.slate300,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: AppTheme.slate400,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
              offset: const Offset(0, 8),
              itemBuilder: (_) => [
                _menuItem(
                  'view',
                  Icons.visibility_outlined,
                  'View Details',
                  AppTheme.slate700,
                ),
                if (widget.state.role == 'Head' && s.status != 'Archived')
                  _menuItem(
                    'archive',
                    Icons.archive_outlined,
                    'Archive',
                    AppTheme.amber500,
                  ),
                if (widget.state.role == 'Head' && s.status == 'Archived')
                  _menuItem(
                    'restore',
                    Icons.unarchive_outlined,
                    'Restore',
                    AppTheme.emerald500,
                  ),
              ],
              onSelected: (action) async {
                if (action == 'view') _showDetail(context);
                if (action == 'archive') {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Archive Student',
                    message:
                        'Archive ${s.name}? They can be restored later from the archived list.',
                    confirmLabel: 'Archive',
                    confirmColor: AppTheme.amber500,
                  );
                  if (ok) widget.state.archiveStudent(s.id);
                }
                if (action == 'restore') {
                  widget.state.restoreStudent(s.id);
                }
              },
            ),
          ],
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hovered ? AppTheme.maroon50 : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Avatar
            UserAvatar(avatarUrl: s.avatar, initials: s.initials, size: 44),
            const SizedBox(width: 12),

            // Name + email
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.slate900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.email,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate500,
                    ),
                  ),
                ],
              ),
            ),

            // Department
            Expanded(
              flex: 3,
              child: Text(
                s.department,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.slate600,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Status badge
            SizedBox(
              width: 90,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.emerald500.withValues(alpha: 0.1)
                        : AppTheme.slate200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    s.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: isActive ? AppTheme.emerald500 : AppTheme.slate500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

            // Hours + progress bar
            SizedBox(
              width: 140,
              child: Row(
                children: [
                  Text(
                    '${s.totalHours.toStringAsFixed(0)}h',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppTheme.slate100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isActive ? AppTheme.maroon : AppTheme.slate300,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Actions menu
            SizedBox(
              width: 48,
              child: Center(
                child: PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: AppTheme.slate400,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 8,
                  offset: const Offset(0, 8),
                  itemBuilder: (_) => [
                    _menuItem(
                      'view',
                      Icons.visibility_outlined,
                      'View Details',
                      AppTheme.slate700,
                    ),
                    if (widget.state.role == 'Head' && s.status != 'Archived')
                      _menuItem(
                        'archive',
                        Icons.archive_outlined,
                        'Archive',
                        AppTheme.amber500,
                      ),
                    if (widget.state.role == 'Head' && s.status == 'Archived')
                      _menuItem(
                        'restore',
                        Icons.unarchive_outlined,
                        'Restore',
                        AppTheme.emerald500,
                      ),
                  ],
                  onSelected: (action) async {
                    if (action == 'view') _showDetail(context);
                    if (action == 'archive') {
                      final ok = await showConfirmDialog(
                        context,
                        title: 'Archive Student',
                        message:
                            'Archive ${s.name}? They can be restored later from the archived list.',
                        confirmLabel: 'Archive',
                        confirmColor: AppTheme.amber500,
                      );
                      if (ok) widget.state.archiveStudent(s.id);
                    }
                    if (action == 'restore') {
                      widget.state.restoreStudent(s.id);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final s = widget.student;
    final isActive = s.status == 'Active';
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: Container(
          width: 440,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.maroon.withValues(alpha: 0.18),
                blurRadius: 48,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Banner ────────────────────────────────────
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 92,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.maroon, AppTheme.maroonDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: SizedBox.expand(
                          child: CustomPaint(painter: _BannerPatternPainter()),
                        ),
                      ),
                      // thin gold accent line
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(height: 3, color: AppTheme.gold),
                      ),
                      // Close button
                      Positioned(
                        top: 14,
                        right: 14,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                      // Avatar overlapping banner
                      Positioned(
                        bottom: -40,
                        left: 24,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: UserAvatar(
                            avatarUrl: s.avatar,
                            initials: s.initials,
                            size: 68,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Name row ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STUDENT ASSISTANT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate400,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                s.name,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppTheme.emerald50
                                      : AppTheme.slate100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isActive
                                        ? AppTheme.emerald500.withValues(
                                            alpha: 0.25,
                                          )
                                        : AppTheme.slate200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? AppTheme.emerald500
                                            : AppTheme.slate400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      s.status,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isActive
                                            ? AppTheme.emerald500
                                            : AppTheme.slate500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Total hours stat card
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.maroon50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.maroon100),
                          ),
                          child: Column(
                            children: [
                              Text(
                                s.totalHours.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.maroon,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'HOURS',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.maroon.withValues(
                                    alpha: 0.65,
                                  ),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Info grid ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _infoTile(
                                Icons.email_outlined,
                                'Email',
                                s.email,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoTile(
                                Icons.business_outlined,
                                'Department',
                                s.department,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _infoTile(
                                Icons.phone_outlined,
                                'Phone',
                                (s.phone?.isEmpty ?? true) ? '—' : s.phone!,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoTile(
                                Icons.location_on_outlined,
                                'Address',
                                (s.address?.isEmpty ?? true) ? '—' : s.address!,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Change Department / Remove buttons ────────────
                  if (widget.state.role == 'Head')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showChangeDepartmentDialog(
                                  context,
                                  widget.state,
                                  s,
                                );
                              },
                              icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Department',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.maroon,
                                side: BorderSide(
                                  color: AppTheme.maroon.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: s.status == 'Archived'
                                ? OutlinedButton.icon(
                                    onPressed: () {
                                      widget.state.restoreStudent(s.id);
                                      Navigator.pop(context);
                                    },
                                    icon: const Icon(
                                      Icons.unarchive_outlined,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Restore',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.emerald500,
                                      side: BorderSide(
                                        color: AppTheme.emerald500.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                    ),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      final ok = await showConfirmDialog(
                                        context,
                                        title: 'Archive Student',
                                        message:
                                            'Archive ${s.name}? Their records are kept and they can be restored later.',
                                        confirmLabel: 'Archive',
                                        confirmColor: AppTheme.amber500,
                                      );
                                      if (ok) widget.state.archiveStudent(s.id);
                                    },
                                    icon: const Icon(
                                      Icons.archive_outlined,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Archive',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.amber500,
                                      side: BorderSide(
                                        color: AppTheme.amber500.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(13),
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
          ),
        ),
      ),
    );
  }

  void _showChangeDepartmentDialog(
    BuildContext context,
    AppState state,
    Student s,
  ) {
    String selected = state.departments.contains(s.department)
        ? s.department
        : state.departments.first;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Change Department',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Move ${s.name} to a different department',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate400,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.slate50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selected,
                      isExpanded: true,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate700,
                        fontWeight: FontWeight.w500,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.slate400,
                        size: 18,
                      ),
                      items: state.departments
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(d, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => selected = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: const BorderSide(color: AppTheme.slate200),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.slate700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          state.updateStudentDepartment(s.id, selected);
                          Navigator.pop(dialogContext);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.slate100),
                ),
                child: Icon(icon, size: 12, color: AppTheme.maroon),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate400,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
