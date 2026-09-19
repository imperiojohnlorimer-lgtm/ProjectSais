import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Generates the batch "Endorsement of Student Assistants for Deployment"
/// letter (the one sent to the VP for Student Affairs and Services listing
/// every Approved applicant) by filling in the university-provided .docx
/// template (assets/templates/endorsement_template.docx).
///
/// Uses the same template-filling trick as the other document services:
/// the template's `word/document.xml` contains `{{TOKEN}}` placeholders for
/// the header/closing fields, and a single templated table row (holding
/// `{{SA_NO}}`, `{{SA_NAME}}`, `{{SA_OFFICE}}`, `{{SA_SUPERVISOR}}`) that
/// this service duplicates once per approved entry, since the number of
/// approved students varies each time — unlike the DTR report's fixed
/// 31-day table.
class EndorsementDocumentService {
  const EndorsementDocumentService();

  static const String _templateAssetPath =
      'assets/templates/endorsement_template.docx';

  Future<ApplicationDocument> generateEndorsement({
    required EndorsementData data,
  }) async {
    final templateBytes = (await rootBundle.load(_templateAssetPath))
        .buffer
        .asUint8List();

    final replacements = <String, String>{
      '{{DATE}}': data.date,
      '{{SEMESTER_LABEL}}': data.semesterLabel,
      '{{SEMESTER_LABEL_LONG}}': data.semesterLabelLong,
      '{{EFFECTIVE_PERIOD}}': data.effectivePeriod,
      '{{BATCH_LABEL}}': data.batchLabel,
      '{{VP_NAME}}': data.vpName,
      '{{CAMPUS_DIRECTOR_NAME}}': data.campusDirectorName,
      '{{HEAD_SWS_NAME}}': data.headSwsName,
      '{{PREPARED_BY_NAME}}': data.preparedByName,
      '{{PREPARED_BY_TITLE}}': data.preparedByTitle,
    };

    final docBytes = _fillTemplate(templateBytes, replacements, data.entries);

    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '');
    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: '',
      requirementName: 'Endorsement Summary',
      fileName: 'endorsement-summary-$timestamp.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description:
          'Batch endorsement of ${data.entries.length} approved Student '
          'Assistant(s) — ${data.semesterLabel}',
      fileSize: docBytes.lengthInBytes / (1024 * 1024),
      bytes: docBytes,
      storagePath: null,
      downloadUrl: null,
    );
  }

  /// Removes Word proofing/bookmark markers and merges consecutive runs
  /// that share identical formatting, so a placeholder like {{TOKEN}} that
  /// Word's spell-checker split across two runs still gets matched by a
  /// plain string replace. Same logic as the other document services.
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

  /// Finds the single `<w:tr>...</w:tr>` block holding `{{SA_NO}}` and
  /// replaces it with one row per entry (each with its own tokens filled
  /// in), so the table grows to match however many students were approved.
  String _expandEntryRows(String xml, List<EndorsementEntry> entries) {
    final rowPattern = RegExp(r'<w:tr\b[^>]*>.*?</w:tr>', dotAll: true);
    final templateRow = rowPattern
        .allMatches(xml)
        .map((m) => m.group(0)!)
        .firstWhere((row) => row.contains('{{SA_NO}}'));

    final builtRows = entries.map((entry) {
      return templateRow
          .replaceAll('{{SA_NO}}', _escapeXml(entry.saNumber))
          .replaceAll('{{SA_NAME}}', _escapeXml(entry.name))
          .replaceAll('{{SA_OFFICE}}', _escapeXml(entry.office))
          .replaceAll('{{SA_SUPERVISOR}}', _escapeXml(entry.supervisor));
    }).join();

    return xml.replaceFirst(templateRow, builtRows);
  }

  Uint8List _fillTemplate(
    Uint8List templateBytes,
    Map<String, String> replacements,
    List<EndorsementEntry> entries,
  ) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final outArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name == 'word/document.xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _normalizeRuns(xml);
        xml = _expandEntryRows(xml, entries);
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
