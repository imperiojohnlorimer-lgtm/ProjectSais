import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/avatar_editor.dart';

// The editor decodes and re-encodes images through the engine. Those
// callbacks never fire inside the FakeAsync zone `testWidgets` runs in, so
// every step that touches an image codec has to happen in `runAsync`.

/// A [width]x[height] PNG whose left half is red and right half is blue, so
/// the crop can be checked by sampling pixels.
Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xFF0000FF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// The pixel at (x, y) as 0xAARRGGBB.
Future<int> _pixelAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  final bytes = data!.buffer.asUint8List();
  return (bytes[offset + 3] << 24) |
      (bytes[offset] << 16) |
      (bytes[offset + 1] << 8) |
      bytes[offset + 2];
}

void main() {
  /// Runs [body] with the engine's real event loop, then settles the UI.
  Future<void> real(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(() async {
      await body();
      // Let the codec / toImage callbacks land before leaving the zone.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  /// Pumps a host with a button that opens the editor, and records what the
  /// editor returns.
  Future<void> pumpHost(
    WidgetTester tester,
    Uint8List source,
    void Function(Uint8List?) onResult,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async =>
                    onResult(await showAvatarEditor(context, source)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await real(tester, () => tester.tap(find.text('open')));
  }

  testWidgets('returns a 512x512 PNG when the crop is accepted', (
    tester,
  ) async {
    late Uint8List source;
    await tester.runAsync(() async => source = await _makePng(400, 200));

    Uint8List? result;
    await pumpHost(tester, source, (r) => result = r);
    expect(find.text('Adjust your photo'), findsOneWidget);

    await real(tester, () => tester.tap(find.text('Use photo')));

    expect(result, isNotNull);
    await tester.runAsync(() async {
      final image = await _decode(result!);
      expect(image.width, 512);
      expect(image.height, 512);
    });
  });

  testWidgets('crops to a square that fills the frame', (tester) async {
    // A 400x200 source at minimum zoom covers the square by scaling on its
    // short side, so the crop is the middle 200x200: left half red, right
    // half blue, with no empty space at any edge.
    late Uint8List source;
    await tester.runAsync(() async => source = await _makePng(400, 200));

    Uint8List? result;
    await pumpHost(tester, source, (r) => result = r);
    await real(tester, () => tester.tap(find.text('Use photo')));

    await tester.runAsync(() async {
      final image = await _decode(result!);
      expect(await _pixelAt(image, 20, 256), 0xFFFF0000);
      expect(await _pixelAt(image, 491, 256), 0xFF0000FF);
      // Corners are covered too — nothing letterboxed in.
      expect((await _pixelAt(image, 2, 2)) >>> 24, 255);
      expect((await _pixelAt(image, 509, 509)) >>> 24, 255);
    });
  });

  testWidgets('panning changes what is kept', (tester) async {
    late Uint8List source;
    await tester.runAsync(() async => source = await _makePng(400, 200));

    Uint8List? centred;
    await pumpHost(tester, source, (r) => centred = r);
    await real(tester, () => tester.tap(find.text('Use photo')));

    Uint8List? panned;
    await pumpHost(tester, source, (r) => panned = r);
    // Drag right: the crop window moves toward the red (left) half.
    await tester.drag(
      find.byKey(const ValueKey('avatar-editor-frame')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    await real(tester, () => tester.tap(find.text('Use photo')));

    expect(panned, isNotNull);
    expect(panned, isNot(equals(centred)));
    await tester.runAsync(() async {
      final image = await _decode(panned!);
      // Far enough right that the previously-blue right edge is now red.
      expect(await _pixelAt(image, 491, 256), 0xFFFF0000);
    });
  });

  testWidgets('cancelling returns null', (tester) async {
    late Uint8List source;
    await tester.runAsync(() async => source = await _makePng(300, 300));

    var called = false;
    Uint8List? result;
    await pumpHost(tester, source, (r) {
      called = true;
      result = r;
    });

    await real(tester, () => tester.tap(find.text('Cancel')));

    expect(called, isTrue);
    expect(result, isNull);
  });

  testWidgets('undecodable bytes throw rather than opening', (tester) async {
    // Callers report upload failures already; returning null here would be
    // indistinguishable from the user cancelling.
    final junk = Uint8List.fromList([1, 2, 3, 4, 5]);
    Object? thrown;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await showAvatarEditor(context, junk);
                  } catch (e) {
                    thrown = e;
                  }
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await real(tester, () => tester.tap(find.text('open')));

    expect(find.text('Adjust your photo'), findsNothing);
    expect(thrown, isNotNull);
  });
}
