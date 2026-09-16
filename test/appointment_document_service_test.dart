import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/appointment_document_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // needed: contract generation loads a template asset via rootBundle

  group('AppointmentDocumentService', () {
    test('creates a contract of appointment document for an approved applicant', () async {
      final applicant = User(
        id: 'user_123',
        name: 'Maria Santos',
        email: 'maria@example.com',
        role: 'Student',
        department: 'IT Department',
        campus: 'Main Campus',
      );

      final application = Application(
        id: 'app_123',
        announcementId: 'ann_123',
        announcementTitle: 'Student Assistant - IT Office',
        applicantId: applicant.id,
        applicantName: applicant.name,
        appliedAt: '2026-08-15',
        status: 'Approved',
        skills: ['Data Entry', 'Customer Service'],
      );

      final generated = await AppointmentDocumentService().generateContractOfAppointment(
        application: application,
        applicant: applicant,
        officeName: 'IT Office',
        supervisorName: 'Jane Cruz',
        supervisorRole: 'Office Supervisor',
        startDate: 'September 1, 2026',
        endDate: 'May 31, 2027',
      );

      expect(generated.fileName, contains('contract-of-appointment'));
      expect(generated.fileName, endsWith('.docx'));
      expect(generated.bytes, isNotEmpty);
      expect(generated.bytes!.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
    });

    test('creates an endorsement letter document for an approved applicant', () async {
      final applicant = User(
        id: 'user_456',
        name: 'Alex Reyes',
        email: 'alex@example.com',
        role: 'Student',
        department: 'Finance Department',
        campus: 'Main Campus',
      );

      final application = Application(
        id: 'app_456',
        announcementId: 'ann_456',
        announcementTitle: 'Student Assistant - Finance Office',
        applicantId: applicant.id,
        applicantName: applicant.name,
        appliedAt: '2026-08-18',
        status: 'Approved',
      );

      final generated = await AppointmentDocumentService().generateEndorsementLetter(
        application: application,
        applicant: applicant,
        supervisorName: 'John Smith',
        officeName: 'Finance Office',
        campusName: 'Main Campus',
      );

      expect(generated.fileName, contains('endorsement-letter'));
      expect(generated.fileName, endsWith('.docx'));
      expect(generated.bytes, isNotEmpty);
      expect(generated.bytes!.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
    });

    test('fills the real contract template with applicant details', () async {
      final applicant = User(
        id: 'user_789',
        name: 'Maria Santos',
        email: 'maria@example.com',
        role: 'Student',
        department: 'IT Department',
        campus: 'Main Campus',
      );

      final application = Application(
        id: 'app_789',
        announcementId: 'ann_789',
        announcementTitle: 'Student Assistant - IT Office',
        applicantId: applicant.id,
        applicantName: applicant.name,
        appliedAt: '2026-08-15',
        status: 'Approved',
        skills: ['Data Entry', 'Customer Service'],
      );

      final generated = await AppointmentDocumentService().generateContractOfAppointment(
        application: application,
        applicant: applicant,
        officeName: 'IT Office',
        supervisorName: 'Jane Cruz',
        supervisorRole: 'Office Supervisor',
        startDate: 'September 1, 2026',
        endDate: 'May 31, 2027',
      );

      final archive = ZipDecoder().decodeBytes(generated.bytes!);
      final documentXml = String.fromCharCodes(
        archive.findFile('word/document.xml')!.content as List<int>,
      );

      final paragraphCount = RegExp('<w:p').allMatches(documentXml).length;

      expect(paragraphCount, greaterThan(10));
      expect(documentXml, contains('STUDENT ASSISTANT CONTRACT OF APPOINTMENT'));
      expect(documentXml, contains('PARTIES AND PURPOSE'));
      expect(documentXml, contains('Maria Santos'));
      expect(documentXml, contains('IT Office'));
      expect(documentXml, contains('September 1, 2026'));
      expect(documentXml, contains('May 31, 2027'));
      // template tokens must all be replaced, none left over
      expect(documentXml, isNot(contains('{{')));
    });
  });
}