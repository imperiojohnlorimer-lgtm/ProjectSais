import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Head-only screen listing everything supervisors have forwarded — approved
/// reports, submitted performance evaluations, and generated DTR/
/// Accomplishment reports — grouped by student instead of mixed into the
/// general notification feed.
class HeadForwardsScreen extends StatefulWidget {
  const HeadForwardsScreen({super.key});

  @override
  State<HeadForwardsScreen> createState() => _HeadForwardsScreenState();
}

class _HeadForwardsScreenState extends State<HeadForwardsScreen> {
  // 'All' | 'report' | 'evaluation' | 'dtr_report'
  String _typeFilter = 'All';
  // 'All' | 'Unreviewed' | 'Reviewed'
  String _statusFilter = 'All';
  String _search = '';

  static const Map<String, String> _typeLabels = {
    'All': 'All',
    'report': 'Reports',
    'evaluation': 'Evaluations',
    'dtr_report': 'DTR Reports',
  };

  static const Map<String, IconData> _typeIcons = {
    'All': Icons.apps_rounded,
    'report': Icons.description_outlined,
    'evaluation': Icons.fact_check_outlined,
    'dtr_report': Icons.event_note_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = _search.trim().toLowerCase();

    final forwards = state.headForwards.where((f) {
      if (_typeFilter != 'All' && f.type != _typeFilter) return false;
      if (_statusFilter == 'Unreviewed' && f.reviewed) return false;
      if (_statusFilter == 'Reviewed' && !f.reviewed) return false;
      if (query.isNotEmpty && !f.studentName.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.sentAt.compareTo(a.sentAt));

    final byStudent = <String, List<HeadForward>>{};
    for (final f in forwards) {
      byStudent.putIfAbsent(f.studentName, () => []).add(f);
    }
    final studentNames = byStudent.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    final totalUnreviewed = state.headForwards.where((f) => !f.reviewed).length;
    final reportCount = state.headForwards
        .where((f) => f.type == 'report')
        .length;
    final evalCount = state.headForwards
        .where((f) => f.type == 'evaluation')
        .length;
    final dtrCount = state.headForwards
        .where((f) => f.type == 'dtr_report')
        .length;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 420;
    final horizontalPadding = isCompact ? 16.0 : 28.0;

    // The header, summary and filters scroll away with the list so the
    // content is not squeezed into a short viewport on small screens.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              24,
              horizontalPadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeroBanner(
                  isMobile: isCompact,
                  icon: Icons.forward_to_inbox_rounded,
                  title: 'Sent to Head',
                  subtitle:
                      'Reports, evaluations, and DTR files forwarded by supervisors',
                  searchHint: 'Search by student name...',
                  onSearch: (value) => setState(() => _search = value),
                  stats: [
                    HeroStatData(
                      label: 'Forwarded',
                      value: '${state.headForwards.length}',
                      icon: Icons.inbox_rounded,
                    ),
                    HeroStatData(
                      label: 'Unreviewed',
                      value: '$totalUnreviewed',
                      icon: Icons.mark_email_unread_rounded,
                    ),
                    HeroStatData(
                      label: 'Reports',
                      value: '$reportCount',
                      icon: Icons.description_outlined,
                    ),
                    HeroStatData(
                      label: 'Evaluations',
                      value: '$evalCount',
                      icon: Icons.fact_check_outlined,
                    ),
                    HeroStatData(
                      label: 'DTR',
                      value: '$dtrCount',
                      icon: Icons.event_note_outlined,
                    ),
                  ],
                ),
                if (state.headForwards.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ProgressStrip(
                    label: 'Reviewed',
                    icon: Icons.fact_check_rounded,
                    progress: state.headForwards.isEmpty
                        ? 0
                        : (state.headForwards.length - totalUnreviewed) /
                              state.headForwards.length,
                    trailing:
                        '${state.headForwards.length - totalUnreviewed}/${state.headForwards.length}',
                  ),
                ],
                const SizedBox(height: 14),
                // Type and review-state filters.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final t in _typeLabels.keys)
                        _chip(
                          label: _typeLabels[t]!,
                          icon: _typeIcons[t],
                          selected: _typeFilter == t,
                          color: AppTheme.maroon,
                          onTap: () => setState(() => _typeFilter = t),
                        ),
                      Container(
                        width: 1,
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: AppTheme.slate200,
                      ),
                      for (final s in const ['All', 'Unreviewed', 'Reviewed'])
                        _chip(
                          label: s,
                          selected: _statusFilter == s,
                          color: AppTheme.slate700,
                          onTap: () => setState(() => _statusFilter = s),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (forwards.isEmpty)
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
                            child: Icon(
                              state.headForwards.isEmpty
                                  ? Icons.inbox_outlined
                                  : Icons.search_off_rounded,
                              size: 36,
                              color: AppTheme.slate300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            state.headForwards.isEmpty
                                ? 'Nothing sent yet'
                                : 'No matches found',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.headForwards.isEmpty
                                ? 'Approved reports, evaluations, and DTR reports that\n'
                                      'supervisors forward will appear here, per student.'
                                : 'Try a different search term or filter.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.slate500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final studentName in studentNames)
                    _StudentGroup(
                      studentName: studentName,
                      items: byStudent[studentName]!,
                      state: state,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact filter chip used for the type and review-state rows.
  Widget _chip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : AppTheme.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? color : AppTheme.slate400),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppTheme.slate600,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentGroup extends StatefulWidget {
  final String studentName;
  final List<HeadForward> items;
  final AppState state;

  const _StudentGroup({
    required this.studentName,
    required this.items,
    required this.state,
  });

  @override
  State<_StudentGroup> createState() => _StudentGroupState();
}

class _StudentGroupState extends State<_StudentGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final unreviewed = widget.items.where((f) => !f.reviewed).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.maroon,
                          AppTheme.maroon.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.studentName.trim().isNotEmpty
                          ? widget.studentName.trim()[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.studentName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unreviewed > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.maroon50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$unreviewed new',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.maroon,
                        ),
                      ),
                    ),
                  Text(
                    '${widget.items.length} item${widget.items.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.slate400,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: widget.items
                    .map((f) => _ForwardTile(item: f, state: widget.state))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ForwardTile extends StatelessWidget {
  final HeadForward item;
  final AppState state;
  const _ForwardTile({required this.item, required this.state});

  IconData get _icon {
    switch (item.type) {
      case 'evaluation':
        return Icons.fact_check_outlined;
      case 'dtr_report':
        return Icons.event_note_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color get _accent {
    switch (item.type) {
      case 'evaluation':
        return AppTheme.blue500;
      case 'dtr_report':
        return AppTheme.emerald500;
      default:
        return AppTheme.maroon;
    }
  }

  String get _typeLabel {
    switch (item.type) {
      case 'evaluation':
        return 'Performance Evaluation';
      case 'dtr_report':
        return 'DTR/Accomplishment Report';
      default:
        return 'Report';
    }
  }

  // The stored downloadUrl is a Supabase signed URL that expires (~1hr), so
  // always request a fresh one from storagePath first, falling back to the
  // stored URL for older records that predate storagePath being saved.
  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      String? url = item.downloadUrl;
      if (item.storagePath != null && item.storagePath!.isNotEmpty) {
        url = await SupabaseStorageService.instance.getDocumentUrl(
          item.storagePath!,
        );
      }
      if (url == null || url.isEmpty)
        throw Exception('No file content available.');
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('The browser could not open the document.');
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
    }
  }

  @override
  Widget build(BuildContext context) {
    // A BoxDecoration can't combine borderRadius with a Border whose sides
    // have different colors/widths (Flutter throws "A borderRadius can only
    // be given on borders with uniform colors" and fails to paint the whole
    // decoration+child) — so the maroon-accent left edge is a Positioned
    // overlay in a Stack instead of part of this Container's border.
    // (Deliberately not a stretched Row sibling either, to keep this tile's
    // height resolution simple and unambiguous regardless of the parent's
    // constraints.)
    final sideColor = item.reviewed
        ? AppTheme.slate200
        : _accent.withValues(alpha: 0.28);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: item.reviewed ? AppTheme.slate50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sideColor),
        boxShadow: item.reviewed
            ? null
            : [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_icon, size: 15, color: _accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _typeLabel,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: _accent,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          if (!item.reviewed)
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppTheme.red500,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'From ${item.sentByName} · ${item.sentAt}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.slate500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (item.downloadUrl != null ||
                              item.storagePath != null)
                            ElevatedButton.icon(
                              onPressed: () => _download(context),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 13,
                              ),
                              label: const Text('Download'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.emerald500,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => state.setHeadForwardReviewed(
                              item.id,
                              !item.reviewed,
                            ),
                            icon: Icon(
                              item.reviewed
                                  ? Icons.check_circle_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 13,
                            ),
                            label: Text(
                              item.reviewed ? 'Reviewed' : 'Mark reviewed',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: item.reviewed
                                  ? AppTheme.slate500
                                  : AppTheme.maroon,
                              side: BorderSide(
                                color: item.reviewed
                                    ? AppTheme.slate300
                                    : AppTheme.maroon,
                                width: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: Container(color: _accent),
          ),
        ],
      ),
    );
  }
}
