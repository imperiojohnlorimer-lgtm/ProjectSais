import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

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
  final _searchCtrl = TextEditingController();

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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = _searchCtrl.text.trim().toLowerCase();

    final forwards = state.headForwards.where((f) {
      if (_typeFilter != 'All' && f.type != _typeFilter) return false;
      if (_statusFilter == 'Unreviewed' && f.reviewed) return false;
      if (_statusFilter == 'Reviewed' && !f.reviewed) return false;
      if (query.isNotEmpty && !f.studentName.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

    final byStudent = <String, List<HeadForward>>{};
    for (final f in forwards) {
      byStudent.putIfAbsent(f.studentName, () => []).add(f);
    }
    final studentNames = byStudent.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    final totalUnreviewed = state.headForwards.where((f) => !f.reviewed).length;
    final reportCount = state.headForwards.where((f) => f.type == 'report').length;
    final evalCount = state.headForwards.where((f) => f.type == 'evaluation').length;
    final dtrCount = state.headForwards.where((f) => f.type == 'dtr_report').length;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 420;
    final horizontalPadding = isCompact ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(color: AppTheme.maroon, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sent to Head',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.slate900, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalUnreviewed > 0
                          ? 'Reports, evaluations, and DTR files forwarded by supervisors · $totalUnreviewed unreviewed'
                          : 'Reports, evaluations, and DTR files forwarded by supervisors',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.slate400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (state.headForwards.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: _SentSummary(
              total: state.headForwards.length,
              unreviewed: totalUnreviewed,
              reportCount: reportCount,
              evalCount: evalCount,
              dtrCount: dtrCount,
            ),
          ),
          const SizedBox(height: 18),
        ],
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by student name...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.slate400),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _searchCtrl.clear()),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.slate200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.slate200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.maroon, width: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _typeLabels.keys.map((t) {
                final selected = _typeFilter == t;
                return GestureDetector(
                  onTap: () => setState(() => _typeFilter = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: selected ? AppTheme.maroon : AppTheme.slate200),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: AppTheme.maroon.withValues(alpha: 0.28),
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
                          _typeIcons[t],
                          size: 14,
                          color: selected ? Colors.white : AppTheme.slate400,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _typeLabels[t]!,
                          style: TextStyle(
                            color: selected ? Colors.white : AppTheme.slate600,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Unreviewed', 'Reviewed'].map((s) {
                final selected = _statusFilter == s;
                return GestureDetector(
                  onTap: () => setState(() => _statusFilter = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.slate800 : AppTheme.slate100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        color: selected ? Colors.white : AppTheme.slate500,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 28),
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
                            decoration: const BoxDecoration(color: AppTheme.slate100, shape: BoxShape.circle),
                            child: Icon(
                              state.headForwards.isEmpty ? Icons.inbox_outlined : Icons.search_off_rounded,
                              size: 36,
                              color: AppTheme.slate300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            state.headForwards.isEmpty ? 'Nothing sent yet' : 'No matches found',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate400),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.headForwards.isEmpty
                                ? 'Approved reports, evaluations, and DTR reports that\n'
                                    'supervisors forward will appear here, per student.'
                                : 'Try a different search term or filter.',
                            style: const TextStyle(fontSize: 13, color: AppTheme.slate500),
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
        ),
      ],
    );
  }
}

class _SentSummary extends StatelessWidget {
  final int total;
  final int unreviewed;
  final int reportCount;
  final int evalCount;
  final int dtrCount;

  const _SentSummary({
    required this.total,
    required this.unreviewed,
    required this.reportCount,
    required this.evalCount,
    required this.dtrCount,
  });

  @override
  Widget build(BuildContext context) {
    final reviewedFraction = total == 0 ? 0.0 : (total - unreviewed) / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.maroon, AppTheme.maroon.withValues(alpha: 0.88)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.maroon.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Reviewed progress',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const Spacer(),
              Text(
                unreviewed > 0 ? '$unreviewed of $total unreviewed' : 'All $total reviewed',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: reviewedFraction.clamp(0, 1)),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 9,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _miniStat(Icons.description_outlined, reportCount, 'Reports'),
              _miniStat(Icons.fact_check_outlined, evalCount, 'Evaluations'),
              _miniStat(Icons.event_note_outlined, dtrCount, 'DTR Reports'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, int count, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: Colors.white70),
      const SizedBox(width: 5),
      Text(
        '$count',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    ],
  );
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
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
                        colors: [AppTheme.maroon, AppTheme.maroon.withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.studentName.trim().isNotEmpty
                          ? widget.studentName.trim()[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.studentName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unreviewed > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.maroon50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$unreviewed new',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.maroon),
                      ),
                    ),
                  Text(
                    '${widget.items.length} item${widget.items.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.slate400, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
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
      case 'evaluation': return Icons.fact_check_outlined;
      case 'dtr_report': return Icons.event_note_outlined;
      default: return Icons.description_outlined;
    }
  }

  Color get _accent {
    switch (item.type) {
      case 'evaluation': return AppTheme.blue500;
      case 'dtr_report': return AppTheme.emerald500;
      default: return AppTheme.maroon;
    }
  }

  String get _typeLabel {
    switch (item.type) {
      case 'evaluation': return 'Performance Evaluation';
      case 'dtr_report': return 'DTR/Accomplishment Report';
      default: return 'Report';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.reviewed ? AppTheme.slate50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          top: BorderSide(color: item.reviewed ? AppTheme.slate200 : _accent.withValues(alpha: 0.28)),
          right: BorderSide(color: item.reviewed ? AppTheme.slate200 : _accent.withValues(alpha: 0.28)),
          bottom: BorderSide(color: item.reviewed ? AppTheme.slate200 : _accent.withValues(alpha: 0.28)),
          left: BorderSide(color: _accent, width: 4),
        ),
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
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _accent, letterSpacing: 0.3),
                      ),
                    ),
                    if (!item.reviewed)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: AppTheme.red500, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.slate800),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'From ${item.sentByName} · ${item.sentAt}',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (item.downloadUrl != null)
                      ElevatedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(item.downloadUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.download_rounded, size: 13),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald500,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => state.setHeadForwardReviewed(item.id, !item.reviewed),
                      icon: Icon(
                        item.reviewed ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                        size: 13,
                      ),
                      label: Text(item.reviewed ? 'Reviewed' : 'Mark reviewed'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: item.reviewed ? AppTheme.slate500 : AppTheme.maroon,
                        side: BorderSide(color: item.reviewed ? AppTheme.slate300 : AppTheme.maroon, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
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
    );
  }
}
