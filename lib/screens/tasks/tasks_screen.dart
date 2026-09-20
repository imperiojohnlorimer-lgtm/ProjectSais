import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Formats a due date the way tasks store it everywhere else in the app
/// ("Mon D, YYYY", e.g. "Sep 19, 2026").
String _formatDueDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Reads a due date back out of the "Mon D, YYYY" form tasks store it in.
/// Returns null for anything that does not parse, so callers can treat the
/// date as unknown rather than overdue.
DateTime? _parseDueDate(String raw) {
  const months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  final parts = raw.replaceAll(',', '').trim().split(RegExp(r'\s+'));
  if (parts.length < 3) return null;
  final month = months.indexOf(parts[0].toLowerCase().substring(0, 3)) + 1;
  final day = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (month == 0 || day == null || year == null) return null;
  return DateTime(year, month, day);
}

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _filterStatus = 'All';
  String _search = '';
  final Set<String> _pendingIds = {};

  static const _statuses = [
    'All',
    'Not Started',
    'In Progress',
    'Completed',
    'Archived',
  ];

  static const Map<String, IconData> _statusIcons = {
    'All': Icons.apps_rounded,
    'Not Started': Icons.radio_button_unchecked_rounded,
    'In Progress': Icons.autorenew_rounded,
    'Completed': Icons.check_circle_rounded,
    'Archived': Icons.archive_rounded,
  };

  Color _statusColor(String s) {
    switch (s) {
      case 'Not Started':
        return AppTheme.slate500;
      case 'In Progress':
        return AppTheme.blue500;
      case 'Completed':
        return AppTheme.emerald500;
      case 'Archived':
        return AppTheme.slate400;
      default:
        return AppTheme.maroon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final role = state.role;

    final query = _search.trim().toLowerCase();
    final tasks = state.filteredTasks.where((t) {
      if (_filterStatus == 'Archived') {
        if (!t.isArchived) return false;
      } else {
        if (t.isArchived) return false;
        if (_filterStatus != 'All' && t.status != _filterStatus) return false;
      }
      return query.isEmpty ||
          t.title.toLowerCase().contains(query) ||
          t.description.toLowerCase().contains(query) ||
          (t.assignedToName ?? '').toLowerCase().contains(query) ||
          (t.category ?? '').toLowerCase().contains(query);
    }).toList();

    final liveTasks = state.filteredTasks.where((t) => !t.isArchived).toList();
    // Anything still open whose due date has already passed.
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final overdueCount = liveTasks.where((t) {
      if (t.status == 'Completed') return false;
      final due = _parseDueDate(t.dueDate);
      return due != null && due.isBefore(startOfToday);
    }).length;
    final isMobile = MediaQuery.of(context).size.width < 700;
    final statusCounts = <String, int>{
      for (final s in _statuses)
        s: s == 'All'
            ? liveTasks.length
            : s == 'Archived'
            ? state.filteredTasks.where((t) => t.isArchived).length
            : liveTasks.where((t) => t.status == s).length,
    };
    final completedCount = statusCounts['Completed'] ?? 0;
    final progress = liveTasks.isEmpty
        ? 0.0
        : completedCount / liveTasks.length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeroBanner(
                  isMobile: isMobile,
                  icon: Icons.task_alt_rounded,
                  title: 'Tasks',
                  subtitle: role == 'Student Assistant'
                      ? 'Your assigned tasks and their progress'
                      : 'Assign and track student assistant tasks',
                  searchHint: 'Search tasks...',
                  onSearch: (value) => setState(() => _search = value),
                  addLabel: role == 'Supervisor' ? 'Assign Task' : null,
                  onAdd: role == 'Supervisor'
                      ? () => _showAddDialog(context, state)
                      : null,
                  filters: [
                    if (role == 'Head')
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showManageCategoriesDialog(context, state),
                        icon: const Icon(Icons.category_rounded, size: 16),
                        label: const Text('Categories'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.maroon,
                          side: const BorderSide(
                            color: AppTheme.maroon,
                            width: 1.3,
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
                      label: 'Tasks',
                      value: '${liveTasks.length}',
                      icon: Icons.assignment_outlined,
                    ),
                    HeroStatData(
                      label: 'In progress',
                      value: '${statusCounts['In Progress'] ?? 0}',
                      icon: Icons.autorenew_rounded,
                    ),
                    HeroStatData(
                      label: 'Completed',
                      value: '$completedCount',
                      icon: Icons.check_circle_rounded,
                    ),
                    HeroStatData(
                      label: 'Overdue',
                      value: '$overdueCount',
                      icon: Icons.event_busy_rounded,
                    ),
                  ],
                ),
                if (liveTasks.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ProgressSummary(
                    progress: progress,
                    completedCount: completedCount,
                    totalCount: liveTasks.length,
                  ),
                ],
                const SizedBox(height: 14),

                // Status filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statuses.map((s) {
                      final selected = _filterStatus == s;
                      final color = _statusColor(s);
                      return GestureDetector(
                        onTap: () => setState(() => _filterStatus = s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withValues(alpha: 0.1)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? color.withValues(alpha: 0.5)
                                  : AppTheme.slate200,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _statusIcons[s],
                                size: 14,
                                color: selected ? color : AppTheme.slate400,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                s,
                                style: TextStyle(
                                  color: selected ? color : AppTheme.slate600,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              if ((statusCounts[s] ?? 0) > 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${statusCounts[s]}',
                                  style: TextStyle(
                                    color: selected ? color : AppTheme.slate400,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        if (tasks.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _emptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverList.list(
              children: [
                for (int i = 0; i < tasks.length; i++) ...[
                  _TaskCard(
                    task: tasks[i],
                    role: role,
                    isBusy: _pendingIds.contains(tasks[i].id),
                    onStatusChange: (newStatus) async {
                      setState(() => _pendingIds.add(tasks[i].id));
                      await state.updateTaskStatus(tasks[i].id, newStatus);
                      if (!context.mounted) return;
                      setState(() => _pendingIds.remove(tasks[i].id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Task status updated to "$newStatus"'),
                          backgroundColor: AppTheme.blue500,
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    },
                    onDelete: () async {
                      final ok = await showConfirmDialog(
                        context,
                        title: 'Delete Task',
                        message: 'Delete this task?',
                        confirmLabel: 'Delete',
                      );
                      if (ok) {
                        setState(() => _pendingIds.add(tasks[i].id));
                        await state.deleteTask(tasks[i].id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Task deleted successfully'),
                            backgroundColor: AppTheme.red500,
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                      }
                    },
                    onArchive: role == 'Supervisor'
                        ? () async {
                            final willArchive = !tasks[i].isArchived;
                            final ok = await showConfirmDialog(
                              context,
                              title: willArchive
                                  ? 'Archive Task'
                                  : 'Restore Task',
                              message: willArchive
                                  ? 'Archive this task? It will be moved out of the active list.'
                                  : 'Restore this task back to the active list?',
                              confirmLabel: willArchive ? 'Archive' : 'Restore',
                              confirmColor: willArchive
                                  ? AppTheme.slate600
                                  : AppTheme.emerald500,
                            );
                            if (!ok) return;
                            setState(() => _pendingIds.add(tasks[i].id));
                            await state.setTaskArchived(
                              tasks[i].id,
                              willArchive,
                            );
                            if (!context.mounted) return;
                            setState(() => _pendingIds.remove(tasks[i].id));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  willArchive
                                      ? 'Task archived'
                                      : 'Task restored',
                                ),
                                backgroundColor: willArchive
                                    ? AppTheme.slate600
                                    : AppTheme.emerald500,
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                          }
                        : null,
                  ),
                  if (i < tasks.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.slate100, AppTheme.slate50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.task_alt_outlined,
              size: 38,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No tasks found',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _search.trim().isEmpty
                ? 'Try a different filter, or assign a new task.'
                : 'No tasks match your search.',
            style: const TextStyle(fontSize: 12.5, color: AppTheme.slate400),
          ),
        ],
      ),
    ),
  );

  void _showAddDialog(BuildContext context, AppState state) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final itemCtrl = TextEditingController();
    String priority = 'Medium';
    String category = state.taskCategories.isNotEmpty
        ? state.taskCategories.first
        : 'General';
    String? assignedTo;
    // Defaults to a week from today; the supervisor can pick any date.
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    List<String> checklistItems = [];

    final students = state.filteredStudents;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              14,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.slate200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppTheme.maroon50,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.assignment_add,
                          color: AppTheme.maroon,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Assign Task',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.slate100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _dialogField(
                    child: TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Task Title',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    child: TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    child: DropdownButtonFormField<String>(
                      initialValue: priority,
                      icon: const Icon(
                        Icons.expand_more_rounded,
                        color: AppTheme.slate400,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                      items: ['High', 'Medium', 'Low']
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: (v) => setSt(() => priority = v!),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    child: DropdownButtonFormField<String>(
                      initialValue: category,
                      icon: const Icon(
                        Icons.expand_more_rounded,
                        color: AppTheme.slate400,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                      items: state.taskCategories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) => setSt(() => category = v ?? category),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    child: DropdownButtonFormField<String>(
                      initialValue: assignedTo,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.expand_more_rounded,
                        color: AppTheme.slate400,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Assign To',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                      items: students
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(
                                s.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setSt(() => assignedTo = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final today = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: dueDate,
                          firstDate: DateTime(
                            today.year,
                            today.month,
                            today.day,
                          ),
                          lastDate: DateTime(today.year + 5, 12, 31),
                        );
                        if (picked != null) setSt(() => dueDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Due Date',
                          border: InputBorder.none,
                          suffixIcon: Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: AppTheme.slate400,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        child: Text(_formatDueDate(dueDate)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    child: TextFormField(
                      controller: itemCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Checklist item',
                        hintText: 'Add a checklist step',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final value = itemCtrl.text.trim();
                        if (value.isNotEmpty) {
                          setSt(() {
                            checklistItems = [...checklistItems, value];
                            itemCtrl.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Item'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.maroon,
                        side: const BorderSide(
                          color: AppTheme.maroon,
                          width: 1.3,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (checklistItems.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: checklistItems.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return Chip(
                          label: Text(
                            item,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          backgroundColor: AppTheme.maroon50,
                          side: BorderSide(
                            color: AppTheme.maroon.withValues(alpha: 0.15),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          deleteIconColor: AppTheme.maroon,
                          onDeleted: () =>
                              setSt(() => checklistItems.removeAt(index)),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.maroon.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          if (titleCtrl.text.trim().isEmpty) return;
                          final student = assignedTo != null
                              ? students.firstWhere(
                                  (s) => s.id == assignedTo,
                                  orElse: () => students.first,
                                )
                              : null;
                          final task = Task(
                            id: 't_${DateTime.now().millisecondsSinceEpoch}',
                            title: titleCtrl.text.trim(),
                            description: descCtrl.text.trim(),
                            status: 'Not Started',
                            priority: priority,
                            dueDate: _formatDueDate(dueDate),
                            assignedTo: student?.id,
                            assignedToName: student?.name,
                            category: category,
                            checklistItems: checklistItems,
                          );
                          await state.addTask(task);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Task assigned successfully!',
                              ),
                              backgroundColor: AppTheme.emerald500,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text(
                          'Assign Task',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
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

  Widget _dialogField({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: AppTheme.slate50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.slate200),
    ),
    child: child,
  );

  void _showManageCategoriesDialog(BuildContext context, AppState state) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.maroon.withValues(alpha: 0.15),
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
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.maroon,
                      AppTheme.maroon.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.folder_open_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Categories',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Organize your tasks',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Input row
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F4F5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.maroon200),
                            ),
                            child: TextField(
                              controller: controller,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'New category name…',
                                hintStyle: TextStyle(
                                  color: AppTheme.slate400,
                                  fontSize: 13,
                                ),
                                prefixIcon: Icon(
                                  Icons.add_rounded,
                                  color: AppTheme.maroon.withValues(alpha: 0.5),
                                  size: 18,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            final value = controller.text.trim();
                            if (value.isNotEmpty) {
                              state.addTaskCategory(value);
                              controller.clear();
                              Navigator.pop(ctx);
                              showDialog(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Category Added'),
                                  content: Text(
                                    '"$value" has been added to task categories.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.maroon,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.maroon.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          'CATEGORIES',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate400,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Divider(color: AppTheme.maroon200, height: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView(
                        shrinkWrap: true,
                        children: state.taskCategories.map((category) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBF8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.maroon200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppTheme.maroon.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.folder_rounded,
                                    size: 14,
                                    color: AppTheme.maroon,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    category,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: AppTheme.slate300,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim completion strip under the header: a label, the count and a bar.
class _ProgressSummary extends StatelessWidget {
  final double progress;
  final int completedCount;
  final int totalCount;

  const _ProgressSummary({
    required this.progress,
    required this.completedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress.clamp(0, 1) * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.donut_small_rounded,
            size: 15,
            color: AppTheme.maroon,
          ),
          const SizedBox(width: 8),
          const Text(
            'Overall progress',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(height: 8, color: AppTheme.slate100),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: progress.clamp(0, 1)),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => Container(
                            height: 8,
                            width: constraints.maxWidth * value,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.maroon, AppTheme.maroonLight],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$completedCount/$totalCount',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($pct%)',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate400,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final String role;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;
  final bool isBusy;

  const _TaskCard({
    required this.task,
    required this.role,
    required this.onStatusChange,
    required this.onDelete,
    this.onArchive,
    this.isBusy = false,
  });

  Color get _priorityAccent {
    switch (task.priority) {
      case 'High':
        return AppTheme.red500;
      case 'Medium':
        return AppTheme.amber500;
      default:
        return AppTheme.blue500;
    }
  }

  /// Open task whose due date has already passed.
  bool get _isOverdue {
    if (task.status == 'Completed' || task.isArchived) return false;
    final due = _parseDueDate(task.dueDate);
    if (due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }

  IconData get _priorityIcon {
    switch (task.priority) {
      case 'High':
        return Icons.keyboard_double_arrow_up_rounded;
      case 'Medium':
        return Icons.drag_handle_rounded;
      default:
        return Icons.keyboard_arrow_down_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isBusy ? 0.5 : 1,
          child: IgnorePointer(ignoring: isBusy, child: _cardBody(context)),
        ),
        if (isBusy)
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppTheme.maroon,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardBody(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _priorityAccent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 4, color: _priorityAccent),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppTheme.slate900,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _priorityAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _priorityAccent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _priorityIcon,
                              size: 12,
                              color: _priorityAccent,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              task.priority,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _priorityAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (role == 'Supervisor') ...[
                        const SizedBox(width: 6),
                        if (onArchive != null)
                          GestureDetector(
                            onTap: onArchive,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.slate50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                task.isArchived
                                    ? Icons.unarchive_rounded
                                    : Icons.archive_rounded,
                                size: 15,
                                color: AppTheme.slate400,
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.red50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.delete_rounded,
                              size: 15,
                              color: AppTheme.red500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      task.description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate500,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      if (task.assignedToName != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.maroon,
                                    AppTheme.maroon.withValues(alpha: 0.7),
                                  ],
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                task.assignedToName!.trim().isNotEmpty
                                    ? task.assignedToName!
                                          .trim()[0]
                                          .toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              task.assignedToName!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.slate600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isOverdue
                                ? Icons.event_busy_rounded
                                : Icons.calendar_today_rounded,
                            size: 12,
                            color: _isOverdue
                                ? AppTheme.red500
                                : AppTheme.slate400,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Due: ${task.dueDate}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isOverdue
                                  ? AppTheme.red500
                                  : AppTheme.slate600,
                              fontWeight: _isOverdue
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          if (_isOverdue) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.red50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.red500.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Text(
                                'OVERDUE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: AppTheme.red500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  if (task.category != null && task.category!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.maroon50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.maroon.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_rounded,
                            size: 12,
                            color: AppTheme.maroon,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            task.category!,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.maroon,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (task.checklistItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Checklist (${task.checklistItems.length})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...task.checklistItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_box_outline_blank_rounded,
                                    size: 14,
                                    color: AppTheme.slate400,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.slate600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Status selector
                  if (task.isArchived)
                    Row(
                      children: const [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppTheme.slate400,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Archived tasks cannot be edited.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slate500,
                          ),
                        ),
                      ],
                    )
                  else if (role == 'Student Assistant')
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Not Started', 'In Progress', 'Completed'].map(
                        (s) {
                          final isActive = task.status == s;
                          final color = s == 'Completed'
                              ? AppTheme.emerald500
                              : s == 'In Progress'
                              ? AppTheme.blue500
                              : AppTheme.slate500;
                          return GestureDetector(
                            onTap: () => onStatusChange(s),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isActive ? color : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isActive ? color : AppTheme.slate200,
                                ),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.28),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Text(
                                s,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: isActive
                                      ? Colors.white
                                      : AppTheme.slate600,
                                ),
                              ),
                            ),
                          );
                        },
                      ).toList(),
                    )
                  else
                    StatusBadge.fromStatus(task.displayStatus),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
