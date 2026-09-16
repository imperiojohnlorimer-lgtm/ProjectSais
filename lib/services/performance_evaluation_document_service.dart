import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Generates the "Performance Evaluation for Student Assistants" document
/// by filling in the *actual* university-provided .docx template
/// (assets/templates/performance_evaluation_template.docx) rather than
/// hand-building OOXML. This preserves the letterhead, logo, footer, fonts,
/// and the rating-grid table layout exactly as designed in Word.
///
/// Uses the same template-filling trick as [AppointmentDocumentService]:
/// the template's `word/document.xml` contains `{{TOKEN}}` placeholders,
/// which are swapped for real values via a straight (XML-escaped) string
/// replace on the unzipped document part, then the docx is re-zipped.
class PerformanceEvaluationDocumentService {
  const PerformanceEvaluationDocumentService();

  static const String _templateAssetPath =
      'assets/templates/performance_evaluation_template.docx';

  /// The 5 rating-band columns on the form, left to right, matching the
  /// `_C1..._C5` token suffixes baked into the template table.
  static const List<_Band> _bands = [
    _Band(minScore: 9, maxScore: 10, column: 1), // 10-9 Exceptional
    _Band(minScore: 7, maxScore: 8, column: 2), // 8-7 Exceeds Expectations
    _Band(minScore: 5, maxScore: 6, column: 3), // 6-5 Meets Expectations
    _Band(minScore: 3, maxScore: 4, column: 4), // 4-3 Improvement Needed
    _Band(minScore: 1, maxScore: 2, column: 5), // 2-1 Consistently Below
  ];

  static String termCheckMark(String term, String targetTerm) {
    return term == targetTerm ? '☒' : '☐';
  }

  static String commentXml(String value, {String rPr = ''}) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final rPrXml = rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>';

    if (lines.length <= 1) {
      return '<w:r>$rPrXml<w:t xml:space="preserve">${_escapeXml(lines.first)}</w:t></w:r>';
    }

    // Each line becomes its own run; line breaks use <w:br/> as a *sibling*
    // of <w:t> inside its own run, since <w:br/> cannot legally live inside
    // a <w:t> element. Never splice this into the middle of another <w:t>.
    final breakRun = '<w:r>$rPrXml<w:br/></w:r>';
    return lines
        .map((line) =>
            '<w:r>$rPrXml<w:t xml:space="preserve">${_escapeXml(line)}</w:t></w:r>')
        .join(breakRun);
  }

  Future<ApplicationDocument> generatePerformanceEvaluation({
    required Evaluation evaluation,
  }) async {
    final templateBytes = (await rootBundle.load(_templateAssetPath))
        .buffer
        .asUint8List();

    final replacements = <String, String>{
      '{{STUDENT_NAME}}': evaluation.studentName,
      '{{OFFICE_DEPT}}': evaluation.office,
      '{{PERIOD_COVERED}}': evaluation.periodCovered,
      '{{DATE_OF_RATING}}': evaluation.dateOfRating,
      '{{ELIGIBLE_YES_MARK}}': evaluation.eligibleForRehire ? '☒' : '☐',
      '{{ELIGIBLE_NO_MARK}}': evaluation.eligibleForRehire ? '☐' : '☒',
      '{{MARK_FIRST}}': termCheckMark(evaluation.term, 'First Semester'),
      '{{MARK_MIDYEAR}}': termCheckMark(evaluation.term, 'Midyear Term'),
      '{{MARK_SECOND}}': termCheckMark(evaluation.term, 'Second Semester'),
      '{{SUPERVISOR_NAME}}': evaluation.supervisorName,
    };

    // Rating grid: for each criterion + overall, mark the single column
    // matching its score with the score itself, and blank the rest.
    const rowKeys = {
      'schedule': 'SCHEDULE',
      'assignedWork': 'ASSIGNEDWORK',
      'initiative': 'INITIATIVE',
      'quality': 'QUALITY',
      'cooperation': 'COOPERATION',
      'attitude': 'ATTITUDE',
      'workLifeBalance': 'WORKLIFEBALANCE',
    };
    rowKeys.forEach((criterionKey, tokenPrefix) {
      final score = evaluation.ratings[criterionKey] ?? 0;
      _fillRowTokens(replacements, tokenPrefix, score);
    });
    _fillRowTokens(replacements, 'OVERALL', evaluation.overallRating);

    final docBytes = _fillTemplate(
      templateBytes,
      replacements,
      evaluation.departmentHeadComments,
    );

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final safeName = evaluation.studentName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .toLowerCase();
    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: evaluation.id.isNotEmpty ? evaluation.id : evaluation.studentId,
      requirementName: 'Performance Evaluation',
      fileName:
          'performance-evaluation-$safeName-${timestamp.replaceAll(RegExp(r'[^0-9]'), '')}.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description:
          'System-generated Performance Evaluation (${evaluation.term})',
      fileSize: docBytes.lengthInBytes / (1024 * 1024),
      bytes: docBytes,
      storagePath: null,
      downloadUrl: null,
    );
  }

  void _fillRowTokens(
    Map<String, String> replacements,
    String tokenPrefix,
    int score,
  ) {
    final band = _bands.firstWhere(
      (b) => score >= b.minScore && score <= b.maxScore,
      orElse: () => _bands.last,
    );
    for (final b in _bands) {
      final token = '{{${tokenPrefix}_C${b.column}}}';
      replacements[token] = b.column == band.column ? score.toString() : '';
    }
  }

  /// Removes Word proofing/bookmark markers and merges consecutive runs
  /// that share identical formatting, so a placeholder like {{TOKEN}} that
  /// Word's spell-checker split across two runs still gets matched by a
  /// plain string replace. Same logic as AppointmentDocumentService.
  String _normalizeRuns(String xml) {
    var normalized = xml
        .replaceAll(RegExp(r'<w:proofErr[^>]*/>'), '')
        .replaceAll(RegExp(r'<w:bookmarkStart[^>]*/>'), '')
        .replaceAll(RegExp(r'<w:bookmarkEnd[^>]*/>'), '');

    final pairPattern = RegExp(
      r'<w:r(?: [^>]*)?><w:rPr>(.*?)</w:rPr><w:t([^>]*)>([^<]*)</w:t></w:r>'
      r'<w:r(?: [^>]*)?><w:rPr>(.*?)</w:rPr><w:t([^>]*)>([^<]*)</w:t></w:r>',
    );

    for (var i = 0; i < 10; i++) {
      var changed = false;
      final merged = normalized.replaceAllMapped(pairPattern, (match) {
        final rpr1 = match.group(1)!;
        final text1 = match.group(3)!;
        final rpr2 = match.group(4)!;
        final text2 = match.group(6)!;
        if (rpr1 != rpr2) return match.group(0)!;
        changed = true;
        return '<w:r><w:rPr>$rpr1</w:rPr>'
            '<w:t xml:space="preserve">$text1$text2</w:t></w:r>';
      });
      normalized = merged;
      if (!changed) break;
    }

    return normalized;
  }

  /// Swaps the *entire* `<w:r>...<w:t>{{DEPT_HEAD_COMMENTS}}</w:t></w:r>` run
  /// for one or more runs holding the comment text.
  ///
  /// This token can't be handled with a plain string replace like the
  /// others: a multi-line comment needs `<w:br/>` line-break elements,
  /// which are only legal as a *sibling* of `<w:t>` inside a `<w:r>`, never
  /// nested inside a `<w:t>` itself. The previous version spliced
  /// `<w:r><w:t>...</w:t></w:r>` markup directly into the middle of the
  /// template's existing `<w:t>{{DEPT_HEAD_COMMENTS}}</w:t>`, producing
  /// invalid, nested `<w:t>` elements — which is what Word was rendering as
  /// garbled/mangled text for multi-line comments. Matching and replacing
  /// the whole run (and reusing its original `<w:rPr>` formatting) keeps
  /// the XML valid regardless of how many lines the comment has.
  String _replaceCommentsRun(String xml, String comments) {
    final pattern = RegExp(
      r'<w:r(?: [^>]*)?><w:rPr>(.*?)</w:rPr><w:t[^>]*>\{\{DEPT_HEAD_COMMENTS\}\}</w:t></w:r>',
    );
    return xml.replaceAllMapped(pattern, (match) {
      final rPr = match.group(1)!;
      if (comments.isEmpty) {
        return '<w:r><w:rPr>$rPr</w:rPr><w:t xml:space="preserve"> </w:t></w:r>';
      }
      return commentXml(comments, rPr: rPr);
    });
  }

  Uint8List _fillTemplate(
    Uint8List templateBytes,
    Map<String, String> replacements,
    String comments,
  ) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final outArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name == 'word/document.xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _normalizeRuns(xml);
        xml = _replaceCommentsRun(xml, comments);
        replacements.forEach((token, value) {
          xml = xml.replaceAll(token, _escapeXml(value));
        });
        final bytes = utf8.encode(xml);
        outArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        outArchive.addFile(
          ArchiveFile(file.name, file.content.length, file.content as List<int>),
        );
      }
    }

    final encoded = ZipEncoder().encode(outArchive);
    return Uint8List.fromList(encoded);
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _Band {
  final int minScore;
  final int maxScore;
  final int column;
  const _Band({required this.minScore, required this.maxScore, required this.column});
}