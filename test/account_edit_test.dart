import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/accounts_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

import 'support/account_writes.dart';

/// Remembers every whole profile saved, as it would be written.
class _Store extends FirestoreService with AccountWrites {
  final saved = <Map<String, dynamic>>[];

  @override
  Future<void> setUserProfile(User user) async {
    saved.add(user.toJson());
    profiles[user.id] = user;
  }
}

final _admin = User(
  id: 'a1',
  name: 'Ana Admin',
  firstName: 'Ana',
  lastName: 'Admin',
  email: 'ana@example.com',
  role: 'Admin',
);

User _assistant({String email = 'juan@example.com'}) => User(
  id: 'sa1',
  name: 'Juan Dela Cruz',
  firstName: 'Juan',
  lastName: 'Dela Cruz',
  email: email,
  role: 'Student Assistant',
  phone: '0917 123 4567',
  studentId: '23B0626',
  studentIdVerifiedAt: '2026-11-01T00:00:00Z',
  studentIdVerifiedBy: 'h1',
  courseProgram: 'BSIT',
);

void main() {
  test('a profile\'s phone, Student ID and program can be emptied', () {
    final user = _assistant();
    final cleared = user.copyWith(
      clearPhone: true,
      clearStudentId: true,
      clearCourseProgram: true,
    );
    expect(cleared.phone, isNull);
    expect(cleared.studentId, isNull);
    expect(cleared.courseProgram, isNull);
    // A clear wins over a value passed with it; null alone keeps.
    expect(user.copyWith(phone: '0918', clearPhone: true).phone, isNull);
    expect(user.copyWith().phone, '0917 123 4567');
  });

  group('Edit Account', () {
    Future<_Store> openEdit(WidgetTester tester, User account) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final original = FlutterError.onError;
      // The test font draws every glyph as a full square, so the screen's
      // rows overflow here though they fit in the app.
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
      final store = _Store();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(firestoreService: store)
            ..currentUser = _admin
            ..users = [_admin, account],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: AccountsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final edit = find.byTooltip('Edit account').last;
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      return store;
    }

    Finder field(String label) => find.widgetWithText(TextField, label);

    Future<void> save(WidgetTester tester) async {
      final button = find.text('Save Changes');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('the sign-in email is shown, not editable', (tester) async {
      await openEdit(tester, _assistant());

      final email = tester.widget<TextField>(field('Email'));
      expect(email.readOnly, isTrue);
      expect(email.controller!.text, 'juan@example.com');
      expect(
        find.text("The sign-in email can't be changed here."),
        findsOneWidget,
      );
    });

    testWidgets('a profile saved with no email can still be saved', (
      tester,
    ) async {
      final store = await openEdit(tester, _assistant(email: ''));
      await save(tester);

      expect(find.text('Enter the email address.'), findsNothing);
      expect(store.saved, hasLength(1));
    });

    testWidgets('an emptied phone and Student ID are saved as none', (
      tester,
    ) async {
      final store = await openEdit(tester, _assistant());
      await tester.enterText(field('Phone (optional)'), '');
      await tester.enterText(field('Student ID (optional)'), '');
      await save(tester);

      final json = store.saved.single;
      expect(json['phone'], isNull);
      expect(json['studentId'], isNull);
      // The old ID's check went with it.
      expect(json.containsKey('studentIdVerifiedAt'), isFalse);
      expect(json.containsKey('studentIdVerifiedBy'), isFalse);
    });
  });
}
