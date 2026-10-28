import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A file that could not be fetched for a reason that may pass (the network,
/// an expired link, the service being busy): trying again can work. Reasons
/// it never will are [FormatException]s.
class DocumentLoadException implements Exception {
  final String message;
  const DocumentLoadException(this.message);

  @override
  String toString() => message;
}

class SupabaseStorageService {
  SupabaseStorageService._();

  static final SupabaseStorageService instance = SupabaseStorageService._();
  static const maxUploadBytes = 10 * 1024 * 1024;

  /// Edge function endpoints and the key every call to them carries. These
  /// were repeated inline at each call site; they live here so a project
  /// change is one edit.
  static const _functionsRoot =
      'https://hksswjhioztqsypbrkjy.supabase.co/functions/v1';
  static const publishableKey =
      'sb_publishable_9gI1i8ibybNp5qLBJpQo1A_7FCIkycd';
  static const uploadDocumentUrl = '$_functionsRoot/upload-document';

  /// Server-side attendance clock-in/out. Validates the scanned QR against
  /// the current session and writes the record with a Firebase service
  /// account, since `attendance` is staff-only in the Firestore rules.
  static const clockAttendanceUrl = '$_functionsRoot/clock-attendance';

  /// Pushes notifications to devices: clock-out reminders (run by a
  /// Supabase cron job), every other notification once the app saves it,
  /// and the test notification the Turn on cards offer.
  static const clockOutRemindersUrl = '$_functionsRoot/clockout-reminders';
  static const _allowedExtensions = {
    'pdf',
    'doc',
    'docx',
    'jpg',
    'jpeg',
    'png',
  };

  final SupabaseClient _client = Supabase.instance.client;

  Future<String> uploadDocument({
    required Uint8List bytes,
    required String path,
    String? contentType,
  }) async {
    _validateUpload(bytes: bytes, path: path, contentType: contentType);
    final token = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken(
      true,
    );
    if (token == null || token.isEmpty) {
      throw const FormatException('You must be signed in to upload a file.');
    }

    final request = http.MultipartRequest('POST', Uri.parse(uploadDocumentUrl))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['apikey'] = publishableKey
      ..fields['path'] = path
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: path.split('/').last,
        ),
      );

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed (${response.statusCode}): $responseBody');
    }

    final result = jsonDecode(responseBody) as Map<String, dynamic>;
    final downloadUrl = result['downloadUrl']?.toString();
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw const FormatException('Upload succeeded without a download URL.');
    }
    return downloadUrl;
  }

  Future<String> getDocumentUrl(String path) {
    return _getFreshDocumentUrl(path);
  }

  /// A link that opens a stored file now. The links saved with files are
  /// signed and stop working after an hour, so this signs a new one from
  /// [path], or, when a record has no path, from the path inside its saved
  /// signed link [storedUrl]. Only a link that isn't a signed one is
  /// returned as saved. Null when there's nothing to open.
  Future<String?> openableUrl({String? path, String? storedUrl}) async {
    final filePath = path != null && path.trim().isNotEmpty
        ? path.trim()
        : pathFromSignedUrl(storedUrl);
    if (filePath != null) return getDocumentUrl(filePath);
    return storedUrl == null || storedUrl.isEmpty ? null : storedUrl;
  }

  /// Whether [uri] is a signed link to a file in our own Documents bucket:
  /// the only kind of link the app downloads itself. Anything else (a link a
  /// student typed, another site) is never fetched.
  static bool isStorageSignedUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == _storageHost &&
      uri.path.startsWith('/storage/v1/object/sign/Documents/');

  static const _storageHost = 'hksswjhioztqsypbrkjy.supabase.co';

  /// Reads [response]'s body, giving up once it passes [maxBytes] so a huge
  /// file can't fill the browser's memory.
  static Future<Uint8List> readCapped(
    http.StreamedResponse response, {
    int maxBytes = 12 * 1024 * 1024,
  }) async {
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw const FormatException(
        'The file is too large to preview. Download it instead.',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw const FormatException(
          'The file is too large to preview. Download it instead.',
        );
      }
    }
    return builder.takeBytes();
  }

  /// The bytes of a stored file, to show it in the app. Signs a fresh link
  /// ([openableUrl]), then fetches it with no credentials attached: the
  /// signature in the link is the permission. Errors never carry the link.
  Future<Uint8List> fetchDocumentBytes({
    String? path,
    String? storedUrl,
    int maxBytes = 12 * 1024 * 1024,
  }) async {
    final url = await openableUrl(path: path, storedUrl: storedUrl);
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) {
      throw const FormatException('This file has no stored copy to open.');
    }
    if (!isStorageSignedUrl(uri)) {
      throw const FormatException(
        "This file is kept somewhere SAIS can't open it from.",
      );
    }
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DocumentLoadException(
          'The file could not be loaded (error ${response.statusCode}). '
          'Try again in a moment.',
        );
      }
      return await readCapped(response, maxBytes: maxBytes);
    } finally {
      client.close();
    }
  }

  /// The path in the Documents bucket that a Supabase storage link points
  /// to (`…/storage/v1/object/sign/Documents/<path>?token=…`), or null for
  /// any other link.
  static String? pathFromSignedUrl(String? url) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }
    final segments = uri.pathSegments;
    final object = segments.indexOf('object');
    if (object < 0 || segments.length < object + 4) return null;
    if (segments[object + 2] != 'Documents') return null;
    final path = segments.skip(object + 3).join('/');
    return path.isEmpty ? null : path;
  }

  Future<String> _getFreshDocumentUrl(String path) async {
    final token = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken(
      true,
    );
    if (token == null || token.isEmpty) {
      throw const FormatException('You must be signed in to view a file.');
    }

    final response = await http.post(
      Uri.parse(uploadDocumentUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': publishableKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'action': 'sign', 'path': path}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Unable to refresh document URL (${response.statusCode}): ${response.body}',
      );
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final url = result['downloadUrl']?.toString();
    if (url == null || url.isEmpty) {
      throw const FormatException('No document URL was returned.');
    }
    return url;
  }

  Future<String> archiveDocument({
    required String sourcePath,
    required String archivePath,
  }) async {
    final bytes = await _client.storage.from('Documents').download(sourcePath);
    await _client.storage
        .from('Documents')
        .uploadBinary(
          archivePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from('Documents').createSignedUrl(archivePath, 3600);
  }

  static String contentTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  static void _validateUpload({
    required Uint8List bytes,
    required String path,
    required String? contentType,
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('The selected file is empty.');
    }
    if (bytes.length > maxUploadBytes) {
      throw const FormatException('Files must be 10 MB or smaller.');
    }

    final pathParts = path.split('/');
    final validPathShape =
        pathParts.length == 4 ||
        (pathParts[0] == 'applications' && pathParts.length == 5);
    if (!validPathShape ||
        (pathParts[0] != 'reports' &&
            pathParts[0] != 'applications' &&
            pathParts[0] != 'announcements') ||
        pathParts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        pathParts
            .skip(1)
            .any((part) => !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(part)) ||
        (pathParts.length == 4 && !RegExp(r'^\d+$').hasMatch(pathParts[2]))) {
      throw const FormatException('Invalid document storage path.');
    }

    final extension = pathParts.last.contains('.')
        ? pathParts.last.split('.').last.toLowerCase()
        : '';
    if (!_allowedExtensions.contains(extension)) {
      throw const FormatException(
        'Only PDF, Word, JPG, JPEG, and PNG files are allowed.',
      );
    }
    if (contentType == null ||
        contentType != contentTypeForExtension(extension)) {
      throw const FormatException('The file content type is not allowed.');
    }
  }
}
