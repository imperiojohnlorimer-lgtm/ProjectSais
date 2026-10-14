import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/task_template.dart';
import '../../theme/app_theme.dart';
import 'task_form_parts.dart';

/// Opens the form for a new template under [category], or for [existing].
Future<void> showTaskTemplateDialog(
  BuildContext context, {
  required String category,
  TaskTemplate? existing,
}) {
  final state = context.read<AppState>();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: TaskTemplateDialog(category: category, existing: existing),
    ),
  );
}

/// The Head's form for one ready-made task: what a Supervisor's Assign Task
/// form is filled with when they pick it.
class TaskTemplateDialog extends StatefulWidget {
  final String category;
  final TaskTemplate? existing;

  const TaskTemplateDialog({super.key, required this.category, this.existing});

  @override
  State<TaskTemplateDialog> createState() => _TaskTemplateDialogState();
}

class _TaskTemplateDialogState extends State<TaskTemplateDialog> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late String _priority = widget.existing?.priority ?? 'Medium';
  late List<String> _checklist = [...?widget.existing?.checklist];
  late bool _ongoing = widget.existing?.ongoing ?? false;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final problem = await state.saveTaskTemplate(
      TaskTemplate(
        id:
            widget.existing?.id ??
            'tpl_${DateTime.now().millisecondsSinceEpoch}',
        category: widget.category,
        title: _title.text,
        description: _description.text,
        priority: _priority,
        checklist: _checklist,
        ongoing: _ongoing,
      ),
    );
    if (!mounted) return;
    if (problem == null) {
      navigator.pop();
    } else {
      // Stay open, so nothing typed is lost.
      setState(() {
        _saving = false;
        _error = problem;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              icon: Icons.bookmark_add_rounded,
              title: widget.existing == null ? 'New Template' : 'Edit Template',
              subtitle: 'In ${widget.category}',
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
                        const TaskSectionLabel('TASK'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _title,
                          maxLength: TaskTemplate.maxTitle,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _description,
                          maxLength: TaskTemplate.maxDescription,
                          minLines: 3,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            alignLabelWithHint: true,
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 22),
                        const TaskSectionLabel('PRIORITY'),
                        const SizedBox(height: 10),
                        PriorityChips(
                          value: _priority,
                          onChanged: (p) => setState(() => _priority = p),
                        ),
                        const SizedBox(height: 22),
                        SwitchListTile(
                          value: _ongoing,
                          onChanged: (v) => setState(() => _ongoing = v),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppTheme.maroon,
                          title: const Text(
                            'Ongoing duty',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate900,
                            ),
                          ),
                          subtitle: const Text(
                            'No due date. The student logs it on days they '
                            'clock in.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.slate500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const TaskSectionLabel('CHECKLIST', optional: true),
                        const SizedBox(height: 10),
                        ChecklistEditor(
                          maxItems: TaskTemplate.maxChecklistItems,
                          maxLength: TaskTemplate.maxChecklistItem,
                          items: _checklist,
                          onChanged: (items) =>
                              setState(() => _checklist = items),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(pad, 14, pad, 16),
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.slate600,
                            side: const BorderSide(color: AppTheme.slate200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.maroon,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          child: Text(_saving ? 'Saving...' : 'Save Template'),
                        ),
                      ),
                    ],
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
