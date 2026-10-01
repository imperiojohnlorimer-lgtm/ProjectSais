import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/head_forwards_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/supabase_storage_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Keeps the reviewed flags the screen saves instead of writing them.
class _Store extends FirestoreService {
  final reviewed = <String, bool>{};

  @override
  Future<void> setHeadForwardReviewed(String id, bool value) async =>
      reviewed[id] = value;

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async {}
}

final _head = User(
  id: 'head1',
  name: 'Helen Head',
  email: 'helen@marsu.edu.ph',
  role: 'Head',
);

void main() {
  group('pathFromSignedUrl', () {
    test('reads the file path out of a signed storage link', () {
      expect(
        SupabaseStorageService.pathFromSignedUrl(
          'https://hksswjhioztqsypbrkjy.supabase.co/storage/v1/object/sign/'
          'Documents/reports/SMNKkY6CSbW2w1OaWGWbjSz76Rr1/1789634453298/'
          'performance-evaluation-charlie.docx?token=abc.def.ghi',
        ),
        'reports/SMNKkY6CSbW2w1OaWGWbjSz76Rr1/1789634453298/'
        'performance-evaluation-charlie.docx',
      );
    });

    test('decodes an escaped path', () {
      expect(
        SupabaseStorageService.pathFromSignedUrl(
          'https://x.supabase.co/storage/v1/object/sign/Documents/'
          'reports/u/1/My%20File.pdf?token=t',
        ),
        'reports/u/1/My File.pdf',
      );
    });

    test('is null for anything else', () {
      for (final url in [
        null,
        '',
        'data:application/pdf;base64,AAAA',
        'https://example.com/file.pdf',
        'https://x.supabase.co/storage/v1/object/sign/Other/reports/a.pdf',
        'https://x.supabase.co/storage/v1/object/sign/Documents',
      ]) {
        expect(
          SupabaseStorageService.pathFromSignedUrl(url),
          isNull,
          reason: url,
        );
      }
    });
  });

  testWidgets('a forwarded item can be marked reviewed and back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = _Store();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(firestoreService: store)
          ..currentUser = _head
          ..users = [_head]
          ..headForwards = [
            HeadForward(
              id: 'f1',
              type: 'evaluation',
              studentId: 's1',
              studentName: 'Charlie A. Matining',
              title: 'Performance Evaluation (First Semester)',
              fileName: 'performance-evaluation-charlie.docx',
              storagePath: 'reports/u/1/performance-evaluation-charlie.docx',
              sentByName: 'Test Supervisor',
              sentById: 'sup1',
              sentAt: 'Sep 17, 2026',
            ),
          ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: HeadForwardsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charlie A. Matining'));
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsOneWidget);
    await tester.tap(find.text('Mark as reviewed'));
    await tester.pumpAndSettle();
    expect(store.reviewed['f1'], isTrue);
    expect(find.text('Reviewed'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reviewed'));
    await tester.pumpAndSettle();
    expect(store.reviewed['f1'], isFalse);
    expect(find.text('Mark as reviewed'), findsOneWidget);
  });
}
