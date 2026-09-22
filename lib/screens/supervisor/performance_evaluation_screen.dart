import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/performance_evaluation_document_service.dart';
import '../../utils/web_download_stub.dart'
    if (dart.library.html) '../../utils/web_download.dart'
    as web_download;

/// Supervisor screen: evaluate a student assistant's performance at the
/// end of the semester, based on their verified DTR (attendance) and an
/// approved accomplishment report — mirrors the official
/// "Performance Evaluation for Student Assistants" form.
class PerformanceEvaluationScreen extends StatefulWidget {
  const PerformanceEvaluationScreen({super.key});

  static String defaultPeriodCovered(String academicYear, String term) {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(academicYear.trim());
    if (match == null) return '';

    final startYear = int.tryParse(match.group(1) ?? '') ?? 0;
    final endYear = int.tryParse(match.group(2) ?? '') ?? startYear;

    switch (term) {
      case 'First Semester':
        return 'Aug $startYear – Dec $startYear';
      case 'Midyear Term':
        return 'Jun $endYear – Jul $endYear';
      case 'Second Semester':
        return 'Jan $endYear – May $endYear';
      default:
        return '';
    }
  }

  @override
  State<PerformanceEvaluationScreen> createState() =>
      _PerformanceEvaluationScreenState();
}

class _PerformanceEvaluationScreenState
    extends State<PerformanceEvaluationScreen> {
  String _search = '';
  String _term = 'First Semester';

  static const _terms = ['First Semester', 'Midyear Term', 'Second Semester'];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    final allForTerm = state.filteredStudents;
    final students = allForTerm.where((s) {
      final q = _search.trim().toLowerCase();
      return q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.department.toLowerCase().contains(q);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final submittedCount = allForTerm
        .where((s) => state.existingEvaluationFor(s.name, _term) != null)
        .length;

    final evaluatedFraction = allForTerm.isEmpty
        ? 0.0
        : submittedCount / allForTerm.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: HeroBanner(
            isMobile: isMobile,
            icon: Icons.fact_check_rounded,
            title: 'Performance Evaluation',
            subtitle:
                'Evaluate student assistants from their verified DTR and '
                'approved reports',
            searchHint: 'Search by name or department...',
            onSearch: (value) => setState(() => _search = value),
            filters: [_termFilter()],
            stats: [
              HeroStatData(
                label: 'Assistants',
                value: '${allForTerm.length}',
                icon: Icons.groups_rounded,
              ),
              HeroStatData(
                label: 'Evaluated',
                value: '$submittedCount',
                icon: Icons.check_circle_rounded,
              ),
              HeroStatData(
                label: 'Remaining',
                value: '${allForTerm.length - submittedCount}',
                icon: Icons.pending_actions_rounded,
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
                if (allForTerm.isNotEmpty) ...[
                  ProgressStrip(
                    label: 'Evaluated',
                    icon: Icons.how_to_reg_rounded,
                    progress: evaluatedFraction,
                    trailing: '$submittedCount/${allForTerm.length}',
                  ),
                  const SizedBox(height: 14),
                ],
                if (students.isEmpty)
                  _emptyState(allForTerm.isEmpty)
                else
                  for (final student in students)
                    _studentCard(context, state, student),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Term picker, sized to sit in the header toolbar beside the search box.
  Widget _termFilter() => Container(
    height: 40,
    constraints: const BoxConstraints(minWidth: 190),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.slate200),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _term,
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
        items: _terms
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (v) => setState(() => _term = v ?? _term),
      ),
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
              Icons.fact_check_outlined,
              size: 36,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            noneAtAll
                ? 'No student assistants to evaluate'
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
              'Try a different name, department or term.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.slate400),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _studentCard(BuildContext context, AppState state, Student student) {
    final verifiedHours = state.verifiedDtrHoursForStudent(student.name);
    final approvedReports = state.approvedReportsForStudent(student.name);
    final existing = state.existingEvaluationFor(student.name, _term);
    final hasBasis = verifiedHours > 0 && approvedReports.isNotEmpty;

    final railColor = existing != null ? AppTheme.emerald500 : AppTheme.maroon;

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
        // Evaluated/not reads from a rail down the side instead of a
        // gradient band across the top. The rail is positioned rather than
        // a Row child because the card sits in a scroll view, where a
        // stretching Row would hand it an unbounded height.
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
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.maroon50,
                        child: Text(
                          student.initials,
                          style: const TextStyle(
                            color: AppTheme.maroon,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate900,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.apartment_rounded,
                                  size: 12,
                                  color: AppTheme.slate400,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    student.department,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.slate400,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (existing != null) _statusPill(existing.status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _basisChip(
                        icon: Icons.access_time_filled_rounded,
                        label:
                            'Verified DTR: ${verifiedHours.toStringAsFixed(1)} hrs',
                        ok: verifiedHours > 0,
                      ),
                      _basisChip(
                        icon: Icons.description_rounded,
                        label: 'Approved Reports: ${approvedReports.length}',
                        ok: approvedReports.isNotEmpty,
                      ),
                    ],
                  ),
                  if (!hasBasis) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.amber50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.amber500.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppTheme.amber500,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'A verified DTR and at least one approved accomplishment '
                              'report give this evaluation a stronger basis, but you may '
                              'still proceed.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: AppTheme.amber500.withValues(
                                  alpha: 0.95,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (_, constraints) {
                      // Three buttons don't fit on one line on a phone, so
                      // there the secondary actions pair up above a
                      // full-width primary button instead of running off the
                      // edge of the card.
                      final compact = constraints.maxWidth < 480;
                      final buttonPadding = EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 16,
                        vertical: 11,
                      );
                      final buttonShape = RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      );
                      Widget label(String text) {
                        final t = Text(
                          text,
                          maxLines: 1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        );
                        // Shrink rather than clip when half a phone-width
                        // button is still too narrow for the label.
                        return compact
                            ? FittedBox(fit: BoxFit.scaleDown, child: t)
                            : t;
                      }

                      final downloadButton = existing == null
                          ? null
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  _downloadEvaluation(context, existing),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 16,
                              ),
                              label: label('Download'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.maroon,
                                side: const BorderSide(
                                  color: AppTheme.maroon,
                                  width: 1.3,
                                ),
                                padding: buttonPadding,
                                shape: buttonShape,
                              ),
                            );
                      final sendButton = existing?.status != 'Submitted'
                          ? null
                          : OutlinedButton.icon(
                              onPressed: existing!.sentToHead
                                  ? null
                                  : () => _sendEvaluationToHead(
                                      context,
                                      state,
                                      existing,
                                    ),
                              icon: Icon(
                                existing.sentToHead
                                    ? Icons.check_circle_rounded
                                    : Icons.send_rounded,
                                size: 16,
                              ),
                              label: label(
                                existing.sentToHead
                                    ? 'Sent to Head'
                                    : 'Send to Head',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: existing.sentToHead
                                    ? AppTheme.emerald500
                                    : AppTheme.maroon,
                                disabledForegroundColor: AppTheme.emerald500,
                                side: BorderSide(
                                  color: existing.sentToHead
                                      ? AppTheme.emerald500
                                      : AppTheme.maroon,
                                  width: 1.3,
                                ),
                                padding: buttonPadding,
                                shape: buttonShape,
                              ),
                            );
                      final primaryButton = ElevatedButton.icon(
                        onPressed: () => _openEvaluationForm(
                          context,
                          state,
                          student,
                          existing,
                          verifiedHours,
                          approvedReports.length,
                        ),
                        icon: Icon(
                          existing == null
                              ? Icons.rate_review_rounded
                              : Icons.edit_rounded,
                          size: 16,
                        ),
                        label: label(
                          existing == null
                              ? 'Evaluate'
                              : 'View / Edit Evaluation',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: buttonPadding,
                          shape: buttonShape,
                        ),
                      );
                      final secondary = [?downloadButton, ?sendButton];

                      if (!compact) {
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [...secondary, primaryButton],
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (secondary.isNotEmpty) ...[
                            Row(
                              children: [
                                for (var i = 0; i < secondary.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 8),
                                  Expanded(child: secondary[i]),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          primaryButton,
                        ],
                      );
                    },
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

  Widget _basisChip({
    required IconData icon,
    required String label,
    required bool ok,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: ok ? AppTheme.emerald50 : AppTheme.slate50,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: ok
            ? AppTheme.emerald500.withValues(alpha: 0.2)
            : AppTheme.slate200,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: ok ? AppTheme.emerald500 : AppTheme.slate400,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: ok ? AppTheme.emerald500 : AppTheme.slate400,
          ),
        ),
      ],
    ),
  );

  Widget _statusPill(String status) {
    final color = status == 'Submitted'
        ? AppTheme.emerald500
        : AppTheme.amber500;
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
          Icon(Icons.check_circle_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            status,
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

  Future<void> _downloadEvaluation(
    BuildContext context,
    Evaluation evaluation,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await const PerformanceEvaluationDocumentService()
          .generatePerformanceEvaluation(evaluation: evaluation);
      final bytes = doc.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to generate the evaluation document.');
      }

      if (kIsWeb) {
        web_download.WebDownloadUtils.downloadBytes(doc.fileName, bytes);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Downloading ${doc.fileName}...'),
            backgroundColor: AppTheme.emerald500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      final uri = Uri.dataFromBytes(
        bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        parameters: {'filename': doc.fileName},
      );
      final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!opened) throw Exception('The browser could not open the document.');
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

  Future<void> _sendEvaluationToHead(
    BuildContext context,
    AppState state,
    Evaluation evaluation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Send to Head?'),
        content: Text(
          'This will send ${evaluation.studentName}\'s performance evaluation '
          '(${evaluation.term}) to the Head. This can\'t be undone.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.maroon,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    bool ok = false;
    String? errorText;
    try {
      ok = await state.sendEvaluationToHead(evaluation);
    } catch (e) {
      errorText = '$e';
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Evaluation sent to Head'
              : 'Failed to send evaluation to Head'
                    '${errorText != null ? ': $errorText' : ''}',
        ),
        backgroundColor: ok ? AppTheme.emerald500 : AppTheme.red500,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _openEvaluationForm(
    BuildContext context,
    AppState state,
    Student student,
    Evaluation? existing,
    double verifiedHours,
    int approvedReportCount,
  ) {
    showDialog(
      context: context,
      builder: (_) => _EvaluationFormDialog(
        student: student,
        term: _term,
        existing: existing,
        verifiedHours: verifiedHours,
        approvedReportCount: approvedReportCount,
      ),
    );
  }
}

class _EvaluationFormDialog extends StatefulWidget {
  final Student student;
  final String term;
  final Evaluation? existing;
  final double verifiedHours;
  final int approvedReportCount;

  const _EvaluationFormDialog({
    required this.student,
    required this.term,
    required this.existing,
    required this.verifiedHours,
    required this.approvedReportCount,
  });

  @override
  State<_EvaluationFormDialog> createState() => _EvaluationFormDialogState();
}

class _EvaluationFormDialogState extends State<_EvaluationFormDialog> {
  late Map<String, int> _ratings;
  late TextEditingController _periodCtrl;
  late TextEditingController _commentsCtrl;
  late bool _eligibleForRehire;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final state = context.read<AppState>();
    _ratings = {
      for (final key in EvaluationCriteria.keys)
        key: existing?.ratings[key] ?? 6,
    };
    final autoPeriod =
        existing?.periodCovered ??
        PerformanceEvaluationScreen.defaultPeriodCovered(
          state.academicYear,
          widget.term,
        );
    _periodCtrl = TextEditingController(text: autoPeriod);
    _commentsCtrl = TextEditingController(
      text: existing?.departmentHeadComments ?? '',
    );
    _eligibleForRehire = existing?.eligibleForRehire ?? true;
  }

  @override
  void dispose() {
    _periodCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  int get _overall {
    final sum = _ratings.values.fold<int>(0, (a, b) => a + b);
    return (sum / _ratings.length).round();
  }

  Color get _overallColor {
    if (_overall >= 9) return AppTheme.emerald500;
    if (_overall >= 7) return AppTheme.blue500;
    if (_overall >= 5) return AppTheme.amber500;
    return AppTheme.red500;
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final periodCovered = _periodCtrl.text.trim();
    if (periodCovered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter the period covered.'),
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

    setState(() => _saving = true);

    final evaluation = Evaluation(
      id: widget.existing?.id ?? '',
      studentId: widget.student.id,
      studentName: widget.student.name,
      office: widget.student.department,
      term: widget.term,
      periodCovered: periodCovered,
      dateOfRating: DateTime.now().toIso8601String().split('T').first,
      eligibleForRehire: _eligibleForRehire,
      ratings: _ratings,
      overallRating: _overall,
      departmentHeadComments: _commentsCtrl.text.trim(),
      supervisorId: state.currentUser?.id ?? '',
      supervisorName: state.currentUser?.name ?? 'Supervisor',
      verifiedDtrHours: widget.verifiedHours,
      approvedReportCount: widget.approvedReportCount,
      status: 'Submitted',
    );

    final ok = await state.saveEvaluation(evaluation);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Evaluation saved for ${widget.student.name}'
              : 'Failed to save evaluation',
        ),
        backgroundColor: ok ? AppTheme.emerald500 : AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 18 : 24,
                  20,
                  isMobile ? 12 : 16,
                  18,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.maroon, AppTheme.maroonDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.rate_review_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.student.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.term} • ${widget.student.department}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 18 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _basisSummary(),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _periodCtrl,
                        decoration: InputDecoration(
                          labelText: 'Period Covered',
                          hintText: 'e.g. Aug 2026 – Dec 2026',
                          prefixIcon: const Icon(
                            Icons.date_range_rounded,
                            size: 19,
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
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppTheme.maroon,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: AppTheme.slate400,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Rate each area from 1 (Consistently Below '
                              'Expectations) to 10 (Exceptional), based on the '
                              'verified DTR and approved accomplishment report above.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.slate500,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        decoration: BoxDecoration(
                          color: AppTheme.slate50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: Column(
                          children: EvaluationCriteria.keys
                              .map(_ratingRow)
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _overallColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _overallColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            const Text(
                              'Overall Evaluation',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slate900,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _overallColor,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: _overallColor.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '$_overall — ${EvaluationCriteria.bandLabel(_overall)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.slate50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          value: _eligibleForRehire,
                          onChanged: (v) =>
                              setState(() => _eligibleForRehire = v),
                          title: const Text(
                            'Eligible for Rehire',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate800,
                            ),
                          ),
                          subtitle: const Text(
                            'The Head sees this when deciding whether to '
                            'rehire them for the next term.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.slate500,
                            ),
                          ),
                          activeColor: AppTheme.maroon,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _commentsCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: "Department Head's Comments (optional)",
                          alignLabelWithHint: true,
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
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppTheme.maroon,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 18 : 24,
                  14,
                  isMobile ? 18 : 24,
                  isMobile ? 18 : 22,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.slate100)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.maroon.withValues(alpha: 0.3),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.check_circle_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Save Evaluation',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
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

  Widget _basisSummary() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.blue50, AppTheme.blue50.withValues(alpha: 0.4)],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.blue500.withValues(alpha: 0.15)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.verified_rounded,
            size: 16,
            color: AppTheme.blue500,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Basis: ${widget.verifiedHours.toStringAsFixed(1)} verified DTR '
            'hrs • ${widget.approvedReportCount} approved accomplishment '
            'report(s)',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.slate700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Color _bandColor(int value) {
    if (value >= 9) return AppTheme.emerald500;
    if (value >= 7) return AppTheme.blue500;
    if (value >= 5) return AppTheme.amber500;
    return AppTheme.red500;
  }

  Widget _ratingRow(String key) {
    final value = _ratings[key]!;
    final color = _bandColor(value);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$value — ${EvaluationCriteria.bandLabel(value)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The label is a full sentence-length description, so it's kept
          // on its own line rather than sharing a Row with the badge — on
          // narrow screens that used to squeeze the paragraph down and
          // leave the badge floating awkwardly beside a mid-wrap line.
          Text(
            EvaluationCriteria.labels[key] ?? key,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: badge),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: AppTheme.slate200,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.15),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '$value',
              onChanged: (v) => setState(() => _ratings[key] = v.round()),
            ),
          ),
        ],
      ),
    );
  }
}
