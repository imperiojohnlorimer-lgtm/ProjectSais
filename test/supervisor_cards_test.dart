import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/supervisor_card.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/my_office/my_office_screen.dart';
import 'package:projectsais/screens/student_portal/student_portal_shell.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

// A real 1x1 PNG, as a profile picture is stored.
final _png =
    'data:image/png;base64,${base64Encode(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='))}';

/// Holds the cards in memory and remembers what was read and written.
class _Store extends FirestoreService {
  _Store({List<SupervisorCard> cards = const [], this.failReads = false})
    : cards = {for (final c in cards) c.id: c};

  final Map<String, SupervisorCard> cards;
  final bool failReads;
  final saved = <SupervisorCard>[];
  final asked = <Iterable<String>?>[];

  @override
  Future<List<SupervisorCard>> getSupervisorCards([
    Iterable<String>? ids,
  ]) async {
    asked.add(ids?.toList());
    if (failReads) throw Exception('permission-denied');
    return [
      for (final c in cards.values)
        if (ids == null || ids.contains(c.id)) c,
    ];
  }

  @override
  Future<void> saveSupervisorCards(List<SupervisorCard> list) async {
    saved.addAll(list);
    for (final c in list) {
      cards[c.id] = c;
    }
  }
}

User _user(
  String id,
  String name,
  String role, {
  String? avatar,
  String status = 'Active',
}) => User(
  id: id,
  name: name,
  email: '$id@marsu.edu.ph',
  role: role,
  avatar: avatar,
  status: status,
);

final _assistant = _user('sa1', 'Juan dela Cruz', 'Student Assistant');

Office _office({
  List<String> headIds = const ['sup1'],
  List<String> headNames = const ['Maria Santos'],
}) => Office(
  id: 'o1',
  name: 'Registrar',
  code: 'REG',
  headIds: headIds,
  headNames: headNames,
  assistantIds: const ['sa1'],
  assistantNames: const ['Juan dela Cruz'],
);

void main() {
  group('Office.supervisorEntries', () {
    test('pairs each name with its account id, without blanks or repeats', () {
      final office = _office(
        headIds: ['a', 'b', 'c', 'd'],
        headNames: ['', ' Maria Santos ', 'Maria Santos', 'Pedro Reyes'],
      );

      expect(office.supervisorEntries, [
        (id: 'b', name: 'Maria Santos'),
        (id: 'd', name: 'Pedro Reyes'),
      ]);
      expect([
        for (final s in office.supervisorEntries) s.name,
      ], office.supervisorNames);
    });

    test('a name saved without an id has an empty one', () {
      final office = _office(headIds: [], headNames: ['Maria Santos']);

      expect(office.supervisorEntries, [(id: '', name: 'Maria Santos')]);
    });
  });

  group('loading the pictures', () {
    test('keeps the avatar of each card found', () async {
      final store = _Store(
        cards: [
          SupervisorCard(id: 'sup1', name: 'Maria Santos', avatar: _png),
          const SupervisorCard(id: 'sup2', name: 'Pedro Reyes'),
        ],
      );
      final state = AppState(firestoreService: store)..currentUser = _assistant;

      await state.loadSupervisorCards(['sup1', 'sup2', 'nobody', '']);

      expect(state.supervisorAvatars, {'sup1': _png, 'sup2': ''});
      // Never asks for a blank id.
      expect(store.asked.single, unorderedEquals(['sup1', 'sup2', 'nobody']));
    });

    test('a refused read leaves things as they were', () async {
      final state = AppState(firestoreService: _Store(failReads: true))
        ..currentUser = _assistant
        ..supervisorAvatars = {'sup1': _png};

      await state.loadSupervisorCards(['sup1']);

      expect(state.supervisorAvatars, {'sup1': _png});
    });

    test('an answer that arrives after sign-out is dropped', () async {
      final state = AppState(
        firestoreService: _Store(
          cards: [SupervisorCard(id: 'sup1', name: 'M', avatar: _png)],
        ),
      )..currentUser = _assistant;

      final loading = state.loadSupervisorCards(['sup1']);
      state.currentUser = null;
      await loading;

      expect(state.supervisorAvatars, isEmpty);
    });
  });

  group('keeping the cards in step', () {
    test('a Head writes the cards that are missing or out of date', () async {
      final store = _Store(
        cards: [
          const SupervisorCard(id: 'sup1', name: 'Old Name', avatar: 'x'),
          SupervisorCard(id: 'sup2', name: 'Pedro Reyes', avatar: _png),
        ],
      );
      final state = AppState(firestoreService: store)
        ..currentUser = _user('h1', 'Hana Head', 'Head')
        ..users = [
          _user('h1', 'Hana Head', 'Head', avatar: _png),
          _user('sup1', 'Maria Santos', 'Supervisor', avatar: _png),
          _user('sup2', 'Pedro Reyes', 'Supervisor', avatar: _png),
          _user('sup3', 'Ana Cruz', 'Supervisor', avatar: _png),
          // No picture and no card: nothing to write.
          _user('sup4', 'Lito Lim', 'Supervisor'),
          _user('sa1', 'Juan dela Cruz', 'Student Assistant', avatar: _png),
          _user('sup5', 'Gone', 'Supervisor', avatar: _png, status: 'Archived'),
        ];

      await state.syncSupervisorCards();

      expect(store.asked.single, isNull, reason: 'a Head reads every card');
      expect(store.saved.map((c) => c.id), unorderedEquals(['sup1', 'sup3']));
      expect(store.cards['sup1']!.name, 'Maria Santos');
      expect(store.cards['sup1']!.avatar, _png);
    });

    test('a removed picture clears the card', () async {
      final store = _Store(
        cards: [SupervisorCard(id: 'sup1', name: 'Maria Santos', avatar: _png)],
      );
      final state = AppState(firestoreService: store)
        ..currentUser = _user('h1', 'Hana Head', 'Head')
        ..users = [_user('sup1', 'Maria Santos', 'Supervisor')];

      await state.syncSupervisorCards();

      expect(store.cards['sup1']!.avatar, '');
    });

    test('a Supervisor writes only their own card', () async {
      final store = _Store();
      final me = _user('sup1', 'Maria Santos', 'Supervisor', avatar: _png);
      final state = AppState(firestoreService: store)
        ..currentUser = me
        ..users = [
          me,
          _user('sup2', 'Pedro Reyes', 'Supervisor', avatar: _png),
        ];

      await state.syncSupervisorCards();

      expect(store.asked.single, ['sup1']);
      expect(store.saved.map((c) => c.id), ['sup1']);
    });

    test('nothing is read or written again until a profile changes', () async {
      final store = _Store();
      final state = AppState(firestoreService: store)
        ..currentUser = _user('h1', 'Hana Head', 'Head')
        ..users = [_user('sup1', 'Maria Santos', 'Supervisor', avatar: _png)];

      await state.syncSupervisorCards();
      await state.syncSupervisorCards();

      expect(store.asked, hasLength(1));
      expect(store.saved, hasLength(1));

      state.users = [
        _user('sup1', 'Maria Santos', 'Supervisor', avatar: '$_png '),
      ];
      await state.syncSupervisorCards();

      expect(store.saved, hasLength(2));
    });

    test('a failed save is tried again on the next roster update', () async {
      final store = _Store(failReads: true);
      final state = AppState(firestoreService: store)
        ..currentUser = _user('h1', 'Hana Head', 'Head')
        ..users = [_user('sup1', 'Maria Santos', 'Supervisor', avatar: _png)];

      await state.syncSupervisorCards();
      await state.syncSupervisorCards();

      expect(store.asked, hasLength(2));
    });

    test('a Student Assistant writes nothing', () async {
      final store = _Store();
      final state = AppState(firestoreService: store)
        ..currentUser = _assistant
        ..users = [_user('sup1', 'Maria Santos', 'Supervisor', avatar: _png)];

      await state.syncSupervisorCards();

      expect(store.asked, isEmpty);
      expect(store.saved, isEmpty);
    });

    test('signing out forgets the pictures', () {
      final state = AppState(firestoreService: _Store())
        ..currentUser = _assistant
        ..supervisorAvatars = {'sup1': _png};

      state.logout();

      expect(state.supervisorAvatars, isEmpty);
    });
  });

  group('My Office', () {
    Future<AppState> pump(WidgetTester tester, _Store store) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = AppState(firestoreService: store)
        ..currentUser = _assistant
        ..offices = [
          _office(
            headIds: ['sup1', 'sup2'],
            headNames: ['Maria Santos', 'Pedro Reyes'],
          ),
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: MyOfficeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('shows each supervisor\'s picture, initials without one', (
      tester,
    ) async {
      final store = _Store(
        cards: [SupervisorCard(id: 'sup1', name: 'Maria Santos', avatar: _png)],
      );
      await pump(tester, store);

      expect(find.text('SUPERVISORS'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('Pedro Reyes'), findsOneWidget);
      // Maria has a picture; Pedro has no card, so his initials show.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('PR'), findsOneWidget);
      expect(find.text('MS'), findsNothing);
      expect(store.asked.single, unorderedEquals(['sup1', 'sup2']));
    });

    testWidgets('View picture enlarges it, and closes again', (tester) async {
      final store = _Store(
        cards: [SupervisorCard(id: 'sup1', name: 'Maria Santos', avatar: _png)],
      );
      await pump(tester, store);

      // Only the supervisor who has a picture offers it.
      expect(find.text('View picture'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.text('View picture'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Maria Santos'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('tapping the picture itself opens it too', (tester) async {
      final store = _Store(
        cards: [SupervisorCard(id: 'sup1', name: 'Maria Santos', avatar: _png)],
      );
      await pump(tester, store);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('a picture that cannot be shown says so', (tester) async {
      final store = _Store(
        cards: [
          const SupervisorCard(
            id: 'sup1',
            name: 'Maria Santos',
            avatar: 'data:image/png;base64,not-an-image',
          ),
        ],
      );
      await pump(tester, store);

      await tester.tap(find.text('View picture'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't show the picture."), findsOneWidget);
    });

    testWidgets('shows initials while the pictures cannot be read', (
      tester,
    ) async {
      await pump(tester, _Store(failReads: true));

      expect(find.text('MS'), findsOneWidget);
      expect(find.text('PR'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('below the phone\'s status bar', () {
    void fakeStatusBar(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 40);
      tester.view.viewPadding = const FakeViewPadding(top: 40);
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      // The test font draws every glyph as a full square, so some rows
      // overflow here though they fit in the app.
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
    }

    testWidgets('the staff and Admin header starts under it', (tester) async {
      fakeStatusBar(tester);
      final state = AppState(firestoreService: _Store())
        ..currentUser = _user('h1', 'Hana Head', 'Head');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(theme: AppTheme.theme, home: const AppShell()),
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(find.byIcon(Icons.menu_rounded).first).dy,
        greaterThanOrEqualTo(40),
      );
    });

    testWidgets('the Student header starts under it', (tester) async {
      fakeStatusBar(tester);
      final state = AppState(firestoreService: _Store())
        ..currentUser = _user('st1', 'Stu Student', 'Student');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const StudentPortalShell(),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(find.byIcon(Icons.notifications_outlined).first).dy,
        greaterThanOrEqualTo(40),
      );
    });

    testWidgets('without a status bar nothing moves', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
      final state = AppState(firestoreService: _Store())
        ..currentUser = _user('h1', 'Hana Head', 'Head');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(theme: AppTheme.theme, home: const AppShell()),
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(find.byIcon(Icons.menu_rounded).first).dy,
        lessThan(30),
      );
    });
  });
}
