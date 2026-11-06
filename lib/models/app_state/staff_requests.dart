part of '../app_state.dart';

// ─── Staff sign-ups (approved by a Head) ───────────
// Someone who signs up as staff becomes a powerless Student profile with
// status 'Pending' and the role they ask for in `requestedRole`. They cannot
// sign in until a Head approves (the role is then given and the account made
// Active) or declines (the account stays locked). The Firestore rules let only
// a Head or the Admin make that change, and nothing else in the profile.
extension AppStateStaffRequests on AppState {
  /// The roles a sign-up may ask for.
  static const requestableStaffRoles = ['Supervisor', 'Head'];

  /// Staff sign-ups waiting for a decision, by name.
  List<User> get staffRequests => [
    for (final u in users)
      if (u.status == 'Pending' &&
          requestableStaffRoles.contains(u.requestedRole) &&
          !u.isDeleted)
        u,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// How many are waiting.
  int get staffRequestCount => staffRequests.length;

  /// Gives [request] the role they asked for and activates the account.
  /// Saved first, then shown: the error to tell the Head, or null once it is
  /// saved.
  Future<String?> approveStaffRequest(User request) async {
    if (role != 'Head' && role != 'Admin') {
      return 'Only a Head can approve a staff account.';
    }
    final requested = request.requestedRole;
    if (request.status != 'Pending' ||
        !requestableStaffRoles.contains(requested)) {
      return 'That request is no longer waiting.';
    }
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateUserFields(request.id, {
        'role': requested,
        'status': 'Active',
        'requestedRole': FieldValue.delete(),
      });
    } catch (error) {
      debugPrint('Could not approve ${request.id}: $error');
      return "Couldn't approve ${request.name}. Please try again.";
    }
    _replaceUser(
      request.id,
      (u) => u.copyWith(
        role: requested,
        status: 'Active',
        clearRequestedRole: true,
      ),
    );
    return null;
  }

  /// Turns [request] down: the account stays locked. The error to tell the
  /// Head, or null once it is saved.
  Future<String?> declineStaffRequest(User request) async {
    if (role != 'Head' && role != 'Admin') {
      return 'Only a Head can decline a staff account.';
    }
    if (request.status != 'Pending') {
      return 'That request is no longer waiting.';
    }
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateUserFields(request.id, {
        'status': 'Declined',
      });
    } catch (error) {
      debugPrint('Could not decline ${request.id}: $error');
      return "Couldn't decline ${request.name}. Please try again.";
    }
    _replaceUser(request.id, (u) => u.copyWith(status: 'Declined'));
    return null;
  }

  void _replaceUser(String id, User Function(User) change) {
    users = [for (final u in users) u.id == id ? change(u) : u];
    _notify();
  }
}
