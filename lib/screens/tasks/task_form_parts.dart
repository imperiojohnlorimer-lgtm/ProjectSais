import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// The look shared by the task forms (Assign Task and the template editor):
/// white outlined fields with a maroon focus ring.
InputDecorationTheme taskInputTheme() {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    labelStyle: const TextStyle(
      color: AppTheme.slate600,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    floatingLabelStyle: const TextStyle(
      color: AppTheme.maroon,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    ),
    hintStyle: const TextStyle(color: AppTheme.slate500, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(AppTheme.slate200),
    enabledBorder: border(AppTheme.slate200),
    focusedBorder: border(AppTheme.maroon, 1.6),
    errorBorder: border(AppTheme.red500),
    focusedErrorBorder: border(AppTheme.red500, 1.6),
  );
}

/// A small grey caps label that opens a group of fields.
class TaskSectionLabel extends StatelessWidget {
  final String text;
  final bool optional;

  const TaskSectionLabel(this.text, {super.key, this.optional = false});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppTheme.slate500,
          letterSpacing: 1.0,
        ),
      ),
      if (optional) ...[
        const SizedBox(width: 6),
        const Text(
          'optional',
          style: TextStyle(fontSize: 10.5, color: AppTheme.slate500),
        ),
      ],
    ],
  );
}

/// The header both task forms open with: a tinted icon, a title and a
/// short line under it, and a close button.
class TaskFormHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  const TaskFormHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.slate100)),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.maroon50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.maroon, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.slate500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: AppTheme.slate500),
        ),
      ],
    ),
  );
}

/// High / Medium / Low as three pills, tinted by urgency.
class PriorityChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const PriorityChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static Color colorOf(String priority) => switch (priority) {
    'High' => AppTheme.red500,
    'Low' => AppTheme.emerald500,
    _ => AppTheme.amber500,
  };

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final p in const ['High', 'Medium', 'Low']) ...[
        Expanded(child: _pill(p)),
        if (p != 'Low') const SizedBox(width: 8),
      ],
    ],
  );

  Widget _pill(String priority) {
    final selected = value == priority;
    final color = colorOf(priority);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(priority),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : AppTheme.slate200,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              priority,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.slate900 : AppTheme.slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A field to type checklist steps into, with the steps added so far shown
/// as removable chips under it.
class ChecklistEditor extends StatefulWidget {
  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  /// How many steps and how long each may be; null for no limit.
  final int? maxItems;
  final int? maxLength;

  const ChecklistEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.maxItems,
    this.maxLength,
  });

  @override
  State<ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends State<ChecklistEditor> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final value = _ctrl.text.trim();
    if (value.isEmpty || _full) return;
    _ctrl.clear();
    widget.onChanged([...widget.items, value]);
  }

  bool get _full =>
      widget.maxItems != null && widget.items.length >= widget.maxItems!;

  @override
  Widget build(BuildContext context) {
    final full = _full;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          enabled: !full,
          maxLength: widget.maxLength,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          decoration: InputDecoration(
            hintText: full ? 'That is the most steps' : 'Add a checklist step',
            counterText: '',
            suffixIcon: IconButton(
              tooltip: 'Add step',
              onPressed: full ? null : _add,
              icon: const Icon(Icons.add_circle_rounded),
              color: AppTheme.maroon,
            ),
          ),
        ),
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                InputChip(
                  label: Text(
                    widget.items[i],
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
                  onDeleted: () => widget.onChanged([
                    for (var j = 0; j < widget.items.length; j++)
                      if (j != i) widget.items[j],
                  ]),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
