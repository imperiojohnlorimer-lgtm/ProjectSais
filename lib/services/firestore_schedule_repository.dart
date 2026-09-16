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
  Future<List<ScheduleEvent>> getEventsFor(String ownerName) async {
    final snapshot = await _events
        .where('ownerName', isEqualTo: ownerName)
        .get();
    return snapshot.docs.map((doc) {
      return ScheduleEvent.fromJson({...doc.data(), 'id': doc.id});
    }).toList();
  }

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async {
    final reference = event.id.isEmpty ? _events.doc() : _events.doc(event.id);
    await reference.set(event.toJson());
    return ScheduleEvent.fromJson({...event.toJson(), 'id': reference.id});
  }

  @override
  Future<void> deleteEvent(String id) => _events.doc(id).delete();
}
