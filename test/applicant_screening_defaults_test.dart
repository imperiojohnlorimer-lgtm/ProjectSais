import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';

void main() {
  group('ApplicantScreeningScreen defaults', () {
    test('uses the assigned office and saved year level for an applicant', () {
      final user = User(
        id: 'u-1',
        name: 'Jane Student',
        email: 'jane@gmail.com',
        role: 'Student',
        department: 'College of Information and Computing Sciences',
        yearLevel: '3rd Year',
      );

      final offices = [
        Office(
          id: 'office-1',
          name: 'Administration',
          code: 'ADMIN',
          headIds: [],
          headNames: [],
          assistantIds: ['u-1'],
          assistantNames: ['Jane Student'],
          capacity: 1,
        ),
        Office(
          id: 'office-2',
          name: 'Finance',
          code: 'FIN',
          headIds: [],
          headNames: [],
          assistantIds: [],
          assistantNames: [],
          capacity: 1,
        ),
      ];

      final defaults = resolveApplicantScreeningDefaults(
        user: user,
        application: Application(
          id: 'app-1',
          announcementId: 'ann-1',
          announcementTitle: 'Student Assistant',
          applicantId: 'u-1',
          applicantName: 'Jane Student',
          appliedAt: '2026-09-01',
        ),
        offices: offices,
      );

      expect(defaults.program, 'College of Information and Computing Sciences');
      expect(defaults.yearLevel, '3rd Year');
      expect(defaults.officeId, 'office-1');
      expect(defaults.officeName, 'Administration');
    });
  });
}
