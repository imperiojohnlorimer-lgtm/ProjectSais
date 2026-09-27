import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/student_portal/sp_notifications_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

/// Records the notification writes the app makes instead of sending them to
/// Firestore, and fakes the few other reads and writes the flows under test
/// need. Live queries get a controller the test pushes documents into.
class _RecordingFirestore extends FirestoreService {
  final added = <Map<String, dynamic>>[];
  final updated = <String, Map<String, dynamic>>{};
  final savedTasks = <Task>[];
  bool failAnnouncementUpdates = false;

  /// What meta/heads holds.
  List<String> headIds = [];
  final publishedHeadIds = <List<String>>[];

  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};

  StreamController<List<Map<String, dynamic>>> list(String key) =>
      _lists.putIfAbsent(key, StreamController.broadcast);

  List<Map<String, dynamic>> sentTo(String userId) =>
      added.where((n) => n['userId'] == userId).toList();

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
      const Stream.empty();

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => [];

  @override
  Future<List<String>> getHeadIds() async => headIds;

  @override
  Future<void> setHeadIds(List<String> ids) async {
    publishedHeadIds.add(ids);
    headIds = ids;
  }

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      added.add(payload);

  @override
  Future<void> updateNotification(
    String id,
    Map<String, dynamic> data,
  ) async => updated[id] = data;

  @override
  Future<void> setApplication(Application a) async {}

  @override
  Future<void> setTask(Task t) async => savedTasks.add(t);

  @override
  Future<void> updateAnnouncement(String id, Map<String, dynamic> data) async {
    if (failAnnouncementUpdates) throw Exception('permission-denied');
  }

  @override
  Future<DocumentReference> addAnnouncement({
    required String title,
    required String body,
    Map<String, dynamic>? extra,
    String? id,
  }) async => _FakeDocRef(id ?? 'new-announcement');
}

// ignore: subtype_of_sealed_class
/// Stands in for the reference Firestore hands back for a new document;
/// the app only reads its id.
class _FakeDocRef implements DocumentReference<Map<String, dynamic>> {
  _FakeDocRef(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@example.com',
  role: 'Head',
);
final _supervisor = User(
  id: 'sup1',
  name: 'Sid Supervisor',
  email: 'sup@example.com',
  role: 'Supervisor',
);
final _assistant = User(
  id: 'sa1',
  name: 'Sara Assistant',
  email: 'sa@example.com',
  role: 'Student Assistant',
);
final _student = User(
  id: 'stu1',
  name: 'Sam Student',
  email: 'sam@example.com',
  role: 'Student',
);

AppNotification _notif(
  String id,
  String userId, {
  bool isRead = false,
  String type = 'system',
}) => AppNotification(
  id: id,
  userId: userId,
  title: 'Title $id',
  message: 'Message $id',
  type: type,
  createdAt: 'Sep 1, 2026, 9:00 AM',
  isRead: isRead,
);

Task _task({String? assignedTo, String? assignedBy}) => Task(
  id: 't1',
  title: 'File the forms',
  description: '',
  status: 'Not Started',
  priority: 'Medium',
  dueDate: 'Oct 1, 2026',
  assignedTo: assignedTo,
  assignedToName: 'Sara Assistant',
  assignedBy: assignedBy,
);

void main() {
  late _RecordingFirestore fake;
  late AppState state;

  setUp(() {
    fake = _RecordingFirestore();
    state = AppState(firestoreService: fake);
  });

  group('applications', () {
    final application = Application(
      id: 'app1',
      announcementId: 'ann1',
      announcementTitle: 'Library Assistant',
      applicantId: _student.id,
      applicantName: _student.name,
      appliedAt: '2026-09-27',
    );

    test('a student applying alerts the Head', () async {
      // A Student can't list other profiles, so after loading, their own is
      // the only one the app knows about.
      fake.headIds = ['head1'];
      state
        ..currentUser = _student
        ..users = [_student];

      final ok = await state.submitApplication(application);

      expect(ok, isTrue);
      expect(fake.sentTo('stu1').single['title'], 'Application Submitted');
      expect(fake.sentTo('head1').single['title'], 'New Application');
    });

    test("a Head's session publishes the Heads for students", () async {
      state.currentUser = _head;
      await state.init();

      fake.list('users').add([
        _head.toJson(),
        _supervisor.toJson(),
        _student.toJson(),
        User(
          id: 'head0',
          name: 'Former Head',
          email: 'former@example.com',
          role: 'Head',
          status: 'Archived',
        ).toJson(),
      ]);
      await _settle();
      // The same roster again doesn't rewrite it.
      fake.list('users').add([_head.toJson(), _supervisor.toJson()]);
      await _settle();

      expect(fake.publishedHeadIds, [
        ['head1'],
      ]);
    });

    test('a student\'s session never publishes the Heads', () async {
      state.currentUser = _student;
      await state.init();

      expect(fake.list('users').hasListener, isFalse);
      expect(fake.publishedHeadIds, isEmpty);
    });
  });

  group('tasks', () {
    test('a new task alerts the student at their account id', () async {
      // An older roster entry, whose id is not the account id.
      state
        ..currentUser = _supervisor
        ..students = [
          Student(
            id: 'roster9',
            name: _assistant.name,
            email: _assistant.email,
            department: 'CICS',
            userId: _assistant.id,
          ),
        ];

      await state.addTask(_task(assignedTo: 'roster9'));

      expect(fake.sentTo('sa1').single['title'], 'New Task Assigned');
      expect(fake.sentTo('roster9'), isEmpty);
    });

    test('a new task records who assigned it', () async {
      state.currentUser = _supervisor;

      await state.addTask(_task(assignedTo: 'sa1'));

      expect(fake.savedTasks.single.assignedBy, 'sup1');
    });

    test('a status change alerts whoever assigned the task', () async {
      state
        ..currentUser = _assistant
        ..tasks = [_task(assignedTo: 'sa1', assignedBy: 'sup1')];

      await state.updateTaskStatus('t1', 'In Progress');

      expect(fake.sentTo('sup1').single['type'], 'task');
    });

    test(
      "a status change on an older task alerts the student's supervisors",
      () async {
        state
          ..currentUser = _assistant
          ..offices = [
            Office(
              id: 'o1',
              name: 'Library',
              code: 'LIB',
              headIds: ['sup1'],
              assistantIds: ['sa1'],
            ),
          ]
          ..tasks = [_task(assignedTo: 'sa1')];

        await state.updateTaskStatus('t1', 'Completed');

        expect(fake.sentTo('sup1').single['type'], 'task');
      },
    );

    test('changing the status of your own task alerts no one', () async {
      state
        ..currentUser = _supervisor
        ..tasks = [_task(assignedTo: 'sa1', assignedBy: 'sup1')];

      await state.updateTaskStatus('t1', 'In Progress');

      expect(fake.added, isEmpty);
    });
  });

  group('announcements', () {
    final pending = Announcement(
      id: 'a1',
      title: 'Office Aide',
      body: 'Body',
      postedBy: _supervisor.name,
      postedByRole: 'Supervisor',
      postedAt: '2026-09-27',
      postedById: _supervisor.id,
      approvalStatus: 'Pending',
      isOpen: false,
    );

    test('a request sent for approval alerts every Head', () async {
      state
        ..currentUser = _supervisor
        ..users = [
          _head,
          _supervisor,
          User(
            id: 'head2',
            name: 'Hugo Head',
            email: 'head2@example.com',
            role: 'Head',
          ),
        ];

      final ok = await state.submitAnnouncementForApproval(pending);

      expect(ok, isTrue);
      for (final headId in ['head1', 'head2']) {
        expect(
          fake.sentTo(headId).single['title'],
          'Student Assistant Request Awaiting Approval',
        );
      }
      expect(fake.sentTo('sup1'), isEmpty);
    });

    test('approving tells the supervisor who asked and the students', () async {
      state
        ..currentUser = _head
        ..users = [_head, _supervisor, _student]
        ..announcements = [pending];

      final ok = await state.approveAnnouncement('a1');

      expect(ok, isTrue);
      expect(fake.sentTo('sup1').single['title'], 'Announcement Approved');
      expect(fake.sentTo('stu1').single['title'], 'New Hiring Announcement');
    });

    test('rejecting tells the supervisor who asked', () async {
      state
        ..currentUser = _head
        ..announcements = [pending];

      final ok = await state.rejectAnnouncement('a1', reason: 'No budget');

      expect(ok, isTrue);
      expect(
        fake.sentTo('sup1').single['message'],
        'Your announcement "Office Aide" was not approved. Reason: No budget',
      );
      expect(state.announcements.single.approvalStatus, 'Rejected');
    });

    test('a rejection that fails to save tells no one', () async {
      fake.failAnnouncementUpdates = true;
      state
        ..currentUser = _head
        ..announcements = [pending];

      final ok = await state.rejectAnnouncement('a1');

      expect(ok, isFalse);
      expect(fake.sentTo('sup1'), isEmpty);
      expect(state.announcements.single.approvalStatus, 'Pending');
    });
  });

  group('read state', () {
    test("you only see your own notifications, even another Head's", () {
      state
        ..currentUser = _head
        ..notifications = [
          _notif('n1', 'head1'),
          _notif('n2', 'head2'),
        ];

      expect(state.myNotifications.map((n) => n.id), ['n1']);
      expect(state.unreadNotificationCount, 1);
    });

    test('mark all read only writes the unread ones', () {
      state
        ..currentUser = _assistant
        ..notifications = [
          _notif('n1', 'sa1', isRead: true),
          _notif('n2', 'sa1'),
          _notif('n3', 'someone-else'),
        ];

      state.markAllNotificationsRead();

      expect(fake.updated.keys, ['n2']);
      expect(state.unreadNotificationCount, 0);
    });

    test('a new notification has the same id here as when saved', () async {
      fake.headIds = ['head1'];
      state
        ..currentUser = _student
        ..users = [_student];
      await state.submitApplication(
        Application(
          id: 'app1',
          announcementId: 'ann1',
          announcementTitle: 'Library Assistant',
          applicantId: _student.id,
          applicantName: _student.name,
          appliedAt: '2026-09-27',
        ),
      );

      final local = state.myNotifications.single;
      expect(local.id, fake.sentTo('stu1').single['id']);
      // Stamped with the time, like the saved one will show.
      expect(local.createdAt, matches(RegExp(r', \d{1,2}:\d{2} (AM|PM)$')));

      // So marking it read before the live feed catches up still reaches
      // the saved notification.
      state.markNotificationRead(local.id);
      expect(fake.updated.keys, [local.id]);
    });
  });

  group('pending timestamps', () {
    test('a createdAt still being written reads as now', () {
      final data = FirestoreService.withPendingTimestamp({
        'createdAt': null,
      }, hasPendingWrites: true);

      final created = (data['createdAt'] as Timestamp).toDate();
      expect(DateTime.now().difference(created).inSeconds, lessThan(5));
    });

    test('saved and older records are left alone', () {
      final saved = Timestamp.fromDate(DateTime(2026, 9, 1));
      expect(
        FirestoreService.withPendingTimestamp({
          'createdAt': saved,
        }, hasPendingWrites: true)['createdAt'],
        saved,
      );
      // Written before createdAt existed: still sorts last.
      expect(
        FirestoreService.withPendingTimestamp({
          'title': 'Old',
        }, hasPendingWrites: true).containsKey('createdAt'),
        isFalse,
      );
      expect(
        FirestoreService.withPendingTimestamp({
          'createdAt': null,
        }, hasPendingWrites: false)['createdAt'],
        isNull,
      );
    });
  });

  group('opening a notification', () {
    String? tabFor(String type, User user) {
      state.currentUser = user;
      return state.notificationTab(_notif('n', user.id, type: type));
    }

    test('goes to the screen for that role', () {
      expect(tabFor('application', _head), 'applications');
      expect(tabFor('application', _student), 'announcements');
      expect(tabFor('announcement', _head), 'announcements_admin');
      expect(tabFor('announcement', _supervisor), 'sv_announcements');
      expect(tabFor('announcement', _assistant), 'announcements');
      expect(tabFor('task', _supervisor), 'tasks');
      expect(tabFor('task', _assistant), 'tasks');
      expect(tabFor('report', _supervisor), 'reports');
      expect(tabFor('head_forward', _head), 'head_forwards');
      expect(tabFor('office', _head), 'offices');
      expect(tabFor('system', _assistant), 'profile');
    });

    test('opens nothing when the message says it all', () {
      expect(tabFor('payroll', _assistant), isNull);
      expect(tabFor('evaluation', _assistant), isNull);
      expect(tabFor('rehire', _assistant), isNull);
      expect(tabFor('head_forward', _supervisor), isNull);
    });

    Future<List<String>> pumpScreen(
      WidgetTester tester,
      List<AppNotification> notifications,
    ) async {
      final opened = <String>[];
      state
        ..currentUser = _assistant
        ..notifications = notifications;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(body: SpNotificationsScreen(onOpen: opened.add)),
          ),
        ),
      );
      return opened;
    }

    testWidgets('tapping one marks it read and opens its screen', (
      tester,
    ) async {
      final opened = await pumpScreen(tester, [
        _notif('n1', 'sa1', type: 'task'),
      ]);

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Title n1'));
      await tester.pump();

      expect(opened, ['tasks']);
      expect(fake.updated.keys, ['n1']);
      expect(state.unreadNotificationCount, 0);
    });

    testWidgets('one with nothing to open is only marked read', (
      tester,
    ) async {
      final opened = await pumpScreen(tester, [
        _notif('n1', 'sa1', type: 'payroll'),
      ]);

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
      await tester.tap(find.text('Title n1'));
      await tester.pump();

      expect(opened, isEmpty);
      expect(fake.updated.keys, ['n1']);
    });
  });

  group('header bell', () {
    Future<void> tapPhoneBell(WidgetTester tester, User user) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      state.currentUser = user;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.notifications_outlined).first);
      await tester.pump();
    }

    testWidgets("takes the Head to the Head's notifications on a phone", (
      tester,
    ) async {
      await tapPhoneBell(tester, _head);
      expect(state.activeTab, 'admin_notifications');
    });

    testWidgets('takes a Supervisor to their notifications on a phone', (
      tester,
    ) async {
      await tapPhoneBell(tester, _supervisor);
      expect(state.activeTab, 'sa_notifications');
    });
  });

  group('unread badge', () {
    Future<Size> badgeSize(WidgetTester tester, int count) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                Positioned(
                  top: -2,
                  right: -2,
                  child: UnreadBadge(count: count),
                ),
              ],
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(UnreadBadge));
    }

    testWidgets('is a 14px circle for one digit', (tester) async {
      expect(await badgeSize(tester, 5), const Size(14, 14));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('widens for bigger counts and stops at 99+', (tester) async {
      final size = await badgeSize(tester, 150);

      expect(find.text('99+'), findsOneWidget);
      expect(size.height, 14);
      expect(size.width, greaterThan(14));
      expect(tester.takeException(), isNull);
    });
  });
}
