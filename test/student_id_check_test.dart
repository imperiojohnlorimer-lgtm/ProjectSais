// The Student ID moved from registration to the application: the student
// types it and sends a photo of their school ID, the Head checks one against
// the other, and only then can the applicant go to screening or be approved.
// Approval puts the ID on the profile, verified and reserved.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/recurring_schedule.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/screens/student_portal/announcements_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/utils/schedule_reader/schedule_reader.dart';

import 'support/account_writes.dart';

class _Store extends FirestoreService with AccountWrites {
  final applications = <String, Application>{};
  final notifications = <Map<String, dynamic>>[];
  final students = <Student>[];

  /// studentIds: Student ID → account id.
  final claims = <String, String>{};
  final verified = <({String uid, String key, String by, String at})>[];

  @override
  Future<void> setApplication(Application a) async => applications[a.id] = a;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);

  @override
  Future<List<String>> getHeadIds() async => ['head1'];

  @override
  Future<void> setUserProfile(User user) async => profiles[user.id] = user;

  @override
  Future<void> setStudent(Student student) async => students.add(student);

  @override
  Future<void> setSkill(String name) async {}

  @override
  Future<String?> studentIdHolder(String key) async => claims[key];

  @override
  Future<String?> verifyStudentId(
    String uid,
    String key, {
    required String verifiedBy,
    required String verifiedAt,
  }) async {
    final holder = claims[key];
    if (holder != null && holder != uid) return holder;
    claims[key] = uid;
    verified.add((uid: uid, key: key, by: verifiedBy, at: verifiedAt));
    return null;
  }
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
);
final _other = User(
  id: 'stu2',
  name: 'Rita Reyes',
  email: 'rita@marsu.edu.ph',
  role: 'Student',
);

Announcement _call({List<String> requirements = const ['Resume::pdf']}) =>
    Announcement(
      id: 'call1',
      title: 'Student Assistant Hiring',
      body: 'Apply to be a Student Assistant.',
      postedBy: 'Helen Head',
      postedAt: '10/1/2026',
      requirements: requirements,
    );

ApplicationDocument _doc(String requirement, String file) =>
    ApplicationDocument(
      id: 'd_$file',
      applicationId: 'app_stu1_2026-2027',
      requirementName: requirement,
      fileName: file,
      uploadedAt: 'Oct 2, 2026',
      fileSize: 0.5,
      storagePath: 'applications/stu1/1/$file',
    );

ApplicationFormData _validForm() => const ApplicationFormData(
  semester: '1st Sem',
  academicYear: '2026-2027',
  surname: 'Student',
  firstName: 'Sam',
  programAndYear: 'BSIT - 3rd Year',
  remainingUnits: '24',
  remainingTerms: '2',
  dateOfBirth: 'Jan 1, 2005',
  age: '21',
  placeOfBirth: 'Boac, Marinduque',
  email: 'sam@marsu.edu.ph',
  citizenship: 'Filipino',
  gender: 'Male',
  civilStatus: 'Single',
  religion: 'Catholic',
  residingAt: "Parent's House",
  emergencyContactName: 'Maria Student',
  emergencyContactNumber: '0917 123 4567',
  permanentAddress: 'Boac, Marinduque',
  contactNumber: '0917 000 0000',
  gwa: '1.75',
  reasonsForAvailing: 'To support my studies.',
);

Application _application({
  User? user,
  String status = Application.pending,
  String? studentNumber = '23B0626',
  bool checked = false,
  List<ApplicationDocument>? documents,
  ClassScheduleSubmission? schedule,
  String? remarks,
  ApplicationFormData? applicationForm,
}) {
  final who = user ?? _student;
  return Application(
    id: Application.idFor(who.id, '2026-2027'),
    announcementId: 'call1',
    announcementTitle: Application.generalTitle,
    applicantId: who.id,
    applicantName: who.name,
    appliedAt: 'Oct 2, 2026',
    status: status,
    remarks: remarks,
    academicYear: '2026-2027',
    studentNumber: studentNumber,
    studentIdCheckedBy: checked ? 'Helen Head' : null,
    studentIdCheckedAt: checked ? '2026-11-20T02:00:00.000Z' : null,
    submittedDocuments: documents ?? [_doc('School ID', 'id.jpg')],
    classSchedule: schedule,
    applicationForm: applicationForm ?? _validForm(),
  );
}

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store()
      ..profiles[_student.id] = _student
      ..profiles[_other.id] = _other;
    state = AppState(firestoreService: store)
      ..currentUser = _head
      ..users = [_head, _student, _other];
  });

  group('the model', () {
    test('the school ID photo is found by its label, in any case', () {
      expect(_application().schoolIdPhoto?.fileName, 'id.jpg');
      expect(
        _application(
          documents: [_doc('school id::image', 'card.png')],
        ).schoolIdPhoto?.fileName,
        'card.png',
      );
      expect(_application(documents: const []).schoolIdPhoto, isNull);
    });

    test('a status change keeps the Student ID and the check', () {
      final moved = _application(checked: true).copyWith(status: 'Approved');
      expect(moved.studentNumber, '23B0626');
      expect(moved.studentIdCheckedBy, 'Helen Head');
      expect(moved.isStudentIdChecked, isTrue);
    });

    test('a profile keeps its verified Student ID through edits', () {
      final verified = _student.copyWith(
        studentId: '23B0626',
        studentIdVerifiedAt: '2026-11-20T02:00:00.000Z',
        studentIdVerifiedBy: 'Helen Head',
      );
      expect(verified.isStudentIdVerified, isTrue);
      expect(verified.copyWith(phone: '0917').isStudentIdVerified, isTrue);
      expect(
        verified.withEmailNotifications(false).studentIdVerifiedBy,
        'Helen Head',
      );
      final json = verified.toJson();
      expect(json['studentIdVerifiedAt'], '2026-11-20T02:00:00.000Z');
      expect(User.fromJson(json).isStudentIdVerified, isTrue);
      // An older profile saves as it was.
      expect(_student.toJson().containsKey('studentIdVerifiedAt'), isFalse);
      expect(
        verified.copyWith(clearStudentIdVerification: true).isStudentIdVerified,
        isFalse,
      );
    });
  });

  group('the Head\'s check', () {
    test('the Head marks it checked, saved with who and when', () async {
      state.applications = [_application()];
      await state.markStudentIdChecked('app_stu1_2026-2027');

      final saved = store.applications['app_stu1_2026-2027']!;
      expect(saved.studentIdCheckedBy, 'Helen Head');
      expect(saved.studentIdCheckedAt, isNotNull);
      expect(state.applications.single.isStudentIdChecked, isTrue);
    });

    test('nobody but a Head can mark it', () async {
      state
        ..currentUser = _student
        ..applications = [_application()];
      await state.markStudentIdChecked('app_stu1_2026-2027');
      expect(store.applications, isEmpty);
    });

    test('unchecked, nobody goes to screening or is approved', () async {
      state.applications = [_application()];
      for (final status in [Application.forScreening, Application.approved]) {
        await expectLater(
          state.updateApplicationStatus('app_stu1_2026-2027', status),
          throwsStateError,
        );
      }
      expect(store.applications, isEmpty);
      expect(store.notifications, isEmpty);
      // Rejecting or putting back needs no check.
      await state.updateApplicationStatus(
        'app_stu1_2026-2027',
        Application.rejected,
        remarks: 'Wrong file: School ID',
      );
      expect(
        store.applications['app_stu1_2026-2027']!.status,
        Application.rejected,
      );
    });

    test('saving an older approval again still finishes it', () async {
      state.applications = [
        _application(status: Application.approved, studentNumber: null),
      ];
      await state.updateApplicationStatus(
        'app_stu1_2026-2027',
        Application.approved,
      );
      expect(
        state.users.firstWhere((u) => u.id == 'stu1').role,
        'Student Assistant',
      );
    });

    test('sending to screening skips the unchecked ones', () async {
      state.applications = [
        _application(checked: true),
        _application(user: _other, studentNumber: '24C1111'),
      ];
      final sent = await state.sendToScreening([
        'app_stu1_2026-2027',
        'app_stu2_2026-2027',
      ]);
      expect(sent, 1);
      expect(store.applications.keys, ['app_stu1_2026-2027']);
    });
  });

  group('approval', () {
    test('puts the checked Student ID on the profile, verified and '
        'reserved', () async {
      state.applications = [_application(checked: true)];
      await state.updateApplicationStatus(
        'app_stu1_2026-2027',
        Application.approved,
      );

      expect(store.claims['23B0626'], 'stu1');
      expect(store.verified.single.by, 'Helen Head');
      expect(store.verified.single.at, '2026-11-20T02:00:00.000Z');
      final user = state.users.firstWhere((u) => u.id == 'stu1');
      expect(user.studentId, '23B0626');
      expect(user.isStudentIdVerified, isTrue);
      expect(user.role, 'Student Assistant');
    });

    test(
      'refuses an ID another account holds, before saving anything',
      () async {
        state
          ..users = [_head, _student, _other.copyWith(studentId: '23B0626')]
          ..applications = [_application(checked: true)];
        expect(
          state.studentIdClashFor(state.applications.single),
          'Rita Reyes',
        );
        await expectLater(
          state.updateApplicationStatus(
            'app_stu1_2026-2027',
            Application.approved,
          ),
          throwsStateError,
        );
        expect(store.applications, isEmpty);
      },
    );

    test('refuses an ID reserved by an account not on the roster', () async {
      store.claims['23B0626'] = 'gone';
      state.applications = [_application(checked: true)];
      await expectLater(
        state.updateApplicationStatus(
          'app_stu1_2026-2027',
          Application.approved,
        ),
        throwsStateError,
      );
      expect(store.applications, isEmpty);
    });

    test('two applications with one ID are flagged on both', () {
      state.applications = [_application(), _application(user: _other)];
      expect(
        state.studentIdClashFor(state.applications.first),
        contains('Rita Reyes'),
      );
      expect(
        state.studentIdClashFor(state.applications.last),
        contains('Sam Student'),
      );
    });
  });

  test(
    'an Admin edit that changes the Student ID drops the verified mark',
    () async {
      final verified = _student.copyWith(
        studentId: '23B0626',
        studentIdVerifiedAt: '2026-11-20T02:00:00.000Z',
        studentIdVerifiedBy: 'Helen Head',
      );
      state.users = [_head, verified];
      await state.updateManagedUser(verified.copyWith(phone: '0917 000 0000'));
      expect(store.profiles['stu1']!.isStudentIdVerified, isTrue);
      await state.updateManagedUser(verified.copyWith(studentId: '24C1111'));
      expect(store.profiles['stu1']!.isStudentIdVerified, isFalse);
    },
  );

  test(
    'an Admin edit opened before the Head verified the ID keeps it',
    () async {
      final verified = _student.copyWith(
        studentId: '23B0626',
        studentIdVerifiedAt: '2026-11-20T02:00:00.000Z',
        studentIdVerifiedBy: 'Helen Head',
      );
      state.users = [_head, verified];
      // The dialog opened on the profile as it was: no Student ID yet.
      await state.updateManagedUser(
        _student.copyWith(phone: '0917 000 0000'),
        opened: (studentId: null),
      );
      final saved = store.profiles['stu1']!;
      expect(saved.studentId, '23B0626');
      expect(saved.isStudentIdVerified, isTrue);
      expect(saved.phone, '0917 000 0000');
    },
  );

  test(
    'an older application checked by the Head verifies the profile ID',
    () async {
      state
        ..users = [_head, _student.copyWith(studentId: '23b0626'), _other]
        ..applications = [
          _application(studentNumber: null, checked: true, documents: const []),
        ];
      await state.updateApplicationStatus(
        'app_stu1_2026-2027',
        Application.approved,
      );
      expect(store.verified.single.key, '23B0626');
      expect(
        state.users.firstWhere((u) => u.id == 'stu1').isStudentIdVerified,
        isTrue,
      );
    },
  );

  test(
    'an older approval saved as Accepted can be saved again unchecked',
    () async {
      state.applications = [
        _application(status: 'Accepted', studentNumber: null),
      ];
      await state.updateApplicationStatus(
        'app_stu1_2026-2027',
        Application.approved,
      );
      expect(
        store.applications['app_stu1_2026-2027']!.status,
        Application.approved,
      );
    },
  );

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget screen, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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

    final schedule = ClassScheduleSubmission(
      fileName: 'schedule.png',
      filePath: 'schedules/stu1/1/schedule.png',
      subjects: [
        RecurringScheduleRule(
          id: 's1',
          ownerName: 'Sam Student',
          label: 'Math 1',
          weekday: 1,
          startTime: const TimeOfDay(hour: 8, minute: 0),
          endTime: const TimeOfDay(hour: 10, minute: 0),
          color: Colors.blue,
          icon: Icons.school_outlined,
          isSubject: true,
        ),
      ],
    );

    /// [webApp]: the form as the web app shows it, where files are read
    /// (tests run as the non-web build, which has no reader of its own).
    /// False is the Android app: nothing reads the files.
    Future<void> openApplyAgain(
      WidgetTester tester,
      Application previous, {
      User? user,
      SchoolIdFileReader? schoolIdReader,
      RequirementFilePicker? filePicker,
      RequirementFileUploader? fileUploader,
      bool webApp = true,
    }) async {
      state
        ..currentUser = user ?? _student
        ..users = [user ?? _student]
        ..announcements = [_call()]
        ..applications = [previous];
      await pump(
        tester,
        AnnouncementsScreen(
          schoolIdReader:
              schoolIdReader ??
              (webApp
                  ? (bytes, mime) async =>
                        const SchoolIdReadResult(ok: false, reason: 'Unread.')
                  : null),
          scheduleReader: webApp
              ? (bytes, mime) async =>
                    const ScheduleReadResult(ok: false, meetings: [])
              : null,
          filePicker: filePicker,
          fileUploader:
              fileUploader ??
              (_, path, _) async => 'https://example.com/$path',
        ),
        const Size(390, 1000),
      );
      await tester.ensureVisible(find.text('Apply Again'));
      await tester.tap(find.text('Apply Again'));
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.text('Submit Application');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('applying again keeps the Student ID and the school ID '
        'photo, which isn\'t counted with the requirements', (tester) async {
      await openApplyAgain(
        tester,
        _application(
          status: Application.rejected,
          remarks: 'Wrong file for "Resume"',
          schedule: schedule,
          documents: [
            _doc('School ID', 'id.jpg'),
            _doc('Resume::pdf', 'resume.pdf'),
          ],
        ),
      );

      expect(find.text('YOUR STUDENT ID'), findsOneWidget);
      expect(find.text('Photo of your school ID (front)'), findsOneWidget);
      expect(find.textContaining('id.jpg'), findsOneWidget);
      expect(find.text('1/1 required documents uploaded'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Student ID'),
      );
      expect(field.controller!.text, '23B0626');
      expect(field.readOnly, isTrue);

      await submit(tester);

      final saved = store.applications['app_stu1_2026-2027']!;
      expect(saved.status, Application.pending);
      expect(saved.studentNumber, '23B0626');
      expect(saved.schoolIdPhoto?.fileName, 'id.jpg');
      expect(saved.isStudentIdChecked, isFalse);
    });

    testWidgets('Student ID is read-only and missing photo stops the form', (
      tester,
    ) async {
      await openApplyAgain(
        tester,
        _application(
          status: Application.rejected,
          studentNumber: null,
          schedule: schedule,
          documents: [_doc('Resume::pdf', 'resume.pdf')],
        ),
      );

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Student ID'),
      );
      expect(field.readOnly, isTrue);
      // Typing directly into the read-only field changes nothing.
      await tester.enterText(
        find.widgetWithText(TextField, 'Student ID'),
        '23B0626',
      );
      expect(field.controller!.text, isEmpty);

      await submit(tester);
      expect(
        find.text(
          'Upload a clear photo of the front of your MarSU school ID so your '
          'Student ID can be scanned.',
        ),
        findsOneWidget,
      );
      expect(store.applications, isEmpty);
    });

    testWidgets('in the Android app the school ID photo uploads unread and '
        'the Student ID is typed', (tester) async {
      final uploads = <String>[];
      await openApplyAgain(
        tester,
        _application(
          status: Application.rejected,
          studentNumber: null,
          schedule: schedule,
          documents: [_doc('Resume::pdf', 'resume.pdf')],
        ),
        webApp: false,
        filePicker: (_) async => PlatformFile(
          name: 'school_id.jpg',
          size: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
        fileUploader: (bytes, path, ext) async {
          uploads.add(path);
          return 'https://example.com/$path';
        },
      );

      final idField = find.widgetWithText(TextField, 'Student ID');
      expect(tester.widget<TextField>(idField).readOnly, isFalse);
      expect(
        find.textContaining('The Head checks it against the photo'),
        findsOneWidget,
      );
      // The class schedule is typed too: its rows can be edited.
      expect(find.text('Add a class'), findsOneWidget);

      await tester.tap(find.text('Upload Document').first);
      await tester.pumpAndSettle();
      expect(uploads, hasLength(1));
      expect(find.textContaining('requires the web app'), findsNothing);

      await tester.enterText(idField, '24a9876');
      await submit(tester);

      final saved = store.applications['app_stu1_2026-2027']!;
      expect(saved.studentNumber, '24A9876');
      expect(saved.schoolIdPhoto?.fileName, 'school_id.jpg');
      // The Head still checks it before screening.
      expect(saved.isStudentIdChecked, isFalse);
    });

    testWidgets('in the Android app a missing Student ID stops the form', (
      tester,
    ) async {
      await openApplyAgain(
        tester,
        _application(
          status: Application.rejected,
          studentNumber: null,
          schedule: schedule,
          documents: [
            _doc('School ID', 'id.jpg'),
            _doc('Resume::pdf', 'resume.pdf'),
          ],
        ),
        webApp: false,
      );
      await tester.enterText(find.widgetWithText(TextField, 'Student ID'), '');

      await submit(tester);

      expect(
        find.text(
          'Type your Student ID as printed on your school ID (like 23B0626).',
        ),
        findsOneWidget,
      );
      expect(store.applications, isEmpty);
    });

    testWidgets('scanning a valid school ID fills Student ID and uploads', (
      tester,
    ) async {
      final uploads = <String>[];
      await openApplyAgain(
        tester,
        _application(
          status: Application.rejected,
          studentNumber: null,
          schedule: schedule,
          documents: [_doc('Resume::pdf', 'resume.pdf')],
        ),
        filePicker: (_) async => PlatformFile(
          name: 'school_id.jpg',
          size: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
        schoolIdReader: (bytes, mime) async {
          expect(mime, 'image/jpeg');
          expect(uploads, isEmpty);
          return const SchoolIdReadResult(ok: true, studentId: '24a9876');
        },
        fileUploader: (bytes, path, ext) async {
          uploads.add(path);
          return 'https://example.com/$path';
        },
      );

      await tester.tap(find.text('Upload Document').first);
      await tester.pumpAndSettle();

      expect(uploads, hasLength(1));
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Student ID'),
      );
      expect(field.controller!.text, '24A9876');
      expect(field.readOnly, isTrue);

      await submit(tester);
      expect(
        store.applications['app_stu1_2026-2027']!.studentNumber,
        '24A9876',
      );
    });

    testWidgets('a non-ID photo is rejected and never uploaded', (
      tester,
    ) async {
      final uploads = <String>[];
      await openApplyAgain(
        tester,
        _application(
          status: Application.rejected,
          studentNumber: null,
          schedule: schedule,
          documents: [_doc('Resume::pdf', 'resume.pdf')],
        ),
        filePicker: (_) async => PlatformFile(
          name: 'selfie.png',
          size: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
        schoolIdReader: (bytes, mime) async => const SchoolIdReadResult(
          ok: false,
          reason: 'This does not look like a MarSU school ID.',
        ),
        fileUploader: (bytes, path, ext) async {
          uploads.add(path);
          return 'https://example.com/$path';
        },
      );

      await tester.tap(find.text('Upload Document').first);
      await tester.pumpAndSettle();

      expect(uploads, isEmpty);
      expect(
        find.text('This does not look like a MarSU school ID.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Student ID'),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('a scanned ID mismatching the profile ID is rejected', (
      tester,
    ) async {
      final uploads = <String>[];
      await openApplyAgain(
        tester,
        user: _student.copyWith(studentId: '23b0626'),
        _application(
          status: Application.rejected,
          studentNumber: null,
          schedule: schedule,
          documents: [_doc('Resume::pdf', 'resume.pdf')],
        ),
        filePicker: (_) async => PlatformFile(
          name: 'other_id.jpg',
          size: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
        schoolIdReader: (bytes, mime) async =>
            const SchoolIdReadResult(ok: true, studentId: '24C1111'),
        fileUploader: (bytes, path, ext) async {
          uploads.add(path);
          return 'https://example.com/$path';
        },
      );

      await tester.tap(find.text('Upload Document').first);
      await tester.pumpAndSettle();

      expect(uploads, isEmpty);
      expect(
        find.textContaining('does not match your account Student ID (23B0626)'),
        findsOneWidget,
      );
    });

    testWidgets('a Student ID on the profile is used, locked', (tester) async {
      await openApplyAgain(
        tester,
        user: _student.copyWith(studentId: '23b0626'),
        _application(
          status: Application.rejected,
          studentNumber: '24C1111',
          schedule: schedule,
          documents: [
            _doc('School ID', 'id.jpg'),
            _doc('Resume::pdf', 'resume.pdf'),
          ],
        ),
      );
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Student ID'),
      );
      expect(field.controller!.text, '23B0626');
      expect(field.readOnly, isTrue);
      expect(
        find.text(
          "From your profile. If it's wrong, ask the Admin to correct it.",
        ),
        findsOneWidget,
      );
      await submit(tester);
      expect(
        store.applications['app_stu1_2026-2027']!.studentNumber,
        '23B0626',
      );
    });

    testWidgets('an ID registered to another account is refused', (
      tester,
    ) async {
      store.claims['23B0626'] = 'someone';
      await openApplyAgain(
        tester,
        _application(
          status: Application.rejected,
          schedule: schedule,
          documents: [
            _doc('School ID', 'id.jpg'),
            _doc('Resume::pdf', 'resume.pdf'),
          ],
        ),
      );
      await submit(tester);
      expect(
        find.textContaining('already registered to another account'),
        findsOneWidget,
      );
      expect(store.applications, isEmpty);
    });

    testWidgets('the Head checks the ID before sending to screening', (
      tester,
    ) async {
      state.applications = [_application()];
      await pump(
        tester,
        const ApplicantScreeningScreen(),
        const Size(1440, 1400),
      );

      expect(find.text('Not checked yet'), findsOneWidget);
      expect(find.text('Check the Student ID first'), findsOneWidget);
      final send = find.widgetWithText(ElevatedButton, 'Send to Screening');
      expect(tester.widget<ElevatedButton>(send).onPressed, isNull);

      await tester.tap(find.text('Student ID checked'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student ID checked').last);
      await tester.pumpAndSettle();

      expect(
        store.applications['app_stu1_2026-2027']!.isStudentIdChecked,
        isTrue,
      );
      expect(find.textContaining('Checked by Helen Head'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(send).onPressed, isNotNull);
    });
  });
}
