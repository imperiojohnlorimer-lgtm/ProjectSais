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
class RecurringScheduleRepository {
  const RecurringScheduleRepository();

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('recurringSchedules');

  /// Normalized so "Juan Dela Cruz" saved from one screen and "juan dela
  /// cruz " read back from another still hit the same document.
  String _docIdFor(String ownerName) {
    final trimmed = ownerName.trim().toLowerCase();
    return trimmed.isEmpty ? '_unknown' : trimmed;
  }

  Future<List<RecurringScheduleRule>> loadRules(String ownerName) async {
    try {
      final snap = await _collection.doc(_docIdFor(ownerName)).get();
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
      debugPrint('RecurringScheduleRepository.loadRules("$ownerName") failed: $e');
      return [];
    }
  }

  Future<void> saveRules(
    String ownerName,
    List<RecurringScheduleRule> rules,
  ) async {
    await _collection.doc(_docIdFor(ownerName)).set({
      'ownerName': ownerName,
      'rules': rules.map((r) => r.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}