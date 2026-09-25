import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/schedule_event.dart';
import 'schedule_repository.dart';

class FirestoreScheduleRepository implements ScheduleRepository {
  FirestoreScheduleRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('schedule_events');

  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerId) async {
    // By account, not name: the Firestore rules only let the owner, the
    // Head and the owner's office Supervisor read these, and they can only
    // check that for a query on ownerId.
    final snapshot = await _events.where('ownerId', isEqualTo: ownerId).get();
    return snapshot.docs.map((doc) {
      return ScheduleEvent.fromJson({...doc.data(), 'id': doc.id});
    }).toList();
  }

  @override
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerId) => _events
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => ScheduleEvent.fromJson({...doc.data(), 'id': doc.id}))
            .toList(),
      );

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async {
    final reference = event.id.isEmpty ? _events.doc() : _events.doc(event.id);
    await reference.set(event.toJson());
    return ScheduleEvent.fromJson({...event.toJson(), 'id': reference.id});
  }

  @override
  Future<void> deleteEvent(String id) => _events.doc(id).delete();
}
