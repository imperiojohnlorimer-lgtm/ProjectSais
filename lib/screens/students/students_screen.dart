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
          (s.userId != null &&
              selectedOffice.assistantIds.contains(s.userId)) ||
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

    final scopedActive = roleScoped
        .where((student) => student.status != 'Archived')
        .toList();
    final archivedCount = roleScoped
        .where((student) => student.status == 'Archived')
        .length;
    final activeCount = scopedActive
        .where((student) => student.status == 'Active')
        .length;
    final loggedHours = scopedActive.fold<double>(
      0,
      (sum, student) => sum + student.totalHours,
    );
    final filterIsOffice = state.role == 'Supervisor';
    final filterValue = filterIsOffice ? _office : _dept;
    final filterOptions = filterIsOffice ? officeOptions : filterDepartments;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────
          HeroBanner(
            isMobile: isMobile,
            icon: Icons.school_rounded,
            title: 'Students',
            subtitle: 'Manage student assistants',
            searchHint: 'Search by name or email...',
            onSearch: (value) => setState(() => _search = value),
            stats: [
              HeroStatData(
                label: 'Students',
                value: '${scopedActive.length}',
                icon: Icons.groups_rounded,
              ),
              HeroStatData(
                label: 'Active',
                value: '$activeCount',
                icon: Icons.check_circle_rounded,
              ),
              HeroStatData(
                label: 'Archived',
                value: '$archivedCount',
                icon: Icons.inventory_2_rounded,
              ),
              HeroStatData(
                label: 'Hours logged',
                value: '${loggedHours.toStringAsFixed(0)}h',
                icon: Icons.schedule_rounded,
              ),
            ],
            filters: [
              _scopeFilter(
                value: filterValue,
                options: filterOptions,
                isOffice: filterIsOffice,
                isMobile: isMobile,
              ),
              _archiveToggle(),
            ],
          ),
          const SizedBox(height: 18),

          // ── Table card ───────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.slate200),
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
                      const Icon(
                        Icons.filter_list_rounded,
                        size: 14,
                        color: AppTheme.slate300,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${students.length} student${students.length != 1 ? 's' : ''} found',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_showArchived)
                        const Text(
                          'Archived view',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.amber500,
                            fontWeight: FontWeight.w700,
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

  /// Department (or office, for supervisors) picker shown in the header
  /// toolbar next to the search field.
  Widget _scopeFilter({
    required String value,
    required List<String> options,
    required bool isOffice,
    required bool isMobile,
  }) {
    return Container(
      height: 40,
      constraints: BoxConstraints(maxWidth: isMobile ? 420 : 260),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: isMobile,
          borderRadius: BorderRadius.circular(10),
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.slate700,
            fontWeight: FontWeight.w600,
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppTheme.slate400,
            size: 18,
          ),
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option,
                  child: Row(
                    children: [
                      Icon(
                        isOffice
                            ? Icons.business_rounded
                            : Icons.apartment_rounded,
                        size: 14,
                        color: AppTheme.maroon.withValues(alpha: 0.65),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(option, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (selected) => setState(() {
            if (isOffice) {
              _office = selected!;
            } else {
              _dept = selected!;
            }
          }),
        ),
      ),
    );
  }

  Widget _archiveToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _showArchived = !_showArchived),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: _showArchived ? AppTheme.amber50 : Colors.white,
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
              _showArchived
                  ? Icons.inventory_2_rounded
                  : Icons.archive_outlined,
              size: 16,
              color: _showArchived ? AppTheme.amber500 : AppTheme.slate400,
            ),
            const SizedBox(width: 7),
            Text(
              _showArchived ? 'Viewing archived' : 'Archived',
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
                      _StatusPill(status: s.status),
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
                        child: _HoursBar(
                          progress: progress,
                          active: isActive,
                          height: 5,
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
        decoration: BoxDecoration(
          gradient: _hovered
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppTheme.maroon50, Colors.white],
                  stops: [0, 0.6],
                )
              : null,
          border: Border(
            left: BorderSide(
              color: _hovered ? AppTheme.maroon : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(17, 14, 20, 14),
        child: Row(
          children: [
            // Avatar
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.maroon.withValues(
                      alpha: _hovered ? 0.22 : 0.1,
                    ),
                    blurRadius: _hovered ? 12 : 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: UserAvatar(
                avatarUrl: s.avatar,
                initials: s.initials,
                size: 44,
              ),
            ),
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
              child: Row(
                children: [
                  Icon(
                    Icons.apartment_rounded,
                    size: 14,
                    color: AppTheme.slate300,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      s.department,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate600,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Status badge
            SizedBox(
              width: 90,
              child: Center(child: _StatusPill(status: s.status)),
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
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HoursBar(progress: progress, active: isActive),
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

                  // ── Assessment history ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showHistoryDialog(context, widget.state, s);
                        },
                        icon: const Icon(Icons.history_rounded, size: 16),
                        label: const Text(
                          'View Assessment History',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.slate700,
                          side: const BorderSide(color: AppTheme.slate200),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
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

  void _showHistoryDialog(BuildContext context, AppState state, Student s) {
    final normalizedName = s.name.trim().toLowerCase();

    final evaluations =
        state.evaluations
            .where(
              (e) =>
                  e.studentId == s.id ||
                  (s.userId != null && e.studentId == s.userId) ||
                  e.studentName.trim().toLowerCase() == normalizedName,
            )
            .toList()
          ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

    final reports =
        state.reports
            .where(
              (r) =>
                  r.applicantId == s.id ||
                  (s.userId != null && r.applicantId == s.userId) ||
                  r.studentName.trim().toLowerCase() == normalizedName,
            )
            .toList()
          ..sort(
            (a, b) => (b.submittedAt ?? '').compareTo(a.submittedAt ?? ''),
          );

    final screenings =
        state.screeningRecords
            .where(
              (r) =>
                  r.applicantId == s.id ||
                  (s.userId != null && r.applicantId == s.userId) ||
                  r.fullName.trim().toLowerCase() == normalizedName,
            )
            .toList()
          ..sort((a, b) {
            final byYear = (b.academicYear ?? '').compareTo(
              a.academicYear ?? '',
            );
            if (byYear != 0) return byYear;
            return b.interviewerDate.compareTo(a.interviewerDate);
          });

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: Container(
          width: 460,
          constraints: const BoxConstraints(maxHeight: 620),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assessment History',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.name,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.slate200),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (evaluations.isEmpty &&
                          reports.isEmpty &&
                          screenings.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.history_toggle_off_rounded,
                                  size: 34,
                                  color: AppTheme.slate300,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No assessment records yet',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.slate400,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (screenings.isNotEmpty) ...[
                        _historySectionLabel(
                          'Applicant Screening',
                          screenings.length,
                        ),
                        for (final r in screenings)
                          _historyTile(
                            icon: Icons.fact_check_outlined,
                            color: AppTheme.blue500,
                            title: r.recommendation,
                            subtitle:
                                'By ${r.interviewerName.isEmpty ? '—' : r.interviewerName} · ${r.interviewerDate}',
                            year: r.academicYear,
                          ),
                        const SizedBox(height: 14),
                      ],
                      if (evaluations.isNotEmpty) ...[
                        _historySectionLabel(
                          'Performance Evaluations',
                          evaluations.length,
                        ),
                        for (final e in evaluations)
                          _historyTile(
                            icon: Icons.grading_outlined,
                            color: AppTheme.maroon,
                            title: '${e.term} · Overall ${e.overallRating}/10',
                            subtitle:
                                'By ${e.supervisorName.isEmpty ? '—' : e.supervisorName} · ${e.periodCovered}',
                            year: e.academicYear,
                          ),
                        const SizedBox(height: 14),
                      ],
                      if (reports.isNotEmpty) ...[
                        _historySectionLabel(
                          'DTR / Accomplishment Reports',
                          reports.length,
                        ),
                        for (final r in reports)
                          _historyTile(
                            icon: Icons.event_note_outlined,
                            color: AppTheme.emerald500,
                            title: r.title.isEmpty ? 'Report' : r.title,
                            subtitle:
                                '${r.status} · ${r.submittedAt ?? 'No date'}',
                            year: r.academicYear,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historySectionLabel(String label, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      '$label ($count)',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppTheme.slate400,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _historyTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    String? year,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.slate50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.slate200),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.slate500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if ((year ?? '').isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'AY $year',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate500,
              ),
            ),
          ),
      ],
    ),
  );

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

/// Status chip with a leading dot, used in the student table.
class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Active' => AppTheme.emerald500,
      'Archived' => AppTheme.slate400,
      'Inactive' => AppTheme.red500,
      _ => AppTheme.amber500,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hours bar that animates to its value, in maroon/gold for active students
/// and grey for everyone else.
class _HoursBar extends StatelessWidget {
  final double progress;
  final bool active;
  final double height;

  const _HoursBar({
    required this.progress,
    required this.active,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: AppTheme.slate100),
          LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              height: height,
              width: constraints.maxWidth * progress,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: active
                      ? [AppTheme.maroon, AppTheme.maroonLight]
                      : [AppTheme.slate300, AppTheme.slate200],
                ),
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
