import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/student_portal/announcements_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

final _student = User(
  id: 'stu1',
  name: 'Sam Student',
  email: 'sam@marsu.edu.ph',
  role: 'Student',
);

Announcement _request({
  String id = 'req1',
  String? office = 'Library',
  String? officeId,
  List<String> skills = const ['Typing'],
  String approvalStatus = 'Approved',
  bool isOpen = true,
  String? academicYear,
}) => Announcement(
  id: id,
  title: 'Aide for ${office ?? 'nobody'}',
  body: 'Help wanted.',
  postedBy: 'Sid Supervisor',
  postedByRole: 'Supervisor',
  postedById: 'sup1',
  postedAt: '10/1/2026',
  officeName: office,
  officeId: officeId,
  skills: skills,
  approvalStatus: approvalStatus,
  isOpen: isOpen,
  academicYear: academicYear,
  acceptsApplications: false,
);

Announcement _call() => Announcement(
  id: 'call1',
  title: 'Student Assistant Hiring',
  body: 'Apply to be a Student Assistant.',
  postedBy: 'Helen Head',
  postedAt: '10/1/2026',
  requirements: const ['Resume::pdf'],
);

Office _office(String id, String name, {bool isActive = true}) =>
    Office(id: id, name: name, code: id.toUpperCase(), isActive: isActive);

void main() {
  late AppState state;

  setUp(() {
    state = AppState(firestoreService: FirestoreService())
      ..currentUser = _student
      ..users = [_student];
  });

  group('offices needing assistants', () {
    test('merge one office\'s requests, skills once each, sorted', () {
      state.announcements = [
        _request(id: 'a', office: 'Library', skills: ['Typing', 'Filing']),
        _request(
          id: 'b',
          office: ' library ',
          skills: ['typing', 'Cashiering'],
        ),
        _request(id: 'c', office: 'Accounting', skills: []),
      ];

      final offices = state.officesNeedingAssistants;

      expect(offices.map((o) => o.office), ['Accounting', 'Library']);
      expect(offices.first.skills, isEmpty);
      expect(offices.last.skills, ['Cashiering', 'Filing', 'Typing']);
    });

    test('leave out requests that are not approved, open, this year, or '
        'name no office', () {
      state.announcements = [
        _request(id: 'pending', office: 'A', approvalStatus: 'Pending'),
        _request(id: 'rejected', office: 'B', approvalStatus: 'Rejected'),
        _request(id: 'closed', office: 'C', isOpen: false),
        _request(id: 'old', office: 'D', academicYear: '2001-2002'),
        _request(id: 'none', office: null),
        _request(id: 'blank', office: '  '),
        _request(id: 'ok', office: 'Registrar'),
      ];

      expect(state.officesNeedingAssistants.map((o) => o.office), [
        'Registrar',
      ]);
    });

    test('use the office\'s current name and skip a deactivated one', () {
      state
        ..offices = [
          _office('lib', 'University Library'),
          _office('old', 'Closed Office', isActive: false),
        ]
        ..announcements = [
          _request(id: 'a', office: 'Library', officeId: 'lib'),
          _request(id: 'b', office: 'LIBRARY', officeId: 'lib', skills: ['X']),
          _request(id: 'c', office: 'Closed Office', officeId: 'old'),
        ];

      final offices = state.officesNeedingAssistants;

      expect(offices, hasLength(1));
      expect(offices.single.office, 'University Library');
      expect(offices.single.skills, ['Typing', 'X']);
    });
  });

  group('the Apply card', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // The test font draws every glyph as a full square, so some rows
      // overflow here though they fit in the app.
      final onError = FlutterError.onError;
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      addTearDown(() => FlutterError.onError = onError);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: AnnouncementsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists the offices and their skills, nothing else of the '
        'request', (tester) async {
      state.announcements = [
        _call(),
        _request(office: 'Library', skills: ['Typing', 'Filing']),
      ];

      await pump(tester, const Size(390, 900));

      expect(find.text('OFFICES THAT NEED STUDENT ASSISTANTS'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Typing'), findsOneWidget);
      expect(find.text('Filing'), findsOneWidget);
      expect(find.text('Sid Supervisor'), findsNothing);
      expect(find.text('Aide for Library'), findsNothing);
      expect(find.textContaining('These offices have asked'), findsOneWidget);
      expect(find.text('Apply Now'), findsOneWidget);
    });

    testWidgets('are left out when no office asked, and the old wording '
        'stays', (tester) async {
      state.announcements = [_call()];

      await pump(tester, const Size(390, 900));

      expect(find.text('OFFICES THAT NEED STUDENT ASSISTANTS'), findsNothing);
      expect(find.textContaining('what the offices need'), findsOneWidget);
    });

    testWidgets('still show when applying is closed', (tester) async {
      state.announcements = [_request(office: 'Registrar')];

      await pump(tester, const Size(390, 900));

      expect(find.textContaining("Applications aren't open yet"), findsWidgets);
      expect(find.text('Registrar'), findsOneWidget);
    });

    testWidgets('cap skills at four and fold offices past four', (
      tester,
    ) async {
      state.announcements = [
        _call(),
        _request(
          id: 'a',
          office: 'Alpha',
          skills: ['S1', 'S2', 'S3', 'S4', 'S5', 'S6'],
        ),
        for (final name in ['Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta'])
          _request(id: name, office: name, skills: []),
      ];

      await pump(tester, const Size(390, 1600));

      expect(find.text('+2'), findsOneWidget);
      expect(find.text('S5'), findsNothing);
      expect(find.text('Gamma'), findsNothing);
      expect(find.text('Show 2 more'), findsOneWidget);

      await tester.ensureVisible(find.text('Show 2 more'));
      await tester.tap(find.text('Show 2 more'));
      await tester.pumpAndSettle();

      expect(find.text('Gamma'), findsOneWidget);
      expect(find.text('Zeta'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });
  });
}
