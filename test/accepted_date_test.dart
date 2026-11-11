import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/profile/profile_screen.dart';
import 'package:projectsais/screens/students/students_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/utils/philippine_dates.dart';

import 'support/account_writes.dart';

class _Store extends FirestoreService with AccountWrites {
  final studentDocs = <String, Student>{};

  @override
  Future<void> setStudent(Student s) async => studentDocs[s.id] = s;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {}
}

final _head = User(
  id: 'head1',
  name: 'Hana Head',
  email: 'head@example.com',
  role: 'Head',
);
final _admin = User(
  id: 'admin1',
  name: 'Ada Admin',
  email: 'admin@example.com',
  role: 'Admin',
);
final _supervisor = User(
  id: 'sup1',
  name: 'Sid Supervisor',
  email: 'sup@example.com',
  role: 'Supervisor',
);
final _applicant = User(
  id: 'st1',
  name: 'Stu Dent',
  email: 'stu@example.com',
  role: 'Student',
);

/// A Student Assistant from before the date was kept.
final _oldAssistant = User(
  id: 'sa1',
  name: 'Sara Assistant',
  email: 'sara@example.com',
  role: 'Student Assistant',
  saId: 'SA 001',
);
final _oldRecord = Student(
  id: 'sa1',
  name: 'Sara Assistant',
  email: 'sara@example.com',
  department: 'CICS',
  userId: 'sa1',
);

AppState _state(_Store store, User me, {List<User> others = const []}) {
  for (final u in [me, ...others]) {
    store.profiles[u.id] = u;
  }
  return AppState(firestoreService: store)
    ..currentUser = me
    ..users = [me, ...others];
}

void main() {
  group('philippine dates', () {
    test('a saved time reads as the day it was in the Philippines', () {
      // 5 PM UTC on the 10th is 1 AM on the 11th in Manila.
      expect(philippineDayText('2026-11-10T17:00:00.000Z'), 'Nov 11, 2026');
      expect(philippineDayText('2026-11-10T15:59:00.000Z'), 'Nov 10, 2026');
      expect(philippineDayText(null), isNull);
      expect(philippineDayText('not a date'), isNull);
    });

    test('a picked day is saved so that it reads back as that day', () {
      final saved = philippineNoonIso(DateTime(2026, 8, 3));
      expect(saved, '2026-08-03T04:00:00.000Z');
      expect(philippineDayText(saved), 'Aug 3, 2026');
      expect(philippineDayOf(saved), DateTime(2026, 8, 3));
    });
  });

  group('the acceptance date', () {
    test('is saved with the role when the Head accepts a student', () async {
      final store = _Store();
      final state = _state(store, _head, others: [_applicant]);
      final before = DateTime.now().toUtc();

      expect(await state.changeUserRole('st1', 'Student Assistant'), isNull);

      // One write carries both, so the role never lands without the date.
      final write = store.profileFieldWrites.firstWhere(
        (w) => w.fields.containsKey('role'),
      );
      expect(write.fields['role'], 'Student Assistant');
      final saved = DateTime.parse(write.fields['acceptedAt'] as String);
      expect(saved.isUtc, isTrue);
      expect(saved.isBefore(before), isFalse);
      expect(
        state.users.firstWhere((u) => u.id == 'st1').acceptedAt,
        write.fields['acceptedAt'],
      );
      state.dispose();
    });

    test('is saved when the Admin makes someone a Student Assistant', () async {
      final store = _Store();
      final state = _state(store, _admin, others: [_applicant]);

      expect(await state.changeUserRole('st1', 'Student Assistant'), isNull);

      expect(store.profiles['st1']!.acceptedAt, isNotNull);
      state.dispose();
    });

    test('is not touched by any other role change', () async {
      final store = _Store();
      final accepted = User(
        id: 'sa1',
        name: 'Sara Assistant',
        email: 'sara@example.com',
        role: 'Student Assistant',
        acceptedAt: '2026-08-03T04:00:00.000Z',
      );
      final state = _state(store, _admin, others: [accepted]);

      expect(await state.changeUserRole('sa1', 'Student'), isNull);

      expect(
        store.profileFieldWrites.every(
          (w) => !w.fields.containsKey('acceptedAt'),
        ),
        isTrue,
      );
      expect(store.profiles['sa1']!.acceptedAt, '2026-08-03T04:00:00.000Z');
      state.dispose();
    });

    test('an account from before it was kept has none', () {
      final loaded = User.fromJson(_oldAssistant.toJson());
      expect(loaded.acceptedAt, isNull);
      // And saving that profile again doesn't add the field.
      expect(_oldAssistant.toJson().containsKey('acceptedAt'), isFalse);
    });

    test('the Head enters it for an older account', () async {
      final store = _Store();
      final state = _state(store, _head, others: [_oldAssistant]);

      expect(await state.setAcceptedDate('sa1', DateTime(2026, 8, 3)), isNull);

      expect(store.profileFieldWrites.single.fields, {
        'acceptedAt': '2026-08-03T04:00:00.000Z',
      });
      expect(
        philippineDayText(
          state.users.firstWhere((u) => u.id == 'sa1').acceptedAt,
        ),
        'Aug 3, 2026',
      );
      state.dispose();
    });

    test('a Supervisor cannot set it, nor anyone a day to come', () async {
      final store = _Store();
      final asSupervisor = _state(store, _supervisor, others: [_oldAssistant]);
      expect(
        await asSupervisor.setAcceptedDate('sa1', DateTime(2026, 8, 3)),
        isNotNull,
      );
      asSupervisor.dispose();

      final asHead = _state(store, _head, others: [_oldAssistant, _applicant]);
      final tomorrow = asHead.philippineClock().add(const Duration(days: 2));
      expect(
        await asHead.setAcceptedDate('sa1', tomorrow),
        "The date can't be in the future.",
      );
      // Only a Student Assistant has one.
      expect(
        await asHead.setAcceptedDate('st1', DateTime(2026, 8, 3)),
        isNotNull,
      );
      expect(store.profileFieldWrites, isEmpty);
      asHead.dispose();
    });

    test('a save that is refused changes nothing and says so', () async {
      final store = _Store();
      final state = _state(store, _head, others: [_oldAssistant]);
      store.failAccountWrites = true;

      expect(
        await state.setAcceptedDate('sa1', DateTime(2026, 8, 3)),
        "Couldn't save the date. Check your connection and try again.",
      );
      expect(state.users.firstWhere((u) => u.id == 'sa1').acceptedAt, isNull);
      state.dispose();
    });
  });

  group('on screen', () {
    Future<void> open(WidgetTester tester, AppState state, Widget page) async {
      tester.view.physicalSize = const Size(1300, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // The test font draws every glyph as a full square, so some rows
      // overflow here though they fit in the app.
      final onError = FlutterError.onError;
      addTearDown(() => FlutterError.onError = onError);
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(body: page),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the Head sees "Not recorded" and sets the date', (
      tester,
    ) async {
      final store = _Store();
      final state = _state(store, _head, others: [_oldAssistant])
        ..students = [_oldRecord];
      await open(tester, state, const StudentsScreen());

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();

      expect(find.text('Date accepted'), findsOneWidget);
      expect(find.text('Not recorded'), findsOneWidget);

      await tester.tap(find.text('Set date'));
      await tester.pumpAndSettle();
      // The picker opens on today; OK keeps it.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final saved = store.profileFieldWrites.single.fields['acceptedAt'];
      expect(saved, isNotNull);
      expect(find.text('Not recorded'), findsNothing);
      expect(find.text(philippineDayText(saved as String)!), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('a Supervisor sees the date and cannot change it', (
      tester,
    ) async {
      final store = _Store();
      final accepted = User(
        id: 'sa1',
        name: 'Sara Assistant',
        email: 'sara@example.com',
        role: 'Student Assistant',
        acceptedAt: '2026-08-03T04:00:00.000Z',
      );
      final state = _state(store, _supervisor, others: [accepted])
        ..students = [_oldRecord]
        ..offices = [
          const Office(
            id: 'o1',
            name: 'CICS Office',
            code: 'CICS',
            headIds: ['sup1'],
            headNames: ['Sid Supervisor'],
            assistantIds: ['sa1'],
            assistantNames: ['Sara Assistant'],
          ),
        ];
      await open(tester, state, const StudentsScreen());

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();

      expect(find.text('Aug 3, 2026'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      expect(find.text('Set date'), findsNothing);
    });

    testWidgets('a Student Assistant sees it on their profile', (tester) async {
      final store = _Store();
      final me = User(
        id: 'sa1',
        name: 'Sara Assistant',
        email: 'sara@example.com',
        role: 'Student Assistant',
        saId: 'SA 001',
        acceptedAt: '2026-08-03T04:00:00.000Z',
      );
      await open(tester, _state(store, me), const ProfileScreen());

      expect(find.text('STUDENT ASSISTANT SINCE'), findsOneWidget);
      expect(find.text('Aug 3, 2026'), findsOneWidget);
    });
  });
}
