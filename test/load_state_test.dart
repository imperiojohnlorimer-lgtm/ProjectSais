import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/skills_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

/// Live queries the test answers (or fails) by hand.
class _FakeLiveFirestore extends FirestoreService {
  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};
  final _docs = <String, StreamController<Map<String, dynamic>?>>{};

  /// What the students-record lookup returns.
  List<String> studentRecordIds = [];

  /// When set, the first fetch of the user's notifications waits for it.
  Completer<List<Map<String, dynamic>>>? notificationsFetch;

  @override
  Future<List<Map<String, dynamic>>> getNotificationsForUser(String userId) =>
      notificationsFetch?.future ?? Future.value(const []);

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
  Future<List<String>> getStudentIdsForUser(String uid) async =>
      studentRecordIds;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final _student = User(
  id: 'stu1',
  name: 'Sam Student',
  email: 'sam@example.com',
  role: 'Student Assistant',
);
final _head = User(
  id: 'head1',
  name: 'Hana Head',
  email: 'head@example.com',
  role: 'Head',
);

void main() {
  late _FakeLiveFirestore fake;
  late AppState state;
  var disposed = false;

  Future<void> signIn(User user) async {
    disposed = false;
    state = AppState(firestoreService: fake)..currentUser = user;
    await state.init();
  }

  setUp(() => fake = _FakeLiveFirestore());

  tearDown(() {
    if (!disposed) state.dispose();
  });

  test('a list is loading until its query answers', () async {
    await signIn(_head);

    expect(state.isLoaded('Users'), isFalse);
    expect(state.isLoaded('Students'), isFalse);

    fake.list('users').add([_head.toJson()]);
    await _settle();

    expect(state.isLoaded('Users'), isTrue);
    expect(state.isLoaded('Students'), isFalse);

    fake.list('students').add([]);
    await _settle();
    expect(state.isLoaded('Students'), isTrue);
  });

  test('an empty answer counts as loaded', () async {
    await signIn(_head);

    fake.list('students').add([]);
    await _settle();

    expect(state.isLoaded('Students'), isTrue);
    expect(state.students, isEmpty);
  });

  test(
    'a query that fails counts as answered, not as loading forever',
    () async {
      await signIn(_head);

      fake.list('users').addError(Exception('permission-denied'));
      await _settle();

      expect(state.isLoaded('Users'), isTrue);
    },
  );

  test('a query this role never opens is never loading', () async {
    await signIn(_student);

    // Only staff and the Admin read the whole roster.
    expect(state.isLoaded('Users'), isTrue);
    expect(state.isLoaded('Head forwards'), isTrue);
  });

  test(
    'a student assistant\'s tasks load when every query has answered',
    () async {
      await signIn(_student);

      expect(state.isLoaded('Tasks'), isFalse);

      fake.list('tasks.assignedTo=stu1').add([]);
      await _settle();
      // The by-name query is still to answer.
      expect(state.isLoaded('Tasks'), isFalse);

      fake.list('tasks.assignedToName=Sam Student').add([]);
      await _settle();
      // No students record: nothing more to wait for.
      expect(state.isLoaded('Tasks'), isTrue);
    },
  );

  test('tasks wait for the students-record query when there is one', () async {
    fake.studentRecordIds = ['rec1'];
    await signIn(_student);

    fake.list('tasks.assignedTo=stu1').add([]);
    fake.list('tasks.assignedToName=Sam Student').add([]);
    await _settle();
    expect(state.isLoaded('Tasks'), isFalse);

    fake.list('tasks.assignedTo in [rec1]').add([]);
    await _settle();
    expect(state.isLoaded('Tasks'), isTrue);
  });

  test(
    'lists show loading while the first fetches are still running',
    () async {
      fake.notificationsFetch = Completer();
      state = AppState(firestoreService: fake)..currentUser = _head;

      final starting = state.init();
      await _settle();
      // The user is known, the listeners aren't started yet.
      expect(state.isLoaded('Users'), isFalse);
      expect(state.isLoaded('Tasks'), isFalse);

      fake.notificationsFetch!.complete(const []);
      await starting;
      // Now they are started, and each waits for its own first answer.
      expect(state.isLoaded('Users'), isFalse);
      fake.list('users').add([_head.toJson()]);
      await _settle();
      expect(state.isLoaded('Users'), isTrue);
    },
  );

  test('before the listeners start nothing is shown as loading', () {
    state = AppState(firestoreService: fake)..currentUser = _head;

    expect(state.isLoaded('Users'), isTrue);
  });

  testWidgets('disposing while it starts up leaves nothing running', (
    tester,
  ) async {
    state = AppState(firestoreService: fake)..currentUser = _head;
    disposed = true;

    final starting = state.init();
    state.dispose();
    await starting;

    // A widget test fails on a timer still pending, or on a notify after
    // dispose; neither happens.
    expect(state.isLoaded('Users'), isTrue);
  });

  testWidgets('a list stops loading after the wait, answered or not', (
    tester,
  ) async {
    await signIn(_head);
    expect(state.isLoaded('Users'), isFalse);

    await tester.pump(AppState.loadTimeout + const Duration(seconds: 1));

    expect(state.isLoaded('Users'), isTrue);
    expect(state.isLoaded('Students'), isTrue);
  });

  testWidgets('a list shows loading, not "nothing here", until it answers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await signIn(_head);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SkillsScreen())),
      ),
    );
    expect(find.byType(LoadingState), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    fake.list('skills').add([]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoadingState), findsNothing);
    expect(find.text('No skills yet — add one to get started'), findsOneWidget);

    // A widget test checks for timers before tearDown runs.
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    disposed = true;
  });
}
