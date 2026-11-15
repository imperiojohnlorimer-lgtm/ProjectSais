import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads Roboto (what phones draw for SAIS's 'Inter', which isn't bundled)
/// and the Material icons from the Flutter SDK, so a test can measure text
/// as a phone lays it out. Returns false when the SDK's fonts aren't there;
/// the caller should then skip.
Future<bool> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = Directory(
    '${root ?? Platform.resolvedExecutable.split('bin').first}'
    '/bin/cache/artifacts/material_fonts',
  );
  final fallback = Directory(r'C:\src\flutter\bin\cache\artifacts\material_fonts');
  final fonts = dir.existsSync() ? dir : fallback;
  if (!File('${fonts.path}/roboto-regular.ttf').existsSync()) return false;
  Future<ByteData> read(String name) async => ByteData.view(
    Uint8List.fromList(File('${fonts.path}/$name').readAsBytesSync()).buffer,
  );
  const roboto = [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
    'roboto-italic.ttf',
  ];
  for (final family in ['Inter', 'Roboto']) {
    final loader = FontLoader(family);
    for (final f in roboto) {
      loader.addFont(read(f));
    }
    await loader.load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('materialicons-regular.otf'))).load();
  return true;
}

/// The text on screen that was cut at its line limit (an ellipsis), from
/// widgets with a font family (the test font can't be judged).
List<String> cutText(WidgetTester tester) {
  final found = <String>[];
  void visit(RenderObject o) {
    if (o is RenderOffstage && o.offstage) return;
    if (o is RenderIndexedStack) {
      var i = 0;
      o.visitChildren((child) {
        if (i++ == o.index) visit(child);
      });
      return;
    }
    if (o is RenderParagraph &&
        o.hasSize &&
        o.text.style?.fontFamily != null &&
        o.didExceedMaxLines) {
      found.add(o.text.toPlainText());
    }
    o.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return found;
}
