import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';

void main() {
  group('ApplicantScreeningScreen defaults', () {
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

    test('uses the saved program, year level and assigned office', () {
      final defaults = resolveApplicantScreeningDefaults(
        user: User(
          id: 'u-1',
          name: 'Jane Student',
          email: 'jane@gmail.com',
          role: 'Student',
          department: 'College of Information and Computing Sciences',
          courseProgram: 'BSIT',
          yearLevel: '3rd Year',
        ),
        offices: offices,
      );

      expect(defaults.program, 'BSIT');
      expect(defaults.yearLevel, '3rd Year');
      expect(defaults.officeId, 'office-1');
      expect(defaults.officeName, 'Administration');
    });

    test('leaves what isn\'t on file for the Head to pick', () {
      final defaults = resolveApplicantScreeningDefaults(
        user: User(
          id: 'u-2',
          name: 'New Applicant',
          email: 'new@gmail.com',
          role: 'Student',
          department: 'College of Information and Computing Sciences',
        ),
        offices: offices,
      );

      // Not the department, and not the job they applied for.
      expect(defaults.program, isEmpty);
      expect(defaults.yearLevel, '1st Year');
      // Not the first office either — they aren't assigned to one yet.
      expect(defaults.officeId, isEmpty);
      expect(defaults.officeName, isEmpty);
    });
  });
}
