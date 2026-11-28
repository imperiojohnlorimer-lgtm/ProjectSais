import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/application_form_document_service.dart';
import '../services/supabase_storage_service.dart';
import '../theme/app_snackbar.dart';
import '../utils/web_download_stub.dart'
    if (dart.library.html) '../utils/web_download.dart'
    as web_download;
import 'document_preview.dart';

/// File name to use when previewing or downloading [app]'s filled Application
/// Form `.docx`.
String applicationFormFileName(Application app) {
  final saved = app.applicationFormDoc?.fileName.trim() ?? '';
  if (saved.isNotEmpty) return saved;
  final rawName = app.applicantName.trim().isEmpty
      ? 'applicant'
      : app.applicantName.trim();
  final safe = rawName
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .toLowerCase();
  return 'application-form-${safe.isEmpty ? 'applicant' : safe}.docx';
}

/// Loads the bytes of [app]'s filled Application Form `.docx`. Prefers the
/// stored document when present, falling back to regenerating from
/// [app.applicationForm] when offline/unavailable or when only structured data
/// was saved.
Future<Uint8List> loadFilledApplicationFormBytes(Application app) async {
  final doc = app.applicationFormDoc;
  if (doc != null) {
    if (doc.bytes != null && doc.bytes!.isNotEmpty) return doc.bytes!;
    final hasPath = doc.storagePath?.trim().isNotEmpty == true;
    final hasUrl = doc.downloadUrl?.trim().isNotEmpty == true;
    if (hasPath || hasUrl) {
      try {
        return await SupabaseStorageService.instance.fetchDocumentBytes(
          path: doc.storagePath,
          storedUrl: doc.downloadUrl,
        );
      } catch (_) {
        if (app.applicationForm == null) rethrow;
      }
    }
  }
  final form = app.applicationForm;
  if (form != null) {
    final generated = await const ApplicationFormDocumentService()
        .generateApplicationForm(data: form, applicationId: app.id);
    if (generated.bytes != null && generated.bytes!.isNotEmpty) {
      return generated.bytes!;
    }
  }
  throw StateError('No filled Application Form is available for this applicant.');
}

/// Opens the filled Application Form `.docx` in the in-app document viewer
/// (which also includes a Download button).
Future<void> previewFilledApplicationForm(
  BuildContext context,
  Application app, {
  DocumentBytesLoader? loader,
}) => showDialog<void>(
  context: context,
  builder: (_) => DocumentPreviewDialog(
    fileName: applicationFormFileName(app),
    loader: loader ?? () => loadFilledApplicationFormBytes(app),
  ),
);

/// Downloads the filled Application Form `.docx` directly to the device.
Future<void> downloadFilledApplicationForm(
  BuildContext context,
  Application app, {
  DocumentBytesLoader? loader,
}) async {
  final fileName = applicationFormFileName(app);
  try {
    final bytes = await (loader?.call() ?? loadFilledApplicationFormBytes(app));
    if (kIsWeb) {
      web_download.WebDownloadUtils.downloadBytes(fileName, bytes);
    } else {
      final uri = Uri.dataFromBytes(
        bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        parameters: {'filename': fileName},
      );
      final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!opened) {
        throw Exception('Could not open the downloaded file.');
      }
    }
    if (context.mounted) {
      AppSnackBar.success(context, 'Downloaded $fileName');
    }
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.error(context, 'Could not download Application Form: $e');
    }
  }
}
