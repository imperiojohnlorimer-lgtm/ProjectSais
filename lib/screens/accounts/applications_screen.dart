import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  static const statusOptions = [
    'All',
    'Pending',
    'Approved',
    'Waitlisted',
    'Rejected',
  ];
  String statusFilter = 'All';
  String departmentFilter = 'All';
  String campusFilter = 'All';

  User? _applicantFor(AppState state, Application app) {
    for (final user in state.users) {
      if (user.id == app.applicantId) return user;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    final allApps = state.applications;
    final pendingApps = allApps.where((a) => a.status == 'Pending').length;

    final departmentOptions = [
      'All',
      ...{
        for (final a in allApps)
          if ((_applicantFor(state, a)?.department ?? '').trim().isNotEmpty)
            _applicantFor(state, a)!.department!.trim(),
      }.toList()..sort(),
    ];
    final campusOptions = [
      'All',
      ...{
        for (final a in allApps)
          if ((_applicantFor(state, a)?.campus ?? '').trim().isNotEmpty)
            _applicantFor(state, a)!.campus!.trim(),
      }.toList()..sort(),
    ];
    if (!departmentOptions.contains(departmentFilter)) departmentFilter = 'All';
    if (!campusOptions.contains(campusFilter)) campusFilter = 'All';

    final apps = allApps.where((a) {
      if (statusFilter != 'All' && a.status != statusFilter) return false;
      final applicant = _applicantFor(state, a);
      if (departmentFilter != 'All' &&
          (applicant?.department ?? '').trim() != departmentFilter) {
        return false;
      }
      if (campusFilter != 'All' &&
          (applicant?.campus ?? '').trim() != campusFilter) {
        return false;
      }
      return true;
    }).toList();

    final titleBlock = Column(
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
              'Applications',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 3),
          child: Text(
            'Manage student applications · Pending: $pendingApps',
            style: const TextStyle(fontSize: 13, color: AppTheme.slate400),
          ),
        ),
      ],
    );
    final pendingBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.red500,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.priority_high_rounded,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            '$pendingApps Pending',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    if (pendingApps > 0) ...[
                      const SizedBox(height: 10),
                      pendingBadge,
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: titleBlock),
                    if (pendingApps > 0) pendingBadge,
                  ],
                ),
        ),
        const SizedBox(height: 18),

        // ── Content ─────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Filters ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.slate200),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.slate900.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _filterGroup(
                        'Status',
                        Icons.flag_outlined,
                        statusFilter,
                        statusOptions,
                        (value) => setState(() => statusFilter = value),
                      ),
                      _dropdownFilterGroup(
                        'Department',
                        Icons.apartment_outlined,
                        departmentFilter,
                        departmentOptions,
                        (value) =>
                            setState(() => departmentFilter = value ?? 'All'),
                      ),
                      _dropdownFilterGroup(
                        'Campus',
                        Icons.location_city_outlined,
                        campusFilter,
                        campusOptions,
                        (value) =>
                            setState(() => campusFilter = value ?? 'All'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (apps.isEmpty)
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
                              Icons.assignment_outlined,
                              size: 36,
                              color: AppTheme.slate300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            allApps.isEmpty
                                ? 'No applications received yet'
                                : 'No applications match these filters',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...apps.map(
                    (a) => _AdminApplicationCard(
                      app: a,
                      state: state,
                      ctx: context,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterGroup(
    String label,
    IconData icon,
    String selected,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppTheme.slate400),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate400,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((option) {
            final active = selected == option;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onChanged(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? AppTheme.maroon : AppTheme.slate100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppTheme.slate600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _dropdownFilterGroup(
    String label,
    IconData icon,
    String selected,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppTheme.slate400),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate400,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(minWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.slate100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isDense: true,
              icon: const Icon(
                Icons.expand_more,
                size: 16,
                color: AppTheme.slate400,
              ),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate700,
              ),
              borderRadius: BorderRadius.circular(10),
              items: options
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(
                        option,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminApplicationCard extends StatefulWidget {
  final Application app;
  final AppState state;
  final BuildContext ctx;

  const _AdminApplicationCard({
    required this.app,
    required this.state,
    required this.ctx,
  });

  @override
  State<_AdminApplicationCard> createState() => _AdminApplicationCardState();
}

class _AdminApplicationCardState extends State<_AdminApplicationCard> {
  Application get app => widget.app;
  AppState get state => widget.state;
  BuildContext get ctx => widget.ctx;

  bool generatingContract = false;
  bool generatingEndorsement = false;
  String? downloadingDocumentId;

  @override
  Widget build(BuildContext context) {
    User? applicant;
    for (final user in state.users) {
      if (user.id == app.applicantId) {
        applicant = user;
        break;
      }
    }
    final announcement = state.announcements.firstWhere(
      (a) => a.id == app.announcementId,
      orElse: () => Announcement(
        id: 'unknown',
        title: 'Unknown Position',
        body: '',
        postedBy: 'Unknown',
        postedAt: '',
        requirements: [],
        isOpen: false,
      ),
    );

    final bgColor = app.status == 'Pending' ? AppTheme.slate50 : Colors.white;
    final borderColor = app.status == 'Pending'
        ? AppTheme.slate200
        : AppTheme.slate200;
    final statusColor = app.status == 'Approved'
        ? AppTheme.emerald500
        : app.status == 'Rejected'
        ? AppTheme.red500
        : app.status == 'Waitlisted'
        ? AppTheme.blue500
        : AppTheme.amber500;
    final statusBg = app.status == 'Approved'
        ? AppTheme.emerald50
        : app.status == 'Rejected'
        ? AppTheme.red50
        : app.status == 'Waitlisted'
        ? AppTheme.blue50
        : AppTheme.amber50;

    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Folder tab — colored by status, pokes out above the card
          Positioned(
            top: -20,
            left: 20,
            child: Container(
              height: 26,
              constraints: const BoxConstraints(minWidth: 84),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Text(
                app.status.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          // Folder body
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(2),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                UserAvatar(
                  avatarUrl: applicant?.avatar,
                  initials:
                      applicant?.initials ??
                      (app.applicantName.isNotEmpty
                          ? app.applicantName[0].toUpperCase()
                          : '?'),
                  size: 56,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.applicantName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        announcement.title,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.slate600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Applied ${app.appliedAt}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    app.status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (app.skills.isNotEmpty ||
                applicant != null ||
                app.remarks?.isNotEmpty == true) ...[
              const Text(
                'APPLICATION DETAILS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              if (app.skills.isNotEmpty) ...[
                const Text(
                  'Skills / Qualifications',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: app.skills
                      .map(
                        (skill) => Chip(
                          label: Text(skill),
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.maroon,
                          ),
                          backgroundColor: AppTheme.maroon50,
                          side: BorderSide(
                            color: AppTheme.maroon.withValues(alpha: 0.2),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (applicant != null) ...[
                if (app.skills.isNotEmpty) const SizedBox(height: 8),
                Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  children: [
                    if (applicant.email.isNotEmpty)
                      _applicationDetail('Email', applicant.email),
                    if (applicant.phone?.isNotEmpty == true)
                      _applicationDetail('Phone', applicant.phone!),
                    if (applicant.department?.isNotEmpty == true)
                      _applicationDetail('Department', applicant.department!),
                    if (applicant.campus?.isNotEmpty == true)
                      _applicationDetail('Campus', applicant.campus!),
                  ],
                ),
              ],
              if (app.remarks?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _applicationDetail('Remarks', app.remarks!),
              ],
              const SizedBox(height: 16),
            ],
            // Documents
            if (app.submittedDocuments.isNotEmpty) ...[
              const Text(
                'SUBMITTED DOCUMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              ...app.submittedDocuments.asMap().entries.map((e) {
                final index = e.key;
                final doc = e.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index < app.submittedDocuments.length - 1 ? 10 : 0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.emerald500, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: AppTheme.emerald500,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doc.fileName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slate900,
                                ),
                              ),
                              if (doc.fileSize != null)
                                Text(
                                  '${doc.fileSize!.toStringAsFixed(2)} MB',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.slate400,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed:
                              downloadingDocumentId == doc.id
                              ? null
                              : ((doc.storagePath != null &&
                                          doc.storagePath!.isNotEmpty) ||
                                      (doc.bytes != null &&
                                          doc.bytes!.isNotEmpty)
                                  ? () => _downloadDocument(doc)
                                  : null),
                          icon: downloadingDocumentId == doc.id
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.download_outlined, size: 13),
                          label: Text(
                            downloadingDocumentId == doc.id
                                ? 'Downloading...'
                                : 'Download',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.emerald500,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppTheme.slate200,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
            // Action buttons
            if (app.status == 'Pending')
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(context),
                    icon: const Icon(Icons.clear_outlined, size: 14),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.red500,
                      side: const BorderSide(color: AppTheme.red500),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _waitlistApplication(context),
                    icon: const Icon(Icons.schedule_outlined, size: 14),
                    label: const Text('Waitlist'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.blue500,
                      side: const BorderSide(color: AppTheme.blue500),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _approveApplication(context),
                    icon: const Icon(Icons.check_rounded, size: 14),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              )
            else if (app.status == 'Waitlisted')
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(context),
                    icon: const Icon(Icons.clear_outlined, size: 14),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.red500,
                      side: const BorderSide(color: AppTheme.red500),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _approveApplication(context),
                    icon: const Icon(Icons.how_to_reg_outlined, size: 14),
                    label: const Text('Approve Anyway'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              )
            else if (app.status == 'Approved' || app.status == 'Accepted')
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: generatingContract
                        ? null
                        : () async {
                            setState(() => generatingContract = true);
                            try {
                              await state.generateContractOfAppointmentDocument(
                                app.id,
                              );
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Contract of Appointment generated.',
                                  ),
                                  backgroundColor: AppTheme.emerald500,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Unable to generate: $e'),
                                  backgroundColor: AppTheme.amber500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => generatingContract = false);
                              }
                            }
                          },
                    icon: generatingContract
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                AppTheme.maroon,
                              ),
                            ),
                          )
                        : const Icon(Icons.description_outlined, size: 14),
                    label: Text(
                      generatingContract
                          ? 'Generating Contract...'
                          : 'Generate Contract of Appointment',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.maroon,
                      side: const BorderSide(color: AppTheme.maroon200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: generatingEndorsement
                        ? null
                        : () async {
                            setState(() => generatingEndorsement = true);
                            try {
                              await state.generateEndorsementLetterDocument(
                                app.id,
                              );
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Endorsement Letter generated.',
                                  ),
                                  backgroundColor: AppTheme.emerald500,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Unable to generate: $e'),
                                  backgroundColor: AppTheme.amber500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => generatingEndorsement = false);
                              }
                            }
                          },
                    icon: generatingEndorsement
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.mail_outline, size: 14),
                    label: Text(
                      generatingEndorsement
                          ? 'Generating Letter...'
                          : 'Generate Endorsement Letter',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
          ],
        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _applicationDetail(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Future<void> _downloadDocument(ApplicationDocument doc) async {
    final messenger = ScaffoldMessenger.of(ctx);
    setState(() => downloadingDocumentId = doc.id);
    try {
      if (doc.storagePath != null && doc.storagePath!.isNotEmpty) {
        final url = await SupabaseStorageService.instance.getDocumentUrl(
          doc.storagePath!,
        );
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) throw Exception('The browser could not open the document.');
      } else if (doc.bytes != null && doc.bytes!.isNotEmpty) {
        final uri = Uri.dataFromBytes(
          doc.bytes!,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          parameters: {'filename': doc.fileName},
        );
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
        );
        if (!opened) throw Exception('The browser could not open the document.');
      } else {
        throw Exception(
          'This document has no file content or storage path. Please upload it again.',
        );
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('Opening ${doc.fileName}...'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Unable to download: $e'),
          backgroundColor: AppTheme.amber500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
    } finally {
      if (mounted) setState(() => downloadingDocumentId = null);
    }
  }

  void _showRejectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        String remarks = '';
        return AlertDialog(
          title: const Text('Reject Application'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Reject ${app.applicantName}\'s application?'),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => remarks = value,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Add remarks (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                state.updateApplicationStatus(
                  app.id,
                  'Rejected',
                  remarks: remarks,
                );
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Application rejected'),
                    backgroundColor: AppTheme.red500,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red500,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  void _approveApplication(BuildContext context) {
    state.updateApplicationStatus(app.id, 'Approved');
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('${app.applicantName}\'s application approved'),
        backgroundColor: AppTheme.emerald500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _waitlistApplication(BuildContext context) {
    state.updateApplicationStatus(app.id, 'Waitlisted');
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('${app.applicantName} was added to the waitlist'),
        backgroundColor: AppTheme.blue500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
    );
  }
}