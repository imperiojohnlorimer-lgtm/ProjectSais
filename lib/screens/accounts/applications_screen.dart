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
import '../../widgets/application_status.dart';
import '../../widgets/shared_widgets.dart';

/// The applicants on the Head's Applications & Screening page
/// ([ApplicantScreeningScreen]). Each applicant's skills are matched
/// against the supervisors' open requests; the match only filters and
/// sorts, so nobody is left out. The Head ticks who goes to screening,
/// rejects an application with a wrong document (the student can apply
/// again), and opens the interview and assessment form from here.
class ApplicationsPanel extends StatefulWidget {
  /// What the page's search box holds: part of a name or a skill.
  final String search;

  /// Opens the interview and assessment form for an application.
  final ValueChanged<Application> onAssess;

  const ApplicationsPanel({
    super.key,
    this.search = '',
    required this.onAssess,
  });

  @override
  State<ApplicationsPanel> createState() => _ApplicationsPanelState();
}

class _ApplicationsPanelState extends State<ApplicationsPanel> {
  static const _statuses = [
    Application.pending,
    Application.forScreening,
    Application.approved,
    Application.waitlisted,
  ];
  String statusFilter = 'All';
  String departmentFilter = 'All';
  String campusFilter = 'All';

  /// [_anyMatch], [_hasMatch], [_noMatch], or the id of one request.
  String _matchFilter = _anyMatch;
  static const _anyMatch = 'All';
  static const _hasMatch = 'Matches a request';
  static const _noMatch = 'No match';

  /// Pending applications ticked to send to screening.
  final _selected = <String>{};
  bool _sending = false;

  User? _applicantFor(AppState state, Application app) {
    for (final user in state.users) {
      if (user.id == app.applicantId) return user;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allApps = state.currentApplications;
    int count(bool Function(Application) test) => allApps.where(test).length;
    final statusCounts = <String, int>{
      'All': allApps.length,
      Application.pending: count((a) => a.status == Application.pending),
      Application.forScreening: count(
        (a) => a.status == Application.forScreening,
      ),
      Application.approved: count((a) => a.isApproved),
      Application.waitlisted: count((a) => a.status == Application.waitlisted),
      Application.rejected: count((a) => a.status == Application.rejected),
    };
    final pendingApps = statusCounts[Application.pending]!;
    // Rejected is only on applications decided before screening replaced it.
    final statusOptions = [
      'All',
      ..._statuses,
      if (statusCounts[Application.rejected]! > 0) Application.rejected,
    ];
    if (!statusOptions.contains(statusFilter)) statusFilter = 'All';
    final pickedFraction = allApps.isEmpty
        ? 0.0
        : (allApps.length - pendingApps) / allApps.length;

    final requests = state.openOfficeRequests;
    if (![_anyMatch, _hasMatch, _noMatch].contains(_matchFilter) &&
        !requests.any((r) => r.id == _matchFilter)) {
      _matchFilter = _anyMatch;
    }
    final chosenRequest = requests
        .where((r) => r.id == _matchFilter)
        .firstOrNull;
    final matches = {for (final a in allApps) a.id: state.skillMatchesFor(a)};

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

    final query = widget.search.trim().toLowerCase();
    final apps = allApps.where((a) {
      if (statusFilter == Application.approved
          ? !a.isApproved
          : statusFilter != 'All' && a.status != statusFilter) {
        return false;
      }
      if (query.isNotEmpty &&
          !a.applicantName.toLowerCase().contains(query) &&
          !state
              .applicantSkills(a)
              .any((skill) => skill.toLowerCase().contains(query))) {
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
      if (_matchFilter == _hasMatch && matches[a.id]!.isEmpty) return false;
      if (_matchFilter == _noMatch && matches[a.id]!.isNotEmpty) return false;
      // A request picked shows who matches it; everyone else is still under
      // All and No match.
      if (chosenRequest != null &&
          !matches[a.id]!.any((m) => m.request.id == chosenRequest.id)) {
        return false;
      }
      return true;
    }).toList();
    // Best match first when matching is what the Head is looking at; a
    // request picked ranks by its own match. Ties keep their order.
    if (_matchFilter != _anyMatch && _matchFilter != _noMatch) {
      int score(Application a) => chosenRequest != null
          ? SkillMatch.of(chosenRequest, state.applicantSkills(a)).count
          : (matches[a.id]!.firstOrNull?.count ?? 0);
      final order = {for (final (i, a) in apps.indexed) a.id: i};
      apps.sort((a, b) {
        final byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : order[a.id]!.compareTo(order[b.id]!);
      });
    }

    // Only Pending applications can be ticked; drop any that moved on.
    _selected.removeWhere(
      (id) =>
          !allApps.any((a) => a.id == id && a.status == Application.pending),
    );
    final pendingShown = [
      for (final a in apps)
        if (a.status == Application.pending) a.id,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HiringCallStrip(state: state),
        const SizedBox(height: 14),
        if (allApps.isNotEmpty) ...[
          ProgressStrip(
            label: 'Picked for screening or decided',
            icon: Icons.fact_check_rounded,
            progress: pickedFraction,
            trailing: '${allApps.length - pendingApps}/${allApps.length}',
          ),
          const SizedBox(height: 14),
        ],
        // ── Filters ─────────────────────────────────
        Container(
          width: double.infinity,
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
              _filterGroup(
                'Skill match',
                Icons.join_inner_rounded,
                chosenRequest == null ? _matchFilter : '',
                const [_anyMatch, _hasMatch, _noMatch],
                (value) => setState(() => _matchFilter = value),
              ),
              _requestFilter(requests, chosenRequest),
              _dropdownFilterGroup(
                'Department',
                Icons.apartment_outlined,
                departmentFilter,
                departmentOptions,
                (value) => setState(() => departmentFilter = value ?? 'All'),
              ),
              _dropdownFilterGroup(
                'Campus',
                Icons.location_city_outlined,
                campusFilter,
                campusOptions,
                (value) => setState(() => campusFilter = value ?? 'All'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (pendingShown.isNotEmpty) ...[
          _selectionBar(state, pendingShown),
          const SizedBox(height: 8),
        ],
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
              key: ValueKey(a.id),
              app: a,
              state: state,
              ctx: context,
              matches: matches[a.id]!,
              chosenRequest: chosenRequest,
              onAssess: widget.onAssess,
              selectable: a.status == Application.pending,
              selected: _selected.contains(a.id),
              onSelected: _sending
                  ? null
                  : (value) => setState(
                      () =>
                          value ? _selected.add(a.id) : _selected.remove(a.id),
                    ),
            ),
          ),
      ],
    );
  }

  /// "Request": all, or one open supervisor request to rank applicants by.
  Widget _requestFilter(List<Announcement> requests, Announcement? chosen) {
    String label(Announcement r) {
      final office = r.officeName?.trim() ?? '';
      final skills = r.skills.isEmpty
          ? 'no skills listed'
          : r.skills.join(', ');
      return office.isEmpty
          ? '${r.title} ($skills)'
          : '$office · ${r.title} ($skills)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 13, color: AppTheme.slate400),
            SizedBox(width: 5),
            Text(
              'Office request',
              style: TextStyle(
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
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: chosen == null ? AppTheme.slate100 : AppTheme.maroon50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: chosen?.id ?? '',
              isDense: true,
              isExpanded: true,
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
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(
                    requests.isEmpty
                        ? 'No open requests'
                        : 'Any request (${requests.length} open)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final r in requests)
                  DropdownMenuItem<String>(
                    value: r.id,
                    child: Text(label(r), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(
                () => _matchFilter = value == null || value.isEmpty
                    ? _anyMatch
                    : value,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tick all / send the ticked Pending applications to screening.
  Widget _selectionBar(AppState state, List<String> pendingShown) {
    final allTicked = pendingShown.every(_selected.contains);
    final count = _selected.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
      decoration: BoxDecoration(
        color: count > 0 ? AppTheme.maroon50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: count > 0 ? AppTheme.maroon200 : AppTheme.slate200,
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: count == 0 ? false : (allTicked ? true : null),
                tristate: true,
                activeColor: AppTheme.maroon,
                onChanged: _sending
                    ? null
                    : (_) => setState(() {
                        if (allTicked) {
                          _selected.removeAll(pendingShown);
                        } else {
                          _selected.addAll(pendingShown);
                        }
                      }),
              ),
              Text(
                count == 0
                    ? 'Tick the applicants to screen '
                          '(${pendingShown.length} pending shown)'
                    : '$count selected for screening',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate700,
                ),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: count == 0 || _sending
                ? null
                : () => _sendSelected(state),
            icon: _sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.how_to_reg_outlined, size: 16),
            label: Text(
              _sending
                  ? 'Sending...'
                  : count == 0
                  ? 'Send to Screening'
                  : 'Send $count to Screening',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.violet500,
              disabledBackgroundColor: _sending
                  ? AppTheme.violet500.withValues(alpha: 0.7)
                  : null,
              disabledForegroundColor: _sending ? Colors.white : null,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSelected(AppState state) async {
    final ids = _selected.toList();
    final confirmed = await showConfirmDialog(
      context,
      title:
          'Send ${ids.length} applicant${ids.length == 1 ? '' : 's'} to '
          'screening?',
      message:
          'They will be told they were selected for screening and will show '
          'in Applicant Screening. Everyone else stays Pending.',
      confirmLabel: 'Send to Screening',
      confirmColor: AppTheme.violet500,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    final sent = await state.sendToScreening(ids);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _selected.clear();
    });
    final failed = ids.length - sent;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '$sent sent to screening'
              : '$sent sent to screening; $failed could not be saved. '
                    'Try those again.',
        ),
        backgroundColor: failed == 0 ? AppTheme.violet500 : AppTheme.amber500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
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
          mainAxisSize: MainAxisSize.min,
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
          mainAxisSize: MainAxisSize.min,
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
        // A long department name is cut short rather than running off a
        // phone.
        Container(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.slate100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isDense: true,
              isExpanded: true,
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
}

/// "Endorsement Summary": one letter listing every approved Student
/// Assistant, for the VP for Student Affairs and Services.
class EndorsementSummaryButton extends StatelessWidget {
  const EndorsementSummaryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        final state = context.read<AppState>();
        _showEndorsementSummaryDialog(context, state, state.applications);
      },
      icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
      label: const Text('Endorsement Summary'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.maroon,
        side: const BorderSide(color: AppTheme.maroon),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  User? _applicantFor(AppState state, Application app) {
    for (final user in state.users) {
      if (user.id == app.applicantId) return user;
    }
    return null;
  }

  Announcement? _announcementFor(AppState state, Application app) {
    for (final ann in state.announcements) {
      if (ann.id == app.announcementId) return ann;
    }
    return null;
  }

  /// The office a student is placed in (via the Head's Offices roster). An
  /// older application made to an office's posting falls back to that
  /// office; otherwise it's blank for the Head to fill in, since approved
  /// applicants have no office until they're placed.
  String _assignedOfficeFor(AppState state, Application app, User? applicant) {
    if (applicant != null) {
      final offices = state.officesForUser(applicant);
      if (offices.isNotEmpty) return offices.first.name;
    }
    final ann = _announcementFor(state, app);
    return ann?.isSupervisorRequest == true ? ann!.officeName ?? '' : '';
  }

  /// The supervisors of the office [applicant] is placed in, else the
  /// supervisor whose posting an older application was made to.
  String _supervisorFor(AppState state, Application app, User? applicant) {
    if (applicant != null) {
      final offices = state.officesForUser(applicant);
      if (offices.isNotEmpty) return offices.first.headNames.join(', ');
    }
    final ann = _announcementFor(state, app);
    return ann?.isSupervisorRequest == true ? ann!.postedBy : '';
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
      final applicant = _applicantFor(state, app);
      officeCtrls.add(
        TextEditingController(text: _assignedOfficeFor(state, app, applicant)),
      );
      supervisorCtrls.add(
        TextEditingController(text: _supervisorFor(state, app, applicant)),
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

  /// How the applicant's skills match the open supervisor requests, best
  /// first; empty when they match none.
  final List<SkillMatch> matches;

  /// The request the list is filtered by, whose match is shown instead.
  final Announcement? chosenRequest;

  /// Opens the interview and assessment form for this application.
  final ValueChanged<Application>? onAssess;

  /// Whether the card has a tick box for sending it to screening.
  final bool selectable;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  const _AdminApplicationCard({
    super.key,
    required this.app,
    required this.state,
    required this.ctx,
    this.matches = const [],
    this.chosenRequest,
    this.onAssess,
    this.selectable = false,
    this.selected = false,
    this.onSelected,
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

  /// 'approve', 'reject', 'screen' or 'unscreen' while that change is
  /// saving.
  String? _deciding;

  /// The decision button's icon, or a spinner while that decision saves.
  Widget _decisionIcon(String action, IconData icon, Color spinnerColor) =>
      _deciding == action
      ? SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
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
    final screening = state.screeningRecords
        .where((r) => r.applicationId == app.id)
        .firstOrNull;
    final offices = applicant == null
        ? const <Office>[]
        : state.officesForUser(applicant);
    final appliedFor =
        app.announcementTitle.isEmpty ||
            app.announcementTitle == Application.generalTitle
        ? 'Applying to be a Student Assistant'
        : app.announcementTitle;

    final statusColor = applicationStatusColor(app.status);
    final statusBg = statusColor.withValues(alpha: 0.1);

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
              color: widget.selected
                  ? AppTheme.maroon50
                  : app.status == Application.pending
                  ? AppTheme.slate50
                  : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(2),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(
                color: widget.selected ? AppTheme.maroon200 : AppTheme.slate200,
                width: 1,
              ),
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
                      if (widget.selectable) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Checkbox(
                            value: widget.selected,
                            activeColor: AppTheme.maroon,
                            onChanged: widget.onSelected == null
                                ? null
                                : (value) => widget.onSelected!(value ?? false),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
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
                              appliedFor,
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
                  _skillMatchSection(),
                  const SizedBox(height: 16),
                  if (app.skills.isNotEmpty ||
                      applicant != null ||
                      screening != null ||
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
                          if (app.isApproved)
                            _applicationDetail(
                              'Office',
                              offices.isEmpty
                                  ? 'Not placed yet'
                                  : offices.map((o) => o.name).join(', '),
                            ),
                        ],
                      ),
                    ],
                    if (screening != null) ...[
                      const SizedBox(height: 8),
                      _applicationDetail(
                        'Screening score',
                        '${screening.averageScore.toStringAsFixed(1)}/5 · '
                            '${screening.recommendation}',
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
                                    // What it was uploaded as, so a wrong
                                    // file is easy to spot.
                                    if (doc.requirementName.trim().isNotEmpty)
                                      Text(
                                        RequirementSpec.parse(
                                          doc.requirementName,
                                        ).label,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.slate500,
                                        ),
                                      ),
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
                  // Full width, so the buttons sit at the right.
                  SizedBox(
                    width: double.infinity,
                    child: _actions(context, offices, screening != null),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// How the applicant's skills meet what supervisors asked for. Everyone
  /// is listed whatever their match; this only helps the Head choose.
  Widget _skillMatchSection() {
    final chosen = widget.chosenRequest;
    final rows = chosen != null
        ? [SkillMatch.of(chosen, state.applicantSkills(app))]
        : widget.matches.take(3).toList();
    final noRequests = state.openOfficeRequests.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.join_inner_rounded,
                size: 14,
                color: AppTheme.maroon,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'SKILL MATCH WITH OFFICE REQUESTS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (chosen == null && widget.matches.length > 3)
                Text(
                  '+${widget.matches.length - 3} more',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (noRequests)
            const Text(
              'No approved supervisor requests are open to match against.',
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            )
          else if (rows.isEmpty)
            const Text(
              'No match with the open requests. They can still be screened '
              'and placed in any office.',
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            )
          else
            for (final match in rows) _matchRow(match),
        ],
      ),
    );
  }

  Widget _matchRow(SkillMatch match) {
    final request = match.request;
    final color = match.hasMatch ? AppTheme.emerald500 : AppTheme.slate400;
    final place = request.officeName?.trim().isNotEmpty == true
        ? request.officeName!
        : request.title;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${match.count}/${match.total}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
                children: [
                  TextSpan(
                    text: place,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate800,
                    ),
                  ),
                  if (match.hasMatch)
                    TextSpan(text: ' · has ${match.matched.join(', ')}'),
                  if (match.missing.isNotEmpty)
                    TextSpan(
                      text: ' · lacks ${match.missing.join(', ')}',
                      style: const TextStyle(color: AppTheme.slate400),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, List<Office> offices, bool screened) {
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    Widget assess({required bool primary}) {
      // Only an interview not held yet is "conducted"; a decided
      // application's form is reviewed, saved assessment or not.
      final label = app.status == Application.forScreening && !screened
          ? 'Conduct Interview & Assessment'
          : 'Review / Edit Assessment';
      final icon = const Icon(Icons.person_search_outlined, size: 14);
      void open() => widget.onAssess?.call(app);
      return primary
          ? ElevatedButton.icon(
              onPressed: open,
              icon: icon,
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.maroon,
                foregroundColor: Colors.white,
                padding: padding,
                elevation: 0,
              ),
            )
          : OutlinedButton.icon(
              onPressed: open,
              icon: icon,
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.maroon,
                side: const BorderSide(color: AppTheme.maroon200),
                padding: padding,
              ),
            );
    }

    final reject = OutlinedButton.icon(
      onPressed: _deciding != null ? null : () => _reject(context),
      icon: _decisionIcon('reject', Icons.block_rounded, AppTheme.red500),
      label: Text(_deciding == 'reject' ? 'Rejecting...' : 'Reject'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.red500,
        side: const BorderSide(color: AppTheme.red500),
        padding: padding,
      ),
    );
    Widget buttons(List<Widget> children) => Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: children,
    );

    switch (app.status) {
      case Application.pending:
        return buttons([
          reject,
          ElevatedButton.icon(
            onPressed: _deciding != null ? null : _sendToScreening,
            icon: _decisionIcon(
              'screen',
              Icons.how_to_reg_outlined,
              Colors.white,
            ),
            label: Text(
              _deciding == 'screen' ? 'Sending...' : 'Send to Screening',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.violet500,
              foregroundColor: Colors.white,
              padding: padding,
              elevation: 0,
            ),
          ),
        ]);
      case Application.forScreening:
        return buttons([
          reject,
          OutlinedButton.icon(
            onPressed: _deciding != null ? null : _backToPending,
            icon: _decisionIcon(
              'unscreen',
              Icons.undo_rounded,
              AppTheme.slate600,
            ),
            label: Text(
              _deciding == 'unscreen' ? 'Moving...' : 'Back to Pending',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.slate600,
              side: const BorderSide(color: AppTheme.slate300),
              padding: padding,
            ),
          ),
          assess(primary: true),
        ]);
      case Application.waitlisted:
        return buttons([
          assess(primary: false),
          ElevatedButton.icon(
            onPressed: _deciding != null
                ? null
                : () => _approveApplication(context, offices),
            icon: _decisionIcon(
              'approve',
              Icons.how_to_reg_outlined,
              Colors.white,
            ),
            label: Text(
              _deciding == 'approve' ? 'Approving...' : 'Approve Anyway',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emerald500,
              foregroundColor: Colors.white,
              // Stays green, slightly faded, while approving instead of
              // turning grey like a dead button.
              disabledBackgroundColor: _deciding == 'approve'
                  ? AppTheme.emerald500.withValues(alpha: 0.75)
                  : null,
              disabledForegroundColor: _deciding == 'approve'
                  ? Colors.white
                  : null,
              padding: padding,
              elevation: 0,
            ),
          ),
        ]);
    }
    if (!app.isApproved) return const SizedBox.shrink();
    // The contract and endorsement letter name the office and its
    // supervisor, so they wait for the placement.
    if (offices.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.amber50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.amber500.withValues(alpha: 0.4),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                const Text(
                  'Not in an office yet. Place them from Offices, then '
                  'generate their Contract of Appointment and Endorsement '
                  'Letter here.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate700,
                    height: 1.45,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => state.setTab('offices'),
                  icon: const Icon(Icons.account_balance_outlined, size: 14),
                  label: const Text('Open Offices'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.maroon,
                    side: const BorderSide(color: AppTheme.maroon200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          buttons([assess(primary: false)]),
        ],
      );
    }
    return buttons([
      assess(primary: false),
      OutlinedButton.icon(
        onPressed: generatingContract
            ? null
            : () => _generate(
                'Contract of Appointment',
                () => state.generateContractOfAppointmentDocument(app.id),
                (busy) => generatingContract = busy,
              ),
        icon: generatingContract
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppTheme.maroon),
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
          padding: padding,
        ),
      ),
      ElevatedButton.icon(
        onPressed: generatingEndorsement
            ? null
            : () => _generate(
                'Endorsement Letter',
                () => state.generateEndorsementLetterDocument(app.id),
                (busy) => generatingEndorsement = busy,
              ),
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
          padding: padding,
          elevation: 0,
        ),
      ),
    ]);
  }

  /// Rejects the application with a reason the student sees, so they can
  /// fix it (a wrong document, usually) and apply again.
  Future<void> _reject(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(application: app),
    );
    if (reason == null || !mounted) return;
    await _decide(
      'reject',
      () => state.updateApplicationStatus(
        app.id,
        Application.rejected,
        remarks: reason,
      ),
      success:
          "${app.applicantName}'s application was rejected. They were told "
          'why and can apply again.',
      color: AppTheme.red500,
    );
  }

  /// Generates [requirementName] with [run] while [setBusy] shows it
  /// working, after asking before replacing a copy already on file.
  Future<void> _generate(
    String requirementName,
    Future<void> Function() run,
    void Function(bool) setBusy,
  ) async {
    final messenger = ScaffoldMessenger.of(ctx);
    if (!await _confirmReplace(requirementName)) return;
    setState(() => setBusy(true));
    try {
      await run();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$requirementName generated.'),
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
          content: Text('Unable to generate: $e'),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => setBusy(false));
    }
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

  Future<void> _sendToScreening() async {
    await _decide(
      'screen',
      () async {
        if (await state.sendToScreening([app.id]) == 0) {
          throw StateError('it was not saved');
        }
      },
      success: '${app.applicantName} was sent to screening',
      color: AppTheme.violet500,
    );
  }

  Future<void> _backToPending() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Take them off the screening list?',
      message:
          "${app.applicantName}'s application goes back to Pending. They "
          'were already told they were selected for screening.',
      confirmLabel: 'Back to Pending',
      confirmColor: AppTheme.slate600,
    );
    if (!confirmed || !mounted) return;
    await _decide(
      'unscreen',
      () => state.updateApplicationStatus(app.id, Application.pending),
      success: "${app.applicantName}'s application is Pending again",
      color: AppTheme.slate600,
    );
  }

  Future<void> _approveApplication(
    BuildContext context,
    List<Office> offices,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve application?',
      message: offices.isEmpty
          ? '${app.applicantName} will become a Student Assistant and get an '
                'SA ID, with no office yet: place them from Offices, then '
                'generate their Contract of Appointment and Endorsement '
                'Letter here. They will be notified.'
          : '${app.applicantName} will become a Student Assistant and get an '
                'SA ID, and their Contract of Appointment and Endorsement '
                'Letter will be generated. They will be notified.',
      confirmLabel: 'Approve',
      confirmColor: AppTheme.emerald500,
    );
    if (!confirmed || !mounted) return;
    await _decide(
      'approve',
      () => state.updateApplicationStatus(
        app.id,
        Application.approved,
        remarks:
            'Approved from the waitlist by ${state.currentUser?.name ?? 'the Head'}.',
      ),
      success: "${app.applicantName}'s application approved",
      color: AppTheme.emerald500,
    );
  }

  /// Saves a change while its button shows a spinner, and only then says
  /// how it went.
  Future<void> _decide(
    String action,
    Future<void> Function() save, {
    required String success,
    required Color color,
  }) async {
    final messenger = ScaffoldMessenger.of(ctx);
    setState(() => _deciding = action);
    try {
      await save();
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
}

/// Which hiring call students apply through, or why they can't apply, so
/// the Head knows whether applications can come in.
class _HiringCallStrip extends StatelessWidget {
  final AppState state;
  const _HiringCallStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final call = state.currentHiringCall;
    final open = state.hiringCallTakesApplications(call);
    final message = call == null
        ? "No hiring call yet, so students can't apply. Post one from "
              'Announcements with "Open Student Assistant applications" on.'
        : !state.allowAcademicApplications
        ? "Applications are closed for this academic year in the Admin's "
              'settings.'
        : call.isPastDeadline()
        ? '"${call.title}" closed on ${call.deadline}. Post a new hiring '
              'call to take more applications.'
        : !call.isOpen
        ? '"${call.title}" is closed. Re-open it or post a new one to take '
              'applications.'
        : 'Students apply through "${call.title}"'
              '${call.deadline == null ? '' : ' until ${call.deadline}'}.';
    final color = open ? AppTheme.emerald500 : AppTheme.amber500;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            open ? Icons.campaign_rounded : Icons.campaign_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.slate700,
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: () => state.setTab('announcements_admin'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.maroon,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Announcements'),
          ),
        ],
      ),
    );
  }
}

/// Asks why an application is rejected. The reason is required: the
/// student sees it and fixes that (a wrong or unreadable document, most
/// often) before applying again. Tapping a submitted document names it.
class _RejectDialog extends StatefulWidget {
  final Application application;
  const _RejectDialog({required this.application});

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  static const _quickReasons = [
    'A wrong document was uploaded',
    "A file can't be opened or read",
    'A requirement is incomplete',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _add(String text) {
    final current = _reason.text.trim();
    setState(() {
      _reason.text = current.isEmpty ? text : '$current. $text';
      _reason.selection = TextSelection.collapsed(offset: _reason.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.application;
    final documents = {
      for (final doc in app.submittedDocuments)
        RequirementSpec.parse(doc.requirementName).label,
    };
    final reason = _reason.text.trim();
    Widget chip(String label, String text) => ActionChip(
      label: Text(label),
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 11.5,
        color: AppTheme.slate700,
      ),
      backgroundColor: AppTheme.slate100,
      side: const BorderSide(color: AppTheme.slate200),
      onPressed: () => _add(text),
    );
    return AlertDialog(
      title: const Text('Reject application?'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${app.applicantName} will be told why and can apply again '
                'with the right documents while applications are open.',
                style: const TextStyle(fontSize: 13, color: AppTheme.slate600),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final text in _quickReasons) chip(text, text),
                  for (final label in documents)
                    chip('Wrong file: $label', 'Wrong file for "$label"'),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                autofocus: true,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Reason (the student sees this)',
                  hintText: 'e.g. Wrong file for "Certificate of Registration"',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.pop(context, reason),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.red500,
            foregroundColor: Colors.white,
          ),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
