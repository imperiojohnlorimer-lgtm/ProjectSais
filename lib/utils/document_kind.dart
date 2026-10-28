import 'dart:typed_data';

import 'package:archive/archive.dart';

/// What a stored file is, for deciding how to show it.
enum DocumentKind {
  image,
  pdf,

  /// A modern Word file. The old binary `.doc` is [other]: nothing in a
  /// browser can draw it without sending it to an outside service.
  docx,
  other,
}

/// The largest file the preview will hold (uploads stop at 10 MB).
const maxPreviewBytes = 12 * 1024 * 1024;

// Limits on a Word file's zip package, so a crafted one can't make the
// browser inflate gigabytes. Declared sizes are read from the zip headers.
const _maxDocxEntries = 500;
const _maxDocxEntryBytes = 25 * 1024 * 1024;
const _maxDocxTotalBytes = 60 * 1024 * 1024;

DocumentKind documentKindForName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'png' || 'jpg' || 'jpeg' => DocumentKind.image,
    'pdf' => DocumentKind.pdf,
    'docx' => DocumentKind.docx,
    _ => DocumentKind.other,
  };
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// Why [bytes] can't be shown as a [kind], in words for the Head; null when
/// they are what the name says. The type comes from the file's own first
/// bytes as well as its name, so a file renamed to look harmless is refused.
String? documentProblem(DocumentKind kind, Uint8List bytes) {
  if (bytes.isEmpty) return 'The file is empty.';
  if (bytes.length > maxPreviewBytes) {
    return 'The file is too large to preview. Download it instead.';
  }
  switch (kind) {
    case DocumentKind.image:
      final png = _startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47]);
      final jpeg = _startsWith(bytes, const [0xFF, 0xD8, 0xFF]);
      return png || jpeg ? null : "This file isn't a picture.";
    case DocumentKind.pdf:
      // A PDF may have a little before its header; browsers look in the
      // first kilobyte.
      final head = bytes.length < 1024 ? bytes : bytes.sublist(0, 1024);
      for (var i = 0; i + 5 <= head.length; i++) {
        if (head[i] == 0x25 &&
            head[i + 1] == 0x50 &&
            head[i + 2] == 0x44 &&
            head[i + 3] == 0x46 &&
            head[i + 4] == 0x2D) {
          return null;
        }
      }
      return "This file isn't a PDF.";
    case DocumentKind.docx:
      return _docxProblem(bytes);
    case DocumentKind.other:
      return "This kind of file can't be previewed.";
  }
}

String? _docxProblem(Uint8List bytes) {
  // Word's older format, and files protected with a password, are not zip.
  if (_startsWith(bytes, const [0xD0, 0xCF, 0x11, 0xE0])) {
    return 'This Word file is password-protected or in the old .doc '
        "format, so it can't be previewed.";
  }
  if (!_startsWith(bytes, const [0x50, 0x4B, 0x03, 0x04])) {
    return "This file isn't a Word document.";
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return "This Word file is damaged and can't be opened.";
  }
  if (archive.length > _maxDocxEntries) {
    return 'This Word file is too complex to preview. Download it instead.';
  }
  var total = 0;
  var hasTypes = false;
  var hasBody = false;
  for (final entry in archive) {
    if (entry.size > _maxDocxEntryBytes) {
      return 'This Word file is too large to preview. Download it instead.';
    }
    total += entry.size;
    if (entry.name == '[Content_Types].xml') hasTypes = true;
    if (entry.name == 'word/document.xml') hasBody = true;
  }
  if (total > _maxDocxTotalBytes) {
    return 'This Word file is too large to preview. Download it instead.';
  }
  if (!hasTypes || !hasBody) return "This file isn't a Word document.";
  return null;
}
