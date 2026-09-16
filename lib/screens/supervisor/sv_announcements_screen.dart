import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/announcement_widgets.dart';

class SvAnnouncementsScreen extends StatelessWidget {
  const SvAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mine = state.myAnnouncements;
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: _submitButton(context, state),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _header(),
                    const Spacer(),
                    _submitButton(context, state),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mine.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: AppTheme.slate100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.campaign_outlined,
                              size: 36,
                              color: AppTheme.slate300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No requests submitted yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate400,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Request a student assistant for your office and wait for admin approval.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.slate300,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...mine.map(
                    (a) => AnnouncementCard(
                      announcement: a,
                      showActions: true,
                      footerActions: [
                        TextButton(
                          onPressed: () =>
                              showAnnouncementDetailsDialog(context, a),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.maroon,
                          ),
                          child: const Text('View Details'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.maroon,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Request Student Assistant',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(left: 14, top: 3),
        child: Text(
          'Request a student assistant for your office — sent to admin for approval',
          style: TextStyle(fontSize: 13, color: AppTheme.slate400),
        ),
      ),
    ],
  );

  Widget _submitButton(BuildContext context, AppState state) =>
      ElevatedButton.icon(
        onPressed: () => _showSubmitDialog(context, state),
        icon: const Icon(Icons.add_rounded, size: 15),
        label: const Text(
          'Request Student Assistant',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.maroon,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      );

  void _showSubmitDialog(BuildContext context, AppState state) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final deadlineCtrl = TextEditingController();
    final slotsCtrl = TextEditingController();
    final reqs = <String>[];
    var acceptsApplications = true;
    final myOffices = state.currentUserOffices;
    final officeSelection = _OfficeSelection();
    if (myOffices.length == 1) {
      officeSelection.office = myOffices.first;
    }

    showDialog(
      context: context,
      builder: (_) => AnnouncementDialog(
        title: 'Request Student Assistant',
        subtitle: 'Request a student assistant for your office — sent to admin for review',
        icon: Icons.campaign_outlined,
        onClose: () => Navigator.pop(context),
        fields: [
          _OfficePickerField(offices: myOffices, selection: officeSelection),
          const SizedBox(height: 14),
          AnnouncementTextField(
            label: 'Request Title *',
            controller: titleCtrl,
            icon: Icons.title_rounded,
          ),
          const SizedBox(height: 14),
          AnnouncementTextField(
            label: 'Description / Reason *',
            controller: bodyCtrl,
            icon: Icons.description_outlined,
            maxLines: 4,
          ),
          const SizedBox(height: 14),
          // Deadline: date picker only
          TextField(
            controller: deadlineCtrl,
            readOnly: true,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 5),
              );
              if (picked != null) {
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
                deadlineCtrl.text =
                    '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
              }
            },
            decoration: InputDecoration(
              labelText: 'Deadline (e.g. June 30, 2026)',
              prefixIcon: Icon(
                Icons.event_outlined,
                color: AppTheme.maroon,
                size: 17,
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
                borderSide: const BorderSide(
                  color: AppTheme.maroon,
                  width: 1.5,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnnouncementTextField(
            label: 'Available Slots',
            controller: slotsCtrl,
            icon: Icons.people_outline,
          ),
          StatefulBuilder(
            builder: (context, setState) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Accept applications'),
              subtitle: const Text('Turn off for a normal announcement'),
              value: acceptsApplications,
              onChanged: (value) => setState(() => acceptsApplications = value),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'REQUIREMENTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          StatefulBuilder(
            builder: (ctx, setState) => Column(
              children: [
                ...reqs.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: RequirementChip(label: e.value)),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => setState(() => reqs.removeAt(e.key)),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.red500,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty &&
                              !reqs.contains(val.trim())) {
                            setState(() => reqs.add(val.trim()));
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Add requirement (press Enter)',
                          prefixIcon: const Icon(
                            Icons.list_outlined,
                            color: AppTheme.maroon,
                            size: 17,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppTheme.slate200,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppTheme.slate200,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppTheme.maroon,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        submitButton: ElevatedButton.icon(
          onPressed: () async {
            final title = titleCtrl.text.trim();
            final body = bodyCtrl.text.trim();
            final officeName = officeSelection.resolvedName;
            if (officeName == null || officeName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Please select or enter an office for this request.'),
        backgroundColor: AppTheme.amber500,
                  behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
              );
              return;
            }
            if (title.isEmpty || body.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Title and description are required.'),
        backgroundColor: AppTheme.amber500,
                  behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
              );
              return;
            }
            final today =
                '${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}';
            final ok = await state.submitAnnouncementForApproval(
              Announcement(
                id: 'ann_${DateTime.now().millisecondsSinceEpoch}',
                title: title,
                body: body,
                postedBy: state.currentUser?.name ?? 'Supervisor',
                postedByRole: 'Supervisor',
                postedById: state.currentUser?.id,
                postedAt: today,
                deadline: deadlineCtrl.text.trim().isEmpty
                    ? null
                    : deadlineCtrl.text.trim(),
                slots: slotsCtrl.text.trim().isEmpty
                    ? null
                    : slotsCtrl.text.trim(),
                requirements: reqs,
                acceptsApplications: acceptsApplications,
                isOpen: false,
                officeId: officeSelection.office?.id,
                officeName: officeName,
                approvalStatus: 'Pending',
              ),
            );
            Navigator.pop(context);
            if (ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Request submitted! The admin will review it and create the listing.',
                  ),
                  backgroundColor: AppTheme.emerald500,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(16),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Failed to submit request. Please try again.',
                  ),
                  backgroundColor: AppTheme.red500,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(16),
                ),
              );
            }
          },
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text(
            'Submit Request',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.maroon,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}

/// Holds the supervisor's office choice for the request dialog: either an
/// existing office from [currentUserOffices], or a freshly-typed office
/// name when their office isn't in the system yet.
class _OfficeSelection {
  Office? office;
  String customName = '';

  String? get resolvedName {
    if (office != null) return office!.name;
    final trimmed = customName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Office picker: a dropdown of the supervisor's offices plus an
/// "Add a new office" option that reveals a text field for a custom name.
class _OfficePickerField extends StatefulWidget {
  final List<Office> offices;
  final _OfficeSelection selection;

  const _OfficePickerField({required this.offices, required this.selection});

  @override
  State<_OfficePickerField> createState() => _OfficePickerFieldState();
}

class _OfficePickerFieldState extends State<_OfficePickerField> {
  static const _addNewSentinel = '__add_new_office__';
  late bool _isAddingNew = widget.offices.isEmpty;
  late final _customCtrl = TextEditingController(
    text: widget.selection.customName,
  );

  InputDecoration _decoration({required String label, required IconData icon}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.maroon, size: 17),
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
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isAddingNew) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _customCtrl,
            onChanged: (value) => widget.selection.customName = value,
            decoration: _decoration(
              label: 'New Office Name *',
              icon: Icons.apartment_outlined,
            ),
          ),
          if (widget.offices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _isAddingNew = false;
                  widget.selection.customName = '';
                  _customCtrl.clear();
                }),
                icon: const Icon(Icons.arrow_back_rounded, size: 14),
                label: const Text('Choose from my offices instead'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.maroon,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'This office will be created by the admin once your request is approved.',
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
            ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      value: widget.selection.office?.id,
      decoration: _decoration(
        label: 'Office *',
        icon: Icons.apartment_outlined,
      ),
      items: [
        ...widget.offices.map(
          (o) => DropdownMenuItem(value: o.id, child: Text(o.name)),
        ),
        const DropdownMenuItem(
          value: _addNewSentinel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: AppTheme.maroon),
              SizedBox(width: 6),
              Text(
                'Add a new office',
                style: TextStyle(
                  color: AppTheme.maroon,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
      onChanged: (value) {
        if (value == _addNewSentinel) {
          setState(() {
            _isAddingNew = true;
            widget.selection.office = null;
          });
          return;
        }
        setState(() {
          widget.selection.office = widget.offices.firstWhere(
            (o) => o.id == value,
          );
        });
      },
      hint: const Text('Select your office'),
    );
  }
}