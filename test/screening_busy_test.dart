import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// A Firestore whose writes wait for the test, then fail. The test makes
/// [gate] itself, so it lives in the test's own clock.
class _Store extends FirestoreService {
  late Completer<void> gate;

  @override
  Future<void> setApplication(Application a) async {
    await gate.future;
    throw Exception('offline');
  }

  @override
  Future<void> setScreeningRecord(ScreeningRecord record) async {
    await gate.future;
    throw Exception('offline');
  }
}

const _skillNames = [
  'Communication Skills',
  'Time Management',
  'Technical Proficiency',
  'Initiative & Problem-Solving',
  'Professionalism & Work Ethic',
  'Adaptability & Learning Ability',
  'Teamwork & Collaboration',
];
const _overallNames = [
  'Suitability for the Role',
  'Enthusiasm & Motivation',
  'Potential for Growth',
  'Overall Impression',
];

final _head = User(
  id: 'h1',
  name: 'John Lori',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);

final _kristel = User(
  id: 's1',
  name: 'Kristel Macutong',
  email: 'kristel@gmail.com',
  role: 'Student',
  studentId: '23B0626',
);

final _waitlisted = Application(
  id: 'app_1',
  announcementId: 'ann1',
  announcementTitle: 'Hiring',
  applicantId: 's1',
  applicantName: 'Kristel Macutong',
  appliedAt: '2026-09-01T00:00:00.000',
  status: 'Waitlisted',
);

final _record = ScreeningRecord(
  id: 'screen-s1-2026-2027',
  applicationId: 'app_1',
  applicantId: 's1',
  fullName: 'Kristel Macutong',
  studentNumber: '23B0626',
  academicProgram: 'BSIT',
  yearLevel: '4th Year',
  permanentAddress: 'Boac',
  presentAddress: 'Boac',
  contactInformation: '0917 123 4567',
  targetOfficeId: 'o1',
  targetOfficeName: 'Registrar',
  skills: {for (final k in _skillNames) k: 2},
  skillNotes: {for (final k in _skillNames) k: ''},
  overall: {for (final k in _overallNames) k: 3},
  overallNotes: {for (final k in _overallNames) k: ''},
  recommendation: 'Recommended with Reservations',
  interviewerName: 'John Lori',
  interviewerDate: '2026-09-02',
  notedByName: 'John Lori',
  notedByTitle: 'Head of Student Assistantship',
  generalNotes: '',
  academicYear: '2026-2027',
);

/// The waiting spinner (the page also draws determinate progress rings).
final spinners = find.byWidgetPredicate(
  (w) => w is CircularProgressIndicator && w.value == null,
);

void main() {
  late _Store store;
  final onError = FlutterError.onError;

  setUp(() => store = _Store());

  Future<void> pumpScreening(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so some rows
    // overflow here though they fit in the app.
    addTearDown(() => FlutterError.onError = onError);
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)
          ..currentUser = _head
          ..users = [_head, _kristel]
          ..applications = [_waitlisted]
          ..screeningRecords = [_record],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: ApplicantScreeningScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('Approve Anyway shows it is approving, then why it failed', (
    tester,
  ) async {
    store.gate = Completer<void>();
    await pumpScreening(tester);
    await tapVisible(tester, find.text('Screening Records (1)'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Approve Anyway'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pump();

    expect(find.text('Approving…'), findsOneWidget);
    expect(spinners, findsOneWidget);

    store.gate.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not approve Kristel'), findsOneWidget);
    expect(find.text('Approve Anyway'), findsOneWidget);
    expect(find.text('Approving…'), findsNothing);
  });

  testWidgets('Save Assessment Record shows it is saving, then why it failed', (
    tester,
  ) async {
    store.gate = Completer<void>();
    await pumpScreening(tester);
    await tapVisible(tester, find.text('Review / Edit Assessment').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'General evaluator remarks'),
      'Needs a second interview.',
    );
    await tapVisible(tester, find.text('Save Assessment Record').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & Waitlist'));
    await tester.pump();

    expect(find.text('Saving…'), findsWidgets);

    store.gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not save the assessment'),
      findsOneWidget,
    );
    expect(find.text('Saving…'), findsNothing);
    // Still on the form, with what was typed.
    expect(find.text('Save Assessment Record'), findsWidgets);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'General evaluator remarks'),
          )
          .controller!
          .text,
      'Needs a second interview.',
    );
  });
}
