import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../models/class_schedule.dart';

@JS('saisReadSchedule')
external JSPromise<JSString> _readSchedule(JSUint8Array bytes, JSString type);

@JS('saisCancelScheduleRead')
external void _cancelScheduleRead();

/// The browser build: web/schedule-reader/ reads the file on this device.
class ScheduleReader {
  const ScheduleReader._();

  static bool get isSupported => true;

  /// What the reader found in [bytes]. Fails with a [ScheduleReadError]
  /// whose message can be shown as it is.
  static Future<ScheduleReadResult> read(
    Uint8List bytes,
    String mimeType,
  ) async {
    await _loadScripts();
    try {
      final json = await _readSchedule(bytes.toJS, mimeType.toJS).toDart;
      return ScheduleReadResult.fromJson(
        Map<String, dynamic>.from(jsonDecode(json.toDart) as Map),
      );
    } catch (error) {
      throw ScheduleReadError(_messageOf(error));
    }
  }

  /// Stops a read in progress (its future then fails).
  static void cancel() {
    if (_scripts != null) {
      try {
        _cancelScheduleRead();
      } catch (_) {}
    }
  }

  static String _messageOf(Object error) {
    // The reader's own messages are written for students; anything else
    // gets a plain one.
    final text = error.toString();
    final match = RegExp(r'Error: (.+)$').firstMatch(text);
    final message = (match?.group(1) ?? text).trim();
    const plain = 'This schedule could not be read. Please type your subjects.';
    if (message.isEmpty || message.length > 200 || message.contains('Dart')) {
      return plain;
    }
    return message;
  }
}

/// A read that failed, with a message for the student.
class ScheduleReadError implements Exception {
  final String message;
  const ScheduleReadError(this.message);
  @override
  String toString() => message;
}

Future<void>? _scripts;

/// Loads the reader's two small scripts the first time; the large libraries
/// they use are fetched by them when reading. A failed load can be retried.
Future<void> _loadScripts() {
  return _scripts ??= () async {
    try {
      for (final src in const [
        'schedule-reader/sais-schedule-layout.js',
        'schedule-reader/sais-schedule.js',
      ]) {
        final done = Completer<void>();
        final script = web.HTMLScriptElement()
          ..src = src
          ..async = false;
        script.onload = ((web.Event _) => done.complete()).toJS;
        script.onerror = ((web.Event _) => done.completeError(
          const ScheduleReadError(
            'The schedule reader could not be loaded. Check your internet '
            'connection and try again.',
          ),
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
