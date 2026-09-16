import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class OfficesScreen extends StatefulWidget {
  const OfficesScreen({super.key});

  @override
  State<OfficesScreen> createState() => _OfficesScreenState();
}

class _OfficesScreenState extends State<OfficesScreen> {
  String _officeSearch = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final acceptedAssistants = state.users
        .where(
          (user) =>
              user.role == 'Student Assistant' && user.status != 'Archived',
        )
        .toList();
    final offices = state.offices.where((office) {
      final query = _officeSearch.trim().toLowerCase();
      return query.isEmpty ||
          office.name.toLowerCase().contains(query) ||
          office.code.toLowerCase().contains(query);
    }).toList();
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 4,
                      height: 48,
                      decoration: const BoxDecoration(color: AppTheme.maroon),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offices',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Manage offices, supervisors, and student assistants',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                SizedBox(
                  width: 174,
                  height: 34,
                  child: TextField(
                    onChanged: (value) => setState(() => _officeSearch = value),
                    decoration: InputDecoration(
                      hintText: 'Filter offices...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 17),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (!isMobile)
                ElevatedButton.icon(
                  onPressed: () => _showOfficeDialog(context),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Add Office'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.maroon,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (isMobile) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => _showOfficeDialog(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Office'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.maroon,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => setState(() => _officeSearch = value),
                  decoration: const InputDecoration(
                    hintText: 'Filter offices...',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Expanded(
          child: offices.isEmpty
              ? const Center(
                  child: Text(
                    'No offices yet',
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
                  itemCount: offices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _OfficeCard(
                    office: offices[index],
                    acceptedAssistants: acceptedAssistants,
                  ),
                ),
        ),
      ],
    );
  }

  static Future<void> _showOfficeDialog(
    BuildContext context, {
    Office? office,
  }) async {
    final state = context.read<AppState>();
    final nameController = TextEditingController(text: office?.name ?? '');
    final codeController = TextEditingController(text: office?.code ?? '');
    final capacityController = TextEditingController(
      text: office != null && office.capacity > 0
          ? office.capacity.toString()
          : '',
    );
    final supervisors = state.users
        .where(
          (user) =>
              user.role.trim().toLowerCase() == 'supervisor' &&
              user.status.trim().toLowerCase() != 'archived',
        )
        .toList();
    var headIds = [...(office?.headIds ?? const <String>[])];
    var requiredSkills = [...(office?.requiredSkills ?? const <String>[])];
    var isActive = office?.isActive ?? true;
    final availableSkills = [...state.skills]..sort();

    final saved = await showDialog<bool>(
      context: context,
      barrierColor: AppTheme.slate900.withValues(alpha: 0.45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Widget emptyHint(String text) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: AppTheme.amber50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.amber500.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTheme.amber500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.amber500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );

          Widget pickerChip({
            required String label,
            required bool selected,
            required VoidCallback onTap,
            IconData icon = Icons.person_outline_rounded,
          }) {
            return InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.maroon : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppTheme.maroon : AppTheme.slate200,
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppTheme.maroon.withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? Icons.check_circle_rounded : icon,
                      size: 15,
                      color: selected ? Colors.white : AppTheme.slate400,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppTheme.slate700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 22, 20, 22),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.maroon, AppTheme.maroonDark],
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              office == null
                                  ? Icons.add_business_rounded
                                  : Icons.edit_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  office == null ? 'Add Office' : 'Edit Office',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  office == null
                                      ? 'Create a new office and assign its staff'
                                      : 'Update office details and staffing',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(dialogContext, false),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
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
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Office name *',
                                      prefixIcon: Icon(
                                        Icons.business_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: codeController,
                                    decoration: const InputDecoration(
                                      labelText: 'Office code *',
                                      prefixIcon: Icon(Icons.tag_outlined),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: capacityController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Assistant capacity (optional)',
                                hintText: 'Leave empty for no limit',
                                prefixIcon: Icon(Icons.groups_outlined),
                              ),
                            ),
                            const SizedBox(height: 20),

                            Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 2,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                initiallyExpanded: false,
                                backgroundColor: AppTheme.slate50,
                                collapsedBackgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: AppTheme.slate200,
                                  ),
                                ),
                                collapsedShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: AppTheme.slate200,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.maroon50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.supervisor_account_outlined,
                                        size: 15,
                                        color: AppTheme.maroon,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Office heads (Supervisors)',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.slate700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    if (headIds.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.maroon50,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${headIds.length}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.maroon,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  supervisors.isEmpty
                                      ? 'No active supervisors available.'
                                      : '${headIds.length} selected',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.slate400,
                                  ),
                                ),
                                children: [
                                  if (supervisors.isEmpty)
                                    emptyHint('No active supervisors available.')
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: supervisors.map((user) {
                                        final selected = headIds.contains(
                                          user.id,
                                        );
                                        return pickerChip(
                                          label: user.name,
                                          selected: selected,
                                          icon: Icons
                                              .supervisor_account_outlined,
                                          onTap: () async {
                                            final checked = !selected;
                                            final confirmed =
                                                await showConfirmDialog(
                                                  context,
                                                  title: checked
                                                      ? 'Assign Office Supervisor'
                                                      : 'Remove Office Supervisor',
                                                  message: checked
                                                      ? 'Assign ${user.name} as a supervisor for this office?'
                                                      : 'Remove ${user.name} as a supervisor for this office?',
                                                  confirmLabel: checked
                                                      ? 'Assign'
                                                      : 'Remove',
                                                  confirmColor: checked
                                                      ? AppTheme.maroon
                                                      : AppTheme.red500,
                                                );
                                            if (!confirmed ||
                                                !context.mounted) {
                                              return;
                                            }
                                            setState(() {
                                              if (checked) {
                                                if (!headIds.contains(
                                                  user.id,
                                                )) {
                                                  headIds.add(user.id);
                                                }
                                              } else {
                                                headIds.remove(user.id);
                                              }
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 2,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                initiallyExpanded: false,
                                backgroundColor: AppTheme.slate50,
                                collapsedBackgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: AppTheme.slate200,
                                  ),
                                ),
                                collapsedShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: AppTheme.slate200,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.maroon50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.star_outline_rounded,
                                        size: 15,
                                        color: AppTheme.maroon,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Required skills',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.slate700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    if (requiredSkills.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.maroon50,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${requiredSkills.length}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.maroon,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  availableSkills.isEmpty
                                      ? 'No skills defined yet. Add some in the Skills page.'
                                      : '${requiredSkills.length} selected',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.slate400,
                                  ),
                                ),
                                children: [
                                  if (availableSkills.isEmpty)
                                    emptyHint(
                                      'No skills defined yet. Add some in the Skills page.',
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: availableSkills.map((skill) {
                                        final selected = requiredSkills
                                            .contains(skill);
                                        return pickerChip(
                                          label: skill,
                                          selected: selected,
                                          icon: Icons.star_outline_rounded,
                                          onTap: () {
                                            setState(() {
                                              if (selected) {
                                                requiredSkills.remove(skill);
                                              } else {
                                                requiredSkills.add(skill);
                                              }
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),

                            if (office != null) ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppTheme.emerald50
                                      : AppTheme.red50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isActive
                                        ? AppTheme.emerald500.withValues(
                                            alpha: 0.3,
                                          )
                                        : AppTheme.red500.withValues(
                                            alpha: 0.3,
                                          ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.pause_circle_outline_rounded,
                                      size: 18,
                                      color: isActive
                                          ? AppTheme.emerald500
                                          : AppTheme.red500,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isActive
                                                ? 'Active office'
                                                : 'Inactive office',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: isActive
                                                  ? AppTheme.emerald500
                                                  : AppTheme.red500,
                                            ),
                                          ),
                                          Text(
                                            isActive
                                                ? 'Visible and available for assignments'
                                                : 'Hidden from staffing workflows',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.slate500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: isActive,
                                      activeThumbColor: AppTheme.emerald500,
                                      onChanged: (value) async {
                                        final confirmed =
                                            await showConfirmDialog(
                                              context,
                                              title: value
                                                  ? 'Activate Office'
                                                  : 'Deactivate Office',
                                              message: value
                                                  ? 'Activate ${office.name}?'
                                                  : 'Deactivate ${office.name}? Assigned users will lose access to this office.',
                                              confirmLabel: value
                                                  ? 'Activate'
                                                  : 'Deactivate',
                                              confirmColor: value
                                                  ? AppTheme.emerald500
                                                  : AppTheme.red500,
                                            );
                                        if (confirmed && context.mounted) {
                                          setState(() => isActive = value);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                    // Footer actions
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppTheme.slate100, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.slate600,
                                side: const BorderSide(
                                  color: AppTheme.slate200,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final name = nameController.text.trim();
                                final code = codeController.text.trim();
                                final capacity =
                                    int.tryParse(
                                      capacityController.text.trim(),
                                    ) ??
                                    0;
                                if (name.isEmpty || code.isEmpty) return;
                                final confirmed = await showConfirmDialog(
                                  dialogContext,
                                  title: office == null
                                      ? 'Create Office'
                                      : 'Save Office Changes',
                                  message: office == null
                                      ? 'Create office "$name"?'
                                      : 'Save changes to ${office.name}?',
                                  confirmLabel: office == null
                                      ? 'Create'
                                      : 'Save',
                                );
                                if (!confirmed || !dialogContext.mounted) {
                                  return;
                                }
                                final heads = supervisors
                                    .where((user) => headIds.contains(user.id))
                                    .toList();
                                final savedOffice = Office(
                                  id:
                                      office?.id ??
                                      'office_${DateTime.now().millisecondsSinceEpoch}',
                                  name: name,
                                  code: code,
                                  headIds: heads
                                      .map((head) => head.id)
                                      .toList(),
                                  headNames: heads
                                      .map((head) => head.name)
                                      .toList(),
                                  assistantIds:
                                      office?.assistantIds ?? const [],
                                  assistantNames:
                                      office?.assistantNames ?? const [],
                                  capacity: capacity,
                                  isActive: isActive,
                                  requiredSkills: requiredSkills,
                                );
                                await state.saveOffice(savedOffice);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext, true);
                                }
                              },
                              icon: Icon(
                                office == null
                                    ? Icons.add_rounded
                                    : Icons.check_rounded,
                                size: 18,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.maroon,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                              ),
                              label: Text(
                                office == null ? 'Add Office' : 'Save Changes',
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
          );
        },
      ),
    );
    nameController.dispose();
    codeController.dispose();
    capacityController.dispose();
    if (saved == true && context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Office saved.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
  }
}

class _OfficeCard extends StatefulWidget {
  final Office office;
  final List<User> acceptedAssistants;
  const _OfficeCard({required this.office, required this.acceptedAssistants});

  @override
  State<_OfficeCard> createState() => _OfficeCardState();
}

class _OfficeCardState extends State<_OfficeCard> {
  String _search = '';
  String _departmentFilter = 'All departments';
  String _skillFilter = 'All skills';
  String _assignmentFilter = 'All assistants';
  bool _groupByDepartment = true;

  Office get office => widget.office;
  List<User> get acceptedAssistants => widget.acceptedAssistants;

  /// True when [user] is already assigned to a *different* office, meaning
  /// they must be removed there first before they can be assigned here.
  bool _isLockedElsewhere(AppState state, User user) {
    if (office.assistantIds.contains(user.id)) return false;
    return state.offices.any(
      (item) => item.id != office.id && item.assistantIds.contains(user.id),
    );
  }

  Widget _matchBadge(double? score) {
    if (score == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.slate100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Not yet assessed',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate500,
          ),
        ),
      );
    }
    late final Color color;
    late final String label;
    if (score >= 80) {
      color = AppTheme.emerald500;
      label = 'Strong match';
    } else if (score >= 60) {
      color = AppTheme.maroon;
      label = 'Good match';
    } else if (score >= 40) {
      color = AppTheme.amber500;
      label = 'Fair match';
    } else {
      color = AppTheme.red500;
      label = 'Low match';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '$label • ${score.round()}%',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _capacitySummary(BuildContext context) {
    final remaining = office.capacity - office.assistantIds.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${office.assistantIds.length} / ${office.capacity} Assigned',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.maroon,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining > 0
                      ? '$remaining slots remaining'
                      : 'At maximum capacity',
                  style: const TextStyle(fontSize: 9, color: AppTheme.slate400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: (office.assistantIds.length / office.capacity).clamp(
                  0.0,
                  1.0,
                ),
                backgroundColor: AppTheme.slate200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  office.assistantIds.length >= office.capacity
                      ? AppTheme.red500
                      : AppTheme.emerald500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staffingIcon() => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: AppTheme.maroon50,
      borderRadius: BorderRadius.circular(9),
    ),
    child: const Icon(
      Icons.people_alt_outlined,
      size: 17,
      color: AppTheme.maroon,
    ),
  );

  Widget _staffingTitle() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Manage Office Staffing & Assistant Roster',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppTheme.slate900,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        'Select student assistants to assign or reallocate to ${office.name}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final normalizedSearch = _search.trim().toLowerCase();
    final allSkills = {
      ...state.skills,
      ...acceptedAssistants.expand(state.skillsForUser),
    }.toList()..sort();
    final visibleAssistants = acceptedAssistants.where((user) {
      final department = user.department?.trim().isNotEmpty == true
          ? user.department!.trim()
          : 'No department';
      final assigned = state.offices.any(
        (item) => item.assistantIds.contains(user.id),
      );
      final userSkills = state.skillsForUser(user);
      return (normalizedSearch.isEmpty ||
              user.name.toLowerCase().contains(normalizedSearch) ||
              user.id.toLowerCase().contains(normalizedSearch) ||
              user.email.toLowerCase().contains(normalizedSearch) ||
              userSkills.any(
                (skill) => skill.toLowerCase().contains(normalizedSearch),
              )) &&
          (_departmentFilter == 'All departments' ||
              department == _departmentFilter) &&
          (_skillFilter == 'All skills' ||
              userSkills.any(
                (skill) =>
                    skill.trim().toLowerCase() == _skillFilter.toLowerCase(),
              )) &&
          (_assignmentFilter == 'All assistants' ||
              (_assignmentFilter == 'Assigned here' &&
                  office.assistantIds.contains(user.id)) ||
              (_assignmentFilter == 'Available' && !assigned) ||
              (_assignmentFilter == 'Other offices' &&
                  assigned &&
                  !office.assistantIds.contains(user.id)));
    }).toList();
    // Best assessment/skill match for this office comes first.
    final sortedVisibleAssistants = state.sortByOfficeMatch(
      visibleAssistants,
      office,
    );
    final assistantsByDepartment = <String, List<User>>{};
    for (final assistant in sortedVisibleAssistants) {
      final department = assistant.department?.trim().isNotEmpty == true
          ? assistant.department!.trim()
          : 'No department';
      (assistantsByDepartment[department] ??= []).add(assistant);
    }
    final departments = assistantsByDepartment.keys.toList()..sort();
    final allDepartments =
        acceptedAssistants
            .map(
              (user) => user.department?.trim().isNotEmpty == true
                  ? user.department!.trim()
                  : 'No department',
            )
            .toSet()
            .toList()
          ..sort();
    final assignedHereCount = office.assistantIds.length;
    final availableCount = acceptedAssistants
        .where(
          (user) =>
              !state.offices.any((item) => item.assistantIds.contains(user.id)),
        )
        .length;
    final otherOfficeCount =
        acceptedAssistants.length - assignedHereCount - availableCount;
    final hasFilters =
        _search.isNotEmpty ||
        _departmentFilter != 'All departments' ||
        _skillFilter != 'All skills' ||
        _assignmentFilter != 'All assistants';
    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 20,
        18,
        isMobile ? 12 : 20,
        20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.maroon.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!isMobile)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.maroon50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.business_rounded, color: AppTheme.maroon),
            ),
          if (!isMobile) const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        office.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        office.code,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate400,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isMobile)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () =>
                              _OfficesScreenState._showOfficeDialog(
                                context,
                                office: office,
                              ),
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppTheme.slate500,
                          ),
                          tooltip: 'Edit office',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => _delete(context),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.red500,
                          ),
                          tooltip: 'Delete office',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 5),
                Text(
                  office.headNames.isEmpty
                      ? 'No office heads assigned'
                      : isMobile
                      ? office.headNames.join(', ')
                      : 'Heads: ${office.headNames.join(', ')}',
                  maxLines: isMobile ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  office.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: office.isActive
                        ? AppTheme.emerald500
                        : AppTheme.slate400,
                  ),
                ),
                const SizedBox(height: 5),
                if (!isMobile)
                  Text(
                    office.capacity > 0
                        ? 'Capacity: ${office.assistantIds.length}/${office.capacity}'
                        : 'Capacity: No limit',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (office.requiredSkills.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: office.requiredSkills
                        .map(
                          (skill) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.maroon50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              skill,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.maroon,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 10),
                ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  childrenPadding: EdgeInsets.zero,
                  backgroundColor: AppTheme.slate50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.slate200),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.slate200),
                  ),
                  title: Row(
                    children: [
                      const Icon(
                        Icons.people_alt_outlined,
                        size: 17,
                        color: AppTheme.slate500,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Manage assistants',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.emerald50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.emerald500.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '${office.assistantIds.length} assigned',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.emerald500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: isMobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _staffingIcon(),
                                    const SizedBox(width: 10),
                                    Expanded(child: _staffingTitle()),
                                  ],
                                ),
                                if (office.capacity > 0) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: _capacitySummary(context),
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Row(
                              children: [
                                _staffingIcon(),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: isMobile
                                      ? const Text(
                                          'Assistant roster',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.slate900,
                                          ),
                                        )
                                      : _staffingTitle(),
                                ),
                                if (office.capacity > 0 && !isMobile)
                                  _capacitySummary(context),
                              ],
                            ),
                    ),
                    const Divider(height: 1, color: AppTheme.slate200),
                    SizedBox(
                      width: double.infinity,
                      child: InputDecorator(
                        decoration: isMobile
                            ? const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              )
                            : InputDecoration(
                                prefixIcon: const Icon(
                                  Icons.people_alt_outlined,
                                  size: 18,
                                ),
                                helperText: acceptedAssistants.isEmpty
                                    ? 'No active student assistants available'
                                    : '${acceptedAssistants.length} available • Select one or more',
                                helperStyle: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.slate400,
                                ),
                                contentPadding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  12,
                                ),
                                filled: true,
                                fillColor: AppTheme.slate50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppTheme.slate200,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppTheme.slate200,
                                  ),
                                ),
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isMobile)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    decoration: const InputDecoration(
                                      hintText: 'Search assistants',
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        size: 17,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                    ),
                                    onChanged: (value) =>
                                        setState(() => _search = value),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    initialValue: _skillFilter,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Skill',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                    ),
                                    items: ['All skills', ...allSkills]
                                        .map(
                                          (value) => DropdownMenuItem(
                                            value: value,
                                            child: Text(
                                              value,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) => setState(
                                      () =>
                                          _skillFilter = value ?? 'All skills',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    initialValue: _departmentFilter,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Department',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                    ),
                                    items:
                                        ['All departments', ...allDepartments]
                                            .map(
                                              (value) => DropdownMenuItem(
                                                value: value,
                                                child: Text(
                                                  value,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (value) => setState(
                                      () => _departmentFilter =
                                          value ?? 'All departments',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    initialValue: _assignmentFilter,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Status',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                    ),
                                    items:
                                        const [
                                              'All assistants',
                                              'Assigned here',
                                              'Available',
                                              'Other offices',
                                            ]
                                            .map(
                                              (value) => DropdownMenuItem(
                                                value: value,
                                                child: Text(value),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (value) => setState(
                                      () => _assignmentFilter =
                                          value ?? 'All assistants',
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      decoration: const InputDecoration(
                                        hintText: 'Search assistants',
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          size: 17,
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 9,
                                        ),
                                      ),
                                      onChanged: (value) =>
                                          setState(() => _search = value),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _departmentFilter,
                                      decoration: const InputDecoration(
                                        labelText: 'Department',
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 9,
                                        ),
                                      ),
                                      items:
                                          ['All departments', ...allDepartments]
                                              .map(
                                                (value) => DropdownMenuItem(
                                                  value: value,
                                                  child: Text(
                                                    value,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (value) => setState(
                                        () => _departmentFilter =
                                            value ?? 'All departments',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _skillFilter,
                                      decoration: const InputDecoration(
                                        labelText: 'Skill',
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 9,
                                        ),
                                      ),
                                      items: ['All skills', ...allSkills]
                                          .map(
                                            (value) => DropdownMenuItem(
                                              value: value,
                                              child: Text(
                                                value,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) => setState(
                                        () => _skillFilter =
                                            value ?? 'All skills',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _assignmentFilter,
                                      decoration: const InputDecoration(
                                        labelText: 'Status',
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 9,
                                        ),
                                      ),
                                      items:
                                          const [
                                                'All assistants',
                                                'Assigned here',
                                                'Available',
                                                'Other offices',
                                              ]
                                              .map(
                                                (value) => DropdownMenuItem(
                                                  value: value,
                                                  child: Text(value),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (value) => setState(
                                        () => _assignmentFilter =
                                            value ?? 'All assistants',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _filterChip(
                                  'All Assistants',
                                  acceptedAssistants.length,
                                  _assignmentFilter == 'All assistants',
                                  () => setState(
                                    () => _assignmentFilter = 'All assistants',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _filterChip(
                                  'Assigned Here',
                                  assignedHereCount,
                                  _assignmentFilter == 'Assigned here',
                                  () => setState(
                                    () => _assignmentFilter = 'Assigned here',
                                  ),
                                  color: AppTheme.emerald500,
                                ),
                                const SizedBox(width: 6),
                                _filterChip(
                                  'Available',
                                  availableCount,
                                  _assignmentFilter == 'Available',
                                  () => setState(
                                    () => _assignmentFilter = 'Available',
                                  ),
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 6),
                                _filterChip(
                                  'Other Offices',
                                  otherOfficeCount,
                                  _assignmentFilter == 'Other offices',
                                  () => setState(
                                    () => _assignmentFilter = 'Other offices',
                                  ),
                                ),
                                if (hasFilters) ...[
                                  const SizedBox(width: 12),
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _search = '';
                                      _departmentFilter = 'All departments';
                                      _skillFilter = 'All skills';
                                      _assignmentFilter = 'All assistants';
                                    }),
                                    icon: const Icon(Icons.close, size: 14),
                                    label: const Text('Clear filters'),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: InkWell(
                                onTap: () => setState(
                                  () =>
                                      _groupByDepartment = !_groupByDepartment,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 126,
                                    minHeight: 38,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: AppTheme.maroon),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.layers_outlined,
                                        size: 15,
                                        color: AppTheme.maroon,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _groupByDepartment
                                            ? 'Grouped'
                                            : 'Flat list',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.maroon,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (visibleAssistants.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: Text(
                                    'No assistants match these filters',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.slate400,
                                    ),
                                  ),
                                ),
                              ),
                            if (office.assistantIds.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '${office.assistantIds.length} assigned to this office',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.emerald500,
                                  ),
                                ),
                              ),
                            if (acceptedAssistants.isEmpty)
                              const Text(
                                'No active student assistants available',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.slate400,
                                ),
                              ),
                            if (_groupByDepartment)
                              ...departments.expand(
                                (department) => [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 2,
                                    ),
                                    child: Text(
                                      department.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.maroon,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  ...assistantsByDepartment[department]!.map((
                                    user,
                                  ) {
                                    final selected = office.assistantIds
                                        .contains(user.id);
                                    final assignedOfficeNames = state.offices
                                        .where(
                                          (item) => item.assistantIds.contains(
                                            user.id,
                                          ),
                                        )
                                        .map((item) => item.name)
                                        .toList();
                                    final matchScore = state
                                        .recommendationScoreForOffice(
                                          user,
                                          office,
                                        );
                                    final locked = _isLockedElsewhere(
                                      state,
                                      user,
                                    );
                                    return CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      value: selected,
                                      title: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              user.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _matchBadge(matchScore),
                                        ],
                                      ),
                                      subtitle: Text(
                                        [
                                          assignedOfficeNames.isEmpty
                                              ? 'Unassigned'
                                              : locked
                                              ? 'Assigned: ${assignedOfficeNames.join(', ')} — remove there first'
                                              : 'Assigned: ${assignedOfficeNames.join(', ')}',
                                          if (state
                                              .skillsForUser(user)
                                              .isNotEmpty)
                                            'Skills: ${state.skillsForUser(user).join(', ')}',
                                        ].join(' • '),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: locked
                                              ? AppTheme.amber500
                                              : AppTheme.slate500,
                                        ),
                                      ),
                                      onChanged: locked
                                          ? null
                                          : (checked) async {
                                              final confirmed =
                                                  await showConfirmDialog(
                                                    context,
                                                    title: checked == true
                                                        ? 'Assign Student Assistant'
                                                        : 'Remove Student Assistant',
                                                    message: checked == true
                                                        ? 'Assign ${user.name} to ${office.name}?'
                                                        : 'Remove ${user.name} from ${office.name}?',
                                                    confirmLabel: checked == true
                                                        ? 'Assign'
                                                        : 'Remove',
                                                    confirmColor: checked == true
                                                        ? AppTheme.maroon
                                                        : AppTheme.red500,
                                                  );
                                              if (!confirmed ||
                                                  !context.mounted)
                                                return;
                                              final ids = [
                                                ...office.assistantIds,
                                              ];
                                              if (checked == true &&
                                                  !ids.contains(user.id))
                                                ids.add(user.id);
                                              if (checked != true)
                                                ids.remove(user.id);
                                              final assistants =
                                                  acceptedAssistants
                                                      .where(
                                                        (item) => ids.contains(
                                                          item.id,
                                                        ),
                                                      )
                                                      .toList();
                                              final assigned = await context
                                                  .read<AppState>()
                                                  .assignStudentAssistantsToOffice(
                                                    office.id,
                                                    assistants,
                                                  );
                                              if (!assigned &&
                                                  context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '${office.name} can have at most ${office.capacity} student assistant${office.capacity == 1 ? '' : 's'}.',
                                                    ),
                                                    backgroundColor:
                                                        AppTheme.red500,
                                                    behavior:
                                                        SnackBarBehavior
                                                            .floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                                                );
                                              }
                                            },
                                    );
                                  }),
                                ],
                              ),
                            if (!_groupByDepartment)
                              ...sortedVisibleAssistants.map((user) {
                                final selected = office.assistantIds.contains(
                                  user.id,
                                );
                                final matchScore = state
                                    .recommendationScoreForOffice(
                                      user,
                                      office,
                                    );
                                final locked = _isLockedElsewhere(
                                  state,
                                  user,
                                );
                                return CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: selected,
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          user.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _matchBadge(matchScore),
                                    ],
                                  ),
                                  subtitle: Text(
                                    state.offices
                                            .where(
                                              (item) => item.assistantIds
                                                  .contains(user.id),
                                            )
                                            .isEmpty
                                        ? 'Available'
                                        : selected
                                        ? 'Assigned to this office'
                                        : 'Assigned to another office — remove there first',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: selected
                                          ? AppTheme.emerald500
                                          : locked
                                          ? AppTheme.amber500
                                          : AppTheme.slate500,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onChanged: locked
                                      ? null
                                      : (checked) => _toggleAssistant(
                                          context,
                                          user,
                                          checked == true,
                                        ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isMobile)
            IconButton(
              onPressed: () => _OfficesScreenState._showOfficeDialog(
                context,
                office: office,
              ),
              icon: const Icon(Icons.edit_outlined, color: AppTheme.slate400),
              tooltip: 'Edit office',
            ),
          if (!isMobile)
            IconButton(
              onPressed: () => _delete(context),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.red500,
              ),
              tooltip: 'Delete office',
            ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    int count,
    bool selected,
    VoidCallback onTap, {
    Color color = AppTheme.maroon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAssistant(
    BuildContext context,
    User user,
    bool checked,
  ) async {
    if (checked && _isLockedElsewhere(context.read<AppState>(), user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${user.name} is already assigned to another office. Remove them there first.',
          ),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: checked ? 'Assign Student Assistant' : 'Remove Student Assistant',
      message: checked
          ? 'Assign ${user.name} to ${office.name}?'
          : 'Remove ${user.name} from ${office.name}?',
      confirmLabel: checked ? 'Assign' : 'Remove',
      confirmColor: checked ? AppTheme.maroon : AppTheme.red500,
    );
    if (!confirmed || !context.mounted) return;
    final ids = [...office.assistantIds];
    if (checked && !ids.contains(user.id)) ids.add(user.id);
    if (!checked) ids.remove(user.id);
    final assistants = acceptedAssistants
        .where((item) => ids.contains(item.id))
        .toList();
    await context.read<AppState>().assignStudentAssistantsToOffice(
      office.id,
      assistants,
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Office',
      message: 'Delete ${office.name}? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: AppTheme.red500,
    );
    if (!confirmed || !context.mounted) return;
    await context.read<AppState>().removeOffice(office.id);
  }
}