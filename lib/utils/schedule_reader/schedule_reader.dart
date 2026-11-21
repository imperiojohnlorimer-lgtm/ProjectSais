// Reads a class schedule picture or PDF on this device (web/schedule-reader/).
// Only a browser can: on any other build [ScheduleReader.isSupported] is
// false and the student types the subjects.
export 'schedule_reader_stub.dart'
    if (dart.library.js_interop) 'schedule_reader_web.dart';
