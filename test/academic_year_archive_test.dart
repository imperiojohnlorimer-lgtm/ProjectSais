import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/admin_notifications_screen.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/widgets/academic_year_archive_dialog.dart';

/// Keeps the academic year settings, the archive list and the notifications
/// the app saves in memory, records which records it copies into an
/// archive, and pushes every settings save to the settings listener the
/// way Firestore would.
class _ArchiveFirestore extends FirestoreService {
  Map<String, dynamic>? settings;
  final archives = <String, Map<String, dynamic>>{};
  List<User> profiles = [];

  /// Notifications saved before the session started.
  List<Map<String, dynamic>> stored = [];
  final added = <Map<String, dynamic>>[];

  /// 'reports:2026-2027' and so on, in the order they were copied.
  final copied = <String>[];

  Map<String, int> toArchive = {};
  Map<String, int> inArchive = {};

  final _settingsDoc = StreamController<Map<String, dynamic>?>.broadcast();

  void push(Map<String, dynamic> data) {
    settings = Map.of(data);
    _settingsDoc.add(Map.of(data));
  }

  List<Map<String, dynamic>> titled(String title) =>
      added.where((n) => n['title'] == title).toList();

  @override
  Future<Map<String, dynamic>?> getAcademicYearSettings() async =>
      settings == null ? null : Map.of(settings!);

  @override
  Future<void> saveAcademicYearSettings(Map<String, dynamic> data) async =>
      push(data);

  @override
  Future<bool> archiveAcademicYearSettings(
    String academicYear,
    Map<String, dynamic> settings, {
    bool archiveAttendance = false,
    Map<String, int>? headcountByCampus,
  }) async {
    if (archives.containsKey(academicYear)) return false;
    archives[academicYear] = {
      ...settings,
      'academicYear': academicYear,
      'archivedAt': DateTime.now(),
      'archiveAttendance': archiveAttendance,
      'dataArchived': false,
      'headcountByCampus': ?headcountByCampus,
    };
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> getAcademicYearArchives() async => [
    for (final year in archives.keys.toList()..sort((a, b) => b.compareTo(a)))
      {...archives[year]!, 'id': year},
  ];

  @override
  Future<void> deleteUnprocessedAcademicYearArchive(String academicYear) async {
    if (archives[academicYear]?['dataArchived'] == false) {
      archives.remove(academicYear);
    }
  }

  @override
  Future<void> markAcademicYearDataArchived(String academicYear) async {
    archives[academicYear]!
      ..['dataArchived'] = true
      ..['dataArchivedAt'] = DateTime.now();
  }

  @override
  Future<void> archiveReportsForAcademicYear(String year) async =>
      copied.add('reports:$year');

  @override
  Future<void> archiveApplicationsForAcademicYear(String year) async =>
      copied.add('applications:$year');

  @override
  Future<void> archiveTasksForAcademicYear(String year) async =>
      copied.add('tasks:$year');

  @override
  Future<void> archiveAnnouncementsForAcademicYear(String year) async =>
      copied.add('announcements:$year');

  @override
  Future<void> archiveCalendarEventsForAcademicYear(String year) async =>
      copied.add('calendar_events:$year');

  @override
  Future<void> archiveEvaluationsForAcademicYear(String year) async =>
      copied.add('evaluations:$year');

  @override
  Future<void> archiveScreeningRecordsForAcademicYear(String year) async =>
      copied.add('screening_records:$year');

  @override
  Future<void> archiveAttendanceForAcademicYear(String year) async =>
      copied.add('attendance:$year');

  @override
  Future<void> restampAcademicYear(String from, String to) async {}

  @override
  Future<Map<String, int>> countRecordsToArchive(String year) async => {
    ...toArchive,
  };

  @override
  Future<Map<String, int>> countArchivedRecords(String year) async => {
    ...inArchive,
  };

  @override
  Future<List<User>> getAllUserProfiles() async => profiles;

  @override
  Future<List<Map<String, dynamic>>> getNotificationsForUser(
    String userId,
  ) async => [
    for (final n in stored)
      if (n['userId'] == userId) n,
  ];

  /// Like the rules: a notification can't be saved over another.
  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {
    final id = payload['id'];
    if (id != null &&
        [...stored, ...added].any((n) => n['id'] == id && id != '')) {
      throw Exception('permission-denied');
    }
    added.add(payload);
  }

  @override
  Future<void> updateNotification(String id, Map<String, dynamic> data) async {}

  @override
  Stream<Map<String, dynamic>?> docStream(String collection, String id) =>
      id == 'academic_year_settings'
      ? _settingsDoc.stream
      : const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> collectionStream(
    String collection, {
    bool newestFirst = false,
  }) => const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> whereStream(
    String collection,
    String field,
    Object value, {
    bool newestFirst = false,
  }) => const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> whereInStream(
    String collection,
    String field,
    List<Object> values,
  ) => const Stream.empty();

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => [];

  @override
  Future<List<String>> getHeadIds() async => [];
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final _admin = User(
  id: 'admin1',
  name: 'Ana Admin',
  email: 'admin@example.com',
  role: 'Admin',
);
final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@example.com',
  role: 'Head',
);
final _head2 = User(
  id: 'head2',
  name: 'Hugo Head',
  email: 'head2@example.com',
  role: 'Head',
);

/// Midnight [days] from today.
DateTime _day(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days);
}

Map<String, dynamic> _settings({
  String year = '2026-2027',
  required DateTime end,
}) => {
  'academicYear': year,
  'semester': 'Summer',
  'startDate': DateTime(end.year - 1, end.month, end.day + 1).toIso8601String(),
  'endDate': end.toIso8601String(),
  'allowApplications': true,
  'enforceHourCap': true,
  'autoArchiveLogs': true,
  'milestones': [],
};

Future<AppState> _signIn(_ArchiveFirestore fake, User user) async {
  final state = AppState(firestoreService: fake)..currentUser = user;
  addTearDown(state.dispose);
  await state.init();
  fake.push(fake.settings!);
  await _settle();
  return state;
}

void main() {
  group('a week before the end date', () {
    test('every Head is told the year will be archived, once', () async {
      final fake = _ArchiveFirestore()
        ..settings = _settings(end: _day(5))
        ..profiles = [_admin, _head, _head2];
      await _signIn(fake, _admin);

      final sent = fake.titled('Academic Year Ending Soon');
      expect(
        [for (final n in sent) n['id']],
        ['ay_ending_2026-2027_head1', 'ay_ending_2026-2027_head2'],
      );
      expect(sent.first['type'], 'academic_year');
      expect(sent.first['academicYear'], '2026-2027');
      expect(
        sent.first['message'],
        startsWith('AY 2026-2027 ends in 5 days ('),
      );

      // Saving the settings again doesn't send it again.
      fake.push({...fake.settings!, 'allowApplications': false});
      await _settle();
      expect(fake.titled('Academic Year Ending Soon'), hasLength(2));
    });

    test("a Head's session doesn't send one the Head already has", () async {
      final fake = _ArchiveFirestore()
        ..settings = _settings(end: _day(2))
        ..profiles = [_head]
        ..stored = [
          {
            'id': 'ay_ending_2026-2027_head1',
            'userId': 'head1',
            'title': 'Academic Year Ending Soon',
            'message': '',
            'type': 'academic_year',
          },
        ];
      final state = await _signIn(fake, _head);

      // Not even a local copy, which would show twice.
      expect(state.myNotifications, hasLength(1));
      expect(state.academicYearEndingSoon, isTrue);
    });

    test('nothing is sent earlier than that', () async {
      final fake = _ArchiveFirestore()
        ..settings = _settings(end: _day(AppState.archiveNoticeDays + 1))
        ..profiles = [_admin, _head];
      final state = await _signIn(fake, _admin);

      expect(fake.added, isEmpty);
      expect(state.academicYearEndingSoon, isFalse);
    });
  });

  group("in the Head's session", () {
    test('a year whose end date has passed waits a day before its records '
        'are copied', () async {
      final fake = _ArchiveFirestore()
        ..settings = _settings(end: _day(-1))
        ..profiles = [_head, _head2];
      final state = await _signIn(fake, _head);

      expect(fake.archives['2026-2027']!['dataArchived'], isFalse);
      expect(fake.copied, isEmpty);
      final ended = fake.titled('Academic Year Ended');
      expect([for (final n in ended) n['userId']], ['head1', 'head2']);
      expect(ended.first['academicYear'], '2026-2027');
      expect(ended.first['message'], contains('will be archived after'));

      final pending = state.pendingArchive!;
      expect(pending.year, '2026-2027');
      expect(
        pending.dueAt.difference(
          fake.archives['2026-2027']!['archivedAt'] as DateTime,
        ),
        AppState.archivePreviewWindow,
      );
      // Listed now, so no longer "ending soon".
      expect(state.academicYearEndingSoon, isFalse);
    });

    Map<String, dynamic> movedOn({required Duration ago}) => {
      ..._settings(year: '2027-2028', end: _day(300)),
      'previous': _settings(end: _day(-30)),
      'termChangedAt': DateTime.now().subtract(ago).toUtc().toIso8601String(),
    };

    test('a listed year is archived once its day has passed', () async {
      final fake = _ArchiveFirestore()
        ..settings = movedOn(ago: const Duration(hours: 25))
        ..profiles = [_head];
      fake.archives['2026-2027'] = {
        'academicYear': '2026-2027',
        'archivedAt': DateTime.now().subtract(const Duration(hours: 25)),
        'archiveAttendance': true,
        'dataArchived': false,
      };
      final state = await _signIn(fake, _head);

      expect(fake.copied, [
        'reports:2026-2027',
        'applications:2026-2027',
        'tasks:2026-2027',
        'announcements:2026-2027',
        'calendar_events:2026-2027',
        'evaluations:2026-2027',
        'screening_records:2026-2027',
        'attendance:2026-2027',
      ]);
      expect(fake.archives['2026-2027']!['dataArchived'], isTrue);
      final archived = fake.titled('Academic Year Archived').single;
      expect(archived['userId'], 'head1');
      expect(archived['academicYear'], '2026-2027');
      expect(state.pendingArchive, isNull);
    });

    test('a year listed less than a day ago waits', () async {
      final listedAt = DateTime.now().subtract(const Duration(hours: 2));
      final fake = _ArchiveFirestore()
        ..settings = movedOn(ago: const Duration(hours: 30))
        ..profiles = [_head];
      fake.archives['2026-2027'] = {
        'academicYear': '2026-2027',
        'archivedAt': listedAt,
        'dataArchived': false,
      };
      final state = await _signIn(fake, _head);

      expect(fake.copied, isEmpty);
      expect(
        state.pendingArchive!.dueAt,
        listedAt.add(AppState.archivePreviewWindow),
      );
    });

    test(
      'a year waits while the Admin can still undo moving on from it',
      () async {
        final fake = _ArchiveFirestore()
          ..settings = movedOn(ago: const Duration(hours: 1))
          ..profiles = [_head];
        // Listed long before, when its end date passed.
        fake.archives['2026-2027'] = {
          'academicYear': '2026-2027',
          'archivedAt': DateTime.now().subtract(const Duration(hours: 30)),
          'dataArchived': false,
        };
        final state = await _signIn(fake, _head);

        expect(fake.copied, isEmpty);
        expect(state.pendingArchive!.dueAt, state.termChangeUndoDeadline);
      },
    );
  });

  group('the Admin moving to the next year', () {
    Future<void> moveOn(AppState state) => state.updateAcademicYearSettings(
      year: '2027-2028',
      semester: '1st Semester',
      startDate: DateTime(2027, 8, 1),
      endDate: DateTime(2028, 7, 31),
      allowApplications: true,
      enforceHourCap: true,
      autoArchiveLogs: true,
      milestones: const [],
    );

    test('tells the Heads when the year will be archived, and when it '
        'is undone', () async {
      final fake = _ArchiveFirestore()
        ..settings = _settings(end: _day(40))
        ..profiles = [_admin, _head];
      final state = await _signIn(fake, _admin);

      await moveOn(state);
      await _settle();

      final closing = fake.titled('Academic Year Closing').single;
      expect(closing['userId'], 'head1');
      expect(closing['academicYear'], '2026-2027');
      expect(
        closing['message'],
        'The Admin started AY 2027-2028. AY 2026-2027\'s records will be '
        'archived after '
        '${AppState.monthDayTime(state.termChangeUndoDeadline!)}. Before '
        'then, preview what will be saved and finish anything still open.',
      );
      // The Admin's list shows it waiting.
      expect(state.academicYearArchive('2026-2027')!['dataArchived'], isFalse);

      await state.undoTermChange();
      await _settle();

      final undone = fake.titled('Academic Year Switch Undone').single;
      expect(undone['academicYear'], '2026-2027');
      expect(state.academicYearArchive('2026-2027'), isNull);
    });

    test("doesn't tell them again about a year listed when its end date "
        'passed', () async {
      final fake = _ArchiveFirestore()
        ..settings = _settings(end: _day(-2))
        ..profiles = [_admin, _head];
      fake.archives['2026-2027'] = {
        'academicYear': '2026-2027',
        'archivedAt': DateTime.now().subtract(const Duration(hours: 3)),
        'dataArchived': false,
      };
      final state = await _signIn(fake, _admin);

      await moveOn(state);
      await _settle();

      expect(fake.titled('Academic Year Closing'), isEmpty);
    });
  });

  group('what the preview shows', () {
    Application application(String id, String status, String year) =>
        Application(
          id: id,
          announcementId: 'ann1',
          announcementTitle: 'Library Assistant',
          applicantId: 'stu_$id',
          applicantName: 'Student $id',
          appliedAt: '2026-09-01',
          status: status,
          academicYear: year,
        );

    Task task(
      String id, {
      String status = 'Completed',
      String? review,
      bool archived = false,
    }) => Task(
      id: id,
      title: 'Task $id',
      description: '',
      status: status,
      priority: 'Medium',
      dueDate: 'Oct 1, 2026',
      academicYear: '2026-2027',
      reviewStatus: review,
      isArchived: archived,
    );

    AttendanceRecord log(String id, String? year, {bool archived = false}) =>
        AttendanceRecord(
          id: id,
          studentName: 'Sara Assistant',
          date: '2026-09-01',
          timeIn: '08:00',
          timeOut: '11:00',
          academicYear: year,
          isArchived: archived,
        );

    test("counts what's still open, by who has to finish it", () {
      final state = AppState(firestoreService: _ArchiveFirestore())
        ..currentUser = _head
        ..applications = [
          application('a1', 'Pending', '2026-2027'),
          application('a2', 'Approved', '2026-2027'),
          application('a3', 'Pending', '2025-2026'),
        ]
        ..announcements = [
          Announcement(
            id: 'r1',
            title: 'Library request',
            body: '',
            postedBy: 'Sid Supervisor',
            postedAt: '2026-09-01',
            approvalStatus: 'Pending',
            academicYear: '2026-2027',
          ),
          Announcement(
            id: 'r2',
            title: 'Registrar request',
            body: '',
            postedBy: 'Sid Supervisor',
            postedAt: '2026-09-01',
            academicYear: '2026-2027',
          ),
        ]
        ..reports = [
          Report(
            id: 'p1',
            title: 'September',
            content: '',
            studentName: 'Sara Assistant',
            status: 'Pending',
            academicYear: '2026-2027',
          ),
          Report(
            id: 'p2',
            title: 'August',
            content: '',
            studentName: 'Sara Assistant',
            status: 'Approved',
            academicYear: '2026-2027',
          ),
        ]
        ..tasks = [
          task('t1', review: 'Pending'),
          task('t2', review: 'Approved'),
          task('t3', review: 'Pending', archived: true),
          task('t4', status: 'In Progress'),
        ];

      expect(state.archiveOpenItems('2026-2027'), (
        applications: 1,
        requests: 1,
        reports: 1,
        tasks: 1,
      ));
    });

    test(
      'counts the records to be copied, attendance from the logs held',
      () async {
        final fake = _ArchiveFirestore()
          ..toArchive = {'reports': 42, 'applications': 65}
          ..inArchive = {'reports': 40, 'attendance': 300};
        final state = AppState(firestoreService: fake)
          ..currentUser = _head
          ..attendance = [
            log('l1', '2026-2027'),
            // Too old to carry a year: swept up with the first year archived.
            log('l2', null),
            log('l3', '2027-2028'),
            log('l4', '2026-2027', archived: true),
          ];

        expect(await state.countArchiveRecords('2026-2027'), {
          'reports': 42,
          'applications': 65,
          'attendance': 2,
        });

        state.autoArchiveAttendanceLogs = false;
        expect((await state.countArchiveRecords('2026-2027'))['attendance'], 0);

        // Once archived, what the archive holds.
        state.academicYearArchives = [
          {'academicYear': '2025-2026', 'dataArchived': true},
        ];
        expect(await state.countArchiveRecords('2025-2026'), {
          'reports': 40,
          'attendance': 300,
        });
      },
    );
  });

  group('the archive dialog', () {
    const toArchive = {
      'reports': 42,
      'applications': 65,
      'screening_records': 60,
      'tasks': 120,
      'evaluations': 25,
      'announcements': 18,
      'calendar_events': 30,
    };

    Map<String, dynamic> waiting() => {
      'academicYear': '2026-2027',
      'archivedAt': DateTime(2026, 10, 4, 15),
      'archiveAttendance': true,
      'dataArchived': false,
      'semester': 'Summer',
      'startDate': DateTime(2026, 8, 1).toIso8601String(),
      'endDate': DateTime(2027, 7, 31).toIso8601String(),
      'headcountByCampus': {'Boac Campus': 20, 'Gasan Campus': 5},
    };

    Future<void> open(
      WidgetTester tester,
      AppState state, {
      Size size = const Size(600, 1600),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showAcademicYearArchiveDialog(context, '2026-2027'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets("shows the Head what will be saved and what's still open", (
      tester,
    ) async {
      final state =
          AppState(firestoreService: _ArchiveFirestore()..toArchive = toArchive)
            ..currentUser = _head
            ..academicYear = '2027-2028'
            ..academicYearArchives = [waiting()]
            ..applications = [
              for (final id in ['a1', 'a2'])
                Application(
                  id: id,
                  announcementId: 'ann1',
                  announcementTitle: 'Library Assistant',
                  applicantId: 'stu_$id',
                  applicantName: 'Student $id',
                  appliedAt: '2026-09-01',
                  academicYear: '2026-2027',
                ),
            ];
      await open(tester, state);

      expect(find.text('AY 2026-2027'), findsOneWidget);
      expect(find.text('Aug 1, 2026 – Jul 31, 2027'), findsOneWidget);
      expect(
        find.text('Will be archived after Oct 5, 3:00 PM.'),
        findsOneWidget,
      );
      expect(find.text('WILL BE SAVED'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Attendance logs'), findsOneWidget);
      expect(find.text('2 applications not decided yet'), findsOneWidget);
      expect(find.text('STUDENT ASSISTANTS AT CLOSE'), findsOneWidget);
      expect(find.text('25 in all'), findsOneWidget);

      await tester.tap(find.text('Open Applications'));
      await tester.pumpAndSettle();

      expect(find.text('WILL BE SAVED'), findsNothing);
      expect(state.activeTab, 'applications');
    });

    testWidgets('fits a phone', (tester) async {
      final state =
          AppState(firestoreService: _ArchiveFirestore()..toArchive = toArchive)
            ..currentUser = _head
            ..academicYear = '2027-2028'
            ..academicYearArchives = [waiting()]
            ..announcements = [
              Announcement(
                id: 'r1',
                title: 'Library request',
                body: '',
                postedBy: 'Sid Supervisor',
                postedAt: '2026-09-01',
                approvalStatus: 'Pending',
                academicYear: '2026-2027',
              ),
            ];
      await open(tester, state, size: const Size(360, 740));

      // Laid out without overflowing; the rest scrolls.
      expect(tester.takeException(), isNull);
      expect(
        find.text('1 student assistant request waiting for your approval'),
        findsOneWidget,
      );
    });

    testWidgets('tells the Head when nothing is left open', (tester) async {
      final state =
          AppState(firestoreService: _ArchiveFirestore()..toArchive = toArchive)
            ..currentUser = _head
            ..academicYear = '2027-2028'
            ..academicYearArchives = [waiting()];
      await open(tester, state);

      expect(find.text('Nothing is left open.'), findsOneWidget);
    });

    testWidgets('shows the Admin a summary of an archived year', (
      tester,
    ) async {
      final state =
          AppState(
              firestoreService: _ArchiveFirestore()
                ..inArchive = {...toArchive, 'attendance': 0},
            )
            ..currentUser = _admin
            ..academicYear = '2027-2028'
            ..academicYearArchives = [
              {
                ...waiting(),
                'archiveAttendance': false,
                'dataArchived': true,
                'dataArchivedAt': DateTime(2026, 10, 5, 15, 12),
                'allowApplications': false,
                'enforceHourCap': true,
                'milestones': [
                  {
                    'title': 'Application deadline',
                    'date': DateTime(2026, 8, 15).toIso8601String(),
                  },
                ],
              },
            ];
      await open(tester, state);

      expect(find.text('Archived on Oct 5, 2026 at 3:12 PM.'), findsOneWidget);
      expect(find.text('RECORDS SAVED'), findsOneWidget);
      expect(find.text('65'), findsOneWidget);
      expect(find.text('Not archived'), findsOneWidget);
      expect(
        find.text(
          'Auto-archive Logs was off, so the attendance logs stayed in '
          'place.',
        ),
        findsOneWidget,
      );
      expect(find.text('STILL OPEN'), findsNothing);
      expect(find.text('Term when it closed'), findsOneWidget);
      expect(find.text('Summer'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Application deadline · Aug 15, 2026'), findsOneWidget);
    });

    testWidgets("tells the Admin a waiting year is counted once it's "
        'archived', (tester) async {
      final state = AppState(firestoreService: _ArchiveFirestore())
        ..currentUser = _admin
        ..academicYear = '2027-2028'
        ..academicYearArchives = [waiting()];
      await open(tester, state);

      expect(
        find.text(
          'Will be archived after Oct 5, 3:00 PM, the next time the Head '
          'opens SAIS.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'They\'re counted once the Head\'s session has archived them.',
        ),
        findsOneWidget,
      );
      expect(find.text('STILL OPEN'), findsNothing);
    });
  });

  group("the Head's pages", () {
    Future<void> pumpShell(WidgetTester tester, AppState state) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await tester.pump();
    }

    testWidgets('carry a banner a week before the end date', (tester) async {
      final state = AppState(firestoreService: _ArchiveFirestore())
        ..currentUser = _head
        ..academicYearEnd = _day(3);
      await pumpShell(tester, state);

      expect(
        find.textContaining('AY 2026-2027 ends in 3 days'),
        findsOneWidget,
      );
    });

    testWidgets('carry a banner while a year waits, which opens the preview', (
      tester,
    ) async {
      final state = AppState(firestoreService: _ArchiveFirestore())
        ..currentUser = _head
        ..academicYear = '2027-2028'
        ..academicYearEnd = _day(300)
        ..academicYearArchives = [
          {
            'academicYear': '2026-2027',
            'archivedAt': DateTime(2026, 10, 4, 15),
            'dataArchived': false,
          },
        ];
      await pumpShell(tester, state);

      expect(
        find.textContaining(
          'AY 2026-2027 will be archived after Oct 5, 3:00 PM.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('WILL BE SAVED'), findsOneWidget);
    });

    testWidgets('carry no banner otherwise', (tester) async {
      final state = AppState(firestoreService: _ArchiveFirestore())
        ..currentUser = _head
        ..academicYearEnd = _day(60);
      await pumpShell(tester, state);

      expect(find.text('Preview'), findsNothing);
    });

    testWidgets('open the preview from its notification', (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = AppState(firestoreService: _ArchiveFirestore())
        ..currentUser = _head
        ..academicYear = '2027-2028'
        ..academicYearArchives = [
          {
            'academicYear': '2026-2027',
            'archivedAt': DateTime(2026, 10, 4, 15),
            'dataArchived': false,
          },
        ]
        ..notifications = [
          AppNotification(
            id: 'n1',
            userId: 'head1',
            title: 'Academic Year Closing',
            message: 'The Admin started AY 2027-2028.',
            type: 'academic_year',
            createdAt: 'Oct 4, 2026',
            academicYear: '2026-2027',
          ),
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(body: AdminNotificationsScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      await tester.tap(find.text('Academic Year Closing'));
      await tester.pumpAndSettle();

      expect(find.text('AY 2026-2027'), findsOneWidget);
      expect(state.myNotifications.single.isRead, isTrue);
    });
  });
}
