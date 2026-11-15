/// What a Student Assistant may see of the supervisor of their office: a name
/// and a picture, nothing else. The profile itself (email, phone, ...) is
/// readable only by staff and its owner, so the picture is copied into
/// `supervisorCards/{account id}` for this (kept in step by
/// `AppState.syncSupervisorCards`).
class SupervisorCard {
  final String id;
  final String name;

  /// The picture, as a `data:image` URL like a profile's; empty when the
  /// supervisor has none.
  final String avatar;

  const SupervisorCard({
    required this.id,
    required this.name,
    this.avatar = '',
  });

  factory SupervisorCard.fromJson(String id, Map<String, dynamic> json) =>
      SupervisorCard(
        id: id,
        name: json['name']?.toString() ?? '',
        avatar: json['avatar']?.toString() ?? '',
      );

  /// The fields saved (the server adds `updatedAt`).
  Map<String, dynamic> toJson() => {'name': name, 'avatar': avatar};
}
