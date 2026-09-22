import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';

void main() {
  group('RehireRecord terms', () {
    test('steps through the academic year and rolls Summer over', () {
      expect(
        RehireRecord.nextTerm('2026-2027', '1st Semester'),
        (academicYear: '2026-2027', semester: '2nd Semester'),
      );
      expect(
        RehireRecord.nextTerm('2026-2027', '2nd Semester'),
        (academicYear: '2026-2027', semester: 'Summer'),
      );
      expect(
        RehireRecord.nextTerm('2026-2027', 'Summer'),
        (academicYear: '2027-2028', semester: '1st Semester'),
      );
    });

    test('orders terms across academic years', () {
      final first = RehireRecord.termOrder('2026-2027', '1st Semester')!;
      final second = RehireRecord.termOrder('2026-2027', '2nd Semester')!;
      final summer = RehireRecord.termOrder('2026-2027', 'Summer')!;
      final nextFirst = RehireRecord.termOrder('2027-2028', '1st Semester')!;
      expect(first < second && second < summer && summer < nextFirst, isTrue);
      expect(RehireRecord.termOrder('not a year', '1st Semester'), isNull);
    });

    test('starts each term in the evaluation form\'s months', () {
      expect(
        RehireRecord.termStart('2026-2027', '1st Semester'),
        DateTime(2026, 8, 1),
      );
      expect(
        RehireRecord.termStart('2026-2027', '2nd Semester'),
        DateTime(2027, 1, 1),
      );
      expect(
        RehireRecord.termStart('2026-2027', 'Summer'),
        DateTime(2027, 6, 1),
      );
    });

    test('keys one decision per student per term', () {
      expect(
        RehireRecord.idFor('uid123', '2026-2027', '2nd Semester'),
        'rehire_uid123_2026-2027_2nd-Semester',
      );
    });
  });

  test('RehireRecord survives a Firestore round trip', () {
    const record = RehireRecord(
      id: 'rehire_uid123_2026-2027_2nd-Semester',
      studentId: 'uid123',
      studentName: 'Juan Dela Cruz',
      saId: 'SA 004',
      academicYear: '2026-2027',
      semester: '2nd Semester',
      decision: RehireRecord.rehired,
      officeIds: ['office1'],
      officeNames: ['Library'],
      evaluationOverallRating: 8,
      eligibleForRehire: true,
      decidedById: 'head1',
      decidedByName: 'Maria Santos',
      decidedAt: '2026-12-10T09:00:00.000',
    );

    final restored = RehireRecord.fromJson({
      ...record.toJson(),
      'id': record.id,
    });

    expect(restored.isRehired, isTrue);
    expect(restored.officeNames, ['Library']);
    expect(restored.eligibleForRehire, isTrue);
    expect(restored.applied, isFalse);
    expect(restored.hasContract, isFalse);
    expect(restored.termLabel, '2nd Semester, AY 2026-2027');
  });
}
