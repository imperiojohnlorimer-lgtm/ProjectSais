import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/supabase_storage_service.dart';
import '../theme/app_theme.dart';
import 'document_preview.dart';

/// Gets the bytes of the picture kept at a storage path. Tests pass their own.
typedef OfficePictureLoader = Future<Uint8List> Function(String path);

// async, so a failure to even reach storage shows the picture's "couldn't
// load" message instead of throwing while the page builds.
Future<Uint8List> _loadFromStorage(String path) async =>
    SupabaseStorageService.instance.fetchDocumentBytes(path: path);

/// An office's location picture, loaded from storage (a fresh link each time,
/// so the one-hour expiry never matters) and kept while the page is open.
/// Tapping it opens it larger in the document viewer.
class OfficePicture extends StatefulWidget {
  final String path;
  final String title;
  final double height;
  final OfficePictureLoader? loader;

  const OfficePicture({
    super.key,
    required this.path,
    required this.title,
    this.height = 200,
    this.loader,
  });

  @override
  State<OfficePicture> createState() => _OfficePictureState();
}

class _OfficePictureState extends State<OfficePicture> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() => (widget.loader ?? _loadFromStorage)(widget.path);

  @override
  void didUpdateWidget(OfficePicture old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _bytes = _load();
  }

  void _retry() {
    final again = _load();
    setState(() {
      _bytes = again;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _frame(
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = snapshot.data;
        if (snapshot.hasError || bytes == null || bytes.isEmpty) {
          return _frame(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.image_not_supported_outlined,
                  color: AppTheme.slate400,
                ),
                const SizedBox(height: 6),
                const Text(
                  "Couldn't load the picture.",
                  style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                ),
                TextButton(onPressed: _retry, child: const Text('Try again')),
              ],
            ),
          );
        }
        return Semantics(
          button: true,
          image: true,
          label: 'Picture of ${widget.title}. Opens it larger.',
          child: GestureDetector(
            onTap: () => showDocumentPreview(
              context,
              fileName: '${widget.title} location.png',
              bytes: bytes,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: double.infinity,
                height: widget.height,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 1200,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppTheme.slate400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _frame({required Widget child}) => Container(
    width: double.infinity,
    height: widget.height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.slate50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.slate200),
    ),
    child: child,
  );
}
