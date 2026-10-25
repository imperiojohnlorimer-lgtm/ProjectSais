import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/announcement_widgets.dart';
import '../../widgets/shared_widgets.dart';
import 'post_announcement_dialog.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  // 'All', 'Hiring Calls', 'SA Requests', 'Office Memos', 'Open',
  // 'Closed', 'Pending'
  String filterStatus = 'All';
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    var anns = state.announcements;
    
    // Apply filter
    if (filterStatus == 'Open') {
      anns = anns.where((a) => a.isOpen).toList();
    } else if (filterStatus == 'Closed') {
      anns = anns.where((a) => !a.isOpen).toList();
    } else if (filterStatus == 'Pending') {
      anns = anns.where((a) => a.isPending).toList();
    } else if (filterStatus == 'Hiring Calls') {
      // The Head's calls students apply through.
      anns = anns.where((a) => a.isHiringCall).toList();
    } else if (filterStatus == 'SA Requests') {
      // Supervisors' requests for a student assistant.
      anns = anns.where((a) => a.isSupervisorRequest).toList();
    } else if (filterStatus == 'Office Memos') {
      anns = anns
          .where((a) => !a.isSupervisorRequest && !a.acceptsApplications)
          .toList();
    }
    
    // Apply search
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      anns = anns.where((a) => 
        a.title.toLowerCase().contains(query) ||
        a.body.toLowerCase().contains(query) ||
        a.requirements.any((r) => r.toLowerCase().contains(query))
      ).toList();
    }
    
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        // FIX: title + "Post Announcement" button used to sit in one Row
        // with a Spacer and a fixed 28px padding — on a narrow phone the
        // button had nowhere to go and got cut off (the hazard-stripe
        // overflow). Below the mobile breakpoint they stack instead.
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: isMobile
              ? Column(
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
                        // Wraps so the badge drops under the title on the
                        // narrowest phones instead of running off the edge.
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Announcements',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.emerald50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Mention Support Active',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.emerald500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create and manage hiring announcements, call for duties, and memos.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            showPostAnnouncementDialog(context),
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text(
                          'Post Announcement',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppTheme.maroon,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Announcements',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.emerald50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Mention Support Active',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.emerald500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Create and manage hiring announcements, call for duties, and memos.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () =>
                          showPostAnnouncementDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: const Text(
                        'Post Announcement',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'All'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'All' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'All'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'All Notices (${state.announcements.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'All'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'Hiring Calls'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'Hiring Calls' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'Hiring Calls'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'Hiring Calls',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'Hiring Calls'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'SA Requests'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'SA Requests' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'SA Requests'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'SA Requests',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'SA Requests'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'Office Memos'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'Office Memos' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'Office Memos'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'Office Memos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'Office Memos'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'Open'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'Open' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'Open'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'Active Open',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'Open'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Content ─────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (anns.isEmpty)
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
                            'No announcements posted yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Use "Post Announcement" to open Student Assistant applications or post a notice.',
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
                  ...anns.map(
                    (a) => _AdminAnnouncementCard(
                      ann: a,
                      state: state,
                      context: context,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _AdminAnnouncementCard extends StatelessWidget {
  final Announcement ann;
  final AppState state;
  final BuildContext context;
  const _AdminAnnouncementCard({
    required this.ann,
    required this.state,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) {
    // Nobody applies to a supervisor's request: count the applicants whose
    // skills match it instead.
    final appCount = ann.isSupervisorRequest
        ? state.applications
              .where(
                (a) =>
                    (a.academicYear == null ||
                        a.academicYear == state.academicYear) &&
                    SkillMatch.of(ann, state.applicantSkills(a)).hasMatch,
              )
              .length
        : state.applications.where((a) => a.announcementId == ann.id).length;
    final isMobile = MediaQuery.of(ctx).size.width < 700;

    final (statusLabel, statusColor, statusBackground) = ann.isPending
        ? (
            'Pending Approval',
            AppTheme.amber500,
            AppTheme.amber500.withValues(alpha: 0.12),
          )
        : ann.isRejected
        ? ('Rejected', AppTheme.red500, AppTheme.red500.withValues(alpha: 0.1))
        : ann.isOpen
        ? ('Open', AppTheme.emerald500, AppTheme.emerald50)
        : ('Closed', AppTheme.slate600, AppTheme.slate100);
    final statusPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: statusBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: ann.isApproved && !ann.isOpen
                  ? AppTheme.slate400
                  : statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slate100, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top: icon, title, status ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
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
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ann.title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            size: 12,
                            color: AppTheme.slate300,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${ann.postedBy} · ${ann.postedAt}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.slate500,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (isMobile) ...[
                        const SizedBox(height: 8),
                        statusPill,
                      ],
                    ],
                  ),
                ),
                // On a phone the pill sits under the title instead, so the
                // title keeps the card's full width.
                if (!isMobile) ...[const SizedBox(width: 8), statusPill],
              ],
            ),
          ),
          // ── Body ──────────────────────────────────────────
          if (ann.officeName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.maroon.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.apartment_rounded,
                      size: 13,
                      color: AppTheme.maroon,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ann.officeName!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.maroon,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              ann.body,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.slate600,
                height: 1.55,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ann.skills.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SkillsNeeded(ann.skills),
            ),
          if (ann.requirements.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ann.requirements
                    .map((req) => RequirementChip(label: req))
                    .toList(),
              ),
            ),
          if (ann.hasAttachment)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: AnnouncementAttachmentTile(announcement: ann),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (ann.deadline != null)
                  _Chip(
                    Icons.event_rounded,
                    'Due ${ann.deadline!}',
                    AppTheme.amber500,
                  ),
                if (ann.slots != null && !ann.isHiringCall)
                  _Chip(
                    Icons.people_rounded,
                    '${ann.slots} slots',
                    AppTheme.blue500,
                  ),
                if (ann.isSupervisorRequest && ann.skills.isNotEmpty)
                  _Chip(
                    Icons.join_inner_rounded,
                    '$appCount applicant${appCount == 1 ? '' : 's'} match',
                    AppTheme.maroon,
                  )
                else if (!ann.isSupervisorRequest && ann.acceptsApplications)
                  _Chip(
                    Icons.assignment_turned_in_rounded,
                    '$appCount applied',
                    AppTheme.maroon,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppTheme.slate100),
          // ── Actions ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: isMobile && ann.isPending
                // Four buttons don't fit across a phone, so a pending
                // request's decision gets a row of its own above View and
                // Delete — otherwise Approve was squeezed to "App…" or pushed
                // off the edge of the card.
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _ApproveAction(ann: ann)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.close_rounded,
                              label: 'Reject',
                              color: AppTheme.red500,
                              onTap: () => _showRejectDialog(ctx, ann.id),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.visibility_outlined,
                              label: 'View details',
                              color: AppTheme.slate600,
                              onTap: () => _showAnnouncementDetails(ctx, ann),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: Icons.delete_outline_rounded,
                            label: '',
                            color: AppTheme.red500,
                            iconOnly: true,
                            onTap: () =>
                                _confirmDelete(ctx),
                          ),
                        ],
                      ),
                    ],
                  )
                : isMobile
                ? Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.visibility_outlined,
                          label: 'View',
                          color: AppTheme.slate600,
                          onTap: () => _showAnnouncementDetails(ctx, ann),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                          child: ann.isOpen
                              ? _ActionButton(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'Close',
                                  color: AppTheme.slate600,
                                  onTap: () =>
                                      _confirmClose(ctx),
                                )
                              : _ActionButton(
                                  icon: Icons.check_rounded,
                                  label: 'Re-open',
                                  color: AppTheme.emerald500,
                                  onTap: () => _confirmReopen(ctx),
                                ),
                        ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: '',
                        color: AppTheme.red500,
                        iconOnly: true,
                        onTap: () =>
                            _confirmDelete(ctx),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            'Direct notifications dispatched',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate500,
                            ),
                          ),
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.visibility_outlined,
                        label: 'View Details',
                        color: AppTheme.slate600,
                        onTap: () => _showAnnouncementDetails(ctx, ann),
                      ),
                      const SizedBox(width: 8),
                      if (ann.isPending) ...[
                        _ApproveAction(ann: ann),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.close_rounded,
                          label: 'Reject',
                          color: AppTheme.red500,
                          onTap: () => _showRejectDialog(ctx, ann.id),
                        ),
                      ] else
                        ann.isOpen
                            ? _ActionButton(
                                icon: Icons.lock_outline_rounded,
                                label: 'Close',
                                color: AppTheme.slate600,
                                onTap: () =>
                                    _confirmClose(ctx),
                              )
                            : _ActionButton(
                                icon: Icons.check_rounded,
                                label: 'Re-open',
                                color: AppTheme.emerald500,
                                onTap: () =>
                                    _confirmReopen(ctx),
                              ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        color: AppTheme.red500,
                        onTap: () =>
                            _confirmDelete(ctx),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx) async {
    final appCount = ann.isSupervisorRequest
        ? 0
        : state.applications.where((a) => a.announcementId == ann.id).length;
    final ok = await showConfirmDialog(
      ctx,
      title: 'Delete announcement?',
      message:
          '"${ann.title}" will be permanently removed'
          '${ann.isVisibleToStudents ? ' and students will no longer see it' : ''}.'
          '${appCount > 0 ? ' The $appCount application${appCount == 1 ? '' : 's'} already submitted will be kept.' : ''}',
      confirmLabel: 'Delete',
    );
    if (!ok || !ctx.mounted) return;
    final messenger = ScaffoldMessenger.of(ctx);
    final deleted = await ctx.read<AppState>().deleteAnnouncement(ann.id);
    if (!deleted) {
      AppSnackBar.showWithMessenger(
        messenger,
        'Could not delete "${ann.title}". Check your connection and try '
        'again.',
        type: SnackType.error,
      );
    }
  }

  Future<void> _confirmClose(BuildContext ctx) async {
    final ok = await showConfirmDialog(
      ctx,
      title: 'Close announcement?',
      message: ann.isSupervisorRequest
          ? '"${ann.title}" will no longer be matched against applicants. '
                'You can re-open it later.'
          : '"${ann.title}" will be hidden from students'
                '${ann.acceptsApplications ? ' and stop taking applications' : ''}. '
                'You can re-open it later.',
      confirmLabel: 'Close',
      confirmColor: AppTheme.slate600,
    );
    if (!ok || !ctx.mounted) return;
    final messenger = ScaffoldMessenger.of(ctx);
    final closed = await ctx.read<AppState>().closeAnnouncement(ann.id);
    if (!closed) {
      AppSnackBar.showWithMessenger(
        messenger,
        'Could not close "${ann.title}", so it is still taking '
        'applications. Check your connection and try again.',
        type: SnackType.error,
      );
    }
  }

  Future<void> _confirmReopen(BuildContext ctx) async {
    final ok = await showConfirmDialog(
      ctx,
      title: 'Re-open announcement?',
      message: ann.isSupervisorRequest
          ? 'Applicants will be matched against "${ann.title}" again.'
          : '"${ann.title}" will be visible to students'
                '${ann.acceptsApplications ? ' and take applications' : ''} '
                'again. Students will be notified.',
      confirmLabel: 'Re-open',
      confirmColor: AppTheme.emerald500,
    );
    if (!ok || !ctx.mounted) return;
    final messenger = ScaffoldMessenger.of(ctx);
    final reopened = await ctx.read<AppState>().approveAnnouncement(ann.id);
    if (!reopened) {
      AppSnackBar.showWithMessenger(
        messenger,
        'Could not re-open "${ann.title}". Check your connection and try '
        'again.',
        type: SnackType.error,
      );
    }
  }

  void _showRejectDialog(BuildContext context, String announcementId) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reject Request',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Let the supervisor know why this request is being rejected (optional).',
              style: TextStyle(fontSize: 13, color: AppTheme.slate600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Reason for rejection',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.slate200),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.red500,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final state = dialogContext.read<AppState>();
              final reason = reasonCtrl.text.trim();
              Navigator.of(dialogContext).pop();
              final rejected = await state.rejectAnnouncement(
                announcementId,
                reason: reason.isEmpty ? null : reason,
              );
              if (!rejected) {
                AppSnackBar.showWithMessenger(
                  messenger,
                  'Could not reject the request. Check your connection and '
                  'try again.',
                  type: SnackType.error,
                );
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  void _showAnnouncementDetails(BuildContext context, Announcement ann) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 520,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      child: Text(
                        'Announcement Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
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
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ann.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: AppTheme.slate400,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Posted by ${ann.postedBy}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          ann.postedAt,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ann.body,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.slate700,
                        height: 1.7,
                      ),
                    ),
                    if (ann.skills.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      SkillsNeeded(ann.skills),
                    ],
                    if (ann.requirements.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Requirements',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ann.requirements
                            .map((req) {
                              final spec = RequirementSpec.parse(req);
                              return _Chip(
                                spec.fileType == 'image'
                                    ? Icons.image_outlined
                                    : spec.fileType != null
                                        ? Icons.description_outlined
                                        : Icons.check_circle_outline,
                                spec.fileTypeLabel == null
                                    ? spec.label
                                    : '${spec.label} (${spec.fileTypeLabel})',
                                AppTheme.maroon,
                              );
                            })
                            .toList(),
                      ),
                    ],
                    if (ann.hasAttachment) ...[
                      const SizedBox(height: 18),
                      AnnouncementAttachmentTile(announcement: ann),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (ann.deadline != null)
                          _Chip(
                            Icons.event_rounded,
                            'Due ${ann.deadline!}',
                            AppTheme.amber500,
                          ),
                        if (ann.slots != null && !ann.isHiringCall)
                          _Chip(
                            Icons.people_rounded,
                            '${ann.slots} slots',
                            AppTheme.blue500,
                          ),
                        _Chip(
                          Icons.info_outline,
                          ann.isPending
                              ? 'Pending approval'
                              : ann.isApproved
                              ? (ann.isOpen ? 'Open' : 'Closed')
                              : 'Rejected',
                          ann.isPending
                              ? AppTheme.amber500
                              : ann.isApproved
                              ? (ann.isOpen
                                    ? AppTheme.emerald500
                                    : AppTheme.slate400)
                              : AppTheme.red500,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.w700),
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
  }
}

/// Approve button for a pending request: asks for confirmation first, then
/// shows a spinner until the approval has been saved.
class _ApproveAction extends StatefulWidget {
  final Announcement ann;
  const _ApproveAction({required this.ann});

  @override
  State<_ApproveAction> createState() => _ApproveActionState();
}

class _ApproveActionState extends State<_ApproveAction> {
  bool _approving = false;

  Future<void> _approve() async {
    // The dialog returns the code for an office the approval creates ('' if
    // it creates none), or null when cancelled.
    final officeCode = await showDialog<String>(
      context: context,
      builder: (_) => _ApproveConfirmDialog(ann: widget.ann),
    );
    if (officeCode == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    final plan = state.officePlanFor(widget.ann);
    setState(() => _approving = true);
    final ok = await state.approveAnnouncement(
      widget.ann.id,
      newOfficeCode: officeCode,
    );
    // Once approved the card swaps this button out, so it may be gone.
    if (mounted) setState(() => _approving = false);
    final officeNote = plan == null || !plan.changesOffice
        ? ''
        : plan.createsOffice
        ? ' The office "${plan.office.name}" was created.'
        : ' ${plan.office.name} was updated.';
    AppSnackBar.showWithMessenger(
      messenger,
      ok
          ? '"${widget.ann.title}" approved.$officeNote'
          : 'Could not approve "${widget.ann.title}". Check your connection '
                'and try again.',
      type: ok ? SnackType.success : SnackType.error,
    );
  }

  @override
  Widget build(BuildContext context) => _ActionButton(
    icon: Icons.check_rounded,
    label: _approving ? 'Approving...' : 'Approve',
    color: AppTheme.emerald500,
    loading: _approving,
    onTap: _approving ? null : _approve,
  );
}

/// Confirms an approval, and says what it does to the request's office:
/// creating it (with a code the Head can change) or the changes that make
/// room in it. Pops the office code, '' when no office is created.
class _ApproveConfirmDialog extends StatefulWidget {
  final Announcement ann;
  const _ApproveConfirmDialog({required this.ann});

  @override
  State<_ApproveConfirmDialog> createState() => _ApproveConfirmDialogState();
}

class _ApproveConfirmDialogState extends State<_ApproveConfirmDialog> {
  late final _code = TextEditingController(
    text: Office.suggestCode(widget.ann.officeName ?? ''),
  );
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _confirm(OfficeRequestPlan? plan) {
    final code = _code.text.trim();
    if (plan != null && plan.createsOffice && code.isEmpty) {
      setState(() => _codeError = 'Enter a code for the new office.');
      return;
    }
    Navigator.pop(context, plan != null && plan.createsOffice ? code : '');
  }

  @override
  Widget build(BuildContext context) {
    final ann = widget.ann;
    final plan = context.watch<AppState>().officePlanFor(ann);
    final details = [
      if (ann.officeName != null) (Icons.apartment_rounded, ann.officeName!),
      (Icons.person_rounded, 'Requested by ${ann.postedBy}'),
      if (ann.slots != null && !ann.isHiringCall) (Icons.people_rounded, '${ann.slots} slots'),
      if (ann.deadline != null) (Icons.event_rounded, 'Due ${ann.deadline}'),
    ];
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Approve this request?',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ann.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                    ),
                  ),
                  for (final (icon, text) in details) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(icon, size: 13, color: AppTheme.slate400),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            text,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.slate600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (ann.skills.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SkillsNeeded(ann.skills),
                  ],
                ],
              ),
            ),
            if (plan != null && plan.changesOffice) ...[
              const SizedBox(height: 12),
              _officeChanges(plan),
            ],
            const SizedBox(height: 14),
            Text(
              'Students never see a request: once approved, applicants are '
              'matched to it by their skills on Applications. '
              '${ann.postedBy} will be notified.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.slate600,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => _confirm(plan),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(
            plan != null && plan.createsOffice
                ? 'Approve & Create Office'
                : 'Approve',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.emerald500,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  /// What approving does to the office, in a tinted box.
  Widget _officeChanges(OfficeRequestPlan plan) {
    final office = plan.office;
    final current = plan.current;
    final supervisor = widget.ann.postedBy;
    final slots = int.tryParse(widget.ann.slots?.trim() ?? '') ?? 0;
    final changes = plan.createsOffice
        ? [
            'Creates "${office.name}" with $supervisor as its supervisor',
            if (office.capacity > 0)
              'Room for ${office.capacity} student '
                  'assistant${office.capacity == 1 ? '' : 's'}',
            if (office.requiredSkills.isNotEmpty)
              'Needs: ${office.requiredSkills.join(', ')}',
          ]
        : [
            if (plan.addedSkills.isNotEmpty)
              'Adds to the skills it needs: ${plan.addedSkills.join(', ')}',
            if (plan.raisesCapacity)
              'Raises its capacity from ${current!.capacity} to '
                  '${office.capacity}, to fit the $slots '
                  'slot${slots == 1 ? '' : 's'} asked for',
            if (plan.addsSupervisor) 'Adds $supervisor as a supervisor',
            if (plan.reactivates) 'Makes it active again',
          ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.maroon50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.maroon.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                plan.createsOffice
                    ? Icons.add_business_rounded
                    : Icons.apartment_rounded,
                size: 15,
                color: AppTheme.maroon,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  plan.createsOffice
                      ? 'New office'
                      : 'Updates ${office.name}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.maroon,
                  ),
                ),
              ),
            ],
          ),
          for (final change in changes) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Icon(Icons.circle, size: 5, color: AppTheme.maroon),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    change,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (plan.createsOffice) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) {
                if (_codeError != null) setState(() => _codeError = null);
              },
              decoration: InputDecoration(
                labelText: 'Office code',
                helperText: 'You can change it later in Offices.',
                errorText: _codeError,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  /// Null disables the button.
  final VoidCallback? onTap;
  final bool iconOnly;

  /// Swaps the icon for a small spinner while an action is in progress.
  final bool loading;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.iconOnly = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 10 : 12,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 15, color: color),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}