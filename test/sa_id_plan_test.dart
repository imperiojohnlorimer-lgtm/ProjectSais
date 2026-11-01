import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/services/firestore_service.dart';

void main() {
  group('planSaId', () {
    test('keeps the ID a profile already holds', () {
      final plan = planSaId(held: ' SA 007 ', counterNext: 9, seedMax: 3);
      expect(plan.held, 'SA 007');
      expect(plan.number, isNull);
    });

    test('gives out the counter\'s next number', () {
      final plan = planSaId(held: '', counterNext: 12, seedMax: null);
      expect(plan.held, isNull);
      expect(plan.number, 12);
    });

    test('the counter wins over a seed', () {
      expect(planSaId(held: '', counterNext: 5, seedMax: 40).number, 5);
    });

    test('with no counter, numbers on from the seed', () {
      expect(planSaId(held: '', counterNext: null, seedMax: 0).number, 1);
      expect(planSaId(held: '', counterNext: null, seedMax: 51).number, 52);
    });

    test('with no counter and no seed there is no number: the caller seeds', () {
      final plan = planSaId(held: '  ', counterNext: null, seedMax: null);
      expect(plan.held, isNull);
      expect(plan.number, isNull);
    });
  });
}
