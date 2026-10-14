import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../models/task_template.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'task_dates.dart';
import 'task_form_parts.dart';

/// Opens the Supervisor's Assign Task form.
Future<void> showAssignTaskSheet(BuildContext context) {
  final state = context.read<AppState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: const AssignTaskSheet(),
    ),
  );
}

/// The Supervisor's Assign Task form. Picking one of the Head's templates
/// for the chosen category fills in the title, description, priority and
/// checklist; everything stays editable, and the task made is its own copy.
class AssignTaskSheet extends StatefulWidget {
  const AssignTaskSheet({super.key});

  @override
  State<AssignTaskSheet> createState() => _AssignTaskSheetState();
}

class _AssignTaskSheetState extends State<AssignTaskSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late String _category;
  String _priority = 'Medium';
  String? _assignedTo;
  // Defaults to a week from today; the supervisor can pick any date.
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  List<String> _checklist = [];
  // An ongoing duty has no due date: the student logs it on days they clock
  // in, instead of finishing it once.
  bool _ongoing = false;
  // The template the form was last filled from, and what it put there, so
  // a later pick only asks before replacing something the supervisor typed.
  String? _templateId;
  ({String title, String description, String priority, List<String> checklist})?
  _applied;
  String? _error;
  // Set while the task saves, so a second tap can't assign it twice.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final categories = context.read<AppState>().taskCategories;
    _category = categories.isNotEmpty
        ? categories.first
        : AppState.fallbackTaskCategory;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Whether the title, description or checklist hold anything other than
  /// what the last template put there (or nothing, when none was picked).
  bool get _hasTypedContent {
    final base = _applied;
    final title = _title.text.trim();
    final description = _description.text.trim();
    if (base == null) {
      return title.isNotEmpty ||
          description.isNotEmpty ||
          _checklist.isNotEmpty;
    }
    return title != base.title ||
        description != base.description ||
        _priority != base.priority ||
        _checklist.join('\n') != base.checklist.join('\n');
  }

  Future<void> _pickTemplate(TaskTemplate template) async {
    if (_saving) return;
    if (_templateId == template.id) {
      // Tapping the chosen one again just lets go of it.
      setState(() {
        _templateId = null;
        _applied = null;
      });
      return;
    }
    if (_hasTypedContent) {
      final replace = await showConfirmDialog(
        context,
        title: 'Use This Template?',
        message:
            'It will replace the title, description and checklist you '
            'have written.',
        confirmLabel: 'Replace',
      );
      if (!replace || !mounted) return;
    }
    setState(() {
      _templateId = template.id;
      _title.text = template.title;
      _description.text = template.description;
      _priority = template.priority;
      _ongoing = template.ongoing;
      _checklist = [...template.checklist];
      _applied = (
        title: template.title,
        description: template.description,
        priority: template.priority,
        checklist: [...template.checklist],
      );
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _assign() async {
    if (_saving) return;
    final state = context.read<AppState>();
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the task a title.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final students = state.filteredStudents;
    final student = _assignedTo == null
        ? null
        : students.where((s) => s.id == _assignedTo).firstOrNull;
    if (_ongoing) {
      await _giveDuty(state, student, navigator, messenger);
      return;
    }
    final saved = await state.addTask(
      Task(
        id: 't_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        description: _description.text.trim(),
        status: 'Not Started',
        priority: _priority,
        dueDate: formatDueDate(_dueDate),
        assignedTo: student?.id,
        assignedToName: student?.name,
        category: _category,
        checklistItems: _checklist,
      ),
    );
    if (!mounted) return;
    if (!saved) {
      // Stay open, so nothing typed is lost.
      setState(() {
        _saving = false;
        _error =
            "Couldn't assign the task. Check your connection and try again.";
      });
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Task assigned successfully!'),
        backgroundColor: AppTheme.emerald500,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Gives the chosen student an ongoing duty instead of a one-off task.
  Future<void> _giveDuty(
    AppState state,
    Student? student,
    NavigatorState navigator,
    ScaffoldMessengerState messenger,
  ) async {
    if (student == null) {
      setState(() {
        _saving = false;
        _error = 'Choose who this ongoing duty is for.';
      });
      return;
    }
    final problem = await state.createTaskDuty(
      title: _title.text,
      description: _description.text,
      priority: _priority,
      category: _category,
      student: student,
    );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _saving = false;
        _error = problem;
      });
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${student.name} can now log this duty on days they clock in.',
        ),
        backgroundColor: AppTheme.emerald500,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 520;
    final pad = narrow ? 16.0 : 24.0;
    // The Head may rename or delete the chosen category while this is open.
    if (!state.taskCategories.contains(_category)) {
      _category = state.taskCategories.isNotEmpty
          ? state.taskCategories.first
          : AppState.fallbackTaskCategory;
      _templateId = null;
      _applied = null;
    }
    final templates = state.templatesIn(_category);
    final students = state.filteredStudents;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: size.height * 0.94),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: AppTheme.slate200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            TaskFormHeader(
              icon: Icons.assignment_add,
              title: 'Assign Task',
              subtitle: 'Give a student assistant something to do',
              onClose: _saving ? null : () => Navigator.pop(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
                child: IgnorePointer(
                  ignoring: _saving,
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(inputDecorationTheme: taskInputTheme()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const TaskSectionLabel('CATEGORY'),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _category,
                          isExpanded: true,
                          icon: const Icon(
                            Icons.expand_more_rounded,
                            color: AppTheme.slate400,
                          ),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.folder_outlined, size: 19),
                          ),
                          items: [
                            for (final c in state.taskCategories)
                              DropdownMenuItem(
                                value: c,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            if (v == null || v == _category) return;
                            _category = v;
                            // A template belongs to one category.
                            _templateId = null;
                            _applied = null;
                          }),
                        ),
                        if (templates.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const TaskSectionLabel('START FROM A TEMPLATE'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in templates) _templateChip(t),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        const TaskSectionLabel('TASK'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _title,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Task title',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _description,
                          minLines: 3,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const TaskSectionLabel('ASSIGNMENT'),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _assignedTo,
                          isExpanded: true,
                          icon: const Icon(
                            Icons.expand_more_rounded,
                            color: AppTheme.slate400,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Assign to',
                            prefixIcon: Icon(Icons.person_outline, size: 19),
                          ),
                          items: [
                            for (final s in students)
                              DropdownMenuItem(
                                value: s.id,
                                child: Text(
                                  s.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _assignedTo = v),
                        ),
                        const SizedBox(height: 14),
                        _ongoingSwitch(),
                        if (!_ongoing) ...[
                          const SizedBox(height: 14),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Due date',
                                prefixIcon: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                ),
                              ),
                              child: Text(
                                formatDueDate(_dueDate),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        const TaskSectionLabel('PRIORITY'),
                        const SizedBox(height: 10),
                        PriorityChips(
                          value: _priority,
                          onChanged: (p) => setState(() => _priority = p),
                        ),
                        if (!_ongoing) ...[
                          const SizedBox(height: 24),
                          const TaskSectionLabel('CHECKLIST', optional: true),
                          const SizedBox(height: 10),
                          ChecklistEditor(
                            items: _checklist,
                            onChanged: (items) =>
                                setState(() => _checklist = items),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _footer(pad),
          ],
        ),
      ),
    );
  }

  Widget _ongoingSwitch() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _ongoing = !_ongoing),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: _ongoing ? AppTheme.maroon50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _ongoing ? AppTheme.maroon200 : AppTheme.slate200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.autorenew_rounded,
              size: 20,
              color: _ongoing ? AppTheme.maroon : AppTheme.slate400,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ongoing duty',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate900,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'No due date. The student logs it on days they clock in.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AppTheme.slate500,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _ongoing,
              activeThumbColor: AppTheme.maroon,
              onChanged: (v) => setState(() => _ongoing = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _templateChip(TaskTemplate t) {
    final selected = _templateId == t.id;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _pickTemplate(t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.maroon50 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.maroon : AppTheme.slate200,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.bookmark_outline,
              size: 15,
              color: selected ? AppTheme.maroon : AppTheme.slate400,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                t.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.maroon : AppTheme.slate600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(double pad) {
    return Container(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.slate100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppTheme.red500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.red500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton(
            onPressed: _saving ? null : _assign,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.maroon,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
              ),
            ),
            child: Text(
              _saving
                  ? 'Saving...'
                  : (_ongoing ? 'Give Ongoing Duty' : 'Assign Task'),
            ),
          ),
        ],
      ),
    );
  }
}
