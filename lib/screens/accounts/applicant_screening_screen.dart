import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/screening_document_service.dart';
import 'dart:html' if (dart.library.html) 'dart:html' as html;

({String program, String yearLevel, String officeId, String officeName})
    resolveApplicantScreeningDefaults({
  User? user,
  Application? application,
  required List<Office> offices,
}) {
  final normalizedName = (user?.name ?? '').trim().toLowerCase();
  final assignedOffice = offices.where((office) {
    if (!office.isActive) return false;
    return office.assistantIds.contains(user?.id ?? '') ||
        office.headIds.contains(user?.id ?? '') ||
        office.headNames.any(
          (name) => name.trim().toLowerCase() == normalizedName,
        ) ||
        office.assistantNames.any(
          (name) => name.trim().toLowerCase() == normalizedName,
        );
  }).toList();

  final programValue = (user?.courseProgram ?? '').trim();
  final fallbackProgram = (application?.announcementTitle ?? '').trim();
  final yearLevelValue = (user?.yearLevel ?? '').trim();
  final defaultOffice = offices.isEmpty ? null : offices.first;
  final selectedOffice =
      assignedOffice.isNotEmpty ? assignedOffice.first : defaultOffice;

  return (
    program: programValue.isNotEmpty
        ? programValue
        : (fallbackProgram.isNotEmpty ? fallbackProgram : ''),
    yearLevel: yearLevelValue.isNotEmpty ? yearLevelValue : '1st Year',
    officeId: selectedOffice?.id ?? '',
    officeName: selectedOffice?.name ?? '',
  );
}

class ApplicantScreeningScreen extends StatefulWidget {
  const ApplicantScreeningScreen({super.key});
  @override
  State<ApplicantScreeningScreen> createState() =>
      _ApplicantScreeningScreenState();
}

class _ApplicantScreeningScreenState extends State<ApplicantScreeningScreen> {
  static const skillNames = [
    'Communication Skills',
    'Time Management',
    'Technical Proficiency',
    'Initiative & Problem-Solving',
    'Professionalism & Work Ethic',
    'Adaptability & Learning Ability',
    'Teamwork & Collaboration',
  ];
  static const overallNames = [
    'Suitability for the Role',
    'Enthusiasm & Motivation',
    'Potential for Growth',
    'Overall Impression',
  ];
  final search = TextEditingController();
  final name = TextEditingController();
  final studentNumber = TextEditingController();
  final program = TextEditingController();
  final address = TextEditingController();
  final contact = TextEditingController();
  final interviewer = TextEditingController();
  final remarks = TextEditingController();
  final yearLevel = TextEditingController();
  final ratings = <String, int>{};
  final notes = <String, String>{};
  String view = 'queue';
  String roleFilter = 'All';
  String screenedFilter = 'All';
  String statusFilter = 'All';
  String recommendation = 'Recommended';
  String targetOfficeId = '';
  String targetOfficeName = '';
  Application? activeApplication;
  ScreeningRecord? activeRecord;
  bool generatingResult = false;

  @override
  void initState() {
    super.initState();
    for (final key in [...skillNames, ...overallNames]) {
      ratings[key] = 4;
      notes[key] = '';
    }
  }

  @override
  void dispose() {
    for (final controller in [
      search,
      name,
      studentNumber,
      program,
      address,
      contact,
      interviewer,
      remarks,
      yearLevel,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final screenedApplicationIds = state.screeningRecords
        .map((record) => record.applicationId)
        .toSet();

    final applications = state.applications.where((application) {
      final value =
          '${application.applicantName} ${application.announcementTitle}'
              .toLowerCase();
      if (!value.contains(search.text.toLowerCase())) return false;

      if (roleFilter != 'All') {
        final applicantUser = _user(state, application);
        final role = (applicantUser?.role ?? 'Student').trim();
        if (roleFilter == 'Student Assistant' && role != 'Student Assistant') {
          return false;
        }
        if (roleFilter == 'Student' && role == 'Student Assistant') {
          return false;
        }
      }

      if (screenedFilter != 'All') {
        final isScreened = screenedApplicationIds.contains(application.id);
        if (screenedFilter == 'Screened' && !isScreened) return false;
        if (screenedFilter == 'Not Screened' && isScreened) return false;
      }

      if (statusFilter != 'All' && application.status != statusFilter) {
        return false;
      }

      return true;
    }).toList();

    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    return Container(
      color: AppTheme.slate50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(state),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 30),
              child: view == 'form'
                  ? _form(state)
                  : view == 'print'
                  ? _print()
                  : view == 'records'
                  ? _records(state.screeningRecords)
                  : _queue(state, applications, screenedApplicationIds),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppState state) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    final badge = Container(
      width: isMobile ? 40.0 : 46.0,
      height: isMobile ? 40.0 : 46.0,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroon, AppTheme.maroonDark],
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: AppTheme.maroon.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.fact_check_outlined,
        color: Colors.white,
        size: isMobile ? 19 : 22,
      ),
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student Applicant Screening & Assessment',
          style: TextStyle(
            fontSize: isMobile ? 15.5 : 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.slate900,
            letterSpacing: -0.2,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          isMobile
              ? 'Office of the VP for Student Affairs & Services'
              : 'Office of the Vice President for Student Affairs & Services · Official MSU Form',
          style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
        ),
      ],
    );

    final newButton = FilledButton.icon(
      onPressed: _newForm,
      icon: const Icon(Icons.add, size: 18),
      label: Text(isMobile ? 'New Screening' : 'New Applicant Screening'),
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(AppTheme.maroon),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: isMobile ? 13 : 14),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        elevation: const WidgetStatePropertyAll(0),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: isMobile ? 13 : 14, fontWeight: FontWeight.w700),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(hPad, isMobile ? 18 : 24, hPad, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.slate200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                badge,
                const SizedBox(width: 12),
                Expanded(child: titleBlock),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: newButton),
          ] else
            Row(
              children: [
                badge,
                const SizedBox(width: 14),
                Expanded(child: titleBlock),
                newButton,
              ],
            ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tab(
                  isMobile ? 'Queue' : 'Applying Students Queue',
                  'queue',
                  state.applications.length,
                  Icons.person_add_alt_1_outlined,
                ),
                const SizedBox(width: 8),
                _tab(
                  isMobile ? 'Records' : 'Screening Results & Records',
                  'records',
                  state.screeningRecords.length,
                  Icons.workspace_premium_outlined,
                ),
                const SizedBox(width: 8),
                _tab(
                  isMobile ? 'Evaluation Sheet' : 'Official Evaluation Sheet',
                  'form',
                  null,
                  Icons.description_outlined,
                ),
                if (activeRecord != null) ...[
                  const SizedBox(width: 8),
                  _tab(
                    isMobile ? 'Print Form' : 'Print Official Form',
                    'print',
                    null,
                    Icons.print_outlined,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, String value, int? count, IconData icon) {
    final active = view == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => view = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.maroon : AppTheme.slate50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppTheme.maroon : AppTheme.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : AppTheme.slate500,
            ),
            const SizedBox(width: 7),
            Text(
              count == null ? label : '$label ($count)',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppTheme.slate700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _queue(
    AppState state,
    List<Application> applications,
    Set<String> screenedApplicationIds,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _banner(
          applications
              .where((application) => application.status == 'Pending')
              .length,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText:
                      'Search by name, applicant number, program, or office...',
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.slate50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  _filterGroup(
                    'Applicant Type',
                    Icons.badge_outlined,
                    roleFilter,
                    const ['All', 'Student', 'Student Assistant'],
                    (value) => setState(() => roleFilter = value),
                  ),
                  _filterGroup(
                    'Screening Status',
                    Icons.rule_outlined,
                    screenedFilter,
                    const ['All', 'Screened', 'Not Screened'],
                    (value) => setState(() => screenedFilter = value),
                  ),
                  _filterGroup(
                    'Application Status',
                    Icons.flag_outlined,
                    statusFilter,
                    const ['All', 'Pending', 'Approved', 'Waitlisted', 'Rejected'],
                    (value) => setState(() => statusFilter = value),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _grid(
          applications.length,
          (index) => _applicationCard(
            state,
            applications[index],
            screenedApplicationIds.contains(applications[index].id),
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

  Widget _banner(int count) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final icon = Container(
      width: isMobile ? 36.0 : 42.0,
      height: isMobile ? 36.0 : 42.0,
      decoration: BoxDecoration(
        color: AppTheme.gold,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.gold.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        Icons.person_search_outlined,
        color: AppTheme.slate900,
        size: isMobile ? 18 : 24,
      ),
    );
    final text = const Text(
      'Student Applicant Pool (Candidates for SA Position)\nSelect a student below to conduct the official interview and competency assessment.',
      style: TextStyle(
        fontSize: 11.5,
        color: AppTheme.slate600,
        height: 1.4,
      ),
    );
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.maroon.withValues(alpha: 0.2)),
      ),
      child: Text(
        '$count Pending Interview',
        style: const TextStyle(
          color: AppTheme.maroon,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.gold50, Colors.white],
        ),
        border: Border.all(color: AppTheme.gold300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: 12),
                pill,
              ],
            )
          : Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(child: text),
                const SizedBox(width: 12),
                pill,
              ],
            ),
    );
  }

  Widget _records(List<ScreeningRecord> records) {
    final state = context.watch<AppState>();
    return _grid(records.length, (index) {
      return _recordCard(state, records[index]);
    });
  }

  Widget _recordCard(AppState state, ScreeningRecord record) {
    final score = _score(record);
    final recColor = _recommendationColor(record.recommendation);
    Application? linkedApplication;
    for (final application in state.applications) {
      if (application.id == record.applicationId) {
        linkedApplication = application;
        break;
      }
    }
    User? applicant;
    for (final user in state.users) {
      if (user.id == record.applicantId) {
        applicant = user;
        break;
      }
    }
    final isWaitlisted = linkedApplication?.status == 'Waitlisted';
    final initials = record.fullName.trim().isEmpty
        ? '?'
        : record.fullName
              .trim()
              .split(RegExp(r'\s+'))
              .map((part) => part.isNotEmpty ? part[0] : '')
              .take(2)
              .join()
              .toUpperCase();

    return _cardShell(
      tabLabel: linkedApplication?.status ?? record.recommendation,
      tabColor: linkedApplication != null
          ? _statusColor(linkedApplication.status)
          : recColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                avatarUrl: applicant?.avatar,
                initials: applicant?.initials ?? initials,
                size: 44,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.fullName,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${record.studentNumber} · ${record.academicProgram}',
                      style: const TextStyle(fontSize: 10.5, color: AppTheme.slate500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _scoreRing(score),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: recColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, size: 13, color: recColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    record.recommendation,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: recColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _recordMetaRow(
            Icons.apartment_outlined,
            record.targetOfficeName.isEmpty ? 'Unassigned Office' : record.targetOfficeName,
          ),
          const SizedBox(height: 6),
          _recordMetaRow(
            Icons.person_outline,
            record.interviewerName.isEmpty ? 'No interviewer' : 'By ${record.interviewerName}',
          ),
          const SizedBox(height: 6),
          _recordMetaRow(Icons.event_outlined, record.interviewerDate),
          if ((record.academicYear ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            _recordMetaRow(Icons.history_outlined, 'AY ${record.academicYear}'),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _outlineAction(
                  'Review Sheet',
                  Icons.visibility_outlined,
                  () => _loadRecord(record),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _downloadAction(record),
              ),
            ],
          ),
          if (isWaitlisted && linkedApplication != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _outlineAction(
                'Approve Anyway',
                Icons.how_to_reg_outlined,
                () => _approveWaitlisted(linkedApplication!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recordMetaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppTheme.slate400),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: AppTheme.slate600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _scoreRing(double score) {
    final pct = (score / 5.0).clamp(0.0, 1.0);
    final color = score >= 4
        ? AppTheme.emerald500
        : score >= 3
        ? AppTheme.amber500
        : AppTheme.red500;
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 4,
              backgroundColor: AppTheme.slate100,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const Text(
                '/5.0',
                style: TextStyle(fontSize: 7.5, color: AppTheme.slate400),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _recommendationColor(String recommendation) {
    switch (recommendation) {
      case 'Highly Recommended':
        return AppTheme.emerald500;
      case 'Recommended':
        return AppTheme.blue500;
      case 'Recommended with Reservations':
        return AppTheme.amber500;
      default:
        return AppTheme.red500;
    }
  }

  /// A folder-styled card shell: a small colored "tab" pokes out of the top
  /// of the card, like a manila folder, so the queue/records grid reads as
  /// a set of applicant folders rather than plain rectangles.
  Widget _cardShell({
    required Widget child,
    String? tabLabel,
    Color? tabColor,
  }) {
    final color = tabColor ?? AppTheme.slate300;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Folder tab
        Positioned(
          top: -20,
          left: 18,
          child: Container(
            height: 24,
            constraints: const BoxConstraints(minWidth: 70),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Text(
              (tabLabel ?? '').toUpperCase(),
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        // Folder body
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(2),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: AppTheme.slate200),
            boxShadow: [
              BoxShadow(
                color: AppTheme.slate900.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _grid(int count, Widget Function(int) item) {
    if (count == 0)
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 34, color: AppTheme.slate300),
              SizedBox(height: 10),
              Text(
                'No records found',
                style: TextStyle(color: AppTheme.slate500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        // FIX: a fixed-aspect-ratio GridView forced every card into the same
        // cell height, which squashed or overflowed cards whose content
        // varies (extra "Approve Anyway" button, more/fewer skill chips
        // wrapping). Building rows manually and stretching each card lets
        // every card size to the tallest one in its row instead.
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                item(i),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < count; i += columns) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
          final rowChildren = <Widget>[];
          for (var c = 0; c < columns; c++) {
            final index = i + c;
            if (c > 0) rowChildren.add(const SizedBox(width: 14));
            rowChildren.add(
              Expanded(child: index < count ? item(index) : const SizedBox()),
            );
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowChildren,
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  Widget _applicationCard(AppState state, Application app, bool isScreened) {
    User? user;
    for (final candidate in state.users) {
      if (candidate.id == app.applicantId) user = candidate;
    }
    final role = (user?.role ?? 'Student').trim();
    final isAssistant = role == 'Student Assistant';
    final isWaitlisted = app.status == 'Waitlisted';

    return _cardShell(
      tabLabel: app.status,
      tabColor: _statusColor(app.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'APP-${app.id}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.slate400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _statusBadge(app.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isAssistant ? AppTheme.gold400 : AppTheme.slate200,
                        width: 2,
                      ),
                    ),
                    child: UserAvatar(
                      avatarUrl: user?.avatar,
                      initials: user?.initials ?? '?',
                      size: 40,
                    ),
                  ),
                  if (isScreened)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          size: 15,
                          color: AppTheme.emerald500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.applicantName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _roleChip(role),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${user?.courseProgram ?? app.announcementTitle} · ${user?.yearLevel ?? 'Student'}',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.slate500),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.apartment_outlined, size: 12, color: AppTheme.maroon),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  user?.department ?? 'General Queue',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.maroon,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isScreened ? Icons.fact_check_outlined : Icons.hourglass_empty,
                size: 12,
                color: isScreened ? AppTheme.emerald500 : AppTheme.slate400,
              ),
              const SizedBox(width: 4),
              Text(
                isScreened ? 'Screened' : 'Not Screened',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isScreened ? AppTheme.emerald500 : AppTheme.slate400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 5, runSpacing: 5, children: app.skills.map(_badge).toList()),
          const SizedBox(height: 14),
          _action(
            app.status == 'Pending'
                ? 'Conduct Interview & Assessment'
                : 'Review / Edit Assessment',
            Icons.person_search_outlined,
            () => _start(app),
          ),
          if (isWaitlisted) ...[
            const SizedBox(height: 8),
            _outlineAction(
              'Approve Anyway',
              Icons.how_to_reg_outlined,
              () => _approveWaitlisted(app),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Approved':
        return AppTheme.emerald500;
      case 'Rejected':
        return AppTheme.red500;
      case 'Waitlisted':
        return AppTheme.amber500;
      default:
        return AppTheme.slate400;
    }
  }

  /// Lets an admin override a "Waitlisted" decision and approve the
  /// applicant directly from the queue, without re-running the whole
  /// screening form.
  Future<void> _approveWaitlisted(Application app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve waitlisted applicant?'),
        content: Text(
          '${app.applicantName} is currently waitlisted. Approving will move '
          'them to "Approved" and notify the applicant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(AppTheme.maroon),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final state = context.read<AppState>();
    await state.updateApplicationStatus(
      app.id,
      'Approved',
      remarks: 'Approved from waitlist by ${state.currentUser?.name ?? 'admin'}.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${app.applicantName} has been approved.'),
        backgroundColor: AppTheme.blue500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
    );
    setState(() {});
  }

  Widget _roleChip(String role) {
    final isAssistant = role == 'Student Assistant';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isAssistant ? AppTheme.gold100 : AppTheme.blue50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: isAssistant ? const Color(0xFF8A6D00) : AppTheme.blue500,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    switch (status) {
      case 'Approved':
        color = AppTheme.emerald500;
        break;
      case 'Rejected':
        color = AppTheme.red500;
        break;
      case 'Waitlisted':
        color = AppTheme.amber500;
        break;
      default:
        color = AppTheme.slate400;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.maroon50,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        color: AppTheme.maroon,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
  Widget _action(String label, IconData icon, VoidCallback action) =>
      FilledButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 13),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(AppTheme.maroon),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  Widget _downloadAction(ScreeningRecord record) => ElevatedButton.icon(
    onPressed: generatingResult ? null : () => _downloadResult(record),
    icon: generatingResult
        ? const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
        : const Icon(Icons.download_outlined, size: 13),
    label: Text(
      generatingResult ? 'Downloading...' : 'Download',
      overflow: TextOverflow.ellipsis,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _outlineAction(String label, IconData icon, VoidCallback action) =>
      OutlinedButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 13),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppTheme.maroon),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppTheme.maroon200),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
Widget _form(AppState state) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _officialHeader(_applicantAvatarForPrint()),
      const SizedBox(height: 18),
      _progressSummaryBar(),
      const SizedBox(height: 18),
      _section(
        1,
        Icons.badge_outlined,
        'Candidate Information',
        _candidateFields(state),
      ),
      const SizedBox(height: 18),
      _section(
        2,
        Icons.psychology_outlined,
        'Skills & Competency Assessment',
        _ratingSection(skillNames, skillsAvg),
        trailing: _sectionAvgChip(skillsAvg),
      ),
      const SizedBox(height: 18),
      _section(
        3,
        Icons.emoji_events_outlined,
        'Overall Evaluation',
        _ratingSection(overallNames, overallAvg),
        trailing: _sectionAvgChip(overallAvg),
      ),
      const SizedBox(height: 18),
      _recommendationSection(),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.slate200),
          boxShadow: [
            BoxShadow(
              color: AppTheme.slate900.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 16, color: AppTheme.maroon),
                const SizedBox(width: 8),
                const Text(
                  '5. SIGN-OFF',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: AppTheme.slate900,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            isMobile
                ? Column(
                    children: [
                      _input('Interviewer Signature & Name', interviewer),
                      const SizedBox(height: 12),
                      TextField(
                        readOnly: true,
                        controller: TextEditingController(text: _today()),
                        decoration: InputDecoration(
                          labelText: 'Interview Date',
                          isDense: true,
                          filled: true,
                          fillColor: AppTheme.slate50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
              children: [
                Expanded(
                  child: _input('Interviewer Signature & Name', interviewer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    readOnly: true,
                    controller: TextEditingController(text: _today()),
                    decoration: InputDecoration(
                      labelText: 'Interview Date',
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.slate50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      isMobile
          ? Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: _action('Save Assessment Record', Icons.check, _save),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _outlineAction(
                    'Preview Print Sheet',
                    Icons.print_outlined,
                    () => setState(() => view = 'print'),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => setState(() => view = 'queue'),
                  child: const Text('Back to Applicants'),
                ),
              ],
            )
          : Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => setState(() => view = 'queue'),
            child: const Text('Back to Applicants'),
          ),
          const SizedBox(width: 4),
          _outlineAction(
            'Preview Print Sheet',
            Icons.print_outlined,
            () => setState(() => view = 'print'),
          ),
          const SizedBox(width: 8),
          _action('Save Assessment Record', Icons.check, _save),
        ],
      ),
    ],
  );
  }

  double get skillsAvg {
    final values = skillNames.map((key) => ratings[key] ?? 0).toList();
    return values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  }

  double get overallAvg {
    final values = overallNames.map((key) => ratings[key] ?? 0).toList();
    return values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  }

  double get combinedAvg {
    final values = [
      ...skillNames.map((key) => ratings[key] ?? 0),
      ...overallNames.map((key) => ratings[key] ?? 0),
    ];
    return values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  }

  Color _scoreColor(double score) => score >= 4
      ? AppTheme.emerald500
      : score >= 3
      ? AppTheme.amber500
      : AppTheme.red500;

  Widget _sectionAvgChip(double avg) {
    final color = _scoreColor(avg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Avg ${avg.toStringAsFixed(1)}',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _progressSummaryBar() {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final ring = SizedBox(
      width: isMobile ? 44 : 50,
      height: isMobile ? 44 : 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: isMobile ? 44 : 50,
            height: isMobile ? 44 : 50,
            child: CircularProgressIndicator(
              value: (combinedAvg / 5.0).clamp(0.0, 1.0),
              strokeWidth: 4.5,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          Text(
            combinedAvg.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Live Assessment Score',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${name.text.isEmpty ? 'Candidate' : name.text} · updates as you rate each criterion',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 11,
          ),
          maxLines: isMobile ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final pills = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _summaryPill('Skills', skillsAvg),
        const SizedBox(width: 8),
        _summaryPill('Overall', overallAvg),
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 14 : 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroon, AppTheme.maroonDark],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.maroon.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // FIX: the score ring, candidate name, and both pills used to sit in
      // one Row — on mobile the pills got squeezed against the name text.
      // Stack the pills onto their own row below on mobile.
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ring,
                    const SizedBox(width: 12),
                    Expanded(child: label),
                  ],
                ),
                const SizedBox(height: 12),
                pills,
              ],
            )
          : Row(
              children: [
                ring,
                const SizedBox(width: 16),
                Expanded(child: label),
                pills,
              ],
            ),
    );
  }

  Widget _summaryPill(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves the profile photo (if any) for whichever applicant is
  /// currently loaded into the screening form, so the printable/official
  /// form can show their real 2x2 photo instead of a placeholder.
  String? _applicantAvatarForPrint() {
    final state = context.read<AppState>();
    final applicantId =
        activeApplication?.applicantId ?? activeRecord?.applicantId;
    if (applicantId == null || applicantId.isEmpty) return null;
    for (final user in state.users) {
      if (user.id == applicantId) return user.avatar;
    }
    return null;
  }

  /// Renders the applicant's real profile photo in the 2x2 photo box on the
  /// official form. Mirrors UserAvatar's data-URL/network handling but stays
  /// square (no circular clip) to match a passport-style 2x2 photo slot.
  Widget _printAvatarImage(String avatarUrl) {
    if (avatarUrl.startsWith('data:image')) {
      try {
        final prefixEnd = avatarUrl.indexOf(',');
        if (prefixEnd < 0) return _printPhotoPlaceholder();
        final payload = avatarUrl
            .substring(prefixEnd + 1)
            .replaceAll(RegExp(r'\s+'), '');
        if (payload.isEmpty) return _printPhotoPlaceholder();
        final bytes = base64Decode(payload);
        if (bytes.isEmpty) return _printPhotoPlaceholder();
        return Image.memory(
          bytes,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _printPhotoPlaceholder(),
        );
      } catch (_) {
        return _printPhotoPlaceholder();
      }
    }
    return Image.network(
      avatarUrl,
      width: 90,
      height: 90,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _printPhotoPlaceholder(),
    );
  }

  Widget _printPhotoPlaceholder() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_outlined, size: 18, color: AppTheme.slate300),
        const SizedBox(height: 4),
        Text('2x2 PHOTO', style: TextStyle(fontSize: 9, color: AppTheme.slate400)),
      ],
    ),
  );

  Widget _officialHeader([String? applicantAvatarUrl]) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    final photoBox = Container(
      width: isMobile ? 70 : 90,
      height: isMobile ? 70 : 90,
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200, style: BorderStyle.solid),
      ),
      clipBehavior: Clip.antiAlias,
      child: applicantAvatarUrl != null && applicantAvatarUrl.isNotEmpty
          ? _printAvatarImage(applicantAvatarUrl)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 18,
                    color: AppTheme.slate300,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '2x2 PHOTO',
                    style: TextStyle(fontSize: 9, color: AppTheme.slate400),
                  ),
                ],
              ),
            ),
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REPUBLIC OF THE PHILIPPINES',
          style: TextStyle(
            fontSize: isMobile ? 9 : 10,
            color: AppTheme.slate500,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          'MARINDUQUE STATE UNIVERSITY',
          style: TextStyle(
            fontSize: isMobile ? 14.5 : 18,
            fontWeight: FontWeight.w900,
            color: AppTheme.slate900,
            letterSpacing: -0.3,
          ),
        ),
        Text(
          isMobile
              ? 'OFFICE OF THE VP FOR STUDENT AFFAIRS & SERVICES'
              : 'OFFICE OF THE VICE PRESIDENT FOR STUDENT AFFAIRS & SERVICES',
          style: TextStyle(
            fontSize: isMobile ? 9.5 : 10.5,
            color: AppTheme.maroon,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        if (!isMobile)
          const Text(
            'Student Auxiliary & Employment Extension Division (SAEED)',
            style: TextStyle(fontSize: 10, color: AppTheme.slate500),
          ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // FIX: logo + long agency title + 90px photo box used to sit in
          // one fixed Row, leaving almost no width for the title text on a
          // phone. On mobile the logo+title pair sits on its own row and
          // the photo moves below, full-width-aligned.
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppLogo(size: 44),
                const SizedBox(width: 10),
                Expanded(child: titleBlock),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [photoBox],
            ),
          ] else
            Row(
              children: [
                const AppLogo(size: 60),
                const SizedBox(width: 14),
                Expanded(child: titleBlock),
                photoBox,
              ],
            ),
          SizedBox(height: isMobile ? 14 : 18),
          Container(height: 1, color: AppTheme.slate200),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.maroon50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'INTERVIEW AND ASSESSMENT FORM FOR STUDENT ASSISTANTS',
              style: TextStyle(
                fontSize: isMobile ? 11.5 : 13.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.maroon,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _section(
    int number,
    IconData icon,
    String title,
    Widget child, {
    Widget? trailing,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Container(
    padding: EdgeInsets.all(isMobile ? 14 : 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.slate200),
      boxShadow: [
        BoxShadow(
          color: AppTheme.slate900.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppTheme.maroon,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 16, color: AppTheme.maroon),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
  }
  Widget _candidateFields(AppState state) {
    final wide = MediaQuery.of(context).size.width > 700;
    final fields = <Widget>[
      _input('Full Name', name),
      _input('Student ID / Applicant #', studentNumber),
      _input('Academic Program', program),
      _input('Permanent / Present Address', address),
      _input('Contact Information', contact),
      _input('Year Level', yearLevel),
      DropdownButtonFormField<String>(
        initialValue: targetOfficeId.isEmpty ? null : targetOfficeId,
        decoration: InputDecoration(
          labelText: 'Recommended / Applying for Office',
          isDense: true,
          filled: true,
          fillColor: AppTheme.slate50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        items: state.offices
            .map(
              (office) =>
                  DropdownMenuItem(value: office.id, child: Text(office.name)),
            )
            .toList(),
        onChanged: (value) {
          final office = state.offices
              .where((office) => office.id == value)
              .toList();
          setState(() {
            targetOfficeId = value ?? '';
            targetOfficeName = office.isEmpty ? '' : office.first.name;
          });
        },
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = wide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: fields.map((field) => SizedBox(width: width, child: field)).toList(),
        );
      },
    );
  }
  Widget _input(String label, TextEditingController controller) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: AppTheme.slate50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),
  );
  Widget _ratingSection(List<String> items, double avg) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              const Text(
                '1 = Needs Improvement    ·    5 = Excellent',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.slate400,
                  fontStyle: FontStyle.italic,
                ),
              ),
              _sectionAvgChip(avg),
            ],
          ),
        ),
        ...items.map((item) {
          final ratingButtons = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var value = 1; value <= 5; value++)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => ratings[item] = value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: ratings[item] == value
                          ? AppTheme.maroon
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ratings[item] == value
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$value',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: ratings[item] == value
                              ? Colors.white
                              : AppTheme.slate600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
          final noteField = TextField(
            onChanged: (value) => notes[item] = value,
            decoration: InputDecoration(
              hintText: 'Observation...',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.slate200),
              ),
            ),
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: isMobile
                // FIX: cramming the label, 5 rating buttons, and a text
                // field into one Row left ~30px per element on a phone.
                // Stack them instead so each piece gets full width.
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ratingButtons,
                      const SizedBox(height: 10),
                      noteField,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate800,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.center,
                          child: ratingButtons,
                        ),
                      ),
                      Expanded(flex: 4, child: noteField),
                    ],
                  ),
          );
        }),
      ],
    );
  }

  Widget _recommendationSection() {
    const options = [
      ('Highly Recommended', Icons.thumb_up_alt_rounded, 'Outstanding fit for the role'),
      ('Recommended', Icons.check_circle_outline, 'Solid, qualified candidate'),
      ('Recommended with Reservations', Icons.info_outline, 'Some concerns to note'),
      ('Not Recommended', Icons.cancel_outlined, 'Does not meet requirements'),
    ];
    return _section(
      4,
      Icons.fact_check_outlined,
      'Final Recommendation',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 640 ? 2 : 1;
              final width = columns == 2
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: options.map((option) {
                  final label = option.$1;
                  final icon = option.$2;
                  final desc = option.$3;
                  final selected = recommendation == label;
                  final color = _recommendationColor(label);
                  return SizedBox(
                    width: width,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => recommendation = label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withValues(alpha: 0.1)
                              : AppTheme.slate50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? color : AppTheme.slate200,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: selected ? color : AppTheme.slate400,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: selected
                                          ? color
                                          : AppTheme.slate700,
                                    ),
                                  ),
                                  Text(
                                    desc,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.slate500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Icon(Icons.check_circle, size: 18, color: color),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: remarks,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'General evaluator remarks',
              filled: true,
              fillColor: AppTheme.slate50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _print() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _officialHeader(_applicantAvatarForPrint()),
      const SizedBox(height: 16),
      _printSection(
        Icons.badge_outlined,
        'Candidate Information',
        [
          ('Full Name', name.text),
          ('Student ID / Applicant #', studentNumber.text),
          ('Academic Program', program.text),
          ('Year Level', yearLevel.text.isEmpty ? '1st Year' : yearLevel.text),
          ('Contact Information', contact.text),
        ],
      ),
      const SizedBox(height: 16),
      _printRatingSection('Skills & Competency Assessment', Icons.psychology_outlined, skillNames),
      const SizedBox(height: 16),
      _printRatingSection('Overall Evaluation', Icons.emoji_events_outlined, overallNames),
      const SizedBox(height: 16),
      _printRecommendationCard(),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _outlineAction(
            'Back',
            Icons.arrow_back,
            () => setState(() => view = 'form'),
          ),
          const SizedBox(width: 8),
          _action(
            'Print Document',
            Icons.print,
            () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Use the device print command to print this sheet.',
                ),
        backgroundColor: AppTheme.blue500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
            ),
          ),
          if (activeRecord != null) ...[
            const SizedBox(width: 8),
            _action(
              generatingResult ? 'Generating...' : 'Generate & Download Result',
              Icons.download_outlined,
              generatingResult ? () {} : () => _downloadResult(activeRecord!),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _printCardShell({required IconData icon, required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.maroon50,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: AppTheme.maroon),
              ),
              const SizedBox(width: 10),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _printSection(IconData icon, String title, List<(String, String)> fields) {
    return _printCardShell(
      icon: icon,
      title: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 640 ? 2 : 1;
          return Wrap(
            spacing: 20,
            runSpacing: 14,
            children: fields.map((field) {
              final width = columns == 2
                  ? (constraints.maxWidth - 20) / 2
                  : constraints.maxWidth;
              return SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.$1.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate400,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      field.$2.isEmpty ? 'N/A' : field.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: field.$2.isEmpty
                            ? AppTheme.slate300
                            : AppTheme.slate800,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _printRatingSection(String title, IconData icon, List<String> items) {
    return _printCardShell(
      icon: icon,
      title: title,
      child: Column(
        children: items.map((item) {
          final value = ratings[item] ?? 0;
          final note = notes[item] ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          note,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppTheme.slate500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.maroon,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$value / 5',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _printRecommendationCard() {
    Color badgeColor;
    switch (recommendation) {
      case 'Highly Recommended':
        badgeColor = AppTheme.emerald500;
        break;
      case 'Recommended':
        badgeColor = AppTheme.blue500;
        break;
      case 'Recommended with Reservations':
        badgeColor = AppTheme.amber500;
        break;
      default:
        badgeColor = AppTheme.red500;
    }
    return _printCardShell(
      icon: Icons.fact_check_outlined,
      title: 'Final Recommendation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              recommendation,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: badgeColor,
              ),
            ),
          ),
          if (remarks.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              remarks.text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.slate700,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _newForm() {
    activeApplication = null;
    activeRecord = null;
    name.clear();
    studentNumber.clear();
    program.clear();
    address.clear();
    contact.clear();
    remarks.clear();
    final state = context.read<AppState>();
    
    // Find the current user's assigned office
    final normalizedName = (state.currentUser?.name ?? '').trim().toLowerCase();
    final assignedOffices = state.offices.where((office) {
      if (!office.isActive) return false;
      return office.assistantIds.contains(state.currentUser?.id ?? '') ||
          office.headIds.contains(state.currentUser?.id ?? '') ||
          office.headNames.any(
            (name) => name.trim().toLowerCase() == normalizedName,
          ) ||
          office.assistantNames.any(
            (name) => name.trim().toLowerCase() == normalizedName,
          );
    }).toList();
    
    final selectedOffice =
        assignedOffices.isNotEmpty ? assignedOffices.first : (state.offices.isEmpty ? null : state.offices.first);
    
    yearLevel.text = (state.currentUser?.yearLevel ?? '').trim().isEmpty ? '1st Year' : state.currentUser!.yearLevel!;
    interviewer.text = state.currentUser?.name ?? '';
    targetOfficeId = selectedOffice?.id ?? '';
    targetOfficeName = selectedOffice?.name ?? '';
    setState(() => view = 'form');
  }

  void _start(Application app) {
    final state = context.read<AppState>();
    _loadAndStartForm(state, app);
  }

  Future<void> _loadAndStartForm(AppState state, Application app) async {
    User? user = _user(state, app);
    
    // Load the fresh user profile from Firestore (not from stale state.users)
    if (user != null && user.id.isNotEmpty) {
      try {
        final freshUser = await state.getFreshUserProfile(user.id);
        if (freshUser != null) {
          user = freshUser;
        }
      } catch (_) {
        // If Firestore load fails, use the in-memory user
      }
    }
    
    if (!mounted) return;
    
    // Find the user's assigned office (assistant or head)
    final normalizedName = (user?.name ?? '').trim().toLowerCase();
    final assignedOffices = state.offices.where((office) {
      if (!office.isActive) return false;
      return office.assistantIds.contains(user?.id ?? '') ||
          office.headIds.contains(user?.id ?? '') ||
          office.headNames.any(
            (name) => name.trim().toLowerCase() == normalizedName,
          ) ||
          office.assistantNames.any(
            (name) => name.trim().toLowerCase() == normalizedName,
          );
    }).toList();
    
    final selectedOffice =
        assignedOffices.isNotEmpty ? assignedOffices.first : null;
    
    activeApplication = app;
    name.text = app.applicantName;
    studentNumber.text = user?.studentId ?? '';
    // Academic Program = Course/Program (not department)
    program.text = (user?.courseProgram ?? '').trim().isEmpty
        ? app.announcementTitle
        : user!.courseProgram!;
    address.text = user?.address ?? '';
    contact.text = '${user?.phone ?? ''} / ${user?.email ?? ''}';
    // Year Level = saved yearLevel from user profile
    yearLevel.text = (user?.yearLevel ?? '').trim().isEmpty ? '1st Year' : user!.yearLevel!;
    interviewer.text = state.currentUser?.name ?? '';
    // Office = user's assigned office, not first office
    targetOfficeId = selectedOffice?.id ?? '';
    targetOfficeName = selectedOffice?.name ?? '';
    setState(() => view = 'form');
  }

  void _loadRecord(ScreeningRecord record) {
    activeRecord = record;
    name.text = record.fullName;
    studentNumber.text = record.studentNumber;
    program.text = record.academicProgram;
    address.text = record.presentAddress;
    contact.text = record.contactInformation;
    yearLevel.text = record.yearLevel;
    interviewer.text = record.interviewerName;
    remarks.text = record.generalNotes;
    recommendation = record.recommendation;
    targetOfficeId = record.targetOfficeId;
    targetOfficeName = record.targetOfficeName;
    ratings.addAll(record.skills);
    ratings.addAll(record.overall);
    notes.addAll(record.skillNotes);
    notes.addAll(record.overallNotes);
    setState(() => view = 'form');
  }

  User? _user(AppState state, Application app) {
    for (final user in state.users) {
      if (user.id == app.applicantId) return user;
    }
    return null;
  }

  double _score(ScreeningRecord record) {
    final values = [...record.skills.values, ...record.overall.values];
    return values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  }

  /// Resolves the applicant's real 2x2 photo (if any) as raw bytes plus its
  /// file extension, so the generated Word document can embed it instead of
  /// the "Paste your 2x2" placeholder. Mirrors the data-URL/network handling
  /// used for the on-screen print preview.
  Future<({Uint8List bytes, String extension})?> _applicantPhotoForDownload(
    ScreeningRecord record,
  ) async {
    final state = context.read<AppState>();
    String? avatarUrl;
    for (final user in state.users) {
      if (user.id == record.applicantId) {
        avatarUrl = user.avatar;
        break;
      }
    }
    if (avatarUrl == null || avatarUrl.isEmpty) return null;

    if (avatarUrl.startsWith('data:image')) {
      try {
        final prefixEnd = avatarUrl.indexOf(',');
        if (prefixEnd < 0) return null;
        final header = avatarUrl.substring(0, prefixEnd);
        final payload = avatarUrl
            .substring(prefixEnd + 1)
            .replaceAll(RegExp(r'\s+'), '');
        if (payload.isEmpty) return null;
        final bytes = base64Decode(payload);
        if (bytes.isEmpty) return null;
        final mimeMatch = RegExp(r'data:image/([a-zA-Z0-9+.-]+)')
            .firstMatch(header);
        final extension = mimeMatch?.group(1) ?? 'jpeg';
        return (bytes: Uint8List.fromList(bytes), extension: extension);
      } catch (_) {
        return null;
      }
    }

    try {
      final request = await html.HttpRequest.request(
        avatarUrl,
        responseType: 'arraybuffer',
      );
      final buffer = request.response as ByteBuffer?;
      if (buffer == null) return null;
      final bytes = buffer.asUint8List();
      if (bytes.isEmpty) return null;
      final extension = _extensionFromUrl(avatarUrl);
      return (bytes: bytes, extension: extension);
    } catch (_) {
      return null;
    }
  }

  String _extensionFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpeg';
    return path.substring(dot + 1).toLowerCase();
  }

  Future<void> _downloadResult(ScreeningRecord record) async {
    if (generatingResult) return;
    setState(() => generatingResult = true);
    try {
      final photo = await _applicantPhotoForDownload(record);
      final document = await const ScreeningDocumentService()
          .generateScreeningResult(
            record: record,
            academicYear: context.read<AppState>().academicYear,
            photoBytes: photo?.bytes,
            photoExtension: photo?.extension,
          );
      final bytes = document.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('The generated document is empty.');
      }
      _triggerWebDownload(document.fileName, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloading ${document.fileName}...'),
        backgroundColor: AppTheme.blue500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to generate result: $error'),
        backgroundColor: AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
        );
      }
    } finally {
      if (mounted) setState(() => generatingResult = false);
    }
  }

  void _triggerWebDownload(String fileName, Uint8List bytes) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    // Saving also decides the application from the recommendation, and an
    // approval promotes the applicant and generates their documents.
    if (activeApplication != null) {
      final applicant = activeApplication!.applicantName;
      final (title, message, label, color) = switch (recommendation) {
        'Not Recommended' => (
          'Save and reject?',
          'With "Not Recommended", $applicant\'s application will be '
              'rejected and they will be notified.',
          'Save & Reject',
          AppTheme.red500,
        ),
        'Recommended with Reservations' => (
          'Save and waitlist?',
          'With "Recommended with Reservations", $applicant\'s application '
              'will be waitlisted and they will be notified.',
          'Save & Waitlist',
          AppTheme.amber500,
        ),
        _ => (
          'Save and approve?',
          'With "$recommendation", $applicant\'s application will be '
              'approved: they become a Student Assistant, get an SA ID, and '
              'their Contract of Appointment and Endorsement Letter are '
              'generated.',
          'Save & Approve',
          AppTheme.emerald500,
        ),
      };
      final confirmed = await showConfirmDialog(
        context,
        title: title,
        message: message,
        confirmLabel: label,
        confirmColor: color,
      );
      if (!confirmed || !mounted) return;
    }
    final recordYear = activeApplication?.academicYear ??
        activeRecord?.academicYear ??
        state.academicYear;
    final stableId = ScreeningRecord.stableIdForApplicant(
      applicantId: activeApplication?.applicantId ?? activeRecord?.applicantId ?? '',
      applicationId: activeApplication?.id ?? '',
      fallback: activeRecord?.id,
      academicYear: recordYear,
    );
    final record = ScreeningRecord(
      id: stableId,
      academicYear: recordYear,
      createdAt: DateTime.now().toIso8601String(),
      applicationId: activeApplication?.id ?? '',
      applicantId: activeApplication?.applicantId ?? '',
      fullName: name.text,
      studentNumber: studentNumber.text,
      academicProgram: program.text,
      yearLevel: yearLevel.text.isEmpty ? '1st Year' : yearLevel.text,
      permanentAddress: address.text,
      presentAddress: address.text,
      contactInformation: contact.text,
      targetOfficeId: targetOfficeId,
      targetOfficeName: targetOfficeName,
      skills: {for (final key in skillNames) key: ratings[key] ?? 0},
      skillNotes: {for (final key in skillNames) key: notes[key] ?? ''},
      overall: {for (final key in overallNames) key: ratings[key] ?? 0},
      overallNotes: {for (final key in overallNames) key: notes[key] ?? ''},
      recommendation: recommendation,
      interviewerName: interviewer.text,
      interviewerDate: _today(),
      notedByName: state.currentUser?.name ?? '',
      notedByTitle: 'Head of Student Assistantship',
      generalNotes: remarks.text,
    );
    await state.saveScreeningRecord(record);
    if (activeApplication != null) {
      final status = recommendation == 'Not Recommended'
          ? 'Rejected'
          : recommendation == 'Recommended with Reservations'
          ? 'Waitlisted'
          : 'Approved';
      await state.updateApplicationStatus(
        activeApplication!.id,
        status,
        remarks:
            'Screening score: ${_score(record).toStringAsFixed(1)}/5. ${remarks.text}',
      );
    }
    if (!mounted) return;
    activeRecord = record;
    setState(() => view = 'records');
  }

  String _today() {
    final date = DateTime.now();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
