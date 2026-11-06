import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/navigation/app_router.dart';
import 'package:projectsais/screens/accounts/staff_requests_screen.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/auth/register_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/staff_request_banner.dart';

User _request(
  String id,
  String name, {
  String requested = 'Supervisor',
  String status = 'Pending',
}) => User(
  id: id,
  name: name,
  email: '$id@gmail.com',
  role: 'Student',
  status: status,
  requestedRole: requested,
  department: 'College of Engineering',
  campus: 'Boac Campus',
  phone: '0917 123 4567',
);

User _staff(String role) =>
    User(id: 'u_$role', name: '$role Person', email: '$role@x.y', role: role);

/// Records what registration would save, with no Firebase.
class _RecordingState extends AppState {
  User? registered;
  String? password;

  @override
  Future<String?> registerWithEmail(User user, String password) async {
    registered = user;
    this.password = password;
    return null;
  }
}

class _Store extends FirestoreService {
  final updates = <String, Map<String, dynamic>>{};
  bool fail = false;

  @override
  Future<void> updateUserFields(String id, Map<String, dynamic> fields) async {
    if (fail) throw Exception('offline');
    updates[id] = fields;
  }
}

AppState _headState(_Store store, List<User> users) =>
    AppState(firestoreService: store)
      ..currentUser = _staff('Head')
      ..users = [_staff('Head'), ...users];

void main() {
  group('User', () {
    test('keeps the role a sign-up asks for, and leaves it off otherwise', () {
      final request = _request('p1', 'Pat');
      expect(request.toJson()['requestedRole'], 'Supervisor');
      expect(User.fromJson(request.toJson()).requestedRole, 'Supervisor');
      expect(_staff('Head').toJson().containsKey('requestedRole'), isFalse);
      // copyWith keeps it, and can clear it.
      expect(request.copyWith(phone: '1').requestedRole, 'Supervisor');
      expect(request.copyWith(clearRequestedRole: true).requestedRole, isNull);
    });
  });

  group('signing in', () {
    test(
      'a waiting or declined staff account is blocked, with its own words',
      () {
        expect(AppState.blocksSignIn('Pending'), isTrue);
        expect(AppState.blocksSignIn('Declined'), isTrue);
        expect(AppState.blocksSignIn('Archived'), isTrue);
        expect(AppState.blocksSignIn('Active'), isFalse);
        expect(AppState.signInBlockedMessage('Pending'), contains('approval'));
        expect(
          AppState.signInBlockedMessage('Declined'),
          contains('not approved'),
        );
        expect(
          AppState.signInBlockedMessage('Archived'),
          contains('deactivated'),
        );
      },
    );
  });

  group('AppState staff requests', () {
    test('lists only waiting requests for the roles that may be asked', () {
      final state = _headState(_Store(), [
        _request('b', 'Bea'),
        _request('a', 'Ana', requested: 'Head'),
        _request('c', 'Cy', requested: 'Admin'),
        _request('d', 'Di', status: 'Declined'),
        _request('e', 'Eli', status: 'Active'),
        _staff('Supervisor'),
      ]);
      expect(state.staffRequests.map((u) => u.name), ['Ana', 'Bea']);
      expect(state.staffRequestCount, 2);
    });

    test('approving saves the role, then shows it', () async {
      final store = _Store();
      final pat = _request('p1', 'Pat');
      final state = _headState(store, [pat]);
      expect(await state.approveStaffRequest(pat), isNull);
      final saved = store.updates['p1']!;
      expect(saved['role'], 'Supervisor');
      expect(saved['status'], 'Active');
      expect(saved['requestedRole'], isA<FieldValue>());
      final now = state.users.firstWhere((u) => u.id == 'p1');
      expect(now.role, 'Supervisor');
      expect(now.status, 'Active');
      expect(now.requestedRole, isNull);
      expect(state.staffRequestCount, 0);
    });

    test('approving a Head request gives the Head role', () async {
      final store = _Store();
      final lee = _request('p2', 'Lee', requested: 'Head');
      final state = _headState(store, [lee]);
      await state.approveStaffRequest(lee);
      expect(store.updates['p2']!['role'], 'Head');
    });

    test('declining only marks the account', () async {
      final store = _Store();
      final pat = _request('p1', 'Pat');
      final state = _headState(store, [pat]);
      expect(await state.declineStaffRequest(pat), isNull);
      expect(store.updates['p1'], {'status': 'Declined'});
      expect(state.users.firstWhere((u) => u.id == 'p1').status, 'Declined');
      expect(state.staffRequestCount, 0);
    });

    test('a failed save leaves the request waiting and says so', () async {
      final store = _Store()..fail = true;
      final pat = _request('p1', 'Pat');
      final state = _headState(store, [pat]);
      expect(
        await state.approveStaffRequest(pat),
        contains("Couldn't approve"),
      );
      expect(
        await state.declineStaffRequest(pat),
        contains("Couldn't decline"),
      );
      expect(state.staffRequestCount, 1);
      expect(state.users.firstWhere((u) => u.id == 'p1').status, 'Pending');
    });

    test('nobody but a Head (or the Admin) decides', () async {
      for (final role in ['Supervisor', 'Student Assistant', 'Student']) {
        final store = _Store();
        final pat = _request('p1', 'Pat');
        final state = AppState(firestoreService: store)
          ..currentUser = _staff(role)
          ..users = [pat];
        expect(await state.approveStaffRequest(pat), isNotNull, reason: role);
        expect(await state.declineStaffRequest(pat), isNotNull, reason: role);
        expect(store.updates, isEmpty, reason: role);
      }
    });

    test('a request already decided cannot be approved again', () async {
      final store = _Store();
      final done = _request('p1', 'Pat', status: 'Declined');
      final state = _headState(store, [done]);
      expect(await state.approveStaffRequest(done), isNotNull);
      expect(store.updates, isEmpty);
    });
  });

  group('the Staff Requests page', () {
    Future<void> pump(
      WidgetTester tester,
      AppState state, {
      double width = 1300,
      Widget screen = const StaffRequestsScreen(),
    }) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(body: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says when nobody is waiting', (tester) async {
      await pump(tester, _headState(_Store(), []));
      expect(find.text('No staff sign-ups are waiting.'), findsOneWidget);
    });

    testWidgets('shows each request with its role and details', (tester) async {
      await pump(
        tester,
        _headState(_Store(), [
          _request('a', 'Ana Reyes'),
          _request('b', 'Ben Cruz', requested: 'Head'),
        ]),
      );
      expect(find.text('2 waiting for approval'), findsOneWidget);
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsOneWidget);
      expect(find.text('Supervisor'), findsOneWidget);
      expect(find.text('Head, Student Assistantship'), findsOneWidget);
      expect(find.text('a@gmail.com'), findsOneWidget);
      expect(find.text('Approve'), findsNWidgets(2));
      expect(find.text('Decline'), findsNWidgets(2));
    });

    testWidgets('approving asks first, then saves and removes the card', (
      tester,
    ) async {
      final store = _Store();
      final state = _headState(store, [_request('a', 'Ana Reyes')]);
      await pump(tester, state);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Approve Ana Reyes?'), findsOneWidget);
      // Cancel changes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.updates, isEmpty);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Approve'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.updates['a']!['role'], 'Supervisor');
      expect(find.text('No staff sign-ups are waiting.'), findsOneWidget);
    });

    testWidgets('declining asks first, then closes the request', (
      tester,
    ) async {
      final store = _Store();
      final state = _headState(store, [_request('a', 'Ana Reyes')]);
      await pump(tester, state);
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(find.text('Decline Ana Reyes?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Decline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.updates['a'], {'status': 'Declined'});
      expect(find.text('No staff sign-ups are waiting.'), findsOneWidget);
    });

    testWidgets('a failed approval keeps the card and says why', (
      tester,
    ) async {
      final store = _Store()..fail = true;
      await pump(tester, _headState(store, [_request('a', 'Ana Reyes')]));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Approve'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't approve Ana Reyes. Please try again."),
        findsOneWidget,
      );
      expect(find.text('Ana Reyes'), findsOneWidget);
    });

    for (final width in [320.0, 390.0, 700.0, 1400.0]) {
      testWidgets('fits ${width.toInt()} px with a long name', (tester) async {
        await pump(
          tester,
          _headState(_Store(), [
            _request(
              'a',
              'Maria Guadalupe Hernandez-Villanueva de la Cruz Santos',
            ),
            _request('b', 'Ben Cruz', requested: 'Head'),
          ]),
          width: width,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the Head\'s banner and sidebar', () {
    testWidgets('the banner counts the requests and opens the page', (
      tester,
    ) async {
      final state = _headState(_Store(), [
        _request('a', 'Ana'),
        _request('b', 'Ben'),
      ]);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: StaffRequestBanner()),
          ),
        ),
      );
      expect(
        find.text('2 staff sign-ups are waiting for your approval.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Review'));
      await tester.pump();
      expect(state.activeTab, 'staff_requests');
      // On the page itself it says nothing.
      expect(find.text('Review'), findsNothing);
    });

    testWidgets('the banner is silent with nobody waiting', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: _headState(_Store(), []),
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: StaffRequestBanner()),
          ),
        ),
      );
      expect(find.text('Review'), findsNothing);
    });

    test('Staff Requests is the Head\'s page, at /staff-requests', () {
      expect(
        AppShell.pagesFor('Head').any((p) => p.id == 'staff_requests'),
        isTrue,
      );
      for (final role in [
        'Admin',
        'Supervisor',
        'Student Assistant',
        'Student',
      ]) {
        expect(
          AppShell.pagesFor(role).any((p) => p.id == 'staff_requests'),
          isFalse,
          reason: role,
        );
        expect(AppRoutes.tabAt(role, '/staff-requests'), isNull, reason: role);
      }
      expect(AppRoutes.pathFor('Head', 'staff_requests'), '/staff-requests');
      expect(AppRoutes.tabAt('Head', '/staff-requests'), 'staff_requests');
    });
  });

  group('the Register page', () {
    late _RecordingState state;

    Future<void> pump(WidgetTester tester, {double width = 1300}) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      state = _RecordingState();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: RegisterScreen(onBackToLogin: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Pat');
      await tester.enterText(fields.at(2), 'Pending');
      await tester.enterText(fields.at(3), 'pat@gmail.com');
      await tester.enterText(fields.at(4), 'Zq7!kdLm92');
      await tester.enterText(fields.at(5), '09171234567');
      await tester.pump();
    }

    Future<void> staffMode(WidgetTester tester) async {
      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts as the student form, with the switch', (tester) async {
      await pump(tester);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('STUDENT DETAILS'), findsOneWidget);
      expect(find.text('Student ID'), findsOneWidget);
      expect(find.text('STAFF DETAILS'), findsNothing);
    });

    testWidgets('the Staff form swaps in the staff details', (tester) async {
      await pump(tester);
      await staffMode(tester);
      expect(find.text('Staff registration'), findsOneWidget);
      expect(find.text('Create your account'), findsNothing);
      expect(find.text('STAFF DETAILS'), findsOneWidget);
      expect(find.text('STUDENT DETAILS'), findsNothing);
      for (final label in ['Role', 'Phone number', 'Department', 'Campus']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['Student ID', 'Course/Program', 'Year level']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(
        find.textContaining('has to approve a staff account'),
        findsOneWidget,
      );
    });

    testWidgets('switching keeps what was typed, and back restores students', (
      tester,
    ) async {
      await pump(tester);
      await fill(tester);
      await staffMode(tester);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        'Pat',
      );
      await tester.tap(find.text('Student'));
      await tester.pumpAndSettle();
      expect(find.text('Student ID'), findsOneWidget);
      expect(find.text('STAFF DETAILS'), findsNothing);
    });

    testWidgets(
      'a staff sign-up asks for the role, Pending, with the consent',
      (tester) async {
        await pump(tester);
        await fill(tester);
        await staffMode(tester);
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.ensureVisible(find.text('Create Account'));
        await tester.tap(find.text('Create Account'));
        await tester.pumpAndSettle();
        final user = state.registered!;
        // A powerless Student profile that only asks for the role.
        expect(user.role, 'Student');
        expect(user.status, 'Pending');
        expect(user.requestedRole, 'Supervisor');
        expect(user.studentId, isNull);
        expect(user.courseProgram, isNull);
        expect(user.yearLevel, isNull);
        expect(user.phone, '0917 123 4567');
        expect(user.department, isNotEmpty);
        expect(user.campus, isNotEmpty);
        expect(user.consentAt, isNotNull);
        expect(user.consentVersion, isNotNull);
        expect(state.password, 'Zq7!kdLm92');
      },
    );

    testWidgets('the Head role can be asked for', (tester) async {
      await pump(tester);
      await fill(tester);
      await staffMode(tester);
      await tester.tap(find.text('Supervisor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Head, Student Assistantship').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(state.registered!.requestedRole, 'Head');
      expect(state.registered!.role, 'Student');
    });

    testWidgets('a student sign-up is unchanged: Active, no requested role', (
      tester,
    ) async {
      await pump(tester);
      await fill(tester);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      final user = state.registered!;
      expect(user.role, 'Student');
      expect(user.status, 'Active');
      expect(user.requestedRole, isNull);
    });

    testWidgets('staff still must accept the notice and fill the form', (
      tester,
    ) async {
      await pump(tester);
      await staffMode(tester);
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      expect(find.text('Please fill in all required fields.'), findsOneWidget);
      await fill(tester);
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      expect(
        find.text(
          'Please read and accept the Privacy Notice to create an account.',
        ),
        findsOneWidget,
      );
      expect(state.registered, isNull);
    });

    for (final width in [320.0, 390.0, 900.0, 1400.0]) {
      testWidgets('the staff form fits ${width.toInt()} px', (tester) async {
        await pump(tester, width: width);
        await staffMode(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
