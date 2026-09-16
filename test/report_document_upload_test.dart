import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';

void main() {
  test('Report keeps uploaded document metadata', () {
    final report = Report.fromJson({
      'id': 'r_123',
      'title': 'Weekly report',
      'content': 'Completed tasks',
      'studentName': 'John Doe',
      'status': 'Pending',
      'attachments': [
        {
          'fileName': 'weekly-report.pdf',
          'storagePath': 'reports/r_123/weekly-report.pdf',
          'fileSize': 245000,
        },
      ],
    });

    expect(report.attachments, isNotEmpty);
    expect(report.attachments.first.fileName, 'weekly-report.pdf');
    expect(report.attachments.first.storagePath, contains('reports/r_123'));
  });

  test('ApplicationDocument omits raw bytes from Firestore payloads', () {
    final doc = ApplicationDocument(
      id: 'appdoc_1',
      applicationId: 'app_1',
      requirementName: 'Resume',
      fileName: 'resume.pdf',
      uploadedAt: 'Aug 31, 2026',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      storagePath: 'applications/app_1/resume.pdf',
      downloadUrl: 'https://example.com/resume.pdf',
    );

    final json = doc.toJson();

    expect(json.containsKey('bytes'), isFalse);
    expect(json['storagePath'], 'applications/app_1/resume.pdf');
    expect(json['downloadUrl'], 'https://example.com/resume.pdf');
  });
}
