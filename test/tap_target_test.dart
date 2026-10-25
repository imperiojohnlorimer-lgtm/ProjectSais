import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

void main() {
  Future<void> pumpTarget(
    WidgetTester tester, {
    required VoidCallback onTap,
    bool selected = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: TapTarget(
            label: 'Attendance',
            selected: selected,
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Attendance'),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('a tap activates it', (tester) async {
    var taps = 0;
    await pumpTarget(tester, onTap: () => taps++);

    await tester.tap(find.text('Attendance'));

    expect(taps, 1);
  });

  testWidgets('Tab reaches it and Enter or Space activates it', (tester) async {
    var taps = 0;
    await pumpTarget(tester, onTap: () => taps++);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(taps, 2);
  });

  testWidgets('a screen reader hears a button named by its text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTarget(tester, onTap: () {}, selected: true);

    final node = tester.getSemantics(find.byType(TapTarget));

    expect(node.label, 'Attendance');
    expect(
      node.flagsCollection.isButton,
      isTrue,
      reason: 'it is announced as a button',
    );
    expect(node.flagsCollection.isSelected.name, 'isTrue');
    handle.dispose();
  });
}
