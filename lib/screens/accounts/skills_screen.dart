import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final query = _search.trim().toLowerCase();
    final skills = state.skills
        .where((skill) => query.isEmpty || skill.toLowerCase().contains(query))
        .toList();
    // How many assistants list each skill — shows which ones actually matter.
    final usage = <String, int>{};
    for (final user in state.users) {
      if (user.role != 'Student Assistant') continue;
      for (final skill in state.skillsForUser(user)) {
        final key = skill.trim().toLowerCase();
        if (key.isEmpty) continue;
        usage[key] = (usage[key] ?? 0) + 1;
      }
    }
    final horizontal = isMobile ? 16.0 : 28.0;
    final columns = width >= 1280
        ? 3
        : width >= 820
        ? 2
        : 1;

    // The hero header scrolls away with the grid so the list is not
    // squeezed into the leftover space below a pinned header.
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 0),
            child: _SkillsHero(
              isMobile: isMobile,
              total: state.skills.length,
              inUse: state.skills
                  .where(
                    (skill) => (usage[skill.trim().toLowerCase()] ?? 0) > 0,
                  )
                  .length,
              onAdd: () => _showAddSkillDialog(context, state),
              onSearch: (value) => setState(() => _search = value),
            ),
          ),
          const SizedBox(height: 20),
          if (state.skills.isEmpty)
            const EmptyState(
              icon: Icons.star_outline_rounded,
              message: 'No skills yet — add one to get started',
            )
          else if (skills.isEmpty)
            const EmptyState(
              icon: Icons.search_off_rounded,
              message: 'No skills match your search',
            )
          else
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final tileWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final skill in skills)
                        SizedBox(
                          width: tileWidth,
                          child: _SkillTile(
                            skill: skill,
                            usageCount: usage[skill.trim().toLowerCase()] ?? 0,
                            onEdit: () =>
                                _showEditSkillDialog(context, state, skill),
                            onDelete: () => _deleteSkill(context, state, skill),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> _showAddSkillDialog(
    BuildContext context,
    AppState state,
  ) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _SkillDialog(
        title: 'Add Skill',
        subtitle: 'Skills appear as choices on the student application form',
        icon: Icons.add_rounded,
        controller: controller,
        onSave: () => state.addSkill(controller.text.trim()),
      ),
    );
    controller.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Skill saved.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  static Future<void> _showEditSkillDialog(
    BuildContext context,
    AppState state,
    String skill,
  ) async {
    final controller = TextEditingController(text: skill);
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _SkillDialog(
        title: 'Edit Skill',
        subtitle: 'Renaming updates this skill everywhere it is used',
        icon: Icons.edit_outlined,
        controller: controller,
        onSave: () => state.updateSkill(skill, controller.text.trim()),
      ),
    );
    controller.dispose();
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Skill updated.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  static Future<void> _deleteSkill(
    BuildContext context,
    AppState state,
    String skill,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Skill',
      message: 'Delete "$skill" from the application skill choices?',
      confirmLabel: 'Delete',
      confirmColor: AppTheme.red500,
    );
    if (!confirmed || !context.mounted) return;
    final deleted = await state.removeSkill(skill);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deleted ? 'Skill deleted.' : 'Could not delete skill.'),
        backgroundColor: deleted ? AppTheme.red500 : AppTheme.amber500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// ─── Hero header ────────────────────────────────────
class _SkillsHero extends StatelessWidget {
  final bool isMobile;
  final int total;
  final int inUse;
  final VoidCallback onAdd;
  final ValueChanged<String> onSearch;

  const _SkillsHero({
    required this.isMobile,
    required this.total,
    required this.inUse,
    required this.onAdd,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return HeroBanner(
      isMobile: isMobile,
      icon: Icons.auto_awesome_rounded,
      title: 'Skills',
      subtitle: 'Manage skills used in student applications',
      addLabel: 'Add Skill',
      searchHint: 'Search skills...',
      onAdd: onAdd,
      onSearch: onSearch,
      stats: [
        HeroStatData(
          label: 'Total skills',
          value: '$total',
          icon: Icons.style_rounded,
        ),
        HeroStatData(
          label: 'In use',
          value: '$inUse',
          icon: Icons.check_circle_rounded,
        ),
        HeroStatData(
          label: 'Unused',
          value: '${total - inUse}',
          icon: Icons.hourglass_empty_rounded,
        ),
      ],
    );
  }
}

// ─── Skill tile ─────────────────────────────────────
class _SkillTile extends StatefulWidget {
  final String skill;
  final int usageCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SkillTile({
    required this.skill,
    required this.usageCount,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_SkillTile> createState() => _SkillTileState();
}

class _SkillTileState extends State<_SkillTile> {
  bool _hovered = false;

  /// A stable accent per skill so the grid reads as a set of distinct
  /// cards rather than one repeated maroon block.
  static const _accents = [
    AppTheme.maroon,
    AppTheme.blue500,
    AppTheme.violet500,
    AppTheme.emerald500,
    AppTheme.amber500,
  ];

  Color get _accent {
    final key = widget.skill.trim().toLowerCase();
    if (key.isEmpty) return AppTheme.maroon;
    final hash = key.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return _accents[hash % _accents.length];
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final used = widget.usageCount > 0;
    final initial = widget.skill.trim().isEmpty
        ? '?'
        : widget.skill.trim()[0].toUpperCase();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered ? accent.withValues(alpha: 0.4) : AppTheme.slate200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.08 : 0.03),
              blurRadius: _hovered ? 14 : 8,
              offset: Offset(0, _hovered ? 5 : 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Accent spine
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.9),
                              accent.withValues(alpha: 0.6),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.28),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.skill,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: used
                                    ? AppTheme.emerald50
                                    : AppTheme.slate100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    used
                                        ? Icons.groups_rounded
                                        : Icons.person_off_outlined,
                                    size: 11,
                                    color: used
                                        ? AppTheme.emerald500
                                        : AppTheme.slate400,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    used
                                        ? '${widget.usageCount} assistant${widget.usageCount == 1 ? '' : 's'}'
                                        : 'Not used yet',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: used
                                          ? AppTheme.emerald500
                                          : AppTheme.slate400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _hovered || isTouchLayout(context) ? 1 : 0.55,
                        child: Row(
                          children: [
                            _TileAction(
                              icon: Icons.edit_outlined,
                              color: AppTheme.slate500,
                              tooltip: 'Edit skill',
                              onTap: widget.onEdit,
                            ),
                            const SizedBox(width: 4),
                            _TileAction(
                              icon: Icons.delete_outline_rounded,
                              color: AppTheme.red500,
                              tooltip: 'Delete skill',
                              onTap: widget.onDelete,
                            ),
                          ],
                        ),
                      ),
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
}

class _TileAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _TileAction({
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
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

// ─── Add / edit dialog ──────────────────────────────
class _SkillDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final TextEditingController controller;
  final Future<bool> Function() onSave;

  const _SkillDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.controller,
    required this.onSave,
  });

  @override
  State<_SkillDialog> createState() => _SkillDialogState();
}

class _SkillDialogState extends State<_SkillDialog> {
  bool _saving = false;

  Future<void> _save() async {
    if (widget.controller.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.onSave();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.maroon50,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(widget.icon, size: 19, color: AppTheme.maroon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: widget.controller,
          autofocus: true,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: 'SKILL NAME',
            hintText: 'e.g. Data encoding',
            prefixIcon: Icon(Icons.star_outline_rounded, size: 19),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppTheme.slate500),
          ),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
