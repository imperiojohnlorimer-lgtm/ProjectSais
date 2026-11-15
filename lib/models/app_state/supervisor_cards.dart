part of '../app_state.dart';

// ─── Supervisor cards ──────────────────────────────
// A Student Assistant can't read a supervisor's profile (email, phone, ...),
// so the picture shown on My Office comes from a card holding only the name
// and picture: supervisorCards/{account id}.
extension AppStateSupervisorCards on AppState {
  /// Fetches the pictures of the supervisors [ids] for My Office. A card that
  /// can't be read (or doesn't exist yet) just leaves initials showing.
  Future<void> loadSupervisorCards(Iterable<String> ids) async {
    final user = currentUser;
    final wanted = {
      for (final id in ids)
        if (id.isNotEmpty) id,
    };
    if (user == null || wanted.isEmpty) return;
    try {
      _firestoreService ??= FirestoreService();
      final cards = await _firestoreService!.getSupervisorCards(wanted);
      // Signed out, or someone else signed in, meanwhile.
      if (_disposed || currentUser?.id != user.id) return;
      supervisorAvatars = {
        ...supervisorAvatars,
        for (final card in cards) card.id: card.avatar,
      };
      _notify();
    } catch (error) {
      debugPrint('Could not load supervisor pictures: $error');
    }
  }

  /// Keeps the cards in step with the profiles, from the full roster the
  /// Users listener delivers. A Head or the Admin brings every Supervisor's
  /// card up to date; a Supervisor's own session does just their own (the
  /// only one firestore.rules lets them write). Writes only what differs,
  /// and nothing for a supervisor with no picture and no card.
  Future<void> syncSupervisorCards() async {
    final fs = _firestoreService;
    final me = currentUser;
    if (fs == null || me == null) return;
    final all = role == 'Head' || role == 'Admin';
    final mine = [
      for (final u in users)
        if (all
            ? u.role == 'Supervisor' && u.status != 'Archived'
            : role == 'Supervisor' && u.id == me.id)
          u,
    ];
    if (mine.isEmpty) return;
    final signature =
        (mine
                .map((u) => '${u.id}|${u.name}|${(u.avatar ?? '').hashCode}')
                .toList()
              ..sort())
            .join(',');
    if (signature == _syncedSupervisorCards) return;
    _syncedSupervisorCards = signature;
    try {
      final stored = {
        for (final card in await fs.getSupervisorCards(all ? null : [me.id]))
          card.id: card,
      };
      final changed = <SupervisorCard>[];
      for (final u in mine) {
        final avatar = u.avatar ?? '';
        final card = stored[u.id];
        final upToDate = card == null
            ? avatar.isEmpty
            : card.name == u.name && card.avatar == avatar;
        if (!upToDate) {
          changed.add(SupervisorCard(id: u.id, name: u.name, avatar: avatar));
        }
      }
      if (changed.isNotEmpty) await fs.saveSupervisorCards(changed);
    } catch (error) {
      _syncedSupervisorCards = null;
      debugPrint('Could not update the supervisor cards: $error');
    }
  }
}
