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
    VoidCallback? onShowPrivacy,
    double textScale = 1.0,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: LandingScreen(
          onSignIn: onSignIn ?? () {},
          onGetStarted: onGetStarted ?? () {},
          onShowPrivacy: onShowPrivacy,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Scrolls [finder] into view, then a little further, so it is not under the
  // sticky header when it is tapped.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
  }

  // Every breakpoint the layout switches on (400 inline Apply, 900 mobile,
  // 1100 drawer, 1180 wide), the narrowest phone, and the extremes.
  const widths = [
    320.0,
    360.0,
    390.0,
    399.0,
    400.0,
    640.0,
    768.0,
    899.0,
    900.0,
    1023.0,
    1024.0,
    1099.0,
    1100.0,
    1179.0,
    1180.0,
    1440.0,
    1920.0,
  ];

  for (final width in widths) {
    testWidgets('lays out without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpAt(tester, Size(width, 900), onShowPrivacy: () {});
      expect(tester.takeException(), isNull);
      expect(find.text('SAIS'), findsWidgets);
    });
  }

  // The test font draws every glyph as a wide square, so 1.3x here is far
  // harsher than 1.3x in the app.
  for (final width in const [390.0, 1100.0, 1440.0]) {
    testWidgets('survives larger text at ${width.toInt()}px', (tester) async {
      await pumpAt(tester, Size(width, 900), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('lays out on a short wide window', (tester) async {
    await pumpAt(tester, const Size(1280, 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows every section, and leads with the hiring', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.text('Work on campus.\nEarn while you learn.'), findsOneWidget);
    expect(find.text('Why be a Student Assistant?'), findsOneWidget);
    expect(
      find.text('Four steps from sign-up to your first shift'),
      findsOneWidget,
    );
    expect(find.text('What to have ready'), findsOneWidget);
    expect(find.text('Questions students ask'), findsOneWidget);
    expect(find.text('Ready to apply?'), findsOneWidget);
    expect(
      find.text('Running the program? SAIS handles the rest.'),
      findsOneWidget,
    );
  });

  testWidgets('never claims that hiring is open, and says what Apply does', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.textContaining('Now hiring'), findsNothing);
    expect(find.textContaining('Applications are open'), findsNothing);
    expect(find.textContaining('open until'), findsNothing);
    expect(find.textContaining('Apply now opens registration'), findsOneWidget);
  });

  testWidgets('collapses nav into a drawer on phones, with Apply in it', (
    tester,
  ) async {
    var start = 0;
    await pumpAt(tester, const Size(390, 844), onGetStarted: () => start++);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    Finder inDrawer(String label) =>
        find.descendant(of: find.byType(Drawer), matching: find.text(label));
    expect(inDrawer('Why join'), findsOneWidget);
    expect(inDrawer('How to apply'), findsOneWidget);
    expect(inDrawer('FAQ'), findsOneWidget);
    expect(inDrawer('For offices'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.widgetWithText(ElevatedButton, 'Apply now'),
      ),
    );
    await tester.pumpAndSettle();
    expect(start, 1);
  });

  testWidgets('every Apply button opens registration, Sign in signs in', (
    tester,
  ) async {
    var start = 0;
    var signIn = 0;
    await pumpAt(
      tester,
      const Size(1440, 900),
      onSignIn: () => signIn++,
      onGetStarted: () => start++,
    );

    // Press the buttons themselves: the sticky header covers whatever is
    // scrolled to the top, so a tap by position can land on the header.
    Future<int> pressAll(Finder finder) async {
      final count = finder.evaluate().length;
      expect(count, greaterThan(0), reason: finder.toString());
      for (var i = 0; i < count; i++) {
        tester.widget<ButtonStyleButton>(finder.at(i)).onPressed!();
        await tester.pumpAndSettle();
      }
      return count;
    }

    // Header, hero and the how-to-apply step list.
    final applied = await pressAll(
      find.widgetWithText(ElevatedButton, 'Apply now'),
    );
    expect(applied, 3);
    await pressAll(find.widgetWithText(ElevatedButton, 'Create my account'));
    await pressAll(find.widgetWithText(TextButton, 'Apply now')); // footer
    expect(start, 5);
    expect(signIn, 0);

    await pressAll(
      find.widgetWithText(OutlinedButton, 'I already have an account'),
    );
    await pressAll(find.widgetWithText(OutlinedButton, 'Sign in'));
    await pressAll(
      find.widgetWithText(TextButton, 'Sign in'),
    ); // header, footer
    await pressAll(find.widgetWithText(OutlinedButton, 'Staff sign in'));
    expect(signIn, 5);
    // None of the sign-in buttons started an application.
    expect(start, 5);
  });

  testWidgets('the Privacy Notice links go to the privacy page', (
    tester,
  ) async {
    var privacy = 0;
    await pumpAt(tester, const Size(1440, 900), onShowPrivacy: () => privacy++);
    final footer = find.widgetWithText(TextButton, 'Privacy Notice');
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    await tester.tap(footer);
    await tester.pumpAndSettle();
    expect(privacy, 1);

    final question = find.text('Is my information private?');
    await reveal(tester, question);
    await tester.tap(question);
    await tester.pumpAndSettle();
    final inAnswer = find.widgetWithText(TextButton, 'Read the Privacy Notice');
    tester.widget<TextButton>(inAnswer).onPressed!();
    expect(privacy, 2);
  });

  testWidgets('no Privacy link when there is nowhere to go', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.text('Privacy Notice'), findsNothing);
  });

  testWidgets('FAQ answers open and close', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    final question = find.text('Can I choose the office I work in?');
    await reveal(tester, question);
    expect(find.textContaining('not to one office'), findsNothing);

    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(find.textContaining('not to one office'), findsOneWidget);

    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(find.textContaining('not to one office'), findsNothing);
  });

  testWidgets('a nav link scrolls the section to just under the header', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1440, 900));
    final heading = find.text('Four steps from sign-up to your first shift');
    // Far below the first screen until the link is used.
    expect(tester.getTopLeft(heading).dy, greaterThan(1200));

    await tester.tap(find.widgetWithText(TextButton, 'How to apply'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(1000));
    // Just under the 76 px header (the section's own padding follows), not
    // hidden behind it and not left off-screen.
    final top = tester.getTopLeft(heading).dy;
    expect(top, inInclusiveRange(76, 300));
  });

  testWidgets('drawer links scroll too, and the drawer fits a short window', (
    tester,
  ) async {
    await pumpAt(tester, const Size(844, 390));
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final faq = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('FAQ'),
    );
    await tester.ensureVisible(faq);
    await tester.pumpAndSettle();
    await tester.tap(faq);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(1000));
  });

  testWidgets('jumps instead of animating when the system asks for less '
      'motion', (tester) async {
    await pumpAt(tester, const Size(1440, 900), reduceMotion: true);
    await tester.tap(find.widgetWithText(TextButton, 'FAQ'));
    // One frame, with no animation to wait out.
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(500));
  });
}
