import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Generates the "Student Assistant's DTR/Accomplishment Report/Class
/// Schedule" document by filling in the university-provided .docx template
/// (assets/templates/dtr_accomplishment_report_template.docx) rather than
/// hand-building OOXML. This preserves the letterhead, table borders, and
/// fonts exactly as designed in Word.
///
/// Uses the same template-filling trick as [PerformanceEvaluationDocumentService]
/// / [AppointmentDocumentService]: the template's `word/document.xml`
/// contains `{{TOKEN}}` placeholders, which are swapped for real values via
/// a straight (XML-escaped) string replace on the unzipped document part,
/// then the docx is re-zipped.
///
/// The template has a fixed 31-day table (unused trailing days for shorter
/// months are simply left blank) and a fixed 12-row weekly class-schedule
/// grid, matching the official form.
class DtrAccomplishmentReportDocumentService {
  const DtrAccomplishmentReportDocumentService();

  static const String _templateAssetPath =
      'assets/templates/dtr_accomplishment_report_template.docx';

  Future<ApplicationDocument> generateDtrAccomplishmentReport({
    required DtrAccomplishmentReportData data,
  }) async {
    final templateBytes = (await rootBundle.load(_templateAssetPath))
        .buffer
        .asUint8List();

    final replacements = <String, String>{
      '{{STUDENT_NAME}}': data.studentName,
      '{{DEPARTMENT}}': data.department,
      '{{MONTH_YEAR}}': data.monthYearLabel,
      '{{TOTAL_HOURS}}': data.totalHours.toStringAsFixed(1),
      '{{TOTAL_UNITS}}': data.totalUnits,
      '{{STUDENT_SIG_NAME}}': data.studentSignatureName,
      '{{SUPERVISOR_SIG_NAME}}': data.supervisorName,
      '{{ADMIN_SIG_NAME}}': data.adminName,
    };

    // 31 fixed day rows — days beyond the selected month's length are
    // simply blanked out.
    for (var day = 1; day <= 31; day++) {
      final row = data.days.length >= day ? data.days[day - 1] : null;
      replacements['{{D${day}_AMIN}}'] = row?.amIn ?? '';
      replacements['{{D${day}_AMOUT}}'] = row?.amOut ?? '';
      replacements['{{D${day}_PMIN}}'] = row?.pmIn ?? '';
      replacements['{{D${day}_PMOUT}}'] = row?.pmOut ?? '';
      replacements['{{D${day}_TOTAL}}'] =
          row?.totalHours == null ? '' : row!.totalHours!.toStringAsFixed(1);
      replacements['{{D${day}_NOTE}}'] = row?.note ?? '';
    }

    // 12 fixed weekly-class-schedule rows (the template's table has 12
    // physical rows — see dtr_accomplishment_report_template.docx).
    for (var i = 1; i <= 12; i++) {
      final row = data.classSchedule.length >= i
          ? data.classSchedule[i - 1]
          : null;
      replacements['{{SCHED${i}_COURSE}}'] = row?.course ?? '';
      replacements['{{SCHED${i}_UNITS}}'] = row?.units ?? '';
      replacements['{{SCHED${i}_MON}}'] = row?.monday ?? '';
      replacements['{{SCHED${i}_TUE}}'] = row?.tuesday ?? '';
      replacements['{{SCHED${i}_WED}}'] = row?.wednesday ?? '';
      replacements['{{SCHED${i}_THU}}'] = row?.thursday ?? '';
      replacements['{{SCHED${i}_FRI}}'] = row?.friday ?? '';
      replacements['{{SCHED${i}_SAT}}'] = row?.saturday ?? '';
    }

    final docBytes = _fillTemplate(templateBytes, replacements);

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final safeName = data.studentName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .toLowerCase();
    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: data.studentId,
      requirementName: 'DTR/Accomplishment Report',
      fileName:
          'dtr-accomplishment-report-$safeName-${timestamp.replaceAll(RegExp(r'[^0-9]'), '')}.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description:
          'System-generated DTR/Accomplishment Report (${data.monthYearLabel})',
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

  Uint8List _fillTemplate(
    Uint8List templateBytes,
    Map<String, String> replacements,
  ) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final outArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name == 'word/document.xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _normalizeRuns(xml);
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