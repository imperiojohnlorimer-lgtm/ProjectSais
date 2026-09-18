import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/supabase_storage_service.dart';
import '../../theme/app_theme.dart';

/// Head-only file manager: create named folders and upload arbitrary
/// documents (memos, MOAs, misc. office files) into them — separate from
/// the auto-collected Student Documents screen, for files that aren't tied
/// to a specific application, report, or evaluation.
class DocumentFoldersScreen extends StatefulWidget {
  const DocumentFoldersScreen({super.key});

  @override
  State<DocumentFoldersScreen> createState() => _DocumentFoldersScreenState();
}

class _DocumentFoldersScreenState extends State<DocumentFoldersScreen> {
  String? _openFolderId;
  bool _uploading = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _createFolder(AppState state) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.maroon),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await state.createDocumentFolder(name.trim());
    }
  }

  Future<void> _deleteFolder(AppState state, DocumentFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Delete "${folder.name}" and all ${state.documents.where((d) => d.folderId == folder.id).length} file(s) inside it? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red500),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.deleteDocumentFolder(folder.id);
      if (mounted) setState(() => _openFolderId = null);
    }
  }

  Future<void> _uploadFile(AppState state, String folderId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('This file type is not available for upload in the current browser session.');
      }

      setState(() => _uploading = true);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid ?? state.currentUser?.id ?? 'user';
      final storagePath = 'reports/$uid/$timestamp/$sanitizedName';
      final extension = file.extension?.toLowerCase();
      final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
        bytes: bytes,
        path: storagePath,
        contentType: extension == null ? null : SupabaseStorageService.contentTypeForExtension(extension),
      );

      await state.uploadManualDocument(
        folderId: folderId,
        fileName: file.name,
        storagePath: storagePath,
        downloadUrl: downloadUrl,
        fileSize: file.size / (1024 * 1024),
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Uploaded ${file.name}'),
            backgroundColor: AppTheme.emerald500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download(Document doc) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      String? url = doc.downloadUrl;
      if ((url == null || url.isEmpty) && doc.filePath != null && doc.filePath!.isNotEmpty) {
        url = await SupabaseStorageService.instance.getDocumentUrl(doc.filePath!);
      }
      if (url == null || url.isEmpty) throw Exception('No file content available.');
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('The browser could not open the document.');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Unable to download: $e'),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _deleteDoc(AppState state, Document doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete "${doc.fileName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red500),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.deleteManualDocument(doc.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 420;
    final horizontalPadding = isCompact ? 16.0 : 28.0;

    final openFolder = _openFolderId == null
        ? null
        : state.documentFolders.where((f) => f.id == _openFolderId).firstOrNull;

    if (openFolder == null && _openFolderId != null) {
      // Folder was deleted elsewhere; fall back to the folder list.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _openFolderId = null);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          child: Row(
            children: [
              if (openFolder != null)
                IconButton(
                  onPressed: () => setState(() => _openFolderId = null),
                  icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.slate600),
                )
              else
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(color: AppTheme.maroon, borderRadius: BorderRadius.circular(2)),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      openFolder?.name ?? 'Document Folders',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.slate900, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      openFolder != null
                          ? '${state.documents.where((d) => d.folderId == openFolder.id).length} file(s)'
                          : '${state.documentFolders.length} folder(s) for memos, MOAs, and other office files',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.slate400),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: openFolder == null
                    ? () => _createFolder(state)
                    : (_uploading ? null : () => _uploadFile(state, openFolder.id)),
                icon: _uploading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(openFolder == null ? Icons.create_new_folder_outlined : Icons.upload_file_rounded, size: 18),
                label: Text(openFolder == null ? 'New Folder' : 'Upload File'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.maroon,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 28),
            child: openFolder == null
                ? _folderGrid(state)
                : _fileList(state, openFolder),
          ),
        ),
      ],
    );
  }

  Widget _folderGrid(AppState state) {
    if (state.documentFolders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: AppTheme.slate100, shape: BoxShape.circle),
                child: const Icon(Icons.folder_off_outlined, size: 36, color: AppTheme.slate300),
              ),
              const SizedBox(height: 16),
              const Text(
                'No folders yet',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate400),
              ),
              const SizedBox(height: 4),
              const Text(
                'Create a folder to start uploading documents.',
                style: TextStyle(fontSize: 13, color: AppTheme.slate500),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 180).floor().clamp(2, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.documentFolders.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            final folder = state.documentFolders[index];
            final count = state.documents.where((d) => d.folderId == folder.id).length;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _openFolderId = folder.id),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.slate200),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.folder_rounded, size: 40, color: AppTheme.amber500),
                        const Spacer(),
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.slate800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$count file${count == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.slate400, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: IconButton(
                        onPressed: () => _deleteFolder(state, folder),
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.slate400),
                        splashRadius: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _fileList(AppState state, DocumentFolder folder) {
    final files = state.documents.where((d) => d.folderId == folder.id).toList()
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

    if (files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: AppTheme.slate100, shape: BoxShape.circle),
                child: const Icon(Icons.insert_drive_file_outlined, size: 36, color: AppTheme.slate300),
              ),
              const SizedBox(height: 16),
              const Text(
                'This folder is empty',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate400),
              ),
              const SizedBox(height: 4),
              const Text(
                'Use "Upload File" to add a document here.',
                style: TextStyle(fontSize: 13, color: AppTheme.slate500),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: files
          .map(
            (doc) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.maroon.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.description_outlined, size: 18, color: AppTheme.maroon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.slate800),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Uploaded by ${doc.uploadedBy.isEmpty ? 'Head' : doc.uploadedBy}',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.slate500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _download(doc),
                    icon: const Icon(Icons.download_rounded, size: 18, color: AppTheme.emerald500),
                  ),
                  IconButton(
                    onPressed: () => _deleteDoc(state, doc),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.red500),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
