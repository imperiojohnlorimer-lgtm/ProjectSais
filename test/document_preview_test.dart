import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/applicant_screening_screen.dart';
import 'package:projectsais/services/supabase_storage_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/document_preview.dart';

// A real 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
final _pdf = Uint8List.fromList(ascii.encode('%PDF-1.7\n1 0 obj\n'));

void main() {
  final onError = FlutterError.onError;

  Future<void> open(
    WidgetTester tester, {
    required String fileName,
    required DocumentBytesLoader loader,
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDocumentPreview(
                  context,
                  fileName: fileName,
                  loader: loader,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
  }

  testWidgets('shows a spinner while the file loads, then the picture', (
    tester,
  ) async {
    final gate = Completer<Uint8List>();
    await open(tester, fileName: 'id-photo.png', loader: () => gate.future);

    expect(find.text('Opening id-photo.png…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Nothing to download until there is a file.
    expect(find.text('Download'), findsNothing);

    gate.complete(_png);
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('id-photo.png'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed load says so and Try again loads it again', (
    tester,
  ) async {
    var calls = 0;
    await open(
      tester,
      fileName: 'id.png',
      loader: () async {
        calls++;
        if (calls == 1) throw Exception('offline');
        return _png;
      },
    );
    await tester.pump();

    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
    'a busy or expired link offers Try again, unlike a refused file',
    (tester) async {
      var calls = 0;
      await open(
        tester,
        fileName: 'resume.png',
        loader: () async {
          calls++;
          if (calls == 1) {
            throw const DocumentLoadException(
              'The file could not be loaded (error 503).',
            );
          }
          return _png;
        },
      );
      await tester.pump();

      expect(find.textContaining('error 503'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets('a refusal from the loader is shown as it was worded', (
    tester,
  ) async {
    await open(
      tester,
      fileName: 'big.pdf',
      loader: () async =>
          throw const FormatException('The file is too large to preview.'),
    );
    await tester.pump();
    expect(find.text('The file is too large to preview.'), findsOneWidget);
  });

  testWidgets('an old .doc cannot be previewed but can be downloaded', (
    tester,
  ) async {
    await open(
      tester,
      fileName: 'resume.doc',
      loader: () async => Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 1, 2]),
    );
    await tester.pump();

    expect(find.textContaining("can't be previewed"), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a file that is not what its name says is refused', (
    tester,
  ) async {
    await open(tester, fileName: 'photo.png', loader: () async => _pdf);
    await tester.pump();

    expect(find.text("This file isn't a picture."), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    // Loading it again would give the same file.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a PDF says it cannot be shown here when the build is not a '
      'browser', (tester) async {
    await open(tester, fileName: 'resume.pdf', loader: () async => _pdf);
    await tester.pump();

    expect(find.textContaining("can't show this file here"), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('an answer that arrives after closing does nothing', (
    tester,
  ) async {
    final gate = Completer<Uint8List>();
    await open(tester, fileName: 'id.png', loader: () => gate.future);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    gate.complete(_png);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('id.png'), findsNothing);
  });

  testWidgets('fills the screen on a phone, with Close reachable', (
    tester,
  ) async {
    await open(
      tester,
      fileName: 'id.png',
      loader: () async => _png,
      size: const Size(390, 800),
    );
    await tester.pump();

    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.width, 390);
    expect(dialog.height, 800);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('on the Applications page', () {
    final head = User(
      id: 'h1',
      name: 'John Lori',
      email: 'head@marsu.edu.ph',
      role: 'Head',
    );
    final student = User(
      id: 's1',
      name: 'Kristel Macutong',
      email: 'kristel@gmail.com',
      role: 'Student',
      studentId: '23B0626',
    );

    Application application(List<ApplicationDocument> docs) => Application(
      id: 'app_1',
      announcementId: 'ann1',
      announcementTitle: 'Hiring',
      applicantId: 's1',
      applicantName: 'Kristel Macutong',
      appliedAt: '2026-09-01T00:00:00.000',
      status: 'Pending',
      submittedDocuments: docs,
    );

    ApplicationDocument doc(
      String id,
      String name, {
      Uint8List? bytes,
      String? path,
    }) => ApplicationDocument(
      id: id,
      applicationId: 'app_1',
      requirementName: 'Resume',
      fileName: name,
      uploadedAt: '2026-09-01',
      bytes: bytes,
      storagePath: path,
    );

    Future<void> pumpPage(
      WidgetTester tester,
      List<ApplicationDocument> docs,
    ) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() => FlutterError.onError = onError);
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(details);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState()
            ..currentUser = head
            ..users = [head, student]
            ..applications = [application(docs)],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const Scaffold(body: ApplicantScreeningScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('each document has Preview, not Download, and it opens the '
        'viewer', (tester) async {
      await pumpPage(tester, [doc('d1', 'photo.png', bytes: _png)]);

      expect(find.text('Download'), findsNothing);
      final preview = find.text('Preview');
      expect(preview, findsOneWidget);
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      await tester.tap(preview);
      await tester.pump();
      await tester.pump();

      expect(find.byType(DocumentPreviewDialog), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('a document that only has a storage path opens too, and says '
        'so when the file cannot be fetched', (tester) async {
      await pumpPage(tester, [
        doc('d1', 'resume.pdf', path: 'applications/a.pdf'),
      ]);

      final preview = find.text('Preview');
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      await tester.tap(preview);
      await tester.pump();
      await tester.pump();

      // No Supabase here, so the fetch fails: the Head is told, not left
      // looking at nothing.
      expect(find.byType(DocumentPreviewDialog), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a record with no file says it is unavailable', (tester) async {
      await pumpPage(tester, [doc('d1', 'lost.pdf')]);

      expect(find.text('Preview'), findsNothing);
      final unavailable = find.text('Unavailable');
      expect(unavailable, findsOneWidget);
      await tester.ensureVisible(unavailable);
      await tester.pumpAndSettle();
      await tester.tap(unavailable, warnIfMissed: false);
      await tester.pump();
      expect(find.byType(DocumentPreviewDialog), findsNothing);
    });
  });
}
