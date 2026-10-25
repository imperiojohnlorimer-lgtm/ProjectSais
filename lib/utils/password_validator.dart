class PasswordValidationResult {
  const PasswordValidationResult({required this.isValid, required this.errors});

  final bool isValid;
  final List<String> errors;
}

class PasswordValidator {
  /// The shortest password accepted.
  static const minLength = 10;

  /// Passwords people choose first. They'd pass the other rules ("Welcome1!"),
  /// and an attacker tries them first.
  static const _common = <String>{
    'password',
    'passw0rd',
    'welcome',
    'letmein',
    'admin',
    'login',
    'iloveyou',
    'monkey',
    'dragon',
    'master',
    'sunshine',
    'princess',
    'football',
    'baseball',
    'superman',
    'batman',
    'shadow',
    'marsu',
    'marsuedu',
    'marinduque',
    'student',
    'sais',
    'changeme',
    'qazwsx',
  };

  /// A common password, with or without the digits, symbols or capitals a
  /// person adds to satisfy the rules ("Password123!").
  static bool _isCommon(String password) {
    final letters = password.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return _common.contains(letters);
  }

  static PasswordValidationResult validate(String password) {
    final errors = <String>[];

    if (password.length < minLength) {
      errors.add('Password must be at least $minLength characters long.');
    }

    if (_isCommon(password)) {
      errors.add('That password is too common. Choose something less obvious.');
    }

    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    if (!hasUppercase || !hasLowercase) {
      errors.add('Password must include both uppercase and lowercase letters.');
    }

    if (!RegExp(r'\d').hasMatch(password)) {
      errors.add('Password must include at least one number.');
    }

    if (!RegExp(r'[^\w\s]').hasMatch(password)) {
      errors.add('Password must include at least one special character.');
    }

    if (password.contains(RegExp(r'\s'))) {
      errors.add('Password must not contain whitespace.');
    }

    if (_containsAlphabeticalSequence(password)) {
      errors.add('Password should not contain a common alphabetical sequence.');
    }

    if (_containsNumericSequence(password)) {
      errors.add('Password should not contain a common numerical sequence.');
    }

    if (_containsKeyboardSequence(password)) {
      errors.add('Password should not contain a common keyboard sequence.');
    }

    return PasswordValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  static bool _containsAlphabeticalSequence(String password) {
    final normalized = password.toLowerCase();
    for (var i = 0; i < normalized.length - 2; i++) {
      final a = normalized.codeUnitAt(i);
      final b = normalized.codeUnitAt(i + 1);
      final c = normalized.codeUnitAt(i + 2);
      if ((b == a + 1 && c == b + 1) || (b == a - 1 && c == b - 1)) {
        return true;
      }
    }
    return false;
  }

  static bool _containsNumericSequence(String password) {
    final normalized = password.toLowerCase();
    for (var i = 0; i < normalized.length - 2; i++) {
      final a = normalized.codeUnitAt(i);
      final b = normalized.codeUnitAt(i + 1);
      final c = normalized.codeUnitAt(i + 2);
      if (a >= 48 && a <= 57 && b == a + 1 && c == b + 1) {
        return true;
      }
      if (a >= 48 && a <= 57 && b == a - 1 && c == b - 1) {
        return true;
      }
    }
    return false;
  }

  static bool _containsKeyboardSequence(String password) {
    final normalized = password.toLowerCase();
    const keyboardPatterns = <String>['qwerty', 'asdf', 'zxcv', 'uiop', 'lkjh', 'mnbv'];
    return keyboardPatterns.any(normalized.contains);
  }
}
