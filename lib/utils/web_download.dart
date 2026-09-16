import 'dart:html';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class WebDownloadUtils {
  static void downloadBytes(String fileName, Uint8List bytes) {
    if (!kIsWeb) return;

    final blob = Blob([bytes]);
    final url = Url.createObjectUrlFromBlob(blob);
    final anchor = AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';

    document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    Url.revokeObjectUrl(url);
  }
}
