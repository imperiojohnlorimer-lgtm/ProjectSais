import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

// A 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Whether any node in the semantics tree is marked as an image.
bool _hasImageNode(WidgetTester tester) {
  var found = false;
  void visit(SemanticsNode node) {
    // ignore: deprecated_member_use
    if (node.getSemanticsData().hasFlag(SemanticsFlag.isImage)) found = true;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return found;
}

void main() {
  testWidgets('the logo tells a screen reader what it is', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLogo())),
    );

    expect(find.bySemanticsLabel('SAIS logo'), findsOneWidget);
    expect(_hasImageNode(tester), isTrue);
    handle.dispose();
  });

  testWidgets('an avatar photo adds no image node beside the name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAvatar(
            avatarUrl: 'data:image/png;base64,${base64Encode(_png)}',
            initials: 'AB',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(_hasImageNode(tester), isFalse);
    handle.dispose();
  });
}
