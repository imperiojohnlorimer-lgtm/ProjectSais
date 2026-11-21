import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/recurring_schedule.dart';
import 'package:projectsais/models/schedule_event.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';

import 'support/account_writes.dart';

RecurringScheduleRule _subject(
  String id,
  String label,
  int weekday, {
  int start = 8,
  int end = 10,
  String units = '3',
}) => RecurringScheduleRule(
  id: id,
  ownerName: 'Sia Assistant',
  label: label,
  weekday: weekday,
  startTime: TimeOfDay(hour: start, minute: 0),
  endTime: TimeOfDay(hour: end, minute: 0),
  color: Colors.blue,
  icon: Icons.school_outlined,
  units: units,
  isSubject: true,
);

RecurringScheduleRule _shift(String id, int weekday) => RecurringScheduleRule(
  id: id,
  ownerName: 'Sia Assistant',
  label: 'Library duty',
  weekday: weekday,
  startTime: const TimeOfDay(hour: 13, minute: 0),
  endTime: const TimeOfDay(hour: 17, minute: 0),
  color: Colors.green,
  icon: Icons.work_outline,
);

ClassScheduleVersion _version(
  String id,
  String from,
  List<RecurringScheduleRule> subjects, {
  String? year = '2026-2027',
}) => ClassScheduleVersion(
  id: id,
  academicYear: year,
  effectiveFrom: from,
  fileName: 'sched.png',
  filePath: 'schedules/sa/1/a.png',
  subjects: subjects,
  approvedAt: '2026-11-01T00:00:00Z',
  approvedBy: 'Hana Head',
  source: 'request',
);

class _Events implements ScheduleRepository {
  final List<ScheduleEvent> events;
  _Events(this.events);

  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerId) async => events;

  @override
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerId) =>
      Stream.value(events);

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async => event;

  final deleted = <String>[];
  @override
  Future<void> deleteEvent(String id) async => deleted.add(id);
}

class _Store extends FirestoreService with AccountWrites {
  final applications = <String, Application>{};

  @override
  Future<void> setApplication(Application a) async => applications[a.id] = a;

  @override
  Future<void> setUserProfile(User user) async => profiles[user.id] = user;

  @override
  Future<void> setStudent(Student student) async {}

  @override
  Future<void> setSkill(String name) async {}

  final requests = <String, Map<String, dynamic>>{};
  final requestUpdates = <String, List<Map<String, dynamic>>>{};
  final notifications = <Map<String, dynamic>>[];
  final owners = <String, OwnerSchedule>{};
  final added =
      <({String ownerId, ClassScheduleVersion version, String? requestId})>[];
  final deletedPrefixes = <String, List<String>>{};
  String outcome = 'saved';

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);

  /// Runs when a request is saved: a test's live list echoing it.
  void Function(ScheduleRequest request)? onCreate;

  @override
  Future<void> createScheduleRequest(ScheduleRequest request) async {
    requests[request.id] = request.toNewJson();
    onCreate?.call(request);
  }

  @override
  Future<void> updateScheduleRequest(
    String id,
    Map<String, dynamic> fields,
  ) async => (requestUpdates[id] ??= []).add(fields);

  @override
  Future<OwnerSchedule> getOwnerSchedule(String ownerId) async =>
      owners[ownerId] ?? const OwnerSchedule();

  @override
  Future<String> addClassScheduleVersion({
    required String ownerId,
    required String ownerName,
    required ClassScheduleVersion version,
    String? requestId,
    Map<String, dynamic>? requestFields,
  }) async {
    if (outcome != 'saved') return outcome;
    final before = owners[ownerId] ?? const OwnerSchedule();
    if (version.sourceId.isNotEmpty &&
        before.versions.any(
          (v) => v.source == version.source && v.sourceId == version.sourceId,
        )) {
      return 'already';
    }
    added.add((ownerId: ownerId, version: version, requestId: requestId));
    owners[ownerId] = OwnerSchedule(
      rules: before.rules.where((r) => !r.isSubject).toList(),
      versions: [...before.versions, version],
    );
    if (requestId != null)
      (requestUpdates[requestId] ??= []).add(requestFields!);
    return 'saved';
  }

  @override
  Future<int> deleteScheduleEventsWithPrefixes(
    String ownerId,
    List<String> prefixes,
  ) async {
    deletedPrefixes[ownerId] = prefixes;
    return prefixes.length;
  }
}

final _head = User(
  id: 'head',
  name: 'Hana Head',
  email: 'h@x.com',
  role: 'Head',
);
final _sup = User(
  id: 'sup',
  name: 'Sam Supervisor',
  email: 's@x.com',
  role: 'Supervisor',
);
final _sa = User(
  id: 'sa',
  name: 'Sia Assistant',
  email: 'a@x.com',
  role: 'Student Assistant',
);

AppState _state(_Store store, User me) => AppState(firestoreService: store)
  ..currentUser = me
  ..users = [_head, _sup, _sa]
  ..offices = [
    Office(
      id: 'o1',
      name: 'Library',
      code: 'LIB',
      headIds: const ['sup'],
      headNames: const ['Sam Supervisor'],
      assistantIds: const ['sa'],
      assistantNames: const ['Sia Assistant'],
    ),
  ];

ScheduleRequest _pending(String id, {String from = '2026-11-20'}) =>
    ScheduleRequest(
      id: id,
      studentId: 'sa',
      studentName: 'Sia Assistant',
      academicYear: '2026-2027',
      fileName: 'new.png',
      filePath: 'schedules/sa/2/b.png',
      subjects: [_subject('n1', 'Networks', 2)],
      effectiveFrom: from,
      submittedAt: DateTime.utc(2026, 11, 19),
    );

void main() {
  group('class schedule versions', () {
    final first = _version('v1', '2026-08-10', [_subject('a', 'Math', 1)]);
    final second = _version('v2', '2027-01-10', [_subject('b', 'Physics', 2)]);

    test('the version in effect is the newest started by that day', () {
      final versions = [first, second];
      expect(
        ClassScheduleVersion.inEffect(versions, DateTime(2026, 8, 9)),
        isNull,
      );
      expect(
        ClassScheduleVersion.inEffect(versions, DateTime(2026, 8, 10))?.id,
        'v1',
      );
      expect(
        ClassScheduleVersion.inEffect(versions, DateTime(2026, 12, 31))?.id,
        'v1',
      );
      expect(
        ClassScheduleVersion.inEffect(versions, DateTime(2027, 1, 10))?.id,
        'v2',
      );
    });

    test('a version of another academic year is not used', () {
      expect(
        ClassScheduleVersion.inEffect(
          [first],
          DateTime(2027, 8, 20),
          academicYear: '2027-2028',
        ),
        isNull,
      );
    });

    test('approved subjects replace typed ones, across linked accounts', () {
      final typed = OwnerSchedule(
        rules: [_subject('old', 'Old typed', 1), _shift('w', 3)],
      );
      final approved = OwnerSchedule(versions: [first, second]);
      final october = OwnerSchedule.mergedRules([
        typed,
        approved,
      ], DateTime(2026, 10, 1));
      expect(october.map((r) => r.id), unorderedEquals(['w', 'a']));
      final january = OwnerSchedule.mergedRules([
        typed,
        approved,
      ], DateTime(2027, 1, 15));
      expect(january.map((r) => r.id), unorderedEquals(['w', 'b']));
      // Nothing approved yet: the typed subjects still count.
      expect(
        OwnerSchedule.mergedRules([
          typed,
        ], DateTime(2026, 10, 1)).map((r) => r.id),
        unorderedEquals(['old', 'w']),
      );
    });

    test('a version reads back what it saved', () {
      final back = ClassScheduleVersion.fromJson(first.toJson());
      expect(back.subjects.single.label, 'Math');
      expect(back.subjects.single.isSubject, isTrue);
      expect(back.effectiveFrom, '2026-08-10');
      final owner = OwnerSchedule.fromJson({
        'rules': [_shift('w', 3).toJson()],
        'classSchedules': [first.toJson()],
      });
      expect(owner.versions.single.id, 'v1');
      expect(owner.rules.single.id, 'w');
    });

    test('a request reads the server time it was sent at', () {
      final request = ScheduleRequest.fromJson({
        ..._pending('r1').toNewJson(),
        'submittedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 19, 3)),
      });
      expect(request.submittedAt, DateTime.utc(2026, 11, 19, 3).toLocal());
      expect(request.isPending, isTrue);
      expect(request.subjects.single.label, 'Networks');
    });
  });

  group('editor rows', () {
    test('rows must be complete and must not overlap', () {
      expect(classScheduleProblems([]), ['Add at least one class.']);
      final a = ClassMeetingRow(
        title: 'Math',
        weekday: 1,
        start: const TimeOfDay(hour: 8, minute: 0),
        end: const TimeOfDay(hour: 10, minute: 0),
      );
      expect(classScheduleProblems([a]), isEmpty);
      final b = ClassMeetingRow(
        title: 'Physics',
        weekday: 1,
        start: const TimeOfDay(hour: 9, minute: 30),
        end: const TimeOfDay(hour: 11, minute: 0),
      );
      expect(classScheduleProblems([a, b]).single, contains('overlap'));
      final c = ClassMeetingRow(title: 'PE', weekday: 2);
      expect(classScheduleProblems([a, c]).single, startsWith('Row 2'));
      final d = ClassMeetingRow(
        title: 'Late',
        weekday: 3,
        start: const TimeOfDay(hour: 10, minute: 0),
        end: const TimeOfDay(hour: 9, minute: 0),
      );
      expect(classScheduleProblems([d]).single, contains('end after'));
    });

    test('a read meeting becomes a row, then a subject rule', () {
      final row = ClassMeetingRow.fromMeeting(
        const ScheduleMeeting(
          title: 'Systems Analysis',
          instructor: 'P. Santos',
          room: 'CL5',
          weekday: 4,
          start: 13 * 60 + 30,
          end: 15 * 60 + 30,
          check: true,
        ),
      );
      expect(row.start, const TimeOfDay(hour: 13, minute: 30));
      expect(row.check, isTrue);
      final rules = classSubjectRules(
        rows: [
          row,
          ClassMeetingRow.fromMeeting(
            const ScheduleMeeting(
              title: 'systems analysis',
              weekday: 1,
              start: 480,
              end: 540,
            ),
          ),
        ],
        ownerName: 'Sia Assistant',
        academicYear: '2026-2027',
        idPrefix: 'p',
      );
      expect(rules.map((r) => r.id), ['p_0', 'p_1']);
      expect(rules.every((r) => r.isSubject), isTrue);
      expect(rules.first.room, 'CL5');
      // The same subject on two days keeps one colour.
      expect(rules[0].color, rules[1].color);
    });

    test('the reader result is read from the browser JSON', () {
      final result = ScheduleReadResult.fromJson({
        'ok': true,
        'source': 'ocr',
        'warnings': [],
        'meetings': [
          {
            'title': 'Math',
            'weekday': 1,
            'start': 480,
            'end': 540.0,
            'mode': 'Online',
            'check': false,
          },
          {
            'title': 'Odd',
            'weekday': 9,
            'start': null,
            'end': null,
            'check': true,
          },
        ],
      });
      expect(result.meetings.first.mode, 'Online');
      expect(result.meetings.first.end, 540);
      expect(result.meetings.last.weekday, isNull);
      expect(result.meetings.last.check, isTrue);
    });
  });

  group('calendar days of an approved schedule', () {
    final legacyDay = ScheduleEvent(
      id: 'rule_old_20261116',
      ownerId: 'sa',
      ownerName: 'Sia Assistant',
      title: 'Old typed',
      details: '',
      date: DateTime(2026, 11, 16),
      color: Colors.red,
      icon: Icons.event,
    );
    final shiftDay = ScheduleEvent(
      id: 'rule_w_20261118',
      ownerId: 'sa',
      ownerName: 'Sia Assistant',
      title: 'Library duty',
      details: '',
      date: DateTime(2026, 11, 18),
      color: Colors.green,
      icon: Icons.event,
    );

    Future<ScheduleService> service(OwnerSchedule owner, _Events events) async {
      final s =
          ScheduleService(events, scheduleWatcher: (_) => Stream.value(owner))
            ..activeAcademicYear = '2026-2027'
            ..setCalendarRange(
              DateTime(2026, 8, 1),
              DateTime(2027, 5, 31),
              (d) => d.month == 12 && d.day == 25,
            );
      await s.ensureLoaded('sa');
      await Future<void>.delayed(Duration.zero);
      return s;
    }

    test('each class day is worked out from the version in effect', () async {
      final owner = OwnerSchedule(
        rules: [_subject('old', 'Old typed', 1), _shift('w', 3)],
        versions: [
          _version('v1', '2026-11-17', [
            _subject('a', 'Math', 1),
            _subject('a2', 'Math', 5),
          ]),
        ],
      );
      final events = _Events([legacyDay, shiftDay]);
      final s = await service(owner, events);
      // Before the start day: nothing from the schedule, and the old typed
      // subject's day is hidden once one is approved.
      expect(s.eventsForDay('sa', DateTime(2026, 11, 16)), isEmpty);
      final monday = s.eventsForDay('sa', DateTime(2026, 11, 23));
      expect(monday.single.title, 'Math');
      expect(monday.single.computed, isTrue);
      expect(s.eventsForDay('sa', DateTime(2026, 11, 27)).single.title, 'Math');
      // A work shift day stays.
      expect(
        s.eventsForDay('sa', DateTime(2026, 11, 18)).single.id,
        'rule_w_20261118',
      );
      // A holiday has no class.
      expect(s.eventsForDay('sa', DateTime(2026, 12, 25)), isEmpty);
      expect(s.markedDaysFor('sa'), contains(DateTime.utc(2026, 11, 23)));
      // A worked-out class can't be deleted on its own.
      await s.deleteEvent('sa', monday.single.id);
      expect(events.deleted, isEmpty);
    });

    test('without an approved schedule nothing changes', () async {
      final owner = OwnerSchedule(rules: [_subject('old', 'Old typed', 1)]);
      final s = await service(owner, _Events([legacyDay]));
      expect(
        s.eventsForDay('sa', DateTime(2026, 11, 16)).single.id,
        legacyDay.id,
      );
    });
  });

  group('requests and approvals', () {
    test(
      'an assistant sends a schedule; an older waiting one is withdrawn',
      () async {
        final store = _Store();
        final state = _state(store, _sa)..scheduleRequests = [_pending('sa_1')];
        final problem = await state.submitScheduleRequest(
          fileName: 'new.png',
          filePath: 'schedules/sa/3/c.png',
          subjects: [_subject('x', 'Chemistry', 3)],
          effectiveFrom: '2026-11-25',
          note: '  new semester ',
        );
        expect(problem, isNull);
        expect(store.requestUpdates['sa_1']!.single['status'], 'Cancelled');
        final saved = store.requests.values.single;
        expect(saved['studentId'], 'sa');
        expect(saved['status'], 'Pending');
        expect(saved['note'], 'new semester');
        expect(state.scheduleRequests.where((r) => r.isPending).length, 1);
        expect(store.notifications.single['userId'], 'head');
        expect(store.notifications.single['type'], 'schedule');
      },
    );

    test(
      'the new request stays waiting when the live list has it first',
      () async {
        final store = _Store();
        final state = _state(store, _sa)..scheduleRequests = [_pending('sa_1')];
        store.onCreate = (r) => state.scheduleRequests = [
          for (final old in state.scheduleRequests)
            old.copyWith(status: ScheduleRequest.cancelled),
          r,
        ];
        await state.submitScheduleRequest(
          fileName: 'new.png',
          filePath: 'schedules/sa/3/c.png',
          subjects: [_subject('x', 'Chemistry', 3)],
          effectiveFrom: '2026-11-25',
        );
        expect(state.myLatestScheduleRequest!.isPending, isTrue);
        expect(state.scheduleRequests.where((r) => r.isPending), hasLength(1));
      },
    );

    test('only an assistant sends one', () async {
      final store = _Store();
      final state = _state(store, _sup);
      expect(
        await state.submitScheduleRequest(
          fileName: 'a',
          filePath: 'schedules/sup/1/a.png',
          subjects: [_subject('x', 'Chemistry', 3)],
          effectiveFrom: '2026-11-25',
        ),
        isNotNull,
      );
      expect(store.requests, isEmpty);
    });

    test(
      'the Head approves: the schedule is added and people are told',
      () async {
        final store = _Store()
          ..owners['sa'] = OwnerSchedule(
            rules: [_subject('old', 'Old typed', 1), _shift('w', 3)],
          );
        final state = _state(store, _head)..scheduleRequests = [_pending('r1')];
        expect(await state.approveScheduleRequest('r1'), isNull);
        final added = store.added.single;
        expect(added.ownerId, 'sa');
        expect(added.requestId, 'r1');
        expect(added.version.effectiveFrom, '2026-11-20');
        expect(added.version.source, 'request');
        expect(added.version.subjects.single.label, 'Networks');
        expect(store.requestUpdates['r1']!.single['status'], 'Approved');
        // The old typed subject's calendar days are cleared.
        expect(store.deletedPrefixes['sa'], ['rule_old_']);
        expect(state.scheduleRequests.single.status, 'Approved');
        final told = store.notifications.map((n) => n['userId']).toSet();
        expect(told, {'sa', 'sup'});
      },
    );

    test('a request withdrawn meanwhile is not approved', () async {
      final store = _Store()..outcome = 'not-pending';
      final state = _state(store, _head)..scheduleRequests = [_pending('r1')];
      expect(await state.approveScheduleRequest('r1'), contains('withdrawn'));
      expect(store.notifications, isEmpty);
      expect(state.scheduleRequests.single.isPending, isTrue);
    });

    test('rejecting needs a reason and keeps the old schedule', () async {
      final store = _Store();
      final state = _state(store, _head)..scheduleRequests = [_pending('r1')];
      expect(await state.rejectScheduleRequest('r1', '  '), isNotNull);
      expect(await state.rejectScheduleRequest('r1', 'Wrong file'), isNull);
      expect(store.requestUpdates['r1']!.single['reviewNote'], 'Wrong file');
      expect(store.added, isEmpty);
      expect(store.notifications.single['userId'], 'sa');
      expect(store.notifications.single['message'], contains('Wrong file'));
    });

    test('only the Head decides', () async {
      final store = _Store();
      final state = _state(store, _sup)..scheduleRequests = [_pending('r1')];
      expect(await state.approveScheduleRequest('r1'), isNotNull);
      expect(await state.rejectScheduleRequest('r1', 'x'), isNotNull);
      expect(store.added, isEmpty);
    });

    test('the Head edits the classes directly, keeping the file', () async {
      final store = _Store()
        ..owners['sa'] = OwnerSchedule(
          versions: [
            _version('v1', '2026-08-10', [_subject('a', 'Math', 1)]),
          ],
        );
      final state = _state(store, _head);
      expect(
        await state.saveClassScheduleByHead(
          studentId: 'sa',
          studentName: 'Sia Assistant',
          subjects: [_subject('b', 'Math', 2)],
          effectiveFrom: '2026-11-20',
        ),
        isNull,
      );
      final added = store.added.single.version;
      expect(added.source, 'head');
      expect(added.filePath, 'schedules/sa/1/a.png');
      expect(added.subjects.single.weekday, 2);
    });
  });

  group('the application\'s schedule', () {
    Application app() => Application(
      id: 'app_sa_2026-2027',
      announcementId: 'call1',
      announcementTitle: Application.generalTitle,
      applicantId: 'sa',
      applicantName: 'Sia Assistant',
      appliedAt: 'Nov 1, 2026',
      academicYear: '2026-2027',
      studentIdCheckedBy: 'Hana Head',
      studentIdCheckedAt: '2026-11-01T02:00:00.000Z',
      classSchedule: ClassScheduleSubmission(
        fileName: 'sched.png',
        filePath: 'schedules/sa/1/a.png',
        subjects: [_subject('a', 'Math', 1)],
      ),
    );

    test('approving makes it the new assistant\'s schedule, once', () async {
      final applicant = User(
        id: 'sa',
        name: 'Sia Assistant',
        email: 'a@x.com',
        role: 'Student',
      );
      final store = _Store()..profiles['sa'] = applicant;
      final state = AppState(firestoreService: store)
        ..currentUser = _head
        ..users = [_head, applicant]
        ..applications = [app()];
      await state.updateApplicationStatus(app().id, Application.approved);
      final added = store.added.single;
      expect(added.ownerId, 'sa');
      expect(added.version.source, 'application');
      expect(added.version.sourceId, app().id);
      expect(added.version.subjects.single.label, 'Math');
      // Saving the decision again doesn't add it twice.
      await state.updateApplicationStatus(app().id, Application.approved);
      expect(store.added, hasLength(1));
    });

    test('it is saved with the application and read back', () {
      final json = app().classSchedule!.toJson();
      final back = Application.fromJson({'classSchedule': json, 'id': 'x'});
      expect(back.classSchedule!.subjects.single.label, 'Math');
      expect(app().copyWith(status: 'Approved').classSchedule, isNotNull);
    });
  });
}
