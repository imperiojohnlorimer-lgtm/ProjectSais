import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageService {
  SupabaseStorageService._();

  static final SupabaseStorageService instance = SupabaseStorageService._();
  static const maxUploadBytes = 10 * 1024 * 1024;
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

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        'https://hksswjhioztqsypbrkjy.supabase.co/functions/v1/upload-document',
      ),
    )
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['apikey'] =
          'sb_publishable_9gI1i8ibybNp5qLBJpQo1A_7FCIkycd'
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

  Future<String> _getFreshDocumentUrl(String path) async {
    final token = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken(
      true,
    );
    if (token == null || token.isEmpty) {
      throw const FormatException('You must be signed in to view a file.');
    }

    final response = await http.post(
      Uri.parse(
        'https://hksswjhioztqsypbrkjy.supabase.co/functions/v1/upload-document',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': 'sb_publishable_9gI1i8ibybNp5qLBJpQo1A_7FCIkycd',
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
    final validPathShape = pathParts.length == 4 ||
        (pathParts[0] == 'applications' && pathParts.length == 5);
    if (!validPathShape ||
        (pathParts[0] != 'reports' && pathParts[0] != 'applications') ||
        pathParts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        pathParts.skip(1).any(
          (part) => !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(part),
        ) ||
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
