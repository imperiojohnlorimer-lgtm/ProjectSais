import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/recurring_schedule.dart';
import 'package:projectsais/models/schedule_event.dart';
import 'package:projectsais/screens/accounts/schedule_requests_screen.dart';
import 'package:projectsais/screens/calendar/calendar_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/class_schedule_editor.dart';

class _NoEvents implements ScheduleRepository {
  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerId) async => [];

  @override
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerId) =>
      const Stream.empty();

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async => event;

  @override
  Future<void> deleteEvent(String id) async {}
}

class _Store extends FirestoreService {
  final updates = <String, Map<String, dynamic>>{};
  int versionsAdded = 0;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {}

  @override
  Future<void> updateScheduleRequest(String id, Map<String, dynamic> f) async =>
      updates[id] = f;

  @override
  Future<OwnerSchedule> getOwnerSchedule(String ownerId) async =>
      const OwnerSchedule();

  @override
  Future<String> addClassScheduleVersion({
    required String ownerId,
    required String ownerName,
    required ClassScheduleVersion version,
    String? requestId,
    Map<String, dynamic>? requestFields,
  }) async {
    versionsAdded++;
    return 'saved';
  }
}

RecurringScheduleRule _subject(String label, int weekday) =>
    RecurringScheduleRule(
      id: 'r_$label$weekday',
      ownerName: 'Sia Assistant',
      label: label,
      weekday: weekday,
      startTime: const TimeOfDay(hour: 8, minute: 0),
      endTime: const TimeOfDay(hour: 10, minute: 0),
      color: Colors.blue,
      icon: Icons.school_outlined,
      isSubject: true,
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
  group('class schedule editor', () {
    Future<ClassScheduleController> pumpEditor(
      WidgetTester tester, {
      required ScheduleFileReader reader,
      List<String>? uploads,
      bool readOnly = true,
      bool withFile = true,
    }) async {
      final controller = ClassScheduleController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClassScheduleEditor(
                controller: controller,
                ownerId: 'sa',
                withFile: withFile,
                readOnly: readOnly,
                picker: () async => PlatformFile(
                  name: 'my schedule.png',
                  size: 4,
                  bytes: Uint8List.fromList([1, 2, 3, 4]),
                ),
                uploader: (bytes, path, ext) async => uploads?.add(path),
                reader: reader,
              ),
            ),
          ),
        ),
      );
      if (withFile) {
        await tester.tap(find.textContaining('Choose your class schedule'));
        await tester.pumpAndSettle();
      }
      return controller;
    }

    testWidgets('scans first into read-only rows, then uploads', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();
      final uploads = <String>[];
      final controller = await pumpEditor(
        tester,
        uploads: uploads,
        reader: (bytes, type) async {
          expect(type, 'image/png');
          // Upload must not start before scan completes.
          expect(uploads, isEmpty);
          return const ScheduleReadResult(
            ok: true,
            meetings: [
              ScheduleMeeting(
                title: 'Systems Analysis',
                weekday: 1,
                start: 480,
                end: 660,
                mode: 'Online',
              ),
              ScheduleMeeting(
                title: 'Networks',
                weekday: 4,
                start: 810,
                end: 930,
                room: 'CL5',
                check: true,
              ),
            ],
          );
        },
      );
      expect(uploads.single, startsWith('schedules/sa/'));
      expect(controller.hasFile, isTrue);
      expect(controller.rows, hasLength(2));
      expect(find.text('Systems Analysis'), findsOneWidget);
      expect(find.textContaining('Scanned 2 classes'), findsOneWidget);
      // Read-only: no text fields, no Add a class, no Read again, no delete.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Add a class'), findsNothing);
      expect(find.text('Read again'), findsNothing);
      expect(find.byTooltip('Remove this class'), findsNothing);
      expect(controller.problems(), isEmpty);
      final subjects = controller.subjects(
        ownerName: 'Sia Assistant',
        academicYear: '2026-2027',
      );
      expect(subjects.map((s) => s.weekday), [1, 4]);
      expect(subjects.last.room, 'CL5');
    });

    testWidgets('cancelling the scan skips uploading', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();
      final read = Completer<ScheduleReadResult>();
      final uploads = <String>[];
      final controller = ClassScheduleController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClassScheduleEditor(
                controller: controller,
                ownerId: 'sa',
                readOnly: true,
                picker: () async => PlatformFile(
                  name: 'my schedule.png',
                  size: 4,
                  bytes: Uint8List.fromList([1, 2, 3, 4]),
                ),
                uploader: (bytes, path, ext) async => uploads.add(path),
                reader: (bytes, type) => read.future,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.textContaining('Choose your class schedule'));
      await tester.pump();
      expect(controller.busy, isTrue);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(controller.busy, isFalse);
      expect(controller.hasFile, isFalse);
      expect(controller.rows, isEmpty);
      expect(uploads, isEmpty);
      // The stopped read finishing late changes nothing.
      read.complete(
        const ScheduleReadResult(
          ok: true,
          meetings: [
            ScheduleMeeting(title: 'Late', weekday: 1, start: 480, end: 540),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.rows, isEmpty);
      expect(uploads, isEmpty);
    });

    testWidgets('an unreadable or non-schedule file is rejected and not uploaded', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();
      final uploads = <String>[];
      final controller = await pumpEditor(
        tester,
        uploads: uploads,
        reader: (bytes, type) async =>
            const ScheduleReadResult(ok: false, meetings: []),
      );
      expect(find.textContaining('was not accepted'), findsOneWidget);
      expect(controller.hasFile, isFalse);
      expect(controller.rows, isEmpty);
      expect(uploads, isEmpty);
      expect(controller.problems(), contains('Choose your class schedule file.'));
    });

    testWidgets('Head edit mode stays editable without a file', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();
      final controller = ClassScheduleController(
        rows: [
          ClassMeetingRow(
            title: 'Math 1',
            weekday: 1,
            start: const TimeOfDay(hour: 8, minute: 0),
            end: const TimeOfDay(hour: 10, minute: 0),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClassScheduleEditor(
                controller: controller,
                ownerId: 'sa',
                withFile: false,
                readOnly: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Add a class'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('calendar', () {
    Future<void> pumpCalendar(WidgetTester tester, User user) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>(
              create: (_) => AppState()
                ..currentUser = user
                ..users = [user],
            ),
            ChangeNotifierProvider<ScheduleService>(
              create: (_) => ScheduleService(_NoEvents()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: CalendarScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an assistant uploads a schedule instead of typing subjects', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        User(
          id: 'sa',
          name: 'Sia Assistant',
          email: 'a@x.com',
          role: 'Student Assistant',
        ),
      );
      expect(find.text('Add Subject'), findsNothing);
      expect(find.text('Add Schedule'), findsNothing);
      expect(find.text('Add Event'), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(find.text('Upload schedule'), findsOneWidget);
    });

    testWidgets('a Supervisor\'s own calendar still has Add Subject', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        User(
          id: 'sup',
          name: 'Sam Supervisor',
          email: 's@x.com',
          role: 'Supervisor',
        ),
      );
      expect(find.text('Add Subject'), findsOneWidget);
      expect(find.text('Add Schedule'), findsOneWidget);
      expect(find.text('Add Event'), findsOneWidget);
      expect(find.text('Upload schedule'), findsNothing);
    });
  });

  group('Schedule Requests page', () {
    testWidgets('the Head compares and approves a new schedule', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreOverflow();
      final store = _Store();
      final head = User(
        id: 'head',
        name: 'Hana Head',
        email: 'h@x.com',
        role: 'Head',
      );
      final sa = User(
        id: 'sa',
        name: 'Sia Assistant',
        email: 'a@x.com',
        role: 'Student Assistant',
      );
      final state = AppState(firestoreService: store)
        ..currentUser = head
        ..users = [head, sa]
        ..scheduleRequests = [
          ScheduleRequest(
            id: 'sa_1',
            studentId: 'sa',
            studentName: 'Sia Assistant',
            academicYear: '2026-2027',
            fileName: 'new.png',
            filePath: 'schedules/sa/1/a.png',
            subjects: [_subject('Networks', 2)],
            effectiveFrom: '2026-11-20',
            note: 'New semester',
            submittedAt: DateTime.utc(2026, 11, 19),
          ),
        ];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<ScheduleService>(
              create: (_) => ScheduleService(_NoEvents()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: ScheduleRequestsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The card starts closed: who, when, and a one-line summary.
      expect(find.text('Sia Assistant'), findsOneWidget);
      expect(find.text('1 subject'), findsOneWidget);
      expect(find.text('Networks'), findsNothing);
      expect(find.text('Approve'), findsNothing);

      // A tap opens the classes and the buttons; another closes them.
      await tester.tap(find.text('Sia Assistant'));
      await tester.pumpAndSettle();
      expect(find.text('Networks'), findsOneWidget);
      await tester.tap(find.text('Sia Assistant'));
      await tester.pumpAndSettle();
      expect(find.text('Networks'), findsNothing);
      await tester.tap(find.text('Sia Assistant'));
      await tester.pumpAndSettle();

      expect(find.text('Note: New semester'), findsOneWidget);
      expect(find.text('Networks'), findsOneWidget);
      expect(find.text('No approved class schedule yet.'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve').last);
      await tester.pumpAndSettle();
      expect(store.versionsAdded, 1);
      expect(find.text('Approved.'), findsOneWidget);
      expect(find.text('No new class schedules are waiting.'), findsOneWidget);
    });
  });
}
