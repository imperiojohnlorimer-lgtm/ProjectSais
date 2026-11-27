// Reads a class schedule or MarSU school ID on this device (web/schedule-reader/).
// Only a browser can: on any other build [ScheduleReader.isSupported] and
// [SchoolIdReader.isSupported] are false.
export 'school_id_read_result.dart';
export 'schedule_reader_stub.dart'
    if (dart.library.js_interop) 'schedule_reader_web.dart';
