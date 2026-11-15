import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/task_template.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'task_form_parts.dart';
import 'task_template_dialog.dart';

/// Opens the Head's Manage Categories dialog.
Future<void> showManageCategoriesDialog(BuildContext context) {
  final state = context.read<AppState>();
  return showDialog<void>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: const ManageCategoriesDialog(),
    ),
  );
}

/// The Head's list of task categories: add one, rename one (the tasks and
/// templates filed under it follow) or delete one nothing is filed under.
/// Opening a category shows the tasks given under it and its templates: the
/// ready-made tasks a Supervisor can pick when assigning one. Results show in the dialog
/// itself, so it stays open while the Head works down the list.
class ManageCategoriesDialog extends StatefulWidget {
  const ManageCategoriesDialog({super.key});

  @override
  State<ManageCategoriesDialog> createState() => _ManageCategoriesDialogState();
}

class _ManageCategoriesDialogState extends State<ManageCategoriesDialog> {
  final _addCtrl = TextEditingController();
  final _renameCtrl = TextEditingController();
  String? _renaming;
  String? _open;
  String? _message;
  bool _isError = false;
  bool _busy = false;

  @override
  void dispose() {
    _addCtrl.dispose();
    _renameCtrl.dispose();
    super.dispose();
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _isError = error;
    });
  }

  Future<void> _add() async {
    final state = context.read<AppState>();
    final name = _addCtrl.text.trim();
    if (name.isEmpty || _busy) return;
    final clash = state.findTaskCategory(name);
    if (clash != null) {
      _say('"$clash" is already a task category.', error: true);
      return;
    }
    setState(() => _busy = true);
    final saved = await state.addTaskCategory(name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved) {
      _addCtrl.clear();
      _say('Added "$name".');
    } else {
      _say(
        "Couldn't save \"$name\". Check your connection and try again.",
        error: true,
      );
    }
  }

  Future<void> _rename(String from) async {
    if (_busy) return;
    final state = context.read<AppState>();
    final to = _renameCtrl.text.trim();
    setState(() => _busy = true);
    final problem = await state.renameTaskCategory(from, to);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (problem == null) {
        _renaming = null;
        if (_open == from) _open = to;
      }
    });
    if (problem != null) {
      _say(problem, error: true);
    } else if (to != from) {
      _say('Renamed "$from" to "$to".');
    }
  }

  Future<void> _delete(String name) async {
    if (_busy) return;
    final state = context.read<AppState>();
    final ok = await showConfirmDialog(
      context,
      title: 'Delete Category',
      message: 'Delete "$name"? No task or template is filed under it.',
      confirmLabel: 'Delete',
      confirmColor: AppTheme.red500,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final problem = await state.deleteTaskCategory(name);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(problem ?? 'Deleted "$name".', error: problem != null);
  }

  Future<void> _deleteTemplate(TaskTemplate template) async {
    if (_busy) return;
    final state = context.read<AppState>();
    final ok = await showConfirmDialog(
      context,
      title: 'Delete Template',
      message:
          'Delete "${template.title}"? Tasks already made from it are not '
          'changed.',
      confirmLabel: 'Delete',
      confirmColor: AppTheme.red500,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final problem = await state.deleteTaskTemplate(template.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(problem ?? 'Deleted "${template.title}".', error: problem != null);
  }

  void _startRename(String name) {
    _renameCtrl.text = name;
    setState(() {
      _renaming = name;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 520;
    final pad = narrow ? 16.0 : 24.0;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 12 : 24,
        vertical: 24,
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaskFormHeader(
              icon: Icons.category_rounded,
              title: 'Task Categories',
              subtitle: 'Organize tasks and their templates',
              onClose: () => Navigator.pop(context),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 18, pad, 0),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(inputDecorationTheme: taskInputTheme()),
                child: _addRow(),
              ),
            ),
            if (_message != null)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                child: _messageBanner(),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 20, pad, 10),
              child: Row(
                children: [
                  const TaskSectionLabel('CATEGORIES'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.slate100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${state.taskCategories.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                itemCount: state.taskCategories.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _row(state, state.taskCategories[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _addCtrl,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'New category name',
              prefixIcon: Icon(Icons.add_rounded, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _busy ? null : _add,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.maroon,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            child: const Text('Add'),
          ),
        ),
      ],
    );
  }

  Widget _messageBanner() {
    final color = _isError ? AppTheme.red500 : AppTheme.emerald500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.slate600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(AppState state, String name) {
    final editing = _renaming == name;
    final open = _open == name && !editing;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: editing ? AppTheme.maroon50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: editing || open ? AppTheme.maroon200 : AppTheme.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: editing ? _renameRow(name) : _plainRow(state, name, open),
          ),
          if (open) _templates(state, name),
        ],
      ),
    );
  }

  Widget _plainRow(AppState state, String name, bool open) {
    final isDefault = name == AppState.fallbackTaskCategory;
    final used = state.tasksInCategory(name);
    final templates = state.templatesIn(name).length;
    final duties = state.dutiesInCategory(name);
    final inUse = used > 0 || templates > 0 || duties > 0;
    final summary = [
      used == 0 ? 'No tasks yet' : (used == 1 ? '1 task' : '$used tasks'),
      if (templates > 0) templates == 1 ? '1 template' : '$templates templates',
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              _open = open ? null : name;
              // The ticks belong to the category that was open.
              _picked.clear();
              _showAllTasks = false;
            }),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.maroon50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    open ? Icons.folder_open_rounded : Icons.folder_rounded,
                    size: 17,
                    color: AppTheme.maroon,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slate900,
                              ),
                            ),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.slate100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Default',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: AppTheme.slate400,
                ),
              ],
            ),
          ),
        ),
        if (!isDefault) ...[
          IconButton(
            tooltip: 'Rename',
            onPressed: _busy ? null : () => _startRename(name),
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppTheme.slate500,
          ),
          IconButton(
            tooltip: !inUse
                ? 'Delete'
                : used > 0
                ? "In use by $used task${used == 1 ? '' : 's'}, so it can't "
                      'be deleted'
                : duties > 0
                ? "It has ongoing duties, so it can't be deleted"
                : "It has templates, so it can't be deleted",
            onPressed: _busy || inUse ? null : () => _delete(name),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: AppTheme.red500,
            disabledColor: AppTheme.slate300,
          ),
        ] else
          const SizedBox(width: 6),
      ],
    );
  }

  Widget _renameRow(String name) {
    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: taskInputTheme()),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _renameCtrl,
              autofocus: true,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _rename(name),
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Category name',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Save',
            onPressed: _busy ? null : () => _rename(name),
            icon: const Icon(Icons.check_rounded, size: 20),
            color: AppTheme.emerald500,
          ),
          IconButton(
            tooltip: 'Cancel',
            onPressed: _busy ? null : () => setState(() => _renaming = null),
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppTheme.slate500,
          ),
        ],
      ),
    );
  }

  /// The templates under an opened category, with a button to add one.
  Widget _templates(AppState state, String category) {
    final templates = state.templatesIn(category);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.slate50,
        border: Border(top: BorderSide(color: AppTheme.slate100)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._taskList(state, category),
          const TaskSectionLabel('TEMPLATES'),
          const SizedBox(height: 10),
          if (templates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'No templates yet. Add the tasks Supervisors give most, so '
                'they can pick one instead of typing it out.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppTheme.slate500,
                ),
              ),
            ),
          for (final t in templates) ...[
            _templateTile(t, category),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => showTaskTemplateDialog(context, category: category),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Add template'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.maroon,
                side: const BorderSide(color: AppTheme.maroon200),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Titles listed before "Show all".
  static const _shownTaskTitles = 10;

  /// The titles ticked to become templates (lower-case, as grouped).
  final _picked = <String>{};
  bool _showAllTasks = false;

  /// The tasks Supervisors have given under [category], by title with how
  /// many were given (the same tasks the row's count adds up). Each can be
  /// ticked to become a template; several at once make several templates.
  /// Empty when there are none.
  List<Widget> _taskList(AppState state, String category) {
    final groups = state.taskTitleGroups(state.tasks, category);
    if (groups.isEmpty) return const [];
    final have = {
      for (final t in state.templatesIn(category)) t.title.trim().toLowerCase(),
    };
    bool tickable(TaskTitleGroup g) =>
        !g.latest.isDutyLog && !have.contains(g.title.toLowerCase());
    final canTick = groups.where(tickable).toList();
    final picked = [
      for (final g in canTick)
        if (_picked.contains(g.title.toLowerCase())) g,
    ];
    final shown = _showAllTasks
        ? groups
        : groups.take(_shownTaskTitles).toList();
    return [
      Row(
        children: [
          const Expanded(child: TaskSectionLabel('TASKS GIVEN')),
          if (canTick.isNotEmpty)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      if (picked.length == canTick.length) {
                        _picked.clear();
                      } else {
                        _picked.addAll(
                          canTick.map((g) => g.title.toLowerCase()),
                        );
                      }
                    }),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.maroon,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              child: Text(
                picked.length == canTick.length ? 'Clear' : 'Select all',
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.slate200),
        ),
        // Scrolls inside, so a long list doesn't push the rest away.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SingleChildScrollView(
            child: Column(
              children: [for (final g in shown) _taskRow(g, tickable(g))],
            ),
          ),
        ),
      ),
      if (groups.length > _shownTaskTitles)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAllTasks = !_showAllTasks),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.slate600,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            child: Text(
              _showAllTasks ? 'Show fewer' : 'Show all ${groups.length}',
            ),
          ),
        ),
      if (picked.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: _busy ? null : () => _makeTemplates(category, picked),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.maroon,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    picked.length == 1
                        ? 'Make 1 template'
                        : 'Make ${picked.length} templates',
                  ),
          ),
        ),
      ],
      const SizedBox(height: 16),
    ];
  }

  /// One title of the list: a tick box (a quiet "Template" tag when it
  /// already is one, nothing for an ongoing duty's log), the title and how
  /// many were given.
  Widget _taskRow(TaskTitleGroup g, bool tickable) {
    final key = g.title.toLowerCase();
    final ticked = _picked.contains(key);
    final isTemplate = !g.latest.isDutyLog && !tickable;
    return InkWell(
      onTap: !tickable || _busy
          ? null
          : () => setState(() {
              if (!_picked.remove(key)) _picked.add(key);
            }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: tickable
                  ? Checkbox(
                      value: ticked,
                      activeColor: AppTheme.maroon,
                      visualDensity: VisualDensity.compact,
                      onChanged: _busy
                          ? null
                          : (_) => setState(() {
                              if (!_picked.remove(key)) _picked.add(key);
                            }),
                    )
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  g.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate900,
                  ),
                ),
              ),
            ),
            if (isTemplate) ...[
              const SizedBox(width: 8),
              const Text(
                'Template',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                ),
              ),
            ],
            if (g.count > 1) ...[
              const SizedBox(width: 8),
              Text(
                '×${g.count}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Makes a template of each ticked task and says how it went.
  Future<void> _makeTemplates(
    String category,
    List<TaskTitleGroup> chosen,
  ) async {
    if (_busy) return;
    final state = context.read<AppState>();
    setState(() => _busy = true);
    final result = await state.saveTaskTemplatesFromTasks(category, chosen);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.problem == null) _picked.clear();
    });
    final problem = result.problem;
    if (problem != null) {
      _say(problem, error: true);
      return;
    }
    final skipped = result.skipped == 0
        ? ''
        : ' Left out ${result.skipped} that already had one.';
    _say(
      result.made == 0
          ? 'Nothing new to make.$skipped'
          : 'Made ${result.made} template${result.made == 1 ? '' : 's'}.'
                '$skipped',
    );
  }

  Widget _templateTile(TaskTemplate t, String category) {
    final steps = t.checklist.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: PriorityChips.colorOf(t.priority),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
                Text(
                  steps == 0
                      ? '${t.priority} priority'
                      : '${t.priority} priority · $steps '
                            'step${steps == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit template',
            onPressed: _busy
                ? null
                : () => showTaskTemplateDialog(
                    context,
                    category: category,
                    existing: t,
                  ),
            icon: const Icon(Icons.edit_outlined, size: 17),
            color: AppTheme.slate500,
          ),
          IconButton(
            tooltip: 'Delete template',
            onPressed: _busy ? null : () => _deleteTemplate(t),
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            color: AppTheme.red500,
          ),
        ],
      ),
    );
  }
}
