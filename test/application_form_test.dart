import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/recurring_schedule.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/screens/profile/profile_screen.dart';
import 'package:projectsais/screens/student_portal/announcements_screen.dart';
import 'package:projectsais/services/application_form_document_service.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/utils/schedule_reader/schedule_reader.dart';
import 'package:projectsais/widgets/application_form_dialog.dart';

import 'support/account_writes.dart';

class _Store extends FirestoreService with AccountWrites {
  final applications = <String, Application>{};
  final notifications = <Map<String, dynamic>>[];

  @override
  Future<void> setApplication(Application a) async => applications[a.id] = a;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);

  @override
  Future<List<String>> getHeadIds() async => ['head1'];

  @override
  Future<String?> studentIdHolder(String key) async => null;
}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'head@marsu.edu.ph',
  role: 'Head',
);

final _student = User(
  id: 'stu1',
  name: 'Juan M. Dela Cruz',
  firstName: 'Juan',
  middleName: 'Mercado',
  lastName: 'Dela Cruz',
  email: 'juan@marsu.edu.ph',
  role: 'Student',
  department: 'CICS',
  courseProgram: 'BSIT',
  yearLevel: '3rd Year',
  phone: '0917 111 2222',
  address: 'Boac, Marinduque',
);

final _sa = User(
  id: 'stu1',
  name: 'Juan M. Dela Cruz',
  firstName: 'Juan',
  middleName: 'Mercado',
  lastName: 'Dela Cruz',
  email: 'juan@marsu.edu.ph',
  role: 'Student Assistant',
  department: 'CICS',
  courseProgram: 'BSIT',
  yearLevel: '3rd Year',
  saId: 'SA 001',
  phone: '0917 111 2222',
  address: 'Boac, Marinduque',
);

ApplicationFormData _sampleForm() => const ApplicationFormData(
  semester: '1st Sem',
  academicYear: '2026-2027',
  surname: 'Dela Cruz',
  firstName: 'Juan',
  middleName: 'Mercado',
  studentNumber: '23B0626',
  programAndYear: 'BSIT - 3rd Year',
  existingScholarships: 'CHED TES',
  remainingUnits: '21',
  remainingTerms: '2',
  dateOfBirth: 'May 10, 2005',
  age: '21',
  placeOfBirth: 'Boac, Marinduque',
  email: 'juan@marsu.edu.ph',
  citizenship: 'Filipino',
  gender: 'Male',
  civilStatus: 'Single',
  religion: 'Roman Catholic',
  residingAt: 'With Guardian',
  guardianName: 'Elena Santos',
  emergencyContactName: 'Elena Santos',
  emergencyContactNumber: '0918 222 3333',
  permanentAddress: 'Tanza, Boac, Marinduque',
  contactNumber: '0917 111 2222',
  gwa: '1.50',
  fatherName: 'Pedro Dela Cruz',
  fatherAge: '50',
  fatherOccupation: 'Farmer',
  fatherNetAnnualIncome: '80000',
  motherName: 'Maria Dela Cruz',
  motherAge: '48',
  motherOccupation: 'Vendor',
  motherNetAnnualIncome: '60000',
  familyHomeAddress: 'Tanza, Boac, Marinduque',
  familyContactNumbers: '0917 111 2222',
  siblings: [
    SiblingEntry(
      name: 'Ana Dela Cruz',
      age: '18',
      schoolOrOccupation: 'MarSU',
      program: 'BSED 1st Year',
    ),
    SiblingEntry(
      name: 'Mark Dela Cruz',
      age: '15',
      schoolOrOccupation: 'MNHS',
      program: 'Grade 10',
    ),
    SiblingEntry(
      name: 'Luis Dela Cruz',
      age: '12',
      schoolOrOccupation: 'Boac South',
      program: 'Grade 7',
    ),
    SiblingEntry(
      name: 'Joy Dela Cruz',
      age: '9',
      schoolOrOccupation: 'Boac South',
      program: 'Grade 4',
    ),
  ],
  totalSiblings: '4',
  workingSiblings: '0',
  studyingSiblings: '4',
  reasonsForAvailing:
      'Support tuition & daily expenses.\nGain office experience.',
  organizations: [
    OrganizationEntry(name: 'CICS Student Council', position: 'Treasurer'),
    OrganizationEntry(name: 'MarSU Red Cross Youth', position: 'Member'),
  ],
  dateSubmitted: 'Oct 5, 2026',
);

Announcement _call() => Announcement(
  id: 'call1',
  title: 'Student Assistant Hiring, 1st Semester',
  body: 'Bring your COR and grades during screening.',
  postedBy: 'Helen Head',
  postedAt: '10/1/2026',
  requirements: const ['Resume::pdf'],
);

void _ignoreOverflow() {
  final onError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = onError);
  FlutterError.onError = (details) =>
      details.exceptionAsString().contains('overflowed')
      ? null
      : onError?.call(details);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApplicationFormData model', () {
    test('serializes and round-trips through JSON and copyWith', () {
      final form = _sampleForm();
      final decoded = ApplicationFormData.fromJson(form.toJson());
      expect(decoded.surname, 'Dela Cruz');
      expect(decoded.siblings, hasLength(4));
      expect(decoded.siblings.last.name, 'Joy Dela Cruz');
      expect(decoded.organizations, hasLength(2));
      expect(decoded.organizations.first.position, 'Treasurer');
      expect(decoded.problems(), isEmpty);

      final app = Application(
        id: 'app_stu1_2026-2027',
        announcementId: 'call1',
        announcementTitle: Application.generalTitle,
        applicantId: 'stu1',
        applicantName: 'Juan M. Dela Cruz',
        appliedAt: 'Oct 5, 2026',
        applicationForm: form,
      );
      expect(app.copyWith(status: Application.approved).applicationForm, isNotNull);
      expect(Application.isApplicationFormRequirement('Application Form'), isTrue);
      expect(
        Application.isApplicationFormRequirement(
          'Application Form for Student Assistantship::word',
        ),
        isTrue,
      );
    });

    test('problems reports missing required fields', () {
      const empty = ApplicationFormData();
      final issues = empty.problems();
      expect(issues, isNotEmpty);
      expect(issues.first, contains('surname'));
    });

    test('problems rejects invalid numbers, GWA, and phone numbers', () {
      final invalid = _sampleForm().copyWith(
        remainingUnits: 'abc',
        remainingTerms: '0',
        age: '5',
        gwa: '6.50',
        contactNumber: '12345',
        emergencyContactNumber: '0918',
        fatherAge: 'old',
        fatherNetAnnualIncome: 'abc',
        familyContactNumbers: '999',
        totalSiblings: 'two',
      );
      final issues = invalid.problems();
      expect(issues, contains('Enter a valid number for remaining units.'));
      expect(
        issues,
        contains('Enter a valid number for remaining terms to graduate.'),
      );
      expect(issues, contains('Enter a valid age.'));
      expect(issues, contains('Enter a valid GWA between 1.00 and 5.00.'));
      expect(
        issues,
        contains('Enter a valid contact number (09XX XXX XXXX).'),
      );
      expect(
        issues,
        contains('Enter a valid emergency contact number (09XX XXX XXXX).'),
      );
      expect(issues, contains("Enter a valid number for father's age."));
      expect(
        issues,
        contains("Enter a valid number for father's net annual income."),
      );
      expect(
        issues,
        contains('Enter a valid family contact number (09XX XXX XXXX).'),
      );
      expect(issues, contains('Enter a valid number for total siblings.'));
    });
  });

  group('ApplicationFormDocumentService', () {
    test('fills the real template with all fields, 4 siblings, 2 orgs, and '
        'XML special characters', () async {
      final form = _sampleForm().copyWith(
        reasonsForAvailing: 'Help & support <family> "studies"\nGain skills',
      );
      final doc = await const ApplicationFormDocumentService()
          .generateApplicationForm(
            data: form,
            applicationId: 'app_stu1_2026-2027',
          );

      expect(doc.fileName, 'application-form-juan-m-dela-cruz.docx');
      expect(doc.requirementName, Application.applicationFormDocument);
      expect(doc.bytes, isNotNull);
      expect(doc.bytes!.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);

      final archive = ZipDecoder().decodeBytes(doc.bytes!);
      expect(archive.findFile('word/header2.xml'), isNotNull);
      expect(archive.findFile('word/footer2.xml'), isNotNull);

      final xml = utf8.decode(
        archive.findFile('word/document.xml')!.content as List<int>,
      );
      expect(xml, isNot(contains('{{')));
      expect(xml, contains('1st Sem [X]'));
      expect(xml, contains('2nd Sem [ ]'));
      expect(xml, contains('2026-2027'));
      expect(xml, contains('DELA CRUZ, Juan Mercado'));
      expect(xml, contains('23B0626'));
      expect(xml, contains('BSIT - 3rd Year'));
      expect(xml, contains('CHED TES'));
      expect(xml, contains('[X] With Guardian: Elena Santos'));
      expect(xml, contains('1.50'));
      expect(xml, contains('Pedro Dela Cruz'));
      expect(xml, contains('Joy Dela Cruz'));
      expect(xml, contains('CICS Student Council'));
      expect(xml, contains('Help &amp; support &lt;family&gt; &quot;studies&quot;'));
      expect(xml, contains('JUAN M. DELA CRUZ'));
      expect(xml, contains('Oct 5, 2026'));
      expect(xml, contains('2 x 2'));
    });

    test('embeds a 2x2 photo into the docx when provided', () async {
      final tinyPng = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      final doc = await const ApplicationFormDocumentService()
          .generateApplicationForm(
            data: _sampleForm(),
            applicationId: 'app_stu1_2026-2027',
            photoBytes: tinyPng,
            photoExtension: 'png',
          );

      final archive = ZipDecoder().decodeBytes(doc.bytes!);
      expect(archive.findFile('word/media/applicant_photo_2x2.png'), isNotNull);
      final rels = utf8.decode(
        archive.findFile('word/_rels/document.xml.rels')!.content as List<int>,
      );
      expect(rels, contains('rIdApplicantPhoto2x2'));
      expect(rels, contains('media/applicant_photo_2x2.png'));

      final xml = utf8.decode(
        archive.findFile('word/document.xml')!.content as List<int>,
      );
      expect(xml, contains('r:embed="rIdApplicantPhoto2x2"'));
      expect(xml, isNot(contains('{{PHOTO_2X2}}')));
    });
  });

  group('UI integration', () {
    late _Store store;
    late AppState state;

    setUp(() {
      store = _Store()..profiles[_student.id] = _student;
      state = AppState(firestoreService: store)
        ..academicYear = '2026-2027'
        ..academicSemester = '1st Semester';
    });

    Future<void> pump(WidgetTester tester, Widget screen, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(body: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Apply card shows requirements and interview notice', (
      tester,
    ) async {
      state
        ..currentUser = _student
        ..users = [_student]
        ..announcements = [_call()];

      await pump(tester, const AnnouncementsScreen(), const Size(390, 900));

      expect(find.text('Application form'), findsOneWidget);
      expect(
        find.textContaining('bring physical copies of any requirements'),
        findsOneWidget,
      );
      expect(
        find.textContaining('scheduled for an interview'),
        findsOneWidget,
      );
    });

    testWidgets('ApplyDialog requires Application Form and uploads filled docx', (
      tester,
    ) async {
      final uploads = <String>[];
      final schedule = ClassScheduleSubmission(
        fileName: 'schedule.png',
        filePath: 'schedules/stu1/1/schedule.png',
        subjects: [
          RecurringScheduleRule(
            id: 's1',
            ownerName: 'Juan M. Dela Cruz',
            label: 'IT 101',
            weekday: 1,
            startTime: const TimeOfDay(hour: 8, minute: 0),
            endTime: const TimeOfDay(hour: 10, minute: 0),
            color: Colors.blue,
            icon: Icons.school_outlined,
            isSubject: true,
          ),
        ],
      );
      final rejected = Application(
        id: 'app_stu1_2026-2027',
        announcementId: 'call1',
        announcementTitle: Application.generalTitle,
        applicantId: 'stu1',
        applicantName: 'Juan M. Dela Cruz',
        appliedAt: 'Oct 2, 2026',
        status: Application.rejected,
        remarks: 'Replace resume',
        studentNumber: '23B0626',
        classSchedule: schedule,
        submittedDocuments: [
          ApplicationDocument(
            id: 'd_id',
            applicationId: 'app_stu1_2026-2027',
            requirementName: 'School ID',
            fileName: 'id.jpg',
            uploadedAt: 'Oct 2, 2026',
            storagePath: 'applications/stu1/1/id.jpg',
          ),
          ApplicationDocument(
            id: 'd_res',
            applicationId: 'app_stu1_2026-2027',
            requirementName: 'Resume::pdf',
            fileName: 'resume.pdf',
            uploadedAt: 'Oct 2, 2026',
            storagePath: 'applications/stu1/1/resume.pdf',
          ),
        ],
      );
      state
        ..currentUser = _student
        ..users = [_student]
        ..announcements = [_call()]
        ..applications = [rejected];

      await pump(
        tester,
        AnnouncementsScreen(
          schoolIdReader: (_, _) async =>
              const SchoolIdReadResult(ok: true, studentId: '23B0626'),
          scheduleReader: (_, _) async =>
              const ScheduleReadResult(ok: false, meetings: []),
          filePicker: (_) async => PlatformFile(
            name: 'resume.pdf',
            size: 4,
            bytes: Uint8List.fromList([1, 2, 3, 4]),
          ),
          fileUploader: (bytes, path, ext) async {
            uploads.add(path);
            return 'https://example.com/$path';
          },
        ),
        const Size(430, 1000),
      );

      await tester.ensureVisible(find.text('Apply Again'));
      await tester.tap(find.text('Apply Again'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Bring physical copies of any requirements'),
        findsOneWidget,
      );

      // Submitting before filling the Application Form is blocked.
      final submitBtn = find.text('Submit Application');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('Please fill out the Application Form before submitting.'),
        findsOneWidget,
      );
      expect(store.applications, isEmpty);

      // Open and fill out the Application Form dialog.
      await tester.ensureVisible(find.text('Fill Out Application Form'));
      await tester.tap(find.text('Fill Out Application Form'));
      await tester.pumpAndSettle();

      expect(find.byType(ApplicationFormDialog), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Remaining Units Including This Term *',
        ),
        '21',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Remaining Terms to Graduate *'),
        '2',
      );
      // Set Date of Birth via picker and Age directly via text field? Date
      // picker is readOnly, so pick today's date dialog!
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Date of Birth *'),
      );
      await tester.tap(find.widgetWithText(TextField, 'Date of Birth *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Place of Birth *'),
        'Boac',
      );
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Gender *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Civil Status *'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Single').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Religion *'),
        'Catholic',
      );
      await tester.ensureVisible(find.text("Parent's House"));
      await tester.tap(find.text("Parent's House"));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Emergency Contact Person *'),
        'Maria Dela Cruz',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Emergency Contact Number *'),
        '0918 222 3333',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'General Weighted Average (Last Semester Attended) *',
        ),
        '1.50',
      );
      await tester.ensureVisible(
        find.widgetWithText(
          TextField,
          'Reason/s for Availing Student Assistantship *',
        ),
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Reason/s for Availing Student Assistantship *',
        ),
        'Support studies',
      );

      await tester.tap(find.text('Save Form'));
      await tester.pumpAndSettle();
      expect(find.byType(ApplicationFormDialog), findsNothing);
      expect(find.text('✓ Filled'), findsOneWidget);
      expect(find.text('Preview Filled Form'), findsOneWidget);

      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      final saved = store.applications['app_stu1_2026-2027'];
      expect(saved, isNotNull);
      expect(saved!.applicationForm, isNotNull);
      expect(saved.applicationFormDoc, isNotNull);
      expect(saved.applicationFormDoc!.fileName, endsWith('.docx'));
      expect(uploads.single, endsWith('.docx'));
    });

    testWidgets('Head, Student, and SA all have preview/download access to '
        'the filled Application Form', (tester) async {
      final app = Application(
        id: 'app_stu1_2026-2027',
        announcementId: 'call1',
        announcementTitle: Application.generalTitle,
        applicantId: 'stu1',
        applicantName: 'Juan M. Dela Cruz',
        appliedAt: 'Oct 5, 2026',
        status: Application.approved,
        academicYear: '2026-2027',
        studentNumber: '23B0626',
        applicationForm: _sampleForm(),
        submittedDocuments: [
          ApplicationDocument(
            id: 'd_form',
            applicationId: 'app_stu1_2026-2027',
            requirementName: Application.applicationFormDocument,
            fileName: 'application-form-juan-m-dela-cruz.docx',
            uploadedAt: 'Oct 5, 2026',
            storagePath: 'applications/stu1/1/form.docx',
          ),
        ],
      );

      // 1. Head view
      state
        ..currentUser = _head
        ..users = [_head, _sa]
        ..applications = [app];
      await pump(
        tester,
        const ApplicantScreeningScreen(),
        const Size(1440, 1400),
      );
      expect(find.text('APPLICATION FORM'), findsOneWidget);
      expect(find.text('View Filled Form'), findsOneWidget);
      expect(find.text('Download (.docx)'), findsOneWidget);

      // 2. SA view on Announcements / Apply status card
      state
        ..currentUser = _sa
        ..users = [_sa];
      await pump(tester, const AnnouncementsScreen(), const Size(390, 900));
      expect(find.text('APPLICATION FORM'), findsOneWidget);
      expect(find.text('Preview Form'), findsOneWidget);
      expect(find.text('Download Form'), findsOneWidget);

      // 3. SA view on Profile screen
      await pump(tester, const ProfileScreen(), const Size(1200, 900));
      expect(find.text('My Application Form'), findsOneWidget);
      expect(find.text('Preview Form'), findsOneWidget);
      expect(find.text('Download (.docx)'), findsOneWidget);
    });

    testWidgets('Student Number is locked to Student ID and numeric fields '
        'reject letters', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: ApplicationFormDialog(
              user: _student,
              academicYear: '2026-2027',
              semester: '1st Semester',
              studentNumber: '23B0626',
              initialData: _sampleForm().copyWith(studentNumber: '99Z9999'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Even if initialData had a stale studentNumber, the live Student ID wins
      // and cannot be changed manually.
      final studentNumberField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Student Number'),
      );
      expect(studentNumberField.readOnly, isTrue);
      expect(studentNumberField.controller!.text, '23B0626');
      await tester.enterText(
        find.widgetWithText(TextField, 'Student Number'),
        '24C1111',
      );
      expect(studentNumberField.controller!.text, '23B0626');

      // Numeric fields reject non-digits/letters.
      final unitsFinder = find.widgetWithText(
        TextField,
        'Remaining Units Including This Term *',
      );
      await tester.enterText(unitsFinder, 'abc');
      expect(tester.widget<TextField>(unitsFinder).controller!.text, '');
      await tester.enterText(unitsFinder, '2a4b');
      expect(tester.widget<TextField>(unitsFinder).controller!.text, '24');

      final gwaFinder = find.widgetWithText(
        TextField,
        'General Weighted Average (Last Semester Attended) *',
      );
      await tester.enterText(gwaFinder, 'abc');
      expect(tester.widget<TextField>(gwaFinder).controller!.text, '1.50');

      final fatherAgeFinder = find.widgetWithText(TextField, "Father's Age");
      await tester.ensureVisible(fatherAgeFinder);
      await tester.enterText(fatherAgeFinder, 'xyz');
      expect(tester.widget<TextField>(fatherAgeFinder).controller!.text, '');
      await tester.enterText(fatherAgeFinder, '5a0');
      expect(tester.widget<TextField>(fatherAgeFinder).controller!.text, '50');

      final totalSibsFinder = find.widgetWithText(TextField, 'Total Siblings');
      await tester.ensureVisible(totalSibsFinder);
      await tester.enterText(totalSibsFinder, 'abc');
      expect(tester.widget<TextField>(totalSibsFinder).controller!.text, '');
      await tester.enterText(totalSibsFinder, '4x');
      expect(tester.widget<TextField>(totalSibsFinder).controller!.text, '4');
    });

    testWidgets('Student Number stays locked even before Student ID is '
        'scanned', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: ApplicationFormDialog(
              user: _student,
              academicYear: '2026-2027',
              semester: '1st Semester',
              studentNumber: '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final studentNumberField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Student Number'),
      );
      expect(studentNumberField.readOnly, isTrue);
      expect(studentNumberField.controller!.text, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Student Number'),
        '24C1111',
      );
      expect(studentNumberField.controller!.text, isEmpty);
    });
  });
}
