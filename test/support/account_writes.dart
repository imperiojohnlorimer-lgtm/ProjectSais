import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// What a test's fake Firestore needs to take the app's account and office
/// writes: field-level profile updates, the SA ID counter and the office
/// transactions, kept in memory. Mix it into a fake:
///
///     class _Store extends FirestoreService with AccountWrites { ... }
///
/// Like Firestore, an update of a profile that was never saved fails, so a
/// test seeds [profiles] (and [officeDocs]) with what the account holds.
mixin AccountWrites on FirestoreService {
  /// The profiles as saved, by account id.
  final profiles = <String, User>{};

  /// The offices as saved, by id.
  final officeDocs = <String, Office>{};

  /// The officeAssignments documents: account id to office id.
  final assignmentDocs = <String, String>{};

  /// The next SA number; 0 means the counter document doesn't exist yet.
  int saCounter = 0;

  /// While set, field-level profile writes are refused (as the rules or a
  /// dropped connection would).
  bool failAccountWrites = false;

  /// Every field-level profile write, in order.
  final profileFieldWrites = <({String id, Map<String, dynamic> fields})>[];

  @override
  Future<void> updateUserFields(String id, Map<String, dynamic> fields) async {
    if (failAccountWrites) throw Exception('permission-denied');
    final base = profiles[id];
    if (base == null) throw Exception('not-found: no profile $id');
    profileFieldWrites.add((id: id, fields: Map.of(fields)));
    profiles[id] = base.copyWith(
      role: fields['role'] as String?,
      status: fields['status'] as String?,
      saId: fields['saId'] as String?,
      skills: (fields['skills'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      isDeleted: fields['deleted'] as bool?,
    );
  }

  @override
  Future<void> updateUserFieldsWithStudent(
    String id,
    Map<String, dynamic> fields,
    Student student,
  ) async {
    await updateUserFields(id, fields);
    await setStudent(student);
  }

  @override
  Future<List<User>> getAllUserProfiles() async => profiles.values.toList();

  @override
  Future<String> allocateSaId(String userId, {int? seedMax}) async {
    if (failAccountWrites) throw Exception('permission-denied');
    final user = profiles[userId];
    if (user == null) throw Exception('not-found: no profile $userId');
    final held = user.saId?.trim() ?? '';
    if (held.isNotEmpty) return held;
    if (saCounter == 0) {
      if (seedMax == null) throw const SaCounterNotSeeded();
      saCounter = seedMax + 1;
    }
    final id = 'SA ${saCounter.toString().padLeft(3, '0')}';
    saCounter++;
    profiles[userId] = user.copyWith(saId: id);
    return id;
  }

  @override
  Future<Map<String, Office>?> updateOffices(
    Iterable<String> ids,
    Map<String, Office>? Function(Map<String, Office> stored) edit, {
    Iterable<String> people = const [],
  }) async {
    if (failAccountWrites) throw Exception('permission-denied');
    final officeIds = {...ids};
    for (final person in people) {
      final office = assignmentDocs[person];
      if (office != null) officeIds.add(office);
    }
    final stored = {
      for (final id in officeIds)
        if (officeDocs[id] != null) id: officeDocs[id]!,
    };
    final changed = edit(stored);
    if (changed == null) return null;
    officeDocs.addAll(changed);
    for (final person in people) {
      final home = officeDocs.values
          .where((office) => office.assistantIds.contains(person))
          .firstOrNull;
      if (home == null) {
        assignmentDocs.remove(person);
      } else {
        assignmentDocs[person] = home.id;
      }
    }
    return changed;
  }
}
