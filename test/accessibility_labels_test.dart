import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

// A 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('the logo tells a screen reader what it is', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLogo())),
    );

    expect(find.bySemanticsLabel('SAIS logo'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an avatar photo adds nothing beside the name', (tester) async {
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

    // No image node of its own: the person is named in the text next to it.
    expect(
      tester.getSemantics(find.byType(UserAvatar)).label,
      isNot(contains('image')),
    );
    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
    handle.dispose();
  });
}
