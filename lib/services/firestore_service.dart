import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import '../models/models.dart';
import '../utils/file_names.dart';
import '../models/schedule_event.dart';
import '../models/supervisor_card.dart';
import '../models/task_duty.dart';
import 'supabase_storage_service.dart';

/// Simple Firestore helper for `announcements` collection.
///
/// Methods return simple types to make UI wiring straightforward.
/// meta/saCounter doesn't exist yet: the caller works out the highest SA
/// number in use and asks again with it as the seed.
class SaCounterNotSeeded implements Exception {
  const SaCounterNotSeeded();

  @override
  String toString() => 'The SA ID counter has not been created yet.';
}

/// What [FirestoreService.allocateSaId] decides from what it read: the ID the
/// profile already holds, else the number to give out (the counter's, or the
/// seed's next one), else null when the counter doesn't exist and there is no
/// seed.
@visibleForTesting
({String? held, int? number}) planSaId({
  required String held,
  required int? counterNext,
  required int? seedMax,
}) {
  final id = held.trim();
  if (id.isNotEmpty) return (held: id, number: null);
  final number = counterNext ?? (seedMax == null ? null : seedMax + 1);
  return (held: null, number: number);
}

class FirestoreService {
  FirestoreService({FirebaseFirestore? instance}) : _instance = instance;

  final FirebaseFirestore? _instance;

  // Resolved on first use rather than in the constructor, so a test can
  // subclass this with fakes without a Firebase app being set up.
  late final FirebaseFirestore _db = _instance ?? FirebaseFirestore.instance;

  CollectionReference get _announcements => _db.collection('announcements');

  CollectionReference get _notifications => _db.collection('notifications');

  /// Ping announcements collection and return elapsed milliseconds or -1 on failure.
  Future<int> pingAnnouncements() async {
    try {
      final sw = Stopwatch()..start();
      await _announcements.limit(1).get();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Adds a new announcement and returns the created document reference.
  Future<DocumentReference> addAnnouncement({
    required String title,
    required String body,
    Map<String, dynamic>? extra,
    String? id,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      ...?extra,
    };

    if (id != null && id.isNotEmpty) {
      final docRef = _announcements.doc(id);
      await docRef.set(data);
      return docRef;
    }

    return await _announcements.add(data);
  }

  /// Streams announcements, newest first by `createdAt`.
  ///
  /// Sorted on the client rather than with a server-side `orderBy`: Firestore
  /// silently drops documents that lack the ordered field, so announcements
  /// without `createdAt` (added by hand or by older versions) would vanish.
  /// Those sort last.
  Stream<List<Map<String, dynamic>>> announcementsStream() {
    return _announcements.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
      DateTime? created(Map<String, dynamic> m) {
        final v = m['createdAt'];
        return v is Timestamp ? v.toDate() : null;
      }

      list.sort((a, b) {
        final ca = created(a);
        final cb = created(b);
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        return cb.compareTo(ca);
      });
      return list;
    });
  }

  /// Newest-first by `createdAt`, sorted here rather than with a server-side
  /// `orderBy` — for the same reason [announcementsStream] does it.
  ///
  /// An `orderBy` alongside a `where` on a different field also needs a
  /// composite index, and without one Firestore rejects the whole query.
  /// That is what left student assistants with an empty attendance list
  /// while supervisors, whose query has no `where`, saw everything.
  /// Records missing `createdAt` sort last instead of disappearing.
  static List<Map<String, dynamic>> _newestFirst(QuerySnapshot snap) {
    final list = snap.docs
        .map(
          (d) => withPendingTimestamp({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }, hasPendingWrites: d.metadata.hasPendingWrites),
        )
        .toList();
    DateTime? created(Map<String, dynamic> m) {
      final value = m['createdAt'];
      return value is Timestamp ? value.toDate() : null;
    }

    list.sort((a, b) {
      final ca = created(a);
      final cb = created(b);
      if (ca == null && cb == null) return 0;
      if (ca == null) return 1;
      if (cb == null) return -1;
      return cb.compareTo(ca);
    });
    return list;
  }

  /// A `createdAt` server timestamp this device is still writing reads as
  /// null until Firestore confirms it. It means "now", so a record just sent
  /// sorts first and shows a time, instead of sorting last with none.
  @visibleForTesting
  static Map<String, dynamic> withPendingTimestamp(
    Map<String, dynamic> data, {
    required bool hasPendingWrites,
  }) {
    if (!hasPendingWrites ||
        !data.containsKey('createdAt') ||
        data['createdAt'] != null) {
      return data;
    }
    return {...data, 'createdAt': Timestamp.now()};
  }

  static List<Map<String, dynamic>> _withIds(QuerySnapshot snap) => snap.docs
      .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
      .toList();

  /// Every document in [collection], kept up to date — the live
  /// counterpart of the one-off `getAll…` reads, so a change made in
  /// another browser shows up without a refresh.
  Stream<List<Map<String, dynamic>>> collectionStream(
    String collection, {
    bool newestFirst = false,
  }) => _db
      .collection(collection)
      .snapshots()
      .map(newestFirst ? _newestFirst : _withIds);

  /// Live documents in [collection] whose [field] equals [value]. Filtered
  /// on one field with no `orderBy`, so it never needs a composite index.
  Stream<List<Map<String, dynamic>>> whereStream(
    String collection,
    String field,
    Object value, {
    bool newestFirst = false,
  }) => _db
      .collection(collection)
      .where(field, isEqualTo: value)
      .snapshots()
      .map(newestFirst ? _newestFirst : _withIds);

  /// Live documents in [collection] whose [field] is one of [values].
  Stream<List<Map<String, dynamic>>> whereInStream(
    String collection,
    String field,
    List<Object> values,
  ) => _db
      .collection(collection)
      .where(field, whereIn: values)
      .snapshots()
      .map(_withIds);

  /// A single live document, or null while it doesn't exist.
  Stream<Map<String, dynamic>?> docStream(String collection, String id) => _db
      .collection(collection)
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? {...?d.data(), 'id': d.id} : null);

  /// Streams every attendance document, newest first.
  Stream<List<Map<String, dynamic>>> attendanceStream() {
    return _attendance.snapshots().map(_newestFirst);
  }

  Stream<List<Map<String, dynamic>>> attendanceStreamForStudent(String uid) {
    return _attendance
        .where('studentId', isEqualTo: uid)
        .snapshots()
        .map(_newestFirst);
  }

  /// Streams tasks collection in real-time.
  Stream<List<Map<String, dynamic>>> tasksStream() {
    return _tasks
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> tasksStreamForUser(String uid) {
    return _tasks
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> tasksStreamForUserName(String name) {
    return _tasks
        .where('assignedToName', isEqualTo: name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  /// Streams submitted applications in real time for the admin view.
  Stream<List<Map<String, dynamic>>> applicationsStream() {
    return _applications
        .orderBy('appliedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
              .toList(),
        );
  }

  /// An applicant's own applications. Sorted here for the same reason the
  /// attendance streams are: a `where` plus an `orderBy` on another field
  /// needs a composite index, and without one the query is rejected and the
  /// applicant sees nothing.
  Stream<List<Map<String, dynamic>>> applicationsStreamForApplicant(
    String uid,
  ) {
    return _applications.where('applicantId', isEqualTo: uid).snapshots().map((
      snap,
    ) {
      final list = snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
      list.sort(
        (a, b) => (b['appliedAt'] ?? '').toString().compareTo(
          (a['appliedAt'] ?? '').toString(),
        ),
      );
      return list;
    });
  }

  CollectionReference get _users => _db.collection('users');

  Future<void> setUserProfile(User user) async {
    await _users.doc(user.id).set(user.toJson());
  }

  /// Writes only [fields] to the profile. For a change to one thing (role,
  /// status, SA ID): a whole-profile [setUserProfile] from a stale copy would
  /// quietly undo whatever else was changed meanwhile, such as an archive.
  Future<void> updateUserFields(String id, Map<String, dynamic> fields) async {
    await _users.doc(id).update(fields);
  }

  /// Like [updateUserFields], and saves [student] in the same batch, so a
  /// promotion never lands on only one of them.
  Future<void> updateUserFieldsWithStudent(
    String id,
    Map<String, dynamic> fields,
    Student student,
  ) async {
    final batch = _db.batch();
    batch.update(_users.doc(id), fields);
    batch.set(_students.doc(student.id), _studentData(student));
    await batch.commit();
  }

  /// Gives [userId] the next Student Assistant ID ("SA 007"), numbered from
  /// the counter in meta/saCounter, in one transaction: two Heads approving
  /// at once can't both get the same number. Returns the ID the profile
  /// already has when it has one. The counter is created from [seedMax] (the
  /// highest number in use) the first time; without a seed, a missing counter
  /// throws [SaCounterNotSeeded] so the caller can work one out.
  Future<String> allocateSaId(String userId, {int? seedMax}) async {
    final counterRef = _db.collection('meta').doc('saCounter');
    // [SaCounterNotSeeded] is thrown out here, not inside the transaction: on
    // the web the Firestore SDK wraps whatever a transaction throws in a
    // plain JavaScript error, so the caller's `on SaCounterNotSeeded` would
    // never match and the first approval would fail with "Dart exception".
    final id = await _db.runTransaction<String?>((transaction) async {
      final userRef = _users.doc(userId);
      final profile = await transaction.get(userRef);
      final counter = await transaction.get(counterRef);
      final plan = planSaId(
        held: ((profile.data() as Map<String, dynamic>?)?['saId'] ?? '')
            .toString(),
        counterNext: counter.exists
            ? ((counter.data() as Map<String, dynamic>)['next'] as num).toInt()
            : null,
        seedMax: seedMax,
      );
      if (plan.held != null) return plan.held;
      final number = plan.number;
      if (number == null) return null; // no counter, no seed
      final id = 'SA ${number.toString().padLeft(3, '0')}';
      transaction.set(counterRef, {'next': number + 1});
      transaction.update(userRef, {'saId': id});
      return id;
    });
    if (id == null) throw const SaCounterNotSeeded();
    return id;
  }

  Future<void> deleteUserProfile(String id) async {
    await _users.doc(id).delete();
  }

  Future<User> migrateUserProfileToAuthUid({
    required String uid,
    required String email,
    required User fallback,
  }) async {
    final snapshot = await _users
        .where('email', isEqualTo: email.toLowerCase())
        .get();
    final rolePriority = {
      'Admin': 5,
      'Head': 4,
      'Supervisor': 3,
      'Student Assistant': 2,
      'Student': 1,
    };
    final sourceDoc = snapshot.docs.isEmpty
        ? null
        : snapshot.docs.reduce((first, next) {
            final firstRole = (first.data() as Map<String, dynamic>)['role'];
            final nextRole = (next.data() as Map<String, dynamic>)['role'];
            return (rolePriority[firstRole] ?? 0) >=
                    (rolePriority[nextRole] ?? 0)
                ? first
                : next;
          });
    final source = sourceDoc == null
        ? fallback
        : User.fromJson({
            ...(sourceDoc.data() as Map<String, dynamic>),
            'id': sourceDoc.id,
          });
    final canonical = source.copyWith(id: uid);

    await _users.doc(uid).set(canonical.toJson());
    for (final doc in snapshot.docs) {
      if (doc.id != uid) await doc.reference.delete();
    }
    return canonical;
  }

  Future<void> archiveAnnouncementsForAcademicYear(String academicYear) async {
    final snapshot = await _announcements
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('announcements');
    for (final announcement in snapshot.docs) {
      await archiveCollection.doc(announcement.id).set({
        ...(announcement.data() as Map<String, dynamic>),
        'archivedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> archiveCalendarEventsForAcademicYear(String academicYear) async {
    final events = await _db
        .collection('schedule_events')
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('calendar_events');
    for (final event in events.docs) {
      final scheduleEvent = ScheduleEvent.fromJson({
        ...event.data(),
        'id': event.id,
      });
      await archiveCollection.doc(event.id).set({
        ...scheduleEvent.toJson(),
        'archivedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<Map<String, dynamic>?> getAcademicYearSettings() async {
    final snapshot = await _db
        .collection('meta')
        .doc('academic_year_settings')
        .get();
    return snapshot.exists ? snapshot.data() : null;
  }

  Future<void> saveAcademicYearSettings(Map<String, dynamic> settings) async {
    await _db.collection('meta').doc('academic_year_settings').set(settings);
  }

  DocumentReference<Map<String, dynamic>> _academicYearArchive(
    String academicYear,
  ) => _db
      .collection('meta')
      .doc('academic_year_archives')
      .collection('years')
      .doc(academicYear);

  /// Records [academicYear] as finished, with its settings, unless it
  /// already is. Its records are copied in later, by the Head's session
  /// (see [markAcademicYearDataArchived]); [archiveAttendance] says whether
  /// that copy should also retire the year's attendance logs.
  /// [headcountByCampus] is each campus's student assistant count as the
  /// year closes, which the Head's dashboard plots year over year. Returns
  /// whether this call put the year on the list.
  Future<bool> archiveAcademicYearSettings(
    String academicYear,
    Map<String, dynamic> settings, {
    bool archiveAttendance = false,
    Map<String, int>? headcountByCampus,
  }) async {
    final archiveRef = _academicYearArchive(academicYear);
    if ((await archiveRef.get()).exists) return false;
    await archiveRef.set({
      // Without the undo bookkeeping, which is about the settings document.
      ...Map.of(settings)..removeWhere(
        (key, _) =>
            key == 'previous' ||
            key == 'termChangedAt' ||
            key == 'undoneAcademicYear',
      ),
      'academicYear': academicYear,
      'archivedAt': FieldValue.serverTimestamp(),
      'archiveAttendance': archiveAttendance,
      'dataArchived': false,
      'headcountByCampus': ?headcountByCampus,
    });
    return true;
  }

  /// The collections a year's records are copied from, keyed by the
  /// archive collection each goes into. Attendance is left out: its logs
  /// are picked by more than their year (see
  /// [archiveAttendanceForAcademicYear]).
  static const _archivedCollections = {
    'reports': 'reports',
    'applications': 'applications',
    'screening_records': 'screeningRecords',
    'tasks': 'tasks',
    'evaluations': 'evaluations',
    'announcements': 'announcements',
    'calendar_events': 'schedule_events',
  };

  /// How many records stamped [academicYear] archiving it would copy, per
  /// archive collection. Counting reads one document per thousand records.
  Future<Map<String, int>> countRecordsToArchive(String academicYear) async {
    final counts = await Future.wait([
      for (final source in _archivedCollections.values)
        _db
            .collection(source)
            .where('academicYear', isEqualTo: academicYear)
            .count()
            .get()
            .then((snapshot) => snapshot.count ?? 0),
    ]);
    return Map.fromIterables(_archivedCollections.keys, counts);
  }

  /// How many records [academicYear]'s archive holds, per collection.
  Future<Map<String, int>> countArchivedRecords(String academicYear) async {
    final names = [..._archivedCollections.keys, 'attendance'];
    final counts = await Future.wait([
      for (final name in names)
        _academicYearArchive(academicYear)
            .collection(name)
            .count()
            .get()
            .then((snapshot) => snapshot.count ?? 0),
    ]);
    return Map.fromIterables(names, counts);
  }

  /// Takes [academicYear] off the archive list again — for an undone move
  /// to the next year — unless the Head's session has already copied its
  /// records in.
  Future<void> deleteUnprocessedAcademicYearArchive(String academicYear) async {
    final archiveRef = _academicYearArchive(academicYear);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(archiveRef);
      if (snapshot.exists && snapshot.data()?['dataArchived'] == false) {
        transaction.delete(archiveRef);
      }
    });
  }

  /// Collections whose records carry the academic year they were made in.
  static const _yearStampedCollections = [
    'attendance',
    'reports',
    'applications',
    'tasks',
    'taskDuties',
    'announcements',
    'schedule_events',
    'classSchedules',
    'evaluations',
    'screeningRecords',
  ];

  /// The id a record moved from year [from] to [to] takes, for the records
  /// whose id names their year: an application (`app_<uid>_<year>`) and a
  /// screening record (`screen-<uid>-<year>`). Null for everything else,
  /// which keeps its id and only has its year field changed.
  @visibleForTesting
  static String? movedYearId(
    String collection,
    String docId,
    Map<String, dynamic> data,
    String from,
    String to,
  ) {
    final applicantId = data['applicantId']?.toString() ?? '';
    if (applicantId.trim().isEmpty || from == to) return null;
    switch (collection) {
      case 'applications':
        return docId == Application.idFor(applicantId, from)
            ? Application.idFor(applicantId, to)
            : null;
      case 'screeningRecords':
        String idFor(String year) => ScreeningRecord.stableIdForApplicant(
          applicantId: applicantId,
          academicYear: year,
        );
        return docId == idFor(from) ? idFor(to) : null;
    }
    return null;
  }

  /// Moves every record stamped [from] to [to]: the records made while a
  /// year the Admin then undid was in effect.
  ///
  /// Applications and screening records name their year in their id, so
  /// they move to the new id (one transaction each: the rules read the old
  /// document for every application moved, and one write may only read a
  /// few). One whose new id is already taken stays in [from], where it
  /// still belongs to that year. A screening record's link to a moved
  /// application follows it.
  /// A record that can't be moved is left as it was, so the next try finds
  /// it; the other records and collections carry on, and the first error is
  /// rethrown at the end.
  Future<void> restampAcademicYear(String from, String to) async {
    Object? firstError;
    StackTrace? firstStack;
    void failed(String what, Object error, StackTrace stack) {
      debugPrint('Could not move $what from AY $from to AY $to: $error');
      firstError ??= error;
      firstStack ??= stack;
    }

    final applications = _db.collection('applications');
    for (final name in _yearStampedCollections) {
      try {
        final collection = _db.collection(name);
        final snapshot = await collection
            .where('academicYear', isEqualTo: from)
            .get();
        final updates = <(DocumentReference, Map<String, dynamic>)>[];
        for (final doc in snapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final change = <String, dynamic>{'academicYear': to};
          if (name == 'screeningRecords') {
            // Point at the application's new id once it has moved there.
            // While its application is still waiting to move (that move
            // failed above), leave the record for the next try.
            final applicantId = data['applicantId']?.toString() ?? '';
            final linked = data['applicationId']?.toString() ?? '';
            if (applicantId.trim().isNotEmpty &&
                linked == Application.idFor(applicantId, from)) {
              try {
                final left = await applications.doc(linked).get();
                if (left.exists && left.data()?['academicYear'] == from) {
                  continue;
                }
                final movedTo = Application.idFor(applicantId, to);
                final moved = await applications.doc(movedTo).get();
                if (moved.exists && !left.exists) {
                  change['applicationId'] = movedTo;
                }
              } catch (error, stack) {
                failed('$name/${doc.id}', error, stack);
                continue;
              }
            }
          }
          final newId = movedYearId(name, doc.id, data, from, to);
          if (newId != null) {
            // Its id names the undone year, so it either moves or stays in
            // that year: relabelled in place, it would sit under next
            // year's id and block (or be overwritten by) that year's real
            // application or screening.
            try {
              final target = collection.doc(newId);
              final copy = {...data, ...change};
              if (name == 'applications') copy['movedFrom'] = doc.id;
              if (name == 'screeningRecords') copy.remove('id');
              // In a transaction, so a record saved under the new id in
              // the meantime is never overwritten.
              final moved = await _db.runTransaction((tx) async {
                if ((await tx.get(target)).exists) return false;
                tx.set(target, copy);
                tx.delete(doc.reference);
                return true;
              });
              if (!moved) {
                debugPrint(
                  'Left $name/${doc.id} in AY $from: $newId already exists.',
                );
              }
            } catch (error, stack) {
              failed('$name/${doc.id}', error, stack);
            }
            continue;
          }
          updates.add((doc.reference, change));
        }
        for (var offset = 0; offset < updates.length; offset += 400) {
          final batch = _db.batch();
          for (final (ref, change) in updates.skip(offset).take(400)) {
            batch.update(ref, change);
          }
          await batch.commit();
        }
      } catch (error, stack) {
        failed(name, error, stack);
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }

  /// Marks [academicYear]'s records as copied into its archive.
  Future<void> markAcademicYearDataArchived(String academicYear) async {
    await _academicYearArchive(academicYear).update({
      'dataArchived': true,
      'dataArchivedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveAttendanceForAcademicYear(String academicYear) async {
    final attendanceSnapshot = await _attendance.get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('attendance');
    // Only this year's logs, plus any old enough to carry no year at all —
    // never a newer year's, which would stop counting toward its hours.
    final records = attendanceSnapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final year = data['academicYear'];
      return data['isArchived'] != true &&
          (year == null || year == academicYear);
    }).toList();
    for (var offset = 0; offset < records.length; offset += 200) {
      final batch = _db.batch();
      final chunk = records.skip(offset).take(200);
      for (final record in chunk) {
        final data = Map<String, dynamic>.from(
          record.data() as Map<String, dynamic>,
        );
        data['archivedAt'] = FieldValue.serverTimestamp();
        batch.set(archiveCollection.doc(record.id), data);
        batch.update(record.reference, {
          'isArchived': true,
          'archivedAcademicYear': academicYear,
          'archivedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> archiveReportsForAcademicYear(String academicYear) async {
    final reportSnapshot = await _reports
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('reports');
    for (final report in reportSnapshot.docs) {
      final data = Map<String, dynamic>.from(
        report.data() as Map<String, dynamic>,
      );
      final attachments = (data['attachments'] as List<dynamic>?) ?? [];
      final archivedAttachments = <Map<String, dynamic>>[];
      for (final rawAttachment in attachments) {
        final attachment = ReportAttachment.fromJson(
          Map<String, dynamic>.from(rawAttachment as Map),
        );
        if (attachment.storagePath.isEmpty) {
          archivedAttachments.add(attachment.toJson());
          continue;
        }
        final archivePath =
            'academic_year_archives/$academicYear/reports/${report.id}/${randomObjectName(attachment.fileName)}';
        try {
          final archivedUrl = await SupabaseStorageService.instance
              .archiveDocument(
                sourcePath: attachment.storagePath,
                archivePath: archivePath,
              );
          archivedAttachments.add({
            ...attachment.toJson(),
            'storagePath': archivePath,
            'downloadUrl': archivedUrl,
          });
        } catch (error) {
          debugPrint(
            'Failed to archive report attachment ${attachment.storagePath}: $error',
          );
          archivedAttachments.add(attachment.toJson());
        }
      }
      data['attachments'] = archivedAttachments;
      data['archivedAt'] = FieldValue.serverTimestamp();
      await archiveCollection.doc(report.id).set(data);
    }
  }

  Future<void> archiveApplicationsForAcademicYear(String academicYear) async {
    final applicationSnapshot = await _applications
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('applications');
    for (final application in applicationSnapshot.docs) {
      final data = Map<String, dynamic>.from(
        application.data() as Map<String, dynamic>,
      );
      final documents = (data['submittedDocuments'] as List<dynamic>?) ?? [];
      final archivedDocuments = <Map<String, dynamic>>[];
      for (final rawDocument in documents) {
        final document = ApplicationDocument.fromJson(
          Map<String, dynamic>.from(rawDocument as Map),
        );
        if (document.storagePath == null || document.storagePath!.isEmpty) {
          archivedDocuments.add(document.toJson());
          continue;
        }
        final archivePath =
            'academic_year_archives/$academicYear/applications/${application.id}/${randomObjectName(document.fileName)}';
        try {
          final archivedUrl = await SupabaseStorageService.instance
              .archiveDocument(
                sourcePath: document.storagePath!,
                archivePath: archivePath,
              );
          archivedDocuments.add({
            ...document.toJson(),
            'storagePath': archivePath,
            'downloadUrl': archivedUrl,
          });
        } catch (error) {
          debugPrint(
            'Failed to archive application document ${document.storagePath}: $error',
          );
          archivedDocuments.add(document.toJson());
        }
      }
      data['submittedDocuments'] = archivedDocuments;
      data['archivedAt'] = FieldValue.serverTimestamp();
      await archiveCollection.doc(application.id).set(data);
    }
  }

  Future<List<Map<String, dynamic>>> getAcademicYearArchives() async {
    final snapshot = await _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .orderBy('academicYear', descending: true)
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  CollectionReference get _offices => _db.collection('offices');

  CollectionReference get _departments => _db.collection('departments');

  Future<List<String>> getAllDepartments() async {
    final snapshot = await _departments.orderBy('name').get();
    return snapshot.docs
        .map(
          (doc) =>
              (doc.data() as Map<String, dynamic>)['name']?.toString() ?? '',
        )
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<Map<String, String>> getDepartmentCodes() async {
    final snapshot = await _departments.get();
    return {
      for (final doc in snapshot.docs)
        if ((doc.data() as Map<String, dynamic>)['name']
                ?.toString()
                .isNotEmpty ==
            true)
          (doc.data() as Map<String, dynamic>)['name'].toString():
              (doc.data() as Map<String, dynamic>)['code']?.toString() ?? '',
    };
  }

  Future<void> setDepartment(String name, {String code = ''}) async {
    await _departments.doc(name).set({
      'name': name,
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteDepartment(String name) async {
    await _departments.doc(name).delete();
  }

  Future<void> updateDepartment(String oldName, String newName) async {
    await setDepartment(newName);
    if (oldName != newName) await deleteDepartment(oldName);
  }

  CollectionReference get _programs => _db.collection('programs');

  Future<List<Program>> getAllPrograms() async {
    final snapshot = await _programs.get();
    return snapshot.docs
        .map(
          (doc) => Program.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  /// Saves [program], creating it when its id is empty. Returns its id.
  Future<String> saveProgram(Program program) async {
    final data = {
      ...program.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (program.id.isEmpty) {
      final doc = await _programs.add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    }
    await _programs.doc(program.id).set(data, SetOptions(merge: true));
    return program.id;
  }

  /// Creates all of [programs] in one write: every one is saved or none is.
  /// Returns them with their new ids. (A batch holds up to 500 writes; the
  /// app asks for at most 50.)
  Future<List<Program>> saveProgramsBatch(List<Program> programs) async {
    final batch = _db.batch();
    final created = <Program>[];
    for (final program in programs) {
      final doc = _programs.doc();
      batch.set(doc, {
        ...program.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      created.add(
        Program(
          id: doc.id,
          code: program.code,
          name: program.name,
          department: program.department,
        ),
      );
    }
    await batch.commit();
    return created;
  }

  Future<void> deleteProgram(String id) async {
    await _programs.doc(id).delete();
  }

  CollectionReference get _skills => _db.collection('skills');

  Future<List<String>> getAllSkills() async {
    final snapshot = await _skills.orderBy('name').get();
    return snapshot.docs
        .map(
          (doc) =>
              (doc.data() as Map<String, dynamic>)['name']?.toString() ?? '',
        )
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> setSkill(String name) async {
    await _skills.doc(name).set({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteSkill(String name) async {
    await _skills.doc(name).delete();
  }

  Future<void> updateSkill(String oldName, String newName) async {
    await setSkill(newName);
    if (oldName != newName) await deleteSkill(oldName);
  }

  Future<List<Office>> getAllOffices() async {
    final snapshot = await _offices.get();
    return snapshot.docs
        .map(
          (doc) => Office.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  Future<void> setOffice(Office office) async {
    await _offices.doc(office.id).set(office.toJson());
  }

  /// Reads the offices [ids] as they are now, lets [edit] change them, and
  /// writes the ones it returns, all in one transaction. A roster edited from
  /// a stale copy would otherwise erase what someone else just did, and an
  /// edit that spans two offices (a move) would land on only one of them.
  ///
  /// [edit] gets the stored offices by id and returns the ones to save, or
  /// null to change nothing (a full office, a vanished one). It may run more
  /// than once, so it must only look at what it is given. Returns what was
  /// saved, or null when [edit] declined.
  ///
  /// [people] are the account ids whose place is being decided. Their
  /// officeAssignments documents are read first (so the office each is in
  /// *now* is read too, whichever the caller thought), and rewritten to
  /// follow the result. Two Heads placing the same person in different
  /// offices then collide on that one document: the second is retried and
  /// sees the first's office instead of leaving the person in both.
  Future<Map<String, Office>?> updateOffices(
    Iterable<String> ids,
    Map<String, Office>? Function(Map<String, Office> stored) edit, {
    Iterable<String> people = const [],
  }) {
    // Someone listed by name alone has no account id, so no assignment
    // document (and Firestore refuses an empty document path).
    final persons = people.where((p) => p.isNotEmpty).toSet();
    return _db.runTransaction((transaction) async {
      final officeIds = {...ids};
      final assigned = <String, String>{};
      for (final person in persons) {
        final snapshot = await transaction.get(_officeAssignments.doc(person));
        final office = snapshot.exists
            ? (snapshot.data() as Map<String, dynamic>)['officeId']?.toString()
            : null;
        if (office != null && office.isNotEmpty) {
          assigned[person] = office;
          officeIds.add(office);
        }
      }
      final stored = <String, Office>{};
      for (final id in officeIds) {
        final snapshot = await transaction.get(_offices.doc(id));
        if (!snapshot.exists) continue;
        stored[id] = Office.fromJson({
          ...(snapshot.data() as Map<String, dynamic>),
          'id': snapshot.id,
        });
      }
      final changed = edit(stored);
      if (changed == null) return null;
      for (final entry in changed.entries) {
        transaction.set(_offices.doc(entry.key), entry.value.toJson());
      }
      // Each person's document follows the offices as they now stand.
      final result = {...stored, ...changed};
      for (final person in persons) {
        final home = result.values
            .where((office) => office.assistantIds.contains(person))
            .firstOrNull;
        final ref = _officeAssignments.doc(person);
        if (home == null) {
          transaction.delete(ref);
        } else {
          transaction.set(ref, {'officeId': home.id});
        }
      }
      return changed;
    });
  }

  Future<void> deleteOffice(String id) async {
    await _offices.doc(id).delete();
  }

  // Office assignments: officeAssignments/{uid} = {officeId}, one per
  // student assistant. The Firestore rules read these to limit each
  // Supervisor to their own office's students; only the Head writes them.
  CollectionReference get _officeAssignments =>
      _db.collection('officeAssignments');

  Future<Map<String, String>> getOfficeAssignments() async {
    final snapshot = await _officeAssignments.get();
    return {
      for (final doc in snapshot.docs)
        doc.id:
            (doc.data() as Map<String, dynamic>)['officeId']?.toString() ?? '',
    };
  }

  /// Applies [changes] (account id → office id, or null to remove) in
  /// batches.
  Future<void> writeOfficeAssignments(Map<String, String?> changes) async {
    final entries = changes.entries.toList();
    for (var offset = 0; offset < entries.length; offset += 400) {
      final batch = _db.batch();
      for (final entry in entries.skip(offset).take(400)) {
        final ref = _officeAssignments.doc(entry.key);
        if (entry.value == null) {
          batch.delete(ref);
        } else {
          batch.set(ref, {'officeId': entry.value});
        }
      }
      await batch.commit();
    }
  }

  /// One-time move of schedules from name keys to account keys.
  ///
  /// Weekly schedules (recurringSchedules) were keyed by the owner's name,
  /// lowercased, and calendar events (schedule_events) carried only
  /// `ownerName`. The Firestore rules now decide access by account, so this
  /// copies each weekly schedule to a document keyed by its owner's account
  /// and stamps `ownerId` on each event. [accountIdByName] maps a lowercased,
  /// trimmed name to its account; names shared by two accounts should be
  /// left out, since there's no telling whose schedule it is. Anything left
  /// unmatched stays visible to the Head only.
  ///
  /// Needs the Head's access, and records that it ran in
  /// meta/schedule_owners_migrated so it only runs once. Safe to rerun if it
  /// stops partway: it only touches schedules that have no account yet.
  Future<void> moveSchedulesToAccounts(
    Map<String, String> accountIdByName,
  ) async {
    final marker = _db.collection('meta').doc('schedule_owners_migrated');
    if ((await marker.get()).exists) return;

    String? accountFor(String? name) =>
        name == null ? null : accountIdByName[name.trim().toLowerCase()];

    final weekly = await _db.collection('recurringSchedules').get();
    final keyedByAccount = weekly.docs.map((doc) => doc.id).toSet();
    var schedulesMoved = 0;
    var schedulesUnmatched = 0;
    for (final doc in weekly.docs) {
      final data = doc.data();
      if (data['ownerId'] != null) continue;
      final ownerId =
          accountFor(data['ownerName']?.toString()) ?? accountFor(doc.id);
      if (ownerId == null) {
        schedulesUnmatched++;
        continue;
      }
      // One already saved under the account is newer; keep it.
      if (keyedByAccount.contains(ownerId)) continue;
      await _db.collection('recurringSchedules').doc(ownerId).set({
        ...data,
        'ownerId': ownerId,
      });
      keyedByAccount.add(ownerId);
      schedulesMoved++;
    }

    final events = await _db.collection('schedule_events').get();
    final ownerByEvent = <String, String>{};
    var eventsUnmatched = 0;
    for (final doc in events.docs) {
      final data = doc.data();
      if (data['ownerId'] != null) continue;
      final ownerId = accountFor(data['ownerName']?.toString());
      if (ownerId == null) {
        eventsUnmatched++;
      } else {
        ownerByEvent[doc.id] = ownerId;
      }
    }
    final entries = ownerByEvent.entries.toList();
    for (var offset = 0; offset < entries.length; offset += 400) {
      final batch = _db.batch();
      for (final entry in entries.skip(offset).take(400)) {
        batch.update(_db.collection('schedule_events').doc(entry.key), {
          'ownerId': entry.value,
        });
      }
      await batch.commit();
    }

    await marker.set({
      'schedulesMoved': schedulesMoved,
      'schedulesUnmatched': schedulesUnmatched,
      'eventsUpdated': entries.length,
      'eventsUnmatched': eventsUnmatched,
      'migratedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<User?> getUserProfileById(String id) async {
    final doc = await _users.doc(id).get();
    if (!doc.exists) return null;
    return User.fromJson({
      ...(doc.data() as Map<String, dynamic>),
      'id': doc.id,
    });
  }

  Future<User?> getUserProfileByEmail(String email) async {
    final snapshot = await _users
        .where('email', isEqualTo: email.toLowerCase())
        .get();
    if (snapshot.docs.isEmpty) return null;

    // Prefer the highest-privilege profile when duplicate records exist for
    // an email, so an older Student document cannot hide a saved Admin role.
    final rolePriority = {
      'Admin': 5,
      'Head': 4,
      'Supervisor': 3,
      'Student Assistant': 2,
      'Student': 1,
    };
    final doc = snapshot.docs.reduce((first, next) {
      final firstRole = (first.data() as Map<String, dynamic>)['role'];
      final nextRole = (next.data() as Map<String, dynamic>)['role'];
      return (rolePriority[firstRole] ?? 0) >= (rolePriority[nextRole] ?? 0)
          ? first
          : next;
    });
    return User.fromJson({
      ...(doc.data() as Map<String, dynamic>),
      'id': doc.id,
    });
  }

  /// Looks up a user profile by Student ID. Used to make sure a Student ID
  /// can't be claimed by more than one account during registration.
  // Student ID reservations: studentIds/{key} → {uid}. See the rules.
  CollectionReference<Map<String, dynamic>> get _studentIds =>
      _db.collection('studentIds');

  /// Reserves the Student ID [key] for the account [uid], unless another
  /// account holds it. Returns whether [uid] holds it now.
  Future<bool> claimStudentId(String key, String uid) {
    final doc = _studentIds.doc(key);
    return _db.runTransaction((transaction) async {
      final holder = (await transaction.get(doc)).data()?['uid'];
      if (holder != null) return holder == uid;
      transaction.set(doc, {'uid': uid});
      return true;
    });
  }

  Future<void> releaseStudentId(String key) => _studentIds.doc(key).delete();

  /// Frees the Student ID [key] if it still names [holder] and [holder] has
  /// no profile at all (a registration whose profile was removed without its
  /// reservation). Read and delete happen in one transaction, so a claim
  /// that changed hands, or a profile that appeared meanwhile, is left
  /// alone. Returns whether it freed the ID. Admin and Head only.
  Future<bool> releaseOrphanStudentIdClaim(String key, String holder) {
    final claim = _studentIds.doc(key);
    return _db.runTransaction((transaction) async {
      final current = (await transaction.get(claim)).data()?['uid'];
      if (current != holder) return false;
      final profile = await transaction.get(_users.doc(holder));
      if (profile.exists) return false;
      transaction.delete(claim);
      return true;
    });
  }

  /// The account holding the Student ID [key], or null when it's free.
  /// Any signed-in account may ask about one ID (the rules).
  Future<String?> studentIdHolder(String key) async {
    final holder = (await _studentIds.doc(key).get()).data()?['uid'];
    return holder is String ? holder : null;
  }

  /// Puts the checked Student ID [key] on [uid]'s profile, marked verified,
  /// and reserves it, in one transaction, unless another account holds it.
  /// Returns that account's id, or null when it's done. The Head's, on
  /// approving an application.
  Future<String?> verifyStudentId(
    String uid,
    String key, {
    required String verifiedBy,
    required String verifiedAt,
  }) {
    final claim = _studentIds.doc(key);
    return _db.runTransaction((transaction) async {
      final holder = (await transaction.get(claim)).data()?['uid'];
      if (holder is String && holder != uid) return holder;
      if (holder == null) transaction.set(claim, {'uid': uid});
      transaction.update(_users.doc(uid), {
        'studentId': key,
        'studentIdVerifiedAt': verifiedAt,
        'studentIdVerifiedBy': verifiedBy,
      });
      return null;
    });
  }

  /// Every reservation, Student ID key → account id. Admin and Head only.
  Future<Map<String, String>> getStudentIdClaims() async {
    final snapshot = await _studentIds.get();
    return {
      for (final doc in snapshot.docs)
        if (doc.data()['uid'] is String) doc.id: doc.data()['uid'] as String,
    };
  }

  /// Sets (account id) or removes (null) each reservation in [changes].
  Future<void> writeStudentIdClaims(Map<String, String?> changes) async {
    final entries = changes.entries.toList();
    for (var i = 0; i < entries.length; i += 500) {
      final batch = _db.batch();
      for (final entry in entries.skip(i).take(500)) {
        final doc = _studentIds.doc(entry.key);
        final uid = entry.value;
        if (uid == null) {
          batch.delete(doc);
        } else {
          batch.set(doc, {'uid': uid});
        }
      }
      await batch.commit();
    }
  }

  Future<List<User>> getAllUserProfiles() async {
    final snapshot = await _users.get();
    return snapshot.docs
        .map(
          (doc) => User.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  // Students
  CollectionReference get _students => _db.collection('students');

  Future<List<Student>> getAllStudents() async {
    final snap = await _students.get();
    return snap.docs
        .map(
          (d) => Student.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<String>> getStudentIdsForUser(String uid) async {
    final snap = await _students.where('userId', isEqualTo: uid).get();
    return snap.docs.map((doc) => doc.id).toList();
  }

  Map<String, dynamic> _studentData(Student s) => {
    'name': s.name,
    'email': s.email,
    'department': s.department,
    'campus': s.campus,
    'status': s.status,
    'totalHours': s.totalHours,
    'phone': s.phone,
    'address': s.address,
    'avatar': s.avatar,
    'userId': s.userId,
  }..removeWhere((k, v) => v == null);

  Future<void> setStudent(Student s) async {
    final data = _studentData(s);
    if (s.id.isNotEmpty) {
      await _students.doc(s.id).set(data);
    } else {
      await _students.add(data);
    }
  }

  /// Saves a students record and its account's profile in one write, so a
  /// change to both (a student moved to another department) never lands on
  /// only one of them.
  Future<void> setStudentWithProfile(Student s, User profile) async {
    final batch = _db.batch();
    batch.set(_students.doc(s.id), _studentData(s));
    batch.set(_users.doc(profile.id), profile.toJson());
    await batch.commit();
  }

  Future<void> deleteStudent(String id) async {
    await _students.doc(id).delete();
  }

  // Attendance
  CollectionReference get _attendance => _db.collection('attendance');

  Future<List<Map<String, dynamic>>> getAllAttendance() async {
    final snap = await _attendance.get();
    return snap.docs
        .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAttendanceForStudent(String uid) async {
    final snap = await _attendance.where('studentId', isEqualTo: uid).get();
    return snap.docs
        .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
        .toList();
  }

  Future<DocumentReference> addAttendance(
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final payload = {...data, 'createdAt': FieldValue.serverTimestamp()};
    if (id != null && id.isNotEmpty) {
      final docRef = _attendance.doc(id);
      await docRef.set(payload);
      return docRef;
    }
    return await _attendance.add(payload);
  }

  Future<void> deleteAttendance(String id) async {
    await _attendance.doc(id).delete();
  }

  Future<void> updateAttendance(String id, Map<String, dynamic> data) async {
    await _attendance.doc(id).update(data);
  }

  // ── Approved class schedules and requests to change them ──
  //
  // The approved ones live beside the weekly rules in
  // `recurringSchedules/{account id}` (`classSchedules`, which only a Head
  // may write); a Student Assistant's change waits in `scheduleRequests`.

  CollectionReference get _scheduleRequests =>
      _db.collection('scheduleRequests');

  DocumentReference<Map<String, dynamic>> _ownerSchedule(String ownerId) =>
      _db.collection('recurringSchedules').doc(ownerId);

  /// Saves a Student Assistant's new request, stamped with the server's time.
  Future<void> createScheduleRequest(ScheduleRequest request) =>
      _scheduleRequests.doc(request.id).set({
        ...request.toNewJson(),
        'submittedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateScheduleRequest(String id, Map<String, dynamic> fields) =>
      _scheduleRequests.doc(id).update(fields);

  Future<OwnerSchedule> getOwnerSchedule(String ownerId) async {
    final snap = await _ownerSchedule(ownerId).get();
    return OwnerSchedule.fromJson(snap.data());
  }

  /// Adds [version] to [ownerId]'s approved class schedules and drops the
  /// subjects typed into their weekly rules, in one transaction, so two
  /// Heads approving at once can't lose one. With [requestId], the request
  /// is decided in the same transaction, and only while it is still
  /// Pending.
  ///
  /// Returns 'saved', 'not-pending' (the request was cancelled or decided
  /// meanwhile; nothing written) or 'already' (a version from the same
  /// source is there; nothing written). Never throws its own errors from
  /// inside the transaction: on the web they come back wrapped.
  Future<String> addClassScheduleVersion({
    required String ownerId,
    required String ownerName,
    required ClassScheduleVersion version,
    String? requestId,
    Map<String, dynamic>? requestFields,
  }) {
    return _db.runTransaction<String>((tx) async {
      final ownerRef = _ownerSchedule(ownerId);
      final requestRef = requestId == null
          ? null
          : _scheduleRequests.doc(requestId);
      final ownerSnap = await tx.get(ownerRef);
      if (requestRef != null) {
        final requestSnap = await tx.get(requestRef);
        final data = requestSnap.data() as Map<String, dynamic>?;
        if (data == null || data['status'] != ScheduleRequest.pending) {
          return 'not-pending';
        }
      }
      final data = ownerSnap.data() ?? const <String, dynamic>{};
      final versions = List<dynamic>.from(
        data['classSchedules'] as List? ?? const [],
      );
      if (version.sourceId.isNotEmpty &&
          versions.any(
            (v) =>
                v is Map &&
                v['source'] == version.source &&
                v['sourceId'] == version.sourceId,
          )) {
        return 'already';
      }
      final rules = [
        for (final r in (data['rules'] as List? ?? const []))
          if (r is Map && r['isSubject'] != true &&
              !(r['isSubject'] == null &&
                  (r['units']?.toString() ?? '').isNotEmpty))
            r,
      ];
      tx.set(ownerRef, {
        'ownerId': ownerId,
        'ownerName': ownerName,
        'rules': rules,
        'classSchedules': [...versions, version.toJson()],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (requestRef != null) tx.update(requestRef, requestFields ?? {});
      return 'saved';
    });
  }

  /// Deletes [ownerId]'s calendar entries whose id starts with one of
  /// [prefixes] (the days the old typed subjects filled in), in batches.
  Future<int> deleteScheduleEventsWithPrefixes(
    String ownerId,
    List<String> prefixes,
  ) async {
    if (prefixes.isEmpty) return 0;
    final snap = await _db
        .collection('schedule_events')
        .where('ownerId', isEqualTo: ownerId)
        .get();
    final doomed = snap.docs
        .where((d) => prefixes.any((p) => d.id.startsWith(p)))
        .toList();
    for (var offset = 0; offset < doomed.length; offset += 400) {
      final batch = _db.batch();
      for (final doc in doomed.skip(offset).take(400)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    return doomed.length;
  }

  // Class Schedule
  CollectionReference get _classSchedules => _db.collection('classSchedules');

  Future<List<ClassScheduleEntry>> getAllClassSchedules() async {
    final snap = await _classSchedules.get();
    return snap.docs
        .map(
          (d) => ClassScheduleEntry.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<ClassScheduleEntry>> getClassSchedulesForStudent(
    String uid,
  ) async {
    final snap = await _classSchedules.where('studentId', isEqualTo: uid).get();
    return snap.docs
        .map(
          (d) => ClassScheduleEntry.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<ClassScheduleEntry> addClassScheduleEntry(ClassScheduleEntry c) async {
    final data = c.toJson()..remove('id');
    final docRef = await _classSchedules.add(data);
    return ClassScheduleEntry(
      id: docRef.id,
      studentId: c.studentId,
      studentName: c.studentName,
      course: c.course,
      units: c.units,
      monday: c.monday,
      tuesday: c.tuesday,
      wednesday: c.wednesday,
      thursday: c.thursday,
      friday: c.friday,
      saturday: c.saturday,
      academicYear: c.academicYear,
      sourceRuleLabel: c.sourceRuleLabel,
    );
  }

  Future<void> deleteClassScheduleEntry(String id) async {
    await _classSchedules.doc(id).delete();
  }

  /// Deletes every saved class-schedule row for [studentName], so a fresh
  /// set can be written in its place (used when a supervisor re-saves the
  /// whole grid from the DTR/Accomplishment Report screen).
  Future<void> deleteClassScheduleEntriesForStudent(String studentName) async {
    final snap = await _classSchedules
        .where('studentName', isEqualTo: studentName)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  /// Whether a class-schedule row saved under [rowStudentId] and
  /// [rowStudentName] is the schedule of the student [studentId] /
  /// [studentName]. The id decides it, since two students can share a name;
  /// only a row saved without one goes by the name.
  static bool isClassScheduleOf({
    required String rowStudentId,
    required String rowStudentName,
    required String studentId,
    required String studentName,
  }) {
    if (studentId.isNotEmpty && rowStudentId.isNotEmpty) {
      return rowStudentId == studentId;
    }
    return rowStudentName == studentName;
  }

  /// Replaces the saved class schedule of [studentId] / [studentName] with
  /// [rows] in one write: the old rows go and the new ones arrive together,
  /// so a save that fails changes nothing, and two saves at once can't leave
  /// both their rows behind. Returns [rows] with the ids they were saved
  /// under.
  Future<List<ClassScheduleEntry>> replaceClassSchedule(
    String studentId,
    String studentName,
    List<ClassScheduleEntry> rows,
  ) async {
    final old = <String, DocumentReference>{};
    void collect(QuerySnapshot snap) {
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? const {};
        final owner = data['studentId'];
        if (isClassScheduleOf(
          rowStudentId: owner is String ? owner : '',
          rowStudentName: data['studentName']?.toString() ?? '',
          studentId: studentId,
          studentName: studentName,
        )) {
          old[doc.id] = doc.reference;
        }
      }
    }

    collect(
      await _classSchedules.where('studentName', isEqualTo: studentName).get(),
    );
    if (studentId.isNotEmpty) {
      collect(
        await _classSchedules.where('studentId', isEqualTo: studentId).get(),
      );
    }

    final batch = _db.batch();
    for (final ref in old.values) {
      batch.delete(ref);
    }
    final saved = <ClassScheduleEntry>[];
    for (final row in rows) {
      final ref = _classSchedules.doc();
      batch.set(ref, row.toJson()..remove('id'));
      saved.add(ClassScheduleEntry.fromJson({...row.toJson(), 'id': ref.id}));
    }
    await batch.commit();
    return saved;
  }

  // Tasks
  CollectionReference get _tasks => _db.collection('tasks');

  Future<List<Task>> getAllTasks() async {
    final snap = await _tasks.orderBy('createdAt', descending: true).get();
    return snap.docs
        .map(
          (d) => Task.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Task>> getTasksForUser(String uid) async {
    final snap = await _tasks
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map(
          (d) => Task.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Task>> getTasksForAssigneeIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final snap = await _tasks.where('assignedTo', whereIn: ids).get();
    return snap.docs
        .map(
          (d) => Task.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setTask(Task t) async {
    final data = {
      'title': t.title,
      'description': t.description,
      'status': t.status,
      'priority': t.priority,
      'dueDate': t.dueDate,
      'assignedTo': t.assignedTo,
      'assignedToName': t.assignedToName,
      'assignedBy': t.assignedBy,
      'category': t.category,
      'checklistItems': t.checklistItems,
      'isArchived': t.isArchived,
      'academicYear': t.academicYear,
      'dutyId': t.dutyId,
      'attendanceId': t.attendanceId,
      'workDate': t.workDate,
    }..removeWhere((k, v) => v == null);
    final clearable = {
      'completedAt': t.completedAt,
      'reviewStatus': t.reviewStatus,
      'reviewedAt': t.reviewedAt,
      'reviewedBy': t.reviewedBy,
      'reviewNote': t.reviewNote,
    };
    data.addAll({
      for (final e in clearable.entries)
        if (e.value != null) e.key: e.value,
    });

    if (t.id.isNotEmpty) {
      final docRef = _tasks.doc(t.id);
      final existing = await docRef.get();
      // The save merges, which would keep a cleared field's old value: a
      // task sent back to In Progress would come back from the server
      // still completed or reviewed. So cleared fields are deleted.
      if (existing.exists) {
        data.addAll({
          for (final e in clearable.entries)
            if (e.value == null) e.key: FieldValue.delete(),
        });
      }
      if (existing.exists &&
          (existing.data() as Map<String, dynamic>?)?.containsKey(
                'createdAt',
              ) ==
              true) {
        await docRef.set(data, SetOptions(merge: true));
      } else {
        await docRef.set({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } else {
      final payload = {...data, 'createdAt': FieldValue.serverTimestamp()};
      await _tasks.add(payload);
    }
  }

  /// Saves the task that logs a day of an ongoing duty, by the Student
  /// Assistant who did it. A plain write: the rules decide whether it is
  /// theirs to make (their own duty, the day they clocked in, once), and a
  /// read first would be refused for a task that isn't there yet.
  Future<void> createDutyLog(Task t) async {
    await _tasks.doc(t.id).set({
      'title': t.title,
      'description': t.description,
      'status': t.status,
      'priority': t.priority,
      'dueDate': t.dueDate,
      'assignedTo': t.assignedTo,
      'assignedToName': t.assignedToName,
      'assignedBy': t.assignedBy,
      'category': t.category,
      'checklistItems': t.checklistItems,
      'isArchived': false,
      'academicYear': t.academicYear,
      'completedAt': t.completedAt,
      'reviewStatus': t.reviewStatus,
      'dutyId': t.dutyId,
      'attendanceId': t.attendanceId,
      'workDate': t.workDate,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Ongoing duties, in `taskDuties`.
  Future<void> setTaskDuty(TaskDuty duty) async {
    await _db.collection('taskDuties').doc(duty.id).set({
      ...duty.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setTaskDutyActive(String id, bool active) async {
    await _db.collection('taskDuties').doc(id).update({'active': active});
  }

  Future<void> deleteTask(String id) async {
    await _tasks.doc(id).delete();
  }

  Future<void> archiveTasksForAcademicYear(String academicYear) async {
    final snapshot = await _tasks
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _db
        .collection('meta')
        .doc('academic_year_archives')
        .collection('years')
        .doc(academicYear)
        .collection('tasks');
    for (final task in snapshot.docs) {
      await archiveCollection.doc(task.id).set({
        ...(task.data() as Map<String, dynamic>),
        'archivedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Supervisors' performance evaluations — what rehire decisions were
  /// based on. A document an evaluation was sent to the Head with keeps its
  /// link: it can be generated again from the evaluation itself.
  Future<void> archiveEvaluationsForAcademicYear(String academicYear) =>
      _copyIntoArchive(_evaluations, academicYear, 'evaluations');

  /// Applicant screening results. The result document a screening produces
  /// is filed with the application, which is archived with its documents.
  Future<void> archiveScreeningRecordsForAcademicYear(String academicYear) =>
      _copyIntoArchive(_screeningRecords, academicYear, 'screening_records');

  /// Copies [source]'s records stamped [academicYear] into that year's
  /// archive, under [archiveName].
  Future<void> _copyIntoArchive(
    CollectionReference source,
    String academicYear,
    String archiveName,
  ) async {
    final snapshot = await source
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final archiveCollection = _academicYearArchive(
      academicYear,
    ).collection(archiveName);
    for (final record in snapshot.docs) {
      await archiveCollection.doc(record.id).set({
        ...(record.data() as Map<String, dynamic>),
        'archivedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Reports
  CollectionReference get _reports => _db.collection('reports');

  Future<List<Report>> getAllReports() async {
    final snap = await _reports.get();
    return snap.docs
        .map(
          (d) => Report.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<List<Report>> getReportsForApplicant(String uid) async {
    final snap = await _reports.where('applicantId', isEqualTo: uid).get();
    return snap.docs
        .map(
          (d) => Report.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  /// Ping reports collection and return elapsed milliseconds or -1 on failure.
  Future<int> pingReports() async {
    try {
      final sw = Stopwatch()..start();
      await _reports.limit(1).get();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  Future<void> setReport(Report r) async {
    final data = {
      'applicantId': r.applicantId,
      'title': r.title,
      'content': r.content,
      'studentName': r.studentName,
      'status': r.status,
      'submittedAt': r.submittedAt,
      'feedback': r.feedback,
      'academicYear': r.academicYear,
      'attachments': r.attachments
          .map((attachment) => attachment.toJson())
          .toList(),
      'sentToHead': r.sentToHead,
      'sentToHeadAt': r.sentToHeadAt,
      'headAttachments': r.headAttachments
          .map((attachment) => attachment.toJson())
          .toList(),
      'taskIds': r.taskIds.isEmpty ? null : r.taskIds,
      'reviewedBy': r.reviewedBy,
      'reviewedAt': r.reviewedAt,
    }..removeWhere((k, v) => v == null);
    if (r.id.isNotEmpty) {
      await _reports.doc(r.id).set(data);
    } else {
      await _reports.add(data);
    }
  }

  // Items a Supervisor has forwarded to the Head (reports, evaluations,
  // DTR/Accomplishment reports) — shown on the Head's dedicated screen.
  CollectionReference get _headForwards => _db.collection('headForwards');

  Future<List<HeadForward>> getAllHeadForwards() async {
    final snap = await _headForwards.get();
    return snap.docs
        .map(
          (d) => HeadForward.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<String> addHeadForward(HeadForward forward) async {
    final ref = await _headForwards.add(forward.toJson());
    return ref.id;
  }

  /// Streams forwarded items in real time so the Head's "Sent to Head"
  /// screen updates immediately, even if it was already open when a
  /// supervisor sends something (or the Head logged in earlier).
  Stream<List<Map<String, dynamic>>> headForwardsStream() {
    return _headForwards.snapshots().map(
      (snap) => snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList(),
    );
  }

  Future<void> setHeadForwardReviewed(String id, bool reviewed) async {
    await _headForwards.doc(id).update({'reviewed': reviewed});
  }

  // Payroll: one processed record per Student Assistant per month, created
  // by an Admin running the Payroll screen's "Process Payroll" action.
  CollectionReference get _payrollRecords => _db.collection('payrollRecords');

  Future<List<PayrollRecord>> getAllPayrollRecords() async {
    final snap = await _payrollRecords.get();
    return snap.docs
        .map(
          (d) => PayrollRecord.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Stream<List<Map<String, dynamic>>> payrollRecordsStream() {
    return _payrollRecords.snapshots().map(
      (snap) => snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList(),
    );
  }

  /// Saves [record] under its id unless a record is already there, in one
  /// transaction. Returns whether it was saved.
  Future<bool> createPayrollRecord(PayrollRecord record) {
    final ref = _payrollRecords.doc(record.id);
    return _db.runTransaction((transaction) async {
      if ((await transaction.get(ref)).exists) return false;
      transaction.set(ref, record.toJson());
      return true;
    });
  }

  Future<void> updatePayrollRecord(String id, Map<String, dynamic> data) async {
    await _payrollRecords.doc(id).update(data);
  }

  /// Marks the payroll record [id] released, only if it is still 'Approved'
  /// when this runs (two Admins releasing together would otherwise both pay
  /// and both notify). Returns whether this call was the one that did it.
  Future<bool> releasePayrollRecord(String id, Map<String, dynamic> data) {
    final ref = _payrollRecords.doc(id);
    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists ||
          (snapshot.data() as Map<String, dynamic>)['status'] != 'Approved') {
        return false;
      }
      transaction.update(ref, data);
      return true;
    });
  }

  // Payroll sheets: the Admin's edited copy of the printed Hourly Wage
  // Payroll, one document per pay period (see PayrollSheet.idForPeriod).
  CollectionReference get _payrollSheets => _db.collection('payrollSheets');

  Stream<List<Map<String, dynamic>>> payrollSheetsStream() {
    return _payrollSheets.snapshots().map(
      (snap) => snap.docs
          .map((d) => {...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList(),
    );
  }

  Future<void> setPayrollSheet(PayrollSheet sheet) async {
    await _payrollSheets.doc(sheet.id).set(sheet.toJson());
  }

  // Payroll checks: the Head's check of each Student Assistant's payroll
  // requirements, one document per student (see PayrollCheck).
  CollectionReference get _payrollChecks => _db.collection('payrollChecks');

  /// Saves the Head's [mark] on one requirement, or clears it when null.
  /// Other requirements on the student's document are left as they are.
  Future<void> setPayrollCheckItem({
    required String studentId,
    required String studentName,
    required String key,
    required PayrollCheckMark? mark,
  }) async {
    await _payrollChecks.doc(studentId).set({
      'studentId': studentId,
      'studentName': studentName,
      'items': {key: mark?.toJson() ?? FieldValue.delete()},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Leaves a student out of one term's payroll, or brings them back when
  /// [exclusion] is null.
  Future<void> setPayrollExclusion({
    required String studentId,
    required String studentName,
    required String termLabel,
    required PayrollExclusion? exclusion,
  }) async {
    await _payrollChecks.doc(studentId).set({
      'studentId': studentId,
      'studentName': studentName,
      'exclusions': {termLabel: exclusion?.toJson() ?? FieldValue.delete()},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Performance Evaluations
  CollectionReference get _evaluations => _db.collection('evaluations');

  Future<List<Evaluation>> getAllEvaluations() async {
    final snap = await _evaluations.get();
    return snap.docs
        .map(
          (d) => Evaluation.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setEvaluation(Evaluation e) async {
    final data = e.toJson();
    if (e.id.isNotEmpty) {
      await _evaluations.doc(e.id).set(data);
    } else {
      await _evaluations.add(data);
    }
  }

  Future<void> deleteEvaluation(String id) async {
    await _evaluations.doc(id).delete();
  }

  // Rehire decisions (Head's Rehiring screen), one per student per term.
  CollectionReference get _rehireRecords => _db.collection('rehireRecords');

  Future<List<RehireRecord>> getAllRehireRecords() async {
    final snap = await _rehireRecords.get();
    return snap.docs
        .map(
          (d) => RehireRecord.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setRehireRecord(RehireRecord record) async {
    await _rehireRecords.doc(record.id).set(record.toJson());
  }

  // Applications
  CollectionReference get _applications => _db.collection('applications');

  Future<List<Application>> getAllApplications() async {
    final snap = await _applications.get();
    return snap.docs
        .map(
          (d) => Application.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setApplication(Application a) async {
    final data = {
      'announcementId': a.announcementId,
      'announcementTitle': a.announcementTitle,
      'applicantId': a.applicantId,
      'applicantName': a.applicantName,
      'appliedAt': a.appliedAt,
      'status': a.status,
      'remarks': a.remarks,
      'skills': a.skills,
      'submittedDocuments': a.submittedDocuments
          .map((document) => document.toJson())
          .toList(),
      'academicYear': a.academicYear,
      'classSchedule': a.classSchedule?.toJson(),
      // A full save: these must be listed, or a status change erases them.
      'studentNumber': a.studentNumber,
      'studentIdCheckedBy': a.studentIdCheckedBy,
      'studentIdCheckedAt': a.studentIdCheckedAt,
      'applicationForm': a.applicationForm?.toJson(),
    }..removeWhere((k, v) => v == null);
    if (a.id.isNotEmpty) {
      await _applications.doc(a.id).set(data);
    } else {
      await _applications.add(data);
    }
  }

  CollectionReference get _screeningRecords =>
      _db.collection('screeningRecords');

  // Deduping (by applicant + academic year) is handled by AppState, which
  // needs to keep records from different academic years distinct instead
  // of collapsing all of an applicant's screenings into one.
  Future<List<ScreeningRecord>> getAllScreeningRecords() async {
    final snap = await _screeningRecords.get();
    return snap.docs
        .map(
          (doc) => ScreeningRecord.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  Future<List<ScreeningRecord>> getScreeningRecordsForApplicant(
    String applicantId,
  ) async {
    final snap = await _screeningRecords
        .where('applicantId', isEqualTo: applicantId)
        .get();
    return snap.docs
        .map(
          (doc) => ScreeningRecord.fromJson({
            ...(doc.data() as Map<String, dynamic>),
            'id': doc.id,
          }),
        )
        .toList();
  }

  Future<void> setScreeningRecord(ScreeningRecord record) async {
    final data = record.toJson();
    data.remove('id');
    await _screeningRecords.doc(record.id).set(data);
  }

  Future<void> deleteScreeningRecord(String id) async {
    await _screeningRecords.doc(id).delete();
  }

  // Notifications

  Future<List<Map<String, dynamic>>> getNotificationsForUser(
    String userId,
  ) async {
    final snap = await _notifications.where('userId', isEqualTo: userId).get();
    return _newestFirst(snap);
  }

  Future<void> addNotification(Map<String, dynamic> payload) async {
    final id = payload['id']?.toString();
    // The id names the document; it isn't stored as a field.
    final data = {...payload, 'createdAt': FieldValue.serverTimestamp()}
      ..remove('id');
    if (id != null && id.isNotEmpty) {
      await _notifications.doc(id).set(data);
    } else {
      await _notifications.add(data);
    }
  }

  Future<void> updateNotification(String id, Map<String, dynamic> data) async {
    await _notifications.doc(id).update(data);
  }

  Future<void> deleteNotification(String id) async {
    await _notifications.doc(id).delete();
  }

  /// Records that [token], one browser's push address, belongs to
  /// [userId], so the clockout-reminders function can reach it. The token
  /// names the document, so a browser has one entry whoever signs in on it.
  Future<void> savePushToken(String token, String userId) async {
    await _db.collection('pushTokens').doc(token).set({
      'userId': userId,
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Supervisor cards: supervisorCards/{account id} = {name, avatar, updatedAt},
  // the only part of a supervisor's profile a Student Assistant may read.
  CollectionReference<Map<String, dynamic>> get _supervisorCards =>
      _db.collection('supervisorCards');

  /// The cards of [ids], or every card when [ids] is null (staff and the
  /// Admin, to compare with the profiles). An id with no card is left out.
  Future<List<SupervisorCard>> getSupervisorCards([
    Iterable<String>? ids,
  ]) async {
    if (ids == null) {
      final snapshot = await _supervisorCards.get();
      return [
        for (final doc in snapshot.docs)
          SupervisorCard.fromJson(doc.id, doc.data()),
      ];
    }
    final docs = await Future.wait([
      for (final id in ids.toSet())
        if (id.isNotEmpty) _supervisorCards.doc(id).get(),
    ]);
    return [
      for (final doc in docs)
        if (doc.exists) SupervisorCard.fromJson(doc.id, doc.data()!),
    ];
  }

  /// Saves each of [cards] in one batch (the stored card is replaced).
  Future<void> saveSupervisorCards(List<SupervisorCard> cards) async {
    for (var i = 0; i < cards.length; i += 500) {
      final batch = _db.batch();
      for (final card in cards.skip(i).take(500)) {
        batch.set(_supervisorCards.doc(card.id), {
          ...card.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> deletePushToken(String token) async {
    await _db.collection('pushTokens').doc(token).delete();
  }

  Future<void> deleteNotificationsForUser(String userId) async {
    final snap = await _notifications.where('userId', isEqualTo: userId).get();
    // A batch holds at most 500 writes; past that Firestore rejects the
    // whole commit and nothing is cleared.
    for (var i = 0; i < snap.docs.length; i += 500) {
      final batch = _db.batch();
      for (final doc in snap.docs.skip(i).take(500)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Account ids of the Heads, which staff sessions keep in meta/heads.
  /// Students can't list user profiles, so this is how their app knows
  /// whom to alert about a new application.
  Future<List<String>> getHeadIds() async {
    final doc = await _db.collection('meta').doc('heads').get();
    final ids = doc.data()?['ids'] as List<dynamic>? ?? const [];
    return [for (final id in ids) id.toString()];
  }

  Future<void> setHeadIds(List<String> ids) async {
    await _db.collection('meta').doc('heads').set({'ids': ids});
  }

  /// The task categories the Head manages, in meta/task_categories.
  Future<void> setTaskCategories(List<String> names) async {
    await _db.collection('meta').doc('task_categories').set({'names': names});
  }

  /// Most tasks [renameTaskCategory] can move: the whole rename is one
  /// transaction (so it either all happens or none of it does), which
  /// holds 500 writes, two of which are the category list and the templates.
  static const maxRenamedTasks = 450;

  /// Saves the category list with [from] changed to [to], moves the tasks
  /// and templates filed under the old name, all in one transaction. The
  /// templates are read inside it, so a template another session just saved
  /// isn't lost.
  Future<void> renameTaskCategory(
    List<String> names, {
    required String from,
    required String to,
    required List<String> taskIds,
    List<String> dutyIds = const [],
  }) async {
    if (taskIds.length + dutyIds.length > maxRenamedTasks) {
      throw StateError('Too many tasks to rename at once.');
    }
    final templatesRef = _db.collection('meta').doc('task_templates');
    await _db.runTransaction((transaction) async {
      final stored = await transaction.get(templatesRef);
      final items = [
        for (final item in stored.data()?['items'] as List<dynamic>? ?? [])
          if (item is Map) Map<String, dynamic>.from(item),
      ];
      final moves = items.any((i) => i['category'] == from);
      transaction.set(_db.collection('meta').doc('task_categories'), {
        'names': names,
      });
      if (moves) {
        transaction.set(templatesRef, {
          'items': [
            for (final i in items)
              i['category'] == from ? {...i, 'category': to} : i,
          ],
        });
      }
      for (final id in taskIds) {
        transaction.update(_tasks.doc(id), {'category': to});
      }
      for (final id in dutyIds) {
        transaction.update(_db.collection('taskDuties').doc(id), {
          'category': to,
        });
      }
    });
  }

  /// Adds a task template, or replaces the one with the same id. Done in a
  /// transaction on the stored list, so two Heads editing at once don't undo
  /// each other.
  Future<void> upsertTaskTemplate(Map<String, dynamic> template) =>
      _changeTaskTemplates((items) {
        final at = items.indexWhere((i) => i['id'] == template['id']);
        if (at < 0) {
          items.add(template);
        } else {
          items[at] = template;
        }
      });

  /// Saves several templates in one transaction: all of them or none.
  Future<void> upsertTaskTemplates(List<Map<String, dynamic>> templates) =>
      _changeTaskTemplates((items) {
        for (final template in templates) {
          final at = items.indexWhere((i) => i['id'] == template['id']);
          if (at < 0) {
            items.add(template);
          } else {
            items[at] = template;
          }
        }
      });

  Future<void> removeTaskTemplate(String id) =>
      _changeTaskTemplates((items) => items.removeWhere((i) => i['id'] == id));

  Future<void> _changeTaskTemplates(
    void Function(List<Map<String, dynamic>> items) change,
  ) {
    final ref = _db.collection('meta').doc('task_templates');
    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final items = [
        for (final item in snapshot.data()?['items'] as List<dynamic>? ?? [])
          if (item is Map) Map<String, dynamic>.from(item),
      ];
      change(items);
      transaction.set(ref, {'items': items});
    });
  }

  // Documents
  CollectionReference get _documents => _db.collection('documents');

  Future<List<Document>> getAllDocuments() async {
    final snap = await _documents.get();
    return snap.docs
        .map(
          (d) => Document.fromJson({
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          }),
        )
        .toList();
  }

  Future<void> setDocument(Document doc) async {
    final data = doc.toJson();
    if (doc.id.isNotEmpty) {
      await _documents.doc(doc.id).set(data);
    } else {
      await _documents.add(data);
    }
  }

  Future<void> deleteDocument(String id) async {
    await _documents.doc(id).delete();
  }

  /// Reads a single announcement by id, or null if missing.
  Future<Map<String, dynamic>?> getAnnouncement(String id) async {
    final doc = await _announcements.doc(id).get();
    if (!doc.exists) return null;
    return {...(doc.data() as Map<String, dynamic>), 'id': doc.id};
  }

  // Attendance QR tokens, one doc per office ---------------------------------------
  /// The attendance QR code of office [officeId] for [sessionKey]: the one
  /// already saved for that session, or else [candidate], saved now. Read
  /// and written in one transaction, so two devices opening the session
  /// together settle on one code instead of the second overwriting a code
  /// that's already posted. [sessionOf] tells which session a saved code
  /// belongs to. Returns the winning code's document.
  Future<Map<String, dynamic>> claimSessionQrToken(
    String officeId,
    String officeName,
    String candidate,
    String sessionKey, {
    required String? Function(Map<String, dynamic> doc) sessionOf,
  }) {
    final doc = _db.collection('attendanceQr').doc(officeId);
    return _db.runTransaction((transaction) async {
      final saved = (await transaction.get(doc)).data();
      if (saved != null &&
          saved['token'] is String &&
          sessionOf(saved) == sessionKey) {
        return saved;
      }
      final fresh = <String, dynamic>{
        'token': candidate,
        'sessionKey': sessionKey,
        // The rules cap it at 200 characters.
        'officeName': officeName.length > 200
            ? officeName.substring(0, 200)
            : officeName,
      };
      transaction.set(doc, {
        ...fresh,
        'generatedAt': FieldValue.serverTimestamp(),
      });
      return fresh;
    });
  }

  /// Updates an announcement (partial update).
  Future<void> updateAnnouncement(String id, Map<String, dynamic> data) async {
    await _announcements.doc(id).update(data);
  }

  /// Approves a supervisor's request ([data] on announcement [id]) and
  /// saves the office it creates or changes, in one batch, so neither is
  /// saved without the other.
  Future<void> approveAnnouncementWithOffice(
    String id,
    Map<String, dynamic> data,
    Office office,
  ) async {
    final batch = _db.batch();
    batch.update(_announcements.doc(id), data);
    batch.set(_offices.doc(office.id), office.toJson());
    await batch.commit();
  }

  /// Deletes an announcement.
  Future<void> deleteAnnouncement(String id) async {
    await _announcements.doc(id).delete();
  }
}
