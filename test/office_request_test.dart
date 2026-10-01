import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Keeps what approving saves instead of writing it.
class _Store extends FirestoreService {
  final updates = <String, Map<String, dynamic>>{};
  final savedOffices = <Office>[];
  final notifications = <Map<String, dynamic>>[];
  bool fail = false;

  @override
  Future<void> updateAnnouncement(String id, Map<String, dynamic> data) async {
    if (fail) throw Exception('offline');
    updates[id] = data;
  }

  @override
  Future<void> approveAnnouncementWithOffice(
    String id,
    Map<String, dynamic> data,
    Office office,
  ) async {
    if (fail) throw Exception('offline');
    updates[id] = data;
    savedOffices.add(office);
  }

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);
}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'helen@example.com',
  role: 'Head',
);
final _supervisor = User(
  id: 'sup1',
  name: 'Sara Supervisor',
  email: 'sara@example.com',
  role: 'Supervisor',
);

Announcement _request({
  String? officeId,
  String? officeName = 'Guidance Office',
  String? slots = '2',
  List<String> skills = const ['Data encoding', 'Web Developer'],
  String approvalStatus = 'Pending',
  String postedByRole = 'Supervisor',
}) => Announcement(
  id: 'req1',
  title: 'Office Aide',
  body: 'Help with records.',
  postedBy: _supervisor.name,
  postedByRole: postedByRole,
  postedById: _supervisor.id,
  postedAt: '10/1/2026',
  slots: slots,
  skills: skills,
  officeId: officeId,
  officeName: officeName,
  approvalStatus: approvalStatus,
  isOpen: false,
);

void main() {
  group('Office.suggestCode', () {
    test('keeps an acronym already in the name', () {
      expect(Office.suggestCode('CICS Office'), 'CICS');
    });
    test('takes the initials of the main words', () {
      expect(Office.suggestCode('Office of the Registrar'), 'OR');
      expect(Office.suggestCode('Guidance Office'), 'GO');
    });
    test('falls back to the first letters of one word', () {
      expect(Office.suggestCode('Library'), 'LIBR');
    });
  });

  group('officePlanFor', () {
    late AppState state;
    setUp(() => state = AppState()..currentUser = _head);

    test('creates the office when there is none', () {
      final plan = state.officePlanFor(_request(), newOfficeCode: 'GUID')!;

      expect(plan.createsOffice, isTrue);
      expect(plan.office.name, 'Guidance Office');
      expect(plan.office.code, 'GUID');
      expect(plan.office.headIds, ['sup1']);
      expect(plan.office.headNames, ['Sara Supervisor']);
      expect(plan.office.capacity, 2);
      expect(plan.office.requiredSkills, ['Data encoding', 'Web Developer']);
      expect(plan.office.isActive, isTrue);
    });

    test('an existing office gets the skills it lacked and room for the '
        'slots', () {
      state.offices = const [
        Office(
          id: 'o1',
          name: 'Guidance Office',
          code: 'GO',
          headIds: ['sup1'],
          headNames: ['Sara Supervisor'],
          assistantIds: ['sa1', 'sa2'],
          assistantNames: ['A', 'B'],
          capacity: 3,
          requiredSkills: ['data encoding'],
        ),
      ];

      final plan = state.officePlanFor(_request(officeId: 'o1'))!;

      expect(plan.createsOffice, isFalse);
      expect(plan.office.id, 'o1');
      // Matched without regard to case, so not added twice.
      expect(plan.addedSkills, ['Web Developer']);
      expect(plan.office.requiredSkills, ['data encoding', 'Web Developer']);
      // Two assistants plus two slots don't fit in three.
      expect(plan.office.capacity, 4);
      expect(plan.raisesCapacity, isTrue);
      expect(plan.addsSupervisor, isFalse);
      expect(plan.office.assistantIds, ['sa1', 'sa2']);
    });

    test('an office with no capacity limit keeps none', () {
      state.offices = const [
        Office(id: 'o1', name: 'Guidance Office', code: 'GO', capacity: 0),
      ];

      final plan = state.officePlanFor(_request(officeId: 'o1'))!;

      expect(plan.office.capacity, 0);
      expect(plan.raisesCapacity, isFalse);
    });

    test('an office typed in by name is matched to the one on file, which '
        'gets the supervisor and is made active again', () {
      state.offices = const [
        Office(
          id: 'o9',
          name: 'guidance office',
          code: 'GO',
          headIds: ['sup2'],
          headNames: ['Other Supervisor'],
          isActive: false,
        ),
      ];

      final plan = state.officePlanFor(_request())!;

      expect(plan.createsOffice, isFalse);
      expect(plan.office.id, 'o9');
      expect(plan.addsSupervisor, isTrue);
      expect(plan.office.headIds, ['sup2', 'sup1']);
      expect(plan.office.headNames, ['Other Supervisor', 'Sara Supervisor']);
      expect(plan.reactivates, isTrue);
      expect(plan.office.isActive, isTrue);
    });

    test('nothing changes for an office that already has it all', () {
      state.offices = const [
        Office(
          id: 'o1',
          name: 'Guidance Office',
          code: 'GO',
          headIds: ['sup1'],
          headNames: ['Sara Supervisor'],
          requiredSkills: ['Data encoding', 'Web Developer'],
        ),
      ];

      final plan = state.officePlanFor(_request(officeId: 'o1'))!;

      expect(plan.changesOffice, isFalse);
    });

    test('only a pending supervisor request that names an office has one', () {
      expect(state.officePlanFor(_request(approvalStatus: 'Approved')), isNull);
      expect(state.officePlanFor(_request(postedByRole: 'Admin')), isNull);
      expect(state.officePlanFor(_request(officeName: null)), isNull);
    });
  });

  group('approveAnnouncement', () {
    late _Store store;
    late AppState state;
    setUp(() {
      store = _Store();
      state = AppState(firestoreService: store)
        ..currentUser = _head
        ..users = [_head, _supervisor];
    });

    test('creates the office with the request and links them', () async {
      state.announcements = [_request()];

      final ok = await state.approveAnnouncement('req1', newOfficeCode: 'GUID');

      expect(ok, isTrue);
      final office = store.savedOffices.single;
      expect(office.code, 'GUID');
      expect(store.updates['req1'], {
        'approvalStatus': 'Approved',
        'isOpen': true,
        'officeId': office.id,
        'officeName': 'Guidance Office',
      });
      expect(state.offices.single.id, office.id);
      expect(state.announcements.single.officeId, office.id);
      expect(
        store.notifications.singleWhere(
          (n) => n['userId'] == 'sup1',
        )['message'],
        contains('The office "Guidance Office" was created'),
      );
    });

    test('an office that needs no change is left alone', () async {
      const office = Office(
        id: 'o1',
        name: 'Guidance Office',
        code: 'GO',
        headIds: ['sup1'],
        headNames: ['Sara Supervisor'],
        requiredSkills: ['Data encoding', 'Web Developer'],
      );
      state
        ..offices = const [office]
        ..announcements = [_request(officeId: 'o1')];

      final ok = await state.approveAnnouncement('req1');

      expect(ok, isTrue);
      expect(store.savedOffices, isEmpty);
      expect(store.updates['req1']!['officeId'], 'o1');
    });

    test('a failed save changes nothing', () async {
      store.fail = true;
      state.announcements = [_request()];

      final ok = await state.approveAnnouncement('req1');

      expect(ok, isFalse);
      expect(state.offices, isEmpty);
      expect(state.announcements.single.isPending, isTrue);
    });
  });
}
