import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/accounts_screen.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:provider/provider.dart';

final _admin = User(
  id: 'a1',
  name: 'Ana Admin',
  firstName: 'Ana',
  lastName: 'Admin',
  email: 'ana@example.com',
  role: 'Admin',
);

final _head = User(
  id: 'h1',
  name: 'Helen Garcia',
  firstName: 'Helen',
  lastName: 'Garcia',
  email: 'helen@example.com',
  role: 'Head',
);

void main() {
  testWidgets('the four row buttons fit inside the Actions column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so other cells
    // overflow here though they fit in the app; only the buttons matter.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('overflowed')) {
        onError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = onError);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState()
          ..currentUser = _admin
          ..users = [_admin, _head],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: AccountsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Each button used to be padded out to 48 px, so four of them (192 px)
    // pushed the bin icon out of the 144 px column and past the table.
    for (final tip in const [
      'View profile',
      'Edit account',
      'Archive account',
      'Delete account permanently',
    ]) {
      final button = find.ancestor(
        of: find.byTooltip(tip).last,
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(button.first), const Size(36, 36), reason: tip);
    }
    final actionsHeader = tester.getRect(find.text('ACTIONS'));
    final bin = tester.getRect(find.byTooltip('Delete account permanently'));
    expect(bin.right, lessThanOrEqualTo(actionsHeader.center.dx + 72 + 1));
  });
}
