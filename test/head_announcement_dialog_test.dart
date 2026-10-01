import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/admin_announcements_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Keeps the announcement the dialog posts instead of writing it.
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

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
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
    await tester.tap(find.text('Post Announcement').first);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('a new announcement starts with no requirements, deadline '
      'or office', (tester) async {
    await openDialog(tester);

    expect(find.text('doc'), findsNothing);
    expect(find.text('docpdf'), findsNothing);
    expect(
      tester.widget<TextField>(field('Deadline')).controller!.text,
      isEmpty,
    );
    expect(find.text('Any office'), findsOneWidget);
  });

  testWidgets('the office chosen is posted with the announcement', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(field('Position Title'), 'Office Aide');
    await tester.enterText(
      field('Description'),
      'Help file records and answer walk-in students.',
    );
    await tester.tap(find.text('Any office'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar').last);
    await tester.pumpAndSettle();

    final post = find.text('Post Announcement').last;
    await tester.ensureVisible(post);
    await tester.tap(post);
    await tester.pumpAndSettle();

    final posted = store.saved.single;
    expect(posted['title'], 'Office Aide');
    expect(posted['officeId'], 'o2');
    expect(posted['officeName'], 'Registrar');
    expect(posted['requirements'], isEmpty);
    expect(posted['deadline'], isNull);
  });
}
