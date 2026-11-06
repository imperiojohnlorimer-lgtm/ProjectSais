import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/backup_info.dart';
import 'supabase_storage_service.dart';

/// Talks to the backup-status function, which holds the GitHub token and
/// only answers an active Admin. Every call returns its error as a sentence
/// to show rather than throwing. Tests swap in a fake.
class BackupService {
  /// The backups GitHub keeps, the recent runs and the schedule. [fresh]
  /// asks the function to look again rather than reuse what it fetched a
  /// moment ago.
  Future<({BackupOverview? overview, String? error})> list({
    bool fresh = false,
  }) async {
    final result = await _call({'action': 'list', 'fresh': fresh});
    if (result.error != null) return (overview: null, error: result.error);
    try {
      return (overview: BackupOverview.fromJson(result.body!), error: null);
    } catch (error) {
      debugPrint('Unreadable backup list: $error');
      return (
        overview: null,
        error: 'The backup list came back in a form SAIS could not read.',
      );
    }
  }

  /// A short-lived link (about a minute) to the backup's zip on GitHub.
  Future<({String? url, String? error})> downloadUrl(int artifactId) async {
    final result = await _call({
      'action': 'download',
      'artifactId': artifactId,
    });
    if (result.error != null) return (url: null, error: result.error);
    final url = result.body!['url']?.toString();
    if (url == null || url.isEmpty) {
      return (url: null, error: 'The server did not give a download link.');
    }
    return (url: url, error: null);
  }

  /// Deletes one backup; the error, or null when it is gone.
  Future<String?> delete(int artifactId) async {
    final result = await _call({'action': 'delete', 'artifactId': artifactId});
    return result.error;
  }

  Future<({Map<String, dynamic>? body, String? error})> _call(
    Map<String, dynamic> request,
  ) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser
          ?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return (body: null, error: 'You must be signed in.');
      }
      final response = await http.post(
        Uri.parse(SupabaseStorageService.backupStatusUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'apikey': SupabaseStorageService.publishableKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(request),
      );
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        body = null;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (body == null) {
          return (body: null, error: 'The server answered in an odd way.');
        }
        return (body: body, error: null);
      }
      if (response.statusCode == 404 && body?['error'] == null) {
        // Supabase's own answer when the function is not deployed.
        return (
          body: null,
          error:
              'The backup service is not set up yet. Deploy the '
              'backup-status function in Supabase.',
        );
      }
      return (
        body: null,
        error:
            body?['error']?.toString() ??
            'The backup service could not answer (${response.statusCode}).',
      );
    } catch (error) {
      debugPrint('Backup request failed: $error');
      return (
        body: null,
        error:
            'Could not reach the backup service. Check your connection and '
            'try again.',
      );
    }
  }
}
