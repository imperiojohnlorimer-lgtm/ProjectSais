import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/endorsement_document_service.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/web_download_stub.dart'
    if (dart.library.html) '../../utils/web_download.dart'
    as web_download;
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
  String _search = '';
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
    final approvedApps = allApps
        .where((a) => a.status == 'Approved' || a.status == 'Accepted')
        .length;
    final waitlistedApps = allApps
        .where((a) => a.status == 'Waitlisted')
        .length;
    final rejectedApps = allApps.where((a) => a.status == 'Rejected').length;
    final statusCounts = <String, int>{
      'All': allApps.length,
      'Pending': pendingApps,
      'Approved': approvedApps,
      'Waitlisted': waitlistedApps,
      'Rejected': rejectedApps,
    };
    final reviewedFraction = allApps.isEmpty
        ? 0.0
        : (allApps.length - pendingApps) / allApps.length;

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

    final query = _search.trim().toLowerCase();
    final apps = allApps.where((a) {
      if (statusFilter != 'All' && a.status != statusFilter) return false;
      if (query.isNotEmpty &&
          !a.applicantName.toLowerCase().contains(query) &&
          !a.announcementTitle.toLowerCase().contains(query)) {
        return false;
      }
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

    final endorsementButton = OutlinedButton.icon(
      onPressed: () => _showEndorsementSummaryDialog(context, state, allApps),
      icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
      label: const Text('Endorsement Summary'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.maroon,
        side: const BorderSide(color: AppTheme.maroon),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: HeroBanner(
            isMobile: isMobile,
            icon: Icons.assignment_turned_in_rounded,
            title: 'Applications',
            subtitle: 'Review and decide on student applications',
            searchHint: 'Search applicants or postings...',
            onSearch: (value) => setState(() => _search = value),
            filters: [endorsementButton],
            stats: [
              HeroStatData(
                label: 'Total',
                value: '${allApps.length}',
                icon: Icons.inbox_rounded,
              ),
              HeroStatData(
                label: 'Pending',
                value: '$pendingApps',
                icon: Icons.pending_actions_rounded,
              ),
              HeroStatData(
                label: 'Approved',
                value: '$approvedApps',
                icon: Icons.check_circle_rounded,
              ),
              HeroStatData(
                label: 'Waitlisted',
                value: '$waitlistedApps',
                icon: Icons.schedule_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Content ─────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (allApps.isNotEmpty) ...[
                  ProgressStrip(
                    label: 'Reviewed',
                    icon: Icons.fact_check_rounded,
                    progress: reviewedFraction,
                    trailing:
                        '${allApps.length - pendingApps}/${allApps.length}',
                  ),
                  const SizedBox(height: 14),
                ],
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
                        counts: statusCounts,
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
    ValueChanged<String> onChanged, {
    Map<String, int>? counts,
  }) {
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: active ? AppTheme.maroon : AppTheme.slate100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : AppTheme.slate600,
                      ),
                    ),
                    if (counts != null && (counts[option] ?? 0) > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white.withValues(alpha: 0.25)
                              : AppTheme.maroon.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${counts[option]}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: active ? Colors.white : AppTheme.maroon,
                          ),
                        ),
                      ),
                    ],
                  ],
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
                      child: Text(option, overflow: TextOverflow.ellipsis),
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

  Announcement? _announcementFor(AppState state, Application app) {
    for (final ann in state.announcements) {
      if (ann.id == app.announcementId) return ann;
    }
    return null;
  }

  /// The office a student is currently assigned to (via the Head's Offices
  /// roster), falling back to the office the original hiring Announcement
  /// was posted for, then the applicant's own department, if they haven't
  /// been placed into an Office roster yet.
  String _assignedOfficeFor(AppState state, Application app, User? applicant) {
    if (applicant != null) {
      final offices = state.officesForUser(applicant);
      if (offices.isNotEmpty) return offices.first.name;
    }
    final ann = _announcementFor(state, app);
    return ann?.officeName ?? applicant?.department ?? '';
  }

  Future<void> _showEndorsementSummaryDialog(
    BuildContext context,
    AppState state,
    List<Application> allApps,
  ) async {
    final approved = allApps
        .where((a) => a.status == 'Approved' || a.status == 'Accepted')
        .toList();

    if (approved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No approved applicants to endorse yet.'),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Every approved applicant gets a permanent, unique SA ID the first
    // time they're endorsed — assigned automatically (sequential "SA 001",
    // "SA 002", ...), never typed in by hand, and reused on every future
    // endorsement letter once assigned.
    final saIds = <String>[];
    for (final app in approved) {
      saIds.add(await state.ensureStudentAssistantId(app.applicantId) ?? '');
    }
    if (!context.mounted) return;

    final today = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final dateCtrl = TextEditingController(
      text: '${months[today.month - 1]} ${today.day}, ${today.year}',
    );
    final semesterCtrl = TextEditingController(text: '1st Semester');
    final academicYearCtrl = TextEditingController(
      text: state.academicYear.replaceAll('-', '–'),
    );
    final effectivePeriodCtrl = TextEditingController();
    final batchLabelCtrl = TextEditingController(text: 'BATCH 1');
    final vpNameCtrl = TextEditingController();
    final campusDirectorCtrl = TextEditingController();
    final headSwsCtrl = TextEditingController();
    final preparedByNameCtrl = TextEditingController(
      text: state.currentUser?.name ?? '',
    );
    final preparedByTitleCtrl = TextEditingController(
      text: 'Head, Student Affairs and Services',
    );

    final officeCtrls = <TextEditingController>[];
    final supervisorCtrls = <TextEditingController>[];
    for (final app in approved) {
      final ann = _announcementFor(state, app);
      final applicant = _applicantFor(state, app);
      officeCtrls.add(
        TextEditingController(text: _assignedOfficeFor(state, app, applicant)),
      );
      supervisorCtrls.add(
        TextEditingController(
          text: ann?.postedByRole == 'Supervisor' ? ann!.postedBy : '',
        ),
      );
    }

    Future<void> generate() async {
      final messenger = ScaffoldMessenger.of(context);
      final entries = <EndorsementEntry>[
        for (var i = 0; i < approved.length; i++)
          EndorsementEntry(
            saNumber: saIds[i],
            name: approved[i].applicantName,
            office: officeCtrls[i].text.trim(),
            supervisor: supervisorCtrls[i].text.trim(),
          ),
      ];

      final data = EndorsementData(
        date: dateCtrl.text.trim(),
        semester: semesterCtrl.text.trim(),
        academicYear: academicYearCtrl.text.trim(),
        effectivePeriod: effectivePeriodCtrl.text.trim(),
        batchLabel: batchLabelCtrl.text.trim(),
        vpName: vpNameCtrl.text.trim(),
        campusDirectorName: campusDirectorCtrl.text.trim(),
        headSwsName: headSwsCtrl.text.trim(),
        preparedByName: preparedByNameCtrl.text.trim(),
        preparedByTitle: preparedByTitleCtrl.text.trim(),
        entries: entries,
      );

      try {
        final doc = await const EndorsementDocumentService()
            .generateEndorsement(data: data);
        final bytes = doc.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw Exception('Failed to generate the endorsement document.');
        }

        if (kIsWeb) {
          web_download.WebDownloadUtils.downloadBytes(doc.fileName, bytes);
        } else {
          final uri = Uri.dataFromBytes(
            bytes,
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            parameters: {'filename': doc.fileName},
          );
          final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
          if (!opened)
            throw Exception('The browser could not open the document.');
        }

        if (!context.mounted) return;
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Generated ${doc.fileName}'),
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
            content: Text('Could not generate document: $e'),
            backgroundColor: AppTheme.red500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Container(
          width: 640,
          constraints: const BoxConstraints(maxHeight: 780),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.maroon, AppTheme.maroonDark],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generate Endorsement Summary',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'One letter listing every Approved Student Assistant, '
                            'for the VP for Student Affairs and Services.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(dialogContext),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
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
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _endorsementField('Date', dateCtrl, width: 190),
                          _endorsementField(
                            'Semester',
                            semesterCtrl,
                            width: 150,
                          ),
                          _endorsementField(
                            'Academic Year',
                            academicYearCtrl,
                            width: 150,
                          ),
                          _endorsementField(
                            'Batch Label',
                            batchLabelCtrl,
                            width: 120,
                          ),
                          _endorsementField(
                            'Effective Period (e.g. "January 5, 2026, to April 30, 2026")',
                            effectivePeriodCtrl,
                            width: 600,
                          ),
                          _endorsementField('VP Name', vpNameCtrl, width: 290),
                          _endorsementField(
                            'Campus Director Name',
                            campusDirectorCtrl,
                            width: 290,
                          ),
                          _endorsementField(
                            'Head, Student Welfare Services',
                            headSwsCtrl,
                            width: 290,
                          ),
                          _endorsementField(
                            'Prepared By (Name)',
                            preparedByNameCtrl,
                            width: 290,
                          ),
                          _endorsementField(
                            'Prepared By (Title)',
                            preparedByTitleCtrl,
                            width: 600,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Approved Student Assistants (${approved.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (var i = 0; i < approved.length; i++)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.slate50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.slate200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.maroon.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      saIds[i],
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.maroon,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    approved[i].applicantName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slate800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  _endorsementField(
                                    'Office/Department',
                                    officeCtrls[i],
                                    width: 260,
                                  ),
                                  _endorsementField(
                                    'Immediate Supervisor',
                                    supervisorCtrls[i],
                                    width: 260,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.slate100)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: generate,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text(
                      'Generate & Download',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.maroon,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _endorsementField(
    String label,
    TextEditingController controller, {
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
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
            borderSide: const BorderSide(color: AppTheme.maroon, width: 1.5),
          ),
        ),
      ),
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

  /// 'approve', 'waitlist' or 'reject' while that decision is saving.
  String? _deciding;

  /// The decision button's icon, or a spinner while that decision saves.
  Widget _decisionIcon(String action, IconData icon, Color spinnerColor) =>
      _deciding == action
      ? SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: spinnerColor,
          ),
        )
      : Icon(icon, size: 14);

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
                            _applicationDetail(
                              'Department',
                              applicant.department!,
                            ),
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
                          bottom: index < app.submittedDocuments.length - 1
                              ? 10
                              : 0,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.emerald500,
                              width: 1,
                            ),
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
                                onPressed: downloadingDocumentId == doc.id
                                    ? null
                                    : ((doc.storagePath != null &&
                                                  doc
                                                      .storagePath!
                                                      .isNotEmpty) ||
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
                                    : const Icon(
                                        Icons.download_outlined,
                                        size: 13,
                                      ),
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
                  if (app.status == 'Pending' || app.status == 'Waitlisted')
                    // Wrap rather than Row so the buttons drop to a second
                    // line instead of running off a narrow card.
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _deciding != null
                              ? null
                              : () => _showRejectDialog(context),
                          icon: _decisionIcon(
                            'reject',
                            Icons.clear_outlined,
                            AppTheme.red500,
                          ),
                          label: Text(
                            _deciding == 'reject' ? 'Rejecting...' : 'Reject',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.red500,
                            side: const BorderSide(color: AppTheme.red500),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                        if (app.status == 'Pending')
                          OutlinedButton.icon(
                            onPressed: _deciding != null
                                ? null
                                : () => _waitlistApplication(context),
                            icon: _decisionIcon(
                              'waitlist',
                              Icons.schedule_outlined,
                              AppTheme.blue500,
                            ),
                            label: Text(
                              _deciding == 'waitlist'
                                  ? 'Waitlisting...'
                                  : 'Waitlist',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.blue500,
                              side: const BorderSide(color: AppTheme.blue500),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: _deciding != null
                              ? null
                              : () => _approveApplication(context),
                          icon: _decisionIcon(
                            'approve',
                            app.status == 'Waitlisted'
                                ? Icons.how_to_reg_outlined
                                : Icons.check_rounded,
                            Colors.white,
                          ),
                          label: Text(
                            _deciding == 'approve'
                                ? 'Approving...'
                                : app.status == 'Waitlisted'
                                ? 'Approve Anyway'
                                : 'Approve',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.emerald500,
                            foregroundColor: Colors.white,
                            // Stays green, slightly faded, while approving
                            // instead of turning grey like a dead button.
                            disabledBackgroundColor: _deciding == 'approve'
                                ? AppTheme.emerald500.withValues(alpha: 0.75)
                                : null,
                            disabledForegroundColor: _deciding == 'approve'
                                ? Colors.white
                                : null,
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
                                  if (!await _confirmReplace(
                                    'Contract of Appointment',
                                  )) {
                                    return;
                                  }
                                  setState(() => generatingContract = true);
                                  try {
                                    await state
                                        .generateContractOfAppointmentDocument(
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
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        margin: const EdgeInsets.all(16),
                                      ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => generatingContract = false,
                                      );
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
                              : const Icon(
                                  Icons.description_outlined,
                                  size: 14,
                                ),
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
                                  if (!await _confirmReplace(
                                    'Endorsement Letter',
                                  )) {
                                    return;
                                  }
                                  setState(() => generatingEndorsement = true);
                                  try {
                                    await state
                                        .generateEndorsementLetterDocument(
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
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        margin: const EdgeInsets.all(16),
                                      ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => generatingEndorsement = false,
                                      );
                                    }
                                  }
                                },
                          icon: generatingEndorsement
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
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
        if (!opened)
          throw Exception('The browser could not open the document.');
      } else if (doc.bytes != null && doc.bytes!.isNotEmpty) {
        final uri = Uri.dataFromBytes(
          doc.bytes!,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          parameters: {'filename': doc.fileName},
        );
        final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!opened)
          throw Exception('The browser could not open the document.');
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
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
                Navigator.pop(dialogContext);
                _decide(
                  'reject',
                  'Rejected',
                  remarks: remarks,
                  success: '${app.applicantName}\'s application rejected',
                  color: AppTheme.red500,
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

  /// Generating a document again replaces the copy already on file, so ask
  /// first when there is one. Returns whether to go ahead.
  Future<bool> _confirmReplace(String requirementName) async {
    final exists = app.submittedDocuments.any(
      (doc) => doc.requirementName == requirementName,
    );
    if (!exists) return true;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Replace the $requirementName?',
      message:
          'A $requirementName was already generated for '
          '${app.applicantName}. Generating it again replaces that copy with '
          'a new one.',
      confirmLabel: 'Replace',
      confirmColor: AppTheme.maroon,
    );
    return confirmed && mounted;
  }

  Future<void> _approveApplication(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve application?',
      message:
          '${app.applicantName} will become a Student Assistant and get an '
          'SA ID, and their Contract of Appointment and Endorsement Letter '
          'will be generated. They will be notified.',
      confirmLabel: 'Approve',
      confirmColor: AppTheme.emerald500,
    );
    if (!confirmed || !mounted) return;
    await _decide(
      'approve',
      'Approved',
      success:
          '${app.applicantName}\'s application approved — their contract '
          'and endorsement letter are ready',
      color: AppTheme.emerald500,
    );
  }

  /// Saves a decision while its button shows a spinner, and only then says
  /// how it went. Approving takes a few seconds (it generates and uploads
  /// the contract and endorsement letter), so the message used to appear
  /// before the work was actually done — or even if it failed.
  Future<void> _decide(
    String action,
    String status, {
    required String success,
    required Color color,
    String? remarks,
  }) async {
    final messenger = ScaffoldMessenger.of(ctx);
    setState(() => _deciding = action);
    try {
      await state.updateApplicationStatus(app.id, status, remarks: remarks);
      messenger.showSnackBar(
        SnackBar(
          content: Text(success),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update ${app.applicantName}\'s application: $error',
          ),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  Future<void> _waitlistApplication(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Waitlist application?',
      message:
          '${app.applicantName}\'s application will be moved to the waitlist '
          'and they will be notified. You can still approve them later.',
      confirmLabel: 'Waitlist',
      confirmColor: AppTheme.amber500,
    );
    if (!confirmed || !mounted) return;
    await _decide(
      'waitlist',
      'Waitlisted',
      success: '${app.applicantName} was added to the waitlist',
      color: AppTheme.blue500,
    );
  }
}
