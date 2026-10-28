import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// The non-browser build: nothing can be drawn here.
class WebDocumentView {
  const WebDocumentView._();

  static bool get isSupported => false;

  static Widget pdf(Uint8List bytes) => const SizedBox.shrink();

  /// [onReady] and [onError] report how the drawing went ([onError]'s
  /// second argument says whether trying again could help); [onEscape] is
  /// called when Escape is pressed inside the document.
  static Widget docx(
    Uint8List bytes, {
    required VoidCallback onReady,
    required void Function(Object error, bool retryable) onError,
    VoidCallback? onEscape,
  }) => const SizedBox.shrink();

  /// Opens [bytes] in a new browser tab as [mimeType].
  static void openInNewTab(Uint8List bytes, String mimeType) {}
}
