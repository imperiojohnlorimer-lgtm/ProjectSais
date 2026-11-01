import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

Widget _host(Widget header) =>
    MaterialApp(home: Scaffold(body: header));

void main() {
  testWidgets('shows the title and the line under it, with a Close button', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      _host(
        LightDialogHeader(
          icon: Icons.campaign_outlined,
          title: 'Announcement Details',
          subtitle: 'View the full announcement information.',
          onClose: () => closed++,
        ),
      ),
    );

    expect(find.text('Announcement Details'), findsOneWidget);
    expect(find.text('View the full announcement information.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    expect(closed, 1);
  });

  testWidgets('has no gradient band, and no line under it when none is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LightDialogHeader(
          icon: Icons.campaign_outlined,
          title: 'Add Office',
          onClose: () {},
        ),
      ),
    );

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    expect(decorations.any((d) => d.gradient != null), isFalse);
    expect(find.text('Add Office'), findsOneWidget);
  });

  testWidgets('cannot be closed while the dialog is busy', (tester) async {
    await tester.pumpWidget(
      _host(
        const LightDialogHeader(
          icon: Icons.campaign_outlined,
          title: 'Request Student Assistant',
          onClose: null,
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('a long title wraps inside a phone-width dialog', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const title = 'Maria Cristina Dela Cruz-Santos de los Reyes III';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: LightDialogHeader(
                    icon: Icons.rate_review_rounded,
                    title: title,
                    subtitle:
                        '2nd Semester, AY 2026-2027 • College of Information and Computing Sciences',
                    onClose: () {},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Inside the dialog's 310 px the title takes a second line instead of
    // running off the edge.
    expect(tester.getSize(find.text(title)).height, greaterThan(30));
    expect(tester.getSize(find.byType(LightDialogHeader)).width, lessThan(391));
  });
}
