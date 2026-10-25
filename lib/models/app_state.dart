import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:projectsais/services/appointment_document_service.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/performance_evaluation_document_service.dart';
import 'package:projectsais/services/push_service.dart';
import 'package:projectsais/services/supabase_storage_service.dart';
import 'package:projectsais/utils/auth_errors.dart';
import '../firebase_options.dart';
import 'assistant_attendance.dart';
import 'models.dart';
import 'task_duty.dart';
import 'task_template.dart';

part 'app_state/clock_out_reminder.dart';
part 'app_state/dashboard_stats.dart';
part 'app_state/push.dart';
part 'app_state/applications_and_folders.dart';
part 'app_state/payroll.dart';
part 'app_state/payroll_requirements.dart';
part 'app_state/rehiring.dart';

/// Outcome of a QR clock-in/out. [clockedIn] only means anything when [ok]
/// is true; [message] carries the server's reason when it isn't.
class QrClockResult {
  final bool ok;
  final bool clockedIn;
  final String message;

  const QrClockResult({
    required this.ok,
    this.clockedIn = false,
    this.message = '',
  });
}

/// The pages a signed-out visitor can see: `/`, `/login` and `/register`.
enum PublicPage { landing, login, register }

class AppState extends ChangeNotifier {
  /// [firestoreService] and [pushService] are for tests; the app lets them
  /// default.
  AppState({FirestoreService? firestoreService, PushService? pushService})
    : _firestoreService = firestoreService,
      _push = pushService ?? PushService();

  User? currentUser;
  String activeTab = 'dashboard';
  bool _isDataSeeded = false;
  Future<void>? _dataSeedFuture;
  FirestoreService? _firestoreService;
  StreamSubscription<List<Map<String, dynamic>>>? _annSub;
  StreamSubscription<List<Map<String, dynamic>>>? _taskSub;
  StreamSubscription<List<Map<String, dynamic>>>? _attSub;
  StreamSubscription<List<Map<String, dynamic>>>? _appSub;
  StreamSubscription<List<Map<String, dynamic>>>? _headForwardsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _payrollSub;
  StreamSubscription<List<Map<String, dynamic>>>? _payrollSheetsSub;

  /// Every other live listener (see [_startLiveData]).
  final List<StreamSubscription<dynamic>> _liveSubs = [];

  /// Bumped each time the live listeners restart, so a listener set up
  /// after an async gap can tell it belongs to an older session.
  int _liveGeneration = 0;

  // Which live queries this session has opened, and which of them have
  // answered (data or an error) at least once. Screens use [isLoaded] to
  // show a loading state rather than "nothing here" before the first answer.
  final Set<String> _loadExpected = {};
  final Set<String> _loadReady = {};
  bool _loadTracking = false;

  /// True from the moment a signed-in user is known until their listeners
  /// start (the initial fetches in between can be slow): pages show loading.
  bool _loadPending = false;
  Timer? _loadTimeout;

  /// Set by [dispose], so work that finishes afterwards does nothing.
  bool _disposed = false;

  /// The Head ids this session last wrote to meta/heads (comma-joined), so
  /// each roster update doesn't rewrite an unchanged list.
  String? _publishedHeadIds;

  /// The profiles' Student IDs as [_syncStudentIdClaims] last reconciled
  /// them, so an unrelated profile change doesn't re-read every claim.
  String? _syncedStudentIds;
  Timer? _missedTimeOutTimer;
  Timer? _clockOutReminderTimer;
  Timer? _archiveTimer;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: kIsWeb
        ? '478525793741-4gdecf12ssq9eu2p0dh9saj1i14uh6ec.apps.googleusercontent.com'
        : null,
  );

  // ─── Attendance QR session ─────────────────────────
  // One QR code per daily session: everyone scanning during the morning
  // session uses the same code, and the afternoon session gets a different
  // one. The code stays put for the whole session so a supervisor can print
  // it once and post it instead of re-generating it every minute.
  String? currentQrToken;
  DateTime? qrGeneratedAt;

  /// Session key (`yyyyMMdd-AM` / `yyyyMMdd-PM`) that [currentQrToken] belongs
  /// to. A token is only accepted while its own session is still running.
  String? currentQrSessionKey;

  // Attendance QR scanning is only allowed during these two daily windows
  // (morning session and afternoon session, with a lunch break in between).
  static const _qrMorningStartMinutes = 7 * 60 + 30; // 7:30 AM
  static const _qrMorningEndMinutes = 12 * 60; // 12:00 PM
  static const _qrAfternoonStartMinutes = 12 * 60 + 30; // 12:30 PM
  static const _qrAfternoonEndMinutes = 17 * 60; // 5:00 PM

  /// Whether the given time (defaults to now) falls within an allowed
  /// attendance QR scanning window.
  bool isWithinAttendanceQrWindow([DateTime? at]) =>
      attendanceQrSessionKey(at) != null;

  /// The session [at] (defaults to now) belongs to, or null when it falls
  /// outside both windows.
  String? attendanceQrSessionKey([DateTime? at]) {
    final now = at ?? DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final String half;
    if (minutes >= _qrMorningStartMinutes && minutes <= _qrMorningEndMinutes) {
      half = 'AM';
    } else if (minutes >= _qrAfternoonStartMinutes &&
        minutes <= _qrAfternoonEndMinutes) {
      half = 'PM';
    } else {
      return null;
    }
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d-$half';
  }

  /// Human label for the session running at [at], e.g. `Morning session`.
  String? attendanceQrSessionLabel([DateTime? at]) {
    final key = attendanceQrSessionKey(at);
    if (key == null) return null;
    return key.endsWith('AM') ? 'Morning session' : 'Afternoon session';
  }

  /// When the session running at [at] ends — the moment its QR code stops
  /// being accepted.
  DateTime? attendanceQrSessionEnd([DateTime? at]) {
    final now = at ?? DateTime.now();
    final key = attendanceQrSessionKey(now);
    if (key == null) return null;
    final endMinutes = key.endsWith('AM')
        ? _qrMorningEndMinutes
        : _qrAfternoonEndMinutes;
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(minutes: endMinutes));
  }

  /// When the next session opens today, if [at] (defaults to now) falls
  /// before the morning window or in the lunch break. Null during a session
  /// and once the afternoon session has ended.
  DateTime? nextAttendanceSessionStart([DateTime? at]) {
    final now = at ?? DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final int startMinutes;
    if (minutes < _qrMorningStartMinutes) {
      startMinutes = _qrMorningStartMinutes;
    } else if (minutes > _qrMorningEndMinutes &&
        minutes < _qrAfternoonStartMinutes) {
      startMinutes = _qrAfternoonStartMinutes;
    } else {
      return null;
    }
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(minutes: startMinutes));
  }

  /// Returns the QR token for the session running right now, minting and
  /// persisting one only when that session doesn't have a token yet.
  ///
  /// Calling this again during the same session hands back the same code, so
  /// a printed QR keeps working until the session ends. Returns null outside
  /// the two daily windows.
  ///
  /// Throws when the code can't be read or saved. The server checks every
  /// scan against the saved code, so showing one that isn't saved would
  /// only get every scan rejected — and minting a replacement because a
  /// read failed would break the code already posted for the session.
  Future<String?> generateAttendanceQrToken([DateTime? at]) async {
    final now = at ?? DateTime.now();
    final sessionKey = attendanceQrSessionKey(now);
    if (sessionKey == null) return null;

    // Already holding this session's token locally.
    if (currentQrToken != null && currentQrSessionKey == sessionKey) {
      return currentQrToken;
    }

    // Random, not a timestamp: the session is public knowledge and the
    // minute the code was made is easy to narrow down, so anything derived
    // from them could be guessed and sent to clock-attendance without ever
    // seeing the posted QR.
    final random = Random.secure();
    final secret = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();

    // Kept only if no other device has saved this session's code already.
    _firestoreService ??= FirestoreService();
    final doc = await _firestoreService!.claimSessionQrToken(
      'SAIS-ATT-$sessionKey-$secret',
      sessionKey,
      sessionOf: _sessionKeyOfQrDoc,
    );
    final token = doc['token'] as String;
    currentQrToken = token;
    currentQrSessionKey = sessionKey;
    qrGeneratedAt = _generatedAtOfQrDoc(doc) ?? now;
    notifyListeners();
    return token;
  }

  /// The session a stored QR doc belongs to. Docs written before sessions
  /// existed have no `sessionKey`, so derive it from when they were generated.
  String? _sessionKeyOfQrDoc(Map<String, dynamic> doc) {
    final stored = doc['sessionKey'] as String?;
    if (stored != null) return stored;
    final generatedAt = _generatedAtOfQrDoc(doc);
    return generatedAt == null ? null : attendanceQrSessionKey(generatedAt);
  }

  DateTime? _generatedAtOfQrDoc(Map<String, dynamic> doc) {
    final generatedAt = doc['generatedAt'];
    if (generatedAt is Timestamp) return generatedAt.toDate();
    if (generatedAt is String) return DateTime.tryParse(generatedAt);
    return null;
  }

  // Mock Data
  List<User> users = [];
  List<Student> students = [];
  List<AttendanceRecord> attendance = [];
  List<ClassScheduleEntry> classSchedules = [];
  List<Task> tasks = [];
  List<Report> reports = [];
  List<Evaluation> evaluations = [];
  List<RehireRecord> rehireRecords = [];
  List<HeadForward> headForwards = [];
  List<PayrollRecord> payrollRecords = [];
  // Until the first snapshot arrives, the preview can't tell who's already
  // been paid, so payroll can't be approved.
  bool payrollRecordsLoaded = false;
  List<PayrollSheet> payrollSheets = [];

  /// The Head's check of each Student Assistant's payroll requirements
  /// (Head and Admin).
  List<PayrollCheck> payrollChecks = [];
  List<Announcement> announcements = [];
  List<Application> applications = [];
  List<ScreeningRecord> screeningRecords = [];
  List<AppNotification> notifications = [];
  List<Document> documents = [];
  List<DocumentFolder> documentFolders = [];
  List<Office> offices = [];
  String academicYear = '2026-2027';
  String academicSemester = '1st Semester';
  DateTime academicYearStart = DateTime(2026, 8, 1);
  DateTime academicYearEnd = DateTime(2027, 7, 31);
  bool allowAcademicApplications = true;
  bool enforceAssistantHourCap = true;
  // Credited hours allowed per Monday–Sunday week while the cap is on.
  // Must match WEEKLY_HOUR_CAP in the clock-attendance function.
  static const weeklyHourCap = 20.0;
  bool autoArchiveAttendanceLogs = true;
  List<Map<String, dynamic>> academicMilestones = [];
  List<Map<String, dynamic>> academicYearArchives = [];

  /// How long the Admin has to undo a change of academic year or semester.
  /// Until then the Head's session holds off on what the change sets off
  /// that can't be taken back: archiving the year left behind, and applying
  /// rehire decisions for the new term.
  static const termChangeUndoWindow = Duration(hours: 24);

  // The year, semester and dates in effect before the last term change, and
  // when that change was saved (see [undoTermChange]).
  Map<String, dynamic>? _previousAcademicTerm;
  DateTime? _termChangedAt;

  // A year the Admin moved to and then undid. Records stamped with it were
  // made while it showed, and the Head's session moves them back.
  String? _undoneAcademicYear;

  /// Official Philippine regular & special (non-working) holidays for the
  /// current academic year. These are fixed by law/proclamation, so unlike
  /// a student's own weekly schedule they are never user-editable — any
  /// recurring "school day" schedule automatically skips these dates when
  /// it repeats week to week, and the DTR/Accomplishment Report marks them
  /// as "Holiday" instead of "Class Schedule" or blank.
  List<DateTime> get holidays => [
    // 2026
    DateTime(2026, 8, 21), // Ninoy Aquino Day
    DateTime(2026, 8, 31), // National Heroes Day
    DateTime(2026, 11, 1), // All Saints' Day
    DateTime(2026, 11, 30), // Bonifacio Day
    DateTime(2026, 12, 8), // Feast of the Immaculate Conception
    DateTime(2026, 12, 25), // Christmas Day
    DateTime(2026, 12, 30), // Rizal Day
    DateTime(2026, 12, 31), // Last Day of the Year
    // 2027
    DateTime(2027, 1, 1), // New Year's Day
    DateTime(2027, 4, 1), // Maundy Thursday (approx.)
    DateTime(2027, 4, 2), // Good Friday (approx.)
    DateTime(2027, 4, 9), // Araw ng Kagitingan
    DateTime(2027, 5, 1), // Labor Day
    DateTime(2027, 6, 12), // Independence Day
  ];

  bool isHoliday(DateTime date) => holidays.any(
    (h) => h.year == date.year && h.month == date.month && h.day == date.day,
  );
  // System status
  bool dbHealthy = true;
  bool authHealthy = true;
  bool reportsHealthy = true;
  int responseTimeMs = 0;
  List<String> departments = [
    'College of Information and Computing Sciences',
    'College of Engineering',
    'College of Education',
    'College of Business Administration',
    'College of Industrial Technology',
    'Administration',
  ];
  Map<String, String> departmentCodes = {};
  // Degree programs, sorted by code. Each belongs to one department.
  List<Program> programs = [];
  List<String> skills = [];

  List<String> campuses = [
    'Boac Campus',
    'Mogpog Campus',
    'Sta. Cruz Campus',
    'Torrijos Campus',
    'Gasan Campus',
  ];

  List<String> taskCategories = [
    'General',
    'Administrative',
    'Academic',
    'Fieldwork',
    'Reporting',
  ];

  /// The ready-made tasks the Head keeps under the categories.
  List<TaskTemplate> taskTemplates = [];

  /// Ongoing duties: the Head sees all, a Supervisor those of their own
  /// office's students, a Student Assistant their own.
  List<TaskDuty> taskDuties = [];

  // ─── Auth ──────────────────────────────────────────
  bool get isAuthenticated => currentUser != null;
  String get role => currentUser?.role ?? 'Student Assistant';

  Future<void> init() async {
    try {
      await _initializeFirebaseAuthUser();
    } finally {
      sessionChecked = true;
      if (!_disposed) {
        // Until the listeners start, pages show loading rather than empty.
        if (currentUser != null) _beginLoadPending();
        notifyListeners();
      }
    }
    if (_disposed) return;
    await _ensureSeeded();
    if (_disposed) return;
    await _loadNotificationsForCurrentUser();
    _startRealtimeListeners();
  }

  /// How long a list may show its loading state before it gives up waiting
  /// (a slow or dropped connection) and shows what it has.
  static const loadTimeout = Duration(seconds: 10);

  /// A signed-in user is known but their listeners haven't started: lists
  /// show loading, and give up waiting after [loadTimeout].
  void _beginLoadPending() {
    if (_disposed) return;
    _loadTimeout?.cancel();
    _loadPending = true;
    _loadTimeout = Timer(loadTimeout, () {
      _loadPending = false;
      notifyListeners();
    });
  }

  /// Begins load tracking afresh for the listeners about to start. Runs once
  /// per (re)start, before any listener registers what it expects.
  void _resetLoadState() {
    _loadTimeout?.cancel();
    _loadPending = false;
    _loadExpected.clear();
    _loadReady.clear();
    _loadTracking = true;
    _loadTimeout = Timer(loadTimeout, () {
      if (_loadReady.length >= _loadExpected.length) return;
      _loadReady.addAll(_loadExpected);
      notifyListeners();
    });
  }

  /// Stops load tracking (sign-out), so a later session starts clean.
  void _clearLoadState() {
    _loadTimeout?.cancel();
    _loadPending = false;
    _loadExpected.clear();
    _loadReady.clear();
    _loadTracking = false;
  }

  /// What the members in the `part` files call to tell listeners: the
  /// ChangeNotifier's own method is protected and testing-only outside this
  /// class, which an extension counts as.
  void _notify() => notifyListeners();

  void _expectLoad(String label) => _loadExpected.add(label);

  void _markLoaded(String label) => _loadReady.add(label);

  /// Whether the live queries whose label starts with [prefix] ('Tasks',
  /// 'Reports', 'Users', ...) have each answered once. True for one this
  /// role never opens, and before the listeners have started at all.
  bool isLoaded(String prefix) {
    if (_loadPending) return false;
    if (!_loadTracking) return true;
    for (final label in _loadExpected) {
      if (label.startsWith(prefix) && !_loadReady.contains(label)) {
        return false;
      }
    }
    return true;
  }

  /// (Re)starts the Firestore listeners. Called on app start and again after
  /// login: the rules require a signed-in user, so listeners started before
  /// sign-in fail with permission-denied and would otherwise stay dead
  /// (leaving lists like announcements empty) until the app is restarted.
  void _startRealtimeListeners() {
    if (_disposed) return;
    _resetLoadState();
    // Start listening to Firestore announcements (if available).
    try {
      _firestoreService ??= FirestoreService();
      _annSub?.cancel();
      _expectLoad('Announcements');
      _annSub = _firestoreService!.announcementsStream().listen(
        (list) {
          _markLoaded('Announcements');
          announcements = list.map((m) {
            final createdAt = m['createdAt'];
            String postedAt = '';
            if (createdAt is Timestamp) {
              postedAt = createdAt.toDate().toString();
            } else if (createdAt is String) {
              postedAt = createdAt;
            } else if (m['postedAt'] != null) {
              postedAt = m['postedAt'].toString();
            }

            return Announcement(
              id: m['id'] ?? '',
              title: m['title'] ?? '',
              body: m['body'] ?? '',
              postedBy: m['postedBy'] ?? 'Admin',
              postedByRole: m['postedByRole'] ?? 'Admin',
              postedAt: postedAt,
              deadline: m['deadline'],
              slots: m['slots']?.toString(),
              requirements:
                  (m['requirements'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [],
              skills: [
                for (final skill in m['skills'] as List<dynamic>? ?? const [])
                  skill.toString(),
              ],
              isOpen: m['isOpen'] ?? true,
              acceptsApplications: m['acceptsApplications'] ?? true,
              postedById: m['postedById'],
              officeId: m['officeId'],
              officeName: m['officeName'],
              approvalStatus: m['approvalStatus'] ?? 'Approved',
              rejectionReason: m['rejectionReason'],
              academicYear: m['academicYear']?.toString(),
              attachmentName: m['attachmentName'],
              attachmentUrl: m['attachmentUrl'],
              attachmentPath: m['attachmentPath'],
              attachmentSize: (m['attachmentSize'] as num?)?.toDouble(),
            );
          }).toList();
          notifyListeners();
        },
        onError: (Object error) {
          debugPrint('Announcements stream error: $error');
          _markLoaded('Announcements');
          notifyListeners();
        },
      );
      // Start listening to attendance collection in real-time so supervisors
      // and admins see updates immediately without refreshing.
      _attSub?.cancel();
      final isStaffUser = role == 'Head' || role == 'Supervisor';
      final seesAllAttendance = isStaffUser || role == 'Admin';
      _expectLoad('Attendance');
      _attSub =
          (seesAllAttendance
                  ? _firestoreService!.attendanceStream()
                  : _firestoreService!.attendanceStreamForStudent(
                      currentUser!.id,
                    ))
              .listen(
                (list) {
                  _markLoaded('Attendance');
                  attendance = list
                      .map((m) => AttendanceRecord.fromJson(m))
                      .toList();
                  notifyListeners();
                  if (isStaffUser) invalidateMissedTimeOuts();
                  if (role == 'Student Assistant') remindToClockOutIfDue();
                },
                // Without this a rejected query (a missing index, say) kills
                // the subscription silently and the list just stays empty.
                onError: (Object error) {
                  debugPrint('Attendance stream error: $error');
                  _markLoaded('Attendance');
                  notifyListeners();
                },
              );

      // Head/Supervisor sessions periodically sweep for attendance records
      // whose session window closed while the student was still clocked in
      // (they missed their time-out), so those records stop counting
      // toward verified hours even if nothing else changes on the record.
      _missedTimeOutTimer?.cancel();
      if (isStaffUser) {
        _missedTimeOutTimer = Timer.periodic(
          const Duration(minutes: 1),
          (_) => invalidateMissedTimeOuts(),
        );
      }

      // Start listening to tasks collection in real-time so assigned tasks
      // propagate to student assistants automatically.
      _taskSub?.cancel();
      if (isStaffUser) {
        _expectLoad('Tasks');
        _taskSub = _firestoreService!.tasksStream().listen(
          (list) {
            _markLoaded('Tasks');
            tasks = list.map((m) => Task.fromJson(m)).toList();
            notifyListeners();
          },
          onError: (Object error) {
            debugPrint('Tasks stream error: $error');
            _markLoaded('Tasks');
            notifyListeners();
          },
        );
      }

      _appSub?.cancel();
      _expectLoad('Applications');
      _appSub =
          (isStaffUser
                  ? _firestoreService!.applicationsStream()
                  : _firestoreService!.applicationsStreamForApplicant(
                      currentUser!.id,
                    ))
              .listen(
                (list) {
                  _markLoaded('Applications');
                  applications = list
                      .map((m) => Application.fromJson(m))
                      .toList();
                  notifyListeners();
                },
                onError: (Object error) {
                  debugPrint('Applications stream error: $error');
                  _markLoaded('Applications');
                  notifyListeners();
                },
              );

      // Head/Supervisor: keep "Sent to Head" items in sync in real time so
      // a forward shows up immediately even if the Head's screen was
      // already open, or they logged in before it was sent.
      _headForwardsSub?.cancel();
      if (isStaffUser) {
        _expectLoad('Head forwards');
        _headForwardsSub = _firestoreService!.headForwardsStream().listen(
          (list) {
            _markLoaded('Head forwards');
            headForwards = list.map((m) => HeadForward.fromJson(m)).toList();
            notifyListeners();
          },
          onError: (Object error) {
            debugPrint('Head forwards stream error: $error');
            _markLoaded('Head forwards');
            notifyListeners();
          },
        );
      }

      // Admin: keep processed Payroll records in sync in real time.
      _payrollSub?.cancel();
      _payrollSheetsSub?.cancel();
      payrollRecordsLoaded = false;
      if (role == 'Admin') {
        _expectLoad('Payroll records');
        _expectLoad('Payroll sheets');
        _payrollSub = _firestoreService!.payrollRecordsStream().listen(
          (list) {
            payrollRecords = list
                .map((m) => PayrollRecord.fromJson(m))
                .toList();
            payrollRecordsLoaded = true;
            _markLoaded('Payroll records');
            notifyListeners();
          },
          // payrollRecordsLoaded stays false: payroll can't be approved
          // without knowing who has been paid.
          onError: (Object error) {
            debugPrint('Payroll records stream error: $error');
            _markLoaded('Payroll records');
            notifyListeners();
          },
        );
        _payrollSheetsSub = _firestoreService!.payrollSheetsStream().listen(
          (list) {
            payrollSheets = list.map((m) => PayrollSheet.fromJson(m)).toList();
            _markLoaded('Payroll sheets');
            notifyListeners();
          },
          onError: (Object error) {
            debugPrint('Payroll sheets stream error: $error');
            _markLoaded('Payroll sheets');
            notifyListeners();
          },
        );
      }
    } catch (_) {
      // Firestore not available or not initialized; ignore and keep in-memory behavior.
    }
    try {
      _startLiveData();
    } catch (error) {
      debugPrint('Live data unavailable: $error');
    }
    if (role != 'Admin') registerForPush();
    // After the notifications have loaded, so a Head's session can see one
    // it already has.
    _noticeAcademicYearEnding();
  }

  void _stopRealtimeListeners() {
    for (final sub in [
      _annSub,
      _attSub,
      _taskSub,
      _appSub,
      _headForwardsSub,
      _payrollSub,
      _payrollSheetsSub,
    ]) {
      sub?.cancel();
    }
    _missedTimeOutTimer?.cancel();
    _clockOutReminderTimer?.cancel();
    _archiveTimer?.cancel();
    for (final sub in _liveSubs) {
      sub.cancel();
    }
    _liveSubs.clear();
    _liveGeneration++;
    _clearLoadState();
  }

  /// Keeps the rest of the shared data live, so a change made in another
  /// browser — a new registration, an office assignment, an approved
  /// report, a notification, a new term — shows up without a refresh. Each
  /// listener only covers what the Firestore rules let this role read.
  void _startLiveData() {
    for (final sub in _liveSubs) {
      sub.cancel();
    }
    _liveSubs.clear();
    final generation = ++_liveGeneration;
    final user = currentUser;
    final fs = _firestoreService;
    if (user == null || fs == null) return;

    final isAdmin = role == 'Admin';
    final isHead = role == 'Head';
    final isStaff = isHead || role == 'Supervisor';

    void listen<T>(
      String label,
      Stream<T> stream,
      void Function(T data) onData,
    ) {
      _expectLoad(label);
      _liveSubs.add(
        stream.listen(
          (data) {
            try {
              onData(data);
            } catch (error) {
              debugPrint('$label update failed: $error');
            }
            _markLoaded(label);
            notifyListeners();
          },
          // Without this a rejected query dies silently and the list just
          // stops updating. It counts as answered: the list shows what it
          // has rather than loading forever.
          onError: (Object error) {
            debugPrint('$label stream error: $error');
            _markLoaded(label);
            notifyListeners();
          },
        ),
      );
    }

    // ── Everyone ──
    listen('Profile', fs.docStream('users', user.id), _onOwnProfileChanged);
    listen(
      'Notifications',
      fs.whereStream('notifications', 'userId', user.id, newestFirst: true),
      (list) => notifications = list.map(AppNotification.fromJson).toList(),
    );
    listen(
      'Academic settings',
      fs.docStream('meta', 'academic_year_settings'),
      (data) {
        if (data == null) return;
        final previousYear = academicYear;
        final previousTerm = '$academicYear|$academicSemester';
        _applyAcademicSettings(data);
        // The Admin archives the old year before saving the new one, so the
        // list already includes it.
        if (previousYear != academicYear) {
          fs
              .getAcademicYearArchives()
              .then((archives) {
                academicYearArchives = archives;
                _scheduleArchiveCheck();
                notifyListeners();
              })
              .catchError((Object error) {
                debugPrint('Failed to reload academic year archives: $error');
              });
          _restampUndoneAcademicYear();
        }
        // The end date may have moved.
        _scheduleArchiveCheck();
        _noticeAcademicYearEnding();
        // A new term is what puts pending rehire decisions into effect.
        if (isHead && previousTerm != '$academicYear|$academicSemester') {
          _applyDueRehireDecisions().then((_) => notifyListeners());
        }
      },
    );
    listen('Offices', fs.collectionStream('offices'), (list) {
      offices = list.map(Office.fromJson).toList();
      if (isHead) _cleanUpDeletedAccounts();
    });
    listen('Departments', fs.collectionStream('departments'), (list) {
      final named =
          list.where((d) => (d['name']?.toString() ?? '').isNotEmpty).toList()
            ..sort(
              (a, b) => a['name'].toString().compareTo(b['name'].toString()),
            );
      departments = [for (final d in named) d['name'].toString()];
      departmentCodes = {
        for (final d in named)
          d['name'].toString(): d['code']?.toString() ?? '',
      };
    });
    listen('Programs', fs.collectionStream('programs'), (list) {
      programs = _sortedPrograms(list.map(Program.fromJson));
    });
    listen('Skills', fs.collectionStream('skills'), (list) {
      _setSkills([
        for (final s in list)
          if ((s['name']?.toString() ?? '').isNotEmpty) s['name'].toString(),
      ]);
    });

    // ── Staff and Admin: the full roster ──
    if (isStaff || isAdmin) {
      listen('Users', fs.collectionStream('users'), (list) {
        _setAllUsers(list.map(User.fromJson).toList());
        // Only a Head or the Admin may publish it (firestore.rules).
        if (isHead || isAdmin) _publishHeadIds();
        if (isAdmin || isHead) _syncStudentIdClaims();
        if (isHead) _cleanUpDeletedAccounts();
      });
      listen('Students', fs.collectionStream('students'), (list) {
        students = list.map(Student.fromJson).toList();
        // Refill any department/campus the profiles take from students.
        _setUsers(users);
        if (isHead) _cleanUpDeletedAccounts();
      });
      listen(
        'Reports',
        fs.collectionStream('reports'),
        (list) => reports = list.map(Report.fromJson).toList(),
      );
    }

    // The Head checks the payroll requirements; the Admin's payroll waits
    // for them.
    if (isHead || isAdmin) {
      listen(
        'Payroll checks',
        fs.collectionStream('payrollChecks'),
        (list) => payrollChecks = list.map(PayrollCheck.fromJson).toList(),
      );
    }

    if (isStaff) {
      listen(
        'Evaluations',
        fs.collectionStream('evaluations'),
        (list) => evaluations = list.map(Evaluation.fromJson).toList(),
      );
      listen(
        'Documents',
        fs.collectionStream('documents'),
        (list) => documents = list.map(Document.fromJson).toList(),
      );
      listen(
        'Class schedules',
        fs.collectionStream('classSchedules'),
        (list) =>
            classSchedules = list.map(ClassScheduleEntry.fromJson).toList(),
      );
      // The built-in list applies until the Head first adds a category.
      listen('Task categories', fs.docStream('meta', 'task_categories'), (
        data,
      ) {
        final names = [
          for (final name in data?['names'] as List<dynamic>? ?? const [])
            if (name.toString().trim().isNotEmpty) name.toString(),
        ];
        if (names.isNotEmpty) taskCategories = names;
      });
      listen(
        'Task duties',
        fs.collectionStream('taskDuties'),
        (list) => taskDuties = list.map(TaskDuty.fromJson).toList(),
      );
      listen('Task templates', fs.docStream('meta', 'task_templates'), (data) {
        taskTemplates = [
          for (final item in data?['items'] as List<dynamic>? ?? const [])
            if (item is Map)
              TaskTemplate.fromJson(Map<String, dynamic>.from(item)),
        ].where((t) => t.id.isNotEmpty && t.title.isNotEmpty).toList();
      });
    }

    if (isHead) {
      listen(
        'Rehire records',
        fs.collectionStream('rehireRecords'),
        (list) => rehireRecords = list.map(RehireRecord.fromJson).toList(),
      );
      listen('Screening records', fs.collectionStream('screeningRecords'), (
        list,
      ) {
        screeningRecords = _dedupeScreeningRecords(
          list.map(ScreeningRecord.fromJson).toList(),
        );
      });
      listen(
        'Document folders',
        fs.collectionStream('documentFolders'),
        (list) =>
            documentFolders = _sortedFolders(list.map(DocumentFolder.fromJson)),
      );
    }

    // ── Student Assistants and Students: only their own records ──
    if (!isStaff && !isAdmin) {
      // Reports match by account id, and older ones by name, as on load.
      final reportsByQuery = <String, Map<String, Report>>{};
      void listenReports(String label, Stream<List<Map<String, dynamic>>> s) {
        listen(label, s, (list) {
          reportsByQuery[label] = {
            for (final m in list) m['id'].toString(): Report.fromJson(m),
          };
          reports = {
            for (final group in reportsByQuery.values) ...group,
          }.values.toList();
        });
      }

      listenReports(
        'Reports: own',
        fs.whereStream('reports', 'applicantId', user.id),
      );
      listenReports(
        'Reports: named',
        fs.whereStream('reports', 'studentName', user.name),
      );

      // Tasks match by account id, by name, or by their students record.
      final tasksByQuery = <String, Map<String, Task>>{};
      void listenTasks(String label, Stream<List<Map<String, dynamic>>> s) {
        listen(label, s, (list) {
          tasksByQuery[label] = {
            for (final m in list) m['id'].toString(): Task.fromJson(m),
          };
          tasks = {
            for (final group in tasksByQuery.values) ...group,
          }.values.toList();
        });
      }

      listenTasks(
        'Tasks: own',
        fs.whereStream('tasks', 'assignedTo', user.id),
      );
      listenTasks(
        'Tasks: named',
        fs.whereStream('tasks', 'assignedToName', user.name),
      );
      // Registered now, before the lookup, so Tasks isn't "loaded" while
      // this query is still to be opened.
      _expectLoad('Tasks: student record');
      fs
          .getStudentIdsForUser(user.id)
          .then((ids) {
            if (generation != _liveGeneration) return;
            if (ids.isEmpty) {
              _markLoaded('Tasks: student record');
              notifyListeners();
              return;
            }
            listenTasks(
              'Tasks: student record',
              fs.whereInStream('tasks', 'assignedTo', ids.take(10).toList()),
            );
          })
          .catchError((Object error) {
            debugPrint('Student-record tasks lookup failed: $error');
            if (generation != _liveGeneration) return;
            _markLoaded('Tasks: student record');
            notifyListeners();
          });

      listen(
        'Own task duties',
        fs.whereStream('taskDuties', 'assignedTo', user.id),
        (list) => taskDuties = list.map(TaskDuty.fromJson).toList(),
      );

      listen(
        'Own class schedule',
        fs.whereStream('classSchedules', 'studentId', user.id),
        (list) =>
            classSchedules = list.map(ClassScheduleEntry.fromJson).toList(),
      );
    }
  }

  /// Keeps the signed-in user's own profile in step with Firestore, so a
  /// change someone else makes to it — an approved application, a rehire
  /// decision, the Admin changing their role or archiving them — takes
  /// effect without signing out and back in.
  void _onOwnProfileChanged(Map<String, dynamic>? data) {
    final current = currentUser;
    if (data == null || current == null) return;
    final fresh = User.fromJson(data).copyWith(id: current.id);
    if (fresh.status == 'Archived') {
      signOut();
      return;
    }
    final roleChanged = fresh.role != current.role;
    currentUser = fresh;
    users = users.map((u) => u.id == fresh.id ? fresh : u).toList();
    if (roleChanged) {
      // Each role sees different screens and reads different data, so
      // start them over for the new one.
      activeTab = 'dashboard';
      // The old role's listeners go first; a sign-out (or another change)
      // while the data loads makes this reload stale.
      _stopRealtimeListeners();
      _beginLoadPending();
      final generation = _liveGeneration;
      _loadAllFromFirestore().then((_) {
        if (_loadIsStale(generation)) return;
        _startRealtimeListeners();
        notifyListeners();
      });
    }
  }

  Future<void> _initializeFirebaseAuthUser() async {
    try {
      final firebaseUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null || firebaseUser.email == null) return;

      final lowerEmail = firebaseUser.email!.toLowerCase();
      // Read the UID document directly. Email queries are denied by the
      // production Firestore rules and must not trigger a default role.
      User? existing = await _loadUserProfile(uid: firebaseUser.uid);
      if (existing == null) {
        try {
          existing = users.firstWhere((user) => user.id == firebaseUser.uid);
        } catch (_) {}
      }
      if (existing == null) {
        try {
          existing = users.firstWhere(
            (u) => u.email.toLowerCase() == lowerEmail,
          );
        } catch (_) {
          existing = null;
        }
      }

      if (existing == null) {
        final email = firebaseUser.email ?? '';
        existing = User(
          id: firebaseUser.uid,
          name: firebaseUser.displayName?.trim().isNotEmpty == true
              ? firebaseUser.displayName!
              : email.split('@').first,
          email: email,
          role: 'Student',
        );
        users = [existing, ...users];
      }

      if (existing.status == 'Archived') {
        await fb_auth.FirebaseAuth.instance.signOut();
        return;
      }

      currentUser = existing.copyWith(id: firebaseUser.uid);
      notifyListeners();
    } catch (error) {
      debugPrint('Firebase auth initialization failed: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Anything still waiting on an older generation (the student-record
    // lookup, say) now knows it is stale.
    _liveGeneration++;
    _annSub?.cancel();
    _attSub?.cancel();
    _taskSub?.cancel();
    _appSub?.cancel();
    _headForwardsSub?.cancel();
    _payrollSub?.cancel();
    _payrollSheetsSub?.cancel();
    _missedTimeOutTimer?.cancel();
    _clockOutReminderTimer?.cancel();
    _archiveTimer?.cancel();
    _clockOutReminderAlerts.close();
    _problemNotices.close();
    _pushMessagesSub?.cancel();
    _loadTimeout?.cancel();
    for (final sub in _liveSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _saveUserProfile(User user) async {
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setUserProfile(user);
  }

  Future<User?> _loadUserProfile({String? uid, String? email}) async {
    try {
      _firestoreService ??= FirestoreService();
      if (uid != null && uid.isNotEmpty) {
        final profile = await _firestoreService!.getUserProfileById(uid);
        if (profile != null) return profile;
      }
      if (email != null && email.isNotEmpty) {
        return await _firestoreService!.getUserProfileByEmail(
          email.toLowerCase(),
        );
      }
    } catch (error) {
      debugPrint('Failed to load user profile: $error');
    }
    return null;
  }

  Future<bool> registerUser(User user, String password) async {
    await _ensureSeeded();
    await _upsertUser(user);
    await _saveUserProfile(user);
    await login(user);
    return true;
  }

  Future<void> _upsertUser(User user) async {
    // Replace existing user by id or email, otherwise insert.
    final normalizedEmail = user.email.toLowerCase();
    final existingIndex = users.indexWhere(
      (u) => u.id == user.id || u.email.toLowerCase() == normalizedEmail,
    );
    if (existingIndex >= 0) {
      users[existingIndex] = user;
    } else {
      users = [user, ...users];
    }
    // Keep list unique by email (first occurrence wins)
    final seen = <String>{};
    users = users.where((u) {
      final e = u.email.toLowerCase();
      if (seen.contains(e)) return false;
      seen.add(e);
      return true;
    }).toList();
  }

  /// Seeds mock data (once) and merges in any accounts previously created
  /// via the Register screen, so they persist across app restarts.
  Future<void> _ensureSeeded() async {
    if (_isDataSeeded) return;
    final existingLoad = _dataSeedFuture;
    if (existingLoad != null) {
      await existingLoad;
      return;
    }

    final load = _loadAllFromFirestore();
    _dataSeedFuture = load;
    await load;
    _isDataSeeded = true;
  }

  Future<User?> authenticateRegisteredUser(
    String email,
    String password,
  ) async {
    final lowerEmail = email.toLowerCase();
    final profile = await _loadUserProfile(email: lowerEmail);
    if (profile == null) return null;
    if (profile.status == 'Archived') return null;
    // Firebase Authentication verifies password, so only allow login if the
    // email/password sign in succeeds.
    try {
      final credential = await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final authUser = credential.user;
      if (authUser != null && !authUser.emailVerified) {
        // Correct password, but the email still isn't verified — don't let
        // this fallback path log the user in.
        return null;
      }
      if (authUser != null) {
        return profile;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool> login(User user, {bool preferProvidedProfile = false}) async {
    await _ensureSeeded();
    final profile = await _loadUserProfile(uid: user.id, email: user.email);
    var authenticatedUser = preferProvidedProfile ? user : profile ?? user;
    fb_auth.User? firebaseUser;
    try {
      firebaseUser = fb_auth.FirebaseAuth.instance.currentUser;
    } catch (error) {
      // No Firebase app (as in tests): go on with the stored profile.
      debugPrint('Firebase auth unavailable: $error');
    }
    if (!preferProvidedProfile &&
        firebaseUser != null &&
        firebaseUser.uid.isNotEmpty &&
        firebaseUser.email?.toLowerCase() == user.email.toLowerCase()) {
      try {
        _firestoreService ??= FirestoreService();
        authenticatedUser = await _firestoreService!
            .migrateUserProfileToAuthUid(
              uid: firebaseUser.uid,
              email: firebaseUser.email!,
              fallback: authenticatedUser,
            );
      } catch (error) {
        debugPrint('Failed to migrate user profile to Firebase UID: $error');
        authenticatedUser = authenticatedUser.copyWith(id: firebaseUser.uid);
      }
    }
    if (authenticatedUser.status == 'Archived') {
      currentUser = null;
      try {
        await fb_auth.FirebaseAuth.instance.signOut();
      } catch (_) {}
      notifyListeners();
      return false;
    }
    currentUser = authenticatedUser;

    users = users.map((u) {
      if (u.id == currentUser!.id ||
          u.email.toLowerCase() == currentUser!.email.toLowerCase()) {
        return currentUser!;
      }
      return u;
    }).toList();
    if (!users.any(
      (u) =>
          u.id == currentUser!.id ||
          u.email.toLowerCase() == currentUser!.email.toLowerCase(),
    )) {
      users = [...users, currentUser!];
    }

    // Load role-scoped data after the authenticated profile is established.
    // Without this, login can briefly show empty lists until a browser refresh.
    await _loadAllFromFirestore();
    await _loadNotificationsForCurrentUser();
    _startRealtimeListeners();
    notifyListeners();
    return true;
  }

  /// Sends a password reset email via Firebase Auth. Returns null on
  /// success, or a user-friendly error message on failure.
  Future<String?> sendPasswordResetEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      return 'Please enter your email address.';
    }
    if (!(normalizedEmail.endsWith('@gmail.com') ||
        normalizedEmail.endsWith('@marsu.edu.ph'))) {
      return 'Enter a valid Gmail address or MSU email (@marsu.edu.ph).';
    }

    try {
      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(
        email: normalizedEmail,
      );
      return null;
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        // Don't reveal whether the account exists — just report success so
        // this can't be used to enumerate registered emails.
        return null;
      }
      if (e.code == 'invalid-email') {
        return 'Enter a valid email address.';
      }
      return e.message ?? 'Unable to send reset email: ${e.code}';
    } catch (error) {
      return 'Unable to send reset email: $error';
    }
  }

  /// What [signInWithEmailAndPassword] returns when the password is right
  /// but the email isn't verified yet. The Login page shows a "Send a new
  /// link" button with it.
  static const unverifiedEmailMessage =
      'Your email address isn\'t verified yet. Open the link in the newest '
      'verification email we sent (check Spam too), then log in again. If '
      'the link says it has expired or was already used, send a new one.';

  /// Whether the last sign-in asked to stay signed in on this device. It
  /// decides how long Firebase keeps the session: on this device until
  /// someone signs out ("Remember me"), or only until the tab is closed.
  bool? _rememberChoice;

  @visibleForTesting
  bool? get rememberChoice => _rememberChoice;

  /// Tells Firebase how long to keep the sign-in about to happen. Must be
  /// set before the sign-in (and again for a Google one, which signs in
  /// separately). Web only; elsewhere there is nothing to choose.
  Future<void> _applyPersistence(bool remember) async {
    _rememberChoice = remember;
    if (!kIsWeb) return;
    try {
      await fb_auth.FirebaseAuth.instance.setPersistence(
        remember ? fb_auth.Persistence.LOCAL : fb_auth.Persistence.SESSION,
      );
    } catch (error) {
      debugPrint('Could not set the sign-in persistence: $error');
    }
  }

  /// What the Login page says after a sign-out the person didn't ask for,
  /// shown once ([takeSignOutNotice]).
  String? _signOutNotice;

  String? takeSignOutNotice() {
    final notice = _signOutNotice;
    _signOutNotice = null;
    return notice;
  }

  /// Signs out someone who has been idle for [after], and says why on the
  /// Login page.
  Future<void> signOutForInactivity(Duration after) async {
    final minutes = after.inMinutes;
    _signOutNotice =
        'You were signed out after $minutes minutes without activity. Log '
        'in again to continue.';
    await signOut();
  }

  Future<String?> signInWithEmailAndPassword(
    String email,
    String password, {
    bool remember = true,
  }) async {
    final lowerEmail = email.toLowerCase();

    try {
      await _applyPersistence(remember);
      final credential = await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final authUser = credential.user;
      if (authUser == null) {
        return 'Unable to log in. Please try again.';
      }

      if (!authUser.emailVerified) {
        // No new link here: each one makes the earlier ones stop working,
        // so sending one on every attempt broke the link people were
        // about to open. The Login page offers "Send a new link"
        // (sendNewVerificationLink) instead.
        await fb_auth.FirebaseAuth.instance.signOut();
        return unverifiedEmailMessage;
      }

      User? existing = await _loadUserProfile(uid: authUser.uid);
      if (existing == null) {
        try {
          existing = users.firstWhere(
            (u) => u.email.toLowerCase() == lowerEmail,
          );
        } catch (_) {
          existing = null;
        }
      }

      if (existing == null) {
        existing = User(
          id: authUser.uid,
          name: authUser.displayName?.trim().isNotEmpty == true
              ? authUser.displayName!
              : email.split('@').first,
          email: email,
          role: 'Student',
        );
        await _saveUserProfile(existing);
        users = [existing, ...users];
      }

      if (existing.status == 'Archived') {
        await fb_auth.FirebaseAuth.instance.signOut();
        return 'This account has been deactivated. Please contact an administrator.';
      }

      await login(existing.copyWith(id: authUser.uid));
      return null;
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('Login failed: ${e.code}');
      return friendlyAuthError(e.code);
    } catch (error) {
      debugPrint('Login failed: $error');
      return friendlyAuthError(null);
    }
  }

  /// For the Login page's "Send a new link": emails [email] a new
  /// verification link. Firebase sends links only to a signed-in account,
  /// so this signs in with [password] and straight back out. If the email
  /// turns out to be verified already (the link worked after all, or a
  /// mail scanner opened it first), nothing is sent: logging in works.
  Future<({bool ok, String message})> sendNewVerificationLink(
    String email,
    String password,
  ) async {
    final auth = fb_auth.FirebaseAuth.instance;
    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final authUser = credential.user;
      if (authUser == null) {
        return (ok: false, message: 'Unable to send a new link. Try again.');
      }
      if (authUser.emailVerified) {
        await auth.signOut();
        return (
          ok: true,
          message:
              'Your email address is already verified. You can log in now.',
        );
      }
      await _sendVerificationEmail(authUser);
      await auth.signOut();
      return (
        ok: true,
        message:
            'A new verification link was sent to ${authUser.email ?? email}. '
            'Open it from the newest email (earlier links no longer work), '
            'then log in here.',
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      await _signOutQuietly();
      if (e.code == 'too-many-requests') {
        return (
          ok: false,
          message:
              'Too many links were sent. Wait a few minutes, then try again.',
        );
      }
      return (
        ok: false,
        message: e.message ?? 'Unable to send a new link: ${e.code}',
      );
    } catch (error) {
      await _signOutQuietly();
      return (ok: false, message: 'Unable to send a new link: $error');
    }
  }

  Future<void> _signOutQuietly() async {
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  /// Emails [authUser] a verification link. Firebase's "email verified"
  /// page then has a Continue button back to this app's Login page. Each
  /// new link makes the earlier ones stop working, so send one only when
  /// an account is made or someone asks for it.
  Future<void> _sendVerificationEmail(fb_auth.User authUser) async {
    final base = Uri.base;
    if (kIsWeb && (base.scheme == 'http' || base.scheme == 'https')) {
      try {
        await authUser.sendEmailVerification(
          // AppRoutes.login.
          fb_auth.ActionCodeSettings(url: '${base.origin}/login'),
        );
        return;
      } on fb_auth.FirebaseAuthException catch (e) {
        // A domain missing from Firebase's authorized list: send the link
        // without a Continue button rather than not at all.
        if (!e.code.contains('continue-uri')) rethrow;
      }
    }
    await authUser.sendEmailVerification();
  }

  Future<String?> signInWithGoogle({bool remember = true}) async {
    await _ensureSeeded();

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return 'Google login was cancelled.';
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        return 'Google authentication failed. Please try again.';
      }

      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      try {
        await _applyPersistence(remember);
        final result = await fb_auth.FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        final authUser = result.user;
        if (authUser == null) {
          return 'Google login failed. Please try again.';
        }

        final email = authUser.email?.toLowerCase() ?? '';
        // Prefer Firestore profile first to avoid local seeded data conflicts.
        // Look up by uid first: registered accounts are stored under their
        // Firebase uid, and the Firestore rules only let a non-staff user read
        // their own document (an email query is denied for them).
        User? existing = await _loadUserProfile(
          uid: authUser.uid,
          email: email,
        );
        if (existing == null) {
          try {
            existing = users.firstWhere((u) => u.email.toLowerCase() == email);
          } catch (_) {
            existing = null;
          }
        }

        // Google sign-in must not create accounts. Firebase has just created
        // (or reused) an auth user for this Google account, but if nobody
        // registered it in SAIS there is no profile, so reject the sign-in
        // the same way email/password login does.
        if (existing == null) {
          final isNewAuthUser = result.additionalUserInfo?.isNewUser ?? false;
          try {
            if (isNewAuthUser) {
              // Don't leave an orphan auth user behind for an unregistered
              // Google account.
              await authUser.delete();
            }
          } catch (_) {}
          try {
            await fb_auth.FirebaseAuth.instance.signOut();
          } catch (_) {}
          try {
            await _googleSignIn.signOut();
          } catch (_) {}
          return 'No account found for this Google account. '
              'Please register first, then log in.';
        }

        if (existing.status == 'Archived') {
          await fb_auth.FirebaseAuth.instance.signOut();
          return 'This account has been deactivated. Please contact an administrator.';
        }

        await login(existing.copyWith(id: authUser.uid));
        return null;
      } on fb_auth.FirebaseAuthException catch (e) {
        if (e.code == 'account-exists-with-different-credential') {
          final email = googleUser.email.toLowerCase();
          final linkedError = await _linkExistingEmailPasswordAccountToGoogle(
            email,
            credential,
          );
          return linkedError;
        }
        debugPrint('Google login failed: ${e.code}');
        return friendlyAuthError(e.code);
      }
    } catch (error) {
      debugPrint('Google login failed: $error');
      return 'Google login failed. Please try again.';
    }
  }

  /// Whether the signed-in account has Google linked.
  ///
  /// Unlike the sign-in methods below, this is read while *building* the
  /// profile screen, so throwing here takes the screen down rather than
  /// failing an action the user asked for. Before Firebase is initialised
  /// it reports false instead; every other Firebase error still surfaces.
  bool get isGoogleAccountLinked {
    try {
      return fb_auth.FirebaseAuth.instance.currentUser?.providerData.any(
            (provider) => provider.providerId == 'google.com',
          ) ??
          false;
    } on FirebaseException catch (e) {
      if (e.code == 'no-app') return false;
      rethrow;
    }
  }

  Future<String?> linkGoogleAccount() async {
    final authUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return 'Please log in before linking a Google account.';
    }
    if (isGoogleAccountLinked) {
      return 'A Google account is already linked to this account.';
    }

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return 'Google linking was cancelled.';

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        return 'Google authentication failed. Please try again.';
      }

      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await authUser.linkWithCredential(credential);
      notifyListeners();
      return null;
    } on fb_auth.FirebaseAuthException catch (error) {
      if (error.code == 'credential-already-in-use' ||
          error.code == 'account-exists-with-different-credential') {
        return 'This Google account is already linked to another account.';
      }
      if (error.code == 'provider-already-linked') {
        return 'A Google account is already linked to this account.';
      }
      return error.message ?? 'Unable to link Google account: ${error.code}';
    } catch (error) {
      return 'Unable to link Google account: $error';
    }
  }

  Future<String?> _linkExistingEmailPasswordAccountToGoogle(
    String email,
    fb_auth.AuthCredential googleCredential,
  ) async {
    return 'Google login failed because this account exists with a different credential. Please use the existing login provider for this account.';
  }

  Future<String?> registerWithEmail(User user, String password) async {
    final normalizedEmail = user.email.trim().toLowerCase();
    if (!(normalizedEmail.endsWith('@gmail.com') ||
        normalizedEmail.endsWith('@marsu.edu.ph'))) {
      return 'Please register with a valid Gmail address or MSU email (@marsu.edu.ph).';
    }

    final studentId = user.studentId?.trim() ?? '';
    final studentIdKey = AppState.studentIdKey(studentId);
    if (studentId.isNotEmpty && studentIdKey == null) {
      return 'Please enter a valid Student ID.';
    }

    await _ensureSeeded();

    // Create the email/password account directly — no Google sign-in popup
    // during registration. Instead, Firebase sends a verification email to
    // the Gmail address the user provided. The user can link their Google
    // account later from the Profile section if they want to.
    final fb_auth.User authUser;
    try {
      final credential = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: user.email,
            password: password,
          );
      final created = credential.user;
      if (created == null) {
        return 'Unable to create account. Please try again.';
      }
      authUser = created;
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return 'An account with this email already exists.';
      }
      if (e.code == 'weak-password') return 'Password is too weak.';
      return e.message ?? 'Registration failed: ${e.code}';
    } catch (error) {
      return 'Registration failed: $error';
    }

    // Save the profile, then reserve its Student ID. Nobody can look up
    // other profiles before signing in, so the reservation is the check:
    // the rules let an account reserve only the ID on its own profile, and
    // never take one that's already reserved. If this ID is, or anything
    // else fails, the registration is undone so the email can try again.
    var profileSaved = false;
    var idReserved = false;
    try {
      _firestoreService ??= FirestoreService();
      await _saveUserProfile(user.copyWith(id: authUser.uid));
      profileSaved = true;
      if (studentIdKey != null) {
        idReserved = await _firestoreService!.claimStudentId(
          studentIdKey,
          authUser.uid,
        );
        if (!idReserved) {
          await _undoRegistration(authUser, deleteProfile: true);
          return 'This Student ID is already registered to another account.';
        }
      }
      await _sendVerificationEmail(authUser);
    } catch (error) {
      await _undoRegistration(
        authUser,
        deleteProfile: profileSaved,
        releaseStudentId: idReserved ? studentIdKey : null,
      );
      return 'Registration failed: $error';
    }

    // Don't fully log the user in yet — they still need to verify their
    // Gmail address. Sign them out of the Firebase session so the login
    // screen's existing "please verify your Gmail" check takes over the
    // next time they try to sign in.
    await fb_auth.FirebaseAuth.instance.signOut();
    return null;
  }

  /// The key a Student ID is reserved under in `studentIds`: trimmed and
  /// upper-case, so "23b0626 " and "23B0626" are one ID. Null when there's
  /// no ID, or one that can't name a document (it holds a "/").
  static String? studentIdKey(String? studentId) {
    final key = (studentId ?? '').trim().toUpperCase();
    if (key.isEmpty || key.contains('/') || key == '.' || key == '..') {
      return null;
    }
    return key;
  }

  /// Takes back a registration that couldn't finish — its reservation, its
  /// profile, then the sign-in itself (the rules allow the first two only
  /// while it's still signed in and unverified) — so the email and Student
  /// ID are free to register again.
  Future<void> _undoRegistration(
    fb_auth.User authUser, {
    required bool deleteProfile,
    String? releaseStudentId,
  }) async {
    try {
      if (releaseStudentId != null) {
        await _firestoreService!.releaseStudentId(releaseStudentId);
      }
    } catch (error) {
      debugPrint('Failed to release Student ID: $error');
    }
    try {
      if (deleteProfile) {
        await _firestoreService!.deleteUserProfile(authUser.uid);
      }
    } catch (error) {
      debugPrint('Failed to remove unfinished profile: $error');
    }
    try {
      await authUser.delete();
    } catch (error) {
      debugPrint('Failed to remove unfinished sign-in: $error');
    }
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  Future<void> signOut() async {
    // While still signed in: only the owner may delete it.
    await _forgetPushToken();
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (_) {}

    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    try {
      await _googleSignIn.disconnect();
    } catch (_) {}

    logout();
  }

  void logout() {
    // The listeners belong to the signed-out account; left running they
    // only fail with permission errors.
    _stopRealtimeListeners();
    currentUser = null;
    activeTab = 'dashboard';
    _academicYearShown = null;
    academicYearOpenedFrom = null;
    _forgetAccountData();
    notifyListeners();
  }

  /// Empties everything the signed-out account could see, so the next person
  /// to sign in on this browser starts with none of it (payroll, the roster,
  /// reports, notifications). The reference data every role loads (offices,
  /// departments, skills, announcements) stays.
  void _forgetAccountData() {
    users = [];
    students = [];
    attendance = [];
    classSchedules = [];
    tasks = [];
    taskDuties = [];
    reports = [];
    evaluations = [];
    rehireRecords = [];
    headForwards = [];
    payrollRecords = [];
    payrollRecordsLoaded = false;
    payrollSheets = [];
    payrollChecks = [];
    applications = [];
    screeningRecords = [];
    notifications = [];
    documents = [];
    documentFolders = [];
    _deletedAccounts = [];
  }

  // ─── Navigation ────────────────────────────────────
  // The address bar follows these: AppRouterDelegate writes the page shown
  // here into it, and opens the page an address names.

  /// The page a signed-out visitor sees.
  PublicPage publicPage = PublicPage.landing;

  void showPublicPage(PublicPage page) {
    if (publicPage == page) return;
    publicPage = page;
    notifyListeners();
  }

  /// Whether startup has finished restoring a signed-in session. Until
  /// then, a link to a signed-in page waits rather than showing Login.
  bool sessionChecked = false;

  void setTab(String tab) {
    activeTab = tab;
    notifyListeners();
  }

  /// The Academic Year page's tab: what archiving one year saves. It isn't
  /// in the sidebar; [openAcademicYear] opens it.
  static const academicYearTab = 'academic_year';

  String? _academicYearShown;

  /// The page the Academic Year page was opened from, which its Back
  /// button returns to and the sidebar keeps highlighted.
  String? academicYearOpenedFrom;

  /// The year the Academic Year page shows: the one opened, else the one
  /// waiting to be archived, else the year in effect.
  String get academicYearShown =>
      _academicYearShown ?? pendingArchive?.year ?? academicYear;

  /// Opens the Academic Year page on [year], or on [academicYearShown]'s
  /// default when null.
  void openAcademicYear(String? year) {
    if (activeTab != academicYearTab) academicYearOpenedFrom = activeTab;
    _academicYearShown = year;
    activeTab = academicYearTab;
    notifyListeners();
  }

  /// Whether a load that began under [generation] has been overtaken: the
  /// listeners restarted, the account signed out, or the state was disposed.
  /// Its late answers must not be written into the lists.
  bool _loadIsStale(int generation) =>
      _disposed || currentUser == null || generation != _liveGeneration;

  Future<void> _loadAllFromFirestore() async {
    _firestoreService ??= FirestoreService();
    final service = _firestoreService!;
    final generation = _liveGeneration;
    // After every answer, before it is used: if the account signed out or
    // another session began meanwhile, this load's answers belong to nobody
    // (a private list must not reappear for the next person), so it stops.
    bool overtaken() => _loadIsStale(generation);
    try {
      // Users: prefer Firestore as source-of-truth, but keep currentUser if not present.
      List<User> firestoreUsers = [];
      try {
        final fetched = await service.getAllUserProfiles();
        if (overtaken()) return;
        firestoreUsers = fetched;
      } catch (error) {
        debugPrint('Failed to load user profiles: $error');
      }

      Map<String, dynamic>? academicSettings;
      try {
        academicSettings = await service.getAcademicYearSettings();
      } catch (error) {
        debugPrint('Failed to load academic settings: $error');
      }
      if (overtaken()) return;
      if (academicSettings != null) _applyAcademicSettings(academicSettings);
      try {
        final fetched = await service.getAcademicYearArchives();
        if (overtaken()) return;
        academicYearArchives = fetched;
      } catch (_) {
        if (overtaken()) return;
        academicYearArchives = [];
      }
      try {
        final fetched = await service.getAllOffices();
        if (overtaken()) return;
        offices = fetched;
      } catch (_) {
        if (overtaken()) return;
        offices = [];
      }
      try {
        final storedDepartments = await service.getAllDepartments();
        final codes = await service.getDepartmentCodes();
        if (overtaken()) return;
        departments = storedDepartments;
        departmentCodes = codes;
      } catch (_) {}
      try {
        final fetched = await service.getAllPrograms();
        if (overtaken()) return;
        programs = _sortedPrograms(fetched);
      } catch (_) {}
      try {
        final fetched = await service.getAllSkills();
        if (overtaken()) return;
        _setSkills(fetched);
      } catch (_) {}
      try {
        final fetched = await service.getAllScreeningRecords();
        if (overtaken()) return;
        screeningRecords = _dedupeScreeningRecords(fetched);
      } catch (_) {}

      // Students
      try {
        final fsStudents = await service.getAllStudents();
        if (overtaken()) return;
        students = fsStudents;
      } catch (_) {
        if (overtaken()) return;
        students = [];
      }

      if (overtaken()) return;
      _setAllUsers(firestoreUsers);

      // Attendance
      try {
        final rawAttendance =
            (role == 'Head' || role == 'Supervisor' || role == 'Admin')
            ? await service.getAllAttendance()
            : await service.getAttendanceForStudent(currentUser!.id);
        if (overtaken()) return;
        attendance = rawAttendance
            .map((m) => AttendanceRecord.fromJson(m))
            .toList();
      } catch (_) {
        if (overtaken()) return;
        attendance = [];
      }

      // Class Schedules (weekly, used to auto-fill DTR/Accomplishment
      // Report's Class Schedule grid)
      try {
        final fetched = (role == 'Head' || role == 'Supervisor')
            ? await service.getAllClassSchedules()
            : await service.getClassSchedulesForStudent(currentUser!.id);
        if (overtaken()) return;
        classSchedules = fetched;
      } catch (_) {
        if (overtaken()) return;
        classSchedules = [];
      }
      if (overtaken()) return;
      await _archiveFinishedAcademicYears(academicSettings);
      await _restampUndoneAcademicYear();
      if (overtaken()) return;

      // Tasks
      try {
        final fsTasks = <Task>[];
        if (role == 'Head' || role == 'Supervisor') {
          fsTasks.addAll(await service.getAllTasks());
        } else {
          try {
            fsTasks.addAll(await service.getTasksForUser(currentUser!.id));
          } catch (_) {}
          try {
            final studentIds = await service.getStudentIdsForUser(
              currentUser!.id,
            );
            fsTasks.addAll(await service.getTasksForAssigneeIds(studentIds));
          } catch (_) {}
          // No lookup by name: the Firestore rules only share a task with
          // the account it is assigned to, since anyone can register under
          // a classmate's name.
        }
        if (overtaken()) return;
        final taskById = <String, Task>{
          for (final task in fsTasks) task.id: task,
        };
        tasks = taskById.values.toList();
      } catch (_) {
        if (overtaken()) return;
        tasks = [];
      }

      // Reports
      try {
        final fsReports =
            (role == 'Head' || role == 'Supervisor' || role == 'Admin')
            ? await service.getAllReports()
            // By account only, never by name — see Tasks above.
            : await service.getReportsForApplicant(currentUser!.id);
        if (overtaken()) return;
        reports = fsReports;
      } catch (_) {
        if (overtaken()) return;
        reports = [];
      }

      // Performance Evaluations
      try {
        final fsEvaluations = await service.getAllEvaluations();
        if (overtaken()) return;
        evaluations = fsEvaluations;
      } catch (_) {
        if (overtaken()) return;
        evaluations = [];
      }

      // Rehire decisions. Any whose term has started since they were made
      // are put into effect now — only a Head may change the roster records
      // involved, so this runs in the Head's session.
      if (role == 'Head') {
        try {
          final fetched = await service.getAllRehireRecords();
          if (overtaken()) return;
          rehireRecords = fetched;
          await _applyDueRehireDecisions();
        } catch (_) {
          if (overtaken()) return;
          rehireRecords = [];
        }
        await _syncOfficeAssignments();
        await _moveSchedulesToAccounts(firestoreUsers);
      }

      // Items supervisors have forwarded to the Head.
      if (role == 'Head' || role == 'Supervisor') {
        try {
          final fetched = await service.getAllHeadForwards();
          if (overtaken()) return;
          headForwards = fetched;
        } catch (_) {
          if (overtaken()) return;
          headForwards = [];
        }
      }

      // Applications
      try {
        final fsApps = await service.getAllApplications();
        if (overtaken()) return;
        applications = fsApps;
        await _syncApprovedApplicationSkills();
      } catch (_) {
        if (overtaken()) return;
        applications = [];
      }
      // Documents
      try {
        final fsDocs = await service.getAllDocuments();
        if (overtaken()) return;
        documents = fsDocs;
      } catch (_) {
        if (overtaken()) return;
        documents = [];
      }
      // Document Folders
      try {
        final fetched = await service.getAllDocumentFolders();
        if (overtaken()) return;
        documentFolders = _sortedFolders(fetched);
      } catch (_) {
        if (overtaken()) return;
        documentFolders = [];
      }

      if (overtaken()) return;
      notifications = [];

      // Ensure currentUser (if set by auth) is present in users
      if (currentUser != null &&
          !users.any(
            (u) => u.email.toLowerCase() == currentUser!.email.toLowerCase(),
          )) {
        users = [currentUser!, ...users];
      }
      // Check system health after loading data
      await checkSystemStatus();
    } catch (error) {
      // If Firestore isn't available, keep lists empty to avoid showing mock data
      debugPrint('Failed to load data from Firestore: $error');
    }
  }

  void _applyAcademicSettings(Map<String, dynamic> settings) {
    academicYear = settings['academicYear']?.toString() ?? academicYear;
    academicSemester = settings['semester']?.toString() ?? academicSemester;
    academicYearStart =
        DateTime.tryParse(settings['startDate']?.toString() ?? '') ??
        academicYearStart;
    academicYearEnd =
        DateTime.tryParse(settings['endDate']?.toString() ?? '') ??
        academicYearEnd;
    allowAcademicApplications =
        settings['allowApplications'] as bool? ?? allowAcademicApplications;
    enforceAssistantHourCap =
        settings['enforceHourCap'] as bool? ?? enforceAssistantHourCap;
    autoArchiveAttendanceLogs =
        settings['autoArchiveLogs'] as bool? ?? autoArchiveAttendanceLogs;
    academicMilestones =
        (settings['milestones'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((milestone) => Map<String, dynamic>.from(milestone))
            .toList() ??
        [];
    final previous = settings['previous'];
    _previousAcademicTerm = previous is Map
        ? Map<String, dynamic>.from(previous)
        : null;
    _termChangedAt = DateTime.tryParse(
      settings['termChangedAt']?.toString() ?? '',
    );
    _undoneAcademicYear = settings['undoneAcademicYear']?.toString();
  }

  /// When the last academic year or semester change stops being undoable,
  /// or null if there's none to undo.
  DateTime? get termChangeUndoDeadline =>
      _previousAcademicTerm == null || _termChangedAt == null
      ? null
      : _termChangedAt!.toLocal().add(termChangeUndoWindow);

  bool get canUndoTermChange =>
      termChangeUndoDeadline?.isAfter(DateTime.now()) ?? false;

  /// Days left until the academic year's last day — 0 on it, negative once
  /// it has passed. Records are filed under the year in the settings, so
  /// the Admin is reminded to start the next one before this runs out.
  int get daysUntilAcademicYearEnds {
    final now = DateTime.now();
    final end = academicYearEnd;
    return DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  }

  /// "2nd Semester, AY 2026-2027" — the term [undoTermChange] goes back to.
  String? get previousTermLabel {
    final previous = _previousAcademicTerm;
    if (previous == null) return null;
    return RehireRecord.termLabelFor(
      previous['academicYear']?.toString() ?? '',
      previous['semester']?.toString() ?? '',
    );
  }

  /// Dedupes only within the same applicant + academic year, so a
  /// re-screening in a later academic year is kept as its own historical
  /// record instead of being collapsed into one row.
  List<ScreeningRecord> _dedupeScreeningRecords(List<ScreeningRecord> loaded) {
    final byApplicantYear = <String, ScreeningRecord>{};
    for (final record in loaded) {
      final normalizedName = record.fullName.trim().toLowerCase();
      final normalizedStudentNumber = record.studentNumber.trim().toLowerCase();
      final identity =
          normalizedName.isNotEmpty && normalizedStudentNumber.isNotEmpty
          ? '$normalizedName|$normalizedStudentNumber'
          : (record.applicantId.trim().isNotEmpty
                ? record.applicantId
                : (record.applicationId.trim().isNotEmpty
                      ? record.applicationId
                      : record.id));
      final key = '$identity|${record.academicYear ?? ''}';
      final existing = byApplicantYear[key];
      if (existing == null ||
          (record.id.startsWith('screen-') &&
              !existing.id.startsWith('screen-')) ||
          record.interviewerDate.compareTo(existing.interviewerDate) > 0) {
        byApplicantYear[key] = record;
      }
    }
    return byApplicantYear.values.toList()
      ..sort((a, b) => b.interviewerDate.compareTo(a.interviewerDate));
  }

  /// Replaces [users] with the Firestore profiles: duplicates sharing an
  /// email are merged into one, the signed-in user is always kept, and a
  /// missing department/campus is filled in from the matching students
  /// record. Call after [students] is loaded.
  /// The accounts the Admin deleted, as the whole roster last listed them.
  /// They stay on file to block sign-in, are hidden from every list, and
  /// leave behind roster records and office places for the Head's session to
  /// clear ([_cleanUpDeletedAccounts]).
  List<User> _deletedAccounts = [];

  /// [_setUsers] for a full roster from Firestore (the one place that knows
  /// which accounts are deleted).
  void _setAllUsers(List<User> all) {
    _deletedAccounts = [
      for (final u in all)
        if (u.isDeleted) u,
    ];
    _setUsers(all);
  }

  void _setUsers(List<User> firestoreUsers) {
    String? pick(String? existing, String? other) =>
        existing != null && existing.isNotEmpty ? existing : other;

    final byEmail = <String, User>{};
    // Deleted accounts only stay on file to block their sign-in.
    for (final u in firestoreUsers.where((u) => !u.isDeleted)) {
      final key = u.email.toLowerCase();
      final existing = byEmail[key];
      byEmail[key] = existing == null
          ? u
          : existing.copyWith(
              department: pick(existing.department, u.department),
              campus: pick(existing.campus, u.campus),
              courseProgram: pick(existing.courseProgram, u.courseProgram),
              yearLevel: pick(existing.yearLevel, u.yearLevel),
              studentId: pick(existing.studentId, u.studentId),
              phone: pick(existing.phone, u.phone),
              address: pick(existing.address, u.address),
              avatar: pick(existing.avatar, u.avatar),
              skills: existing.skills.isNotEmpty ? existing.skills : u.skills,
              status: existing.status != 'Archived'
                  ? existing.status
                  : u.status,
              role: existing.role != 'Student' ? existing.role : u.role,
            );
    }
    if (currentUser != null && currentUser!.email.isNotEmpty) {
      byEmail.putIfAbsent(currentUser!.email.toLowerCase(), () => currentUser!);
    }

    final studentByUserId = {
      for (final s in students)
        if (s.userId != null && s.userId!.isNotEmpty) s.userId!: s,
    };
    final studentByEmail = {for (final s in students) s.email.toLowerCase(): s};
    users = byEmail.values.map((u) {
      if ((u.department ?? '').isNotEmpty && (u.campus ?? '').isNotEmpty) {
        return u;
      }
      final s = studentByUserId[u.id] ?? studentByEmail[u.email.toLowerCase()];
      return s == null
          ? u
          : u.copyWith(department: s.department, campus: s.campus);
    }).toList();
  }

  /// Archives finished academic years.
  ///
  /// A year is recorded as finished either here, once its end date passes,
  /// or by the Admin moving the settings on to the next year. Copying its
  /// records into the archive needs every application, task and calendar,
  /// which only the Head can read, so that part always happens in the
  /// Head's session — once per year, and no sooner than [archiveDueAt], so
  /// the Heads can preview it first.
  Future<void> _archiveFinishedAcademicYears(
    Map<String, dynamic>? settings,
  ) async {
    if (role != 'Head') return;
    try {
      _firestoreService ??= FirestoreService();
      // The end date is the year's last day, so it's over only once the
      // day after it begins.
      final end = academicYearEnd;
      final dayAfterEnd = DateTime(end.year, end.month, end.day + 1);
      final yearEnded = !DateTime.now().isBefore(dayAfterEnd);
      if (settings != null && yearEnded) {
        final year = academicYear;
        final listed = await _firestoreService!.archiveAcademicYearSettings(
          year,
          settings,
          archiveAttendance: autoArchiveAttendanceLogs,
          headcountByCampus: studentsPerCampus,
        );
        if (listed) {
          final due = DateTime.now().add(archivePreviewWindow);
          await _notifyHeadsAboutArchive(
            year,
            title: 'Academic Year Ended',
            message:
                'AY $year ended on ${monthDay(end)}. Its records will be '
                'archived after ${monthDayTime(due)}. Before then, preview '
                'what will be saved and finish anything still open.',
          );
        }
      }
      final archives = await _firestoreService!.getAcademicYearArchives();
      for (final archive in archives) {
        final due = archiveDueAt(archive);
        if (due == null) continue;
        final year = archive['id'].toString();
        // A year's records stay live while it's back in effect after an
        // undo, and until the Heads have had their time to preview them —
        // which also outlasts the Admin's chance to undo moving on from it.
        if (year == academicYear && !yearEnded) continue;
        if (due.isAfter(DateTime.now())) continue;
        await _firestoreService!.archiveReportsForAcademicYear(year);
        await _firestoreService!.archiveApplicationsForAcademicYear(year);
        await _firestoreService!.archiveTasksForAcademicYear(year);
        await _firestoreService!.archiveAnnouncementsForAcademicYear(year);
        await _firestoreService!.archiveCalendarEventsForAcademicYear(year);
        await _firestoreService!.archiveEvaluationsForAcademicYear(year);
        await _firestoreService!.archiveScreeningRecordsForAcademicYear(year);
        if (archive['archiveAttendance'] == true) {
          await _firestoreService!.archiveAttendanceForAcademicYear(year);
        }
        await _firestoreService!.markAcademicYearDataArchived(year);
        await _notifyHeadsAboutArchive(
          year,
          title: 'Academic Year Archived',
          message:
              'AY $year\'s records have been archived. Open this to see '
              'what was saved.',
        );
      }
      academicYearArchives = await _firestoreService!.getAcademicYearArchives();
    } catch (error) {
      // Firebase availability errors should not prevent the app from
      // loading; an unfinished year is picked up again next time.
      debugPrint('Failed to archive academic years: $error');
    }
    _scheduleArchiveCheck();
  }

  /// Moves records stamped with a year the Admin moved to and then undid
  /// (see [undoTermChange]) back to the year in effect. Only the Head can
  /// update them all, so this runs in the Head's session.
  Future<void> _restampUndoneAcademicYear() async {
    final undone = _undoneAcademicYear;
    if (role != 'Head' || undone == null || undone == academicYear) return;
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.restampAcademicYear(undone, academicYear);
    } catch (error) {
      // Picked up again next time.
      debugPrint('Failed to move records back from AY $undone: $error');
    }
  }

  // ─── Academic year archive: notices and preview ────

  /// How long a finished year waits on the archive list before the Head's
  /// session copies its records in, so the Heads can preview what will be
  /// saved and finish what's still open. As long as [termChangeUndoWindow],
  /// so a year the Admin moved on from is copied once that can't be undone.
  static const archivePreviewWindow = Duration(hours: 24);

  /// How many days before the year's end date the Heads hear it's coming.
  static const archiveNoticeDays = 7;

  /// What an academic year's archive holds, as (collection in the archive,
  /// label), in the order the archive dialog lists them.
  static const archiveRecordKinds = [
    (key: 'reports', label: 'Reports'),
    (key: 'applications', label: 'Applications'),
    (key: 'screening_records', label: 'Screening results'),
    (key: 'tasks', label: 'Tasks'),
    (key: 'evaluations', label: 'Evaluations'),
    (key: 'announcements', label: 'Announcements'),
    (key: 'calendar_events', label: 'Calendar events'),
    (key: 'attendance', label: 'Attendance logs'),
  ];

  /// The once-only archive notices this session has sent, so each goes out
  /// once however often the settings change.
  final _archiveNoticesSent = <String>{};

  /// A date saved in an archive entry, in local time: a Firestore timestamp,
  /// or an ISO string for the settings' own dates.
  static DateTime? dateOf(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime date => date.toLocal(),
    String text => DateTime.tryParse(text),
    _ => null,
  };

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Jul 31".
  static String monthDay(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.day}';

  /// "3:00 PM".
  static String clockTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Oct 5, 3:00 PM", rounded up to the minute so a time something is due
  /// is never early.
  static String monthDayTime(DateTime date) {
    final at = date.second == 0 && date.millisecond == 0
        ? date
        : DateTime(date.year, date.month, date.day, date.hour, date.minute + 1);
    return '${monthDay(at)}, ${clockTime(at)}';
  }

  /// "today", "tomorrow" or "in 5 days".
  static String daysAwayLabel(int days) => switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $days days',
  };

  /// [year]'s entry on the archive list, if it's on it.
  Map<String, dynamic>? academicYearArchive(String year) {
    for (final archive in academicYearArchives) {
      if ((archive['academicYear'] ?? archive['id'])?.toString() == year) {
        return archive;
      }
    }
    return null;
  }

  /// When [archive]'s records are due to be copied in:
  /// [archivePreviewWindow] after the year went on the archive list, and
  /// not before the Admin can no longer undo moving on from it. Null once
  /// they have been.
  DateTime? archiveDueAt(Map<String, dynamic> archive) {
    if (archive['dataArchived'] != false) return null;
    var due =
        dateOf(archive['archivedAt'])?.add(archivePreviewWindow) ??
        DateTime.now();
    final year = (archive['academicYear'] ?? archive['id'])?.toString();
    final undoDeadline = termChangeUndoDeadline;
    if (undoDeadline != null &&
        undoDeadline.isAfter(due) &&
        year == _previousAcademicTerm?['academicYear']?.toString()) {
      due = undoDeadline;
    }
    return due;
  }

  /// The year waiting for the Head's session to copy its records into the
  /// archive, and when that's due — or null when none is.
  ({String year, DateTime dueAt})? get pendingArchive {
    for (final archive in academicYearArchives) {
      final due = archiveDueAt(archive);
      final year = (archive['academicYear'] ?? archive['id'])?.toString();
      if (due == null || year == null) continue;
      // Back in effect after an undo: it waits for its end date again.
      if (year == academicYear && daysUntilAcademicYearEnds >= 0) continue;
      return (year: year, dueAt: due);
    }
    return null;
  }

  /// Whether the year in effect ends within [archiveNoticeDays], or has
  /// ended, without being on the archive list yet.
  bool get academicYearEndingSoon =>
      daysUntilAcademicYearEnds <= archiveNoticeDays &&
      academicYearArchive(academicYear) == null;

  /// Whether archiving [year] takes its attendance logs too: the
  /// "Auto-archive Logs" setting it went on the list with, or for a year
  /// not on it yet, the setting now.
  bool archivesAttendance(String year) {
    final archive = academicYearArchive(year);
    return archive == null
        ? autoArchiveAttendanceLogs
        : archive['archiveAttendance'] == true;
  }

  /// What's still unfinished among [year]'s records, which archiving
  /// copies as they stand: applications the Head hasn't decided, student
  /// assistant requests waiting for the Head's approval, and reports and
  /// completed tasks waiting for a supervisor.
  ({int applications, int requests, int reports, int tasks}) archiveOpenItems(
    String year,
  ) => (
    applications: applications
        .where((a) => a.academicYear == year && a.isUndecided)
        .length,
    requests: announcements
        .where((a) => a.academicYear == year && a.isPending)
        .length,
    reports: reports
        .where((r) => r.academicYear == year && r.status == 'Pending')
        .length,
    tasks: tasks
        .where(
          (t) => t.academicYear == year && !t.isArchived && t.awaitingApproval,
        )
        .length,
  );

  /// How many of each kind of record [year]'s archive holds — or, before
  /// it's been archived, would get — keyed as in [archiveRecordKinds]. A
  /// year not archived yet takes the Head's access to count.
  Future<Map<String, int>> countArchiveRecords(String year) async {
    _firestoreService ??= FirestoreService();
    final archive = academicYearArchive(year);
    if (archive != null && archive['dataArchived'] != false) {
      return _firestoreService!.countArchivedRecords(year);
    }
    final counts = {...await _firestoreService!.countRecordsToArchive(year)};
    // The logs archiveAttendanceForAcademicYear would take, out of the full
    // list a Head's session keeps.
    counts['attendance'] = archivesAttendance(year)
        ? attendance
              .where(
                (record) =>
                    !record.isArchived &&
                    (record.academicYear == null ||
                        record.academicYear == year),
              )
              .length
        : 0;
    return counts;
  }

  /// Sends every Head an 'academic_year' notification about [year], which
  /// opens its archive preview or summary. With [onceId] it's one that's
  /// only ever sent once: each Head's copy is saved as `<onceId>_<head id>`,
  /// and the rules refuse saving a notification over another.
  Future<void> _notifyHeadsAboutArchive(
    String year, {
    required String title,
    required String message,
    String? onceId,
  }) async {
    for (final headId in await _headIds()) {
      final id = onceId == null ? null : '${onceId}_$headId';
      if (id != null &&
          (!_archiveNoticesSent.add(id) ||
              notifications.any((n) => n.id == id))) {
        continue;
      }
      _addNotification(
        AppNotification(
          id: id ?? '',
          userId: headId,
          title: title,
          message: message,
          type: 'academic_year',
          createdAt: _formattedToday(),
          academicYear: year,
        ),
        id: id,
      );
    }
    notifyListeners();
  }

  /// Tells the Heads, once a year, that the year in effect ends within
  /// [archiveNoticeDays] and will be archived after that. Whichever Admin
  /// or Head session opens SAIS first that week sends it, so it can reach
  /// a Head's phone before they open SAIS themselves.
  Future<void> _noticeAcademicYearEnding() async {
    if (role != 'Admin' && role != 'Head') return;
    final days = daysUntilAcademicYearEnds;
    if (days < 0 || !academicYearEndingSoon) return;
    final year = academicYear;
    await _notifyHeadsAboutArchive(
      year,
      title: 'Academic Year Ending Soon',
      message:
          'AY $year ends ${daysAwayLabel(days)} '
          '(${monthDay(academicYearEnd)}), and its records will be archived '
          'after that. Preview what will be saved and finish anything still '
          'open.',
      onceId: 'ay_ending_$year',
    );
  }

  /// Sets a timer for the next archiving step that a Head's session left
  /// open would otherwise leave for a reload: listing the year in effect
  /// the day after its end date, or copying in a listed year's records once
  /// they're due. Only within [archiveNoticeDays]; anything later is picked
  /// up when SAIS next loads.
  void _scheduleArchiveCheck() {
    _archiveTimer?.cancel();
    _archiveTimer = null;
    if (role != 'Head' || currentUser == null) return;
    final now = DateTime.now();
    final end = academicYearEnd;
    DateTime? next;
    for (final at in [
      if (academicYearArchive(academicYear) == null)
        DateTime(end.year, end.month, end.day + 1),
      for (final archive in academicYearArchives) ?archiveDueAt(archive),
    ]) {
      if (at.isAfter(now) && (next == null || at.isBefore(next))) next = at;
    }
    if (next == null) return;
    final wait = next.difference(now);
    if (wait > const Duration(days: archiveNoticeDays)) return;
    // A moment past it, so the step finds it due.
    _archiveTimer = Timer(wait + const Duration(seconds: 1), () async {
      try {
        _firestoreService ??= FirestoreService();
        await _archiveFinishedAcademicYears(
          await _firestoreService!.getAcademicYearSettings(),
        );
      } catch (error) {
        debugPrint('Failed to check for academic years to archive: $error');
      }
      notifyListeners();
    });
  }

  Future<void> _syncApprovedApplicationSkills() async {
    final approvedSkills = applications
        .where(
          (application) =>
              application.status == 'Approved' ||
              application.status == 'Accepted',
        )
        .expand((application) => application.skills)
        .map((skill) => skill.trim())
        .where((skill) => skill.isNotEmpty)
        .toSet();

    for (final skill in approvedSkills) {
      if (skills.any(
        (existing) => existing.toLowerCase() == skill.toLowerCase(),
      )) {
        continue;
      }
      try {
        await _firestoreService!.setSkill(skill);
        skills = [...skills, skill]..sort();
      } catch (error) {
        debugPrint('Failed to sync approved application skill: $error');
      }
    }
  }

  // ─── Announcements ─────────────────────────────────
  Future<bool> postAnnouncement(Announcement a) async {
    // Persist announcement to Firestore first. Only update local state on success
    // so announcements are always sourced from Firebase.
    _firestoreService ??= FirestoreService();
    try {
      final docRef = await _firestoreService!.addAnnouncement(
        id: a.id,
        title: a.title,
        body: a.body,
        extra: {
          'postedBy': a.postedBy,
          'postedByRole': a.postedByRole,
          'postedAt': a.postedAt,
          'deadline': a.deadline,
          'slots': a.slots,
          'requirements': a.requirements,
          'isOpen': a.isOpen,
          'acceptsApplications': a.acceptsApplications,
          'postedById': a.postedById,
          'officeId': a.officeId,
          'officeName': a.officeName,
          'approvalStatus': a.approvalStatus,
          'rejectionReason': a.rejectionReason,
          'academicYear': a.academicYear ?? academicYear,
          'attachmentName': a.attachmentName,
          'attachmentUrl': a.attachmentUrl,
          'attachmentPath': a.attachmentPath,
          'attachmentSize': a.attachmentSize,
        },
      );

      final created = Announcement(
        id: docRef.id,
        title: a.title,
        body: a.body,
        postedBy: a.postedBy,
        postedByRole: a.postedByRole,
        postedAt: a.postedAt,
        deadline: a.deadline,
        slots: a.slots,
        requirements: a.requirements,
        isOpen: a.isOpen,
        acceptsApplications: a.acceptsApplications,
        postedById: a.postedById,
        officeId: a.officeId,
        officeName: a.officeName,
        approvalStatus: a.approvalStatus,
        rejectionReason: a.rejectionReason,
        academicYear: a.academicYear ?? academicYear,
        attachmentName: a.attachmentName,
        attachmentUrl: a.attachmentUrl,
        attachmentPath: a.attachmentPath,
        attachmentSize: a.attachmentSize,
      );

      // Update local state and notify users now that Firestore write succeeded.
      announcements = _withAdded(announcements, created, (a) => a.id);
      final studentUsers = users.where((u) => u.role == 'Student');
      for (final u in studentUsers) {
        _addNotification(
          AppNotification(
            id: 'n_${DateTime.now().millisecondsSinceEpoch}_${u.id}',
            userId: u.id,
            title: 'New Hiring Announcement',
            message: created.title,
            type: 'announcement',
            createdAt: _formattedToday(),
          ),
        );
      }
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('Firestore announcement write failed: $error');
      return false;
    }
  }

  Future<bool> submitAnnouncementForApproval(Announcement a) async {
    // Persist pending announcement to Firestore first, then update local state
    // so submitted announcements survive refresh.
    final pendingExtra = {
      'approvalStatus': 'Pending',
      'isOpen': false,
      'postedBy': a.postedBy,
      'postedByRole': a.postedByRole,
      'postedById': a.postedById,
      'postedAt': a.postedAt,
      'deadline': a.deadline,
      'slots': a.slots,
      'requirements': a.requirements,
      'skills': a.skills,
      'acceptsApplications': a.acceptsApplications,
      'officeId': a.officeId,
      'officeName': a.officeName,
      'academicYear': a.academicYear ?? academicYear,
      'attachmentName': a.attachmentName,
      'attachmentUrl': a.attachmentUrl,
      'attachmentPath': a.attachmentPath,
      'attachmentSize': a.attachmentSize,
    }..removeWhere((k, v) => v == null);

    _firestoreService ??= FirestoreService();
    try {
      final docRef = await _firestoreService!.addAnnouncement(
        title: a.title,
        body: a.body,
        extra: pendingExtra,
      );

      final pending = Announcement(
        id: docRef.id,
        title: a.title,
        body: a.body,
        postedBy: a.postedBy,
        postedByRole: a.postedByRole,
        postedAt: a.postedAt,
        deadline: a.deadline,
        slots: a.slots,
        requirements: a.requirements,
        skills: a.skills,
        isOpen: false,
        acceptsApplications: a.acceptsApplications,
        postedById: a.postedById,
        officeId: a.officeId,
        officeName: a.officeName,
        approvalStatus: 'Pending',
        academicYear: a.academicYear ?? academicYear,
        attachmentName: a.attachmentName,
        attachmentUrl: a.attachmentUrl,
        attachmentPath: a.attachmentPath,
        attachmentSize: a.attachmentSize,
      );

      announcements = _withAdded(announcements, pending, (a) => a.id);

      // Notify admins locally and persist notifications to Firestore so
      // admins signed in on other devices will receive them.
      List<User> adminUsers = users.where((u) => u.role == 'Head').toList();
      if (adminUsers.isEmpty) {
        try {
          final fsUsers = await _firestoreService!.getAllUserProfiles();
          adminUsers = fsUsers.where((u) => u.role == 'Head').toList();
        } catch (_) {
          adminUsers = [];
        }
      }

      if (currentUser != null &&
          currentUser!.role == 'Head' &&
          !adminUsers.any((u) => u.id == currentUser!.id)) {
        adminUsers.add(currentUser!);
      }

      for (final u in adminUsers) {
        final notif = AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${u.id}',
          userId: u.id,
          title: 'Student Assistant Request Awaiting Approval',
          message: a.officeName != null
              ? '${a.postedBy} requested a student assistant for ${a.officeName}: "${a.title}".'
              : '${a.postedBy} submitted "${a.title}" for approval.',
          type: 'announcement',
          createdAt: _formattedToday(),
        );
        // _addNotification already persists this to Firestore, so no need
        // to write it a second time here (that was causing duplicates).
        _addNotification(notif);
      }
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('Failed to submit announcement for approval: $error');
      return false;
    }
  }

  /// What approving [request] does to the office it names, or null for
  /// anything but a pending supervisor's request that names one.
  ///
  /// The office is the one the supervisor picked, else one of the same
  /// name. With none, approving creates it, coded [newOfficeCode] (or
  /// [Office.suggestCode]), with the supervisor over it, the requested
  /// skills, and room for the slots asked for. An office that exists gets
  /// the requested skills it lacked, its capacity raised if the slots
  /// wouldn't fit, the supervisor added if they weren't over it, and is
  /// reactivated if it was inactive.
  OfficeRequestPlan? officePlanFor(
    Announcement request, {
    String? newOfficeCode,
  }) {
    final name = request.officeName?.trim() ?? '';
    if (!request.isPending ||
        request.postedByRole != 'Supervisor' ||
        name.isEmpty) {
      return null;
    }
    final wanted = name.toLowerCase();
    bool named(Office office) => office.name.trim().toLowerCase() == wanted;
    final current =
        offices.where((o) => o.id == request.officeId).firstOrNull ??
        offices.where((o) => o.isActive && named(o)).firstOrNull ??
        offices.where(named).firstOrNull;
    final supervisorId = request.postedById ?? '';
    final supervisorName = request.postedBy;
    final slots = int.tryParse(request.slots?.trim() ?? '') ?? 0;

    if (current == null) {
      final code = newOfficeCode?.trim() ?? '';
      return OfficeRequestPlan(
        current: null,
        office: Office(
          id: 'office_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          code: code.isEmpty ? Office.suggestCode(name) : code,
          headIds: [supervisorId],
          headNames: [supervisorName],
          capacity: slots,
          requiredSkills: request.skills,
        ),
        addedSkills: request.skills,
        addsSupervisor: true,
      );
    }

    final known = {
      for (final skill in current.requiredSkills) skill.trim().toLowerCase(),
    };
    final addedSkills = [
      for (final skill in request.skills)
        if (known.add(skill.trim().toLowerCase())) skill,
    ];
    final addsSupervisor = !current.hasHead(supervisorId, supervisorName);
    // The id and name lists run in parallel, so line them up first.
    final heads = current.headIds.length > current.headNames.length
        ? current.headIds.length
        : current.headNames.length;
    List<String> padded(List<String> list) => [
      ...list,
      for (var i = list.length; i < heads; i++) '',
    ];
    final needed = current.assistantIds.length + slots;
    return OfficeRequestPlan(
      current: current,
      office: current.copyWith(
        headIds: addsSupervisor
            ? [...padded(current.headIds), supervisorId]
            : null,
        headNames: addsSupervisor
            ? [...padded(current.headNames), supervisorName]
            : null,
        // No capacity means no limit, which stays.
        capacity: current.capacity > 0 && needed > current.capacity
            ? needed
            : null,
        isActive: true,
        requiredSkills: [...current.requiredSkills, ...addedSkills],
      ),
      addedSkills: addedSkills,
      addsSupervisor: addsSupervisor,
    );
  }

  /// Approves a supervisor's pending request, or re-opens a closed
  /// announcement. The change is saved to Firestore before anything else
  /// happens, so the caller can show progress while it saves and report a
  /// failure instead of the approval silently not sticking. Returns whether
  /// it succeeded.
  ///
  /// A request for an office also creates or updates that office, as
  /// [officePlanFor] describes, in the same save; [newOfficeCode] is the
  /// code a created office gets.
  Future<bool> approveAnnouncement(String id, {String? newOfficeCode}) async {
    final original = announcements.where((a) => a.id == id).firstOrNull;
    if (original == null) return false;
    final plan = officePlanFor(original, newOfficeCode: newOfficeCode);
    final changes = <String, dynamic>{
      'approvalStatus': 'Approved',
      'isOpen': true,
      if (plan != null) 'officeId': plan.office.id,
      if (plan != null) 'officeName': plan.office.name,
    };

    if (id.isNotEmpty) {
      try {
        _firestoreService ??= FirestoreService();
        if (plan != null && plan.changesOffice) {
          await _firestoreService!.approveAnnouncementWithOffice(
            id,
            changes,
            plan.office,
          );
        } else {
          await _firestoreService!.updateAnnouncement(id, changes);
        }
      } catch (error) {
        debugPrint('Failed to approve announcement: $error');
        return false;
      }
    }

    if (plan != null && plan.changesOffice) {
      final index = offices.indexWhere((o) => o.id == plan.office.id);
      offices = index < 0
          ? [...offices, plan.office]
          : ([...offices]..[index] = plan.office);
    }
    final approved = original.copyWith(
      approvalStatus: 'Approved',
      isOpen: true,
      officeId: plan?.office.id,
      officeName: plan?.office.name,
    );
    announcements = announcements
        .map((a) => a.id == id ? approved : a)
        .toList();

    // A supervisor's request ends with the Head's approval: students never
    // see it, they apply to be a Student Assistant. Only the Head's own
    // announcements, re-opened here, are news to them.
    if (!approved.isSupervisorRequest) {
      final studentUsers = users.where((u) => u.role == 'Student');
      for (final u in studentUsers) {
        _addNotification(
          AppNotification(
            id: 'n_${DateTime.now().millisecondsSinceEpoch}_${u.id}',
            userId: u.id,
            title: 'New Hiring Announcement',
            message: approved.title,
            type: 'announcement',
            createdAt: _formattedToday(),
          ),
        );
      }
    }

    final postedById = approved.postedById;
    if (postedById != null && postedById.isNotEmpty) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_approved',
          userId: postedById,
          title: 'Announcement Approved',
          message: approved.isSupervisorRequest
              ? 'Your request "${approved.title}" was approved. The Head '
                    'will match Student Assistants to it by their skills.'
                    '${plan != null && plan.createsOffice ? ' The office "${plan.office.name}" was created, with you as its supervisor.' : ''}'
              : 'Your announcement "${approved.title}" was approved and is now live.',
          type: 'announcement',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();
    return true;
  }

  /// Rejects a supervisor's pending request. Like [approveAnnouncement], the
  /// rejection is saved before the supervisor is told, so a failed save
  /// doesn't leave them notified of a rejection that never happened.
  /// Returns whether it succeeded.
  Future<bool> rejectAnnouncement(String id, {String? reason}) async {
    final original = announcements.where((a) => a.id == id).firstOrNull;
    if (original == null) return false;

    if (id.isNotEmpty) {
      try {
        _firestoreService ??= FirestoreService();
        await _firestoreService!.updateAnnouncement(id, {
          'approvalStatus': 'Rejected',
          'isOpen': false,
          'rejectionReason': reason,
        });
      } catch (error) {
        debugPrint('Failed to reject announcement: $error');
        return false;
      }
    }

    final rejected = original.copyWith(
      approvalStatus: 'Rejected',
      isOpen: false,
      rejectionReason: reason,
    );
    announcements = announcements
        .map((a) => a.id == id ? rejected : a)
        .toList();

    final postedById = rejected.postedById;
    if (postedById != null && postedById.isNotEmpty) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_rejected',
          userId: postedById,
          title: 'Announcement Rejected',
          message:
              'Your announcement "${rejected.title}" was not approved.${reason != null && reason.isNotEmpty ? " Reason: $reason" : ""}',
          type: 'announcement',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();
    return true;
  }

  /// Stops an announcement taking applications. Saved first, like
  /// [approveAnnouncement]: shown as closed only once it really is, since
  /// students can keep applying to one that only looks closed. Returns
  /// whether it succeeded.
  Future<bool> closeAnnouncement(String id) async {
    if (id.isNotEmpty) {
      try {
        _firestoreService ??= FirestoreService();
        await _firestoreService!.updateAnnouncement(id, {'isOpen': false});
      } catch (error) {
        debugPrint('Failed to close announcement: $error');
        return false;
      }
    }
    announcements = announcements
        .map((a) => a.id == id ? a.copyWith(isOpen: false) : a)
        .toList();
    notifyListeners();
    return true;
  }

  /// Deletes an announcement, saved first like [closeAnnouncement].
  /// Returns whether it succeeded.
  Future<bool> deleteAnnouncement(String id) async {
    if (id.isNotEmpty) {
      try {
        _firestoreService ??= FirestoreService();
        await _firestoreService!.deleteAnnouncement(id);
      } catch (error) {
        debugPrint('Failed to delete announcement: $error');
        return false;
      }
    }
    announcements = announcements.where((a) => a.id != id).toList();
    notifyListeners();
    return true;
  }

  /// Only admin-approved announcements are visible to students.
  List<Announcement> get studentVisibleAnnouncements => announcements
      .where(
        (a) =>
            a.isVisibleToStudents &&
            (a.academicYear == null || a.academicYear == academicYear),
      )
      .toList();

  /// Announcements submitted by the current supervisor (any status).
  List<Announcement> get myAnnouncements =>
      announcements.where((a) => a.postedBy == currentUser?.name).toList();

  // ─── Students ────────────────────────────────────────
  /// Moves a student to [newDepartment], on their students record and on
  /// their linked account, saved together so the two never disagree.
  /// Returns an error message, or null once it's saved; a refused save is
  /// undone here.
  Future<String?> updateStudentDepartment(
    String studentId,
    String newDepartment,
  ) async {
    final saved = await _saveStudentRecord(
      studentId,
      (s) => s.copyWith(department: newDepartment),
      accountChange: (u) => u.copyWith(department: newDepartment),
    );
    return saved
        ? null
        : "Couldn't change the student's department. Please try again.";
  }

  // ─── Departments ───────────────────────────────────
  /// Saves an office's details (name, code, capacity, skills, active) and
  /// its supervisors. [basedOn] is the office [office] was made from (what a
  /// dialog opened on); with it, only the supervisors added or removed since
  /// are applied, to the supervisors stored now. The student assistants are
  /// never taken from [office]: they stay as stored, so a copy opened a while
  /// ago can't erase someone placed since. A new office is simply saved.
  Future<void> saveOffice(Office office, {Office? basedOn}) async {
    _firestoreService ??= FirestoreService();
    final known = offices.where((item) => item.id == office.id).firstOrNull;
    final base = basedOn ?? known;
    var saved = office;
    if (base == null) {
      await _firestoreService!.setOffice(office);
    } else {
      final removedHeads = [
        for (var i = 0; i < base.headIds.length; i++)
          if (!office.headIds.contains(base.headIds[i]))
            (
              id: base.headIds[i],
              name: i < base.headNames.length ? base.headNames[i] : '',
            ),
      ];
      final addedHeads = [
        for (var i = 0; i < office.headIds.length; i++)
          if (!base.headIds.contains(office.headIds[i]))
            (
              id: office.headIds[i],
              name: i < office.headNames.length ? office.headNames[i] : '',
            ),
      ];
      final result = await _firestoreService!.updateOffices({office.id}, (
        stored,
      ) {
        final current = stored[office.id];
        if (current == null) return {office.id: office};
        var merged = current;
        for (final gone in removedHeads) {
          merged = merged.withoutHead(gone.id, gone.name);
        }
        for (final head in addedHeads) {
          if (merged.hasHead(head.id, head.name)) continue;
          merged = merged.copyWith(
            headIds: [...merged.headIds, head.id],
            headNames: [...merged.headNames, head.name],
          );
        }
        return {
          office.id: office.copyWith(
            assistantIds: current.assistantIds,
            assistantNames: current.assistantNames,
            headIds: merged.headIds,
            headNames: merged.headNames,
          ),
        };
      });
      saved = result?[office.id] ?? office;
    }
    final index = offices.indexWhere((item) => item.id == office.id);
    offices = index < 0 ? [...offices, saved] : [...offices]
      ..[index] = saved;
    notifyListeners();
    await _syncOfficeAssignments();
  }

  /// Whether two copies of an office differ in who is in it (ids or names,
  /// assistants or supervisors: an older entry may be a name alone).
  static bool _peopleDiffer(Office a, Office b) =>
      !_sameList(a.assistantIds, b.assistantIds) ||
      !_sameList(a.assistantNames, b.assistantNames) ||
      !_sameList(a.headIds, b.headIds) ||
      !_sameList(a.headNames, b.headNames);

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Applies the result of a transaction over offices to the list shown, and
  /// brings `officeAssignments` in step.
  Future<void> _showSavedOffices(Map<String, Office> saved) async {
    offices = [for (final o in offices) saved[o.id] ?? o];
    for (final o in saved.values) {
      if (!offices.any((item) => item.id == o.id)) offices = [...offices, o];
    }
    notifyListeners();
    await _syncOfficeAssignments();
  }

  Future<void> removeOffice(String id) async {
    _firestoreService ??= FirestoreService();
    await _firestoreService!.deleteOffice(id);
    offices = offices.where((office) => office.id != id).toList();
    notifyListeners();
    await _syncOfficeAssignments();
  }

  /// Mirrors which office each student assistant is in onto
  /// `officeAssignments/{uid}`.
  ///
  /// The Firestore rules read it to find a record's office, so a Supervisor
  /// can only change attendance, reports, tasks and evaluations for students
  /// in an office they head. Only the Head may write it, so this runs in the
  /// Head's session: at load and after every office change. Active offices
  /// win if a student is somehow listed in more than one.
  Future<void> _syncOfficeAssignments() async {
    // No offices usually means they failed to load, and syncing then would
    // wipe every assignment. Leaving stale ones is safe: the rules also
    // check the office itself, so one pointing at a deleted office grants
    // nothing.
    if (role != 'Head' || offices.isEmpty) return;
    final desired = <String, String>{};
    for (final office in [
      ...offices.where((office) => office.isActive),
      ...offices.where((office) => !office.isActive),
    ]) {
      for (final id in office.assistantIds) {
        if (id.isNotEmpty) desired.putIfAbsent(id, () => office.id);
      }
    }
    try {
      _firestoreService ??= FirestoreService();
      final current = await _firestoreService!.getOfficeAssignments();
      final changes = <String, String?>{
        for (final entry in desired.entries)
          if (current[entry.key] != entry.value) entry.key: entry.value,
        for (final id in current.keys)
          if (!desired.containsKey(id)) id: null,
      };
      if (changes.isNotEmpty) {
        await _firestoreService!.writeOfficeAssignments(changes);
      }
    } catch (error) {
      debugPrint('Failed to sync office assignments: $error');
    }
  }

  /// Moves schedules saved under people's names onto their accounts, once —
  /// see [FirestoreService.moveSchedulesToAccounts]. Head-only, like the
  /// office sync. [accounts] must be the full list just read from
  /// Firestore: matching against a partial list would leave schedules
  /// behind and still mark the move done.
  Future<void> _moveSchedulesToAccounts(List<User> accounts) async {
    if (role != 'Head' || accounts.isEmpty) return;
    final byName = <String, String>{};
    final shared = <String>{};
    for (final account in accounts) {
      final key = account.name.trim().toLowerCase();
      if (key.isEmpty || account.id.isEmpty) continue;
      if (byName.containsKey(key) && byName[key] != account.id) {
        shared.add(key);
      }
      byName[key] = account.id;
    }
    byName.removeWhere((key, _) => shared.contains(key));
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.moveSchedulesToAccounts(byName);
    } catch (error) {
      debugPrint('Failed to move schedules to accounts: $error');
    }
  }

  /// Makes [assistants] the roster of [officeId], and takes the ones just
  /// added out of any other office (one office each). What changes is the
  /// difference from the roster shown: the people added and the people
  /// removed are applied to the roster as stored now, in one transaction, so
  /// two Heads placing different students don't erase each other, and a move
  /// lands on both offices or neither. False when the office is full or gone,
  /// or the save failed.
  Future<bool> assignStudentAssistantsToOffice(
    String officeId,
    List<User> assistants,
  ) async {
    final office = offices.where((item) => item.id == officeId).firstOrNull;
    if (office == null) return false;
    final assignedIds = assistants.map((assistant) => assistant.id).toSet();
    if (office.capacity > 0 && assignedIds.length > office.capacity) {
      return false;
    }
    final added = [
      for (final a in assistants)
        if (!office.hasAssistant(a.id, a.name)) a,
    ];
    final removed = [
      for (var i = 0; i < office.assistantIds.length; i++)
        if (!assignedIds.contains(office.assistantIds[i]))
          (
            id: office.assistantIds[i],
            name: i < office.assistantNames.length
                ? office.assistantNames[i]
                : '',
          ),
    ];
    // The offices the added people are in now, to take them out of.
    final touched = {
      officeId,
      for (final other in offices)
        if (other.id != officeId &&
            added.any((a) => other.hasAssistant(a.id, a.name)))
          other.id,
    };

    _firestoreService ??= FirestoreService();
    final Map<String, Office>? saved;
    try {
      saved = await _firestoreService!.updateOffices(touched, (stored) {
        var target = stored[officeId];
        if (target == null) return null;
        for (final gone in removed) {
          target = target!.withoutAssistant(gone.id, gone.name);
        }
        for (final a in added) {
          if (target!.hasAssistant(a.id, a.name)) continue;
          target = target.copyWith(
            assistantIds: [...target.assistantIds, a.id],
            assistantNames: [...target.assistantNames, a.name],
          );
        }
        if (target!.capacity > 0 &&
            target.assistantIds.length > target.capacity) {
          return null;
        }
        final changed = {officeId: target};
        for (final entry in stored.entries) {
          if (entry.key == officeId) continue;
          var other = entry.value;
          for (final a in added) {
            if (other.hasAssistant(a.id, a.name)) {
              other = other.withoutAssistant(a.id, a.name);
            }
          }
          if (_peopleDiffer(other, entry.value)) changed[entry.key] = other;
        }
        return changed;
      }, people: [for (final a in added) a.id, for (final g in removed) g.id]);
    } catch (error) {
      debugPrint('Failed to save the office roster: $error');
      return false;
    }
    if (saved == null) return false;
    await _showSavedOffices(saved);

    final assignedOffice = offices.firstWhere((item) => item.id == officeId);
    // Only students new to the office hear about it: saving the roster to
    // add one student shouldn't tell everyone already there again.
    final previousIds = office.assistantIds.toSet();
    final removedAny = previousIds.any((id) => !assignedIds.contains(id));
    if (added.isEmpty && !removedAny) return true;
    final addedNames = added.map((assistant) => assistant.name).join(', ');

    // Each new student only hears about their own assignment, not the
    // whole roster.
    for (final assistant in added) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().microsecondsSinceEpoch}_office_${assistant.id}',
          userId: assistant.id,
          title: 'Office Assignment Updated',
          message: 'You have been assigned to ${assignedOffice.name}.',
          type: 'office',
          createdAt: _formattedToday(),
        ),
      );
    }
    // The office's supervisors hear who joined, since it's their office.
    _notifyOfficeUsers(
      assignedOffice.headIds,
      title: 'Office Assignment Updated',
      message: added.isEmpty
          ? 'Student assistant assignments were updated for ${assignedOffice.name}.'
          : '$addedNames ${added.length == 1 ? 'was' : 'were'} assigned to ${assignedOffice.name}.',
    );
    return true;
  }

  /// Makes [supervisors] the supervisors of [officeId]: the difference from
  /// the list shown is applied to the one stored now, in a transaction.
  /// False when the office is gone or the save failed.
  Future<bool> assignSupervisorsToOffice(
    String officeId,
    List<User> supervisors,
  ) async {
    final office = offices.where((item) => item.id == officeId).firstOrNull;
    if (office == null) return false;
    final keptIds = supervisors.map((s) => s.id).toSet();
    final added = [
      for (final s in supervisors)
        if (!office.hasHead(s.id, s.name)) s,
    ];
    final removed = [
      for (var i = 0; i < office.headIds.length; i++)
        if (!keptIds.contains(office.headIds[i]))
          (
            id: office.headIds[i],
            name: i < office.headNames.length ? office.headNames[i] : '',
          ),
    ];
    _firestoreService ??= FirestoreService();
    final Map<String, Office>? saved;
    try {
      saved = await _firestoreService!.updateOffices({officeId}, (stored) {
        var target = stored[officeId];
        if (target == null) return null;
        for (final gone in removed) {
          target = target!.withoutHead(gone.id, gone.name);
        }
        for (final s in added) {
          if (target!.hasHead(s.id, s.name)) continue;
          target = target.copyWith(
            headIds: [...target.headIds, s.id],
            headNames: [...target.headNames, s.name],
          );
        }
        return {officeId: target!};
      });
    } catch (error) {
      debugPrint('Failed to save the office supervisors: $error');
      return false;
    }
    if (saved == null) return false;
    await _showSavedOffices(saved);
    final updatedOffice = offices.firstWhere((item) => item.id == officeId);

    // As with students, only supervisors new to the office hear about it.
    final previousIds = office.headIds.toSet();
    final removedAny = previousIds.any(
      (id) => !supervisors.any((supervisor) => supervisor.id == id),
    );
    if (added.isEmpty && !removedAny) return true;

    // Each new supervisor only hears about their own assignment.
    for (final supervisor in added) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().microsecondsSinceEpoch}_office_${supervisor.id}',
          userId: supervisor.id,
          title: 'Office Assignment Updated',
          message: 'You have been assigned to supervise ${updatedOffice.name}.',
          type: 'office',
          createdAt: _formattedToday(),
        ),
      );
    }
    // Assigned students just hear that the office's supervisors changed.
    _notifyOfficeUsers(
      updatedOffice.assistantIds,
      title: 'Office Assignment Updated',
      message: added.isEmpty
          ? 'Supervisors were updated for ${updatedOffice.name}.'
          : '${added.map((supervisor) => supervisor.name).join(', ')} ${added.length == 1 ? 'was' : 'were'} assigned to supervise ${updatedOffice.name}.',
    );
    return true;
  }

  Future<bool> addDepartment(String name, {String code = ''}) async {
    final normalized = name.trim();
    if (normalized.isEmpty || departments.contains(normalized)) return false;
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setDepartment(normalized, code: code.trim());
      departments = [...departments, normalized];
      departmentCodes[normalized] = code.trim();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The category every task can fall back on. It stays on the list, so
  /// it can be neither renamed nor deleted.
  static const fallbackTaskCategory = 'General';

  /// The category on the list named [name], whatever its case or spacing:
  /// "fieldwork" finds "Fieldwork".
  String? findTaskCategory(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    return taskCategories.where((c) => c.trim().toLowerCase() == key).firstOrNull;
  }

  /// How many tasks (archived ones too) are filed under [category].
  int tasksInCategory(String category) =>
      tasks.where((t) => (t.category ?? '') == category).length;

  /// How many ongoing duties (stopped ones too) are filed under [category].
  int dutiesInCategory(String category) =>
      taskDuties.where((d) => d.category == category).length;

  /// Adds a task category and saves the list, so it's there for every
  /// Supervisor and after a reload. Returns whether it saved; a blank name
  /// or one already on the list (in any case) is refused.
  Future<bool> addTaskCategory(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty || findTaskCategory(normalized) != null) {
      return false;
    }
    final updated = [...taskCategories, normalized];
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTaskCategories(updated);
    } catch (error) {
      debugPrint('Failed to save task categories: $error');
      return false;
    }
    taskCategories = updated;
    notifyListeners();
    return true;
  }

  /// Renames the category [from] to [to], and the tasks filed under it with
  /// it, in one save. Returns null when it worked, or what to tell the
  /// Head.
  Future<String?> renameTaskCategory(String from, String to) async {
    final name = to.trim();
    if (name.isEmpty) return 'Type a name for the category.';
    if (from == fallbackTaskCategory) {
      return '"$fallbackTaskCategory" is the default category, so it keeps '
          'its name.';
    }
    if (name == from) return null;
    final clash = findTaskCategory(name);
    if (clash != null && clash.toLowerCase() != from.toLowerCase()) {
      return '"$clash" is already a task category.';
    }
    final updated = [for (final c in taskCategories) c == from ? name : c];
    final taskIds = [
      for (final t in tasks)
        if ((t.category ?? '') == from) t.id,
    ];
    // Ongoing duties carry the category their daily logs are filed under.
    final dutyIds = [
      for (final d in taskDuties)
        if (d.category == from) d.id,
    ];
    if (taskIds.length + dutyIds.length > FirestoreService.maxRenamedTasks) {
      return '"$from" is used by too many tasks to rename in one go.';
    }
    final templates = [
      for (final t in taskTemplates)
        t.category == from ? t.copyWith(category: name) : t,
    ];
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.renameTaskCategory(
        updated,
        from: from,
        to: name,
        taskIds: taskIds,
        dutyIds: dutyIds,
      );
    } catch (error) {
      debugPrint('Failed to rename task category: $error');
      return "Couldn't rename it. Check your connection and try again.";
    }
    taskCategories = updated;
    taskTemplates = templates;
    taskDuties = [
      for (final d in taskDuties)
        d.category == from ? d.copyWith(category: name) : d,
    ];
    tasks = [
      for (final t in tasks)
        (t.category ?? '') == from ? t.copyWith(category: name) : t,
    ];
    notifyListeners();
    return null;
  }

  /// Removes a task category nothing is filed under. Returns null when it
  /// worked, or what to tell the Head.
  Future<String?> deleteTaskCategory(String name) async {
    if (name == fallbackTaskCategory) {
      return '"$fallbackTaskCategory" is the default category, so it stays.';
    }
    final used = tasksInCategory(name);
    if (used > 0) {
      final noun = used == 1 ? 'task' : 'tasks';
      return '"$name" is used by $used $noun, so it '
          "can't be deleted. Rename it instead.";
    }
    final templates = templatesIn(name).length;
    if (templates > 0) {
      final noun = templates == 1 ? 'template' : 'templates';
      return '"$name" still has $templates $noun. Delete them first.';
    }
    final duties = dutiesInCategory(name);
    if (duties > 0) {
      final noun = duties == 1 ? 'ongoing duty' : 'ongoing duties';
      return '"$name" is used by $duties $noun, so it can\'t be deleted. '
          'Rename it instead.';
    }
    final updated = [for (final c in taskCategories) if (c != name) c];
    if (updated.isEmpty) return 'Keep at least one category.';
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTaskCategories(updated);
    } catch (error) {
      debugPrint('Failed to delete task category: $error');
      return "Couldn't delete it. Check your connection and try again.";
    }
    taskCategories = updated;
    notifyListeners();
    return null;
  }

  // ── Ongoing duties ───────────────────────────────────

  /// Today's date in Philippine time ("Oct 14, 2026"), the way tasks and
  /// attendance records name a day and the same day the Firestore rules
  /// and the attendance server go by.
  String philippineToday([DateTime? now]) {
    final day = _philippineDay(now);
    return '${_monthNames[day.month - 1]} ${day.day}, ${day.year}';
  }

  DateTime _philippineDay([DateTime? now]) {
    final clock = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    return DateTime(clock.year, clock.month, clock.day);
  }

  /// The ongoing duties this user may see: all for the Head, those of their
  /// office's students for a Supervisor, their own for anyone else.
  List<TaskDuty> get filteredDuties {
    if (role == 'Head') return taskDuties;
    if (role == 'Supervisor') {
      final assistantIds = _studentIdentityIdsForSupervisor();
      return taskDuties.where((d) => assistantIds.contains(d.assignedTo)).toList();
    }
    return taskDuties.where((d) => d.assignedTo == currentUser?.id).toList();
  }

  /// The duties a Student Assistant can log: active, and set up this
  /// academic year (one never carries into the next by itself).
  List<TaskDuty> get dutiesToLog => [
    for (final d in filteredDuties)
      if (d.active && d.academicYear == academicYear) d,
  ];

  /// The signed-in student's attendance record from today (Philippine
  /// time), which is what lets them log a duty. Timing out isn't needed:
  /// a missed time-out is dealt with on the attendance side.
  AttendanceRecord? attendanceForToday([DateTime? now]) {
    final me = currentUser?.id;
    if (me == null) return null;
    final today = philippineToday(now);
    return attendance
        .where((r) => r.studentId == me && r.date == today && !r.isArchived)
        .lastOrNull;
  }

  /// The task that logs [duty] for today, once the student made it.
  Task? dutyLogForToday(TaskDuty duty, [DateTime? now]) {
    final id = duty.logIdFor(_philippineDay(now));
    return tasks.where((t) => t.id == id).firstOrNull;
  }

  /// A Supervisor (or the Head) gives [student] an ongoing duty. Returns
  /// null when it worked, or what to tell them.
  Future<String?> createTaskDuty({
    required String title,
    required String description,
    required String priority,
    required String category,
    required Student student,
  }) async {
    final name = title.trim();
    if (name.isEmpty) return 'Give the duty a title.';
    if (name.length > TaskDuty.maxTitle) {
      return 'Keep the title under ${TaskDuty.maxTitle} characters.';
    }
    final me = currentUser;
    if (me == null || (role != 'Supervisor' && role != 'Head')) {
      return 'Only a Supervisor can give an ongoing duty.';
    }
    // The student's account id: that is who the duty is for, and who logs
    // it. A roster entry with no account behind it can't.
    final accountId = (student.userId ?? '').isNotEmpty
        ? student.userId!
        : student.id;
    final hasAccount = users.any(
      (u) => u.id == accountId && u.role == 'Student Assistant',
    );
    if (!hasAccount) {
      return '${student.name} has no Student Assistant account yet, so '
          "can't log a duty.";
    }
    final clash = taskDuties.any(
      (d) =>
          d.active &&
          d.assignedTo == accountId &&
          d.academicYear == academicYear &&
          d.title.trim().toLowerCase() == name.toLowerCase(),
    );
    if (clash) {
      return '${student.name} already has an ongoing duty called "$name".';
    }
    final duty = TaskDuty(
      id: 'duty_${DateTime.now().millisecondsSinceEpoch}',
      title: name,
      description: description.trim(),
      priority: priority,
      category: category,
      assignedTo: accountId,
      assignedToName: student.name,
      assignedBy: me.id,
      academicYear: academicYear,
    );
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTaskDuty(duty);
    } catch (error) {
      debugPrint('Failed to save task duty: $error');
      return "Couldn't save the duty. Check your connection and try again.";
    }
    taskDuties = [
      duty,
      for (final d in taskDuties)
        if (d.id != duty.id) d,
    ];
    notifyListeners();
    _addNotification(
      AppNotification(
        id: 'n_${DateTime.now().microsecondsSinceEpoch}_$accountId',
        userId: accountId,
        title: 'New Ongoing Duty',
        message:
            '${me.name} gave you an ongoing duty: "$name". On days you '
            'clock in, log your work on the Tasks screen.',
        type: 'task',
        createdAt: _formattedToday(),
      ),
    );
    notifyListeners();
    return null;
  }

  /// Stops an ongoing duty, or starts it again. Shown straight away, then
  /// saved; a refused save is undone and reported as false.
  Future<bool> setTaskDutyActive(String id, bool active) async {
    final index = taskDuties.indexWhere((d) => d.id == id);
    if (index < 0) return false;
    final previous = taskDuties;
    taskDuties = [...taskDuties]..[index] = taskDuties[index].copyWith(
      active: active,
    );
    notifyListeners();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTaskDutyActive(id, active);
      return true;
    } catch (error) {
      debugPrint('Failed to change task duty: $error');
      taskDuties = previous;
      notifyListeners();
      return false;
    }
  }

  /// Who approves [studentId]'s logs now: the heads of the office they are
  /// in. A student who moved offices has a new supervisor, so the one who
  /// gave the duty ([fallback]) is told only when no office is found.
  Set<String> _approversOf(String studentId, String fallback) {
    final heads = {
      for (final office in offices)
        if (office.isActive && office.assistantIds.contains(studentId))
          ...office.headIds,
    };
    return heads.isNotEmpty ? heads : {if (fallback.isNotEmpty) fallback};
  }

  void _tellApproversOfLog(Task log, String studentName, String when) {
    final me = currentUser?.id;
    for (final id in _approversOf(log.assignedTo ?? '', log.assignedBy ?? '')) {
      if (id == me) continue;
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().microsecondsSinceEpoch}_$id',
          userId: id,
          title: 'Task Awaiting Approval',
          message:
              '$studentName logged "${log.title}" for $when. Approve or '
              'reject it on the Tasks screen.',
          type: 'task',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();
  }

  /// The signed-in Student Assistant logs what they did for [duty] today.
  /// That makes today's task for the supervisor to approve, the same as a
  /// task the student completes: it needs a clock-in from today, and a day
  /// can be logged once. Returns null when it worked, or what to tell them.
  Future<String?> logDutyWork(TaskDuty duty, {String note = ''}) async {
    final me = currentUser;
    if (me == null || role != 'Student Assistant') {
      return 'Only a Student Assistant can log an ongoing duty.';
    }
    if (!duty.active ||
        duty.assignedTo != me.id ||
        duty.academicYear != academicYear) {
      return "This duty isn't open for logging.";
    }
    final record = attendanceForToday();
    if (record == null) {
      return "Clock in first. You can log a duty on a day you've clocked in.";
    }
    final text = note.trim();
    if (text.length > TaskDuty.maxNote) {
      return 'Keep the note under ${TaskDuty.maxNote} characters.';
    }
    if (dutyLogForToday(duty) != null) {
      return "You've already logged this duty today.";
    }
    final today = philippineToday();
    final log = Task(
      id: duty.logIdFor(_philippineDay()),
      title: duty.title,
      description: text,
      status: 'Completed',
      priority: duty.priority,
      dueDate: today,
      assignedTo: me.id,
      assignedToName: me.name,
      assignedBy: duty.assignedBy,
      category: duty.category,
      academicYear: duty.academicYear,
      completedAt: today,
      reviewStatus: 'Pending',
      dutyId: duty.id,
      attendanceId: record.id,
      workDate: today,
    );
    tasks = [log, ...tasks];
    notifyListeners();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.createDutyLog(log);
    } catch (error) {
      debugPrint('Failed to log duty: $error');
      // Take back only this log: other changes may have arrived meanwhile.
      tasks = [
        for (final t in tasks)
          if (t.id != log.id) t,
      ];
      notifyListeners();
      return "Couldn't save your log. Check your connection and try again.";
    }
    _tellApproversOfLog(log, me.name, today);
    return null;
  }

  /// Sends a rejected duty log again, with a corrected [note]. It keeps the
  /// day it was for. Returns null when it worked, or what to tell them.
  Future<String?> resubmitDutyLog(Task log, {String note = ''}) async {
    final me = currentUser;
    if (me == null || role != 'Student Assistant' || log.assignedTo != me.id) {
      return "This log isn't yours to send.";
    }
    final current = tasks.where((t) => t.id == log.id).firstOrNull;
    if (current == null || !current.isDutyLog || !current.wasRejected) {
      return "This log can't be sent again.";
    }
    final text = note.trim();
    if (text.length > TaskDuty.maxNote) {
      return 'Keep the note under ${TaskDuty.maxNote} characters.';
    }
    final day = current.workDate ?? current.completedAt ?? philippineToday();
    final sent = current.copyWith(
      description: text,
      status: 'Completed',
      completedAt: day,
      resetReview: true,
      reviewStatus: 'Pending',
    );
    tasks = [for (final t in tasks) t.id == sent.id ? sent : t];
    notifyListeners();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTask(sent);
    } catch (error) {
      debugPrint('Failed to resend duty log: $error');
      tasks = [for (final t in tasks) t.id == sent.id ? current : t];
      notifyListeners();
      return "Couldn't send it. Check your connection and try again.";
    }
    _tellApproversOfLog(sent, me.name, day);
    return null;
  }

  /// Most templates the Head can keep; they share one Firestore document.
  static const maxTaskTemplates = 60;

  /// The templates under [category], in the order the Head made them.
  List<TaskTemplate> templatesIn(String category) =>
      taskTemplates.where((t) => t.category == category).toList();

  /// Saves a template, new or changed. Returns null when it worked, or what
  /// to tell the Head.
  Future<String?> saveTaskTemplate(TaskTemplate template) async {
    final title = template.title.trim();
    if (title.isEmpty) return 'Give the template a title.';
    if (!taskCategories.contains(template.category)) {
      return 'Pick a category from the list.';
    }
    final clash = taskTemplates.any(
      (o) =>
          o.id != template.id &&
          o.category == template.category &&
          o.title.trim().toLowerCase() == title.toLowerCase(),
    );
    if (clash) {
      return '"${template.category}" already has a template called "$title".';
    }
    final isNew = !taskTemplates.any((o) => o.id == template.id);
    if (isNew && taskTemplates.length >= maxTaskTemplates) {
      return 'You can keep up to $maxTaskTemplates templates. Delete one '
          'you no longer use first.';
    }
    final clean = template.copyWith(
      title: title,
      description: template.description.trim(),
      checklist: [
        for (final item in template.checklist)
          if (item.trim().isNotEmpty) item.trim(),
      ],
    );
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.upsertTaskTemplate(clean.toJson());
    } catch (error) {
      debugPrint('Failed to save task template: $error');
      return "Couldn't save the template. Check your connection and try "
          'again.';
    }
    // The live listener may have delivered it already, so look again.
    taskTemplates = taskTemplates.any((o) => o.id == clean.id)
        ? [for (final o in taskTemplates) o.id == clean.id ? clean : o]
        : [...taskTemplates, clean];
    notifyListeners();
    return null;
  }

  /// Removes a template. Tasks already made from it are not touched.
  Future<String?> deleteTaskTemplate(String id) async {
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.removeTaskTemplate(id);
    } catch (error) {
      debugPrint('Failed to delete task template: $error');
      return "Couldn't delete the template. Check your connection and try "
          'again.';
    }
    taskTemplates = [
      for (final t in taskTemplates)
        if (t.id != id) t,
    ];
    notifyListeners();
    return null;
  }

  /// The skill on the list named [name], whatever its case or spacing:
  /// "communication skills" finds "Communication Skills".
  String? findSkill(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    return skills.where((s) => s.trim().toLowerCase() == key).firstOrNull;
  }

  /// [names] with one entry per skill whatever its case, keeping the
  /// best-written spelling (more capitals: "Communication Skills" over
  /// "Communication skills"), sorted. Names stay exactly as saved: a
  /// skill's name is its document's id, so a trimmed copy would be one no
  /// document has.
  static List<String> uniqueSkills(Iterable<String> names) {
    int capitals(String s) => RegExp('[A-Z]').allMatches(s).length;
    final kept = <String, String>{};
    for (final name in names) {
      final key = name.trim().toLowerCase();
      if (key.isEmpty) continue;
      final current = kept[key];
      if (current == null ||
          capitals(name) > capitals(current) ||
          (capitals(name) == capitals(current) &&
              name.compareTo(current) < 0)) {
        kept[key] = name;
      }
    }
    return kept.values.toList()..sort();
  }

  /// Takes the skills list as saved. The same skill saved twice in
  /// different case (the list used to allow it) shows once, and a Head's
  /// session deletes the extra spellings, which only the Head may write.
  void _setSkills(List<String> saved) {
    skills = uniqueSkills(saved);
    // A rename writes the new name before deleting the old, so for a
    // moment the two are both saved: that's not a duplicate to clear.
    if (role != 'Head' || _skillRenames > 0) return;
    final extras = [
      for (final name in saved)
        if (!skills.contains(name)) name,
    ];
    if (extras.isEmpty) return;
    _firestoreService ??= FirestoreService();
    for (final name in extras) {
      _firestoreService!.deleteSkill(name).catchError((Object error) {
        debugPrint('Failed to merge the duplicate skill "$name": $error');
      });
    }
  }

  Future<bool> addSkill(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty || findSkill(normalized) != null) return false;
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setSkill(normalized);
      skills = [...skills, normalized]..sort();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeSkill(String name) async {
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.deleteSkill(name);
      skills = skills.where((skill) => skill != name).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Skill renames being saved; see [_setSkills].
  int _skillRenames = 0;

  Future<bool> updateSkill(String oldName, String newName) async {
    final normalized = newName.trim();
    // Another skill by that name, in any case, is refused; this one's own
    // name in another case ("communication skills" to "Communication
    // Skills") is a rename.
    final clash = findSkill(normalized);
    if (normalized.isEmpty || (clash != null && clash != oldName)) {
      return false;
    }
    _skillRenames++;
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateSkill(oldName, normalized);
      skills =
          skills.map((skill) => skill == oldName ? normalized : skill).toList()
            ..sort();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _skillRenames--;
    }
  }

  Future<bool> removeDepartment(String name) async {
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.deleteDepartment(name);
      departments = departments.where((d) => d != name).toList();
      departmentCodes.remove(name);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateDepartment(
    String oldName,
    String newName, {
    String code = '',
  }) async {
    final normalized = newName.trim();
    if (normalized.isEmpty ||
        (normalized != oldName && departments.contains(normalized))) {
      return false;
    }
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateDepartment(oldName, normalized);
      departments = departments
          .map((department) => department == oldName ? normalized : department)
          .toList();
      await _firestoreService!.setDepartment(normalized, code: code.trim());
      departmentCodes.remove(oldName);
      departmentCodes[normalized] = code.trim();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Programs ──────────────────────────────────────
  List<Program> _sortedPrograms(Iterable<Program> list) => [
    for (final p in list)
      if (p.code.trim().isNotEmpty) p,
  ]..sort((a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()));

  /// The programs under [department], by code.
  List<Program> programsForDepartment(String? department) =>
      programs.where((p) => p.department == department).toList();

  /// The program whose code is [code], ignoring case, if there is one.
  Program? programByCode(String? code) {
    final wanted = code?.trim().toLowerCase() ?? '';
    if (wanted.isEmpty) return null;
    return programs
        .where((p) => p.code.trim().toLowerCase() == wanted)
        .firstOrNull;
  }

  /// Adds [program], or saves changes to it when it has an id. Refuses a
  /// blank code or name, or a code another program already uses. Students
  /// who already chose a program keep its old code if the code changes, as
  /// they keep a renamed department.
  Future<bool> saveProgram(Program program) async {
    final cleaned = program.copyWith(
      code: program.code.trim(),
      name: program.name.trim(),
      department: program.department.trim(),
    );
    if (cleaned.code.isEmpty || cleaned.name.isEmpty) return false;
    final clash = programByCode(cleaned.code);
    if (clash != null && clash.id != cleaned.id) return false;
    try {
      _firestoreService ??= FirestoreService();
      final id = await _firestoreService!.saveProgram(cleaned);
      programs = _sortedPrograms([
        for (final p in programs)
          if (p.id != id) p,
        Program(
          id: id,
          code: cleaned.code,
          name: cleaned.name,
          department: cleaned.department,
        ),
      ]);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeProgram(Program program) async {
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.deleteProgram(program.id);
      programs = programs.where((p) => p.id != program.id).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads the department and program lists for the registration form,
  /// which a visitor fills in before they have an account. The Firestore
  /// rules let anyone read both lists for this. Keeps the built-in
  /// department list if nothing is stored yet or the read fails.
  Future<void> loadRegistrationCatalog() async {
    try {
      _firestoreService ??= FirestoreService();
      // One read gives both the names and their codes.
      final codes = await _firestoreService!.getDepartmentCodes();
      if (codes.isNotEmpty) {
        departments = codes.keys.toList()..sort();
        departmentCodes = codes;
      }
      programs = _sortedPrograms(await _firestoreService!.getAllPrograms());
      notifyListeners();
    } catch (error) {
      debugPrint('Registration lists failed to load: $error');
    }
  }

  // ─── Applications ──────────────────────────────────
  Future<void> saveScreeningRecord(ScreeningRecord record) async {
    _firestoreService ??= FirestoreService();
    final recordYear = record.academicYear ?? academicYear;
    final stableRecord = record
        .withId(
          ScreeningRecord.stableIdForApplicant(
            applicantId: record.applicantId,
            applicationId: record.applicationId,
            fallback: record.id,
            academicYear: recordYear,
          ),
        )
        .copyWithMeta(
          academicYear: recordYear,
          createdAt: record.createdAt ?? DateTime.now().toIso8601String(),
        );
    await _firestoreService!.setScreeningRecord(stableRecord);
    // Only collapse duplicates raised within the SAME academic year (e.g. a
    // legacy un-keyed record for this applicant/year); records from other
    // academic years are left alone so screening history is preserved.
    final normalizedName = record.fullName.trim().toLowerCase();
    final normalizedStudentNumber = record.studentNumber.trim().toLowerCase();
    final duplicates = (await _firestoreService!.getAllScreeningRecords())
        .where(
          (candidate) =>
              candidate.id != stableRecord.id &&
              (candidate.academicYear ?? '') ==
                  (stableRecord.academicYear ?? '') &&
              candidate.fullName.trim().toLowerCase() == normalizedName &&
              candidate.studentNumber.trim().toLowerCase() ==
                  normalizedStudentNumber,
        )
        .toList();
    for (final duplicate in duplicates) {
      if (duplicate.id != stableRecord.id) {
        await _firestoreService!.deleteScreeningRecord(duplicate.id);
      }
    }

    screeningRecords = [
      stableRecord,
      ...screeningRecords.where(
        (item) =>
            item.id != stableRecord.id &&
            !duplicates.any((d) => d.id == item.id),
      ),
    ];
    notifyListeners();
  }

  /// [list] with [item] added at the front, unless it's already there. A
  /// live listener usually has it first: Firestore reports a new document
  /// as soon as it's written, before the save itself returns.
  static List<T> _withAdded<T>(List<T> list, T item, String Function(T) idOf) =>
      list.any((x) => idOf(x) == idOf(item)) ? list : [item, ...list];

  // ─── Document Folders (Head file manager) ─────────────

  /// "to be a Student Assistant", or for an older application to a
  /// posting, "for" and its title in quotes.
  static String _appliedFor(Application app) =>
      app.announcementTitle.isEmpty ||
          app.announcementTitle == Application.generalTitle
      ? 'to be a Student Assistant'
      : 'for "${app.announcementTitle}"';

  // ─── Notifications ─────────────────────────────────
  /// The longest title and message a notification may carry: firestore.rules
  /// refuses more, so nobody can use a notification to send an essay (or a
  /// page of text dressed up as an alert) to the Head.
  static const notificationTitleMax = 100;
  static const notificationMessageMax = 500;

  /// [text] cut to [max] characters, ending in an ellipsis when it was cut.
  @visibleForTesting
  static String clipNotificationText(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1).trimRight()}…';

  static const _docIdChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final _docIdRandom = Random.secure();

  /// A random 20-character id, the same shape Firestore generates.
  String _newDocId() => String.fromCharCodes([
    for (var i = 0; i < 20; i++)
      _docIdChars.codeUnitAt(_docIdRandom.nextInt(_docIdChars.length)),
  ]);

  /// Saves [n] under [id] when given (one that must only ever be sent once),
  /// else under a new random id, and has it pushed to the recipient's
  /// devices unless [push] is off.
  void _addNotification(AppNotification n, {String? id, bool push = true}) {
    // The local copy gets the id the saved one will have, so marking it read
    // or deleting it before the live feed catches up reaches the saved one.
    id ??= _newDocId();
    // The rules refuse longer text, so a long reason or remark is cut here.
    final payload = {
      ...n.toJson(),
      'title': clipNotificationText(n.title, notificationTitleMax),
      'message': clipNotificationText(n.message, notificationMessageMax),
    };
    final local = AppNotification.fromJson({
      ...payload,
      'id': id,
      'createdAt': DateTime.now(),
    });
    notifications = [local, ...notifications];
    _firestoreService ??= FirestoreService();
    final savedId = id;
    _firestoreService!
        .addNotification({...payload, 'id': id})
        .then((_) {
          // Only once it's saved: the push function reads it from there.
          if (push) _queuePush(savedId);
        })
        .catchError((error) {
          debugPrint('Failed to persist notification: $error');
          // It never reached anyone: take back the copy shown here, and say
          // so rather than let the sender think they were told.
          // Only this optimistic copy: a saved one the live feed already
          // delivered (a reminder the server made first) stays.
          notifications = [
            for (final item in notifications)
              if (!identical(item, local)) item,
          ];
          if (!_disposed) {
            notifyListeners();
            if (!_problemNotices.isClosed) {
              _problemNotices.add(
                '"${n.title}" could not be sent. Tell the person yourself, '
                'or try the action again.',
              );
            }
          }
        });
  }

  final _problemNotices = StreamController<String>.broadcast();

  /// Things that failed in the background, such as a notification that
  /// couldn't be saved, for the shell to show: nothing else would tell the
  /// person who did the action.
  Stream<String> get problemNotices => _problemNotices.stream;

  final _pushQueue = <String>[];

  /// Gathers the notifications saved in one go (approving several
  /// applications, say) into one request to the push function.
  void _queuePush(String id) {
    _pushQueue.add(id);
    if (_pushQueue.length > 1) return;
    scheduleMicrotask(() {
      final ids = List.of(_pushQueue);
      _pushQueue.clear();
      _push.deliver(ids);
    });
  }

  void _notifyOfficeUsers(
    Iterable<String> userIds, {
    required String title,
    required String message,
  }) {
    final uniqueIds = userIds.where((id) => id.isNotEmpty).toSet();
    for (final userId in uniqueIds) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().microsecondsSinceEpoch}_office_$userId',
          userId: userId,
          title: title,
          message: message,
          type: 'office',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();
  }

  /// Writes the Head accounts to meta/heads for [_headIds]. Only called
  /// with the full roster from the Users listener — a partial list here
  /// would leave students alerting too few Heads.
  void _publishHeadIds() {
    final ids = [
      for (final u in users)
        if (u.role == 'Head' && u.status != 'Archived') u.id,
    ]..sort();
    final joined = ids.join(',');
    if (ids.isEmpty || joined == _publishedHeadIds) return;
    _publishedHeadIds = joined;
    _firestoreService?.setHeadIds(ids).catchError((Object error) {
      _publishedHeadIds = null;
      debugPrint('Failed to publish the Head list: $error');
    });
  }

  /// Keeps the `studentIds` reservations in step with the profiles, from
  /// the full roster the Users listener delivers: accounts made before
  /// reservations existed get theirs (so a newcomer can't register the
  /// same ID), and an ID the Admin changed on a profile frees the old one.
  /// Reservations for accounts not in the roster — deleted ones, or a
  /// registration newer than this list — are left alone.
  Future<void> _syncStudentIdClaims() async {
    final fs = _firestoreService;
    if (fs == null) return;
    final keyOf = {for (final u in users) u.id: studentIdKey(u.studentId)};
    final signature =
        (keyOf.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(
          ',',
        );
    if (signature == _syncedStudentIds) return;
    _syncedStudentIds = signature;
    try {
      final claims = await fs.getStudentIdClaims();
      final changes = <String, String?>{};
      for (final MapEntry(key: id, value: holder) in claims.entries) {
        if (keyOf.containsKey(holder) && keyOf[holder] != id) {
          changes[id] = null;
        }
      }
      final held = {...claims}..removeWhere((id, _) => changes.containsKey(id));
      for (final user in users) {
        final id = keyOf[user.id];
        // Two older accounts sharing an ID: the first keeps it.
        if (id == null || held.containsKey(id)) continue;
        held[id] = user.id;
        changes[id] = user.id;
      }
      if (changes.isNotEmpty) await fs.writeStudentIdClaims(changes);
    } catch (error) {
      _syncedStudentIds = null;
      debugPrint('Failed to sync Student ID reservations: $error');
    }
  }

  /// The Heads to alert about something. Staff know them from the roster;
  /// everyone else reads the list staff sessions publish.
  Future<List<String>> _headIds() async {
    final known = [
      for (final u in users)
        if (u.role == 'Head') u.id,
    ];
    if (known.isNotEmpty) return known;
    try {
      _firestoreService ??= FirestoreService();
      return await _firestoreService!.getHeadIds();
    } catch (error) {
      debugPrint('Failed to look up the Heads: $error');
      return [];
    }
  }

  Future<void> _loadNotificationsForCurrentUser() async {
    final user = currentUser;
    if (user == null) return;
    try {
      _firestoreService ??= FirestoreService();
      final stored = await _firestoreService!.getNotificationsForUser(user.id);
      notifications = stored.map(AppNotification.fromJson).toList();
      notifyListeners();
    } catch (error) {
      debugPrint('Failed to load notifications: $error');
    }
  }

  List<AppNotification> get myNotifications {
    if (currentUser == null) return [];
    return notifications.where((n) => n.userId == currentUser!.id).toList();
  }

  int get unreadNotificationCount =>
      myNotifications.where((n) => !n.isRead).length;

  /// The tab a notification is about, among those the signed-in role has,
  /// or null when there's nothing more to see than its message (a payout,
  /// an evaluation result, a rehire decision). Student Portal tabs use the
  /// same ids: 'announcements' and 'profile'.
  String? notificationTab(AppNotification n) {
    return switch ((n.type, role)) {
      ('announcement', 'Head') => 'announcements_admin',
      ('announcement', 'Supervisor') => 'sv_announcements',
      ('announcement', 'Student Assistant' || 'Student') => 'announcements',
      ('application', 'Head') => 'applications',
      // A student's applications are listed on the Announcements screen.
      ('application', 'Student') => 'announcements',
      ('task', 'Head' || 'Supervisor' || 'Student Assistant') => 'tasks',
      ('report', 'Supervisor' || 'Student Assistant') => 'reports',
      ('head_forward', 'Head') => 'head_forwards',
      ('office', 'Head') => 'offices',
      ('office', 'Supervisor') => 'students',
      ('attendance', 'Student Assistant') => 'attendance',
      // A returned or missing DTR is sent again from there.
      ('payroll_requirement', 'Supervisor') => 'dtr_accomplishment_report',
      // Role changes: the profile shows the new role.
      ('system', _) => 'profile',
      _ => null,
    };
  }

  void markNotificationRead(String id) {
    notifications = notifications
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
    _firestoreService?.updateNotification(id, {'isRead': true}).catchError((
      error,
    ) {
      debugPrint('Failed to update notification: $error');
    });
    notifyListeners();
  }

  void markAllNotificationsRead() {
    // Only the unread ones need a write; the rest are already saved as read.
    final unread = myNotifications.where((n) => !n.isRead).toList();
    notifications = notifications
        .map((n) => n.userId == currentUser?.id ? n.copyWith(isRead: true) : n)
        .toList();
    for (final notification in unread) {
      _firestoreService
          ?.updateNotification(notification.id, {'isRead': true})
          .catchError((error) {
            debugPrint('Failed to update notification: $error');
          });
    }
    notifyListeners();
  }

  void deleteNotification(String id) {
    notifications = notifications.where((n) => n.id != id).toList();
    _firestoreService?.deleteNotification(id).catchError((error) {
      debugPrint('Failed to delete notification: $error');
    });
    notifyListeners();
  }

  Future<void> clearAllNotifications() async {
    final userId = currentUser?.id;
    if (userId == null) return;
    notifications = notifications.where((n) => n.userId != userId).toList();
    notifyListeners();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.deleteNotificationsForUser(userId);
    } catch (error) {
      debugPrint('Failed to clear notifications: $error');
    }
  }

  void addStudent(Student student) {
    students = [...students, student];
    notifyListeners();
  }

  /// Archives a student by deactivating their account — the same switch
  /// the Admin's Accounts screen uses — so they're signed out and can't log
  /// in, clock in, or change anything until restored. That alone takes
  /// them off every roster (Students, Tasks, Schedule, DTR, evaluations)
  /// and onto the Students screen's archived list; see [archivedStudents].
  /// They're also taken off their office, whose supervisors are told.
  /// Their records are kept. Returns an error message, or null once it's
  /// done.
  Future<String?> archiveStudent(String id) async {
    const failed = "Couldn't archive the student. Please try again.";
    final base = _studentRecordFor(id).base;
    if (base == null) return failed;
    final account = _accountForStudent(base);
    if (account == null) {
      // An old roster entry with no account: only the record can go.
      final saved = await _saveStudentRecord(
        id,
        (s) => s.copyWith(status: 'Archived'),
      );
      return saved ? null : failed;
    }
    final memberOf = [
      for (final office in offices)
        if (office.hasAssistant(account.id, account.name)) office,
    ];

    if (!await _setAccountStatus(account, 'Archived')) return failed;
    if (memberOf.isEmpty) return null;

    try {
      await _setAssistantOffice(account, null);
    } catch (error) {
      debugPrint('Failed to take ${account.id} off their office: $error');
      return "${account.name} was archived, but couldn't be removed from "
          '${memberOf.map((o) => o.name).join(', ')}. Remove them from the '
          'Offices screen.';
    }
    for (final office in memberOf) {
      _notifyOfficeUsers(
        office.headIds,
        title: 'Student Assistant Archived',
        message:
            '${account.name} was archived and removed from ${office.name}.',
      );
    }
    return null;
  }

  /// Reactivates an archived student's account, which puts them back on
  /// the roster and lets them sign in again — whether the Head or the
  /// Admin archived them. Their office isn't restored; the Head assigns one
  /// from the Offices screen. Only a Student Assistant comes back this way:
  /// someone who wasn't rehired is a Student again, and returns through
  /// the Rehiring screen or a new application instead. Returns an error
  /// message, or null once it's saved.
  Future<String?> restoreStudent(String id) async {
    const failed = "Couldn't restore the student. Please try again.";
    final record = students.where((s) => s.id == id).firstOrNull;
    // Someone archived with no record is listed under their account id.
    final account = record != null
        ? _accountForStudent(record)
        : users.where((u) => u.id == id).firstOrNull;
    if (account != null && account.role != 'Student Assistant') {
      return '${account.name} is no longer a Student Assistant. Rehire them '
          'from the Rehiring screen instead.';
    }
    if (record != null && record.status == 'Archived') {
      // Older data can have the record itself archived; it comes back too.
      final saved = await _saveStudentRecord(
        id,
        (s) => s.copyWith(status: 'Active'),
        accountChange: account?.status == 'Archived'
            ? (u) => u.copyWith(status: 'Active')
            : null,
      );
      return saved ? null : failed;
    }
    if (account == null) return failed;
    return await _setAccountStatus(account, 'Active') ? null : failed;
  }

  /// Saves [account] with [status]. Shown straight away; a save the
  /// Firestore rules or the connection refuse is undone here and reported
  /// as false.
  Future<bool> _setAccountStatus(User account, String status) async {
    final updated = account.copyWith(status: status);
    final previousUsers = users;
    users = [for (final u in users) u.id == account.id ? updated : u];
    notifyListeners();
    try {
      // Only the status: see FirestoreService.updateUserFields.
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateUserFields(account.id, {
        'status': status,
      });
      return true;
    } catch (error) {
      debugPrint('Failed to set account ${account.id} to $status: $error');
      users = previousUsers;
      notifyListeners();
      return false;
    }
  }

  /// The account a students record belongs to, by its userId or email.
  User? _accountForStudent(Student s) => _accountLookup()(s);

  /// Finds the account a students record belongs to, by its userId or
  /// email. Build it once to look up a whole roster.
  User? Function(Student) _accountLookup() {
    final byId = {for (final u in users) u.id: u};
    final byEmail = {for (final u in users) u.email.trim().toLowerCase(): u};
    return (s) {
      final byUserId = s.userId == null ? null : byId[s.userId];
      if (byUserId != null) return byUserId;
      final email = s.email.trim().toLowerCase();
      return email.isEmpty ? null : byEmail[email];
    };
  }

  /// The students record [id] as stored, or — for a Student Assistant
  /// listed only from their account (see [effectiveStudents]) — the listing
  /// to create one from. Null when there is neither.
  ({Student? stored, Student? base}) _studentRecordFor(String id) {
    final stored = students.where((s) => s.id == id).firstOrNull;
    return (
      stored: stored,
      base: stored ?? effectiveStudents.where((s) => s.id == id).firstOrNull,
    );
  }

  /// Applies [change] to the students record [id] — and [accountChange],
  /// when given, to the account it belongs to — and saves both in one
  /// write, so the two never disagree. Shown straight away; a save the
  /// Firestore rules or the connection refuse is undone here and reported
  /// as false, so the roster never shows a change that isn't on file.
  Future<bool> _saveStudentRecord(
    String id,
    Student Function(Student) change, {
    User Function(User)? accountChange,
  }) async {
    final (:stored, :base) = _studentRecordFor(id);
    if (base == null) return false;
    final updated = change(base);
    final account = accountChange == null ? null : _accountForStudent(updated);
    final updatedAccount = account == null ? null : accountChange!(account);

    final previousStudents = students;
    final previousUsers = users;
    students = stored == null
        ? [...students, updated]
        : [for (final s in students) s.id == id ? updated : s];
    if (updatedAccount != null) {
      users = [
        for (final u in users) u.id == updatedAccount.id ? updatedAccount : u,
      ];
    }
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      if (updatedAccount == null) {
        await _firestoreService!.setStudent(updated);
      } else {
        await _firestoreService!.setStudentWithProfile(updated, updatedAccount);
      }
      return true;
    } catch (error) {
      debugPrint('Failed to save students record $id: $error');
      students = previousStudents;
      users = previousUsers;
      notifyListeners();
      return false;
    }
  }

  /// Students who are archived — their account deactivated by the Head or
  /// the Admin, or their record archived because they weren't rehired —
  /// scoped like [filteredStudents]. They're left off every other roster;
  /// the Students screen lists them separately.
  List<Student> get archivedStudents => switch (role) {
    'Head' => _archivedStudentRecords(),
    'Supervisor' =>
      _archivedStudentRecords().where(_studentBelongsToCurrentOffice).toList(),
    _ => const [],
  };

  /// Everyone off the roster for being archived, one entry each, filled in
  /// from their account and marked Archived. Someone with an active record
  /// and account is on the roster instead.
  List<Student> _archivedStudentRecords() {
    final accountOf = _accountLookup();
    final onRoster = <String>{};
    final archived = <Student>[];
    for (final s in students) {
      final account = accountOf(s);
      if (s.status != 'Archived' && account?.status != 'Archived') {
        onRoster.addAll([s.id, ?s.userId, ?account?.id]);
      } else {
        archived.add(
          _withAccountDetails(s, account).copyWith(status: 'Archived'),
        );
      }
    }
    final listed = <String>{};
    final result = [
      for (final s in archived)
        if (!onRoster.contains(s.id) &&
            !onRoster.contains(s.userId) &&
            listed.add(s.userId ?? s.id))
          s,
    ];
    // An archived Student Assistant who never had a record.
    for (final u in users) {
      if (u.role != 'Student Assistant' ||
          u.status != 'Archived' ||
          onRoster.contains(u.id) ||
          !listed.add(u.id)) {
        continue;
      }
      result.add(
        Student(
          id: u.id,
          name: u.name,
          email: u.email,
          department: u.department ?? '',
          campus: u.campus,
          status: 'Archived',
          phone: u.phone,
          address: u.address,
          avatar: u.avatar,
          userId: u.id,
        ),
      );
    }
    return result;
  }

  Student _withAccountDetails(Student s, User? account) => s.copyWith(
    name: account?.name,
    email: account?.email,
    department: s.department.isNotEmpty ? null : account?.department,
    campus: s.campus ?? account?.campus,
    avatar: s.avatar ?? account?.avatar,
    userId: s.userId ?? account?.id,
  );

  void deleteStudent(String id) {
    students = students.where((s) => s.id != id).toList();
    notifyListeners();
  }

  // ─── Attendance CRUD ───────────────────────────────
  /// Clocks the student in or out by handing the scanned token to the
  /// `clockAttendance` function.
  ///
  /// The device decides nothing here. The server checks that the token is
  /// the current session's, that the window is open by its own clock, and
  /// whether this is a clock-in or a clock-out — then writes the record
  /// with admin credentials, since the rules keep attendance staff-only.
  /// That means a student can't forge hours by calling Firestore directly
  /// or by moving their phone's clock.
  Future<QrClockResult> clockViaQr(String token) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser
          ?.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        return const QrClockResult(
          ok: false,
          message: 'You must be signed in to clock in.',
        );
      }

      final response = await http.post(
        Uri.parse(SupabaseStorageService.clockAttendanceUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'apikey': SupabaseStorageService.publishableKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': token}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason =
            body['error']?.toString() ??
            'The attendance server rejected that scan.';
        debugPrint('Clock via QR rejected (${response.statusCode}): $reason');
        return QrClockResult(ok: false, message: reason);
      }

      // The attendance stream delivers the new record on its own, so there
      // is nothing to patch into local state here.
      return QrClockResult(
        ok: true,
        clockedIn: body['action']?.toString() == 'in',
        // Set when the weekly hours cap trimmed this session's hours.
        message: body['message']?.toString() ?? '',
      );
    } catch (error) {
      debugPrint('Clock via QR failed: $error');
      return const QrClockResult(
        ok: false,
        message:
            'Could not reach the attendance server. Check your '
            'connection and try again.',
      );
    }
  }

  /// Actual elapsed hours between a "H:MM AM/PM" time-in and time-out on
  /// the same day.
  ///
  /// Returns 0 rather than a guess when the times can't be trusted — either
  /// string unparseable, or a time-out at or before the time-in. These hours
  /// feed payroll, so an unearned four hours is far worse than a zero the
  /// Head can correct with a manual time-out. (Times are stored to the
  /// minute, so a session shorter than a minute genuinely is 0 hours.)
  double _hoursBetween(String? timeIn, String timeOut) {
    final inMinutes = _parseTimeOfDayMinutes(timeIn ?? '');
    final outMinutes = _parseTimeOfDayMinutes(timeOut);
    if (inMinutes == null || outMinutes == null) return 0.0;
    final diff = outMinutes - inMinutes;
    if (diff <= 0) return 0.0;
    return diff / 60.0;
  }

  /// A Head/Supervisor manually completing a student's missed time-out —
  /// the actual verification step the System needs before those hours can
  /// count toward payroll. Sets a real time-out and computes real elapsed
  /// hours (same as [clockOut]), and clears [AttendanceRecord.isInvalid]
  /// since a human has now confirmed when the student actually left.
  ///
  /// Returns whether it saved. A refused save is undone here, so the log
  /// never shows a time-out that isn't really on file.
  Future<bool> setManualTimeOut(String recordId, String timeOut) async {
    final existing = attendance.cast<AttendanceRecord?>().firstWhere(
      (r) => r?.id == recordId,
      orElse: () => null,
    );
    final elapsed = _hoursBetween(existing?.timeIn, timeOut);
    // A person confirming the time-out doesn't lift the weekly cap: the
    // clock-attendance function would have trimmed these hours the same way.
    final totalHours = existing == null
        ? elapsed
        : _hoursWithinWeeklyCap(existing, elapsed);

    final previousAttendance = attendance;
    attendance = attendance.map((r) {
      if (r.id != recordId) return r;
      return AttendanceRecord(
        id: r.id,
        studentName: r.studentName,
        studentId: r.studentId,
        date: r.date,
        timeIn: r.timeIn,
        timeOut: timeOut,
        totalHours: totalHours,
        academicYear: r.academicYear,
        isArchived: r.isArchived,
        archivedAcademicYear: r.archivedAcademicYear,
        isInvalid: false,
      );
    }).toList();
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateAttendance(recordId, {
        'timeOut': timeOut,
        'totalHours': totalHours,
        'isInvalid': false,
        // Kept alongside, as clock-attendance does, when the cap trimmed it.
        if (totalHours < elapsed) 'hoursBeforeWeeklyCap': elapsed,
      });
      return true;
    } catch (error) {
      debugPrint('Failed to save the manual time-out: $error');
      attendance = previousAttendance;
      notifyListeners();
      return false;
    }
  }

  /// How much of [elapsed] hours, worked in the session [record] holds, the
  /// student's weekly cap still credits: the cap (when the Admin has it on)
  /// less what their other finished sessions that Monday–Sunday week already
  /// count. The same rule clock-attendance applies at the time-out.
  ///
  /// [pending] holds hours about to be saved (by record id) that stand in
  /// for what the records show, so corrections made together share one
  /// budget instead of each seeing the same room.
  double _hoursWithinWeeklyCap(
    AttendanceRecord record,
    double elapsed, {
    Map<String, double> pending = const {},
  }) {
    if (!enforceAssistantHourCap) return elapsed;
    final day = _parseFormattedDate(record.date);
    if (day == null) return elapsed;
    final monday = DateTime(
      day.year,
      day.month,
      day.day,
    ).subtract(Duration(days: day.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    final used = attendance
        .where((r) {
          if (r.id == record.id || r.studentId != record.studentId) {
            return false;
          }
          if (r.isActive || r.isArchived || r.isInvalid) return false;
          final d = _parseFormattedDate(r.date);
          return d != null && !d.isBefore(monday) && d.isBefore(nextMonday);
        })
        .fold<double>(
          0,
          (total, r) => total + (pending[r.id] ?? r.totalHours ?? 0),
        );
    final room = weeklyHourCap - used;
    if (room <= 0) return 0;
    return elapsed < room ? elapsed : room;
  }

  /// Repair for attendance records saved with a placeholder duration rather
  /// than a real one — first when clocking out hard-coded every session at a
  /// flat 4.0 hours, and later when [_hoursBetween] fell back to 4.0 for a
  /// time-out at or before the time-in. Anything with both a time-in and a
  /// time-out already has everything needed to recompute its true duration,
  /// so this recalculates [AttendanceRecord.totalHours] for every completed
  /// record from its own stored timestamps and re-saves only the ones that
  /// actually changed.
  ///
  /// It only ever corrects a record downwards, or fills one that has no
  /// hours at all (within the weekly cap, oldest first, so they share one
  /// budget). It never raises hours a record already has, even zero: those
  /// may have been trimmed by the weekly cap when the student clocked out,
  /// and putting the full elapsed time back would undo that.
  ///
  /// Returns how many records were written and how many could not be. A
  /// failed write leaves the local value fixed but the stored one stale,
  /// and the attendance stream then pushes the old value straight back —
  /// which looks exactly like the button doing nothing. Callers must report
  /// [failed] instead of claiming success.
  Future<({int fixed, int failed})> recalculateAttendanceHours() async {
    _firestoreService ??= FirestoreService();
    final corrections = <String, double>{};

    final unfilled = <AttendanceRecord>[];
    for (final r in attendance) {
      if (r.isActive) continue; // no time-out yet — nothing to recompute.
      final stored = r.totalHours;
      if (stored == null) {
        unfilled.add(r);
        continue;
      }
      final elapsed = _hoursBetween(r.timeIn, r.timeOut!);
      if (stored - elapsed > 0.01) corrections[r.id] = elapsed;
    }
    // Oldest first: each fill uses up part of the week's room, and the
    // lowered figures above have already given some back.
    DateTime when(AttendanceRecord r) =>
        (_parseFormattedDate(r.date) ?? DateTime(1970)).add(
          Duration(minutes: _parseTimeOfDayMinutes(r.timeIn) ?? 0),
        );
    unfilled.sort((a, b) => when(a).compareTo(when(b)));
    for (final r in unfilled) {
      corrections[r.id] = _hoursWithinWeeklyCap(
        r,
        _hoursBetween(r.timeIn, r.timeOut!),
        pending: corrections,
      );
    }

    if (corrections.isEmpty) return (fixed: 0, failed: 0);

    attendance = attendance.map((r) {
      final fixed = corrections[r.id];
      if (fixed == null) return r;
      return AttendanceRecord(
        id: r.id,
        studentName: r.studentName,
        studentId: r.studentId,
        date: r.date,
        timeIn: r.timeIn,
        timeOut: r.timeOut,
        totalHours: fixed,
        academicYear: r.academicYear,
        isArchived: r.isArchived,
        archivedAcademicYear: r.archivedAcademicYear,
        isInvalid: r.isInvalid,
      );
    }).toList();
    notifyListeners();

    // Each correction targets a different document, so fire them
    // concurrently instead of paying one round trip at a time.
    var failed = 0;
    await Future.wait(
      corrections.entries.map((entry) async {
        try {
          await _firestoreService!.updateAttendance(entry.key, {
            'totalHours': entry.value,
          });
        } catch (e) {
          // Most often a rules rejection (the signed-in account is not
          // Head/Supervisor) — worth seeing, since the stream will quietly
          // restore the stale hours a moment later.
          debugPrint('Could not save recalculated hours for ${entry.key}: $e');
          failed++;
        }
      }),
    );

    return (fixed: corrections.length - failed, failed: failed);
  }

  /// Parses a "H:MM AM/PM" time-of-day string (the format [clockIn]/
  /// [clockOut] store) into minutes since midnight, or null if it can't
  /// be parsed.
  int? _parseTimeOfDayMinutes(String time) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(time.trim());
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)!.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  /// Marks any still-clocked-in attendance record as invalid once its
  /// session window (morning or afternoon) has closed without a time-out —
  /// the student missed their time-out, so the record stops counting
  /// toward verified hours. A record from a previous day that's still
  /// active is treated the same way (its window is long past).
  Future<void> invalidateMissedTimeOuts() async {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final todayStr = _formattedToday();

    // A Supervisor may only change their own office's records (the Firestore
    // rules refuse the rest), so their sweep covers just those; the Head's
    // covers everyone.
    final sweep = role == 'Supervisor' ? filteredAttendance : attendance;
    final toInvalidate = <String>[];
    for (final record in sweep) {
      if (!record.isActive || record.isInvalid || record.isArchived) {
        continue;
      }

      if (record.date.isNotEmpty && record.date != todayStr) {
        toInvalidate.add(record.id);
        continue;
      }

      final timeInMinutes = _parseTimeOfDayMinutes(record.timeIn);
      if (timeInMinutes == null) continue;

      final inMorningWindow = timeInMinutes <= _qrMorningEndMinutes;
      final cutoff = inMorningWindow
          ? _qrMorningEndMinutes
          : _qrAfternoonEndMinutes;
      if (nowMinutes > cutoff) {
        toInvalidate.add(record.id);
      }
    }

    if (toInvalidate.isEmpty) return;

    final invalidIds = toInvalidate.toSet();
    attendance = attendance.map((r) {
      if (!invalidIds.contains(r.id)) return r;
      return AttendanceRecord(
        id: r.id,
        studentName: r.studentName,
        studentId: r.studentId,
        date: r.date,
        timeIn: r.timeIn,
        timeOut: r.timeOut,
        totalHours: r.totalHours,
        academicYear: r.academicYear,
        isArchived: r.isArchived,
        archivedAcademicYear: r.archivedAcademicYear,
        isInvalid: true,
      );
    }).toList();
    notifyListeners();

    _firestoreService ??= FirestoreService();
    for (final id in toInvalidate) {
      try {
        await _firestoreService!.updateAttendance(id, {'isInvalid': true});
      } catch (_) {
        // Firestore unavailable, or a record the rules keep from this
        // user — local state is still updated; the next successful sweep
        // will persist it. One failure mustn't stop the rest.
      }
    }
  }

  /// Archives or restores one attendance record.
  ///
  /// Archiving is the reversible counterpart to deleting: the record leaves
  /// the working log and stops counting toward verified hours, but it stays
  /// on file for the DTR and the payroll trail.
  Future<bool> setAttendanceArchived(String id, bool archived) async {
    // Archived by hand, a record is no longer one archived with its year,
    // which payroll would still pay for.
    attendance = attendance
        .map(
          (a) => a.id == id
              ? AttendanceRecord(
                  id: a.id,
                  studentName: a.studentName,
                  studentId: a.studentId,
                  date: a.date,
                  timeIn: a.timeIn,
                  timeOut: a.timeOut,
                  totalHours: a.totalHours,
                  academicYear: a.academicYear,
                  isArchived: archived,
                  isInvalid: a.isInvalid,
                )
              : a,
        )
        .toList();
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateAttendance(id, {
        'isArchived': archived,
        'archivedAcademicYear': FieldValue.delete(),
      });
      return true;
    } catch (error) {
      debugPrint('Could not archive attendance record: $error');
      return false;
    }
  }

  Future<bool> deleteAttendance(String id) async {
    attendance = attendance.where((a) => a.id != id).toList();
    notifyListeners();

    // Without this the record only vanished from this device and came
    // straight back on the next load.
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.deleteAttendance(id);
      return true;
    } catch (error) {
      debugPrint('Could not delete attendance record: $error');
      return false;
    }
  }

  // ─── Tasks CRUD ────────────────────────────────────
  /// Assigns a task. Shown straight away, then saved; a save the Firestore
  /// rules or the connection refuse is undone here and reported as false,
  /// and only a saved task notifies the student.
  Future<bool> addTask(Task task) async {
    task = Task(
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      dueDate: task.dueDate,
      assignedTo: task.assignedTo,
      assignedToName: task.assignedToName,
      // Whoever assigns it hears when the student changes its status.
      assignedBy: task.assignedBy ?? currentUser?.id,
      category: task.category,
      checklistItems: task.checklistItems,
      isArchived: task.isArchived,
      academicYear: task.academicYear ?? academicYear,
      completedAt: task.status == 'Completed'
          ? (task.completedAt ?? _formattedToday())
          : null,
    );
    final previousTasks = tasks;
    tasks = [task, ...tasks];
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTask(task);
    } catch (error) {
      debugPrint('Failed to save task: $error');
      tasks = previousTasks;
      notifyListeners();
      return false;
    }

    final recipientId = _assigneeAccountId(task);
    if (recipientId != null) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_$recipientId',
          userId: recipientId,
          title: 'New Task Assigned',
          message: 'You have been assigned "${task.title}".',
          type: 'task',
          createdAt: _formattedToday(),
        ),
      );
      notifyListeners();
    }
    return true;
  }

  /// The account a task's student is notified at. assignedTo is a roster
  /// id; older roster entries keep the student's account id in userId
  /// instead, and notifications go by account.
  String? _assigneeAccountId(Task task) {
    if (task.assignedTo == null) return null;
    final rosterEntry = students
        .where((s) => s.id == task.assignedTo)
        .firstOrNull;
    return (rosterEntry?.userId ?? '').isNotEmpty
        ? rosterEntry!.userId!
        : task.assignedTo!;
  }

  /// Changes a task's status. Shown straight away, then saved; a save the
  /// Firestore rules or the connection refuse is undone here and reported
  /// as false, and only a saved change notifies whoever assigned the task.
  ///
  /// Marking a task Completed sends it to the supervisor for approval. An
  /// approved task is on the student's DTR and can no longer change.
  Future<bool> updateTaskStatus(String id, String status) async {
    final existingTask = tasks.firstWhere(
      (task) => task.id == id,
      orElse: () => Task(
        id: '',
        title: '',
        description: '',
        status: 'Not Started',
        priority: 'Low',
        dueDate: '',
      ),
    );
    if (existingTask.id.isEmpty ||
        existingTask.isArchived ||
        existingTask.isApproved) {
      return false;
    }
    final previousTasks = tasks;
    final becameCompleted = status == 'Completed';
    tasks = tasks.map((t) {
      if (t.id != id) return t;
      // Stamp (or clear) the completion date so the DTR/Accomplishment
      // Report screen can, once the task is approved, turn "task completed
      // today" into that day's accomplishment entry. Re-completing a task
      // that's already marked Completed keeps its original date rather
      // than overwriting it.
      // A duty log keeps the day it was made for.
      final completedAt = becameCompleted
          ? (t.isDutyLog
                ? (t.workDate ?? t.completedAt ?? _formattedToday())
                : (t.completedAt ?? _formattedToday()))
          : null;
      if (becameCompleted) {
        // Waiting for the supervisor again; an earlier rejection's note
        // no longer applies.
        return t.copyWith(
          status: status,
          completedAt: completedAt,
          resetReview: true,
          reviewStatus: 'Pending',
        );
      }
      // Taken back before approval, the task no longer waits for one. A
      // rejection's note stays until the student completes it again.
      return t.copyWith(
        status: status,
        clearCompletedAt: true,
        resetReview: !t.wasRejected,
      );
    }).toList();
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTask(tasks.firstWhere((t) => t.id == id));
    } catch (error) {
      debugPrint('Failed to save task status: $error');
      tasks = previousTasks;
      notifyListeners();
      return false;
    }

    if (existingTask.status != status) {
      // Tasks created before assignedBy was recorded go to the supervisors
      // of the student's office instead.
      final assignee = existingTask.assignedTo;
      final recipientIds = existingTask.assignedBy != null
          ? {existingTask.assignedBy!}
          : {
              for (final office in offices)
                if (office.isActive &&
                    assignee != null &&
                    office.assistantIds.contains(assignee))
                  ...office.headIds,
            };
      for (final recipientId in recipientIds) {
        if (recipientId == currentUser?.id) continue;
        _addNotification(
          AppNotification(
            id: 'n_${DateTime.now().microsecondsSinceEpoch}_$recipientId',
            userId: recipientId,
            title: becameCompleted ? 'Task Awaiting Approval' : 'Task Updated',
            message: becameCompleted
                ? '${existingTask.assignedToName ?? "A student"} marked '
                      '"${existingTask.title}" as Completed. Approve or '
                      'reject it on the Tasks screen.'
                : '${existingTask.assignedToName ?? "A student"} marked "${existingTask.title}" as $status.',
            type: 'task',
            createdAt: _formattedToday(),
          ),
        );
      }
      notifyListeners();
    }
    return true;
  }

  /// The supervisor's verdict on a task the student marked Completed.
  /// Approving it puts it on the student's DTR, on the day it was
  /// completed, and lets the student put it in a report. Rejecting it
  /// sends it back to In Progress with [note] for the student. Shown
  /// straight away, then saved; a refused save is undone here and reported
  /// as false, and only a saved verdict notifies the student.
  Future<bool> reviewTask(
    String id, {
    required bool approve,
    String? note,
  }) async {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index < 0) return false;
    final task = tasks[index];
    if (task.isArchived || !task.awaitingApproval) return false;
    final reason = note?.trim() ?? '';
    final updated = approve
        ? task.copyWith(
            resetReview: true,
            reviewStatus: 'Approved',
            reviewedAt: _formattedToday(),
            reviewedBy: currentUser?.id,
          )
        : task.copyWith(
            status: 'In Progress',
            clearCompletedAt: true,
            resetReview: true,
            reviewStatus: 'Rejected',
            reviewedAt: _formattedToday(),
            reviewedBy: currentUser?.id,
            reviewNote: reason.isEmpty ? null : reason,
          );
    final previousTasks = tasks;
    tasks = [...tasks]..[index] = updated;
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTask(updated);
    } catch (error) {
      debugPrint('Failed to save task review: $error');
      tasks = previousTasks;
      notifyListeners();
      return false;
    }

    final recipientId = _assigneeAccountId(task);
    if (recipientId != null && recipientId != currentUser?.id) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().microsecondsSinceEpoch}_$recipientId',
          userId: recipientId,
          title: approve ? 'Task Approved' : 'Task Rejected',
          message: approve
              ? 'Your supervisor approved "${task.title}". It is now on '
                    'your DTR and can go into your next report.'
              : 'Your supervisor did not approve "${task.title}" and moved '
                    'it back to In Progress.'
                    '${reason.isEmpty ? '' : ' Reason: $reason'}',
          type: 'task',
          createdAt: _formattedToday(),
        ),
      );
      notifyListeners();
    }
    return true;
  }

  /// The approved tasks the signed-in student can still put in a report,
  /// most recently completed first. A task already in one of their reports
  /// is left out, unless the supervisor rejected that report. Reports sent
  /// before reports recorded their tasks are matched by the "• Title" lines
  /// the report form wrote into their content.
  List<Task> get reportableTasks {
    final standing = filteredReports.where((r) => r.status != 'Rejected');
    final usedIds = {for (final r in standing) ...r.taskIds};
    final usedTitles = <String>{};
    for (final report in standing.where((r) => r.taskIds.isEmpty)) {
      for (final rawLine in report.content.split('\n')) {
        final line = rawLine.trim();
        if (!line.startsWith('•')) continue;
        final title = line.substring(1).trim().split(' — ').first.trim();
        if (title.isNotEmpty) usedTitles.add(title.toLowerCase());
      }
    }
    final list = filteredTasks
        .where(
          (t) =>
              t.isApproved &&
              !t.isArchived &&
              !usedIds.contains(t.id) &&
              // A duty log has its own id, and shares its title with every
              // other day's, so an old report's "• Title" line can't stand
              // for it.
              (t.isDutyLog ||
                  !usedTitles.contains(t.title.trim().toLowerCase())),
        )
        .toList();
    final epoch = DateTime(1970);
    list.sort(
      (a, b) => (_parsePayrollDate(b.completedAt) ?? epoch).compareTo(
        _parsePayrollDate(a.completedAt) ?? epoch,
      ),
    );
    return list;
  }

  /// Deletes a task. Returns whether it was deleted; a refused delete is
  /// undone here, so the task doesn't vanish only to come back on reload.
  Future<bool> deleteTask(String id) async {
    final previousTasks = tasks;
    tasks = tasks.where((t) => t.id != id).toList();
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.deleteTask(id);
      return true;
    } catch (error) {
      debugPrint('Failed to delete task: $error');
      tasks = previousTasks;
      notifyListeners();
      return false;
    }
  }

  /// Archives or restores a task. Returns whether it saved; a refused save
  /// is undone here.
  Future<bool> setTaskArchived(String id, bool isArchived) async {
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) return false;
    final updated = tasks[index].copyWith(isArchived: isArchived);
    final previousTasks = tasks;
    tasks = [...tasks]..[index] = updated;
    notifyListeners();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTask(updated);
      return true;
    } catch (error) {
      debugPrint('Failed to archive task: $error');
      tasks = previousTasks;
      notifyListeners();
      return false;
    }
  }

  // ─── Reports CRUD ──────────────────────────────────
  Future<bool> submitReport(Report report) async {
    _firestoreService ??= FirestoreService();
    try {
      await _firestoreService!.setReport(report);
      reports = [report, ...reports];
      User? assistant;
      try {
        assistant = users.firstWhere((user) {
          final sameId = user.id == currentUser?.id;
          final sameName =
              user.name.trim().toLowerCase() ==
              report.studentName.trim().toLowerCase();
          return user.role == 'Student Assistant' && (sameId || sameName);
        });
      } catch (_) {}
      final assistantId = assistant?.id ?? currentUser?.id;
      final assistantName = assistant?.name ?? report.studentName;
      final supervisorIds = offices
          .where(
            (office) =>
                office.isActive &&
                office.hasAssistant(assistantId ?? '', assistantName),
          )
          .expand((office) => office.headIds)
          .toSet();
      for (final supervisorId in supervisorIds) {
        _addNotification(
          AppNotification(
            id: 'n_${DateTime.now().microsecondsSinceEpoch}_report_$supervisorId',
            userId: supervisorId,
            title: 'New Report Submitted',
            message: '$assistantName submitted a report: ${report.title}.',
            type: 'report',
            createdAt: _formattedToday(),
          ),
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to submit report to Firestore: $e');
      return false;
    }
  }

  Future<bool> updateReportStatus(
    String id,
    String status, {
    String? feedback,
  }) async {
    final idx = reports.indexWhere((r) => r.id == id);
    if (idx < 0) return false;
    final old = reports[idx];
    final updated = Report(
      id: old.id,
      applicantId: old.applicantId,
      title: old.title,
      content: old.content,
      studentName: old.studentName,
      status: status,
      submittedAt: old.submittedAt,
      feedback: feedback ?? old.feedback,
      attachments: old.attachments,
      academicYear: old.academicYear,
      sentToHead: old.sentToHead,
      sentToHeadAt: old.sentToHeadAt,
      headAttachments: old.headAttachments,
      taskIds: old.taskIds,
    );

    _firestoreService ??= FirestoreService();
    try {
      await _firestoreService!.setReport(updated);
      reports = reports.map((r) => r.id == id ? updated : r).toList();
      if (old.applicantId != null &&
          (status == 'Approved' || status == 'Rejected')) {
        _addNotification(
          AppNotification(
            id: 'n_${DateTime.now().millisecondsSinceEpoch}_${old.applicantId}',
            userId: old.applicantId!,
            title: 'Report $status',
            message:
                'Your report "${old.title}" was $status.${feedback != null ? " Feedback: $feedback" : ""}',
            type: 'report',
            createdAt: _formattedToday(),
          ),
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to update report status in Firestore: $e');
      return false;
    }
  }

  /// Records an item a Supervisor forwarded to the Head, so it shows up on
  /// the Head's dedicated "Sent to Head" screen (grouped by student)
  /// instead of the general notification feed.
  Future<void> _recordHeadForward({
    required String type,
    required String studentId,
    required String studentName,
    required String title,
    required String fileName,
    String? downloadUrl,
    String? storagePath,
  }) async {
    _firestoreService ??= FirestoreService();
    final forwardId = await _firestoreService!.addHeadForward(
      HeadForward(
        id: '',
        type: type,
        studentId: studentId,
        studentName: studentName,
        title: title,
        fileName: fileName,
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        sentByName: currentUser?.name ?? 'Supervisor',
        sentById: currentUser?.id,
        sentAt: _formattedToday(),
      ),
    );
    headForwards = _withAdded(
      headForwards,
      HeadForward(
        id: forwardId,
        type: type,
        studentId: studentId,
        studentName: studentName,
        title: title,
        fileName: fileName,
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        sentByName: currentUser?.name ?? 'Supervisor',
        sentById: currentUser?.id,
        sentAt: _formattedToday(),
      ),
      (f) => f.id,
    );
    for (final head in users.where((u) => u.role == 'Head')) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${head.id}',
          userId: head.id,
          title: 'New Item Forwarded',
          message:
              '${currentUser?.name ?? "A supervisor"} sent "$title" for $studentName.',
          type: 'head_forward',
          createdAt: _formattedToday(),
        ),
      );
    }
  }

  /// Head marks a forwarded item as reviewed/unreviewed on the "Sent to
  /// Head" screen.
  Future<void> setHeadForwardReviewed(String id, bool reviewed) async {
    _firestoreService ??= FirestoreService();
    try {
      await _firestoreService!.setHeadForwardReviewed(id, reviewed);
      headForwards = headForwards
          .map((f) => f.id == id ? f.copyWith(reviewed: reviewed) : f)
          .toList();
      if (reviewed) {
        final forward = headForwards.where((f) => f.id == id).firstOrNull;
        if (forward != null && forward.sentById != null) {
          _addNotification(
            AppNotification(
              id: 'n_${DateTime.now().millisecondsSinceEpoch}_${forward.sentById}',
              userId: forward.sentById!,
              title: 'Item Reviewed',
              message:
                  'The Head reviewed "${forward.title}" for ${forward.studentName}.',
              type: 'head_forward',
              createdAt: _formattedToday(),
            ),
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update head forward: $e');
    }
  }

  /// Supervisor forwards an already-approved report to the Head. The
  /// report's own attachments (uploaded when it was submitted) travel with
  /// it — nothing needs to be re-uploaded here.
  Future<bool> sendReportToHead(String id) async {
    final idx = reports.indexWhere((r) => r.id == id);
    if (idx < 0) return false;
    final old = reports[idx];
    if (old.status != 'Approved') return false;

    final updated = Report(
      id: old.id,
      applicantId: old.applicantId,
      title: old.title,
      content: old.content,
      studentName: old.studentName,
      status: old.status,
      submittedAt: old.submittedAt,
      feedback: old.feedback,
      attachments: old.attachments,
      academicYear: old.academicYear,
      sentToHead: true,
      sentToHeadAt: _formattedToday(),
      headAttachments: old.attachments,
      taskIds: old.taskIds,
    );

    _firestoreService ??= FirestoreService();
    try {
      await _firestoreService!.setReport(updated);
      reports = reports.map((r) => r.id == id ? updated : r).toList();

      final firstAttachment = updated.attachments.isNotEmpty
          ? updated.attachments.first
          : null;
      await _recordHeadForward(
        type: 'report',
        studentId: updated.applicantId ?? '',
        studentName: updated.studentName,
        title: updated.title,
        fileName: firstAttachment?.fileName ?? '${updated.title}.txt',
        downloadUrl: firstAttachment?.downloadUrl,
        storagePath: firstAttachment?.storagePath,
      );

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to send report to Head in Firestore: $e');
      rethrow;
    }
  }

  /// Regenerates the already-submitted performance evaluation document (the
  /// same file the "Download" button produces) and forwards it to the Head
  /// — no manual re-upload needed.
  Future<bool> sendEvaluationToHead(Evaluation evaluation) async {
    if (evaluation.status != 'Submitted') return false;
    _firestoreService ??= FirestoreService();
    try {
      final doc = await const PerformanceEvaluationDocumentService()
          .generatePerformanceEvaluation(evaluation: evaluation);
      final bytes = doc.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to generate the evaluation document.');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Reuses the 'reports/<uploaderUid>/...' path shape that the
      // upload-document edge function already allows (it only accepts
      // 'reports' and 'applications' as valid roots), keyed by the
      // supervisor's own Firebase UID as the storage rules require.
      final uploaderUid =
          fb_auth.FirebaseAuth.instance.currentUser?.uid ??
          currentUser?.id ??
          'user';
      final storagePath = 'reports/$uploaderUid/$timestamp/${doc.fileName}';
      final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
        bytes: bytes,
        path: storagePath,
        contentType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );

      final updated = evaluation.copyWith(
        sentToHead: true,
        sentToHeadAt: _formattedToday(),
      );
      final withAttachment = Evaluation(
        id: updated.id,
        studentId: updated.studentId,
        studentName: updated.studentName,
        office: updated.office,
        term: updated.term,
        periodCovered: updated.periodCovered,
        dateOfRating: updated.dateOfRating,
        eligibleForRehire: updated.eligibleForRehire,
        ratings: updated.ratings,
        overallRating: updated.overallRating,
        departmentHeadComments: updated.departmentHeadComments,
        supervisorId: updated.supervisorId,
        supervisorName: updated.supervisorName,
        verifiedDtrHours: updated.verifiedDtrHours,
        approvedReportCount: updated.approvedReportCount,
        status: updated.status,
        academicYear: updated.academicYear,
        createdAt: updated.createdAt,
        updatedAt: updated.updatedAt,
        sentToHead: true,
        sentToHeadAt: updated.sentToHeadAt,
        headAttachmentName: doc.fileName,
        headAttachmentPath: storagePath,
        headAttachmentUrl: downloadUrl,
      );

      await _firestoreService!.setEvaluation(withAttachment);
      evaluations = evaluations
          .map((e) => e.id == withAttachment.id ? withAttachment : e)
          .toList();

      await _recordHeadForward(
        type: 'evaluation',
        studentId: withAttachment.studentId,
        studentName: withAttachment.studentName,
        title: 'Performance Evaluation (${withAttachment.term})',
        fileName: doc.fileName,
        downloadUrl: downloadUrl,
        storagePath: storagePath,
      );

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to send evaluation to Head: $e');
      rethrow;
    }
  }

  /// Uploads an already-generated DTR/Accomplishment report (the same bytes
  /// the "Generate Report" button produces) and forwards it to the Head.
  Future<bool> sendDtrReportToHead({
    required String studentId,
    required String studentName,
    required String monthLabel,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Reuses the 'reports/<uploaderUid>/...' path shape that the
      // upload-document edge function already allows (it only accepts
      // 'reports' and 'applications' as valid roots), keyed by the
      // supervisor's own Firebase UID as the storage rules require.
      final uploaderUid =
          fb_auth.FirebaseAuth.instance.currentUser?.uid ??
          currentUser?.id ??
          'user';
      final storagePath = 'reports/$uploaderUid/$timestamp/$fileName';
      final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
        bytes: bytes,
        path: storagePath,
        contentType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );

      await _recordHeadForward(
        type: 'dtr_report',
        studentId: studentId,
        studentName: studentName,
        title: 'DTR/Accomplishment Report ($monthLabel)',
        fileName: fileName,
        downloadUrl: downloadUrl,
        storagePath: storagePath,
      );

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to send DTR report to Head: $e');
      rethrow;
    }
  }

  // ─── Profile Update ────────────────────────────────
  Future<void> updateProfile({
    PersonName? nameParts,
    String? phone,
    String? address,
    String? avatar,
    List<String>? skills,
    String? yearLevel,
  }) async {
    if (currentUser != null) {
      currentUser = currentUser!.copyWith(
        nameParts: nameParts,
        phone: phone,
        address: address,
        avatar: avatar,
        skills: skills,
        yearLevel: yearLevel,
      );

      users = users.map((user) {
        if (user.id == currentUser!.id ||
            user.email.toLowerCase() == currentUser!.email.toLowerCase()) {
          return currentUser!;
        }
        return user;
      }).toList();
      if (!users.any(
        (user) =>
            user.id == currentUser!.id ||
            user.email.toLowerCase() == currentUser!.email.toLowerCase(),
      )) {
        users = [...users, currentUser!];
      }

      await _saveUserProfile(currentUser!);
      notifyListeners();
    }
  }

  Future<void> updateUserAvatar(String userId, String? avatar) async {
    users = users.map((user) {
      if (user.id == userId) {
        return user.copyWith(avatar: avatar);
      }
      return user;
    }).toList();

    if (currentUser?.id == userId) {
      currentUser = currentUser!.copyWith(avatar: avatar);
      await _saveUserProfile(currentUser!);
    }

    notifyListeners();
  }

  // ─── Accounts ──────────────────────────────────────
  Future<void> updateAcademicYearSettings({
    required String year,
    required String semester,
    required DateTime startDate,
    required DateTime endDate,
    required bool allowApplications,
    required bool enforceHourCap,
    required bool autoArchiveLogs,
    required List<Map<String, dynamic>> milestones,
  }) async {
    _firestoreService ??= FirestoreService();
    // The year this puts on the archive list, if any.
    String? closedYear;
    if (academicYear != year) {
      final currentSettings = await _firestoreService!
          .getAcademicYearSettings();
      if (currentSettings != null && currentSettings['academicYear'] != null) {
        // Only record the year as finished. Its records are copied into the
        // archive by the Head's session (see _archiveFinishedAcademicYears),
        // since the Admin can't read them all.
        final finishedYear = currentSettings['academicYear'].toString();
        // The finished year's own "Auto-archive Logs" setting, which the
        // app treats as on when it was never saved.
        final archiveAttendance =
            currentSettings['autoArchiveLogs'] as bool? ?? true;
        final headcount = studentsPerCampus;
        final listed = await _firestoreService!.archiveAcademicYearSettings(
          finishedYear,
          currentSettings,
          archiveAttendance: archiveAttendance,
          headcountByCampus: headcount,
        );
        // Already listed when its end date passed first, and the Heads were
        // told then.
        if (listed) {
          closedYear = finishedYear;
          // Newest first, like getAcademicYearArchives.
          academicYearArchives =
              [
                ...academicYearArchives.where(
                  (archive) => archive['academicYear'] != finishedYear,
                ),
                {
                  ...currentSettings,
                  'academicYear': finishedYear,
                  'archivedAt': DateTime.now(),
                  'archiveAttendance': archiveAttendance,
                  'dataArchived': false,
                  'headcountByCampus': headcount,
                },
              ]..sort(
                (a, b) => b['academicYear'].toString().compareTo(
                  a['academicYear'].toString(),
                ),
              );
        }
      }
    }
    final termChanged = academicYear != year || academicSemester != semester;
    final settings = <String, dynamic>{
      'academicYear': year,
      'semester': semester,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'allowApplications': allowApplications,
      'enforceHourCap': enforceHourCap,
      'autoArchiveLogs': autoArchiveLogs,
      'milestones': milestones,
      'updatedAt': FieldValue.serverTimestamp(),
      // What undoTermChange goes back to. Saving other settings keeps the
      // term change undoable.
      if (termChanged) ...{
        'previous': {
          'academicYear': academicYear,
          'semester': academicSemester,
          'startDate': academicYearStart.toIso8601String(),
          'endDate': academicYearEnd.toIso8601String(),
          // A new year drops the old year's milestones; undoing brings
          // them back.
          'milestones': academicMilestones,
        },
        'termChangedAt': DateTime.now().toUtc().toIso8601String(),
      } else if (_previousAcademicTerm != null && _termChangedAt != null) ...{
        'previous': _previousAcademicTerm,
        'termChangedAt': _termChangedAt!.toUtc().toIso8601String(),
      },
      // Until the Head's session has moved its records back — and dropped
      // once that year is legitimately reached.
      if (_undoneAcademicYear != null && _undoneAcademicYear != year)
        'undoneAcademicYear': _undoneAcademicYear,
    };
    await _firestoreService!.saveAcademicYearSettings(settings);
    _applyAcademicSettings(settings);
    notifyListeners();
    if (closedYear != null) {
      final due =
          termChangeUndoDeadline ?? DateTime.now().add(archivePreviewWindow);
      await _notifyHeadsAboutArchive(
        closedYear,
        title: 'Academic Year Closing',
        message:
            'The Admin started AY $year. AY $closedYear\'s records will be '
            'archived after ${monthDayTime(due)}. Before then, preview what '
            'will be saved and finish anything still open.',
      );
    }
  }

  /// Undoes the last academic year or semester change, within
  /// [termChangeUndoWindow]: the year, semester and dates go back to what
  /// they were (with the old year's milestones, when the year changed), and
  /// a year that change marked as finished comes off the archive list
  /// again. Other settings stay as they are. Records made in
  /// the meantime carry the undone year, so the Head's session moves them
  /// back (see [_restampUndoneAcademicYear]).
  Future<void> undoTermChange() async {
    _firestoreService ??= FirestoreService();
    // Fresh, in case another Admin session changed the settings meanwhile.
    final current = await _firestoreService!.getAcademicYearSettings();
    if (current == null) throw StateError('No academic year settings saved.');
    _applyAcademicSettings(current);
    final previous = _previousAcademicTerm;
    if (!canUndoTermChange || previous == null) {
      notifyListeners();
      throw StateError('The last term change can no longer be undone.');
    }
    final previousYear = previous['academicYear'].toString();
    final undoneYear = academicYear;
    if (previousYear != undoneYear) {
      await _firestoreService!.deleteUnprocessedAcademicYearArchive(
        previousYear,
      );
    }
    final restored = <String, dynamic>{
      ...current,
      'academicYear': previousYear,
      'semester': previous['semester'],
      'startDate': previous['startDate'],
      'endDate': previous['endDate'],
      'updatedAt': FieldValue.serverTimestamp(),
      if (previousYear != undoneYear) ...{
        'undoneAcademicYear': undoneYear,
        if (previous['milestones'] is List)
          'milestones': previous['milestones'],
      },
    }..removeWhere((key, _) => key == 'previous' || key == 'termChangedAt');
    await _firestoreService!.saveAcademicYearSettings(restored);
    _applyAcademicSettings(restored);
    try {
      academicYearArchives = await _firestoreService!.getAcademicYearArchives();
    } catch (_) {}
    notifyListeners();
    if (previousYear != undoneYear) {
      await _notifyHeadsAboutArchive(
        previousYear,
        title: 'Academic Year Switch Undone',
        message:
            'The Admin moved back to AY $previousYear, so its records won\'t '
            'be archived for now.',
      );
    }
  }

  Future<String?> createManagedUser(User user, String password) async {
    await _ensureSeeded();
    if (users.any((u) => u.email.toLowerCase() == user.email.toLowerCase())) {
      return 'An account with this email already exists.';
    }
    final idKey = studentIdKey(user.studentId);
    if ((user.studentId ?? '').trim().isNotEmpty && idKey == null) {
      return 'Please enter a valid Student ID.';
    }
    if (idKey != null && users.any((u) => studentIdKey(u.studentId) == idKey)) {
      return 'This Student ID is already registered to another account.';
    }

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'admin-account-${DateTime.now().microsecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final credential = await fb_auth.FirebaseAuth.instanceFor(
        app: secondaryApp,
      ).createUserWithEmailAndPassword(email: user.email, password: password);
      final authUser = credential.user!;
      final createdUser = user.copyWith(id: authUser.uid);
      try {
        await _saveUserProfile(createdUser);
      } catch (_) {
        // Without a profile the login is useless, and it would block
        // creating the account again ("email already exists"), so undo it.
        try {
          await authUser.delete();
        } catch (_) {}
        rethrow;
      }
      if (idKey != null) {
        try {
          await _firestoreService!.claimStudentId(idKey, createdUser.id);
        } catch (error) {
          // The Admin's next roster update reserves it (see
          // _syncStudentIdClaims), so the account itself still stands.
          debugPrint('Failed to reserve Student ID: $error');
        }
      }
      // Login requires a verified email, and nothing else would send the
      // new user a link.
      try {
        await _sendVerificationEmail(authUser);
      } catch (error) {
        debugPrint('Failed to send verification email: $error');
      }
      await _upsertUser(createdUser);
      notifyListeners();
      return null;
    } on fb_auth.FirebaseAuthException catch (e) {
      return e.message ?? 'Unable to create account.';
    } catch (e) {
      return 'Unable to create account: $e';
    } finally {
      await secondaryApp?.delete();
    }
  }

  Future<void> updateManagedUser(User user) async {
    await _upsertUser(user);
    await _saveUserProfile(user);
    notifyListeners();
  }

  Future<void> addUser(User user) async {
    await _upsertUser(user);
    await _saveUserProfile(user);
    notifyListeners();
  }

  /// Deletes an account as far as the app can. The sign-in itself can only
  /// be removed from the Firebase console, so the profile stays behind,
  /// archived and marked deleted: that blocks sign-in ("deactivated")
  /// wherever it's checked, where a missing profile would let the person
  /// back in as a brand-new Student. Deleted accounts are hidden everywhere.
  ///
  /// Only the profile is written, which is all the rules let an Admin do:
  /// the roster records and office places of a deleted account are cleared
  /// by the Head's session ([_cleanUpDeletedAccounts]). Returns whether it
  /// saved; deleting an account twice is harmless.
  Future<bool> deleteManagedUser(String id) async {
    final user = users.where((u) => u.id == id).firstOrNull;
    if (user == null) return true;
    _firestoreService ??= FirestoreService();
    try {
      await _firestoreService!.updateUserFields(id, {
        'status': 'Archived',
        'deleted': true,
      });
    } catch (error) {
      debugPrint('Failed to delete account $id: $error');
      return false;
    }

    // A Head may remove the roster records now; an Admin's delete leaves
    // them to the Head's session.
    if (role == 'Head') await _removeStudentRecordsOf(user);
    users = users.where((u) => u.id != id).toList();
    _deletedAccounts = [..._deletedAccounts, user];
    notifyListeners();
    return true;
  }

  Future<bool> deleteUser(String id) => deleteManagedUser(id);

  bool _cleaningDeletedAccounts = false;

  /// Set while [submitApplication] saves, so a second tap does nothing.
  bool _submittingApplication = false;

  /// Clears the roster records and office places of accounts the Admin
  /// deleted. The Admin's delete can only write the profile (the rules keep
  /// the roster and the offices to the Head), so the Head's session finishes
  /// it, whenever the roster, the students or the offices change. Safe to
  /// run again: it does nothing once they're clear.
  Future<void> _cleanUpDeletedAccounts() async {
    if (role != 'Head' || _deletedAccounts.isEmpty || _cleaningDeletedAccounts) {
      return;
    }
    // Wait for the lists it works on.
    if (offices.isEmpty && students.isEmpty) return;
    _cleaningDeletedAccounts = true;
    try {
      _firestoreService ??= FirestoreService();
      for (final gone in _deletedAccounts) {
        if (_studentRecordsForUser(gone).isNotEmpty) {
          await _removeStudentRecordsOf(gone);
        }
      }
      final touched = {
        for (final office in offices)
          if (_deletedAccounts.any(
            (gone) =>
                office.hasAssistant(gone.id, gone.name) ||
                office.hasHead(gone.id, gone.name),
          ))
            office.id,
      };
      if (touched.isEmpty) return;
      final deleted = [..._deletedAccounts];
      final saved = await _firestoreService!.updateOffices(touched, (stored) {
        final changed = <String, Office>{};
        for (final entry in stored.entries) {
          var office = entry.value;
          for (final gone in deleted) {
            if (office.hasAssistant(gone.id, gone.name)) {
              office = office.withoutAssistant(gone.id, gone.name);
            }
            if (office.hasHead(gone.id, gone.name)) {
              office = office.withoutHead(gone.id, gone.name);
            }
          }
          if (_peopleDiffer(office, entry.value)) changed[entry.key] = office;
        }
        return changed;
      });
      if (saved != null && saved.isNotEmpty) await _showSavedOffices(saved);
    } catch (error) {
      debugPrint('Failed to clean up deleted accounts: $error');
    } finally {
      _cleaningDeletedAccounts = false;
    }
  }

  /// Deletes the students records of [user], which only a Head may do. A
  /// failure leaves them for [_cleanUpDeletedAccounts].
  Future<void> _removeStudentRecordsOf(User user) async {
    final records = _studentRecordsForUser(user);
    try {
      for (final record in records) {
        if (record.id.isNotEmpty) {
          await _firestoreService!.deleteStudent(record.id);
        }
      }
      students = [
        for (final s in students)
          if (!records.contains(s)) s,
      ];
    } catch (error) {
      debugPrint('Failed to remove the student records of ${user.id}: $error');
    }
  }

  Future<bool> archiveUser(String id) async {
    final user = users.where((u) => u.id == id).firstOrNull;
    return user != null && await _setAccountStatus(user, 'Archived');
  }

  Future<bool> restoreUser(String id) async {
    final user = users.where((u) => u.id == id).firstOrNull;
    return user != null && await _setAccountStatus(user, 'Active');
  }

  /// Changes [id]'s role. The role is saved first, on its own field, and
  /// shown only once it's saved. A promotion to Student Assistant also
  /// needs a students record: a Head writes it in the same batch (the rules
  /// don't let an Admin, whose promotions are listed from the account).
  ///
  /// [notify] is off when the change comes from a flow that sends its own,
  /// more specific notification (such as a rehire decision).
  ///
  /// Returns null when it's done, or what went wrong. A message about the
  /// student record means the role itself did change.
  Future<String?> changeUserRole(
    String id,
    String newRole, {
    bool notify = true,
  }) async {
    final user = users.where((u) => u.id == id).firstOrNull;
    if (user == null) return null;
    final oldRole = user.role;
    final promoted = newRole == 'Student Assistant';
    final roleChanges = oldRole != newRole;
    // Already in the role: nothing to save for it. A Head still makes sure a
    // Student Assistant has an active students record, which is how a
    // promotion cut short is finished by saving the approval again.
    if (!roleChanges && !(promoted && role == 'Head')) return null;
    _firestoreService ??= FirestoreService();
    final service = _firestoreService!;

    final updatedUser = user.copyWith(role: newRole);
    // A new students record, written with the role (Head only).
    Student? newRecord;
    if (promoted && role == 'Head' && _studentRecordsForUser(user).isEmpty) {
      newRecord = Student(
        id: user.id,
        name: user.name,
        email: user.email,
        department:
            user.department ?? (departments.isNotEmpty ? departments.first : ''),
        campus: user.campus,
        userId: user.id,
        totalHours: 0,
      );
    }
    try {
      if (roleChanges && newRecord != null) {
        await service.updateUserFieldsWithStudent(id, {
          'role': newRole,
        }, newRecord);
      } else if (roleChanges) {
        await service.updateUserFields(id, {'role': newRole});
      } else if (newRecord != null) {
        await service.setStudent(newRecord);
      }
    } catch (error) {
      debugPrint('Failed to change the role of $id: $error');
      return "Couldn't change ${user.name}'s role. Please try again.";
    }

    // Saved: now it shows. Their notifications, applications, tasks and
    // reports stay with them; if it's the signed-in user, the role follows.
    if (roleChanges) {
      users = [for (final u in users) u.id == id ? updatedUser : u];
      if (currentUser?.id == id) {
        currentUser = currentUser!.copyWith(role: newRole);
      }
    }
    if (newRecord != null) students = [newRecord, ...students];

    String? problem;
    if (promoted && newRecord == null && role == 'Head') {
      try {
        // A returning Student Assistant (not rehired in an earlier term)
        // still has their old, archived record — bring it back rather
        // than leave them off every roster.
        await _setStudentRecordsStatus(updatedUser, 'Active');
      } catch (error) {
        debugPrint('Failed to bring back the student record of $id: $error');
        problem =
            "${user.name} is now a Student Assistant, but their student "
            "record couldn't be brought back. Save the change again to retry.";
      }
    }
    // Notify the user that their role was changed
    if (notify && roleChanges) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_role_change_$id',
          userId: id,
          title: 'Role Updated',
          message: 'Your role has been changed from "$oldRole" to "$newRole".',
          type: 'system',
          createdAt: _formattedToday(),
        ),
      );
    }

    notifyListeners();
    return problem;
  }

  /// The students-collection records that belong to [user].
  List<Student> _studentRecordsForUser(User user) {
    final email = user.email.trim().toLowerCase();
    return students
        .where(
          (s) =>
              s.id == user.id ||
              s.userId == user.id ||
              (email.isNotEmpty && s.email.trim().toLowerCase() == email),
        )
        .toList();
  }

  Future<void> _setStudentRecordsStatus(User user, String status) async {
    _firestoreService ??= FirestoreService();
    for (final record in _studentRecordsForUser(user)) {
      if (record.status == status) continue;
      final updated = record.copyWith(status: status);
      await _firestoreService!.setStudent(updated);
      students = students.map((s) => s.id == record.id ? updated : s).toList();
    }
  }

  // ─── Document Management ───────────────────────────
  void addDocument(Document document) {
    documents.add(document);
    notifyListeners();
  }

  void removeDocument(String documentId) {
    documents.removeWhere((d) => d.id == documentId);
    notifyListeners();
  }

  // ─── Filtered Data ─────────────────────────────────
  Set<String> _assistantIdsForSupervisor() {
    final supervisor = currentUser;
    if (supervisor == null) return {};
    return offices
        .where(
          (office) =>
              office.isActive &&
              (office.headIds.contains(supervisor.id) ||
                  office.headNames.any(
                    (name) =>
                        name.trim().toLowerCase() ==
                        supervisor.name.trim().toLowerCase(),
                  )),
        )
        .expand((office) => office.assistantIds)
        .toSet();
  }

  List<Office> get _supervisedOffices => offices.where((office) {
    final supervisor = currentUser;
    if (supervisor == null || !office.isActive) return false;
    return office.hasHead(supervisor.id, supervisor.name);
  }).toList();

  Set<String> _officeAssistantNamesForSupervisor() => _supervisedOffices
      .expand((office) => office.assistantNames)
      .map((name) => name.trim().toLowerCase())
      .toSet();

  Set<String> _studentIdentityIdsForSupervisor() {
    final officeAssistantIds = _assistantIdsForSupervisor();
    final ids = {...officeAssistantIds};
    for (final student in effectiveStudents) {
      if (officeAssistantIds.contains(student.id) ||
          (student.userId != null &&
              officeAssistantIds.contains(student.userId))) {
        ids.add(student.id);
        if (student.userId != null) ids.add(student.userId!);
      }
    }
    return ids;
  }

  bool _studentBelongsToCurrentOffice(Student student) {
    final assistantIds = _assistantIdsForSupervisor();
    final assistantNames = _officeAssistantNamesForSupervisor();
    return assistantIds.contains(student.id) ||
        (student.userId != null && assistantIds.contains(student.userId)) ||
        assistantNames.contains(student.name.trim().toLowerCase());
  }

  bool _attendanceBelongsToStudent(AttendanceRecord record, Student student) {
    final studentId = student.userId ?? student.id;
    return record.studentId == student.id ||
        record.studentId == studentId ||
        record.studentName == student.name;
  }

  List<Student> get _officeStudentsForSupervisor =>
      effectiveStudents.where(_studentBelongsToCurrentOffice).toList();

  List<String> get _officeStudentNamesForSupervisor => {
    ..._officeStudentsForSupervisor.map((student) => student.name),
    ..._supervisedOffices.expand((office) => office.assistantNames),
  }.where((name) => name.trim().isNotEmpty).toList();

  List<Office> get currentUserOffices {
    final user = currentUser;
    if (user == null) return const [];
    return officesForUser(user);
  }

  /// The active offices [user] works in or supervises.
  List<Office> officesForUser(User user) => offices
      .where(
        (office) =>
            office.isActive &&
            (office.hasAssistant(user.id, user.name) ||
                office.hasHead(user.id, user.name)),
      )
      .toList();

  List<Student> get effectiveStudents {
    double hoursFor(Set<String> ids, Set<String> names) {
      final normalizedNames = names
          .where((name) => name.trim().isNotEmpty)
          .map((name) => name.trim().toLowerCase())
          .toSet();
      // By id; only records saved without one fall back to the name, since
      // two students can share a name.
      return attendance
          .where(
            (record) =>
                record.countsTowardHours &&
                ((record.studentId ?? '').isNotEmpty
                    ? ids.contains(record.studentId)
                    : normalizedNames.contains(
                        record.studentName.trim().toLowerCase(),
                      )),
          )
          .fold<double>(0, (sum, record) => sum + (record.totalHours ?? 0));
    }

    // An archived account keeps its owner off the roster whatever their
    // record says: they're on [archivedStudents] instead.
    final accountOf = _accountLookup();
    final activeStudents = students
        .where(
          (s) => s.status != 'Archived' && accountOf(s)?.status != 'Archived',
        )
        .map((s) {
          final user = accountOf(s);
          final identityIds = {
            s.id,
            if (s.userId != null) s.userId!,
            if (user != null) user.id,
          };
          final hours = hoursFor(identityIds, {
            s.name,
            if (user != null) user.name,
          });
          return s.copyWith(
            name: user?.name,
            email: user?.email,
            department: s.department.isNotEmpty
                ? s.department
                : user?.department,
            campus: s.campus ?? user?.campus,
            totalHours: hours > 0 ? hours : s.totalHours,
            phone: s.phone ?? user?.phone,
            address: s.address ?? user?.address,
            avatar: s.avatar ?? user?.avatar,
            userId: s.userId ?? user?.id,
          );
        })
        .toList();

    final existingStudentIds = {
      for (final s in activeStudents) s.userId ?? s.id,
    };
    // Archived students stay off the roster — they're on [archivedStudents]
    // — rather than coming back below as active.
    final archivedRecords = _archivedStudentRecords();
    final archivedIds = {
      for (final s in archivedRecords) ...[s.id, ?s.userId],
    };

    final fallback = users
        .where((u) => u.role == 'Student Assistant' && u.status != 'Archived')
        .where((u) {
          final key = u.id;
          return !existingStudentIds.contains(key) &&
              !archivedIds.contains(key);
        })
        .map((u) {
          return Student(
            id: u.id,
            name: u.name,
            email: u.email,
            department:
                u.department ??
                (departments.isNotEmpty ? departments.first : ''),
            campus: u.campus,
            status: u.status,
            totalHours: hoursFor({u.id}, {u.name}),
            phone: u.phone,
            address: u.address,
            avatar: u.avatar,
            userId: u.id,
          );
        })
        .toList();

    final combined = [...activeStudents, ...fallback];
    // Archived students count as known, so an office that still lists one
    // doesn't bring them back below.
    final knownNames = {
      for (final student in [...combined, ...archivedRecords])
        student.name.trim().toLowerCase(),
    };
    for (final office in _supervisedOffices) {
      for (var index = 0; index < office.assistantIds.length; index++) {
        final assistantId = office.assistantIds[index];
        final assistantName = index < office.assistantNames.length
            ? office.assistantNames[index]
            : assistantId;
        if (knownNames.contains(assistantName.trim().toLowerCase())) continue;
        final linkedUser = users.cast<User?>().firstWhere(
          (user) =>
              user?.id == assistantId ||
              user?.name.trim().toLowerCase() ==
                  assistantName.trim().toLowerCase(),
          orElse: () => null,
        );
        if (linkedUser?.status == 'Archived') continue;
        combined.add(
          Student(
            id: assistantId,
            name: linkedUser?.name ?? assistantName,
            email: linkedUser?.email ?? '',
            department: linkedUser?.department ?? '',
            campus: linkedUser?.campus,
            status: linkedUser?.status ?? 'Active',
            totalHours: hoursFor(
              {assistantId, if (linkedUser != null) linkedUser.id},
              {assistantName, if (linkedUser != null) linkedUser.name},
            ),
            userId: linkedUser?.id ?? assistantId,
          ),
        );
        knownNames.add(assistantName.trim().toLowerCase());
      }
      for (final assistantName in office.assistantNames) {
        if (knownNames.contains(assistantName.trim().toLowerCase())) continue;
        final linkedUser = users.cast<User?>().firstWhere(
          (user) =>
              user?.name.trim().toLowerCase() ==
              assistantName.trim().toLowerCase(),
          orElse: () => null,
        );
        if (linkedUser?.status == 'Archived') continue;
        combined.add(
          Student(
            id: linkedUser?.id ?? assistantName,
            name: linkedUser?.name ?? assistantName,
            email: linkedUser?.email ?? '',
            department: linkedUser?.department ?? '',
            campus: linkedUser?.campus,
            status: linkedUser?.status ?? 'Active',
            totalHours: hoursFor(
              {if (linkedUser != null) linkedUser.id, assistantName},
              {assistantName, if (linkedUser != null) linkedUser.name},
            ),
            userId: linkedUser?.id ?? assistantName,
          ),
        );
        knownNames.add(assistantName.trim().toLowerCase());
      }
    }
    return combined;
  }

  List<Student> get filteredStudents {
    final base = effectiveStudents;
    if (role == 'Head') return base.toList();
    if (role == 'Supervisor')
      return base.where(_studentBelongsToCurrentOffice).toList();
    return base.where((s) => s.userId == currentUser?.id).toList();
  }

  /// The day an attendance record is for ("Oct 5, 2026" as saved), or null
  /// when it can't be read.
  DateTime? attendanceDay(AttendanceRecord record) =>
      _parsePayrollDate(record.date);

  /// Each current Student Assistant's attendance from [from] to [to]
  /// (whole days, both included; null for no limit), for the Head's
  /// summary. Archived records count in no total, as everywhere; they're
  /// listed only with [includeArchived], to be restored. A record belongs
  /// to the account or students record its studentId names; one saved
  /// without an id goes by the name. "Today" is Philippine time, as the
  /// attendance server keeps it.
  List<AssistantAttendance> assistantAttendance({
    DateTime? from,
    DateTime? to,
    bool includeArchived = false,
    DateTime? now,
  }) {
    final clock = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    final today = '${_monthNames[clock.month - 1]} ${clock.day}, ${clock.year}';
    final first = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    final last = to == null ? null : DateTime(to.year, to.month, to.day);
    bool inPeriod(AttendanceRecord record) {
      if (first == null && last == null) return true;
      final day = attendanceDay(record);
      if (day == null) return false;
      return (first == null || !day.isBefore(first)) &&
          (last == null || !day.isAfter(last));
    }

    final rows = <AssistantAttendance>[];
    for (final user in users) {
      if (user.role != 'Student Assistant' || user.status == 'Archived') {
        continue;
      }
      final studentRecords = _studentRecordsForUser(user);
      final ids = {
        user.id,
        for (final s in studentRecords) ...[s.id, ?s.userId],
      };
      final names = {
        user.name.trim().toLowerCase(),
        for (final s in studentRecords) s.name.trim().toLowerCase(),
      }..remove('');
      final mine = attendance.where(
        (record) =>
            (includeArchived || !record.isArchived) &&
            ((record.studentId ?? '').isNotEmpty
                ? ids.contains(record.studentId)
                : names.contains(record.studentName.trim().toLowerCase())),
      );
      final records = mine.where(inPeriod).toList()
        ..sort((a, b) {
          final byDay = (attendanceDay(b) ?? DateTime(0)).compareTo(
            attendanceDay(a) ?? DateTime(0),
          );
          return byDay != 0 ? byDay : b.timeIn.compareTo(a.timeIn);
        });
      rows.add(
        AssistantAttendance(
          assistant: user,
          offices: [
            for (final office in offices)
              if (office.isActive && office.hasAssistant(user.id, user.name))
                office,
          ],
          records: records,
          clockedIn: mine.any(
            (record) =>
                !record.isArchived &&
                record.isActive &&
                !record.isInvalid &&
                record.date == today,
          ),
          verifiedDays: {
            for (final record in records)
              if (record.countsTowardHours)
                attendanceDay(record)?.toIso8601String() ?? record.date,
          }.length,
        ),
      );
    }
    rows.sort(
      (a, b) => a.assistant.name.toLowerCase().compareTo(
        b.assistant.name.toLowerCase(),
      ),
    );
    return rows;
  }

  List<AttendanceRecord> get filteredAttendance {
    if (role == 'Head') return attendance;
    if (role == 'Student Assistant') {
      // Match on the account id first and fall back to the name. Records
      // written server-side carry studentId, so matching on the display
      // name alone would hide them the moment a name is edited or differs
      // by so much as whitespace.
      final myId = currentUser?.id;
      final myName = currentUser?.name;
      return attendance
          .where(
            (a) =>
                (myId != null && a.studentId == myId) ||
                (myName != null && a.studentName == myName),
          )
          .toList();
    }
    if (role == 'Supervisor') {
      return attendance
          .where(
            (record) => _officeStudentsForSupervisor.any(
              (student) => _attendanceBelongsToStudent(record, student),
            ),
          )
          .toList();
    }
    return attendance;
  }

  List<Task> get filteredTasks {
    if (role == 'Head') return tasks;
    if (role == 'Supervisor') {
      final assistantIds = _studentIdentityIdsForSupervisor();
      return tasks
          .where(
            (task) =>
                (task.assignedTo != null &&
                    assistantIds.contains(task.assignedTo)) ||
                (task.assignedToName != null &&
                    _officeStudentNamesForSupervisor.contains(
                      task.assignedToName,
                    )),
          )
          .toList();
    }
    if (role == 'Student Assistant') {
      final myId = currentUser?.id;
      final myName = currentUser?.name;
      return tasks
          .where(
            (t) =>
                (t.assignedTo != null && t.assignedTo == myId) ||
                (t.assignedToName != null && t.assignedToName == myName),
          )
          .toList();
    }
    return tasks.where((task) => task.assignedTo == currentUser?.id).toList();
  }

  List<Report> get filteredReports {
    if (role == 'Admin') return reports;
    if (role == 'Student Assistant') {
      final myId = currentUser?.id;
      return reports
          .where(
            (report) =>
                (myId != null && report.applicantId == myId) ||
                report.studentName == currentUser?.name,
          )
          .toList();
    }
    if (role == 'Supervisor') {
      final studentNames = _officeStudentNamesForSupervisor.toSet();
      final studentIds = _studentIdentityIdsForSupervisor();
      return reports
          .where(
            (report) =>
                studentNames.contains(report.studentName) ||
                (report.applicantId != null &&
                    studentIds.contains(report.applicantId)),
          )
          .toList();
    }
    return reports
        .where((report) => report.studentName == currentUser?.name)
        .toList();
  }

  List<Evaluation> get filteredEvaluations {
    if (role == 'Admin') return evaluations;
    if (role == 'Student Assistant') {
      return evaluations
          .where((e) => e.studentName == currentUser?.name)
          .toList();
    }
    if (role == 'Supervisor') {
      final studentNames = _officeStudentNamesForSupervisor.toSet();
      return evaluations
          .where((e) => studentNames.contains(e.studentName))
          .toList();
    }
    return const [];
  }

  /// Total verified DTR hours for a student: the sum of completed
  /// (timed-out) attendance records, scoped the same way as
  /// [filteredAttendance] so a supervisor only sees their own office's data.
  double verifiedDtrHoursForStudent(Student student) {
    return filteredAttendance
        .where(
          (a) =>
              a.countsTowardHours &&
              isRecordOfStudent(student, a.studentId, a.studentName),
        )
        .fold<double>(0, (sum, a) => sum + (a.totalHours ?? 0));
  }

  /// Accomplishment reports already approved by the supervisor for a
  /// student, scoped the same way as [filteredReports].
  List<Report> approvedReportsForStudent(Student student) {
    return filteredReports
        .where(
          (r) =>
              r.status == 'Approved' &&
              isRecordOfStudent(student, r.applicantId, r.studentName),
        )
        .toList();
  }

  /// Whether a record saved under [recordId] / [recordName] is [student]'s.
  ///
  /// Records carry the student's account (or roster) id, and that decides
  /// it: two students can share a name, and matching by name would hand one
  /// the other's hours. Only a record saved without an id — or a roster
  /// entry not yet linked to an account — falls back to the name.
  bool isRecordOfStudent(Student student, String? recordId, String recordName) {
    if (recordId != null && recordId.isNotEmpty) {
      if (recordId == student.id || recordId == student.userId) return true;
      if ((student.userId ?? '').isNotEmpty) return false;
    }
    return recordName.trim().toLowerCase() == student.name.trim().toLowerCase();
  }

  // ─── Payroll ───────────────────────────────────────────
  // Parses the handful of date-string shapes this codebase already writes
  // ("Sep 19, 2026" from attendance, "9/19/2026" from reports) so payroll
  // can filter both by an arbitrary pay period.

  static const _fullMonthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static bool _isContractFile(ApplicationDocument doc) =>
      doc.requirementName == 'Contract of Appointment' ||
      doc.fileName.toLowerCase().contains('contract-of-appointment');

  static bool _isEndorsementFile(ApplicationDocument doc) =>
      doc.requirementName == 'Endorsement Letter' ||
      doc.fileName.toLowerCase().contains('endorsement-letter');

  /// The students holding up a period's payroll: anyone in [preview] —
  /// the whole period, not a filtered part of it — still 'Incomplete'.
  /// The payroll is approved for everyone at once, so until this is empty
  /// it can't be approved at all.
  static List<PayrollRecord> payrollHeldBy(List<PayrollRecord> preview) =>
      preview.where((p) => p.status == 'Incomplete').toList();

  // ─── Payroll requirements (Head) ───────────────────────
  // The Head checks each Student Assistant's requirements; the Admin's
  // payroll waits until every one is checked (see buildPayrollPreview).

  // ─── Rehiring ──────────────────────────────────────

  static const _evaluationTermOrder = {
    'First Semester': 0,
    'Second Semester': 1,
    'Midyear Term': 2,
  };

  // ─── Clock-out reminder ────────────────────────────
  /// How long before a session ends a Student Assistant still clocked in
  /// is reminded to clock out.
  static const clockOutReminderLead = Duration(minutes: 30);

  /// Reminders sent while the app is open, for the shell to show on screen
  /// as well as in the notifications list.
  final _clockOutReminderAlerts = StreamController<AppNotification>.broadcast();
  Stream<AppNotification> get clockOutReminderAlerts =>
      _clockOutReminderAlerts.stream;

  /// Reminders this session has already handled, so one the student deleted
  /// isn't sent again on the next attendance update.
  final _clockOutRemindersHandled = <String>{};

  /// The reminder's notification id: one per attendance record, so a reload,
  /// a second tab or another device can't send it twice. (The rules refuse
  /// rewriting a saved notification, so a second save of it fails.)
  static String clockOutReminderId(String recordId) => 'clockout_$recordId';

  // ─── Push notifications ────────────────────────────
  // Every notification is also pushed to the recipient's registered
  // browsers, reaching a phone with SAIS closed: the clockout-reminders
  // function sends the clock-out reminder on a schedule, and every other
  // notification as soon as it's saved (_queuePush).
  final PushService _push;
  StreamSubscription<Map<String, dynamic>>? _pushMessagesSub;

  /// The token saved for this browser. Deleted at sign-out, so the next
  /// person on this browser doesn't get this account's reminders.
  String? _pushToken;

  /// Whether this browser may show SAIS's notifications; null until a
  /// Student Assistant's sign-in has checked.
  PushPermission? pushPermission;

  /// Whether pushed notifications reach this browser.
  bool get pushOn => _pushToken != null;

  /// Set while [registerForPush] runs.
  bool pushBusy = false;

  /// Seconds the test notification waits, so there's time to lock the
  /// phone or switch apps and see it arrive like a real reminder.
  static const pushTestDelaySeconds = 10;
}
