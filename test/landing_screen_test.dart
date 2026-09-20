import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/screens/landing/landing_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    VoidCallback? onSignIn,
    VoidCallback? onGetStarted,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: LandingScreen(
          onSignIn: onSignIn ?? () {},
          onGetStarted: onGetStarted ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Every breakpoint the layout switches on, plus the extremes either side.
  const widths = [320.0, 390.0, 640.0, 768.0, 899.0, 900.0, 1024.0, 1179.0,
      1180.0, 1440.0, 1920.0];

  for (final width in widths) {
    testWidgets('lays out without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpAt(tester, Size(width, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('SAIS'), findsWidgets);
    });
  }

  testWidgets('shows every section', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.text('Every stage of the program, in one place'), findsOneWidget);
    expect(find.text('One system, four points of view'), findsOneWidget);
    expect(
      find.text('From application to payroll in four steps'),
      findsOneWidget,
    );
    expect(find.text('Ready to get your office on SAIS?'), findsOneWidget);
  });

  testWidgets('collapses nav into a drawer on phones', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Features'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
  });

  testWidgets('hero actions fire their callbacks', (tester) async {
    var signIn = 0;
    var start = 0;
    await pumpAt(
      tester,
      const Size(1440, 900),
      onSignIn: () => signIn++,
      onGetStarted: () => start++,
    );
    await tester.tap(find.text('Get started').first);
    await tester.tap(find.text('Sign in to your account'));
    await tester.pumpAndSettle();
    expect(start, 1);
    expect(signIn, 1);
  });
}
