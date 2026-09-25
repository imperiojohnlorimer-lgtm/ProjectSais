import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/recurring_schedule.dart';

/// Reads/writes each owner's recurring weekly [RecurringScheduleRule]s
/// ("Add Schedule"/"Add Subject" on the calendar — e.g. "Class Schedule,
/// every Monday, 8:00 AM - 5:00 PM").
///
/// Pulled out of the Schedule (calendar) screen so the DTR/Accomplishment
/// Report builder can read the exact same rules and auto-fill its "Class
/// Schedule" table (and its automatic task-completion entries) from them -
/// both features now agree on a single source of truth instead of the
/// calendar and the report drifting apart.
///
/// IMPORTANT: this used to be backed by SharedPreferences, which is local
/// to a single device/browser. That meant a subject the student added from
/// their own account/device never showed up on the supervisor's screen -
/// they were reading two completely separate local stores that happened to
/// share a key name. This now reads/writes a shared Firestore document per
/// owner so every device and account sees the same, current schedule.
///
/// Each document is keyed by the owner's account id, which is what the
/// Firestore rules check: only the owner, the Head and the Supervisor of
/// the owner's office may read or change it. Documents saved before that
/// were keyed by the owner's name, lowercased; the Head's session copies
/// them across (see [legacyDocIdFor]).
class RecurringScheduleRepository {
  const RecurringScheduleRepository();

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('recurringSchedules');

  /// Where [ownerName]'s rules were kept before they were keyed by account.
  static String legacyDocIdFor(String ownerName) {
    final trimmed = ownerName.trim().toLowerCase();
    return trimmed.isEmpty ? '_unknown' : trimmed;
  }

  Future<List<RecurringScheduleRule>> loadRules(String ownerId) async {
    if (ownerId.isEmpty) return [];
    try {
      final snap = await _collection.doc(ownerId).get();
      final raw = (snap.data()?['rules'] as List<dynamic>?) ?? const [];
      return raw
          .map(
            (e) => RecurringScheduleRule.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (e) {
      // Offline, permissions not yet set up, etc. - fail soft with an empty
      // schedule rather than crashing the calendar or the DTR report. Still
      // logged so a permission error doesn't just look like "no schedule
      // was ever saved" when debugging.
      debugPrint('RecurringScheduleRepository.loadRules("$ownerId") failed: $e');
      return [];
    }
  }

  Future<void> saveRules(
    String ownerId,
    String ownerName,
    List<RecurringScheduleRule> rules,
  ) async {
    await _collection.doc(ownerId).set({
      'ownerId': ownerId,
      'ownerName': ownerName,
      'rules': rules.map((r) => r.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}