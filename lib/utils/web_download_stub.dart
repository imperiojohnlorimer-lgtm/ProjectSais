import 'dart:typed_data';

class WebDownloadUtils {
  static void downloadBytes(String fileName, Uint8List bytes) {
    // No-op on non-web targets.
  }
}
