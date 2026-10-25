import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/screens/student_portal/announcements_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';

import 'support/account_writes.dart';

/// Keeps the writes the application flow makes instead of sending them.
class _Store extends FirestoreService with AccountWrites {
  final applications = <String, Application>{};
  final notifications = <Map<String, dynamic>>[];
  final students = <Student>[];
  final skills = <String>[];
  List<String> headIds = ['head1'];

  @override
  Future<void> setApplication(Application a) async => applications[a.id] = a;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);

  @override
  Future<List<String>> getHeadIds() async => headIds;

  @override
  Future<void> setUserProfile(User user) async => profiles[user.id] = user;

  @override
  Future<void> setStudent(Student student) async => students.add(student);

  @override
  Future<void> setSkill(String name) async => skills.add(name);

  List<Map<String, dynamic>> sentTo(String userId) =>
      notifications.where((n) => n['userId'] == userId).toList();
}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);
final _student = User(
  id: 'stu1',
  name: 'Sam Student',
  email: 'sam@marsu.edu.ph',
  role: 'Student',
  department: 'CICS',
);
final _student2 = User(
  id: 'stu2',
  name: 'Rita Reyes',
  email: 'rita@marsu.edu.ph',
  role: 'Student',
  department: 'CICS',
);

Announcement _call({
  String id = 'call1',
  bool isOpen = true,
  String? deadline,
  List<String> requirements = const ['Resume::pdf'],
}) => Announcement(
  id: id,
  title: 'Student Assistant Hiring, 1st Semester',
  body: 'Apply to be a Student Assistant.',
  postedBy: 'Helen Head',
  postedAt: '10/1/2026',
  isOpen: isOpen,
  deadline: deadline,
  requirements: requirements,
);

Announcement _request({
  String id = 'req1',
  String office = 'Library',
  List<String> skills = const ['Typing', 'MS Excel', 'Filing'],
  String approvalStatus = 'Approved',
  bool isOpen = true,
}) => Announcement(
  id: id,
  title: '$office Aide',
  body: 'Help at the $office.',
  postedBy: 'Sid Supervisor',
  postedByRole: 'Supervisor',
  postedById: 'sup1',
  postedAt: '10/1/2026',
  officeName: office,
  skills: skills,
  approvalStatus: approvalStatus,
  isOpen: isOpen,
  acceptsApplications: false,
);

Application _application(
  User user, {
  List<String> skills = const [],
  String status = Application.pending,
  String year = '2026-2027',
}) => Application(
  id: Application.idFor(user.id, year),
  announcementId: 'call1',
  announcementTitle: Application.generalTitle,
  applicantId: user.id,
  applicantName: user.name,
  appliedAt: 'Oct 2, 2026',
  status: status,
  skills: skills,
  academicYear: year,
);

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store()
      ..profiles[_student.id] = _student
      ..profiles[_student2.id] = _student2;
    state = AppState(firestoreService: store);
  });

  group('the hiring call', () {
    test('is the Head\'s newest one, never a supervisor\'s request', () {
      state.announcements = [
        _request(id: 'req-new'),
        _call(id: 'call-new'),
        _call(id: 'call-old'),
      ];

      expect(state.currentHiringCall?.id, 'call-new');
      expect(state.studentVisibleAnnouncements.map((a) => a.id), [
        'call-new',
        'call-old',
      ]);
    });

    test('closing it closes applications; an older one doesn\'t take over', () {
      state.announcements = [_call(id: 'call-new', isOpen: false), _call()];

      expect(state.currentHiringCall?.id, 'call-new');
      expect(
        state.hiringCallTakesApplications(state.currentHiringCall),
        isFalse,
      );
    });

    test('students read the Head\'s other announcements, not requests', () {
      final memo = Announcement(
        id: 'memo1',
        title: 'Orientation',
        body: 'See you Monday.',
        postedBy: 'Helen Head',
        postedAt: '10/1/2026',
        acceptsApplications: false,
      );
      state.announcements = [_request(), memo, _call()];

      expect(state.studentNotices.map((a) => a.id), ['memo1']);
    });
  });

  group('applying', () {
    setUp(() {
      state
        ..currentUser = _student
        ..users = [_student]
        ..announcements = [_call()];
    });

    test('saves one general application under the year\'s id', () async {
      final ok = await state.submitApplication(
        _application(_student, skills: ['Typing']),
      );

      expect(ok, isTrue);
      final saved = store.applications.values.single;
      expect(saved.id, 'app_stu1_2026-2027');
      expect(saved.announcementTitle, 'Student Assistant');
      expect(saved.status, Application.pending);
      expect(state.myCurrentApplication?.id, saved.id);
      expect(
        store.sentTo('head1').single['message'],
        'Sam Student applied to be a Student Assistant.',
      );
    });

    test('a second application the same year is refused', () async {
      expect(await state.submitApplication(_application(_student)), isTrue);
      expect(await state.submitApplication(_application(_student)), isFalse);
      expect(store.applications, hasLength(1));
    });

    test('is refused once the call is closed, replaced or past its '
        'deadline', () async {
      state.announcements = [_call(isOpen: false)];
      expect(await state.submitApplication(_application(_student)), isFalse);

      state.announcements = [_call(id: 'call2'), _call()];
      expect(await state.submitApplication(_application(_student)), isFalse);

      state.announcements = [_call(deadline: 'Jan 5, 2020')];
      expect(await state.submitApplication(_application(_student)), isFalse);

      state.announcements = [];
      expect(await state.submitApplication(_application(_student)), isFalse);
      expect(store.applications, isEmpty);
    });
  });

  test('with only older applications, the newest by date is shown', () {
    final older = Application(
      id: 'app_1759000000000',
      announcementId: 'lib-post',
      announcementTitle: 'Library Aide',
      applicantId: 'stu1',
      applicantName: 'Sam Student',
      appliedAt: 'Sep 30, 2026',
      status: Application.rejected,
      academicYear: '2026-2027',
    );
    final newer = Application(
      id: 'app_1759400000000',
      announcementId: 'reg-post',
      announcementTitle: 'Registrar Aide',
      applicantId: 'stu1',
      applicantName: 'Sam Student',
      appliedAt: 'Oct 2, 2026',
      status: Application.approved,
      academicYear: '2026-2027',
    );
    state
      ..currentUser = _student
      // The live list orders them by their dates as text, newest-looking
      // first: "Sep 30" before "Oct 2".
      ..applications = [older, newer];

    expect(state.myCurrentApplication?.id, newer.id);
  });

  test(
    'an older rejected application replaced by a new one is off the list',
    () {
      final old = Application(
        id: 'app_1759000000000',
        announcementId: 'lib-post',
        announcementTitle: 'Library Aide',
        applicantId: 'stu1',
        applicantName: 'Sam Student',
        appliedAt: 'Sep 30, 2026',
        status: Application.rejected,
        academicYear: '2026-2027',
      );
      final other = Application(
        id: 'app_1759000000001',
        announcementId: 'reg-post',
        announcementTitle: 'Registrar Aide',
        applicantId: 'stu2',
        applicantName: 'Rita Reyes',
        appliedAt: 'Sep 30, 2026',
        status: Application.rejected,
        academicYear: '2026-2027',
      );
      state.applications = [_application(_student), old, other];

      expect(state.currentApplications.map((a) => a.id), [
        'app_stu1_2026-2027',
        'app_1759000000001',
      ]);
    },
  );

  group('skill matching', () {
    setUp(() {
      state
        ..currentUser = _head
        ..users = [_head, _student, _student2]
        ..announcements = [
          _request(id: 'lib', office: 'Library'),
          _request(id: 'reg', office: 'Registrar', skills: ['typing']),
          _request(id: 'old', office: 'Clinic', isOpen: false),
          _request(id: 'wait', office: 'Gym', approvalStatus: 'Pending'),
          _call(),
        ];
    });

    test('ranks open requests by how many skills match, any case', () {
      final matches = state.skillMatchesFor(
        _application(_student, skills: ['TYPING', 'ms excel']),
      );

      expect(matches.map((m) => m.request.id), ['lib', 'reg']);
      expect(matches.first.matched, ['Typing', 'MS Excel']);
      expect(matches.first.missing, ['Filing']);
      expect('${matches.first.count}/${matches.first.total}', '2/3');
    });

    test('an applicant with no match still has an application, just no '
        'matches', () {
      expect(
        state.skillMatchesFor(_application(_student2, skills: ['Singing'])),
        isEmpty,
      );
    });

    test('closed or unapproved requests and hiring calls aren\'t matched', () {
      expect(state.openOfficeRequests.map((r) => r.id), ['lib', 'reg']);
    });
  });

  group('screening', () {
    setUp(() {
      state
        ..currentUser = _head
        ..users = [_head, _student, _student2]
        ..applications = [
          _application(_student, skills: ['Typing']),
          _application(_student2, status: Application.waitlisted),
        ];
    });

    test(
      'only Pending applications go to screening, and they\'re told',
      () async {
        final sent = await state.sendToScreening([
          'app_stu1_2026-2027',
          'app_stu2_2026-2027',
        ]);

        expect(sent, 1);
        expect(store.applications.keys, ['app_stu1_2026-2027']);
        expect(
          store.applications['app_stu1_2026-2027']!.status,
          Application.forScreening,
        );
        expect(store.sentTo('stu1').single['title'], 'Selected for Screening');
        expect(store.sentTo('stu2'), isEmpty);
      },
    );

    test('approving makes a Student Assistant with no office and no '
        'documents yet', () async {
      await state.updateApplicationStatus(
        'app_stu1_2026-2027',
        Application.approved,
      );

      final user = state.users.firstWhere((u) => u.id == 'stu1');
      expect(user.role, 'Student Assistant');
      expect(user.saId, isNotNull);
      expect(user.skills, ['Typing']);
      expect(state.officesForUser(user), isEmpty);
      // The contract and endorsement letter wait for the office.
      expect(
        store.applications['app_stu1_2026-2027']!.submittedDocuments,
        isEmpty,
      );
      expect(store.sentTo('stu1').single['title'], 'Application Approved');
    });

    test(
      'saving an approval again finishes it without a second notice',
      () async {
        await state.updateApplicationStatus(
          'app_stu1_2026-2027',
          Application.approved,
        );
        await state.updateApplicationStatus(
          'app_stu1_2026-2027',
          Application.approved,
        );

        expect(store.sentTo('stu1'), hasLength(1));
        expect(
          state.users.firstWhere((u) => u.id == 'stu1').role,
          'Student Assistant',
        );
        // The students record is made once, and kept.
        expect(store.students.where((s) => s.userId == 'stu1'), hasLength(1));
        expect(state.students.where((s) => s.userId == 'stu1'), hasLength(1));
      },
    );

    test('a decision that fails to save tells no one', () async {
      final failing = _FailingStore();
      state = AppState(firestoreService: failing)
        ..currentUser = _head
        ..users = [_head, _student]
        ..applications = [_application(_student)];

      await expectLater(
        state.updateApplicationStatus(
          'app_stu1_2026-2027',
          Application.forScreening,
        ),
        throwsException,
      );
      expect(state.applications.single.status, Application.pending);
      expect(failing.notifications, isEmpty);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget screen, Size size) async {
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
            home: Scaffold(body: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a student sees one way to apply and no office requests', (
      tester,
    ) async {
      state
        ..currentUser = _student
        ..users = [_student]
        ..skills = ['Typing', 'MS Excel']
        ..announcements = [_request(), _call()];

      await pump(tester, const AnnouncementsScreen(), const Size(390, 900));

      expect(find.text('Apply to be a Student Assistant'), findsOneWidget);
      expect(find.text('Library Aide'), findsNothing);
      expect(find.text('Apply Now'), findsOneWidget);

      await tester.tap(find.text('Apply Now'));
      await tester.pumpAndSettle();

      // The form asks for skills and the call's requirements, no office.
      expect(find.text('YOUR SKILLS'), findsOneWidget);
      expect(find.text('Typing'), findsOneWidget);
      expect(find.text('Only PDF accepted'), findsOneWidget);
      expect(find.text('Upload Document'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('after applying, the student follows their application', (
      tester,
    ) async {
      state
        ..currentUser = _student
        ..users = [_student]
        ..announcements = [_call()]
        ..applications = [
          _application(_student, status: Application.forScreening),
        ];

      await pump(tester, const AnnouncementsScreen(), const Size(390, 900));

      expect(find.text('Your application'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
      expect(find.textContaining('selected for screening'), findsOneWidget);
    });

    testWidgets('the Head sees every applicant, picks some and sends them '
        'to screening', (tester) async {
      state
        ..currentUser = _head
        ..users = [_head, _student, _student2]
        ..announcements = [_request(), _call()]
        ..applications = [
          _application(_student, skills: ['Typing', 'MS Excel']),
          _application(_student2, skills: ['Singing']),
        ];

      await pump(
        tester,
        const ApplicantScreeningScreen(),
        const Size(1440, 1400),
      );

      // Both are listed, the one matching nothing too.
      expect(find.text('Sam Student'), findsOneWidget);
      expect(find.text('Rita Reyes'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      expect(
        find.textContaining('No match with the open requests'),
        findsOneWidget,
      );

      // "No match" keeps only Rita.
      await tester.tap(find.text('No match'));
      await tester.pumpAndSettle();
      expect(find.text('Sam Student'), findsNothing);
      expect(find.text('Rita Reyes'), findsOneWidget);

      // Tick her and send her to screening.
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send 1 to Screening'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send to Screening').last);
      await tester.pumpAndSettle();

      expect(
        store.applications['app_stu2_2026-2027']?.status,
        Application.forScreening,
      );
      expect(store.applications.containsKey('app_stu1_2026-2027'), isFalse);
    });

    testWidgets('picking an office request shows who matches it, best '
        'first', (tester) async {
      state
        ..currentUser = _head
        ..users = [_head, _student, _student2]
        ..announcements = [
          _request(id: 'lib', office: 'Library'),
          _request(id: 'reg', office: 'Registrar', skills: ['Singing']),
          _call(),
        ]
        ..applications = [
          _application(_student, skills: ['Typing', 'MS Excel']),
          _application(_student2, skills: ['Singing']),
        ];

      await pump(
        tester,
        const ApplicantScreeningScreen(),
        const Size(1440, 1400),
      );
      await tester.tap(find.textContaining('Any request'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Registrar · Registrar Aide').last);
      await tester.pumpAndSettle();

      expect(find.text('Rita Reyes'), findsOneWidget);
      expect(find.text('Sam Student'), findsNothing);
      expect(find.text('1/1'), findsOneWidget);
    });

    testWidgets('one page: an applicant picked for screening is interviewed '
        'from the same list', (tester) async {
      state
        ..currentUser = _head
        ..users = [_head, _student, _student2]
        ..applications = [
          _application(_student),
          _application(_student2, status: Application.forScreening),
        ];

      await pump(
        tester,
        const ApplicantScreeningScreen(),
        const Size(1440, 1400),
      );

      // Everyone is on the one list, and there's no queue elsewhere.
      expect(find.text('Applications & Screening'), findsOneWidget);
      expect(find.text('Sam Student'), findsOneWidget);
      expect(find.text('Rita Reyes'), findsOneWidget);
      expect(find.text('Send to Screening'), findsWidgets);

      await tester.tap(find.text('Conduct Interview & Assessment'));
      await tester.pumpAndSettle();

      expect(
        find.text('INTERVIEW AND ASSESSMENT FORM FOR STUDENT ASSISTANTS'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Full Name'))
            .controller!
            .text,
        'Rita Reyes',
      );
    });

    testWidgets('ticks and filters survive a visit to the records', (
      tester,
    ) async {
      state
        ..currentUser = _head
        ..users = [_head, _student, _student2]
        ..applications = [_application(_student), _application(_student2)];

      await pump(
        tester,
        const ApplicantScreeningScreen(),
        const Size(1440, 1400),
      );
      await tester.tap(find.text('Pending').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      expect(find.text('Send 1 to Screening'), findsOneWidget);

      await tester.tap(find.text('Screening Records (0)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Applicants (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Send 1 to Screening'), findsOneWidget);
    });

    testWidgets('the Head rejects a wrong document with a reason', (
      tester,
    ) async {
      state
        ..currentUser = _head
        ..users = [_head, _student]
        ..applications = [
          Application(
            id: 'app_stu1_2026-2027',
            announcementId: 'call1',
            announcementTitle: Application.generalTitle,
            applicantId: 'stu1',
            applicantName: 'Sam Student',
            appliedAt: 'Oct 2, 2026',
            academicYear: '2026-2027',
            submittedDocuments: [
              ApplicationDocument(
                id: 'd1',
                applicationId: 'app_stu1_2026-2027',
                requirementName: 'Certificate of Registration::pdf',
                fileName: 'selfie.pdf',
                uploadedAt: 'Oct 2, 2026',
              ),
            ],
          ),
        ];

      await pump(
        tester,
        const ApplicantScreeningScreen(),
        const Size(1440, 1400),
      );
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      // No reason, no rejection.
      final confirm = find.widgetWithText(ElevatedButton, 'Reject');
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);

      await tester.tap(find.text('Wrong file: Certificate of Registration'));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      final saved = store.applications['app_stu1_2026-2027']!;
      expect(saved.status, Application.rejected);
      expect(saved.remarks, 'Wrong file for "Certificate of Registration"');
      expect(
        store.sentTo('stu1').single['message'],
        contains('Wrong file for "Certificate of Registration"'),
      );
    });

    testWidgets('a rejected student applies again, keeping their files', (
      tester,
    ) async {
      state
        ..currentUser = _student
        ..users = [_student]
        ..skills = ['Typing']
        ..announcements = [_call()]
        ..applications = [
          Application(
            id: 'app_stu1_2026-2027',
            announcementId: 'call1',
            announcementTitle: Application.generalTitle,
            applicantId: 'stu1',
            applicantName: 'Sam Student',
            appliedAt: 'Oct 2, 2026',
            status: Application.rejected,
            remarks: 'Wrong file for "Resume"',
            skills: const ['Typing'],
            academicYear: '2026-2027',
            submittedDocuments: [
              ApplicationDocument(
                id: 'd1',
                applicationId: 'app_stu1_2026-2027',
                requirementName: 'Resume::pdf',
                fileName: 'resume.pdf',
                uploadedAt: 'Oct 2, 2026',
                fileSize: 0.5,
                storagePath: 'applications/stu1/1/resume.pdf',
              ),
            ],
          ),
        ];

      await pump(tester, const AnnouncementsScreen(), const Size(390, 900));

      expect(find.text('Reason: Wrong file for "Resume"'), findsOneWidget);
      await tester.tap(find.text('Apply Again'));
      await tester.pumpAndSettle();

      // The form starts from what they sent: the skill and the file.
      expect(find.text('From last time'), findsOneWidget);
      expect(find.textContaining('resume.pdf'), findsOneWidget);
      final submit = find.text('Submit Application');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final saved = store.applications['app_stu1_2026-2027']!;
      expect(saved.status, Application.pending);
      expect(saved.remarks, isNull);
      expect(saved.skills, ['Typing']);
      expect(
        saved.submittedDocuments.single.storagePath,
        'applications/stu1/1/resume.pdf',
      );
      expect(
        store.sentTo('head1').single['message'],
        'Sam Student applied again to be a Student Assistant.',
      );
    });
  });
}

/// Refuses every application save, as the rules would.
class _FailingStore extends _Store {
  @override
  Future<void> setApplication(Application a) async =>
      throw Exception('permission-denied');
}
