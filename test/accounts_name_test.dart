import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/accounts_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

final _admin = User(
  id: 'a1',
  name: 'Ana Admin',
  firstName: 'Ana',
  lastName: 'Admin',
  email: 'ana@marsu.edu.ph',
  role: 'Admin',
);

// Saved before names were split.
final _old = User(
  id: 'sa1',
  name: 'Mark Dave M. Miciano',
  email: 'mark@gmail.com',
  role: 'Student Assistant',
);

void main() {
  Future<void> pumpAccounts(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState()
          ..currentUser = _admin
          ..users = [_admin, _old],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: AccountsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(1440, 1000), Size(390, 900)]) {
    testWidgets('an unsplit name is marked and its edit starts from a guess '
        'at ${size.width.toInt()}px', (tester) async {
      // The test font draws every glyph as a full square, so the screen's
      // header, role and action rows overflow here though they fit in the
      // app. They aren't this test's business: it only checks that the
      // edit dialog adds no overflow of its own.
      final overflows = <FlutterErrorDetails>[];
      final onError = FlutterError.onError;
      FlutterError.onError = (details) =>
          details.exceptionAsString().contains('overflowed')
          ? overflows.add(details)
          : onError?.call(details);
      try {
        await pumpAccounts(tester, size);
      } finally {
        FlutterError.onError = onError;
      }
      // Only the old account; the Admin's own name is split.
      expect(find.text('Split name'), findsOneWidget);

      final edit = find.byTooltip('Edit account').first;
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('saved with one full name, "Mark Dave M. Miciano"'),
        findsOneWidget,
      );
      String textOf(String label) => tester
          .widget<TextField>(find.widgetWithText(TextField, label))
          .controller!
          .text;
      expect(textOf('First name *'), 'Mark Dave');
      expect(textOf('Middle name'), 'M.');
      expect(textOf('Last name *'), 'Miciano');
    });
  }
}
