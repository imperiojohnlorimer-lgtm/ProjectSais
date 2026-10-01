import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/supervisor/sv_announcements_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Keeps the announcement the dialog saves instead of writing it.
class _Store extends FirestoreService {
  final saved = <Map<String, dynamic>>[];

  @override
  Future<DocumentReference> addAnnouncement({
    required String title,
    required String body,
    Map<String, dynamic>? extra,
    String? id,
  }) async {
    saved.add({'title': title, 'body': body, ...?extra});
    return _FakeDocRef('req${saved.length}');
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

final _supervisor = User(
  id: 'sup1',
  name: 'Sara Supervisor',
  email: 'sara@marsu.edu.ph',
  role: 'Supervisor',
);
final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'helen@marsu.edu.ph',
  role: 'Head',
);

void main() {
  late _Store store;

  Future<void> openDialog(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    store = _Store();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)
          ..currentUser = _supervisor
          ..users = [_head, _supervisor]
          ..skills = ['Data encoding', 'Web Developer']
          ..offices = const [
            Office(
              id: 'o1',
              name: 'CICS Office',
              code: 'CICS',
              headIds: ['sup1'],
              headNames: ['Sara Supervisor'],
            ),
          ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: SvAnnouncementsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Request'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  for (final size in const [Size(1440, 1000), Size(390, 900)]) {
    final width = size.width.toInt();

    testWidgets('a request is laid out like the Head\'s announcement '
        'at ${width}px', (tester) async {
      await openDialog(tester, size);

      expect(tester.takeException(), isNull);
      for (final section in [
        'BASIC INFORMATION',
        'OFFICE & SCHEDULE',
        'NEEDED SKILLS',
        'REQUIREMENTS',
        'ATTACHMENT',
      ]) {
        expect(find.text(section), findsOneWidget);
      }
      // The supervisor's only office is chosen for them.
      expect(find.text('CICS Office'), findsOneWidget);
    });

    testWidgets('missing details are shown on the form at ${width}px', (
      tester,
    ) async {
      await openDialog(tester, size);

      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a position title.'), findsOneWidget);
      expect(
        find.text('Say what the student assistant will do.'),
        findsOneWidget,
      );
      expect(store.saved, isEmpty);
      expect(tester.takeException(), isNull);

      // Typing clears that field's message.
      await tester.enterText(field('Position Title'), 'Office Aide');
      await tester.pump();
      expect(find.text('Enter a position title.'), findsNothing);
    });
  }

  testWidgets('a complete request is sent to the Head', (tester) async {
    await openDialog(tester, const Size(1440, 1000));

    await tester.enterText(field('Position Title'), 'Office Aide');
    await tester.enterText(
      field('Description / Reason'),
      'Help file records and answer walk-in students.',
    );
    await tester.enterText(field('Available Slots'), '2');
    final skill = find.text('Web Developer');
    await tester.ensureVisible(skill);
    await tester.pumpAndSettle();
    await tester.tap(skill);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Add requirement (press Enter)'),
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

    await tester.ensureVisible(find.text('Submit Request'));
    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    final request = store.saved.single;
    expect(request['title'], 'Office Aide');
    expect(request['approvalStatus'], 'Pending');
    expect(request['isOpen'], false);
    expect(request['postedByRole'], 'Supervisor');
    expect(request['officeId'], 'o1');
    expect(request['officeName'], 'CICS Office');
    expect(request['slots'], '2');
    expect(request['requirements'], ['Certificate of Registration::pdf']);
    expect(request['skills'], ['Web Developer']);
    expect(request['acceptsApplications'], true);
    expect(request['academicYear'], isNotNull);
    // Sent: the dialog closed.
    expect(find.text('BASIC INFORMATION'), findsNothing);
    expect(
      find.text(
        'Request sent. The Head will review it before students see it.',
      ),
      findsOneWidget,
    );
  });
}
