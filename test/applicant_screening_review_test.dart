import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

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
  role: 'Student Assistant',
  studentId: '23B0626',
  courseProgram: 'BSIT',
  yearLevel: '4th Year',
);

final _roni = User(
  id: 's2',
  name: 'Roni Perez',
  email: 'roni@gmail.com',
  role: 'Student Assistant',
  studentId: '23B0627',
  courseProgram: 'BSIT',
  yearLevel: '3rd Year',
);

Application _application(String id, User user) => Application(
  id: id,
  announcementId: 'ann1',
  announcementTitle: 'Hiring',
  applicantId: user.id,
  applicantName: user.name,
  appliedAt: '2026-09-01T00:00:00.000',
  status: 'Approved',
);

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

// Kristel was screened: every skill rated 2, every overall rating 3.
final _kristelRecord = ScreeningRecord(
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
  generalNotes: 'Needs more practice with spreadsheets.',
  academicYear: '2026-2027',
);

void main() {
  Future<void> pumpScreening(WidgetTester tester) async {
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
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState()
          ..currentUser = _head
          ..users = [_head, _kristel, _roni]
          ..applications = [
            _application('app_1', _kristel),
            _application('app_2', _roni),
          ]
          ..screeningRecords = [_kristelRecord]
          ..programs = const [
            Program(
              id: 'p1',
              code: 'BSIT',
              name: 'Bachelor of Science in Information Technology',
              department: 'College of Information and Computing Sciences',
            ),
          ]
          ..offices = const [Office(id: 'o1', name: 'Registrar', code: 'REG')],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: ApplicantScreeningScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> review(WidgetTester tester, int card) async {
    final button = find.text('Review / Edit Assessment').at(card);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    // Opens at once: no profile has to be fetched first.
    await tester.pump();
    expect(
      find.text('INTERVIEW AND ASSESSMENT FORM FOR STUDENT ASSISTANTS'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  }

  String remarksText(WidgetTester tester) => tester
      .widget<TextField>(
        find.widgetWithText(TextField, 'General evaluator remarks'),
      )
      .controller!
      .text;

  testWidgets('a screened application opens with its saved assessment', (
    tester,
  ) async {
    await pumpScreening(tester);
    await review(tester, 0);

    expect(find.text('Avg 2.0'), findsWidgets);
    expect(find.text('Avg 3.0'), findsWidgets);
    expect(find.text('Avg 4.0'), findsNothing);
    expect(remarksText(tester), 'Needs more practice with spreadsheets.');
    // A saved record can be printed straight away.
    expect(find.text('Print Official Form'), findsOneWidget);
  });

  testWidgets('the next applicant starts fresh, from their profile', (
    tester,
  ) async {
    await pumpScreening(tester);
    await review(tester, 0);
    final back = find.text('Back to Applicants');
    await tester.ensureVisible(back);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();

    await review(tester, 1);
    String field(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(field('Full Name'), 'Roni Perez');
    expect(field('Student ID / Applicant #'), '23B0627');
    expect(field('Year Level'), '3rd Year');
    // None of Kristel's ratings or remarks carried over.
    expect(find.text('Avg 4.0'), findsWidgets);
    expect(find.text('Avg 2.0'), findsNothing);
    expect(find.text('Avg 3.0'), findsNothing);
    expect(remarksText(tester), isEmpty);
    expect(find.text('Print Official Form'), findsNothing);
  });
}
