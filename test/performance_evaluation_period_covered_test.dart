import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/screens/supervisor/performance_evaluation_screen.dart';
import 'package:projectsais/services/performance_evaluation_document_service.dart';

void main() {
  group('PerformanceEvaluationScreen default period covered', () {
    test('uses the academic year and selected term for first semester', () {
      expect(
        PerformanceEvaluationScreen.defaultPeriodCovered('2026-2027', 'First Semester'),
        'Aug 2026 – Dec 2026',
      );
    });

    test('uses the academic year and selected term for second semester', () {
      expect(
        PerformanceEvaluationScreen.defaultPeriodCovered('2026-2027', 'Second Semester'),
        'Jan 2027 – May 2027',
      );
    });

    test('uses the academic year and selected term for midyear', () {
      expect(
        PerformanceEvaluationScreen.defaultPeriodCovered('2026-2027', 'Midyear Term'),
        'Jun 2027 – Jul 2027',
      );
    });
  });

  group('PerformanceEvaluationDocumentService template mapping', () {
    test('marks the selected term using the template checkbox values', () {
      expect(
        PerformanceEvaluationDocumentService.termCheckMark('First Semester', 'First Semester'),
        '☒',
      );
      expect(
        PerformanceEvaluationDocumentService.termCheckMark('First Semester', 'Midyear Term'),
        '☐',
      );
      expect(
        PerformanceEvaluationDocumentService.termCheckMark('Midyear Term', 'Midyear Term'),
        '☒',
      );
    });

    test('preserves line breaks for department head comments', () {
      final xml = PerformanceEvaluationDocumentService.commentXml('First line\nSecond line');
      expect(xml, contains('First line'));
      expect(xml, contains('Second line'));
      expect(xml, contains('<w:br/>'));
    });
  });
}
