import 'dart:typed_data';

import '../../models/class_schedule.dart';
import 'school_id_read_result.dart';

/// The non-browser build: no reader.
class ScheduleReader {
  const ScheduleReader._();

  static bool get isSupported => false;

  static Future<ScheduleReadResult> read(Uint8List bytes, String mimeType) =>
      Future.error(UnsupportedError('Reading a schedule needs the web app.'));

  static void cancel() {}
}

/// The non-browser build: no school ID reader.
class SchoolIdReader {
  const SchoolIdReader._();

  static bool get isSupported => false;

  static Future<SchoolIdReadResult> read(Uint8List bytes, String mimeType) =>
      Future.error(UnsupportedError('Reading a school ID needs the web app.'));

  static void cancel() {}
}

/// A read that failed, with a message for the student.
class ScheduleReadError implements Exception {
  final String message;
  const ScheduleReadError(this.message);
  @override
  String toString() => message;
}
