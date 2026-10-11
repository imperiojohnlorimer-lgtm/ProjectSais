import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/admin_announcements_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Keeps what the Head's dialogs save instead of writing it.
class _Store extends FirestoreService {
  final saved = <Map<String, dynamic>>[];
  final approved = <String, Map<String, dynamic>>{};
  final savedOffices = <Office>[];

  @override
  Future<void> updateAnnouncement(String id, Map<String, dynamic> data) async =>
      approved[id] = data;

  @override
  Future<void> approveAnnouncementWithOffice(
    String id,
    Map<String, dynamic> data,
    Office office,
  ) async {
    approved[id] = data;
    savedOffices.add(office);
  }

  @override
  Future<DocumentReference> addAnnouncement({
    required String title,
    required String body,
    Map<String, dynamic>? extra,
    String? id,
  }) async {
    saved.add({'title': title, 'body': body, ...?extra});
    return _FakeDocRef(id ?? 'ann${saved.length}');
  }

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {}
}

// ignore: subtype_of_sealed_class
class _FakeDocRef implements DocumentReference<Map<String, dynamic>> {
  _FakeDocRef(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'helen@marsu.edu.ph',
  role: 'Head',
);

void main() {
  late _Store store;

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<Announcement> announcements = const [],
    Size size = const Size(1440, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so some of the
    // screen's rows overflow here though they fit in the app.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);
    addTearDown(() => FlutterError.onError = onError);
    store = _Store();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)
          ..currentUser = _head
          ..users = [_head]
          ..announcements = announcements
          ..offices = const [
            Office(id: 'o1', name: 'CICS Office', code: 'CICS'),
            Office(id: 'o2', name: 'Registrar', code: 'REG'),
          ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: AdminAnnouncementsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(
    WidgetTester tester, [
    Size size = const Size(1440, 1000),
  ]) async {
    await pumpScreen(tester, size: size);
    await tester.tap(find.text('Post Announcement').first);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  for (final (width, size) in [
    (1440, const Size(1440, 1000)),
    (390, const Size(390, 844)),
  ]) {
    testWidgets('a new hiring call asks for no office or slots at ${width}px', (
      tester,
    ) async {
      await openDialog(tester, size);

      expect(find.text('Hiring call'), findsOneWidget);
      expect(find.text('Notice'), findsOneWidget);
      expect(find.text('Last day to apply'), findsOneWidget);
      expect(find.text('No deadline'), findsOneWidget);
      expect(find.text('doc'), findsNothing);
      expect(find.text('docpdf'), findsNothing);
      // Students apply to be a Student Assistant, never to one office, and
      // aren't hired for a number of places.
      expect(find.text('Any office'), findsNothing);
      expect(find.text('Available Slots'), findsNothing);
      expect(find.text('Position Title'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing details are shown on the form', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Post Hiring Call'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a title of at least 3 characters.'),
      findsOneWidget,
    );
    expect(find.text('Write at least 10 characters.'), findsOneWidget);
    expect(store.saved, isEmpty);
  });

  testWidgets('a hiring call is posted with its requirements and no slots', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(field('Title'), 'Student Assistant Hiring');
    await tester.enterText(
      field('Description'),
      'Apply to be a Student Assistant for the first semester.',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Certificate of Registration'),
      'Certificate of Registration',
    );
    for (final target in [
      find.text('PDF'),
      find.byTooltip('Add requirement'),
    ]) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    expect(find.text('Certificate of Registration (PDF)'), findsOneWidget);

    final post = find.text('Post Hiring Call');
    await tester.ensureVisible(post);
    await tester.tap(post);
    await tester.pumpAndSettle();

    final posted = store.saved.single;
    expect(posted['title'], 'Student Assistant Hiring');
    expect(posted['acceptsApplications'], isTrue);
    expect(posted['requirements'], ['Certificate of Registration::pdf']);
    expect(posted['slots'], isNull);
    expect(posted['officeId'], isNull);
    expect(posted['deadline'], isNull);
  });

  testWidgets('a long requirement fits on a phone', (tester) async {
    await openDialog(tester, const Size(390, 844));

    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Certificate of Registration'),
      'Certificate of Registration for the First Semester of the Year',
    );
    final add = find.byTooltip('Add requirement');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a notice takes no applications, deadline or requirements', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.text('Notice'));
    await tester.pumpAndSettle();
    expect(find.text('Last day to apply'), findsNothing);

    await tester.enterText(field('Title'), 'Orientation');
    await tester.enterText(
      field('Description'),
      'Orientation for new Student Assistants on Monday.',
    );
    await tester.tap(find.text('Post Notice'));
    await tester.pumpAndSettle();

    final posted = store.saved.single;
    expect(posted['acceptsApplications'], isFalse);
    expect(posted['requirements'], isEmpty);
    expect(posted['deadline'], isNull);
  });

  testWidgets('approving a request for an office not on file creates it', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      announcements: [
        Announcement(
          id: 'req1',
          title: 'Office Aide',
          body: 'Help with records.',
          postedBy: 'Sara Supervisor',
          postedByRole: 'Supervisor',
          postedById: 'sup1',
          postedAt: '10/1/2026',
          slots: '2',
          skills: const ['Web Developer'],
          officeName: 'Guidance Office',
          approvalStatus: 'Pending',
          isOpen: false,
        ),
      ],
    );

    final approve = find.widgetWithText(InkWell, 'Approve').first;
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();

    expect(find.text('New office'), findsOneWidget);
    expect(
      find.text(
        'Creates "Guidance Office" with Sara Supervisor as its '
        'supervisor',
      ),
      findsOneWidget,
    );
    final code = find.widgetWithText(TextField, 'Office code');
    expect(tester.widget<TextField>(code).controller!.text, 'GO');
    await tester.enterText(code, 'GUID');
    await tester.tap(find.text('Approve & Create Office'));
    await tester.pumpAndSettle();

    final office = store.savedOffices.single;
    expect(office.name, 'Guidance Office');
    expect(office.code, 'GUID');
    expect(office.headIds, ['sup1']);
    expect(office.capacity, 2);
    expect(office.requiredSkills, ['Web Developer']);
    expect(store.approved['req1']!['officeId'], office.id);
  });
}
