import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 28,
            24,
            isMobile ? 16 : 28,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 4, height: 28, color: AppTheme.maroon),
                        const SizedBox(width: 10),
                        const Text(
                          'Skills',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 14, top: 3),
                      child: Text(
                        'Manage skills used in student applications',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.slate400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddSkillDialog(context, state),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Skill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.maroon,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: state.skills.isEmpty
              ? const Center(
                  child: Text(
                    'No skills yet',
                    style: TextStyle(
                      color: AppTheme.slate400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 28,
                    0,
                    isMobile ? 16 : 28,
                    28,
                  ),
                  itemCount: state.skills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final skill = state.skills[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_outline_rounded,
                            color: AppTheme.maroon,
                            size: 19,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              skill,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                _showEditSkillDialog(context, state, skill),
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: AppTheme.slate500,
                              size: 19,
                            ),
                            tooltip: 'Edit skill',
                          ),
                          IconButton(
                            onPressed: () =>
                                _deleteSkill(context, state, skill),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppTheme.red500,
                              size: 19,
                            ),
                            tooltip: 'Delete skill',
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static Future<void> _showAddSkillDialog(
    BuildContext context,
    AppState state,
  ) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Skill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Skill name',
            hintText: 'e.g. Data encoding',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final ok = await state.addSkill(name);
              if (dialogContext.mounted) Navigator.pop(dialogContext, ok);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Skill saved.'),
          backgroundColor: AppTheme.emerald500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Skill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Skill name',
            hintText: 'e.g. Data encoding',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final ok = await state.updateSkill(skill, name);
              if (dialogContext.mounted) Navigator.pop(dialogContext, ok);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Skill updated.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        margin: const EdgeInsets.all(16),),
    );
  }
}