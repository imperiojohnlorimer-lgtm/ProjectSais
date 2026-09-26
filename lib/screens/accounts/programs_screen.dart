import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Admin screen for the degree programs students choose when they
/// register. Programs are grouped under their department, and each group
/// takes the same accent colour its department has on the Departments
/// screen, so the two read as one set.
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  // The Departments screen's accent colours, in the same order, so a
  // department keeps its colour on both screens.
  static const _accents = [
    Color(0xFF8B1C3E),
    Color(0xFF1C5F8B),
    Color(0xFF1C8B5A),
    Color(0xFF7D3C98),
    Color(0xFF8B6914),
  ];
  static const _allDepartments = 'All departments';

  String _search = '';
  String _department = _allDepartments;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    final state = context.watch<AppState>();
    final query = _search.trim().toLowerCase();
    final allPrograms = state.programs;

    // How many people list each program on their profile, by code.
    final enrolled = <String, int>{};
    for (final user in state.users) {
      final code = user.courseProgram?.trim().toLowerCase() ?? '';
      if (code.isEmpty) continue;
      enrolled[code] = (enrolled[code] ?? 0) + 1;
    }
    int enrolledIn(Program p) => enrolled[p.code.trim().toLowerCase()] ?? 0;

    final departmentFilter = _department == _allDepartments
        ? null
        : _department;
    bool matches(Program p) =>
        query.isEmpty ||
        p.code.toLowerCase().contains(query) ||
        p.name.toLowerCase().contains(query) ||
        p.department.toLowerCase().contains(query);

    // One group per department, in the Departments screen's order, then any
    // programs whose department no longer exists.
    final groups = <({String department, Color accent, List<Program> items})>[];
    for (var i = 0; i < state.departments.length; i++) {
      final dept = state.departments[i];
      if (departmentFilter != null && dept != departmentFilter) continue;
      final items = allPrograms
          .where((p) => p.department == dept && matches(p))
          .toList();
      // Empty departments only show while browsing, as a prompt to add one.
      if (items.isEmpty && query.isNotEmpty) continue;
      groups.add((
        department: dept,
        accent: _accents[i % _accents.length],
        items: items,
      ));
    }
    final orphans = allPrograms
        .where((p) => !state.departments.contains(p.department) && matches(p))
        .toList();
    if (orphans.isNotEmpty && departmentFilter == null) {
      groups.add((department: '', accent: AppTheme.slate400, items: orphans));
    }

    final shown = groups.fold<int>(0, (total, g) => total + g.items.length);
    final coveredDepartments = state.departments
        .where((d) => allPrograms.any((p) => p.department == d))
        .length;
    final studentCount = allPrograms.fold<int>(
      0,
      (total, p) => total + enrolledIn(p),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: HeroBanner(
            isMobile: isMobile,
            icon: Icons.school_rounded,
            title: 'Programs',
            subtitle: 'Degree programs students choose when they register',
            searchHint: 'Search by code or program name...',
            onSearch: (value) => setState(() => _search = value),
            addLabel: 'Add Program',
            onAdd: () => _showProgramDialog(context),
            filters: [_departmentFilter(state)],
            stats: [
              HeroStatData(
                label: 'Programs',
                value: '${allPrograms.length}',
                icon: Icons.school_rounded,
              ),
              // Departments that have at least one program, of all of them.
              HeroStatData(
                label: 'Departments',
                value: '$coveredDepartments/${state.departments.length}',
                icon: Icons.business_rounded,
              ),
              HeroStatData(
                label: 'Students',
                value: '$studentCount',
                icon: Icons.groups_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ── Content ─────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: groups.isEmpty || (shown == 0 && query.isNotEmpty)
                ? _emptyState(query.isNotEmpty)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final group in groups)
                        _DepartmentGroup(
                          department: group.department,
                          code: state.departmentCodes[group.department] ?? '',
                          accent: group.accent,
                          programs: group.items,
                          enrolledIn: enrolledIn,
                          onAdd: group.department.isEmpty
                              ? null
                              : () => _showProgramDialog(
                                  context,
                                  department: group.department,
                                ),
                          onEdit: (p) =>
                              _showProgramDialog(context, program: p),
                          onDelete: (p) => _deleteProgram(context, p),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _departmentFilter(AppState state) {
    final options = [_allDepartments, ...state.departments];
    final value = options.contains(_department) ? _department : _allDepartments;
    return Container(
      height: 40,
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: AppTheme.slate400,
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate700,
          ),
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _department = v ?? _allDepartments),
        ),
      ),
    );
  }

  Widget _emptyState(bool searching) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                color: AppTheme.slate100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school_outlined,
                size: 40,
                color: AppTheme.slate400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              searching ? 'No programs match your search' : 'No programs yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'Try a different code or name'
                  : 'Add a department first, then its programs',
              style: const TextStyle(fontSize: 13, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProgram(BuildContext context, Program program) async {
    final state = context.read<AppState>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete program?',
      message:
          '"${program.label}" will be removed from the program list. '
          'Students who already chose it keep it on their profile.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    final removed = await state.removeProgram(program);
    if (!context.mounted) return;
    _snack(
      context,
      removed
          ? 'Program "${program.code}" deleted'
          : 'Could not delete program "${program.code}"',
      removed ? AppTheme.red500 : AppTheme.amber500,
    );
  }

  Future<void> _showProgramDialog(
    BuildContext context, {
    Program? program,
    String? department,
  }) async {
    final state = context.read<AppState>();
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: state,
        child: _ProgramDialog(
          program: program,
          department: department ?? program?.department,
        ),
      ),
    );
    if (saved == null || !context.mounted) return;
    _snack(
      context,
      program == null ? 'Program "$saved" added!' : 'Program updated!',
      AppTheme.emerald500,
    );
  }

  void _snack(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

/// One department's heading and its programs as a grid of cards.
class _DepartmentGroup extends StatelessWidget {
  final String department;
  final String code;
  final Color accent;
  final List<Program> programs;
  final int Function(Program) enrolledIn;
  final VoidCallback? onAdd;
  final ValueChanged<Program> onEdit;
  final ValueChanged<Program> onDelete;

  const _DepartmentGroup({
    required this.department,
    required this.code,
    required this.accent,
    required this.programs,
    required this.enrolledIn,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = department.isEmpty ? 'No department' : department;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              if (code.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                programs.length == 1
                    ? '1 program'
                    : '${programs.length} programs',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate400,
                ),
              ),
              if (onAdd != null) ...[
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.maroon,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (programs.isEmpty)
            _EmptyDepartmentRow(onAdd: onAdd)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : (constraints.maxWidth >= 620 ? 2 : 1);
                const gap = 12.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final program in programs)
                      SizedBox(
                        width: width,
                        child: _ProgramCard(
                          program: program,
                          accent: accent,
                          enrolled: enrolledIn(program),
                          onEdit: () => onEdit(program),
                          onDelete: () => onDelete(program),
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
}

/// A department with no programs yet: a dashed prompt to add the first.
class _EmptyDepartmentRow extends StatelessWidget {
  final VoidCallback? onAdd;

  const _EmptyDepartmentRow({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.slate50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 17,
              color: AppTheme.slate400,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No programs yet. Add the first one for this department.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.slate500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One program: its code, full name, and how many students list it.
class _ProgramCard extends StatelessWidget {
  final Program program;
  final Color accent;
  final int enrolled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProgramCard({
    required this.program,
    required this.accent,
    required this.enrolled,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Text(
                  program.code,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const Spacer(),
              _CardAction(
                icon: Icons.edit_outlined,
                color: AppTheme.maroon,
                tooltip: 'Edit program',
                onTap: onEdit,
              ),
              const SizedBox(width: 6),
              _CardAction(
                icon: Icons.delete_outline_rounded,
                color: AppTheme.red500,
                tooltip: 'Delete program',
                onTap: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Two lines tall whatever the name, so cards in a row line up.
          SizedBox(
            height: 38,
            child: Text(
              program.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate900,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppTheme.slate100),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                size: 15,
                color: AppTheme.slate400,
              ),
              const SizedBox(width: 6),
              Text(
                switch (enrolled) {
                  0 => 'No students yet',
                  1 => '1 student',
                  _ => '$enrolled students',
                },
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _CardAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

/// Add or edit one program. Pops with the saved code.
class _ProgramDialog extends StatefulWidget {
  final Program? program;
  final String? department;

  const _ProgramDialog({required this.program, required this.department});

  @override
  State<_ProgramDialog> createState() => _ProgramDialogState();
}

class _ProgramDialogState extends State<_ProgramDialog> {
  late final _codeCtrl = TextEditingController(text: widget.program?.code);
  late final _nameCtrl = TextEditingController(text: widget.program?.name);
  String? _department;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.program != null;

  @override
  void initState() {
    super.initState();
    _department = widget.department;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final department = _department;
    if (department == null || code.isEmpty || name.isEmpty) {
      setState(() => _error = 'Choose a department and fill in both fields.');
      return;
    }
    final clash = state.programByCode(code);
    if (clash != null && clash.id != widget.program?.id) {
      setState(
        () => _error = '"${clash.code}" is already used by ${clash.name}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await state.saveProgram(
      Program(
        id: widget.program?.id ?? '',
        code: code,
        name: name,
        department: department,
      ),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = 'Could not save the program. Try again.';
      });
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final narrow = MediaQuery.of(context).size.width < 520;
    final departments = state.departments;

    final codeField = _field(
      label: 'Code',
      controller: _codeCtrl,
      hint: 'e.g. BSIT',
      icon: Icons.tag_rounded,
    );
    final nameField = _field(
      label: 'Program name',
      controller: _nameCtrl,
      hint: 'e.g. Bachelor of Science in Information Technology',
      icon: Icons.school_outlined,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.maroon50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      size: 20,
                      color: AppTheme.maroon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'Edit Program' : 'Add Program',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                        ),
                        const Text(
                          'Students pick it under its department',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppTheme.slate400,
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _label('Department'),
              DropdownButtonFormField<String>(
                initialValue: departments.contains(_department)
                    ? _department
                    : null,
                isExpanded: true,
                menuMaxHeight: 320,
                hint: const Text('Choose a department'),
                decoration: _decoration(icon: Icons.business_outlined),
                items: [
                  for (final d in departments)
                    DropdownMenuItem(
                      value: d,
                      child: Text(d, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _department = v;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              if (narrow) ...[
                codeField,
                const SizedBox(height: 16),
                nameField,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: codeField),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: nameField),
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.red50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.red500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(_isEditing ? 'Save Changes' : 'Add Program'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.maroon,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.slate700,
      ),
    ),
  );

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          controller: controller,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          style: const TextStyle(fontSize: 13, color: AppTheme.slate900),
          decoration: _decoration(icon: icon, hint: hint),
        ),
      ],
    );
  }

  InputDecoration _decoration({required IconData icon, String? hint}) =>
      InputDecoration(
        prefixIcon: Icon(icon, color: AppTheme.slate400, size: 18),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppTheme.slate400),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
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
      );
}
