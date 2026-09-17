import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../services/performance_evaluation_document_service.dart';
import '../../utils/web_download_stub.dart'
    if (dart.library.html) '../../utils/web_download.dart' as web_download;

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
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final submittedCount = allForTerm
        .where((s) => state.existingEvaluationFor(s.name, _term) != null)
        .length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.slate50, Colors.white],
          stops: [0.0, 0.25],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
            child: _header(allForTerm.length, submittedCount),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _termDropdown(),
                      const SizedBox(height: 10),
                      _searchField(),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(width: 230, child: _termDropdown()),
                      const SizedBox(width: 12),
                      Expanded(child: _searchField()),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: students.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
                    itemCount: students.length,
                    itemBuilder: (context, i) =>
                        _studentCard(context, state, students[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(int total, int submitted) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppTheme.maroon, AppTheme.maroonDark],
              ).createShader(bounds),
              child: const Text(
                'Performance Evaluation',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Evaluate student assistants based on verified DTR and an '
              'approved accomplishment report',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.slate500,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      if (total > 0) _progressBadge(total, submitted),
    ],
  );

  Widget _progressBadge(int total, int submitted) {
    final pct = total == 0 ? 0.0 : submitted / total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 3.5,
                  backgroundColor: AppTheme.slate100,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.emerald500),
                ),
                Text(
                  '${(pct * 100).round()}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$submitted / $total',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                ),
              ),
              const Text(
                'evaluated',
                style: TextStyle(fontSize: 10.5, color: AppTheme.slate400),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _termDropdown() => DropdownButtonFormField<String>(
    initialValue: _term,
    icon: const Icon(Icons.expand_more_rounded, color: AppTheme.slate400),
    decoration: InputDecoration(
      labelText: 'Term',
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
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
    items: _terms
        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
        .toList(),
    onChanged: (v) => setState(() => _term = v ?? _term),
  );

  Widget _searchField() => TextField(
    onChanged: (v) => setState(() => _search = v),
    decoration: InputDecoration(
      hintText: 'Search student assistant by name or department...',
      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.slate400),
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
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.slate100, AppTheme.slate50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              size: 38,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No student assistants found',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try a different search term or switch the selected term.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.slate400),
          ),
        ],
      ),
    ),
  );

  Widget _studentCard(BuildContext context, AppState state, Student student) {
    final verifiedHours = state.verifiedDtrHoursForStudent(student.name);
    final approvedReports = state.approvedReportsForStudent(student.name);
    final existing = state.existingEvaluationFor(student.name, _term);
    final hasBasis = verifiedHours > 0 && approvedReports.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: existing != null ? AppTheme.emerald500.withValues(alpha: 0.25) : AppTheme.slate200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent top strip
            Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: existing != null
                      ? [AppTheme.emerald500, AppTheme.emerald500.withValues(alpha: 0.5)]
                      : [AppTheme.maroon, AppTheme.gold],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppTheme.maroon, AppTheme.maroonLight],
                          ),
                        ),
                        child: CircleAvatar(
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
                                const Icon(Icons.apartment_rounded, size: 12, color: AppTheme.slate400),
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
                        label: 'Verified DTR: ${verifiedHours.toStringAsFixed(1)} hrs',
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.amber50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.amber500.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.amber500),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'A verified DTR and at least one approved accomplishment '
                              'report give this evaluation a stronger basis, but you may '
                              'still proceed.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: AppTheme.amber500.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (existing != null) ...[
                        OutlinedButton.icon(
                          onPressed: () => _downloadEvaluation(context, existing),
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text(
                            'Download',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.maroon,
                            side: const BorderSide(color: AppTheme.maroon, width: 1.3),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (existing.status == 'Submitted')
                          OutlinedButton.icon(
                            onPressed: existing.sentToHead
                                ? null
                                : () => _sendEvaluationToHead(context, state, existing),
                            icon: Icon(
                              existing.sentToHead
                                  ? Icons.check_circle_rounded
                                  : Icons.send_rounded,
                              size: 16,
                            ),
                            label: Text(
                              existing.sentToHead ? 'Sent to Head' : 'Send to Head',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.maroon.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () => _openEvaluationForm(
                            context,
                            state,
                            student,
                            existing,
                            verifiedHours,
                            approvedReports.length,
                          ),
                          icon: Icon(
                            existing == null ? Icons.rate_review_rounded : Icons.edit_rounded,
                            size: 16,
                          ),
                          label: Text(
                            existing == null ? 'Evaluate' : 'View / Edit Evaluation',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.maroon,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
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
        color: ok ? AppTheme.emerald500.withValues(alpha: 0.2) : AppTheme.slate200,
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
    final color = status == 'Submitted' ? AppTheme.emerald500 : AppTheme.amber500;
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not generate document: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
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
    final autoPeriod = existing?.periodCovered ??
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
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
          ok ? 'Evaluation saved for ${widget.student.name}' : 'Failed to save evaluation',
        ),
        backgroundColor: ok ? AppTheme.emerald500 : AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
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
                padding: EdgeInsets.fromLTRB(isMobile ? 18 : 24, 20, isMobile ? 12 : 16, 18),
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
                      child: const Icon(Icons.rate_review_rounded, color: Colors.white, size: 20),
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
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                          prefixIcon: const Icon(Icons.date_range_rounded, size: 19),
                          filled: true,
                          fillColor: AppTheme.slate50,
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
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.tune_rounded, size: 16, color: AppTheme.slate400),
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
                          children: EvaluationCriteria.keys.map(_ratingRow).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _overallColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _overallColor.withValues(alpha: 0.25)),
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
                                    color: _overallColor.withValues(alpha: 0.35),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(isMobile ? 18 : 24, 14, isMobile ? 18 : 24, isMobile ? 18 : 22),
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
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
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
          child: const Icon(Icons.verified_rounded, size: 16, color: AppTheme.blue500),
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
              onChanged: (v) =>
                  setState(() => _ratings[key] = v.round()),
            ),
          ),
        ],
      ),
    );
  }
}