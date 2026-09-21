import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Generates the university's "Hourly Wage Payroll" by filling in
/// assets/templates/payroll_template.docx, which was built from the sample
/// "Payroll Summary.docx" so the letterhead, column widths, and signatory
/// block stay exactly as designed in Word.
///
/// It prints a [PayrollSheet] — the Admin's edited copy of the payroll — so
/// every header field, row and signatory comes out exactly as reviewed.
///
/// Unlike the fixed-size forms (see [DtrAccomplishmentReportDocumentService]),
/// a payroll has any number of rows, so the template holds one `{{TOKEN}}` row
/// of each kind — a summary row, a campus heading row, and a student row —
/// that are cloned as needed. Students are grouped by campus and split into
/// sheets of [rowsPerSheet] rows. As on the paper form, each sheet closes with
/// TOTAL CARRIED FORWARD and its own signatory block, the next one opens with
/// TOTAL BROUGHT FORWARD, and the last one ends with the grand TOTAL.
class PayrollDocumentService {
  const PayrollDocumentService();

  static const String _templateAssetPath =
      'assets/templates/payroll_template.docx';

  /// Campus heading plus student rows on one sheet. The sample fits 28 on its
  /// two landscape pages; 24 leaves room for the brought-forward row and for
  /// names long enough to wrap onto a second line.
  static const int rowsPerSheet = 24;

  // The sample's blank lines, kept when the Admin leaves a field empty so
  // Accounting can still write it in by hand.
  static const _payrollNoBlank = '_______________________';
  static const _fundClusterBlank = '_______________________________';

  Future<ApplicationDocument> generatePayroll({
    required PayrollSheet sheet,
  }) async {
    final templateBytes = (await rootBundle.load(
      _templateAssetPath,
    )).buffer.asUint8List();

    final docBytes = _rewriteDocument(
      templateBytes,
      (xml) => _buildPayroll(xml, sheet, _paginate(sheet.entries)),
    );

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final safePeriod = sheet.periodLabel
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .toLowerCase();
    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: 'payroll',
      requirementName: 'Hourly Wage Payroll',
      fileName:
          'hourly-wage-payroll-$safePeriod-${timestamp.replaceAll(RegExp(r'[^0-9]'), '')}.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description:
          'System-generated Hourly Wage Payroll (${sheet.periodLabel})',
      fileSize: docBytes.lengthInBytes / (1024 * 1024),
      bytes: docBytes,
      storagePath: null,
      downloadUrl: null,
    );
  }

  /// Groups the rows campus by campus (alphabetical) and splits them into
  /// sheets. Within a campus the rows keep the order the Admin sees in the
  /// editor, so the numbers match; students are numbered straight through the
  /// whole payroll, as on the paper form.
  List<List<_SheetRow>> _paginate(List<PayrollSheetEntry> entries) {
    final byCampus = <String, List<PayrollSheetEntry>>{};
    for (final entry in entries) {
      final campus = entry.campus.trim();
      byCampus
          .putIfAbsent(campus.isEmpty ? 'Unspecified Campus' : campus, () => [])
          .add(entry);
    }

    final sheets = <List<_SheetRow>>[[]];
    var number = 0;
    for (final campus in byCampus.keys.toList()..sort()) {
      final roster = byCampus[campus]!;
      for (var i = 0; i < roster.length; i++) {
        final opensCampus = i == 0;
        var sheet = sheets.last;
        // A campus heading never sits alone at the foot of a sheet: it moves
        // over together with its first student.
        if (sheet.length + (opensCampus ? 2 : 1) > rowsPerSheet) {
          sheet = <_SheetRow>[];
          sheets.add(sheet);
        }
        // Repeat the heading when a campus continues onto a new sheet, so no
        // sheet starts with students of an unnamed campus.
        if (opensCampus || sheet.isEmpty) sheet.add(_SheetRow.campus(campus));
        sheet.add(_SheetRow.student(++number, roster[i]));
      }
    }
    return sheets;
  }

  String _buildPayroll(
    String xml,
    PayrollSheet payroll,
    List<List<_SheetRow>> sheets,
  ) {
    final bodyStart = xml.indexOf('<w:body>') + '<w:body>'.length;
    final sectStart = xml.lastIndexOf('<w:sectPr');
    // One sheet runs from the heading to the end of the signatory table; the
    // closing paragraph after it (which Word requires before the section
    // properties) is written once, after the last sheet.
    final sheetEnd = xml.lastIndexOf('</w:tbl>', sectStart) + '</w:tbl>'.length;

    // Header fields and signatories read the same on every sheet, so they're
    // filled in once, before the rows are located.
    final signatories = payroll.signatories;
    final sheetTemplate = _fill(xml.substring(bodyStart, sheetEnd), {
      '{{ENTITY_NAME}}': payroll.entityName,
      '{{PAYROLL_NO}}': payroll.payrollNo.trim().isEmpty
          ? _payrollNoBlank
          : payroll.payrollNo,
      '{{FUND_CLUSTER}}': payroll.fundCluster.trim().isEmpty
          ? _fundClusterBlank
          : payroll.fundCluster,
      for (final (i, box) in const ['A', 'B', 'C', 'D'].indexed) ...{
        '{{SIG_${box}_NAME}}': signatories[i].name,
        '{{SIG_${box}_TITLE}}': signatories[i].title,
      },
    });

    final summary = _rowAround(sheetTemplate, '{{SUM_LABEL}}');
    final campus = _rowAround(sheetTemplate, '{{CAMPUS}}');
    final student = _rowAround(sheetTemplate, '{{NAME}}');
    if (summary.end != campus.start || campus.end != student.start) {
      throw StateError(
        'payroll_template.docx must keep its summary, campus and student '
        'rows together, in that order.',
      );
    }
    final summaryRow = sheetTemplate.substring(summary.start, summary.end);
    final campusRow = sheetTemplate.substring(campus.start, campus.end);
    final studentRow = sheetTemplate.substring(student.start, student.end);

    final out = StringBuffer(xml.substring(0, bodyStart));
    var totals = const _Totals();
    for (var s = 0; s < sheets.length; s++) {
      final rows = StringBuffer();
      if (s > 0) {
        rows.write(_fillSummary(summaryRow, 'TOTAL BROUGHT FORWARD', totals));
      }
      for (final row in sheets[s]) {
        final entry = row.entry;
        if (entry == null) {
          rows.write(_fill(campusRow, {'{{CAMPUS}}': row.campus!}));
          continue;
        }
        rows.write(
          _fill(studentRow, {
            '{{NO}}': '${row.number}',
            '{{NAME}}': entry.name,
            '{{DESIGNATION}}': entry.designation,
            '{{HOURS}}': _hours(entry.hoursWorked),
            '{{RATE}}': _money(entry.ratePerHour),
            '{{TOTAL}}': _money(entry.totalAmount),
            // Blank rather than zero where the sample leaves the cell empty.
            '{{UT_HRS}}': entry.undertimeHours == 0
                ? ''
                : '${entry.undertimeHours}',
            '{{UT_MINS}}': '${entry.undertimeMinutes}',
            '{{UT_AMOUNT}}': _money(entry.undertimeAmount),
            '{{GROSS}}': _money(entry.grossAmount),
            '{{TAX}}': entry.taxesWithheld == 0
                ? ''
                : _money(entry.taxesWithheld),
            '{{SSS}}': entry.sss == 0 ? '' : _money(entry.sss),
            '{{NET}}': _money(entry.netPay),
            '{{REMARKS}}': entry.remarks,
          }),
        );
        totals = totals.add(entry);
      }
      final isLast = s == sheets.length - 1;
      rows.write(
        _fillSummary(
          summaryRow,
          isLast ? 'TOTAL' : 'TOTAL CARRIED FORWARD',
          totals,
        ),
      );

      final sheet = sheetTemplate.replaceRange(
        summary.start,
        student.end,
        rows.toString(),
      );
      out.write(s == 0 ? sheet : _startOnNewPage(sheet));
    }
    out.write(xml.substring(sheetEnd));
    return out.toString();
  }

  String _fillSummary(String row, String label, _Totals totals) => _fill(row, {
    '{{SUM_LABEL}}': label,
    '{{SUM_TOTAL}}': _money(totals.total),
    '{{SUM_UT_AMOUNT}}': _money(totals.undertime),
    '{{SUM_GROSS}}': _money(totals.gross),
    '{{SUM_TAX}}': _money(totals.taxes),
    '{{SUM_SSS}}': _money(totals.sss),
    '{{SUM_NET}}': _money(totals.net),
  });

  String _fill(String xml, Map<String, String> values) {
    var filled = xml;
    values.forEach((token, value) {
      filled = filled.replaceAll(token, _escapeXml(value));
    });
    return filled;
  }

  /// The bounds of the `<w:tr>` that contains [token].
  ({int start, int end}) _rowAround(String xml, String token) {
    final at = xml.indexOf(token);
    if (at < 0) {
      throw StateError('payroll_template.docx is missing $token');
    }
    final start = [
      xml.lastIndexOf('<w:tr>', at),
      xml.lastIndexOf('<w:tr ', at),
    ].reduce((a, b) => a > b ? a : b);
    final end = xml.indexOf('</w:tr>', at) + '</w:tr>'.length;
    return (start: start, end: end);
  }

  /// Makes a sheet's heading paragraph start a new page. The template's
  /// heading has no paragraph style, so pageBreakBefore can lead its pPr.
  String _startOnNewPage(String sheet) {
    final open = RegExp(r'^<w:p(?:\s[^>]*)?>').firstMatch(sheet);
    if (open == null) return sheet;
    final rest = sheet.substring(open.end);
    return rest.startsWith('<w:pPr>')
        ? '${open[0]}<w:pPr><w:pageBreakBefore/>'
              '${rest.substring('<w:pPr>'.length)}'
        : '${open[0]}<w:pPr><w:pageBreakBefore/></w:pPr>$rest';
  }

  /// 2000 → "2,000.00".
  static String _money(double value) {
    final fixed = value.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final whole = fixed
        .substring(0, dot)
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '$whole${fixed.substring(dot)}';
  }

  /// 80 → "80", 81.5 → "81.5", 37.666… → "37.67".
  static String _hours(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

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

  Uint8List _rewriteDocument(
    Uint8List templateBytes,
    String Function(String documentXml) rewrite,
  ) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final outArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name == 'word/document.xml') {
        final xml = rewrite(
          _normalizeRuns(utf8.decode(file.content as List<int>)),
        );
        final bytes = utf8.encode(xml);
        outArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        outArchive.addFile(
          ArchiveFile(
            file.name,
            file.content.length,
            file.content as List<int>,
          ),
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

/// One table row on a sheet: either a campus heading or a numbered student.
class _SheetRow {
  final String? campus;
  final int number;
  final PayrollSheetEntry? entry;

  const _SheetRow.campus(String this.campus) : number = 0, entry = null;
  const _SheetRow.student(this.number, PayrollSheetEntry this.entry)
    : campus = null;
}

/// Running column totals, carried from sheet to sheet.
class _Totals {
  final double total;
  final double undertime;
  final double gross;
  final double taxes;
  final double sss;
  final double net;

  const _Totals({
    this.total = 0,
    this.undertime = 0,
    this.gross = 0,
    this.taxes = 0,
    this.sss = 0,
    this.net = 0,
  });

  _Totals add(PayrollSheetEntry entry) => _Totals(
    total: total + entry.totalAmount,
    undertime: undertime + entry.undertimeAmount,
    gross: gross + entry.grossAmount,
    taxes: taxes + entry.taxesWithheld,
    sss: sss + entry.sss,
    net: net + entry.netPay,
  );
}
