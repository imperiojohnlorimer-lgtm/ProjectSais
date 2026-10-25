/// What to tell a person whose sign-in failed, from Firebase Auth's error
/// [code] (null for anything that isn't a Firebase error).
///
/// Never Firebase's own text: it reads like "Firebase: Error
/// (auth/invalid-credential)", and an unknown email, a wrong password and a
/// deleted account must not sound different (that would say which emails
/// have accounts).
String friendlyAuthError(String? code) {
  switch (code) {
    case 'invalid-credential':
    case 'invalid-login-credentials':
    case 'wrong-password':
    case 'user-not-found':
      return 'Wrong email or password.';
    case 'invalid-email':
      return "That email address doesn't look right.";
    case 'too-many-requests':
      return 'Too many attempts. Wait a few minutes before trying again, or '
          'reset your password.';
    case 'network-request-failed':
      return "Can't reach the server. Check your internet connection and try "
          'again.';
    case 'user-disabled':
      return 'This account has been deactivated. Please contact an '
          'administrator.';
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
      return 'Google login was cancelled.';
    default:
      return 'Login failed. Please try again.';
  }
}
