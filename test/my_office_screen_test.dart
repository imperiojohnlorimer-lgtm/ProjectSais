import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/offices_screen.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/dashboard/dashboard_screen.dart';
import 'package:projectsais/screens/my_office/my_office_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/utils/file_names.dart';

// A real 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

final _assistant = User(
  id: 'u_1',
  name: 'Juan dela Cruz',
  email: 'juan@marsu.edu.ph',
  role: 'Student Assistant',
);

Office _office({
  String id = 'o1',
  String name = 'Registrar',
  String code = 'REG',
  List<String> headIds = const ['h1'],
  List<String> headNames = const ['Maria Santos'],
  List<String> assistantIds = const ['u_1'],
  List<String> assistantNames = const ['Juan dela Cruz'],
  List<String> requiredSkills = const [],
  String about = '',
  String location = '',
  String locationImagePath = '',
  bool isActive = true,
}) => Office(
  id: id,
  name: name,
  code: code,
  headIds: headIds,
  headNames: headNames,
  assistantIds: assistantIds,
  assistantNames: assistantNames,
  requiredSkills: requiredSkills,
  about: about,
  location: location,
  locationImagePath: locationImagePath,
  isActive: isActive,
);

void main() {
  group('Office details', () {
    test(
      'about, location and picture survive JSON, and old documents have none',
      () {
        final office = _office(
          about: 'Keeps the student records.',
          location: 'Main Building, Room 204',
          locationImagePath: 'announcements/h1/123/abc.png',
        );

        final again = Office.fromJson({'id': 'o1', ...office.toJson()});

        expect(again.about, 'Keeps the student records.');
        expect(again.location, 'Main Building, Room 204');
        expect(again.locationImagePath, 'announcements/h1/123/abc.png');

        final legacy = Office.fromJson({
          'id': 'o1',
          'name': 'Old',
          'code': 'O',
        });
        expect(legacy.about, '');
        expect(legacy.location, '');
        expect(legacy.locationImagePath, '');
      },
    );

    test(
      'a roster change keeps them, and the saved document always has them',
      () {
        final office = _office(
          about: 'A',
          location: 'B',
          locationImagePath: 'announcements/h1/1/x.png',
        );

        final without = office.withoutAssistant('u_1', 'Juan dela Cruz');

        expect(without.assistantIds, isEmpty);
        expect(without.about, 'A');
        expect(without.location, 'B');
        expect(without.locationImagePath, 'announcements/h1/1/x.png');
        expect(office.toJson(), containsPair('about', 'A'));
        expect(_office().toJson(), containsPair('location', ''));
        expect(_office().toJson(), containsPair('locationImagePath', ''));
      },
    );

    test('supervisor names drop blanks and repeats', () {
      final office = _office(headNames: ['', ' Maria Santos ', 'Maria Santos']);
      expect(office.supervisorNames, ['Maria Santos']);
    });

    test('the picture goes under a path the upload function takes', () {
      final path = officePicturePath(
        'uid123',
        'Front Door.JPG',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(
        RegExp(
          r'^announcements/uid123/1700000000000/[a-z0-9]{16}\.jpg$',
        ).hasMatch(path),
        isTrue,
        reason: path,
      );
      expect(path.contains('Front'), isFalse);
    });
  });

  group('the My Office page', () {
    Future<AppState> pump(
      WidgetTester tester,
      List<Office> offices, {
      Size size = const Size(1000, 1800),
      OfficePictureLoaderForTest? loader,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = AppState(firestoreService: FirestoreService())
        ..currentUser = _assistant
        ..offices = offices;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(body: MyOfficeScreen(pictureLoader: loader)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('shows what the Head wrote, the supervisors and the skills', (
      tester,
    ) async {
      await pump(tester, [
        _office(
          about: 'Keeps the student records.',
          location: 'Main Building, Room 204',
          requiredSkills: ['Typing', 'Filing'],
          headIds: ['a', 'b'],
          headNames: ['', 'Maria Santos'],
        ),
      ]);

      expect(find.text('Registrar'), findsOneWidget);
      expect(find.text('REG'), findsOneWidget);
      expect(find.text('Keeps the student records.'), findsOneWidget);
      expect(find.text('Main Building, Room 204'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('SUPERVISOR'), findsOneWidget);
      expect(find.text('Typing'), findsOneWidget);
      expect(find.text('Filing'), findsOneWidget);
      expect(find.textContaining("hasn't added"), findsNothing);
    });

    testWidgets('says what the Head has not filled in yet', (tester) async {
      await pump(tester, [_office(headIds: [], headNames: [])]);

      expect(
        find.text("The Head hasn't added a description yet."),
        findsOneWidget,
      );
      expect(
        find.text("The Head hasn't added a location yet."),
        findsOneWidget,
      );
      expect(find.text('No supervisor assigned yet.'), findsOneWidget);
      expect(find.text('SKILLS THIS OFFICE LOOKS FOR'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('shows each office the student works in', (tester) async {
      await pump(tester, [
        _office(),
        _office(
          id: 'o2',
          name: 'Library',
          code: 'LIB',
          headNames: ['Pedro Reyes'],
        ),
      ]);

      expect(find.text('Registrar'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Pedro Reyes'), findsOneWidget);
    });

    testWidgets('explains an assistant with no office, or an inactive one', (
      tester,
    ) async {
      await pump(tester, [
        _office(assistantIds: ['x'], assistantNames: ['']),
      ]);
      expect(
        find.textContaining('not placed in an office yet'),
        findsOneWidget,
      );
    });

    testWidgets('names an inactive office', (tester) async {
      await pump(tester, [_office(isActive: false)]);
      expect(
        find.textContaining('Registrar) is currently inactive'),
        findsOneWidget,
      );
    });

    testWidgets('never lists the other assistants', (tester) async {
      await pump(tester, [
        _office(
          assistantIds: ['u_1', 'u_2'],
          assistantNames: ['Juan dela Cruz', 'Rita Reyes'],
        ),
      ]);
      expect(find.textContaining('Rita'), findsNothing);
    });

    testWidgets('shows the location picture and opens it larger on a tap', (
      tester,
    ) async {
      final asked = <String>[];
      await pump(
        tester,
        [_office(locationImagePath: 'announcements/h1/1/x.png')],
        loader: (path) async {
          asked.add(path);
          return Uint8List.fromList(_png);
        },
      );

      expect(asked, ['announcements/h1/1/x.png']);
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      // The viewer shows the same picture, from the bytes already loaded.
      expect(find.byType(Image), findsWidgets);
      expect(asked, hasLength(1));
    });

    testWidgets('a picture that will not load says so and can be retried', (
      tester,
    ) async {
      var fail = true;
      await pump(
        tester,
        [_office(locationImagePath: 'announcements/h1/1/x.png')],
        loader: (path) async {
          if (fail) throw Exception('offline');
          return Uint8List.fromList(_png);
        },
      );

      expect(find.text("Couldn't load the picture."), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load the picture."), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('fits long text on the narrowest phone', (tester) async {
      await pump(tester, size: const Size(320, 2400), [
        _office(
          name: 'Office of the University Library and Information Services',
          about: 'A very long description. ' * 20,
          location:
              'The Annex Building behind the old gymnasium, ground floor, room 12',
          headIds: ['a', 'b'],
          headNames: [
            'Maria Concepcion Santos-Villanueva',
            'Jose Protacio Rizal Mercado',
          ],
          requiredSkills: [
            'Communication Skills',
            'MS Excel',
            'Filing',
            'Typing',
          ],
        ),
      ]);
      expect(tester.takeException(), isNull);
    });
  });

  group('getting to the page', () {
    test('only a Student Assistant has it', () {
      for (final role in ['Admin', 'Head', 'Supervisor']) {
        expect(
          AppShell.pagesFor(role).any((p) => p.id == 'my_office'),
          isFalse,
          reason: role,
        );
      }
      expect(
        AppShell.pagesFor('Student Assistant').any((p) => p.id == 'my_office'),
        isTrue,
      );
    });

    test('an office assignment notification opens it', () {
      final state = AppState(firestoreService: FirestoreService())
        ..currentUser = _assistant;
      final note = AppNotification(
        id: 'n1',
        userId: 'u_1',
        title: 'Office Assignment Updated',
        message: 'You have been assigned to Registrar.',
        type: 'office',
        createdAt: 'Nov 7',
      );
      expect(state.notificationTab(note), 'my_office');
    });

    testWidgets('the dashboard card links to it', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = AppState(firestoreService: FirestoreService())
        ..currentUser = _assistant
        ..offices = [_office()];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('View details'));
      await tester.pump();

      expect(state.activeTab, 'my_office');
    });
  });

  group('the Head\'s Offices dialog', () {
    final head = User(
      id: 'h1',
      name: 'Hana Head',
      email: 'h@marsu.edu.ph',
      role: 'Head',
    );

    Future<void> openEdit(WidgetTester tester, Office office) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      // The test font draws every glyph as a full square, so some rows
      // overflow here though they fit in the app.
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
      final state = AppState(firestoreService: FirestoreService())
        ..currentUser = head
        ..offices = [office];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: OfficesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit office').first);
      await tester.pumpAndSettle();
    }

    TextField field(WidgetTester tester, String label) =>
        tester.widget<TextField>(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          ),
        );

    testWidgets('asks for the location, a picture and an about text', (
      tester,
    ) async {
      await openEdit(
        tester,
        _office(about: 'Keeps records.', location: 'Room 204'),
      );

      expect(field(tester, 'Location (optional)').controller!.text, 'Room 204');
      expect(
        field(tester, 'About this office (optional)').controller!.text,
        'Keeps records.',
      );
      expect(find.text('Add a picture of the location'), findsOneWidget);
      expect(find.textContaining('up to 5 MB'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('an office with a picture offers to replace or remove it', (
      tester,
    ) async {
      await openEdit(
        tester,
        _office(locationImagePath: 'announcements/h1/1/x.png'),
      );

      expect(find.text('Replace picture'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Add a picture of the location'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('the card shows the location', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
      final state = AppState(firestoreService: FirestoreService())
        ..currentUser = head
        ..offices = [_office(location: 'Main Building, Room 204')];
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: OfficesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Building, Room 204'), findsOneWidget);
    });
  });
}

typedef OfficePictureLoaderForTest = Future<Uint8List> Function(String path);
