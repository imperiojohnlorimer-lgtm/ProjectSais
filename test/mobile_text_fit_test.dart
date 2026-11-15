import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';

import '../tool/mobile_audit/seed.dart';
import 'support/real_fonts.dart';

/// Pages that cut names, offices and page titles on a phone, measured with
/// the font a phone actually draws (Roboto), at 360 px wide: none of these
/// may be cut, and nothing may overflow. (tool/mobile_audit checks every
/// page; this keeps the ones fixed from coming back.)
void main() {
  var fonts = false;
  setUpAll(() async => fonts = await loadRealFonts());

  final pages = <(String role, String tab, List<String> whole)>[
    // The page name in the phone header, beside the bell and avatar.
    ('Head', 'payroll_requirements', ['Payroll Requirements']),
    ('Head', 'applications', ['Applications & Screening']),
    // Long names on the list cards.
    ('Supervisor', 'students', [assistant.name, assistant2.name]),
    ('Head', 'rehiring', [assistant2.name]),
    ('Admin', 'accounts', [head.name, supervisor.name, assistant.name]),
  ];

  for (final (role, tab, whole) in pages) {
    testWidgets('$role $tab fits a 360 px phone', (tester) async {
      if (!fonts) {
        markTestSkipped("the Flutter SDK's Roboto isn't available here");
        return;
      }
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final overflows = <String>[];
      final onError = FlutterError.onError;
      FlutterError.onError = (details) {
        final message = details.exceptionAsString();
        if (message.contains('overflowed')) {
          overflows.add(message.split('\n').first);
        }
      };
      addTearDown(() => FlutterError.onError = onError);
      final state = seededState(role)..activeTab = tab;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider(
              create: (_) => ScheduleService(InMemoryScheduleRepository()),
            ),
          ],
          child: MaterialApp(theme: AppTheme.theme, home: const AppShell()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final cut = cutText(tester);
      for (final text in whole) {
        expect(find.textContaining(text), findsWidgets, reason: text);
        expect(cut.where((c) => c.contains(text)), isEmpty, reason: text);
      }
      expect(overflows, isEmpty);
      FlutterError.onError = onError;
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
}
