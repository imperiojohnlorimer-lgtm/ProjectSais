import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class AcademicYearSettingsScreen extends StatefulWidget {
  const AcademicYearSettingsScreen({super.key});

  @override
  State<AcademicYearSettingsScreen> createState() =>
      _AcademicYearSettingsScreenState();
}

class _AcademicYearSettingsScreenState
    extends State<AcademicYearSettingsScreen> {
  late final TextEditingController _yearController;
  late DateTime _startDate;
  late DateTime _endDate;
  late String _semester;
  late bool _allowApplications;
  late bool _enforceHourCap;
  late bool _autoArchiveLogs;
  late List<_MilestoneDraft> _milestones;
  bool _saving = false;

  /// The year the dates were last set for, so typing only moves them when
  /// the year itself changes — not on every keystroke.
  late String _datedYear;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController();
    _loadSaved(context.read<AppState>());
  }

  /// Fills the form with the settings in effect.
  void _loadSaved(AppState state) {
    _yearController.text = state.academicYear;
    _datedYear = state.academicYear;
    _semester = state.academicSemester;
    _startDate = state.academicYearStart;
    _endDate = state.academicYearEnd;
    _allowApplications = state.allowAcademicApplications;
    _enforceHourCap = state.enforceAssistantHourCap;
    _autoArchiveLogs = state.autoArchiveAttendanceLogs;
    _milestones = state.academicMilestones
        .map(_MilestoneDraft.fromMap)
        .toList();
  }

  @override
  void dispose() {
    _yearController.dispose();
    for (final milestone in _milestones) {
      milestone.dispose();
    }
    super.dispose();
  }

  String _dateLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';

  Future<void> _selectDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  /// The first year of [year] ("2026-2027" -> 2026), or null unless it's
  /// two consecutive years in YYYY-YYYY form.
  static int? _firstYearOf(String year) {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(year.trim());
    if (match == null) return null;
    final first = int.parse(match.group(1)!);
    return int.parse(match.group(2)!) == first + 1 ? first : null;
  }

  /// The year in effect and the one after it — the only years [_save] lets
  /// the settings move to.
  static List<String> _yearChoices(String currentYear) =>
      {currentYear, RehireRecord.shiftAcademicYear(currentYear, 1)}.toList();

  /// The months each term covers — the ones Payroll's pay period, the
  /// evaluation form's "Period Covered" and rehire contracts use.
  String _termMonths() {
    final firstYear = _firstYearOf(_yearController.text);
    String year(int offset) =>
        firstYear == null ? '' : ' ${firstYear + offset}';
    return '1st Semester: Aug – Dec${year(0)} · '
        '2nd Semester: Jan – May${year(1)} · '
        'Summer: Jun – Jul${year(1)}';
  }

  void _selectYear(String year) {
    setState(() {
      _yearController.text = year;
      _applyYearDates(year);
    });
  }

  /// Points the dates at [year] when it differs from the year they were set
  /// for: the saved dates for the year in effect, otherwise Aug 1 – Jul 31.
  /// Typed years go through here too, so a new year never keeps the
  /// previous year's dates.
  void _applyYearDates(String year) {
    if (year == _datedYear) return;
    final state = context.read<AppState>();
    if (year == state.academicYear) {
      _startDate = state.academicYearStart;
      _endDate = state.academicYearEnd;
    } else {
      final firstYear = _firstYearOf(year);
      if (firstYear == null) return;
      _startDate = DateTime(firstYear, 8, 1);
      _endDate = DateTime(firstYear + 1, 7, 31);
    }
    _datedYear = year;
  }

  Future<void> _save() async {
    final year = _yearController.text.trim();
    final firstYear = _firstYearOf(year);
    if (firstYear == null) {
      _showMessage(
        'Enter the academic year as two consecutive years, e.g. 2026-2027.',
        true,
      );
      return;
    }
    if (!_endDate.isAfter(_startDate)) {
      _showMessage('The end date must be after the start date.', true);
      return;
    }
    // The end date decides when the year is archived, so it has to belong
    // to the year being saved.
    if (_startDate.year != firstYear || _endDate.year != firstYear + 1) {
      _showMessage(
        'AY $year must start in $firstYear and end in ${firstYear + 1}.',
        true,
      );
      return;
    }

    final state = context.read<AppState>();
    final yearChanged = year != state.academicYear;
    // Leaving a year archives it, and an archived year is never archived
    // again — so going back would strand the rest of its records. A
    // mistaken move is taken back with "Undo change" instead.
    if (yearChanged) {
      final currentFirstYear = _firstYearOf(state.academicYear);
      if (currentFirstYear != null && firstYear < currentFirstYear) {
        _showMessage(
          'AY $year is before the current AY ${state.academicYear}. The '
          'academic year can only move forward'
          '${state.canUndoTermChange ? ' — use Undo change to go back.' : '.'}',
          true,
        );
        return;
      }
      if (state.academicYearArchives.any(
        (archive) => archive['academicYear']?.toString() == year,
      )) {
        _showMessage('AY $year has already been archived.', true);
        return;
      }
    }

    // Moving to a new academic year archives the old one, and a new term
    // is what puts pending rehire decisions into effect — neither is
    // something to do by accident.
    final semesterChanged = _semester != state.academicSemester;

    // A new year's timeline doesn't carry the old year's dates over.
    DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);
    final milestones = yearChanged
        ? _milestones
              .where(
                (milestone) =>
                    !day(milestone.date).isBefore(day(_startDate)) &&
                    !day(milestone.date).isAfter(day(_endDate)),
              )
              .toList()
        : _milestones;
    final dropped = _milestones.length - milestones.length;

    if (yearChanged || semesterChanged) {
      final undoHours = AppState.termChangeUndoWindow.inHours;
      final droppedNote = dropped == 0
          ? ''
          : ' $dropped milestone${dropped == 1 ? '' : 's'} dated outside '
                'AY $year will be removed.';
      final confirmed = await showConfirmDialog(
        context,
        title: yearChanged
            ? 'Start academic year $year?'
            : 'Switch to $_semester?',
        message: yearChanged
            ? 'Everyone will be moved to AY $year, $_semester. After '
                  '$undoHours hours, AY ${state.academicYear}\'s records '
                  'will be archived and rehire decisions for the new term '
                  'will take effect. Until then you can undo this here.'
                  '$droppedNote'
            : 'Everyone will see $_semester, AY $year as the current term. '
                  'Rehire decisions made for it will take effect after '
                  '$undoHours hours; until then you can undo this here.',
        confirmLabel: yearChanged ? 'Start new year' : 'Switch term',
        confirmColor: AppTheme.maroon,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await context.read<AppState>().updateAcademicYearSettings(
        year: year,
        semester: _semester,
        startDate: _startDate,
        endDate: _endDate,
        allowApplications: _allowApplications,
        enforceHourCap: _enforceHourCap,
        autoArchiveLogs: _autoArchiveLogs,
        milestones: milestones.map((milestone) => milestone.toMap()).toList(),
      );
      if (mounted) setState(() => _milestones = milestones);
      if (mounted) _showMessage('Academic year settings saved.');
    } catch (error) {
      if (mounted) _showMessage('Could not save settings: $error', true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _undoTermChange() async {
    final state = context.read<AppState>();
    final previous = state.previousTermLabel;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Go back to $previous?',
      message:
          'Everyone will be moved back to $previous, and anything made '
          'since the change will be moved back to it too. Your other '
          'settings stay as they are.',
      confirmLabel: 'Undo change',
      confirmColor: AppTheme.maroon,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await state.undoTermChange();
      if (!mounted) return;
      setState(() => _loadSaved(state));
      _showMessage('Moved back to $previous.');
    } catch (error) {
      if (mounted) _showMessage('Could not undo the change: $error', true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String text, [bool error = false]) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? AppTheme.red500 : AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mobile = MediaQuery.of(context).size.width < 760;
    final assigned = state.offices
        .expand((office) => office.assistantIds)
        .toSet()
        .length;
    final content = <Widget>[
      _header(),
      if (state.canUndoTermChange) ...[
        const SizedBox(height: 16),
        _undoNotice(state),
      ],
      const SizedBox(height: 22),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summary(
            Icons.school_outlined,
            'ACADEMIC CYCLE',
            _semester,
            'AY ${_yearController.text}',
            AppTheme.maroon50,
            AppTheme.maroon,
          ),
          _summary(
            Icons.date_range_outlined,
            'COVERAGE DURATION',
            '${_endDate.difference(_startDate).inDays + 1} Days',
            '${_dateLabel(_startDate)} - ${_dateLabel(_endDate)}',
            AppTheme.blue50,
            AppTheme.blue500,
          ),
          _summary(
            Icons.people_outline,
            'ACTIVE SCOPE',
            '$assigned Assigned SAs',
            'Across ${state.offices.length} registered offices',
            AppTheme.emerald50,
            AppTheme.emerald500,
          ),
        ],
      ),
      const SizedBox(height: 22),
    ];
    content.add(
      mobile
          ? Column(
              children: [
                _settingsPanel(mobile, state),
                const SizedBox(height: 16),
                _sidePanel(),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _settingsPanel(mobile, state)),
                const SizedBox(width: 18),
                Expanded(child: _sidePanel()),
              ],
            ),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 28, 24, mobile ? 16 : 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      ),
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 4,
        height: 54,
        decoration: BoxDecoration(
          color: AppTheme.maroon,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Academic Year Settings',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
                _badge(),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Configure system-wide academic boundaries, term milestones, and student assistant session schedules.',
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _undoNotice(AppState state) {
    final deadline = state.termChangeUndoDeadline!;
    final hour = deadline.hour % 12 == 0 ? 12 : deadline.hour % 12;
    final minute = deadline.minute.toString().padLeft(2, '0');
    final period = deadline.hour < 12 ? 'AM' : 'PM';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.amber50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.amber500.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 20, color: AppTheme.amber500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Changed from ${state.previousTermLabel} by mistake? You can '
              'undo it until ${_dateLabel(deadline)}, $hour:$minute $period.',
              style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _saving ? null : _undoTermChange,
            icon: const Icon(Icons.undo, size: 17),
            label: const Text('Undo change'),
          ),
        ],
      ),
    );
  }

  Widget _badge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.emerald50,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 7, color: AppTheme.emerald500),
        SizedBox(width: 5),
        Text(
          'Active Term',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFF047857),
          ),
        ),
      ],
    ),
  );
  Widget _summary(
    IconData icon,
    String label,
    String title,
    String detail,
    Color tint,
    Color color,
  ) => SizedBox(
    width: 250,
    child: _panel(
      Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppTheme.slate400,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _settingsPanel(bool mobile, AppState state) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          Icons.tune,
          'Current Academic Period',
          'This period is shared across dashboards, student allocation modules, and reporting exports.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 6,
          children: _yearChoices(state.academicYear)
              .map(
                (year) => ChoiceChip(
                  label: Text(year),
                  selected: _yearController.text == year,
                  onSelected: (_) => _selectYear(year),
                  selectedColor: AppTheme.maroon,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: _yearController.text == year
                        ? Colors.white
                        : AppTheme.slate600,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _yearController,
          onChanged: (value) => setState(() => _applyYearDates(value.trim())),
          decoration: const InputDecoration(
            labelText: 'Academic Year',
            hintText: 'e.g. 2026-2027',
            prefixIcon: Icon(Icons.calendar_today_outlined),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue:
              ['1st Semester', '2nd Semester', 'Summer'].contains(_semester)
              ? _semester
              : '1st Semester',
          decoration: InputDecoration(
            labelText: 'Semester / Academic Term',
            prefixIcon: const Icon(Icons.school_outlined),
            helperText: _termMonths(),
            helperMaxLines: 3,
          ),
          items: const ['1st Semester', '2nd Semester', 'Summer']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) => setState(() => _semester = value ?? _semester),
        ),
        const SizedBox(height: 14),
        mobile
            ? Column(
                children: [
                  _dateButton('Start Date', _startDate, true),
                  const SizedBox(height: 12),
                  _dateButton('End Date', _endDate, false),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _dateButton('Start Date', _startDate, true)),
                  const SizedBox(width: 12),
                  Expanded(child: _dateButton('End Date', _endDate, false)),
                ],
              ),
        const Divider(height: 30),
        const Text(
          'PERIOD GUARDRAILS & ENFORCEMENT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: AppTheme.slate500,
          ),
        ),
        _policy(
          'Open Applications',
          'Permit students to apply for offices in this AY',
          _allowApplications,
          (v) => setState(() => _allowApplications = v),
        ),
        _policy(
          'Weekly Hours Cap',
          'Enforce maximum 20-hour weekly assistant threshold',
          _enforceHourCap,
          (v) => setState(() => _enforceHourCap = v),
        ),
        _policy(
          'Auto-archive Logs',
          'Archive attendance logs after the active period ends',
          _autoArchiveLogs,
          (v) => setState(() => _autoArchiveLogs = v),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt, size: 17),
              label: const Text('Reset'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 17),
              label: Text(_saving ? 'Updating...' : 'Save Settings'),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _sidePanel() => Column(
    children: [
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(
              Icons.event_note_outlined,
              'AY Key Milestones',
              'Your active term timeline',
            ),
            const SizedBox(height: 16),
            ..._firebaseMilestones(),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _archiveHistory(),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.maroon50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'Synchronized Academic Context\nChanging this period refreshes office hour calculations, assignment rosters, and reporting filters throughout the system.',
          style: TextStyle(fontSize: 11, height: 1.4, color: AppTheme.slate600),
        ),
      ),
    ],
  );

  Widget _archiveHistory() {
    final archives = context.watch<AppState>().academicYearArchives;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            Icons.archive_outlined,
            'Archived Academic Years',
            'Previous periods stored in Firebase',
          ),
          const SizedBox(height: 10),
          if (archives.isEmpty)
            const Text(
              'No archived academic years yet.',
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            )
          else
            ...archives.map(
              (archive) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(
                  Icons.history,
                  size: 18,
                  color: AppTheme.slate500,
                ),
                title: Text(
                  archive['academicYear']?.toString() ?? 'Unknown year',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  archive['semester']?.toString() ?? 'Archived period',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _firebaseMilestones() {
    if (_milestones.isEmpty) {
      return [
        Row(
          children: [
            const Expanded(
              child: Text(
                'No milestones added yet.',
                style: TextStyle(fontSize: 12, color: AppTheme.slate500),
              ),
            ),
            _addMilestoneButton(),
          ],
        ),
      ];
    }
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [_addMilestoneButton()],
      ),
      ..._milestones.asMap().entries.map(
        (entry) => _milestone(entry.key, entry.value),
      ),
    ];
  }

  Widget _addMilestoneButton() => OutlinedButton.icon(
    onPressed: _openMilestoneEditor,
    icon: const Icon(Icons.add, size: 16),
    label: const Text('Add milestone'),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Future<void> _openMilestoneEditor([int? index]) async {
    final existing = index == null ? null : _milestones[index];
    final titleController = TextEditingController(text: existing?.title ?? '');
    DateTime selectedDate = existing?.date ?? _startDate;
    final result = await showDialog<_MilestoneDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Add milestone' : 'Edit milestone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Milestone title',
                  hintText: 'e.g. Application deadline',
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Date'),
                subtitle: Text(_dateLabel(selectedDate)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialogContext,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) setDialogState(() => selectedDate = date);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.pop(
                    dialogContext,
                    _MilestoneDraft(title: title, date: selectedDate),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _milestones.add(result);
      } else {
        _milestones[index] = result;
      }
    });
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.slate200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
  Widget _heading(IconData icon, String title, String subtitle) => Row(
    children: [
      Icon(icon, color: AppTheme.maroon, size: 20),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _dateButton(String label, DateTime date, bool start) => InkWell(
    onTap: () => _selectDate(start),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.event_outlined),
      ),
      child: Text(_dateLabel(date)),
    ),
  );
  Widget _policy(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(
      title,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
    value: value,
    activeThumbColor: AppTheme.maroon,
    onChanged: onChanged,
  );
  Widget _milestone(int index, _MilestoneDraft milestone) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      radius: 13,
      backgroundColor: AppTheme.maroon50,
      child: Text(
        '${index + 1}',
        style: const TextStyle(
          fontSize: 10,
          color: AppTheme.maroon,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    title: Text(
      milestone.title,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      _dateLabel(milestone.date),
      style: const TextStyle(fontSize: 11),
    ),
    trailing: PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      onSelected: (action) {
        if (action == 'edit') _openMilestoneEditor(index);
        if (action == 'delete') setState(() => _milestones.removeAt(index));
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    ),
  );
  Future<void> _reset() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Discard changes?',
      message:
          'Any changes you haven\'t saved will be lost and the form will go '
          'back to the current settings.',
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;
    setState(() => _loadSaved(context.read<AppState>()));
  }
}

class _MilestoneDraft {
  _MilestoneDraft({required this.title, required this.date});

  factory _MilestoneDraft.fromMap(Map<String, dynamic> map) => _MilestoneDraft(
    title: map['title']?.toString() ?? '',
    date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
  );

  final String title;
  final DateTime date;

  Map<String, dynamic> toMap() => {
    'title': title,
    'date': date.toIso8601String(),
  };

  void dispose() {}
}
