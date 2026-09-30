import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';

PayrollRecord _record(String studentId, String name) => PayrollRecord(
  id: '',
  studentId: studentId,
  studentName: name,
  office: 'Library',
  campus: 'Boac Campus',
  periodStart: '2025-08-01',
  periodEnd: '2025-12-31',
  periodLabel: '1st Semester, AY 2025-2026',
  monthlyBreakdown: const [],
  dtrVerified: true,
  reportVerified: true,
  status: 'Ready',
);

void main() {
  group('PersonName', () {
    final juan = PersonName(
      first: ' Juan ',
      middle: 'Santos',
      last: 'Dela  Cruz',
      suffix: 'Jr.',
    );

    test('shows the middle initial between first and last name', () {
      expect(juan.display, 'Juan S. Dela Cruz Jr.');
      expect(PersonName(first: 'Juan', last: 'Cruz').display, 'Juan Cruz');
    });

    test('puts the surname first for the payroll', () {
      expect(juan.surnameFirst, 'Dela Cruz, Juan Jr. S.');
      expect(
        PersonName(
          first: 'Mark Dave',
          middle: 'M.',
          last: 'Miciano',
        ).surnameFirst,
        'Miciano, Mark Dave M.',
      );
      expect(
        PersonName(first: 'Juan', last: 'Cruz').surnameFirst,
        'Cruz, Juan',
      );
    });

    test('needs a first and a last name', () {
      expect(juan.isComplete, isTrue);
      expect(PersonName(first: 'Juan').isComplete, isFalse);
      expect(PersonName(first: '  ', last: 'Cruz').isComplete, isFalse);
    });

    group('guess', () {
      String parts(String name) {
        final guess = PersonName.guess(name);
        return '${guess.first}|${guess.middle}|${guess.last}|${guess.suffix}';
      }

      test('takes the last word as the surname', () {
        expect(parts('Mark Dave Miciano'), 'Mark Dave||Miciano|');
      });

      test('keeps dela, de los and the like with the surname', () {
        expect(parts('Juan dela Cruz'), 'Juan||dela Cruz|');
        expect(parts('Maria de los Santos'), 'Maria||de los Santos|');
      });

      test('takes a lone initial as the middle name', () {
        expect(
          parts('Princess Cate S. Pardilla'),
          'Princess Cate|S.|Pardilla|',
        );
        expect(parts('Juan S Dela Cruz'), 'Juan|S|Dela Cruz|');
      });

      test('takes a trailing Jr. or III as the suffix', () {
        expect(parts('Juan P. Dela Cruz Jr'), 'Juan|P.|Dela Cruz|Jr.');
        expect(parts('Jose Rizal III'), 'Jose||Rizal|III');
      });

      test('copes with one word or none', () {
        expect(parts('Juan'), 'Juan|||');
        expect(parts('  '), '|||');
      });
    });
  });

  group('User name parts', () {
    final old = User(
      id: 'u1',
      name: 'Juan dela Cruz',
      email: 'juan@gmail.com',
      role: 'Student Assistant',
    );

    test('an account from before the split keeps its name as saved', () {
      expect(old.hasNameParts, isFalse);
      expect(old.surnameFirstName, 'Juan dela Cruz');
      expect(old.nameParts.last, 'dela Cruz');
      expect(old.toJson().containsKey('firstName'), isFalse);
    });

    test('splitting the name also sets the name the app shows', () {
      final split = old.copyWith(
        nameParts: PersonName(
          first: 'Juan',
          middle: 'Santos',
          last: 'Dela Cruz',
        ),
      );
      expect(split.hasNameParts, isTrue);
      expect(split.name, 'Juan S. Dela Cruz');
      expect(split.surnameFirstName, 'Dela Cruz, Juan S.');

      final saved = User.fromJson(split.toJson());
      expect(saved.firstName, 'Juan');
      expect(saved.middleName, 'Santos');
      expect(saved.lastName, 'Dela Cruz');
      expect(saved.suffix, '');
      expect(saved.surnameFirstName, 'Dela Cruz, Juan S.');
    });

    test('other changes keep the parts', () {
      final split = old.copyWith(
        nameParts: PersonName(first: 'Juan', last: 'Dela Cruz'),
      );
      final moved = split.copyWith(role: 'Student', phone: '09171234567');
      expect(moved.firstName, 'Juan');
      expect(moved.lastName, 'Dela Cruz');
      expect(moved.name, 'Juan Dela Cruz');
    });
  });

  group('Payroll sheet names', () {
    test('rows take the names given and sort by them', () {
      final names = {'u1': 'Miciano, Mark Dave M.', 'u2': 'Guevara, Uver V.'};
      final sheet = PayrollSheet.fromRecords(
        periodStart: '2025-08-01',
        periodEnd: '2025-12-31',
        periodLabel: '1st Semester, AY 2025-2026',
        records: [
          _record('u1', 'Mark Dave M. Miciano'),
          _record('u2', 'Uver V. Guevara'),
          _record('gone', 'Old Account'),
        ],
        nameOf: (r) => names[r.studentId] ?? r.studentName,
      );
      expect(sheet.entries.map((e) => e.name), [
        'Guevara, Uver V.',
        'Miciano, Mark Dave M.',
        'Old Account',
      ]);
    });
  });
}
