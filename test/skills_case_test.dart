import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/skills_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Keeps the skill writes, and feeds live lists the test pushes.
class _Store extends FirestoreService {
  final saved = <String>[];
  final deleted = <String>[];
  final _lists = <String, StreamController<List<Map<String, dynamic>>>>{};

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
      const Stream.empty();

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => [];

  @override
  Future<List<String>> getHeadIds() async => [];

  @override
  Future<void> setHeadIds(List<String> ids) async {}

  @override
  Future<void> setSkill(String name) async => saved.add(name);

  @override
  Future<void> deleteSkill(String name) async => deleted.add(name);

  @override
  Future<void> updateSkill(String oldName, String newName) async {
    saved.add(newName);
    // Firestore reports the new name before the old one is gone.
    list('skills').add([
      {'name': oldName},
      {'name': newName},
    ]);
    await Future<void>.delayed(Duration.zero);
    if (oldName != newName) deleted.add(oldName);
  }
}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store();
    state = AppState(firestoreService: store)..currentUser = _head;
  });

  test('one skill per name whatever its case, the best spelling kept', () {
    expect(
      AppState.uniqueSkills([
        'Communication skills',
        'Web Developer',
        'Communication Skills',
        ' web developer ',
      ]),
      ['Communication Skills', 'Web Developer'],
    );
  });

  test(
    "the Head's session merges a skill saved twice in different case",
    () async {
      await state.init();
      store.list('skills').add([
        {'name': 'Communication Skills'},
        {'name': 'Communication skills'},
        {'name': 'Programmer'},
      ]);
      await _settle();

      expect(state.skills, ['Communication Skills', 'Programmer']);
      expect(store.deleted, ['Communication skills']);
    },
  );

  test(
    'a rename to the same name in other case deletes only the old one',
    () async {
      await state.init();
      store.list('skills').add([
        {'name': 'Communication Skills'},
      ]);
      await _settle();

      expect(
        await state.updateSkill('Communication Skills', 'Communication skills'),
        isTrue,
      );
      await _settle();

      expect(store.deleted, ['Communication Skills']);
      expect(state.skills, ['Communication skills']);
    },
  );

  test('a skill saved with spaces around it is not deleted', () async {
    await state.init();
    store.list('skills').add([
      {'name': ' Filing '},
    ]);
    await _settle();

    expect(store.deleted, isEmpty);
    expect(state.findSkill('filing'), ' Filing ');
  });

  test(
    'a skill already on the list, in any case, is not added again',
    () async {
      state.skills = ['Communication Skills'];

      expect(await state.addSkill('communication skills'), isFalse);
      expect(await state.addSkill('Filing'), isTrue);
      expect(store.saved, ['Filing']);
    },
  );

  test('a skill can be renamed to its own name in another case, not to '
      "another skill's", () async {
    state.skills = ['Communication skills', 'Filing'];

    expect(
      await state.updateSkill('Communication skills', 'Communication Skills'),
      isTrue,
    );
    expect(state.skills, ['Communication Skills', 'Filing']);
    expect(await state.updateSkill('Filing', 'communication SKILLS'), isFalse);
  });

  test("a student's skills count once whatever their case", () {
    state.skills = ['Communication Skills'];
    final assistant = User(
      id: 'sa1',
      name: 'Sara Assistant',
      email: 'sara@marsu.edu.ph',
      role: 'Student Assistant',
      skills: const ['Communication skills', 'Filing'],
    );
    state.applications = [
      Application(
        id: 'app1',
        announcementId: 'call1',
        announcementTitle: Application.generalTitle,
        applicantId: 'sa1',
        applicantName: 'Sara Assistant',
        appliedAt: 'Oct 2, 2026',
        status: Application.approved,
        skills: const ['Communication Skills'],
      ),
    ];

    expect(state.skillsForUser(assistant), ['Communication Skills', 'Filing']);
  });

  testWidgets('adding a skill in another case says it is already there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    state.skills = ['Communication Skills'];
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: SkillsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Skill').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'communication skills');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('"Communication Skills" is already on the list.'),
      findsOneWidget,
    );
    expect(store.saved, isEmpty);
  });
}
