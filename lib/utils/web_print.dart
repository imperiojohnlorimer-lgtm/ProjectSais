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

  /// Prints a list as a table on landscape pages: a small school line, the
  /// [title], the [details] lines, then [rows] (the first row is the
  /// header, repeated on every page). [numeric] marks the columns to align
  /// right. Every piece of text goes in as text, never as HTML, so a name
  /// someone typed can't add markup.
  ///
  /// Throws if the browser refuses to print, so the caller can report it.
  static Future<void> printTable({
    required String title,
    required List<String> details,
    required List<List<String>> rows,
    Set<int> numeric = const {},
  }) async {
    if (!kIsWeb) return;
    _cleanUp();

    final style = StyleElement()
      ..id = _styleId
      ..text =
          '''
#$_rootId { display: none; }
@media print {
  @page { size: A4 landscape; margin: 12mm; }
  html, body { background: #fff !important; }
  body > *:not(#$_rootId) { display: none !important; }
  #$_rootId {
    display: block !important;
    font-family: Arial, Helvetica, sans-serif;
    color: #0f172a;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  #$_rootId .school { font-size: 8.5pt; color: #8b1c3e; font-weight: bold;
    letter-spacing: 0.4pt; margin: 0 0 1.5mm; }
  #$_rootId h1 { font-size: 15pt; margin: 0 0 1.5mm; }
  #$_rootId p { font-size: 8.5pt; color: #475569; margin: 0 0 0.8mm; }
  #$_rootId table { width: 100%; border-collapse: collapse; margin-top: 4mm;
    font-size: 8.5pt; }
  #$_rootId thead { display: table-header-group; }
  #$_rootId tr { break-inside: avoid; page-break-inside: avoid; }
  #$_rootId th { background: #f1f5f9; text-align: left; font-weight: bold;
    border-bottom: 1.2pt solid #8b1c3e; }
  #$_rootId th, #$_rootId td { padding: 1.4mm 2mm; vertical-align: top;
    border-bottom: 0.5pt solid #e2e8f0; overflow-wrap: break-word; }
  #$_rootId tbody tr:nth-child(even) td { background: #f8fafc; }
  #$_rootId .num { text-align: right; white-space: nowrap; }
}''';

    final root = DivElement()..id = _rootId;
    root.append(
      ParagraphElement()
        ..className = 'school'
        ..text =
            'MARINDUQUE STATE UNIVERSITY · SAIS: STUDENT ASSISTANT '
            'INFORMATION SYSTEM',
    );
    root.append(HeadingElement.h1()..text = title);
    for (final line in details) {
      root.append(ParagraphElement()..text = line);
    }
    final table = TableElement();
    if (rows.isNotEmpty) {
      final head = table.createTHead().addRow();
      for (final (i, cell) in rows.first.indexed) {
        final th = Element.tag('th')..text = cell;
        if (numeric.contains(i)) th.className = 'num';
        head.append(th);
      }
      final body = table.createTBody();
      for (final row in rows.skip(1)) {
        final tr = body.addRow();
        for (final (i, cell) in row.indexed) {
          final td = tr.addCell()..text = cell;
          if (numeric.contains(i)) td.className = 'num';
        }
      }
    }
    root.append(table);

    final head = document.head;
    final body = document.body;
    if (head == null || body == null) {
      throw StateError('The page is not ready to print.');
    }
    head.append(style);
    body.append(root);
    try {
      window.print();
    } finally {
      Timer(const Duration(seconds: 20), _cleanUp);
    }
  }

  static void _cleanUp() {
    document.getElementById(_rootId)?.remove();
    document.getElementById(_styleId)?.remove();
  }
}
