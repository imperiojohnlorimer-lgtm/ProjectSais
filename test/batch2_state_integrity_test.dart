import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/class_schedule.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/recurring_schedule.dart';
import 'package:projectsais/models/schedule_event.dart';
import 'package:projectsais/models/task_template.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';

class _FakeBatch2Firestore extends FirestoreService {
  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};
  final _docs = <String, StreamController<Map<String, dynamic>?>>{};
  final List<Map<String, dynamic>> attendanceUpdates = [];
  final List<RehireRecord> savedRehires = [];

  StreamController<List<Map<String, dynamic>>> list(String key) =>
      _lists.putIfAbsent(key, StreamController.broadcast);

  @override
  Stream<List<Map<String, dynamic>>> collectionStream(
    String collection, {
    bool newestFirst = false,
  }) => list(collection).stream;

  @override
  Stream<List<Map<String, dynamic>>> whereStream(
    String collection,
    String field,
    Object value, {
    bool newestFirst = false,
  }) => list('$collection.$field=$value').stream;

  @override
  Stream<List<Map<String, dynamic>>> whereInStream(
    String collection,
    String field,
    List<Object> values,
  ) => list('$collection.$field in $values').stream;

  @override
  Stream<Map<String, dynamic>?> docStream(String collection, String id) =>
      _docs.putIfAbsent('$collection/$id', StreamController.broadcast).stream;

  @override
  Future<List<Map<String, dynamic>>> getNotificationsForUser(
    String userId,
  ) async => const [];

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => const [];

  @override
  Future<Map<String, dynamic>?> getAcademicYearSettings() async => null;

  @override
  Future<List<Map<String, dynamic>>> getAcademicYearArchives() async =>
      const [];

  @override
  Future<void> updateAttendance(String id, Map<String, dynamic> data) async {
    attendanceUpdates.add({'id': id, ...data});
  }

  @override
  Future<void> setRehireRecord(RehireRecord record) async {
    savedRehires.add(record);
  }
}

class _StreamingScheduleRepo extends InMemoryScheduleRepository {
  final StreamController<List<ScheduleEvent>> controller =
      StreamController<List<ScheduleEvent>>.broadcast();
  final List<ScheduleEvent> stored = [];

  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerId) async =>
      stored.where((e) => e.ownerId == ownerId).toList();

  @override
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerId) =>
      controller.stream;

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async {
    final saved = event.id.isEmpty ? event.copyWith() : event;
    stored.add(saved);
    // Simulate a live Firestore listener emitting the saved event immediately
    // before addEvent returns to ScheduleService.
    controller.add(List<ScheduleEvent>.from(stored));
    return saved;
  }
}

String _formatManilaDate(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('Model integrity fixes', () {
    test(
      'User and Student initials handle consecutive spaces and whitespace',
      () {
        final userSpaced = User(
          id: 'u1',
          name: '  Ana   Maria  Cruz ',
          email: 'ana@example.com',
          role: 'Student Assistant',
        );
        final userBlank = User(
          id: 'u2',
          name: '   ',
          email: 'blank@example.com',
          role: 'Student Assistant',
        );
        final studentSpaced = Student(
          id: 's1',
          name: 'Juan   Dela Cruz',
          email: 'juan@example.com',
          department: 'CICS',
        );
        final studentBlank = Student(
          id: 's2',
          name: '   ',
          email: 'blank@example.com',
          department: 'CICS',
        );

        expect(userSpaced.initials, 'AM');
        expect(userBlank.initials, '?');
        expect(studentSpaced.initials, 'JD');
        expect(studentBlank.initials, '?');
      },
    );

    test('Document.fromJson accepts int and double fileSize values', () {
      final zeroDoc = Document.fromJson({'id': 'd0', 'fileSize': 0});
      final intDoc = Document.fromJson({'id': 'd1', 'fileSize': 12});
      final doubleDoc = Document.fromJson({'id': 'd2', 'fileSize': 2.5});
      final nullDoc = Document.fromJson({'id': 'd3'});

      expect(zeroDoc.fileSize, 0.0);
      expect(intDoc.fileSize, 12.0);
      expect(doubleDoc.fileSize, 2.5);
      expect(nullDoc.fileSize, isNull);
    });

    test('HeadForward.copyWith preserves storagePath', () {
      final forward = HeadForward(
        id: 'hf1',
        type: 'report',
        studentId: 'sa1',
        studentName: 'Ana Reyes',
        title: 'Monthly Report',
        fileName: 'report.pdf',
        storagePath: 'forwards/report.pdf',
        sentByName: 'Sup One',
        sentAt: '2026-10-01T00:00:00Z',
        reviewed: false,
      );

      final updated = forward.copyWith(reviewed: true);

      expect(updated.reviewed, isTrue);
      expect(updated.storagePath, 'forwards/report.pdf');
    });

    test(
      'Office.withAssistant and withHead align mismatched ID/name arrays',
      () {
        const legacy = Office(
          id: 'o1',
          name: 'Library',
          code: 'LIB',
          assistantIds: [],
          assistantNames: ['Legacy Assistant'],
          headIds: [],
          headNames: ['Legacy Head'],
        );

        final withAssistant = legacy.withAssistant('u2', 'New Assistant');
        expect(withAssistant.assistantIds, ['', 'u2']);
        expect(withAssistant.assistantNames, [
          'Legacy Assistant',
          'New Assistant',
        ]);

        final afterRemove = withAssistant.withoutAssistant(
          'u2',
          'New Assistant',
        );
        expect(afterRemove.assistantIds, ['']);
        expect(afterRemove.assistantNames, ['Legacy Assistant']);

        final withHead = legacy.withHead('h2', 'New Head');
        expect(withHead.headIds, ['', 'h2']);
        expect(withHead.headNames, ['Legacy Head', 'New Head']);
      },
    );
  });

  group('ScheduleService integrity fixes', () {
    test(
      'addEvent deduplicates when watchEventsFor already emitted saved event',
      () async {
        final repo = _StreamingScheduleRepo();
        final service = ScheduleService(repo);
        addTearDown(() async {
          service.dispose();
          await repo.controller.close();
        });

        await service.ensureLoaded('sa1');
        final event = ScheduleEvent(
          id: 'evt_1',
          ownerId: 'sa1',
          ownerName: 'Sara',
          title: 'Shift',
          details: '8 AM',
          date: DateTime.utc(2026, 11, 20),
          color: Colors.blue,
          icon: Icons.event,
        );

        await service.addEvent(event);
        await _settle();

        final events = service.eventsFor('sa1');
        expect(events.where((e) => e.id == 'evt_1').length, 1);
      },
    );

    test(
      'setCalendarRange invalidates cache across different holiday years',
      () async {
        final repo = InMemoryScheduleRepository();
        final ownerSchedule = OwnerSchedule(
          versions: [
            ClassScheduleVersion(
              id: 'v1',
              academicYear: null,
              effectiveFrom: '2026-01-01',
              fileName: 'sched.pdf',
              filePath: 'schedules/sched.pdf',
              subjects: const [
                RecurringScheduleRule(
                  id: 'sub_fri',
                  ownerName: 'Sara',
                  label: 'CS101',
                  weekday: DateTime.friday,
                  startTime: TimeOfDay(hour: 9, minute: 0),
                  endTime: TimeOfDay(hour: 11, minute: 0),
                  color: Colors.blue,
                  icon: Icons.school_outlined,
                  isSubject: true,
                ),
                RecurringScheduleRule(
                  id: 'sub_sat',
                  ownerName: 'Sara',
                  label: 'CS102',
                  weekday: DateTime.saturday,
                  startTime: TimeOfDay(hour: 9, minute: 0),
                  endTime: TimeOfDay(hour: 11, minute: 0),
                  color: Colors.green,
                  icon: Icons.school_outlined,
                  isSubject: true,
                ),
              ],
              approvedAt: '2026-01-01T00:00:00Z',
              approvedBy: 'Head',
              source: 'head',
            ),
          ],
        );
        final service = ScheduleService(
          repo,
          scheduleWatcher: (_) => Stream.value(ownerSchedule),
        );
        addTearDown(service.dispose);

        await service.ensureLoaded('sa1');
        await _settle();

        final dec25_2026 = DateTime.utc(2026, 12, 25); // Friday
        final dec25_2027 = DateTime.utc(2027, 12, 25); // Saturday

        service.setCalendarRange(
          DateTime(2026, 12, 1),
          DateTime(2027, 12, 31),
          (day) => day.year == 2026 && day.month == 12 && day.day == 25,
        );
        final first = service.eventsFor('sa1');
        expect(first.any((e) => e.dayKey == dec25_2026), isFalse);
        expect(first.any((e) => e.dayKey == dec25_2027), isTrue);

        // Same range & month/day (12/25), different year (2027 instead of 2026):
        // cache must invalidate so 2026 Dec 25 reappears and 2027 Dec 25 hides.
        service.setCalendarRange(
          DateTime(2026, 12, 1),
          DateTime(2027, 12, 31),
          (day) => day.year == 2027 && day.month == 12 && day.day == 25,
        );
        final second = service.eventsFor('sa1');
        expect(second.any((e) => e.dayKey == dec25_2026), isTrue);
        expect(second.any((e) => e.dayKey == dec25_2027), isFalse);
      },
    );
  });

  group('AppState Batch 2 fixes', () {
    late _FakeBatch2Firestore fake;
    late AppState state;

    setUp(() {
      fake = _FakeBatch2Firestore();
      state = AppState(firestoreService: fake);
    });

    tearDown(() {
      state.dispose();
    });

    test(
      'init when signed out leaves hasLoadProblem false without crashing',
      () async {
        await state.init();
        expect(state.currentUser, isNull);
        expect(state.hasLoadProblem, isFalse);
      },
    );

    test(
      'filteredReports and filteredEvaluations work for Head role',
      () async {
        state.currentUser = User(
          id: 'h1',
          name: 'Head User',
          email: 'head@example.com',
          role: 'Head',
        );
        state.academicYear = '2026-2027';
        state.reports = [
          Report(
            id: 'r1',
            title: 'Approved Forwarded',
            content: 'ok',
            studentName: 'Sara',
            status: 'Approved',
            academicYear: '2026-2027',
            sentToHead: true,
          ),
          Report(
            id: 'r2',
            title: 'Not Forwarded',
            content: 'ok',
            studentName: 'Sara',
            status: 'Approved',
            academicYear: '2026-2027',
            sentToHead: false,
          ),
          Report(
            id: 'r3',
            title: 'Other Year',
            content: 'ok',
            studentName: 'Sara',
            status: 'Approved',
            academicYear: '2025-2026',
            sentToHead: true,
          ),
        ];
        state.evaluations = [
          Evaluation(
            id: 'e1',
            studentId: 'sa1',
            studentName: 'Sara',
            office: 'Library',
            term: '1st Semester',
            periodCovered: 'Aug-Dec',
            dateOfRating: 'Dec 1, 2026',
            eligibleForRehire: true,
            ratings: const {'punctuality': 9},
            overallRating: 9,
            departmentHeadComments: 'Good',
            supervisorId: 'sup1',
            supervisorName: 'Sup',
            status: 'Submitted',
            academicYear: '2026-2027',
            sentToHead: true,
          ),
          Evaluation(
            id: 'e2',
            studentId: 'sa1',
            studentName: 'Sara',
            office: 'Library',
            term: '1st Semester',
            periodCovered: 'Aug-Dec',
            dateOfRating: 'Dec 1, 2026',
            eligibleForRehire: true,
            ratings: const {'punctuality': 9},
            overallRating: 9,
            departmentHeadComments: 'Draft',
            supervisorId: 'sup1',
            supervisorName: 'Sup',
            status: 'Draft',
            academicYear: '2026-2027',
            sentToHead: true,
          ),
        ];

        expect(state.filteredReports.map((r) => r.id).toList(), [
          'r1',
          'r2',
          'r3',
        ]);
        expect(state.filteredEvaluations.map((e) => e.id).toList(), [
          'e1',
          'e2',
        ]);
      },
    );

    test(
      'setAttendanceArchived(id, false) enforces 20h weekly cap on restore',
      () async {
        state.academicYear = '2026-2027';
        state.attendance = [
          AttendanceRecord(
            id: 'existing_18h',
            studentId: 'sa1',
            studentName: 'Sara',
            date: 'Nov 23, 2026',
            timeIn: '8:00 AM',
            timeOut: '2:00 PM',
            totalHours: 18.0,
            academicYear: '2026-2027',
          ),
          AttendanceRecord(
            id: 'archived_4h',
            studentId: 'sa1',
            studentName: 'Sara',
            date: 'Nov 24, 2026',
            timeIn: '8:00 AM',
            timeOut: '12:00 PM',
            totalHours: 4.0,
            isArchived: true,
            academicYear: '2026-2027',
          ),
          AttendanceRecord(
            id: 'archived_2h',
            studentId: 'sa1',
            studentName: 'Sara',
            date: 'Nov 25, 2026',
            timeIn: '8:00 AM',
            timeOut: '10:00 AM',
            totalHours: 2.0,
            isArchived: true,
            academicYear: '2026-2027',
          ),
        ];

        final restoredPartial = await state.setAttendanceArchived(
          'archived_4h',
          false,
        );
        expect(restoredPartial, isTrue);
        final firstRestored = state.attendance.firstWhere(
          (r) => r.id == 'archived_4h',
        );
        expect(firstRestored.isArchived, isFalse);
        expect(firstRestored.totalHours, 2.0);

        final restoredZero = await state.setAttendanceArchived(
          'archived_2h',
          false,
        );
        expect(restoredZero, isTrue);
        final secondRestored = state.attendance.firstWhere(
          (r) => r.id == 'archived_2h',
        );
        expect(secondRestored.isArchived, isFalse);
        expect(secondRestored.totalHours, 0.0);
      },
    );

    test(
      'setManualTimeOut does not pool null-studentId records across different students',
      () async {
        state.academicYear = '2026-2027';
        state.attendance = [
          AttendanceRecord(
            id: 'alice_18h',
            studentId: null,
            studentName: 'Alice One',
            date: 'Nov 23, 2026',
            timeIn: '8:00 AM',
            timeOut: '2:00 PM',
            totalHours: 18.0,
            academicYear: '2026-2027',
          ),
          AttendanceRecord(
            id: 'bob_open',
            studentId: null,
            studentName: 'Bob Two',
            date: 'Nov 24, 2026',
            timeIn: '8:00 AM',
            academicYear: '2026-2027',
          ),
        ];

        final ok = await state.setManualTimeOut('bob_open', '12:00 PM');
        expect(ok, isTrue);
        final updated = state.attendance.firstWhere((r) => r.id == 'bob_open');
        expect(updated.totalHours, 4.0);
      },
    );

    test(
      'applyRehireDecisionNow does not mark applied=true when student user is missing',
      () async {
        state.currentUser = User(
          id: 'h1',
          name: 'Head User',
          email: 'head@example.com',
          role: 'Head',
        );
        state.academicYear = '2026-2027';
        state.users = [state.currentUser!];

        final record = RehireRecord(
          id: 'reh1',
          studentId: 'missing_sa',
          studentName: 'Missing Student',
          academicYear: '2026-2027',
          semester: '1st Semester',
          decision: RehireRecord.notRehired,
          decidedById: 'h1',
          decidedByName: 'Head User',
          decidedAt: '2026-10-01T00:00:00Z',
        );
        state.rehireRecords = [record];

        await state.applyRehireDecisionNow(record);

        expect(state.rehireRecords.first.applied, isFalse);
        expect(fake.savedRehires, isEmpty);
      },
    );

    test('studentIdClashFor detects deleted account studentId', () async {
      state.currentUser = User(
        id: 'h1',
        name: 'Head User',
        email: 'head@example.com',
        role: 'Head',
      );
      await state.init();

      final deletedUser = User(
        id: 'del1',
        name: 'Deleted Student',
        email: 'deleted@example.com',
        role: 'Student',
        studentId: '23B0626',
        isDeleted: true,
      );
      fake.list('users').add([deletedUser.toJson()]);
      await _settle();

      final app = Application(
        id: 'app_u2_2026-2027',
        announcementId: 'ann1',
        announcementTitle: Application.generalTitle,
        applicantId: 'u2',
        applicantName: 'New Applicant',
        appliedAt: '2026-10-01T00:00:00Z',
        studentNumber: '23B0626',
      );

      final clash = state.studentIdClashFor(app);
      expect(clash, 'Deleted Student (a deleted account)');
    });

    test(
      'logout clears taskTemplates and resets taskCategories to defaults',
      () {
        state.taskTemplates = const [
          TaskTemplate(
            id: 't1',
            category: 'Custom',
            title: 'Sensitive Template',
          ),
        ];
        state.taskCategories = ['Custom', 'Extra'];

        state.logout();

        expect(state.taskTemplates, isEmpty);
        expect(state.taskCategories, ['General', 'Administrative', 'Academic']);
      },
    );

    test(
      'dashboardStats avgHoursPerWeek excludes invalid records and respects 0h capped totalHours',
      () {
        final now = state.philippineClock();
        final todayText = _formatManilaDate(now);
        state.currentUser = User(
          id: 'h1',
          name: 'Head User',
          email: 'head@example.com',
          role: 'Head',
        );
        state.academicYear = '2026-2027';
        state.students = [
          Student(
            id: 's1',
            userId: 'sa1',
            name: 'Sara One',
            email: 'sa1@example.com',
            department: 'CICS',
            status: 'Active',
          ),
        ];
        state.attendance = [
          AttendanceRecord(
            id: 'valid_4h',
            studentId: 'sa1',
            studentName: 'Sara One',
            date: todayText,
            timeIn: '8:00 AM',
            timeOut: '12:00 PM',
            totalHours: 4.0,
            academicYear: '2026-2027',
          ),
          AttendanceRecord(
            id: 'capped_0h',
            studentId: 'sa1',
            studentName: 'Sara One',
            date: todayText,
            timeIn: '1:00 PM',
            timeOut: '5:00 PM',
            totalHours: 0.0,
            academicYear: '2026-2027',
          ),
          AttendanceRecord(
            id: 'invalid_8h',
            studentId: 'sa1',
            studentName: 'Sara One',
            date: todayText,
            timeIn: '8:00 AM',
            timeOut: '4:00 PM',
            totalHours: 8.0,
            isInvalid: true,
            academicYear: '2026-2027',
          ),
        ];

        // 4.0 credited hours over 4 weeks -> 1.0 h/week (not 3.0 or 4.0).
        expect(state.dashboardStats['avgHoursPerWeek'], '1.0');
      },
    );
  });
}
