import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/supabase_storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/document_kind.dart';
import '../utils/web_document_view.dart';
import '../utils/web_download_stub.dart'
    if (dart.library.html) '../utils/web_download.dart'
    as web_download;
import 'shared_widgets.dart';

/// Gets the bytes of the file being previewed. Tests pass their own.
typedef DocumentBytesLoader = Future<Uint8List> Function();

/// Opens [fileName] in a viewer over the page, so it can be read before it is
/// downloaded. The file comes from [bytes] when the record carries them, else
/// from storage ([storagePath], or the path inside an older saved signed link
/// [storedUrl]). Pictures, PDFs and Word (.docx) files are shown; any other
/// file says so and offers Download.
Future<void> showDocumentPreview(
  BuildContext context, {
  required String fileName,
  String? storagePath,
  String? storedUrl,
  Uint8List? bytes,
  @visibleForTesting DocumentBytesLoader? loader,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => DocumentPreviewDialog(
      fileName: fileName,
      loader:
          loader ??
          (bytes != null && bytes.isNotEmpty
              ? () async => bytes
              : () => SupabaseStorageService.instance.fetchDocumentBytes(
                  path: storagePath,
                  storedUrl: storedUrl,
                )),
    ),
  );
}

enum _Phase { loading, ready, failed, unsupported }

class DocumentPreviewDialog extends StatefulWidget {
  final String fileName;
  final DocumentBytesLoader loader;

  const DocumentPreviewDialog({
    super.key,
    required this.fileName,
    required this.loader,
  });

  @override
  State<DocumentPreviewDialog> createState() => _DocumentPreviewDialogState();
}

class _DocumentPreviewDialogState extends State<DocumentPreviewDialog> {
  _Phase _phase = _Phase.loading;
  Uint8List? _bytes;
  String _message = '';

  /// Whether the failure could be a passing one (so Try again makes sense),
  /// not a file that will never open.
  bool _canRetry = true;

  /// Whether the Word viewer has drawn the file yet (it spins until then).
  bool _docxDrawn = false;

  /// Counts loads, so an answer for an earlier try is dropped.
  int _try = 0;

  late final DocumentKind _kind = documentKindForName(widget.fileName);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final attempt = ++_try;
    setState(() {
      _phase = _Phase.loading;
      _docxDrawn = false;
    });
    Uint8List bytes;
    try {
      bytes = await widget.loader();
    } on DocumentLoadException catch (e) {
      return _fail(attempt, e.message);
    } on FormatException catch (e) {
      return _fail(attempt, e.message, retry: false);
    } catch (_) {
      return _fail(
        attempt,
        'The file could not be loaded. Check the connection and try again.',
      );
    }
    if (!mounted || attempt != _try) return;
    _bytes = bytes;
    if (_kind == DocumentKind.other) {
      setState(() => _phase = _Phase.unsupported);
      return;
    }
    final problem = documentProblem(_kind, bytes);
    if (problem != null) return _fail(attempt, problem, retry: false);
    final needsBrowser =
        _kind == DocumentKind.pdf || _kind == DocumentKind.docx;
    setState(
      () => _phase = needsBrowser && !WebDocumentView.isSupported
          ? _Phase.unsupported
          : _Phase.ready,
    );
  }

  void _fail(int attempt, String message, {bool retry = true}) {
    if (!mounted || attempt != _try) return;
    setState(() {
      _phase = _Phase.failed;
      _message = message;
      _canRetry = retry;
    });
  }

  void _download() {
    final bytes = _bytes;
    if (bytes == null) return;
    web_download.WebDownloadUtils.downloadBytes(widget.fileName, bytes);
  }

  void _openInNewTab() {
    final bytes = _bytes;
    if (bytes == null) return;
    WebDocumentView.openInNewTab(
      bytes,
      _kind == DocumentKind.pdf ? 'application/pdf' : _imageType(bytes),
    );
  }

  static String _imageType(Uint8List bytes) =>
      bytes.length > 3 && bytes[0] == 0x89 ? 'image/png' : 'image/jpeg';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final phone = size.width < 600;
    final canOpenTab =
        _phase == _Phase.ready &&
        WebDocumentView.isSupported &&
        (_kind == DocumentKind.pdf || _kind == DocumentKind.image);

    final content = Column(
      children: [
        _header(canOpenTab, phone),
        const Divider(height: 1, color: AppTheme.slate200),
        Expanded(child: _body()),
      ],
    );

    return Dialog(
      insetPadding: phone
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(phone ? 0 : 16),
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: phone ? size.width : size.width.clamp(0.0, 1100.0),
        height: phone ? size.height : size.height * 0.92,
        child: content,
      ),
    );
  }

  Widget _header(bool canOpenTab, bool phone) {
    final hasFile = _bytes != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(_iconFor(_kind), size: 20, color: AppTheme.maroon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate900,
              ),
            ),
          ),
          if (canOpenTab)
            IconButton(
              tooltip: 'Open in a new tab',
              onPressed: _openInNewTab,
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
              color: AppTheme.slate600,
            ),
          if (hasFile)
            phone
                ? IconButton(
                    tooltip: 'Download',
                    onPressed: _download,
                    icon: const Icon(Icons.download_rounded, size: 20),
                    color: AppTheme.maroon,
                  )
                : TextButton.icon(
                    onPressed: _download,
                    icon: const Icon(Icons.download_rounded, size: 17),
                    label: const Text('Download'),
                  ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 21),
            color: AppTheme.slate600,
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(DocumentKind kind) => switch (kind) {
    DocumentKind.image => Icons.image_outlined,
    DocumentKind.pdf => Icons.picture_as_pdf_outlined,
    DocumentKind.docx => Icons.description_outlined,
    DocumentKind.other => Icons.insert_drive_file_outlined,
  };

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return LoadingState(message: 'Opening ${widget.fileName}…');
      case _Phase.failed:
        return _notice(
          Icons.error_outline_rounded,
          _message,
          actions: [
            if (_canRetry)
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.maroon),
                child: const Text('Try again'),
              ),
          ],
        );
      case _Phase.unsupported:
        return _notice(
          Icons.visibility_off_outlined,
          _kind == DocumentKind.other
              ? "This kind of file can't be previewed. Download it to open it "
                    'on your computer.'
              : "This device can't show this file here. Download it to open "
                    'it.',
        );
      case _Phase.ready:
        return _preview();
    }
  }

  Widget _preview() {
    final bytes = _bytes!;
    switch (_kind) {
      case DocumentKind.image:
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(
              bytes,
              cacheWidth: 2400,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _notice(
                Icons.broken_image_outlined,
                "This picture can't be shown. Download it to open it.",
              ),
            ),
          ),
        );
      case DocumentKind.pdf:
        return WebDocumentView.pdf(bytes);
      case DocumentKind.docx:
        return Stack(
          children: [
            Positioned.fill(
              child: WebDocumentView.docx(
                bytes,
                onReady: () {
                  if (mounted) setState(() => _docxDrawn = true);
                },
                onEscape: () => Navigator.of(context).maybePop(),
                onError: (_, retryable) => _fail(
                  _try,
                  retryable
                      ? 'The Word viewer could not be loaded. Check the '
                            'connection and try again.'
                      : "This Word file can't be shown. Download it to open "
                            'it.',
                  retry: retryable,
                ),
              ),
            ),
            if (!_docxDrawn)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white,
                  child: LoadingState(message: 'Opening ${widget.fileName}…'),
                ),
              ),
          ],
        );
      case DocumentKind.other:
        return const SizedBox.shrink();
    }
  }

  Widget _notice(
    IconData icon,
    String text, {
    List<Widget> actions = const [],
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: AppTheme.slate500),
              const SizedBox(height: 14),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppTheme.slate600,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(spacing: 10, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
