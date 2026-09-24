import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/dtr_accomplishment_report.dart';
import 'package:projectsais/services/dtr_accomplishment_report_document_service.dart';

/// Reads the generated .docx back out as the text Word would render, so a
/// test can assert on what actually lands on the page rather than on the
/// bytes we happened to pass in.
String _documentXml(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final part = archive.firstWhere((f) => f.name == 'word/document.xml');
  return utf8.decode(part.content as List<int>);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // loads the template asset

  test('sign-off names reach the generated document', () async {
    final doc = await const DtrAccomplishmentReportDocumentService()
        .generateDtrAccomplishmentReport(
          data: const DtrAccomplishmentReportData(
            studentId: 'student_1',
            studentName: 'Charlie A. Matining',
            department: 'Registrar',
            studentSignatureName: 'EDITED STUDENT NAME',
            supervisorName: 'EDITED SUPERVISOR NAME',
            approverName: 'EDITED APPROVER NAME',
            monthYearLabel: 'September 01–30, 2026',
            days: [],
            classSchedule: [],
          ),
        );

    final xml = _documentXml(doc.bytes!);

    // The three sign-off names the supervisor types must be substituted.
    expect(xml, contains('EDITED STUDENT NAME'));
    expect(xml, contains('EDITED SUPERVISOR NAME'));
    expect(xml, contains('EDITED APPROVER NAME'));

    // And no placeholder may survive into the finished document — a
    // leftover {{TOKEN}} is exactly what an edit "not changing" looks like.
    final leftovers = RegExp(r'\{\{[A-Z0-9_]+\}\}')
        .allMatches(xml)
        .map((m) => m.group(0)!)
        .toSet();
    expect(leftovers, isEmpty, reason: 'unreplaced tokens: $leftovers');
  });
}
