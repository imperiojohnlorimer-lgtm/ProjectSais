import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/services/firestore_service.dart';

void main() {
  group('FirestoreService.movedYearId (undoing a year switch)', () {
    const from = '2027-2028';
    const to = '2026-2027';

    test(
      'an application named for the undone year moves to the year in effect',
      () {
        expect(
          FirestoreService.movedYearId(
            'applications',
            'app_stu_2027-2028',
            {'applicantId': 'stu'},
            from,
            to,
          ),
          'app_stu_2026-2027',
        );
      },
    );

    test('a screening record named for the undone year moves with it', () {
      expect(
        FirestoreService.movedYearId(
          'screeningRecords',
          'screen-stu-2027-2028',
          {'applicantId': 'stu'},
          from,
          to,
        ),
        'screen-stu-2026-2027',
      );
    });

    test('records whose id does not name the undone year keep their id', () {
      // An older application (no year in the id), another applicant's id,
      // and a screening record keyed by something else.
      expect(
        FirestoreService.movedYearId(
          'applications',
          'app_123',
          {'applicantId': 'stu'},
          from,
          to,
        ),
        isNull,
      );
      expect(
        FirestoreService.movedYearId(
          'applications',
          'app_other_2027-2028',
          {'applicantId': 'stu'},
          from,
          to,
        ),
        isNull,
      );
      expect(
        FirestoreService.movedYearId(
          'screeningRecords',
          'screen-app_123',
          {'applicantId': 'stu'},
          from,
          to,
        ),
        isNull,
      );
    });

    test('no applicant, the same year, or another collection: no move', () {
      expect(
        FirestoreService.movedYearId(
          'applications',
          'app__2027-2028',
          {'applicantId': ''},
          from,
          to,
        ),
        isNull,
      );
      expect(
        FirestoreService.movedYearId(
          'applications',
          'app_stu_2027-2028',
          {'applicantId': 'stu'},
          from,
          from,
        ),
        isNull,
      );
      expect(
        FirestoreService.movedYearId(
          'tasks',
          'app_stu_2027-2028',
          {'applicantId': 'stu'},
          from,
          to,
        ),
        isNull,
      );
    });
  });
}
