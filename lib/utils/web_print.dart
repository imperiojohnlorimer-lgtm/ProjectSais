import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:flutter/foundation.dart';

class WebPrintUtils {
  /// Whether this build can open a print dialog.
  static bool get isSupported => kIsWeb;

  static const _rootId = 'sais-print-root';
  static const _styleId = 'sais-print-style';

  /// Prints [pngBytes] as a single centred page with an optional heading and
  /// caption lines underneath it.
  ///
  /// The sheet is appended to the host page and revealed only inside a
  /// `@media print` block: an iframe or popup would be a cleaner container,
  /// but both get blocked or lose their user-activation after the awaits it
  /// takes to rasterise the QR.
  ///
  /// Throws if the browser refuses to print, so the caller can report it.
  static Future<void> printImage(
    Uint8List pngBytes, {
    String title = '',
    List<String> captions = const [],
  }) async {
    if (!kIsWeb) return;

    // Clear the sheet from an earlier print before building a new one.
    _cleanUp();

    final style = StyleElement()
      ..id = _styleId
      ..text =
          '''
#$_rootId { display: none; }
@media print {
  @page { margin: 16mm; }
  html, body { background: #fff !important; }
  body > *:not(#$_rootId) { display: none !important; }
  #$_rootId {
    display: block !important;
    font-family: Arial, Helvetica, sans-serif;
    color: #0f172a;
    text-align: center;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  #$_rootId h1 { font-size: 20pt; margin: 0 0 6mm; }
  #$_rootId img { width: 120mm; height: 120mm; image-rendering: pixelated; }
  #$_rootId p { font-size: 11pt; color: #475569; margin: 2mm 0 0; }
}''';

    final image = ImageElement(
      src: 'data:image/png;base64,${base64Encode(pngBytes)}',
    );
    final root = DivElement()..id = _rootId;
    if (title.isNotEmpty) root.append(HeadingElement.h1()..text = title);
    root.append(image);
    for (final caption in captions) {
      root.append(ParagraphElement()..text = caption);
    }

    final head = document.head;
    final body = document.body;
    if (head == null || body == null) {
      throw StateError('The page is not ready to print.');
    }
    head.append(style);
    body.append(root);

    try {
      // A browser prints whatever is decoded at the moment print() is called,
      // so an undecoded image would come out as an empty sheet.
      if (image.complete != true) {
        await image.onLoad.first.timeout(const Duration(seconds: 5));
      }
      window.print();
    } finally {
      // Chrome returns from print() once the preview closes; other browsers
      // return straight away, so leave the sheet in place briefly. It is
      // hidden on screen either way.
      Timer(const Duration(seconds: 20), _cleanUp);
    }
  }

  static void _cleanUp() {
    document.getElementById(_rootId)?.remove();
    document.getElementById(_styleId)?.remove();
  }
}
