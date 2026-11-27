import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/utils/password_validator.dart';

void main() {
  group('PasswordValidator', () {
    test('accepts a strong password', () {
      final result = PasswordValidator.validate('StrongPass1!');

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('rejects weak passwords with missing complexity rules', () {
      final result = PasswordValidator.validate('pass');

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Password must be at least 10 characters long.'));
      expect(result.errors, contains('Password must include both uppercase and lowercase letters.'));
      expect(result.errors, contains('Password must include at least one number.'));
      expect(result.errors, contains('Password must include at least one special character.'));
    });

    test('rejects common sequences and whitespace', () {
      final result = PasswordValidator.validate('Abcdefg1!');
      final whitespaceResult = PasswordValidator.validate('Strong Pass1!');

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Password should not contain a common alphabetical sequence.'));
      expect(whitespaceResult.isValid, isFalse);
      expect(whitespaceResult.errors, contains('Password must not contain whitespace.'));
    });

    test('does not false-positive across ASCII letter or digit boundaries', () {
      for (final password in [
        'Str0ng10/Pass!',
        'SafePass0/.X',
        'MyKey89:Valid!',
        'Guard9:;Pass1',
        'Valid#\$%Pass1',
        'Alpha<=>Beta1!',
        'Strong`abPass1!',
        'Strongyz{Pass1!',
      ]) {
        final result = PasswordValidator.validate(password);
        expect(result.isValid, isTrue, reason: '$password: ${result.errors}');
        expect(result.errors, isEmpty);
      }
    });

    test('reports numerical and alphabetical sequences separately', () {
      final numResult = PasswordValidator.validate('StrongPass123!');
      expect(numResult.isValid, isFalse);
      expect(
        numResult.errors,
        equals(['Password should not contain a common numerical sequence.']),
      );

      final descNumResult = PasswordValidator.validate('StrongPass987!');
      expect(descNumResult.isValid, isFalse);
      expect(
        descNumResult.errors,
        equals(['Password should not contain a common numerical sequence.']),
      );

      final alphaResult = PasswordValidator.validate('StrongabcPass1!');
      expect(alphaResult.isValid, isFalse);
      expect(
        alphaResult.errors,
        equals(['Password should not contain a common alphabetical sequence.']),
      );

      final descAlphaResult = PasswordValidator.validate('StrongzyxPass1!');
      expect(descAlphaResult.isValid, isFalse);
      expect(
        descAlphaResult.errors,
        equals(['Password should not contain a common alphabetical sequence.']),
      );
    });
  });
}
