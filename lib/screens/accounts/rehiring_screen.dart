import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

typedef _Term = ({String academicYear, String semester});

/// Head screen: decide, term by term, which Student Assistants are rehired
/// and which aren't — the follow-through on the "Eligible for Rehire" mark
/// supervisors give on each performance evaluation.
class RehiringScreen extends StatefulWidget {
  const RehiringScreen({super.key});

  @override
  State<RehiringScreen> createState() => _RehiringScreenState();
}

class _RehiringScreenState extends State<RehiringScreen> {
  static const _filters = [
    'All',
    'Recommended',
    'Not recommended',
    'No evaluation',
    'Pending decision',
    'Rehired',
    'Not rehired',
  ];

  String _search = '';
  String _filter = 'All';
  _Term? _term;
  String? _busyUserId;

  bool _matchesFilter(Evaluation? evaluation, RehireRecord? record) {
    switch (_filter) {
      case 'Recommended':
        return evaluation?.eligibleForRehire == true;
      case 'Not recommended':
        return evaluation?.eligibleForRehire == false;
      case 'No evaluation':
        return evaluation == null;
      case 'Pending decision':
        return record == null;
      case 'Rehired':
        return record?.isRehired == true;
      case 'Not rehired':
        return record != null && !record.isRehired;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    final termOptions = state.rehireTermOptions;
    final term = termOptions.contains(_term)
        ? _term!
        : state.defaultRehireTerm;
    final termLabel = RehireRecord.termLabelFor(
      term.academicYear,
      term.semester,
    );
    final termStarted = state.rehireTermHasStarted(
      term.academicYear,
      term.semester,
    );

    final candidates = state.rehireCandidates(term.academicYear, term.semester);
    final evaluationFor = {
      for (final u in candidates) u.id: state.latestEvaluationForUser(u),
    };
    final recordFor = {
      for (final u in candidates)
        u.id: state.rehireRecordFor(u.id, term.academicYear, term.semester),
    };

    final q = _search.trim().toLowerCase();
    final visible = candidates.where((u) {
      final matchesSearch =
          q.isEmpty ||
          u.name.toLowerCase().contains(q) ||
          (u.saId ?? '').toLowerCase().contains(q);
      return matchesSearch &&
          _matchesFilter(evaluationFor[u.id], recordFor[u.id]);
    }).toList();

    final recommended = evaluationFor.values
        .where((e) => e?.eligibleForRehire == true)
        .length;
    final notRecommended = evaluationFor.values
        .where((e) => e?.eligibleForRehire == false)
        .length;
    final noEvaluation = evaluationFor.values.where((e) => e == null).length;
    final decided = recordFor.values.whereType<RehireRecord>().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: HeroBanner(
            isMobile: isMobile,
            icon: Icons.autorenew_rounded,
            title: 'Rehiring',
            subtitle:
                'Decide who continues as a student assistant, based on '
                'their supervisor\'s evaluation',
            searchHint: 'Search by name or SA ID...',
            onSearch: (value) => setState(() => _search = value),
            filters: [
              _dropdown<_Term>(
                value: term,
                minWidth: 230,
                items: {
                  for (final option in termOptions)
                    option: 'For ${RehireRecord.termLabelFor(option.academicYear, option.semester)}',
                },
                onChanged: (value) => setState(() => _term = value),
              ),
              _dropdown<String>(
                value: _filter,
                minWidth: 170,
                items: {for (final f in _filters) f: f},
                onChanged: (value) => setState(() => _filter = value),
              ),
            ],
            stats: [
              HeroStatData(
                label: 'Recommended',
                value: '$recommended',
                icon: Icons.thumb_up_alt_rounded,
              ),
              HeroStatData(
                label: 'Not recommended',
                value: '$notRecommended',
                icon: Icons.thumb_down_alt_rounded,
              ),
              HeroStatData(
                label: 'No evaluation',
                value: '$noEvaluation',
                icon: Icons.help_outline_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (candidates.isNotEmpty) ...[
                  ProgressStrip(
                    label: 'Decided',
                    icon: Icons.how_to_reg_rounded,
                    progress: decided / candidates.length,
                    trailing: '$decided/${candidates.length}',
                  ),
                  const SizedBox(height: 10),
                  _timingNote(termLabel, termStarted),
                  const SizedBox(height: 14),
                ],
                if (visible.isEmpty)
                  _emptyState(candidates.isEmpty)
                else
                  for (final user in visible)
                    _candidateCard(
                      state,
                      user,
                      term,
                      evaluationFor[user.id],
                      recordFor[user.id],
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required double minWidth,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) => Container(
    height: 40,
    constraints: BoxConstraints(minWidth: minWidth),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.slate200),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        isExpanded: true,
        borderRadius: BorderRadius.circular(12),
        icon: const Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: AppTheme.slate400,
        ),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.slate700,
        ),
        items: items.entries
            .map(
              (entry) => DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ),
  );

  Widget _timingNote(String termLabel, bool termStarted) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.blue50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.blue500.withValues(alpha: 0.18)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.blue500),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            termStarted
                ? '$termLabel has started, so decisions for it take effect '
                      'as soon as you save them.'
                : 'Decisions for $termLabel take effect when that term '
                      'starts in the academic year settings. Until then '
                      'everyone stays in their office, so students who '
                      'aren\'t rehired can finish the current term.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.slate700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _emptyState(bool noneAtAll) => Center(
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
              Icons.autorenew_rounded,
              size: 36,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            noneAtAll
                ? 'No student assistants to decide on'
                : 'No student assistants match this search',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate400,
            ),
          ),
          if (!noneAtAll) ...[
            const SizedBox(height: 4),
            const Text(
              'Try a different name or filter.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.slate400),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _candidateCard(
    AppState state,
    User user,
    _Term term,
    Evaluation? evaluation,
    RehireRecord? record,
  ) {
    final offices = state.officesForUser(user);
    final officeLabel = offices.isNotEmpty
        ? offices.map((o) => o.name).join(', ')
        : (record?.officeNames.isNotEmpty == true
              ? record!.officeNames.join(', ')
              : 'No office');
    final busy = _busyUserId == user.id;

    final railColor = record == null
        ? AppTheme.slate300
        : (record.isRehired ? AppTheme.emerald500 : AppTheme.red500);

    void decide({required bool rehire}) =>
        _openDecision(state, user, term, evaluation, record, rehire: rehire);

    // Undecided: Don't Rehire / Rehire. Rehired: Contract / Don't Rehire /
    // Edit. Not rehired: Edit / Rehire.
    final actions = <Widget>[
      if (record != null && record.isRehired)
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => record.hasContract
                    ? _downloadContract(record)
                    : _generateContract(state, record),
          icon: Icon(
            record.hasContract
                ? Icons.download_rounded
                : Icons.note_add_outlined,
            size: 16,
          ),
          label: Text(record.hasContract ? 'Contract' : 'Generate Contract'),
          style: _outlinedStyle(AppTheme.maroon),
        ),
      if (record == null || record.isRehired)
        OutlinedButton.icon(
          onPressed: busy ? null : () => decide(rehire: false),
          icon: const Icon(Icons.person_off_outlined, size: 16),
          label: const Text("Don't Rehire"),
          style: _outlinedStyle(AppTheme.red500),
        ),
      if (record != null)
        OutlinedButton.icon(
          onPressed: busy ? null : () => decide(rehire: record.isRehired),
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Edit'),
          style: _outlinedStyle(AppTheme.slate600),
        ),
      if (record == null || !record.isRehired)
        ElevatedButton.icon(
          onPressed: busy ? null : () => decide(rehire: true),
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.autorenew_rounded, size: 16),
          label: const Text('Rehire'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.maroon,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserAvatar(
                        avatarUrl: user.avatar,
                        initials: user.initials,
                        size: 40,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if ((user.saId ?? '').isNotEmpty) user.saId!,
                                officeLabel,
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.slate400,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _decisionPill(record),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _recommendationChip(evaluation),
                      if (evaluation != null) _evaluationChip(evaluation),
                    ],
                  ),
                  if (record != null) ...[
                    const SizedBox(height: 12),
                    _decisionDetails(state, record, busy),
                  ],
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: actions,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: railColor),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outlinedStyle(Color color) => OutlinedButton.styleFrom(
    foregroundColor: color,
    side: BorderSide(color: color, width: 1.3),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
  );

  Widget _decisionPill(RehireRecord? record) {
    final (label, color, icon) = record == null
        ? ('Pending', AppTheme.slate500, Icons.schedule_rounded)
        : record.isRehired
        ? ('Rehired', AppTheme.emerald500, Icons.check_circle_rounded)
        : ('Not rehired', AppTheme.red500, Icons.cancel_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _recommendationChip(Evaluation? evaluation) {
    if (evaluation == null) {
      return _chip(
        icon: Icons.help_outline_rounded,
        label: 'No evaluation yet',
        color: AppTheme.slate500,
      );
    }
    return evaluation.eligibleForRehire
        ? _chip(
            icon: Icons.thumb_up_alt_rounded,
            label: 'Recommended for rehire',
            color: AppTheme.emerald500,
          )
        : _chip(
            icon: Icons.thumb_down_alt_rounded,
            label: 'Not recommended for rehire',
            color: AppTheme.red500,
          );
  }

  Widget _evaluationChip(Evaluation evaluation) => _chip(
    icon: Icons.fact_check_outlined,
    label:
        '${evaluation.term}'
        '${evaluation.academicYear != null ? ' ${evaluation.academicYear}' : ''}'
        ' · ${evaluation.overallRating}/10 '
        '${EvaluationCriteria.bandLabel(evaluation.overallRating)}'
        ' · ${evaluation.supervisorName}',
    color: AppTheme.blue500,
  );

  Widget _decisionDetails(AppState state, RehireRecord record, bool busy) {
    final decidedOn = DateTime.tryParse(record.decidedAt);
    final decidedLabel = decidedOn == null
        ? record.decidedAt
        : '${_months[decidedOn.month - 1]} ${decidedOn.day}, ${decidedOn.year}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${record.isRehired ? 'Rehired' : 'Not rehired'} for '
            '${record.termLabel}'
            '${record.isRehired && record.officeNames.isNotEmpty ? ' in ${record.officeNames.join(', ')}' : ''}'
            ' · by ${record.decidedByName.isEmpty ? 'Head' : record.decidedByName}'
            ' on $decidedLabel',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
          ),
          if (record.remarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Remarks: ${record.remarks}',
              style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ],
          const SizedBox(height: 6),
          if (record.applied)
            const Row(
              children: [
                Icon(Icons.check_rounded, size: 14, color: AppTheme.emerald500),
                SizedBox(width: 4),
                Text(
                  'In effect',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.emerald500,
                  ),
                ),
              ],
            )
          else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  'Takes effect when ${record.termLabel} starts.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.amber500,
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => _applyNow(state, record),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Apply now'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static const _months = [
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

  Future<void> _openDecision(
    AppState state,
    User user,
    _Term term,
    Evaluation? evaluation,
    RehireRecord? record, {
    required bool rehire,
  }) async {
    final result = await showDialog<_DecisionResult>(
      context: context,
      builder: (_) => _RehireDecisionDialog(
        user: user,
        term: term,
        evaluation: evaluation,
        record: record,
        initialRehire: rehire,
        termStarted: state.rehireTermHasStarted(
          term.academicYear,
          term.semester,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyUserId = user.id);
    final error = await state.decideRehire(
      user: user,
      termYear: term.academicYear,
      termSemester: term.semester,
      rehire: result.rehire,
      officeId: result.officeId,
      remarks: result.remarks,
    );
    if (!mounted) return;
    setState(() => _busyUserId = null);

    if (error != null) {
      AppSnackBar.showWithMessenger(messenger, error, type: SnackType.error);
      return;
    }
    final saved = state.rehireRecordFor(
      user.id,
      term.academicYear,
      term.semester,
    );
    final termLabel = RehireRecord.termLabelFor(
      term.academicYear,
      term.semester,
    );
    if (result.rehire && saved != null && !saved.hasContract) {
      AppSnackBar.showWithMessenger(
        messenger,
        '${user.name} was rehired, but the contract could not be generated. '
        'Use "Generate Contract" to try again.',
        type: SnackType.warning,
        duration: const Duration(seconds: 5),
      );
    } else {
      AppSnackBar.showWithMessenger(
        messenger,
        result.rehire
            ? '${user.name} was rehired for $termLabel'
            : '${user.name} will not be rehired for $termLabel',
        type: SnackType.success,
      );
    }
  }

  Future<void> _applyNow(AppState state, RehireRecord record) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Apply now?',
      message: record.isRehired
          ? 'This puts ${record.studentName} in '
                '${record.officeNames.isEmpty ? 'their office' : record.officeNames.join(', ')} '
                'as a student assistant now, before ${record.termLabel} starts.'
          : 'This takes ${record.studentName} off their office and returns '
                'their account to Student now, before ${record.termLabel} '
                'starts. They will no longer be able to log hours.',
      confirmLabel: 'Apply now',
      confirmColor: AppTheme.maroon,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyUserId = record.studentId);
    final error = await state.applyRehireDecisionNow(record);
    if (!mounted) return;
    setState(() => _busyUserId = null);
    AppSnackBar.showWithMessenger(
      messenger,
      error ?? 'Decision for ${record.studentName} is now in effect',
      type: error == null ? SnackType.success : SnackType.error,
    );
  }

  Future<void> _generateContract(AppState state, RehireRecord record) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyUserId = record.studentId);
    final error = await state.generateRehireContract(record);
    if (!mounted) return;
    setState(() => _busyUserId = null);
    AppSnackBar.showWithMessenger(
      messenger,
      error ?? 'Contract of Appointment generated for ${record.studentName}',
      type: error == null ? SnackType.success : SnackType.error,
    );
  }

  Future<void> _downloadContract(RehireRecord record) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // The stored URL is a signed one that expires, so ask for a fresh one
      // from the storage path when there is one.
      final path = record.contractStoragePath;
      final url = path != null && path.isNotEmpty
          ? await SupabaseStorageService.instance.getDocumentUrl(path)
          : record.contractDownloadUrl;
      if (url == null || url.isEmpty) {
        throw Exception('This contract has no file attached.');
      }
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('The browser could not open the contract.');
    } catch (e) {
      AppSnackBar.showWithMessenger(
        messenger,
        'Unable to download: $e',
        type: SnackType.warning,
      );
    }
  }
}

class _DecisionResult {
  final bool rehire;
  final String? officeId;
  final String remarks;

  const _DecisionResult({
    required this.rehire,
    required this.officeId,
    required this.remarks,
  });
}

/// Confirms a rehire decision: the supervisor's evaluation for reference,
/// Rehire / Don't rehire, the office to rehire into, and remarks — which
/// are required when going against the supervisor's recommendation.
class _RehireDecisionDialog extends StatefulWidget {
  final User user;
  final _Term term;
  final Evaluation? evaluation;
  final RehireRecord? record;
  final bool initialRehire;
  final bool termStarted;

  const _RehireDecisionDialog({
    required this.user,
    required this.term,
    required this.evaluation,
    required this.record,
    required this.initialRehire,
    required this.termStarted,
  });

  @override
  State<_RehireDecisionDialog> createState() => _RehireDecisionDialogState();
}

class _RehireDecisionDialogState extends State<_RehireDecisionDialog> {
  late bool _rehire;
  String? _officeId;
  late final TextEditingController _remarksCtrl;
  bool _showRemarksError = false;

  @override
  void initState() {
    super.initState();
    _rehire = widget.initialRehire;
    _remarksCtrl = TextEditingController(text: widget.record?.remarks ?? '');
    final state = context.read<AppState>();
    final activeOffices = state.offices.where((o) => o.isActive);
    // Default to where they are now, else where the last decision put them.
    final current = state.officesForUser(widget.user).firstOrNull?.id;
    final recorded = widget.record?.officeIds.firstOrNull;
    _officeId = [current, recorded]
        .whereType<String>()
        .where((id) => activeOffices.any((o) => o.id == id))
        .firstOrNull;
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  String get _termLabel =>
      RehireRecord.termLabelFor(widget.term.academicYear, widget.term.semester);

  /// Going against the supervisor's recommendation needs a reason on record.
  bool get _overridesRecommendation {
    final eligible = widget.evaluation?.eligibleForRehire;
    if (eligible == null) return false;
    return eligible != _rehire;
  }

  void _submit() {
    if (_rehire && _officeId == null) return;
    if (_overridesRecommendation && _remarksCtrl.text.trim().isEmpty) {
      setState(() => _showRemarksError = true);
      return;
    }
    Navigator.pop(
      context,
      _DecisionResult(
        rehire: _rehire,
        officeId: _rehire ? _officeId : null,
        remarks: _remarksCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final activeOffices = state.offices.where((o) => o.isActive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final currentOffices = state.officesForUser(widget.user);
    final selectedOffice = activeOffices
        .where((o) => o.id == _officeId)
        .firstOrNull;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isMobile ? 18 : 22, 18, 10, 14),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.maroon,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Rehire decision for $_termLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppTheme.slate400,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.slate200),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 18 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _evaluationSummary(),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.autorenew_rounded, size: 16),
                            label: Text('Rehire'),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.person_off_outlined, size: 16),
                            label: Text("Don't rehire"),
                          ),
                        ],
                        selected: {_rehire},
                        onSelectionChanged: (selection) => setState(() {
                          _rehire = selection.first;
                          _showRemarksError = false;
                        }),
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: _rehire
                              ? AppTheme.maroon
                              : AppTheme.red500,
                          selectedForegroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_rehire) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _officeId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Office',
                          prefixIcon: Icon(
                            Icons.account_balance_outlined,
                            size: 19,
                          ),
                        ),
                        hint: const Text('Choose an office'),
                        items: activeOffices.map((office) {
                          final count = office.assistantIds.length;
                          final capacity = office.capacity > 0
                              ? '$count/${office.capacity}'
                              : '$count';
                          return DropdownMenuItem(
                            value: office.id,
                            child: Text(
                              '${office.name}  ($capacity assistants)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() => _officeId = value),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _remarksCtrl,
                      maxLines: 3,
                      onChanged: (_) {
                        if (_showRemarksError) {
                          setState(() => _showRemarksError = false);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: _overridesRecommendation
                            ? 'Remarks (required)'
                            : 'Remarks (optional)',
                        alignLabelWithHint: true,
                        helperText: _overridesRecommendation
                            ? 'This goes against the supervisor\'s '
                                  'recommendation, so give a reason.'
                            : null,
                        helperMaxLines: 2,
                        errorText: _showRemarksError
                            ? 'Please give a reason for this decision.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _effectNote(currentOffices, selectedOffice),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppTheme.slate200),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 18 : 22,
                12,
                isMobile ? 18 : 22,
                16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppTheme.slate500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _rehire && _officeId == null ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rehire
                          ? AppTheme.maroon
                          : AppTheme.red500,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    child: Text(_rehire ? 'Rehire' : "Don't Rehire"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _evaluationSummary() {
    final evaluation = widget.evaluation;
    if (evaluation == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.amber50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.amber500.withValues(alpha: 0.25)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.amber500),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No performance evaluation on file yet. You can ask their '
                'supervisor to evaluate them first, or decide without one.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.slate700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final eligible = evaluation.eligibleForRehire;
    final color = eligible ? AppTheme.emerald500 : AppTheme.red500;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                eligible
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_down_alt_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  eligible
                      ? 'Supervisor recommends rehiring'
                      : 'Supervisor does not recommend rehiring',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${evaluation.term}'
            '${evaluation.academicYear != null ? ', AY ${evaluation.academicYear}' : ''}'
            ' · rated by ${evaluation.supervisorName}',
            style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          const SizedBox(height: 4),
          Text(
            'Overall ${evaluation.overallRating}/10 — '
            '${EvaluationCriteria.bandLabel(evaluation.overallRating)}'
            ' · ${evaluation.verifiedDtrHours.toStringAsFixed(1)} verified '
            'DTR hrs',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
          ),
          if (evaluation.departmentHeadComments.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${evaluation.departmentHeadComments.trim()}"',
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.slate600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _effectNote(List<Office> currentOffices, Office? selectedOffice) {
    final when = widget.termStarted
        ? 'Right away'
        : 'When $_termLabel starts';
    final currentLabel = currentOffices.isEmpty
        ? 'their office'
        : currentOffices.map((o) => o.name).join(', ');
    final saId = widget.user.saId;
    final text = _rehire
        ? '$when, they continue as a student assistant'
              '${selectedOffice != null ? ' in ${selectedOffice.name}' : ''}'
              '${saId != null && saId.isNotEmpty ? ', keeping $saId' : ''}. '
              'A new Contract of Appointment for $_termLabel is generated now '
              'and filed in Student Documents.'
        : '$when, they are taken off $currentLabel and their account goes '
              'back to Student, so they stop logging hours. They can still '
              'apply again later; their SA ID and records are kept.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.subdirectory_arrow_right_rounded,
          size: 16,
          color: AppTheme.slate400,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.slate600,
            ),
          ),
        ),
      ],
    );
  }
}
