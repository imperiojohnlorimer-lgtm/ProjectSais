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
      expect(result.errors, contains('Password must be at least 8 characters long.'));
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
  });
}
