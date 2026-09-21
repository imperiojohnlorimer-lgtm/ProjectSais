import 'package:flutter/foundation.dart';

class WebPrintUtils {
  /// Whether this build can open a print dialog.
  static bool get isSupported => false;

  static Future<void> printImage(
    Uint8List pngBytes, {
    String title = '',
    List<String> captions = const [],
  }) async {
    // No-op on non-web targets.
  }
}
