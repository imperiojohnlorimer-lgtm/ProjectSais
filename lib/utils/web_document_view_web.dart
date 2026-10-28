import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('saisConfigureDocxFrame')
external JSPromise<JSAny?> _configureDocxFrame(web.HTMLIFrameElement frame);

@JS('saisRenderDocx')
external JSPromise<JSAny?> _renderDocx(
  JSUint8Array bytes,
  web.HTMLIFrameElement frame,
);

/// The browser build: a PDF in the browser's own viewer, a Word file drawn by
/// the vendored docx-preview (web/docx-preview/). See web/docx-preview/README.md
/// for why the Word file is drawn in a sandboxed frame.
class WebDocumentView {
  const WebDocumentView._();

  static bool get isSupported => true;

  static Widget pdf(Uint8List bytes) => _PdfFrame(bytes: bytes);

  static Widget docx(
    Uint8List bytes, {
    required VoidCallback onReady,
    required void Function(Object error, bool retryable) onError,
    VoidCallback? onEscape,
  }) => _DocxFrame(
    bytes: bytes,
    onReady: onReady,
    onError: onError,
    onEscape: onEscape,
  );

  static void openInNewTab(Uint8List bytes, String mimeType) {
    final url = _blobUrl(bytes, mimeType);
    web.window.open(url, '_blank', 'noopener');
    // The new tab has its own hold on the file by the time it loads.
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  }
}

String _blobUrl(Uint8List bytes, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  return web.URL.createObjectURL(blob);
}

class _PdfFrame extends StatefulWidget {
  final Uint8List bytes;
  const _PdfFrame({required this.bytes});

  @override
  State<_PdfFrame> createState() => _PdfFrameState();
}

class _PdfFrameState extends State<_PdfFrame> {
  // The type is ours, never the server's, and the bytes were checked to
  // start like a PDF before they got here.
  late final String _url = _blobUrl(widget.bytes, 'application/pdf');

  @override
  void dispose() {
    web.URL.revokeObjectURL(_url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.style
          ..border = '0'
          ..width = '100%'
          ..height = '100%';
        frame.title = 'PDF preview';
        frame.src = _url;
      },
    );
  }
}

Future<void>? _scripts;

/// Loads the Word viewer's scripts the first time one is needed; a failed
/// load can be tried again.
Future<void> _loadScripts() {
  return _scripts ??= () async {
    try {
      for (final src in const [
        'docx-preview/jszip.min.js',
        'docx-preview/docx-preview.min.js',
        'docx-preview/sais-docx.js',
      ]) {
        final done = Completer<void>();
        final script = web.HTMLScriptElement()
          ..src = src
          ..async = false;
        script.onload = ((web.Event _) => done.complete()).toJS;
        script.onerror = ((web.Event _) => done.completeError(
          StateError('The Word viewer could not be loaded.'),
        )).toJS;
        web.document.head!.append(script);
        await done.future;
      }
    } catch (_) {
      _scripts = null;
      rethrow;
    }
  }();
}

class _DocxFrame extends StatefulWidget {
  final Uint8List bytes;
  final VoidCallback onReady;
  final void Function(Object error, bool retryable) onError;
  final VoidCallback? onEscape;

  const _DocxFrame({
    required this.bytes,
    required this.onReady,
    required this.onError,
    this.onEscape,
  });

  @override
  State<_DocxFrame> createState() => _DocxFrameState();
}

class _DocxFrameState extends State<_DocxFrame> {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _draw(web.HTMLIFrameElement frame) async {
    try {
      await _loadScripts();
    } catch (error) {
      // The viewer's scripts did not arrive (a passing network problem).
      if (!_disposed) widget.onError(error, true);
      return;
    }
    try {
      await _configureDocxFrame(frame).toDart;
      frame.addEventListener(
        'sais-escape',
        ((web.Event _) => widget.onEscape?.call()).toJS,
      );
      await _renderDocx(widget.bytes.toJS, frame).toDart;
      if (!_disposed) widget.onReady();
    } catch (error) {
      // This file will not draw, however often it is tried.
      if (!_disposed) widget.onError(error, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.style
          ..border = '0'
          ..width = '100%'
          ..height = '100%';
        frame.title = 'Word document preview';
        _draw(frame);
      },
    );
  }
}
