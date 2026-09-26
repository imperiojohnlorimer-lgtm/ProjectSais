import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:projectsais/services/appointment_document_service.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/services/performance_evaluation_document_service.dart';
import 'package:projectsais/services/supabase_storage_service.dart';
import '../firebase_options.dart';
import 'models.dart';

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

class AppState extends ChangeNotifier {
  /// [firestoreService] is for tests; the app lets it default.
  AppState({FirestoreService? firestoreService})
    : _firestoreService = firestoreService;

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
  Timer? _missedTimeOutTimer;
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
  Future<String?> generateAttendanceQrToken() async {
    final now = DateTime.now();
    final sessionKey = attendanceQrSessionKey(now);
    if (sessionKey == null) return null;

    // Already holding this session's token locally.
    if (currentQrToken != null && currentQrSessionKey == sessionKey) {
      return currentQrToken;
    }

    _firestoreService ??= FirestoreService();

    // Another device may have already created this session's token.
    try {
      final doc = await _firestoreService!.getCurrentQrToken();
      final token = doc?['token'] as String?;
      if (token != null && _sessionKeyOfQrDoc(doc!) == sessionKey) {
        currentQrToken = token;
        currentQrSessionKey = sessionKey;
        qrGeneratedAt = _generatedAtOfQrDoc(doc) ?? now;
        notifyListeners();
        return token;
      }
    } catch (_) {
      // Firestore unavailable — fall through and mint a local token.
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
    final token = 'SAIS-ATT-$sessionKey-$secret';
    currentQrToken = token;
    currentQrSessionKey = sessionKey;
    qrGeneratedAt = now;
    notifyListeners();

    // Persist so other devices validate against the same session token.
    try {
      await _firestoreService!.setCurrentQrToken(token, sessionKey);
    } catch (_) {
      // Firestore unavailable — continue with the in-memory token.
    }

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
  List<PayrollSheet> payrollSheets = [];
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

  // ─── Auth ──────────────────────────────────────────
  bool get isAuthenticated => currentUser != null;
  String get role => currentUser?.role ?? 'Student Assistant';

  Future<void> init() async {
    await _initializeFirebaseAuthUser();
    await _ensureSeeded();
    await _loadNotificationsForCurrentUser();
    _startRealtimeListeners();
  }

  /// (Re)starts the Firestore listeners. Called on app start and again after
  /// login: the rules require a signed-in user, so listeners started before
  /// sign-in fail with permission-denied and would otherwise stay dead
  /// (leaving lists like announcements empty) until the app is restarted.
  void _startRealtimeListeners() {
    // Start listening to Firestore announcements (if available).
    try {
      _firestoreService ??= FirestoreService();
      _annSub?.cancel();
      _annSub = _firestoreService!.announcementsStream().listen(
        (list) {
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
        },
      );
      // Start listening to attendance collection in real-time so supervisors
      // and admins see updates immediately without refreshing.
      _attSub?.cancel();
      final isStaffUser = role == 'Head' || role == 'Supervisor';
      final seesAllAttendance = isStaffUser || role == 'Admin';
      _attSub =
          (seesAllAttendance
                  ? _firestoreService!.attendanceStream()
                  : _firestoreService!.attendanceStreamForStudent(
                      currentUser!.id,
                    ))
              .listen(
                (list) {
                  attendance = list
                      .map((m) => AttendanceRecord.fromJson(m))
                      .toList();
                  notifyListeners();
                  if (isStaffUser) invalidateMissedTimeOuts();
                },
                // Without this a rejected query (a missing index, say) kills
                // the subscription silently and the list just stays empty.
                onError: (Object error) {
                  debugPrint('Attendance stream error: $error');
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
        _taskSub = _firestoreService!.tasksStream().listen((list) {
          tasks = list.map((m) => Task.fromJson(m)).toList();
          notifyListeners();
        });
      }

      _appSub?.cancel();
      _appSub =
          (isStaffUser
                  ? _firestoreService!.applicationsStream()
                  : _firestoreService!.applicationsStreamForApplicant(
                      currentUser!.id,
                    ))
              .listen((list) {
                applications = list
                    .map((m) => Application.fromJson(m))
                    .toList();
                notifyListeners();
              });

      // Head/Supervisor: keep "Sent to Head" items in sync in real time so
      // a forward shows up immediately even if the Head's screen was
      // already open, or they logged in before it was sent.
      _headForwardsSub?.cancel();
      if (isStaffUser) {
        _headForwardsSub = _firestoreService!.headForwardsStream().listen((
          list,
        ) {
          headForwards = list.map((m) => HeadForward.fromJson(m)).toList();
          notifyListeners();
        });
      }

      // Admin: keep processed Payroll records in sync in real time.
      _payrollSub?.cancel();
      _payrollSheetsSub?.cancel();
      if (role == 'Admin') {
        _payrollSub = _firestoreService!.payrollRecordsStream().listen((list) {
          payrollRecords = list.map((m) => PayrollRecord.fromJson(m)).toList();
          notifyListeners();
        });
        _payrollSheetsSub = _firestoreService!.payrollSheetsStream().listen((
          list,
        ) {
          payrollSheets = list.map((m) => PayrollSheet.fromJson(m)).toList();
          notifyListeners();
        });
      }
    } catch (_) {
      // Firestore not available or not initialized; ignore and keep in-memory behavior.
    }
    try {
      _startLiveData();
    } catch (error) {
      debugPrint('Live data unavailable: $error');
    }
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
    for (final sub in _liveSubs) {
      sub.cancel();
    }
    _liveSubs.clear();
    _liveGeneration++;
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
      _liveSubs.add(
        stream.listen(
          (data) {
            try {
              onData(data);
            } catch (error) {
              debugPrint('$label update failed: $error');
            }
            notifyListeners();
          },
          // Without this a rejected query dies silently and the list just
          // stops updating.
          onError: (Object error) => debugPrint('$label stream error: $error'),
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
        final previousTerm = '$academicYear|$academicSemester';
        _applyAcademicSettings(data);
        // A new term is what puts pending rehire decisions into effect.
        if (isHead && previousTerm != '$academicYear|$academicSemester') {
          _applyDueRehireDecisions().then((_) => notifyListeners());
        }
      },
    );
    listen(
      'Offices',
      fs.collectionStream('offices'),
      (list) => offices = list.map(Office.fromJson).toList(),
    );
    listen('Departments', fs.collectionStream('departments'), (list) {
      final named =
          list
              .where((d) => (d['name']?.toString() ?? '').isNotEmpty)
              .toList()
            ..sort(
              (a, b) => a['name'].toString().compareTo(b['name'].toString()),
            );
      departments = [for (final d in named) d['name'].toString()];
      departmentCodes = {
        for (final d in named) d['name'].toString(): d['code']?.toString() ?? '',
      };
    });
    listen('Programs', fs.collectionStream('programs'), (list) {
      programs = _sortedPrograms(list.map(Program.fromJson));
    });
    listen('Skills', fs.collectionStream('skills'), (list) {
      skills = [
        for (final s in list)
          if ((s['name']?.toString() ?? '').isNotEmpty) s['name'].toString(),
      ]..sort();
    });

    // ── Staff and Admin: the full roster ──
    if (isStaff || isAdmin) {
      listen('Users', fs.collectionStream('users'), (list) {
        _setUsers(list.map(User.fromJson).toList());
      });
      listen('Students', fs.collectionStream('students'), (list) {
        students = list.map(Student.fromJson).toList();
        // Refill any department/campus the profiles take from students.
        _setUsers(users);
      });
      listen(
        'Reports',
        fs.collectionStream('reports'),
        (list) => reports = list.map(Report.fromJson).toList(),
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
        (list) => documentFolders = list.map(DocumentFolder.fromJson).toList(),
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
        'Own reports',
        fs.whereStream('reports', 'applicantId', user.id),
      );
      listenReports(
        'Named reports',
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

      listenTasks('Own tasks', fs.whereStream('tasks', 'assignedTo', user.id));
      listenTasks(
        'Named tasks',
        fs.whereStream('tasks', 'assignedToName', user.name),
      );
      fs
          .getStudentIdsForUser(user.id)
          .then((ids) {
            if (ids.isEmpty || generation != _liveGeneration) return;
            listenTasks(
              'Student-record tasks',
              fs.whereInStream('tasks', 'assignedTo', ids.take(10).toList()),
            );
          })
          .catchError((Object error) {
            debugPrint('Student-record tasks lookup failed: $error');
          });

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
      _loadAllFromFirestore().then((_) {
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
    _annSub?.cancel();
    _attSub?.cancel();
    _taskSub?.cancel();
    _appSub?.cancel();
    _headForwardsSub?.cancel();
    _payrollSub?.cancel();
    _payrollSheetsSub?.cancel();
    _missedTimeOutTimer?.cancel();
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

  /// Load the latest user profile from Firestore by ID (public method)
  Future<User?> getFreshUserProfile(String userId) async {
    return await _loadUserProfile(uid: userId);
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
    final firebaseUser = fb_auth.FirebaseAuth.instance.currentUser;
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

  Future<String?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final lowerEmail = email.toLowerCase();

    try {
      final credential = await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final authUser = credential.user;
      if (authUser == null) {
        return 'Unable to log in. Please try again.';
      }

      if (!authUser.emailVerified) {
        // Send a fresh link: the first one may have expired or been lost,
        // and accounts made by the Admin before links were sent never got
        // one at all.
        var sent = true;
        try {
          await authUser.sendEmailVerification();
        } catch (error) {
          // Usually Firebase's limit on how often links can be sent.
          sent = false;
          debugPrint('Failed to send verification email: $error');
        }
        await fb_auth.FirebaseAuth.instance.signOut();
        return sent
            ? 'Please verify your email address before logging in. A new verification link was sent.'
            : 'Please verify your email address before logging in, using the link we sent earlier.';
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
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-email') {
        return e.message ?? 'Login failed: ${e.code}';
      }
      return e.message ?? 'Login failed: ${e.code}';
    } catch (error) {
      return 'Login failed: $error';
    }
  }

  Future<String?> signInWithGoogle() async {
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
        return e.message ?? 'Google login failed: ${e.code}';
      }
    } catch (error) {
      return 'Google login failed: $error';
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

    await _ensureSeeded();

    // Make sure this Student ID isn't already claimed by another account.
    final studentId = user.studentId?.trim() ?? '';
    if (studentId.isNotEmpty) {
      try {
        _firestoreService ??= FirestoreService();
        final existingByStudentId = await _firestoreService!
            .getUserProfileByStudentId(studentId);
        if (existingByStudentId != null &&
            existingByStudentId.email.toLowerCase() != normalizedEmail) {
          return 'This Student ID is already registered to another account.';
        }
      } catch (error) {
        debugPrint('Failed to check Student ID uniqueness: $error');
      }
    }

    // Create the email/password account directly — no Google sign-in popup
    // during registration. Instead, Firebase sends a verification email to
    // the Gmail address the user provided. The user can link their Google
    // account later from the Profile section if they want to.
    try {
      final credential = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: user.email,
            password: password,
          );
      final authUser = credential.user;
      if (authUser == null) {
        return 'Unable to create account. Please try again.';
      }

      await authUser.sendEmailVerification();
      final registeredUser = user.copyWith(id: authUser.uid);
      await _saveUserProfile(registeredUser);

      // Don't fully log the user in yet — they still need to verify their
      // Gmail address. Sign them out of the Firebase session so the login
      // screen's existing "please verify your Gmail" check takes over the
      // next time they try to sign in.
      await fb_auth.FirebaseAuth.instance.signOut();

      return null;
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use')
        return 'An account with this email already exists.';
      if (e.code == 'weak-password') return 'Password is too weak.';
      return e.message ?? 'Registration failed: ${e.code}';
    } catch (error) {
      return 'Registration failed: $error';
    }
  }

  Future<void> signOut() async {
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
    notifyListeners();
  }

  // ─── Navigation ────────────────────────────────────
  void setTab(String tab) {
    activeTab = tab;
    notifyListeners();
  }

  Future<void> _loadAllFromFirestore() async {
    _firestoreService ??= FirestoreService();
    try {
      // Users: prefer Firestore as source-of-truth, but keep currentUser if not present.
      List<User> firestoreUsers = [];
      try {
        firestoreUsers = await _firestoreService!.getAllUserProfiles();
      } catch (error) {
        debugPrint('Failed to load user profiles: $error');
      }

      Map<String, dynamic>? academicSettings;
      try {
        academicSettings = await _firestoreService!.getAcademicYearSettings();
      } catch (error) {
        debugPrint('Failed to load academic settings: $error');
      }
      if (academicSettings != null) _applyAcademicSettings(academicSettings);
      try {
        academicYearArchives = await _firestoreService!
            .getAcademicYearArchives();
      } catch (_) {
        academicYearArchives = [];
      }
      try {
        offices = await _firestoreService!.getAllOffices();
      } catch (_) {
        offices = [];
      }
      try {
        final storedDepartments = await _firestoreService!.getAllDepartments();
        departments = storedDepartments;
        departmentCodes = await _firestoreService!.getDepartmentCodes();
      } catch (_) {}
      try {
        programs = _sortedPrograms(await _firestoreService!.getAllPrograms());
      } catch (_) {}
      try {
        skills = await _firestoreService!.getAllSkills();
      } catch (_) {}
      try {
        screeningRecords = _dedupeScreeningRecords(
          await _firestoreService!.getAllScreeningRecords(),
        );
      } catch (_) {}

      // Students
      try {
        final fsStudents = await _firestoreService!.getAllStudents();
        students = fsStudents;
      } catch (_) {
        students = [];
      }

      _setUsers(firestoreUsers);

      // Attendance
      try {
        final rawAttendance =
            (role == 'Head' || role == 'Supervisor' || role == 'Admin')
            ? await _firestoreService!.getAllAttendance()
            : await _firestoreService!.getAttendanceForStudent(currentUser!.id);
        attendance = rawAttendance
            .map((m) => AttendanceRecord.fromJson(m))
            .toList();
      } catch (_) {
        attendance = [];
      }

      // Class Schedules (weekly, used to auto-fill DTR/Accomplishment
      // Report's Class Schedule grid)
      try {
        classSchedules = (role == 'Head' || role == 'Supervisor')
            ? await _firestoreService!.getAllClassSchedules()
            : await _firestoreService!.getClassSchedulesForStudent(
                currentUser!.id,
              );
      } catch (_) {
        classSchedules = [];
      }
      await _archiveFinishedAcademicYears(academicSettings);

      // Tasks
      try {
        final fsTasks = <Task>[];
        if (role == 'Head' || role == 'Supervisor') {
          fsTasks.addAll(await _firestoreService!.getAllTasks());
        } else {
          try {
            fsTasks.addAll(
              await _firestoreService!.getTasksForUser(currentUser!.id),
            );
          } catch (_) {}
          try {
            final studentIds = await _firestoreService!.getStudentIdsForUser(
              currentUser!.id,
            );
            fsTasks.addAll(
              await _firestoreService!.getTasksForAssigneeIds(studentIds),
            );
          } catch (_) {}
          // No lookup by name: the Firestore rules only share a task with
          // the account it is assigned to, since anyone can register under
          // a classmate's name.
        }
        final taskById = <String, Task>{
          for (final task in fsTasks) task.id: task,
        };
        tasks = taskById.values.toList();
      } catch (_) {
        tasks = [];
      }

      // Reports
      try {
        final fsReports =
            (role == 'Head' || role == 'Supervisor' || role == 'Admin')
            ? await _firestoreService!.getAllReports()
            // By account only, never by name — see Tasks above.
            : await _firestoreService!.getReportsForApplicant(
                currentUser!.id,
              );
        reports = fsReports;
      } catch (_) {
        reports = [];
      }

      // Performance Evaluations
      try {
        final fsEvaluations = await _firestoreService!.getAllEvaluations();
        evaluations = fsEvaluations;
      } catch (_) {
        evaluations = [];
      }

      // Rehire decisions. Any whose term has started since they were made
      // are put into effect now — only a Head may change the roster records
      // involved, so this runs in the Head's session.
      if (role == 'Head') {
        try {
          rehireRecords = await _firestoreService!.getAllRehireRecords();
          await _applyDueRehireDecisions();
        } catch (_) {
          rehireRecords = [];
        }
        await _syncOfficeAssignments();
        await _moveSchedulesToAccounts(firestoreUsers);
      }

      // Items supervisors have forwarded to the Head.
      if (role == 'Head' || role == 'Supervisor') {
        try {
          headForwards = await _firestoreService!.getAllHeadForwards();
        } catch (_) {
          headForwards = [];
        }
      }

      // Applications
      try {
        final fsApps = await _firestoreService!.getAllApplications();
        applications = fsApps;
        await _syncApprovedApplicationSkills();
      } catch (_) {
        applications = [];
      }
      // Documents
      try {
        final fsDocs = await _firestoreService!.getAllDocuments();
        documents = fsDocs;
      } catch (_) {
        documents = [];
      }
      // Document Folders
      try {
        documentFolders = await _firestoreService!.getAllDocumentFolders();
      } catch (_) {
        documentFolders = [];
      }

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
  void _setUsers(List<User> firestoreUsers) {
    String? pick(String? existing, String? other) =>
        existing != null && existing.isNotEmpty ? existing : other;

    final byEmail = <String, User>{};
    for (final u in firestoreUsers) {
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
  /// Head's session — once per year.
  Future<void> _archiveFinishedAcademicYears(
    Map<String, dynamic>? settings,
  ) async {
    if (role != 'Head') return;
    try {
      _firestoreService ??= FirestoreService();
      if (settings != null && academicYearEnd.isBefore(DateTime.now())) {
        await _firestoreService!.archiveAcademicYearSettings(
          academicYear,
          settings,
          archiveAttendance: autoArchiveAttendanceLogs,
        );
      }
      final archives = await _firestoreService!.getAcademicYearArchives();
      for (final archive in archives) {
        if (archive['dataArchived'] != false) continue;
        final year = archive['id'].toString();
        await _firestoreService!.archiveReportsForAcademicYear(year);
        await _firestoreService!.archiveApplicationsForAcademicYear(year);
        await _firestoreService!.archiveTasksForAcademicYear(year);
        await _firestoreService!.archiveAnnouncementsForAcademicYear(year);
        await _firestoreService!.archiveCalendarEventsForAcademicYear(year);
        if (archive['archiveAttendance'] == true) {
          await _firestoreService!.archiveAttendanceForAcademicYear(year);
        }
        await _firestoreService!.markAcademicYearDataArchived(year);
      }
      academicYearArchives = await _firestoreService!.getAcademicYearArchives();
    } catch (error) {
      // Firebase availability errors should not prevent the app from
      // loading; an unfinished year is picked up again next time.
      debugPrint('Failed to archive academic years: $error');
    }
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
      announcements = [created, ...announcements];
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
      'acceptsApplications': a.acceptsApplications,
      'officeId': a.officeId,
      'officeName': a.officeName,
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
        isOpen: false,
        postedById: a.postedById,
        officeId: a.officeId,
        officeName: a.officeName,
        approvalStatus: 'Pending',
      );

      announcements = [pending, ...announcements];

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

  /// Approves a supervisor's pending request, or re-opens a closed
  /// announcement. The change is saved to Firestore before anything else
  /// happens, so the caller can show progress while it saves and report a
  /// failure instead of the approval silently not sticking. Returns whether
  /// it succeeded.
  Future<bool> approveAnnouncement(String id) async {
    final original = announcements.where((a) => a.id == id).firstOrNull;
    if (original == null) return false;

    if (id.isNotEmpty) {
      try {
        _firestoreService ??= FirestoreService();
        await _firestoreService!.updateAnnouncement(id, {
          'approvalStatus': 'Approved',
          'isOpen': true,
        });
      } catch (error) {
        debugPrint('Failed to approve announcement: $error');
        return false;
      }
    }

    final approved = original.copyWith(
      approvalStatus: 'Approved',
      isOpen: true,
    );
    announcements = announcements
        .map((a) => a.id == id ? approved : a)
        .toList();

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

    final postedById = approved.postedById;
    if (postedById != null && postedById.isNotEmpty) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_approved',
          userId: postedById,
          title: 'Announcement Approved',
          message:
              'Your announcement "${approved.title}" was approved and is now live.',
          type: 'announcement',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();
    return true;
  }

  void rejectAnnouncement(String id, {String? reason}) {
    Announcement? rejected;
    announcements = announcements.map((a) {
      if (a.id != id) return a;
      rejected = a.copyWith(
        approvalStatus: 'Rejected',
        isOpen: false,
        rejectionReason: reason,
      );
      return rejected!;
    }).toList();

    if (rejected == null) return;

    if (rejected!.postedById != null && rejected!.postedById!.isNotEmpty) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_rejected',
          userId: rejected!.postedById!,
          title: 'Announcement Rejected',
          message:
              'Your announcement "${rejected!.title}" was not approved.${reason != null && reason.isNotEmpty ? " Reason: $reason" : ""}',
          type: 'announcement',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();

    // Persist rejection to Firestore.
    try {
      if (id.isNotEmpty) {
        _firestoreService ??= FirestoreService();
        _firestoreService!.updateAnnouncement(id, {
          'approvalStatus': 'Rejected',
          'isOpen': false,
          'rejectionReason': reason,
        });
      }
    } catch (_) {}
  }

  void closeAnnouncement(String id) {
    announcements = announcements
        .map((a) => a.id == id ? a.copyWith(isOpen: false) : a)
        .toList();
    notifyListeners();

    try {
      if (id.isNotEmpty) {
        _firestoreService ??= FirestoreService();
        _firestoreService!.updateAnnouncement(id, {'isOpen': false});
      }
    } catch (_) {}
  }

  void deleteAnnouncement(String id) {
    announcements = announcements.where((a) => a.id != id).toList();
    notifyListeners();

    try {
      if (id.isNotEmpty) {
        _firestoreService ??= FirestoreService();
        _firestoreService!.deleteAnnouncement(id);
      }
    } catch (_) {}
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
  void updateStudentDepartment(String studentId, String newDepartment) {
    students = students.map((s) {
      if (s.id == studentId) {
        return s.copyWith(department: newDepartment);
      }
      return s;
    }).toList();
    // Keep the linked user account's department in sync too, if any.
    final student = students.firstWhere(
      (s) => s.id == studentId,
      orElse: () => Student(id: '', name: '', email: '', department: ''),
    );
    if (student.userId != null) {
      users = users.map((u) {
        if (u.id == student.userId) {
          return u.copyWith(department: newDepartment);
        }
        return u;
      }).toList();
    }
    notifyListeners();
  }

  // ─── Departments ───────────────────────────────────
  Future<void> saveOffice(Office office) async {
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setOffice(office);
    final index = offices.indexWhere((item) => item.id == office.id);
    offices = index < 0 ? [...offices, office] : [...offices]
      ..[index] = office;
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

  Future<bool> assignStudentAssistantsToOffice(
    String officeId,
    List<User> assistants,
  ) async {
    final office = offices.firstWhere((item) => item.id == officeId);
    final assignedIds = assistants.map((assistant) => assistant.id).toSet();
    if (office.capacity > 0 && assignedIds.length > office.capacity) {
      return false;
    }
    final assistantNames = {
      for (final assistant in assistants) assistant.id: assistant.name,
    };
    final updatedOffices = offices.map((item) {
      if (item.id == officeId) {
        return item.copyWith(
          assistantIds: assignedIds.toList(),
          assistantNames: assistants
              .map((assistant) => assistant.name)
              .toList(),
        );
      }
      if (assignedIds.any(item.assistantIds.contains)) {
        final remainingIds = item.assistantIds
            .where((id) => !assignedIds.contains(id))
            .toList();
        return item.copyWith(
          assistantIds: remainingIds,
          assistantNames: remainingIds.map((id) {
            final oldIndex = item.assistantIds.indexOf(id);
            return oldIndex >= 0 && oldIndex < item.assistantNames.length
                ? item.assistantNames[oldIndex]
                : assistantNames[id] ?? id;
          }).toList(),
        );
      }
      return item;
    }).toList();

    for (final updatedOffice in updatedOffices) {
      if (updatedOffice.id == officeId ||
          updatedOffice !=
              offices.firstWhere((item) => item.id == updatedOffice.id)) {
        await saveOffice(updatedOffice);
      }
    }

    final assignedOffice = offices.firstWhere((item) => item.id == officeId);
    final assignedNames = assistants
        .map((assistant) => assistant.name)
        .join(', ');

    // Each assigned student only hears about their own assignment, not the
    // whole roster.
    for (final assistant in assistants) {
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
    // Heads see the full roster summary since it's their office.
    _notifyOfficeUsers(
      assignedOffice.headIds,
      title: 'Office Assignment Updated',
      message: assistants.isEmpty
          ? 'Student assistant assignments were updated for ${assignedOffice.name}.'
          : '$assignedNames ${assistants.length == 1 ? 'was' : 'were'} assigned to ${assignedOffice.name}.',
    );
    return true;
  }

  Future<void> assignSupervisorsToOffice(
    String officeId,
    List<User> supervisors,
  ) async {
    final office = offices.firstWhere((item) => item.id == officeId);
    final updatedOffice = office.copyWith(
      headIds: supervisors.map((supervisor) => supervisor.id).toList(),
      headNames: supervisors.map((supervisor) => supervisor.name).toList(),
    );
    await saveOffice(updatedOffice);

    // Each assigned supervisor only hears about their own assignment.
    for (final supervisor in supervisors) {
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
      message: supervisors.isEmpty
          ? 'Supervisors were updated for ${updatedOffice.name}.'
          : '${supervisors.map((supervisor) => supervisor.name).join(', ')} ${supervisors.length == 1 ? 'was' : 'were'} assigned to supervise ${updatedOffice.name}.',
    );
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

  void addTaskCategory(String name) {
    final normalized = name.trim();
    if (normalized.isNotEmpty && !taskCategories.contains(normalized)) {
      taskCategories = [...taskCategories, normalized];
      notifyListeners();
    }
  }

  Future<bool> addSkill(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty || skills.contains(normalized)) return false;
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

  Future<bool> updateSkill(String oldName, String newName) async {
    final normalized = newName.trim();
    if (normalized.isEmpty ||
        (normalized != oldName && skills.contains(normalized))) {
      return false;
    }
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

  // ─── Document Folders (Head file manager) ─────────────
  Future<void> createDocumentFolder(String name) async {
    if (name.trim().isEmpty) return;
    _firestoreService ??= FirestoreService();
    final folder = DocumentFolder(
      id: '',
      name: name.trim(),
      createdBy: currentUser?.name ?? '',
      createdAt: DateTime.now().toIso8601String(),
    );
    final id = await _firestoreService!.addDocumentFolder(folder);
    documentFolders = [
      DocumentFolder(
        id: id,
        name: folder.name,
        createdBy: folder.createdBy,
        createdAt: folder.createdAt,
      ),
      ...documentFolders,
    ];
    notifyListeners();
  }

  Future<void> deleteDocumentFolder(String folderId) async {
    _firestoreService ??= FirestoreService();
    final docsInFolder = documents
        .where((d) => d.folderId == folderId)
        .toList();
    for (final doc in docsInFolder) {
      await _firestoreService!.deleteDocument(doc.id);
    }
    await _firestoreService!.deleteDocumentFolder(folderId);
    documents = documents.where((d) => d.folderId != folderId).toList();
    documentFolders = documentFolders.where((f) => f.id != folderId).toList();
    notifyListeners();
  }

  /// Uploads a document either into a folder ([folderId]) or directly onto
  /// a student's own document list ([studentId]/[studentName]).
  Future<void> uploadManualDocument({
    String? folderId,
    String? studentId,
    String? studentName,
    required String fileName,
    required String storagePath,
    required String downloadUrl,
    double? fileSize,
  }) async {
    _firestoreService ??= FirestoreService();
    final doc = Document(
      id: '',
      name: fileName,
      fileName: fileName,
      uploadedBy: currentUser?.name ?? '',
      uploadedAt: DateTime.now().toIso8601String(),
      documentType: 'Other',
      filePath: storagePath,
      downloadUrl: downloadUrl,
      fileSize: fileSize,
      folderId: folderId,
      studentId: studentId,
      studentName: studentName,
    );
    await _firestoreService!.setDocument(doc);
    documents = await _firestoreService!.getAllDocuments();
    notifyListeners();
  }

  Future<void> deleteManualDocument(String documentId) async {
    _firestoreService ??= FirestoreService();
    await _firestoreService!.deleteDocument(documentId);
    documents = documents.where((d) => d.id != documentId).toList();
    notifyListeners();
  }

  Future<bool> submitApplication(Application app) async {
    // Closed by the Admin's "Open Applications" setting; the Firestore
    // rules refuse it too.
    if (currentUser?.role == 'Student Assistant' ||
        !allowAcademicApplications) {
      return false;
    }
    _firestoreService ??= FirestoreService();
    app = app.copyWith(academicYear: app.academicYear ?? academicYear);
    try {
      await _firestoreService!.setApplication(app);
    } catch (error) {
      debugPrint('Failed to submit application to Firestore: $error');
      return false;
    }

    applications = [app, ...applications];
    // Notify admin users
    final admins = users.where((u) => u.role == 'Head');
    for (final u in admins) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${u.id}',
          userId: u.id,
          title: 'New Application',
          message:
              '${app.applicantName} applied for "${app.announcementTitle}"',
          type: 'application',
          createdAt: _formattedToday(),
        ),
      );
    }
    // Notify the applicant
    _addNotification(
      AppNotification(
        id: 'n_${DateTime.now().millisecondsSinceEpoch}_${app.applicantId}',
        userId: app.applicantId,
        title: 'Application Submitted',
        message:
            'Your application for "${app.announcementTitle}" has been submitted.',
        type: 'application',
        createdAt: _formattedToday(),
      ),
    );
    notifyListeners();
    return true;
  }

  Future<void> updateApplicationStatus(
    String id,
    String status, {
    String? remarks,
  }) async {
    Application? updatedApplication;
    applications = applications.map((a) {
      if (a.id != id) return a;
      final updated = a.copyWith(status: status, remarks: remarks);
      updatedApplication = updated;
      // Notify the applicant
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${a.applicantId}',
          userId: a.applicantId,
          title: 'Application $status',
          message:
              'Your application for "${a.announcementTitle}" was $status.${remarks != null ? " Remarks: $remarks" : ""}',
          type: 'application',
          createdAt: _formattedToday(),
        ),
      );
      return updated;
    }).toList();
    if (updatedApplication != null) {
      _firestoreService ??= FirestoreService();
      if (status == 'Approved' || status == 'Accepted') {
        await generateApprovedApplicantDocuments(updatedApplication!.id);
      }

      await _firestoreService!.setApplication(updatedApplication!);
      if (status == 'Approved' || status == 'Accepted') {
        for (final skill in updatedApplication!.skills) {
          final normalizedSkill = skill.trim();
          if (normalizedSkill.isEmpty ||
              skills.any(
                (existing) =>
                    existing.toLowerCase() == normalizedSkill.toLowerCase(),
              )) {
            continue;
          }
          try {
            await _firestoreService!.setSkill(normalizedSkill);
            skills = [...skills, normalizedSkill]..sort();
          } catch (error) {
            debugPrint('Failed to add approved application skill: $error');
          }
        }
        final applicantIndex = users.indexWhere(
          (user) => user.id == updatedApplication!.applicantId,
        );
        if (applicantIndex >= 0) {
          final applicant = users[applicantIndex];
          final mergedSkills = {
            ...applicant.skills,
            ...updatedApplication!.skills,
          }.toList()..sort();
          final updatedApplicant = applicant.copyWith(skills: mergedSkills);
          await _upsertUser(updatedApplicant);
          if (currentUser?.id == updatedApplicant.id) {
            currentUser = updatedApplicant;
          }
          await _saveUserProfile(updatedApplicant);
          if (applicant.role == 'Student') {
            await changeUserRole(
              updatedApplication!.applicantId,
              'Student Assistant',
            );
          }
          await ensureStudentAssistantId(updatedApplication!.applicantId);
        }
      }
    }
    notifyListeners();
  }

  /// Assigns a unique, sequential Student Assistant Program ID (e.g.
  /// "SA 001") the first time a user needs one, and returns it. Idempotent —
  /// if the user already has one, it's returned unchanged. This is how
  /// every Student Assistant automatically gets an SA ID, without a Head
  /// having to type one in by hand.
  Future<String?> ensureStudentAssistantId(String userId) async {
    final index = users.indexWhere((u) => u.id == userId);
    if (index < 0) return null;
    final existing = users[index].saId;
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final numberPattern = RegExp(r'^SA\s*0*(\d+)$');
    var highest = 0;
    for (final u in users) {
      final match = numberPattern.firstMatch(u.saId?.trim() ?? '');
      if (match == null) continue;
      final n = int.tryParse(match.group(1)!) ?? 0;
      if (n > highest) highest = n;
    }
    final newId = 'SA ${(highest + 1).toString().padLeft(3, '0')}';

    final updated = users[index].copyWith(saId: newId);
    await _upsertUser(updated);
    if (currentUser?.id == updated.id) currentUser = updated;
    await _saveUserProfile(updated);
    notifyListeners();
    return newId;
  }

  Future<void> generateApprovedApplicantDocuments(String applicationId) async {
    await _generateApprovedApplicantDocument(
      applicationId,
      includeContract: true,
      includeEndorsement: true,
    );
  }

  /// Generates only the Contract of Appointment for an approved applicant,
  /// leaving any previously generated Endorsement Letter untouched.
  Future<void> generateContractOfAppointmentDocument(
    String applicationId,
  ) async {
    await _generateApprovedApplicantDocument(
      applicationId,
      includeContract: true,
      includeEndorsement: false,
    );
  }

  /// Generates only the Endorsement Letter for an approved applicant,
  /// leaving any previously generated Contract of Appointment untouched.
  Future<void> generateEndorsementLetterDocument(String applicationId) async {
    await _generateApprovedApplicantDocument(
      applicationId,
      includeContract: false,
      includeEndorsement: true,
    );
  }

  Future<void> _generateApprovedApplicantDocument(
    String applicationId, {
    required bool includeContract,
    required bool includeEndorsement,
  }) async {
    final appIndex = applications.indexWhere((a) => a.id == applicationId);
    if (appIndex < 0) return;

    final app = applications[appIndex];
    if (app.status != 'Approved' && app.status != 'Accepted') return;

    final applicant = users.firstWhere(
      (user) => user.id == app.applicantId,
      orElse: () => User(
        id: app.applicantId,
        name: app.applicantName,
        email: '',
        role: 'Student',
      ),
    );

    // Prefer the applicant's actual assigned Office (as shown on their
    // profile / User Profile dialog) over parsing the announcement title —
    // that title-parsing was only ever a fallback and doesn't reflect the
    // applicant's real office assignment.
    final assignedOffices = officesForUser(applicant);
    final officeName = assignedOffices.isNotEmpty
        ? assignedOffices.map((o) => o.name).join(', ')
        : (app.announcementTitle.contains('-')
              ? app.announcementTitle.split('-').last.trim()
              : 'Student Assistant Office');

    // Immediate Supervisor should be the head of the applicant's assigned
    // office, not whichever admin happens to be generating the document.
    final officeHeadNames = assignedOffices.expand((o) => o.headNames).toList();
    final supervisorName = officeHeadNames.isNotEmpty
        ? officeHeadNames.join(', ')
        : (currentUser?.name ?? 'Office Supervisor');
    final supervisorRole = currentUser?.role ?? 'Supervisor';

    ApplicationDocument? contractDocument;
    ApplicationDocument? endorsementDocument;

    if (includeContract) {
      final rawContractDocument = await const AppointmentDocumentService()
          .generateContractOfAppointment(
            application: app,
            applicant: applicant,
            officeName: officeName,
            supervisorName: supervisorName,
            supervisorRole: supervisorRole,
            startDate: AppointmentDocumentService.formatDate(DateTime.now()),
            endDate: 'End of Academic Term',
          );
      contractDocument = await _uploadGeneratedDocument(rawContractDocument);
    }

    if (includeEndorsement) {
      final rawEndorsementDocument = await const AppointmentDocumentService()
          .generateEndorsementLetter(
            application: app,
            applicant: applicant,
            supervisorName: supervisorName,
            officeName: officeName,
            campusName: applicant.campus ?? 'Main Campus',
            studentId: applicant.studentId,
            courseProgram: applicant.courseProgram,
            yearLevel: applicant.yearLevel,
            contactNumber: applicant.phone,
            // "Endorsed By" is whoever (the Head) is generating this document.
            endorsedByName: currentUser?.name,
            endorsedByContact: currentUser?.phone,
            endorsedByEmail: currentUser?.email,
          );
      endorsementDocument = await _uploadGeneratedDocument(
        rawEndorsementDocument,
      );
    }

    // Upload the generated bytes to Supabase Storage instead of embedding
    // them directly in the Firestore document. A ~500KB docx as a raw
    // Firestore int array blows well past Firestore's 1MB document limit
    // and per-field size limits, which is why the write was silently
    // failing to persist the real fileSize/bytes (showing "0.00 MB" after
    // a refresh) and why downloads fell back to a data: URI — which
    // browsers save under the generic name "download" since data: URIs
    // don't carry a real filename/Content-Disposition.
    final filteredDocuments = app.submittedDocuments
        .where(
          (doc) =>
              (includeContract &&
                      doc.requirementName == 'Contract of Appointment') ==
                  false &&
              (includeEndorsement &&
                      doc.requirementName == 'Endorsement Letter') ==
                  false,
        )
        .toList();

    final generatedDocuments = [
      ...filteredDocuments,
      if (contractDocument != null) contractDocument,
      if (endorsementDocument != null) endorsementDocument,
    ];

    final updated = app.copyWith(submittedDocuments: generatedDocuments);
    applications[appIndex] = updated;
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setApplication(updated);
    notifyListeners();
  }

  /// Uploads a freshly-generated document's bytes to Supabase Storage and
  /// returns a copy carrying `storagePath`/`downloadUrl` instead of the raw
  /// bytes, so it's small enough to store in Firestore and downloads with
  /// its real filename via a signed URL. Falls back to keeping the raw
  /// bytes only if the upload itself fails, so document generation never
  /// completely breaks if storage is briefly unavailable.
  Future<ApplicationDocument> _uploadGeneratedDocument(
    ApplicationDocument doc,
  ) async {
    final bytes = doc.bytes;
    if (bytes == null || bytes.isEmpty) return doc;

    try {
      final extension = doc.fileName.contains('.')
          ? doc.fileName.split('.').last
          : 'docx';
      final storagePath =
          'applications/${fb_auth.FirebaseAuth.instance.currentUser?.uid ?? currentUser?.id ?? 'user'}/${doc.applicationId}/${doc.id}/${doc.fileName}';
      final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
        bytes: bytes,
        path: storagePath,
        contentType: SupabaseStorageService.contentTypeForExtension(extension),
      );
      return ApplicationDocument(
        id: doc.id,
        applicationId: doc.applicationId,
        requirementName: doc.requirementName,
        fileName: doc.fileName,
        uploadedAt: doc.uploadedAt,
        description: doc.description,
        fileSize: doc.fileSize,
        bytes: null,
        storagePath: storagePath,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      // Storage upload failed — keep the raw bytes so the document is at
      // least usable this session, even though it won't survive a refresh.
      return doc;
    }
  }

  bool hasApplied(String announcementId) {
    return applications.any(
      (a) =>
          a.announcementId == announcementId &&
          a.applicantId == currentUser?.id,
    );
  }

  Application? myApplicationFor(String announcementId) {
    try {
      return applications.firstWhere(
        (a) =>
            a.announcementId == announcementId &&
            a.applicantId == currentUser?.id,
      );
    } catch (_) {
      return null;
    }
  }

  List<Application> get myApplications => applications
      .where(
        (a) =>
            a.applicantId == currentUser?.id &&
            (a.academicYear == null || a.academicYear == academicYear),
      )
      .toList();

  List<Application> get myArchivedApplications => applications
      .where(
        (a) =>
            a.applicantId == currentUser?.id &&
            a.academicYear != null &&
            a.academicYear != academicYear,
      )
      .toList();

  List<String> skillsForUser(User user) {
    final names = [...user.skills];
    for (final application in applications) {
      if ((application.applicantId == user.id ||
              application.applicantName.trim().toLowerCase() ==
                  user.name.trim().toLowerCase()) &&
          (application.status == 'Approved' ||
              application.status == 'Accepted')) {
        names.addAll(application.skills);
      }
    }
    return names.toSet().toList()..sort();
  }

  /// Finds the most relevant completed screening/assessment record for
  /// [user], matched by applicant id first and falling back to name.
  ScreeningRecord? screeningRecordForUser(User user) {
    final matches = screeningRecords
        .where(
          (record) =>
              record.applicantId == user.id ||
              (record.fullName.trim().toLowerCase() ==
                  user.name.trim().toLowerCase()),
        )
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final byYear = (a.academicYear ?? '').compareTo(b.academicYear ?? '');
      if (byYear != 0) return byYear;
      return a.interviewerDate.compareTo(b.interviewerDate);
    });
    return matches.last;
  }

  /// Full screening/assessment history for [user] across all academic
  /// years, most recent first.
  List<ScreeningRecord> screeningHistoryForUser(User user) {
    final matches = screeningRecords
        .where(
          (record) =>
              record.applicantId == user.id ||
              (record.fullName.trim().toLowerCase() ==
                  user.name.trim().toLowerCase()),
        )
        .toList();
    matches.sort((a, b) {
      final byYear = (b.academicYear ?? '').compareTo(a.academicYear ?? '');
      if (byYear != 0) return byYear;
      return b.interviewerDate.compareTo(a.interviewerDate);
    });
    return matches;
  }

  /// Computes a 0-100 recommendation score for assigning [user] to
  /// [office], based on their screening/assessment result (skills &
  /// overall ratings + interviewer recommendation) and how many of their
  /// tagged skills were validated during screening.
  ///
  /// Returns null when the applicant has no screening record yet, so the
  /// UI can show "Not yet assessed" instead of a misleading score.
  /// Returns how many of [office.requiredSkills] are present among
  /// [user]'s skills (profile + approved application), case-insensitively.
  int matchedRequiredSkillsCount(User user, Office office) {
    if (office.requiredSkills.isEmpty) return 0;
    final taggedSkills = skillsForUser(
      user,
    ).map((skill) => skill.trim().toLowerCase()).toSet();
    return office.requiredSkills
        .where((req) => taggedSkills.contains(req.trim().toLowerCase()))
        .length;
  }

  /// 0-100 score of how well [user]'s skills cover [office.requiredSkills].
  /// Returns null when the office has no required skills configured.
  double? requiredSkillMatchScore(User user, Office office) {
    if (office.requiredSkills.isEmpty) return null;
    final matched = matchedRequiredSkillsCount(user, office);
    return matched / office.requiredSkills.length * 100;
  }

  double? recommendationScoreForOffice(User user, Office office) {
    final record = screeningRecordForUser(user);
    final skillScore = requiredSkillMatchScore(user, office);
    if (record == null) return skillScore;

    double averageOf(Map<String, int> ratings) {
      if (ratings.isEmpty) return 0;
      final total = ratings.values.fold<int>(0, (sum, value) => sum + value);
      return total / ratings.length; // ratings are on a 1-5 scale
    }

    final skillsAvg = averageOf(record.skills);
    final overallAvg = averageOf(record.overall);

    // Base score: weighted blend of skill ratings and overall evaluation,
    // scaled to 0-100.
    double score = ((skillsAvg * 0.6) + (overallAvg * 0.4)) / 5 * 100;

    // Adjust for the interviewer's final recommendation.
    switch (record.recommendation) {
      case 'Highly Recommended':
        score += 10;
        break;
      case 'Recommended':
        score += 3;
        break;
      case 'Recommended with Reservations':
        score -= 10;
        break;
      case 'Not Recommended':
        score -= 40;
        break;
    }

    // Small bonus when the skills validated in screening overlap with the
    // skills already tagged on the applicant's profile/application.
    final taggedSkills = skillsForUser(user);
    if (taggedSkills.isNotEmpty && record.skills.isNotEmpty) {
      final matchedCount = record.skills.keys.where((skill) {
        return taggedSkills.any(
          (tagged) => tagged.trim().toLowerCase() == skill.trim().toLowerCase(),
        );
      }).length;
      score += (matchedCount / record.skills.length) * 5;
    }

    // Blend in how well the applicant covers the office's required skills,
    // when the office has any configured. Weighted evenly with the
    // screening-based score so a strong skill match still moves the needle
    // even for a well-screened applicant, and vice versa.
    if (skillScore != null) {
      score = (score * 0.5) + (skillScore * 0.5);
    }

    return score.clamp(0, 100);
  }

  /// Returns [users] sorted best-match-first for [office], using
  /// [recommendationScoreForOffice]. Applicants without an assessment on
  /// file are pushed to the end (alphabetically among themselves).
  List<User> sortByOfficeMatch(List<User> users, Office office) {
    final sorted = [...users];
    sorted.sort((a, b) {
      final scoreA = recommendationScoreForOffice(a, office);
      final scoreB = recommendationScoreForOffice(b, office);
      if (scoreA == null && scoreB == null) return a.name.compareTo(b.name);
      if (scoreA == null) return 1;
      if (scoreB == null) return -1;
      return scoreB.compareTo(scoreA);
    });
    return sorted;
  }

  // ─── Notifications ─────────────────────────────────
  void _addNotification(AppNotification n) {
    notifications = [n, ...notifications];
    _firestoreService ??= FirestoreService();
    _firestoreService!.addNotification(n.toJson()).catchError((error) {
      debugPrint('Failed to persist notification: $error');
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
    notifications = notifications
        .map((n) => n.userId == currentUser?.id ? n.copyWith(isRead: true) : n)
        .toList();
    for (final notification in notifications.where(
      (n) => n.userId == currentUser?.id,
    )) {
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

  void archiveStudent(String id) {
    students = students
        .map((s) => s.id == id ? s.copyWith(status: 'Archived') : s)
        .toList();
    notifyListeners();
  }

  void restoreStudent(String id) {
    students = students
        .map((s) => s.id == id ? s.copyWith(status: 'Active') : s)
        .toList();
    notifyListeners();
  }

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
  Future<void> setManualTimeOut(String recordId, String timeOut) async {
    final existing = attendance.cast<AttendanceRecord?>().firstWhere(
      (r) => r?.id == recordId,
      orElse: () => null,
    );
    final totalHours = _hoursBetween(existing?.timeIn, timeOut);

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
      });
    } catch (_) {
      // ignore
    }
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
  /// Returns how many records were written and how many could not be. A
  /// failed write leaves the local value fixed but the stored one stale,
  /// and the attendance stream then pushes the old value straight back —
  /// which looks exactly like the button doing nothing. Callers must report
  /// [failed] instead of claiming success.
  Future<({int fixed, int failed})> recalculateAttendanceHours() async {
    _firestoreService ??= FirestoreService();
    final corrections = <String, double>{};

    for (final r in attendance) {
      if (r.isActive) continue; // no time-out yet — nothing to recompute.
      final correct = _hoursBetween(r.timeIn, r.timeOut!);
      if (r.totalHours == null || (r.totalHours! - correct).abs() > 0.01) {
        corrections[r.id] = correct;
      }
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
    attendance = attendance
        .map((a) => a.id == id ? a.copyWith(isArchived: archived) : a)
        .toList();
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.updateAttendance(id, {'isArchived': archived});
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
  Future<void> addTask(Task task) async {
    task = Task(
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      dueDate: task.dueDate,
      assignedTo: task.assignedTo,
      assignedToName: task.assignedToName,
      assignedBy: task.assignedBy,
      category: task.category,
      checklistItems: task.checklistItems,
      isArchived: task.isArchived,
      academicYear: task.academicYear ?? academicYear,
      completedAt: task.status == 'Completed'
          ? (task.completedAt ?? _formattedToday())
          : null,
    );
    // Optimistically update local state for immediate UI feedback.
    tasks = [task, ...tasks];
    if (task.assignedTo != null) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${task.assignedTo}',
          userId: task.assignedTo!,
          title: 'New Task Assigned',
          message: 'You have been assigned "${task.title}".',
          type: 'task',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTask(task);
    } catch (_) {
      // Firestore not available — keep local state.
    }
  }

  Future<void> updateTaskStatus(String id, String status) async {
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
    if (existingTask.id.isEmpty || existingTask.isArchived) return;
    tasks = tasks.map((t) {
      if (t.id == id) {
        // Stamp (or clear) the completion date so the DTR/Accomplishment
        // Report screen can automatically turn "task completed today" into
        // that day's attendance/accomplishment entry. Re-completing a task
        // that's already marked Completed keeps its original date rather
        // than overwriting it.
        final becameCompleted = status == 'Completed';
        return Task(
          id: t.id,
          title: t.title,
          description: t.description,
          status: status,
          priority: t.priority,
          dueDate: t.dueDate,
          assignedTo: t.assignedTo,
          assignedToName: t.assignedToName,
          assignedBy: t.assignedBy,
          category: t.category,
          checklistItems: t.checklistItems,
          isArchived: t.isArchived,
          academicYear: t.academicYear,
          completedAt: becameCompleted
              ? (t.completedAt ?? _formattedToday())
              : null,
        );
      }
      return t;
    }).toList();
    if (existingTask.assignedBy != null && existingTask.status != status) {
      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${existingTask.assignedBy}',
          userId: existingTask.assignedBy!,
          title: 'Task Updated',
          message:
              '${existingTask.assignedToName ?? "A student"} marked "${existingTask.title}" as $status.',
          type: 'task',
          createdAt: _formattedToday(),
        ),
      );
    }
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      final updated = tasks.firstWhere((t) => t.id == id);
      await _firestoreService!.setTask(updated);
    } catch (_) {}
  }

  Future<void> deleteTask(String id) async {
    tasks = tasks.where((t) => t.id != id).toList();
    notifyListeners();

    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.deleteTask(id);
    } catch (_) {}
  }

  Future<void> setTaskArchived(String id, bool isArchived) async {
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = tasks[index];
    final updated = Task(
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      dueDate: task.dueDate,
      assignedTo: task.assignedTo,
      assignedToName: task.assignedToName,
      assignedBy: task.assignedBy,
      category: task.category,
      checklistItems: task.checklistItems,
      isArchived: isArchived,
      academicYear: task.academicYear,
      completedAt: task.completedAt,
    );
    tasks = [...tasks]..[index] = updated;
    notifyListeners();
    try {
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setTask(updated);
    } catch (_) {}
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
          .where((office) {
            if (!office.isActive) return false;
            return (assistantId != null &&
                    office.assistantIds.contains(assistantId)) ||
                office.assistantNames.any(
                  (name) =>
                      name.trim().toLowerCase() ==
                      assistantName.trim().toLowerCase(),
                );
          })
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
    headForwards = [
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
      ...headForwards,
    ];
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
        final forward = headForwards.firstWhere(
          (f) => f.id == id,
          orElse: () => headForwards.first,
        );
        if (forward.sentById != null) {
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
    String? name,
    String? phone,
    String? address,
    String? avatar,
    List<String>? skills,
    String? yearLevel,
  }) async {
    if (currentUser != null) {
      currentUser = currentUser!.copyWith(
        name: name,
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
    if (academicYear != year) {
      final currentSettings = await _firestoreService!
          .getAcademicYearSettings();
      if (currentSettings != null && currentSettings['academicYear'] != null) {
        // Only record the year as finished. Its records are copied into the
        // archive by the Head's session (see _archiveFinishedAcademicYears),
        // since the Admin can't read them all.
        await _firestoreService!.archiveAcademicYearSettings(
          currentSettings['academicYear'].toString(),
          currentSettings,
          // The finished year's own "Auto-archive Logs" setting, which the
          // app treats as on when it was never saved.
          archiveAttendance: currentSettings['autoArchiveLogs'] as bool? ?? true,
        );
        academicYearArchives = [
          ...academicYearArchives.where(
            (archive) =>
                archive['academicYear'] != currentSettings['academicYear'],
          ),
          {...currentSettings, 'academicYear': currentSettings['academicYear']},
        ];
      }
    }
    await _firestoreService!.saveAcademicYearSettings({
      'academicYear': year,
      'semester': semester,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'allowApplications': allowApplications,
      'enforceHourCap': enforceHourCap,
      'autoArchiveLogs': autoArchiveLogs,
      'milestones': milestones,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    academicYear = year;
    academicSemester = semester;
    academicYearStart = startDate;
    academicYearEnd = endDate;
    allowAcademicApplications = allowApplications;
    enforceAssistantHourCap = enforceHourCap;
    autoArchiveAttendanceLogs = autoArchiveLogs;
    academicMilestones = milestones;
    notifyListeners();
  }

  Future<String?> createManagedUser(User user, String password) async {
    await _ensureSeeded();
    if (users.any((u) => u.email.toLowerCase() == user.email.toLowerCase())) {
      return 'An account with this email already exists.';
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
      // Login requires a verified email, and nothing else would send the
      // new user a link.
      try {
        await authUser.sendEmailVerification();
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

  Future<void> deleteManagedUser(String id) async {
    final user = users.firstWhere((u) => u.id == id);
    _firestoreService ??= FirestoreService();
    await _firestoreService!.deleteUserProfile(id);

    final linkedStudents = students
        .where(
          (student) =>
              student.userId == id ||
              student.email.toLowerCase() == user.email.toLowerCase(),
        )
        .toList();
    for (final student in linkedStudents) {
      if (student.id.isNotEmpty) {
        await _firestoreService!.deleteStudent(student.id);
      }
    }
    students = students
        .where((student) => !linkedStudents.contains(student))
        .toList();
    users = users.where((u) => u.id != id).toList();
    notifyListeners();
  }

  Future<void> deleteUser(String id) => deleteManagedUser(id);

  Future<void> archiveUser(String id) async {
    final user = users.firstWhere((u) => u.id == id);
    final archivedUser = user.copyWith(status: 'Archived');
    users = users.map((u) => u.id == id ? archivedUser : u).toList();
    await _saveUserProfile(archivedUser);
    notifyListeners();
  }

  Future<void> restoreUser(String id) async {
    final user = users.firstWhere((u) => u.id == id);
    final restoredUser = user.copyWith(status: 'Active');
    users = users.map((u) => u.id == id ? restoredUser : u).toList();
    await _saveUserProfile(restoredUser);
    notifyListeners();
  }

  /// [notify] is off when the change comes from a flow that sends its own,
  /// more specific notification (such as a rehire decision).
  Future<void> changeUserRole(
    String id,
    String newRole, {
    bool notify = true,
  }) async {
    final user = users.firstWhere(
      (u) => u.id == id,
      orElse: () => User(id: '', name: '', email: '', role: ''),
    );
    if (user.id.isEmpty) return;

    // When converting Student to Student Assistant or vice versa, preserve all user data
    final oldRole = user.role;
    users = users.map((u) {
      if (u.id == id) return u.copyWith(role: newRole);
      return u;
    }).toList();

    // Preserve all user data during role transitions
    // - Notifications stay with the user
    // - Applications stay with the user
    // - Tasks and reports are tied to user name/id and will follow
    // - If current user's role changed, update the global role
    if (currentUser?.id == id) {
      currentUser = currentUser!.copyWith(role: newRole);
    }

    final updatedUser = users.firstWhere((u) => u.id == id, orElse: () => user);
    await _saveUserProfile(updatedUser);

    // If the user was promoted to Student Assistant, ensure a Student
    // record exists and persist it to Firestore so the dashboard shows
    // them as enrolled.
    if (newRole == 'Student Assistant') {
      try {
        _firestoreService ??= FirestoreService();
        final hasStudent = _studentRecordsForUser(updatedUser).isNotEmpty;
        if (hasStudent) {
          // A returning Student Assistant (not rehired in an earlier term)
          // still has their old, archived record — bring it back rather
          // than leave them off every roster.
          await _setStudentRecordsStatus(updatedUser, 'Active');
        } else {
          final dept =
              updatedUser.department ??
              (departments.isNotEmpty ? departments.first : '');
          final campusVal = updatedUser.campus;
          final student = Student(
            id: updatedUser.id,
            name: updatedUser.name,
            email: updatedUser.email,
            department: dept,
            campus: campusVal,
            userId: updatedUser.id,
            totalHours: 0,
          );
          students = [student, ...students];
          await _firestoreService!.setStudent(student);
        }
      } catch (e) {
        debugPrint('Failed to create student record for promoted user $id: $e');
      }
    }
    // Notify the user that their role was changed
    if (notify) {
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
    return office.headIds.contains(supervisor.id) ||
        office.headNames.any(
          (name) =>
              name.trim().toLowerCase() == supervisor.name.trim().toLowerCase(),
        );
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
    return offices.where((office) {
      if (!office.isActive) return false;
      return office.assistantIds.contains(user.id) ||
          office.headIds.contains(user.id) ||
          office.headNames.any(
            (name) =>
                name.trim().toLowerCase() == user.name.trim().toLowerCase(),
          ) ||
          office.assistantNames.any(
            (name) =>
                name.trim().toLowerCase() == user.name.trim().toLowerCase(),
          );
    }).toList();
  }

  List<Office> officesForUser(User user) {
    final normalizedName = user.name.trim().toLowerCase();
    return offices.where((office) {
      if (!office.isActive) return false;
      return office.assistantIds.contains(user.id) ||
          office.headIds.contains(user.id) ||
          office.headNames.any(
            (name) => name.trim().toLowerCase() == normalizedName,
          ) ||
          office.assistantNames.any(
            (name) => name.trim().toLowerCase() == normalizedName,
          );
    }).toList();
  }

  List<Student> get effectiveStudents {
    final userById = {for (final u in users) u.id: u};
    double hoursFor(Set<String> ids, Set<String> names) {
      final normalizedNames = names
          .where((name) => name.trim().isNotEmpty)
          .map((name) => name.trim().toLowerCase())
          .toSet();
      return attendance
          .where(
            (record) =>
                (record.studentId != null && ids.contains(record.studentId)) ||
                normalizedNames.contains(
                  record.studentName.trim().toLowerCase(),
                ),
          )
          .fold<double>(0, (sum, record) => sum + (record.totalHours ?? 0));
    }

    final activeStudents = students.where((s) => s.status != 'Archived').map((
      s,
    ) {
      User? user = s.userId == null ? null : userById[s.userId];
      user ??= users.cast<User?>().firstWhere(
        (candidate) =>
            candidate?.email.trim().toLowerCase() ==
            s.email.trim().toLowerCase(),
        orElse: () => null,
      );
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
        department: s.department.isNotEmpty ? s.department : user?.department,
        campus: s.campus ?? user?.campus,
        totalHours: hours > 0 ? hours : s.totalHours,
        phone: s.phone ?? user?.phone,
        address: s.address ?? user?.address,
        avatar: s.avatar ?? user?.avatar,
        userId: s.userId ?? user?.id,
      );
    }).toList();

    final existingStudentIds = {
      for (final s in activeStudents) s.userId ?? s.id,
    };

    final fallback = users
        .where((u) => u.role == 'Student Assistant' && u.status != 'Archived')
        .where((u) {
          final key = u.id;
          return !existingStudentIds.contains(key);
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
    final knownNames = {
      for (final student in combined) student.name.trim().toLowerCase(),
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
  double verifiedDtrHoursForStudent(String studentName) {
    return filteredAttendance
        .where(
          (a) =>
              a.studentName == studentName &&
              !a.isArchived &&
              !a.isActive, // has a timeOut => verified/completed
        )
        .fold<double>(0, (sum, a) => sum + (a.totalHours ?? 0));
  }

  /// Accomplishment reports already approved by the supervisor for a
  /// student, scoped the same way as [filteredReports].
  List<Report> approvedReportsForStudent(String studentName) {
    return filteredReports
        .where((r) => r.studentName == studentName && r.status == 'Approved')
        .toList();
  }

  // ─── Payroll ───────────────────────────────────────────
  // Parses the handful of date-string shapes this codebase already writes
  // ("Sep 19, 2026" from attendance, "9/19/2026" from reports) so payroll
  // can filter both by an arbitrary pay period.
  DateTime? _parsePayrollDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    if (slash != null) {
      try {
        return DateTime(
          int.parse(slash.group(3)!),
          int.parse(slash.group(1)!),
          int.parse(slash.group(2)!),
        );
      } catch (_) {
        return null;
      }
    }

    const abbrMonths = [
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
    const fullMonths = [
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
    final named = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})$').firstMatch(s);
    if (named != null) {
      final monthName = named.group(1)!;
      var index = abbrMonths.indexOf(monthName);
      if (index < 0) index = fullMonths.indexOf(monthName);
      if (index < 0) return null;
      try {
        return DateTime(
          int.parse(named.group(3)!),
          index + 1,
          int.parse(named.group(2)!),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _dateWithinRange(String? raw, DateTime start, DateTime endInclusive) {
    final parsed = _parsePayrollDate(raw);
    if (parsed == null) return false;
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
        !day.isAfter(
          DateTime(endInclusive.year, endInclusive.month, endInclusive.day),
        );
  }

  /// Every calendar month touched by [start]..[endInclusive] (both ends
  /// inclusive), so a semester-long pay period can still have the 25–40
  /// hour rule checked and capped one month at a time.
  List<(int month, int year)> _monthsInRange(
    DateTime start,
    DateTime endInclusive,
  ) {
    final months = <(int, int)>[];
    var cursor = DateTime(start.year, start.month);
    final last = DateTime(endInclusive.year, endInclusive.month);
    while (!cursor.isAfter(last)) {
      months.add((cursor.month, cursor.year));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return months;
  }

  /// This student's verified (timed-out, non-archived) attendance hours
  /// within [start]..[endInclusive], broken down by calendar month so each
  /// month's payable hours can be capped at [PayrollRecord.maximumMonthlyHours]
  /// individually before the semester total is summed. Isn't scoped to the
  /// current viewer's role since only an Admin runs payroll.
  /// Every name this user's attendance/report rows might be logged under —
  /// their own account name plus any linked Student roster name — lowercase
  /// and trimmed, the same identity-matching approach [effectiveStudents]
  /// already uses, since older attendance/report rows may only have a
  /// studentName string rather than a stable studentId. [studentsByUserId]/
  /// [studentsByEmail] are precomputed once by the caller (typically
  /// [buildPayrollPreview], over every active assistant) rather than
  /// rescanning the full [students] roster per user.
  Set<String> _nameKeysFor(
    User user, {
    required Map<String, Student> studentsByUserId,
    required Map<String, Student> studentsByEmail,
  }) {
    final keys = <String>{user.name.trim().toLowerCase()};
    final linked =
        studentsByUserId[user.id] ??
        studentsByEmail[user.email.trim().toLowerCase()];
    if (linked != null) keys.add(linked.name.trim().toLowerCase());
    return keys;
  }

  /// [studentId], when attendance/report rows have one, is preferred over
  /// the fuzzy [studentNameKeys] match — it's the stable identity clockIn()
  /// already records, whereas studentName is free text that can drift from
  /// the account name (case, spacing, a roster rename).
  List<PayrollMonthBreakdown> monthlyHoursInPeriod(
    String studentId,
    Set<String> studentNameKeys,
    DateTime start,
    DateTime endInclusive,
  ) {
    bool belongsToStudent(AttendanceRecord a) =>
        a.studentId == studentId ||
        studentNameKeys.contains(a.studentName.trim().toLowerCase());

    return _monthsInRange(start, endInclusive).map((entry) {
      final (month, year) = entry;
      final monthStart = DateTime(year, month, 1);
      final monthEndInclusive = DateTime(year, month + 1, 0);
      final rangeStart = monthStart.isBefore(start) ? start : monthStart;
      final rangeEnd = monthEndInclusive.isAfter(endInclusive)
          ? endInclusive
          : monthEndInclusive;

      final hours = attendance
          .where(
            (a) =>
                belongsToStudent(a) &&
                !a.isArchived &&
                !a.isActive &&
                _dateWithinRange(a.date, rangeStart, rangeEnd),
          )
          .fold<double>(0, (sum, a) => sum + (a.totalHours ?? 0));

      return PayrollMonthBreakdown(
        month: month,
        year: year,
        hoursWorked: hours,
        payableHours: hours
            .clamp(0, PayrollRecord.maximumMonthlyHours)
            .toDouble(),
      );
    }).toList();
  }

  /// Whether an approved accomplishment report — standing in for the
  /// broader "payroll requirements" (the DTR/Accomplishment Report bundle
  /// a supervisor forwards to the Head) — exists for this student anywhere
  /// within the given period.
  bool hasApprovedReportInPeriod(
    Set<String> studentNameKeys,
    DateTime start,
    DateTime endInclusive,
  ) {
    return reports.any(
      (r) =>
          studentNameKeys.contains(r.studentName.trim().toLowerCase()) &&
          r.status == 'Approved' &&
          _dateWithinRange(r.submittedAt, start, endInclusive),
    );
  }

  /// Builds a payroll preview for every active Student Assistant for the
  /// pay period [start]..[endInclusive] (typically a whole semester, not a
  /// single month) — purely computed for anyone not yet approved. Once a
  /// student has a persisted [PayrollRecord] for this exact period (status
  /// 'Approved' or 'Released'), that persisted record is returned as-is
  /// instead of recomputing, so an approved amount stays fixed even if
  /// attendance data changes afterward. Retrieves and verifies each
  /// student's DTR records and accomplishment report before marking them
  /// 'Ready' to approve; anyone missing either is 'Incomplete'.
  List<PayrollRecord> buildPayrollPreview({
    required DateTime start,
    required DateTime endInclusive,
    required String periodLabel,
  }) {
    final isoStart = _isoDate(start);
    final isoEnd = _isoDate(endInclusive);
    final existingByStudent = {
      for (final p in payrollRecords)
        if (p.periodStart == isoStart && p.periodEnd == isoEnd) p.studentId: p,
    };

    final assistants = users.where(
      (u) => u.role == 'Student Assistant' && u.status == 'Active',
    );

    // Built once for the whole preview rather than rescanning `students`
    // per assistant inside `_nameKeysFor`.
    final studentsByUserId = {
      for (final s in students)
        if (s.userId != null) s.userId!: s,
    };
    final studentsByEmail = {
      for (final s in students) s.email.trim().toLowerCase(): s,
    };

    return assistants.map((user) {
      final existing = existingByStudent[user.id];
      if (existing != null) return existing;

      final nameKeys = _nameKeysFor(
        user,
        studentsByUserId: studentsByUserId,
        studentsByEmail: studentsByEmail,
      );
      final breakdown = monthlyHoursInPeriod(
        user.id,
        nameKeys,
        start,
        endInclusive,
      );
      final dtrVerified = breakdown.any((m) => m.hoursWorked > 0);
      final reportVerified = hasApprovedReportInPeriod(
        nameKeys,
        start,
        endInclusive,
      );
      final assignedOffices = officesForUser(user);
      final office = assignedOffices.isNotEmpty
          ? assignedOffices.first.name
          : (user.department ?? '');

      return PayrollRecord(
        id: '',
        studentId: user.id,
        studentName: user.name,
        saId: user.saId,
        office: office,
        campus: user.campus,
        department: user.department,
        periodStart: isoStart,
        periodEnd: isoEnd,
        periodLabel: periodLabel,
        monthlyBreakdown: breakdown,
        dtrVerified: dtrVerified,
        reportVerified: reportVerified,
        status: dtrVerified && reportVerified ? 'Ready' : 'Incomplete',
      );
    }).toList();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The Admin's saved payroll sheet for a pay period, if any.
  PayrollSheet? payrollSheetFor(String periodStart, String periodEnd) {
    final id = PayrollSheet.idForPeriod(periodStart, periodEnd);
    return payrollSheets.where((sheet) => sheet.id == id).firstOrNull;
  }

  /// The most recently saved payroll sheet, whose signatories and header
  /// fields a new period's sheet starts from.
  PayrollSheet? get latestPayrollSheet {
    if (payrollSheets.isEmpty) return null;
    return payrollSheets.reduce(
      (a, b) => (b.updatedAt ?? '').compareTo(a.updatedAt ?? '') > 0 ? b : a,
    );
  }

  Future<PayrollSheet> savePayrollSheet(PayrollSheet sheet) async {
    _firestoreService ??= FirestoreService();
    final saved = sheet.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
      updatedBy: currentUser?.name ?? 'Admin',
    );
    await _firestoreService!.setPayrollSheet(saved);
    payrollSheets = [saved, ...payrollSheets.where((s) => s.id != saved.id)];
    notifyListeners();
    return saved;
  }

  /// Administrators approve payroll: computes the payable amount from
  /// total hours rendered for every currently-'Ready' entry in [preview]
  /// and records it in the payroll records with status 'Approved' —
  /// skipping anything 'Incomplete', already 'Approved', or 'Released'.
  /// Does not notify students yet; that happens on [releasePayroll].
  Future<(int count, double total)> approvePayroll(
    List<PayrollRecord> preview,
  ) async {
    _firestoreService ??= FirestoreService();
    final today = _formattedToday();
    var count = 0;
    var total = 0.0;

    for (final record in preview) {
      if (record.status != 'Ready') continue;
      final toSave = record.copyWith(
        status: 'Approved',
        approvedAt: today,
        approvedBy: currentUser?.name ?? 'Admin',
      );
      final docId = await _firestoreService!.addPayrollRecord(toSave);
      payrollRecords = [toSave.copyWith(id: docId), ...payrollRecords];
      count++;
      total += record.grossPay;
    }

    notifyListeners();
    return (count, total);
  }

  /// Administrators release payroll: marks every 'Approved' record for the
  /// pay period [start]..[endInclusive] as 'Released' (the actual payout
  /// moment) and notifies each Student Assistant that their pay has been
  /// released.
  Future<(int count, double total)> releasePayroll({
    required DateTime start,
    required DateTime endInclusive,
  }) async {
    _firestoreService ??= FirestoreService();
    final today = _formattedToday();
    var count = 0;
    var total = 0.0;
    final isoStart = _isoDate(start);
    final isoEnd = _isoDate(endInclusive);

    final toRelease = payrollRecords.where(
      (p) =>
          p.periodStart == isoStart &&
          p.periodEnd == isoEnd &&
          p.status == 'Approved',
    );

    for (final record in toRelease) {
      final releasedBy = currentUser?.name ?? 'Admin';
      await _firestoreService!.updatePayrollRecord(record.id, {
        'status': 'Released',
        'releasedAt': today,
        'releasedBy': releasedBy,
      });
      payrollRecords = payrollRecords
          .map(
            (p) => p.id == record.id
                ? p.copyWith(
                    status: 'Released',
                    releasedAt: today,
                    releasedBy: releasedBy,
                  )
                : p,
          )
          .toList();
      count++;
      total += record.grossPay;

      _addNotification(
        AppNotification(
          id: 'n_${DateTime.now().millisecondsSinceEpoch}_${record.studentId}',
          userId: record.studentId,
          title: 'Payout Released',
          message:
              'Your pay for ${record.periodLabel} (${record.payableHours.toStringAsFixed(1)} hrs · '
              '₱${record.grossPay.toStringAsFixed(2)}) has been released.',
          type: 'payroll',
          createdAt: today,
        ),
      );
    }

    notifyListeners();
    return (count, total);
  }

  /// This student's saved weekly class schedule rows (used to auto-fill
  /// the DTR/Accomplishment Report's "Class Schedule" grid), scoped the
  /// same way as [filteredStudents] so a supervisor only sees their own
  /// office's data.
  List<ClassScheduleEntry> classScheduleForStudent(String studentName) {
    final officeNames = role == 'Supervisor'
        ? _officeStudentNamesForSupervisor.toSet()
        : null;
    return classSchedules
        .where(
          (c) =>
              c.studentName == studentName &&
              (officeNames == null || officeNames.contains(c.studentName)),
        )
        .toList();
  }

  /// Replaces this student's saved weekly class schedule with [rows] —
  /// called when a supervisor edits and generates a DTR/Accomplishment
  /// Report, so the schedule is remembered for next time instead of having
  /// to be re-typed every month. Persists to Firestore when available,
  /// falling back to an in-memory update if the backend call fails.
  Future<void> saveClassScheduleForStudent(
    String studentId,
    String studentName,
    List<ClassScheduleEntry> rows,
  ) async {
    _firestoreService ??= FirestoreService();
    try {
      await _firestoreService!.deleteClassScheduleEntriesForStudent(
        studentName,
      );
      final saved = <ClassScheduleEntry>[];
      for (final row in rows) {
        saved.add(await _firestoreService!.addClassScheduleEntry(row));
      }
      classSchedules = [
        ...classSchedules.where((c) => c.studentName != studentName),
        ...saved,
      ];
    } catch (_) {
      // Firestore not available — fall back to an in-memory update so the
      // grid still stays pre-filled for the rest of this session.
      classSchedules = [
        ...classSchedules.where((c) => c.studentName != studentName),
        ...rows,
      ];
    }
    notifyListeners();
  }

  /// The most recent evaluation already on file for a student + term
  /// (so a supervisor can see/edit what was already submitted).
  Evaluation? existingEvaluationFor(String studentName, String term) {
    final matches = filteredEvaluations
        .where((e) => e.studentName == studentName && e.term == term)
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return matches.first;
  }

  /// Create or update a performance evaluation.
  Future<bool> saveEvaluation(Evaluation evaluation) async {
    _firestoreService ??= FirestoreService();
    final nowIso = DateTime.now().toIso8601String();
    try {
      Evaluation savedEvaluation;
      if (evaluation.id.isEmpty) {
        // New evaluation: stamp createdAt/academicYear, then persist.
        final withCreated = Evaluation(
          id: '',
          studentId: evaluation.studentId,
          studentName: evaluation.studentName,
          office: evaluation.office,
          term: evaluation.term,
          periodCovered: evaluation.periodCovered,
          dateOfRating: evaluation.dateOfRating,
          eligibleForRehire: evaluation.eligibleForRehire,
          ratings: evaluation.ratings,
          overallRating: evaluation.overallRating,
          departmentHeadComments: evaluation.departmentHeadComments,
          supervisorId: evaluation.supervisorId,
          supervisorName: evaluation.supervisorName,
          verifiedDtrHours: evaluation.verifiedDtrHours,
          approvedReportCount: evaluation.approvedReportCount,
          status: evaluation.status,
          academicYear: academicYear,
          createdAt: nowIso,
          updatedAt: nowIso,
        );
        await _firestoreService!.setEvaluation(withCreated);
        evaluations = [withCreated, ...evaluations];
        savedEvaluation = withCreated;
      } else {
        final updated = evaluation.copyWith(updatedAt: nowIso);
        await _firestoreService!.setEvaluation(updated);
        evaluations = evaluations
            .map((e) => e.id == updated.id ? updated : e)
            .toList();
        savedEvaluation = updated;
      }

      // Notify the student assistant that their evaluation result is ready.
      if (savedEvaluation.status == 'Submitted') {
        String? recipientUserId;
        try {
          final student = students.firstWhere(
            (s) => s.id == savedEvaluation.studentId,
          );
          recipientUserId = student.userId;
        } catch (_) {
          recipientUserId = null;
        }
        // Fall back to matching by name if the student record lookup
        // didn't resolve a linked user account.
        if (recipientUserId == null || recipientUserId.isEmpty) {
          try {
            final matchedUser = users.firstWhere(
              (u) =>
                  u.role == 'Student Assistant' &&
                  u.name == savedEvaluation.studentName,
            );
            recipientUserId = matchedUser.id;
          } catch (_) {
            recipientUserId = null;
          }
        }

        if (recipientUserId != null && recipientUserId.isNotEmpty) {
          final band = EvaluationCriteria.bandLabel(
            savedEvaluation.overallRating,
          );
          _addNotification(
            AppNotification(
              id: 'n_${DateTime.now().millisecondsSinceEpoch}_$recipientUserId',
              userId: recipientUserId,
              title: 'Performance Evaluation Available',
              message:
                  'Your performance evaluation for ${savedEvaluation.term} '
                  '(${savedEvaluation.periodCovered}) is ready. Overall '
                  'rating: ${savedEvaluation.overallRating} — $band.',
              type: 'evaluation',
              createdAt: _formattedToday(),
            ),
          );
        }
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to save evaluation in Firestore: $e');
      return false;
    }
  }

  // ─── Rehiring ──────────────────────────────────────
  /// Terms the Head can make rehire decisions for: the current term (per the
  /// academic year settings) and the three after it.
  List<({String academicYear, String semester})> get rehireTermOptions {
    final options = [(academicYear: academicYear, semester: academicSemester)];
    while (options.length < 4) {
      options.add(
        RehireRecord.nextTerm(options.last.academicYear, options.last.semester),
      );
    }
    return options;
  }

  /// The term the Rehiring screen opens on: the one after the current term,
  /// skipping the optional Summer term.
  ({String academicYear, String semester}) get defaultRehireTerm {
    var term = RehireRecord.nextTerm(academicYear, academicSemester);
    if (term.semester == 'Summer') {
      term = RehireRecord.nextTerm(term.academicYear, term.semester);
    }
    return term;
  }

  /// Whether decisions for a term should already be in effect, i.e. the
  /// academic year settings have reached that term.
  bool rehireTermHasStarted(String termYear, String termSemester) {
    final target = RehireRecord.termOrder(termYear, termSemester);
    final current = RehireRecord.termOrder(academicYear, academicSemester);
    // A term that can't be placed on the calendar shouldn't hold the
    // decision back forever.
    if (target == null || current == null) return true;
    return target <= current;
  }

  static const _evaluationTermOrder = {
    'First Semester': 0,
    'Second Semester': 1,
    'Midyear Term': 2,
  };

  /// [user]'s most recent submitted performance evaluation — the one whose
  /// "Eligible for Rehire" mark the rehire decision follows up on.
  Evaluation? latestEvaluationForUser(User user) {
    final ids = {user.id, for (final s in _studentRecordsForUser(user)) s.id};
    final name = user.name.trim().toLowerCase();
    final matches = evaluations
        .where(
          (e) =>
              e.status == 'Submitted' &&
              (ids.contains(e.studentId) ||
                  e.studentName.trim().toLowerCase() == name),
        )
        .toList();
    matches.sort((a, b) {
      final byYear = (b.academicYear ?? '').compareTo(a.academicYear ?? '');
      if (byYear != 0) return byYear;
      final byTerm = (_evaluationTermOrder[b.term] ?? -1).compareTo(
        _evaluationTermOrder[a.term] ?? -1,
      );
      if (byTerm != 0) return byTerm;
      return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
    });
    return matches.firstOrNull;
  }

  RehireRecord? rehireRecordFor(
    String userId,
    String termYear,
    String termSemester,
  ) => rehireRecords
      .where(
        (r) =>
            r.studentId == userId &&
            r.academicYear == termYear &&
            r.semester == termSemester,
      )
      .firstOrNull;

  /// Everyone the Head decides on for a term: all current Student
  /// Assistants, plus anyone already decided on for that term — a student
  /// who wasn't rehired is a Student again, but their decision should stay
  /// visible and reversible.
  List<User> rehireCandidates(String termYear, String termSemester) {
    final decided = rehireRecords
        .where((r) => r.academicYear == termYear && r.semester == termSemester)
        .map((r) => r.studentId)
        .toSet();
    return users
        .where(
          (u) =>
              u.status != 'Archived' &&
              (u.role == 'Student Assistant' || decided.contains(u.id)),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Records the Head's rehire decision for [user] for the given term and
  /// notifies the student and their office supervisors. A rehire also gets
  /// the new term's Contract of Appointment, filed in Student Documents.
  ///
  /// The roster change itself (office, role, students record) waits until
  /// the term starts — see [_applyRehireRecord] — unless it already has.
  /// Returns an error message, or null on success.
  Future<String?> decideRehire({
    required User user,
    required String termYear,
    required String termSemester,
    required bool rehire,
    String? officeId,
    String remarks = '',
  }) async {
    Office? office;
    if (rehire) {
      office = offices.where((o) => o.id == officeId).firstOrNull;
      if (office == null) return 'Choose the office they will be rehired to.';
      if (!office.assistantIds.contains(user.id) &&
          office.capacity > 0 &&
          office.assistantIds.length >= office.capacity) {
        return '${office.name} is already at its capacity of '
            '${office.capacity}.';
      }
    }

    final currentOffices = officesForUser(user);
    final previous = rehireRecordFor(user.id, termYear, termSemester);
    final List<String> officeIds;
    final List<String> officeNames;
    if (office != null) {
      officeIds = [office.id];
      officeNames = [office.name];
    } else if (currentOffices.isNotEmpty) {
      officeIds = currentOffices.map((o) => o.id).toList();
      officeNames = currentOffices.map((o) => o.name).toList();
    } else {
      // Already taken off their office by an earlier decision for this
      // term; keep recording where they were.
      officeIds = previous?.officeIds ?? const [];
      officeNames = previous?.officeNames ?? const [];
    }

    final evaluation = latestEvaluationForUser(user);
    var record = RehireRecord(
      id: RehireRecord.idFor(user.id, termYear, termSemester),
      studentId: user.id,
      studentName: user.name,
      saId: user.saId,
      academicYear: termYear,
      semester: termSemester,
      decision: rehire ? RehireRecord.rehired : RehireRecord.notRehired,
      officeIds: officeIds,
      officeNames: officeNames,
      evaluationId: evaluation?.id,
      evaluationTerm: evaluation?.term,
      evaluationAcademicYear: evaluation?.academicYear,
      evaluationOverallRating: evaluation?.overallRating,
      eligibleForRehire: evaluation?.eligibleForRehire,
      remarks: remarks.trim(),
      decidedById: currentUser?.id ?? '',
      decidedByName: currentUser?.name ?? '',
      decidedAt: DateTime.now().toIso8601String(),
    );

    try {
      _firestoreService ??= FirestoreService();
      // A changed decision shouldn't leave the old contract behind in
      // Student Documents.
      final oldContractId = previous?.contractDocumentId;
      if (oldContractId != null && oldContractId.isNotEmpty) {
        await _firestoreService!.deleteDocument(oldContractId);
        documents = documents.where((d) => d.id != oldContractId).toList();
      }
      if (office != null) {
        try {
          record = await _attachRehireContract(record, user, office);
        } catch (error) {
          // The decision still stands; the Rehiring screen offers to
          // generate the contract again.
          debugPrint('Failed to generate rehire contract: $error');
        }
      }
      await _firestoreService!.setRehireRecord(record);
      rehireRecords = [record, ...rehireRecords.where((r) => r.id != record.id)];
      if (rehireTermHasStarted(termYear, termSemester)) {
        await _applyRehireRecord(record);
      }
    } catch (error) {
      debugPrint('Failed to save rehire decision: $error');
      notifyListeners();
      return 'Could not save the decision: $error';
    }

    final officeLabel = officeNames.isEmpty
        ? ''
        : ' in ${officeNames.join(', ')}';
    _addNotification(
      AppNotification(
        id: 'n_${DateTime.now().microsecondsSinceEpoch}_rehire_${user.id}',
        userId: user.id,
        title: rehire
            ? 'Rehired as Student Assistant'
            : 'Student Assistantship Not Renewed',
        message: rehire
            ? 'You have been rehired as a Student Assistant for '
                  '${record.termLabel}$officeLabel.'
                  '${record.hasContract ? ' Your new Contract of Appointment has been prepared.' : ''}'
            : 'Your Student Assistant appointment will not be renewed for '
                  '${record.termLabel}.'
                  '${record.remarks.isNotEmpty ? ' Remarks: ${record.remarks}' : ''}',
        type: 'rehire',
        createdAt: _formattedToday(),
      ),
    );
    _notifyOfficeUsers(
      {
        ...currentOffices.expand((o) => o.headIds),
        ...?office?.headIds,
      },
      title: rehire ? 'Student Assistant Rehired' : 'Student Assistant Not Rehired',
      message: rehire
          ? '${user.name} was rehired for ${record.termLabel}$officeLabel.'
          : '${user.name} will not be rehired for ${record.termLabel}.',
    );
    notifyListeners();
    return null;
  }

  /// Puts a pending decision into effect now, without waiting for its term
  /// to start. Returns an error message, or null on success.
  Future<String?> applyRehireDecisionNow(RehireRecord record) async {
    try {
      await _applyRehireRecord(record);
      notifyListeners();
      return null;
    } catch (error) {
      debugPrint('Failed to apply rehire decision: $error');
      return 'Could not apply the decision: $error';
    }
  }

  /// Retries the Contract of Appointment for a rehire whose contract
  /// couldn't be generated when the decision was made.
  Future<String?> generateRehireContract(RehireRecord record) async {
    final user = users.where((u) => u.id == record.studentId).firstOrNull;
    final office = offices
        .where((o) => o.id == record.officeIds.firstOrNull)
        .firstOrNull;
    if (user == null || office == null) {
      return 'The student or their office could not be found.';
    }
    try {
      final updated = await _attachRehireContract(record, user, office);
      _firestoreService ??= FirestoreService();
      await _firestoreService!.setRehireRecord(updated);
      rehireRecords = rehireRecords
          .map((r) => r.id == updated.id ? updated : r)
          .toList();
      notifyListeners();
      return null;
    } catch (error) {
      debugPrint('Failed to generate rehire contract: $error');
      return 'Could not generate the contract: $error';
    }
  }

  /// Generates the Contract of Appointment for a rehired student's new
  /// term, uploads it, and files it under the student so it shows up in
  /// Student Documents.
  Future<RehireRecord> _attachRehireContract(
    RehireRecord record,
    User user,
    Office office,
  ) async {
    final today = DateTime.now();
    final termStart = RehireRecord.termStart(
      record.academicYear,
      record.semester,
    );
    final startDate = termStart == null || termStart.isBefore(today)
        ? today
        : termStart;
    final raw = await const AppointmentDocumentService()
        .generateContractOfAppointment(
          application: Application(
            id: record.id,
            announcementId: '',
            announcementTitle: 'Rehire - ${record.termLabel}',
            applicantId: user.id,
            applicantName: user.name,
            appliedAt: record.decidedAt,
            status: 'Approved',
          ),
          applicant: user,
          officeName: office.name,
          supervisorName: office.headNames.isNotEmpty
              ? office.headNames.join(', ')
              : 'Office Supervisor',
          supervisorRole: 'Supervisor',
          startDate: AppointmentDocumentService.formatDate(startDate),
          endDate: 'End of ${record.termLabel}',
        );
    final bytes = raw.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('The contract document came out empty.');
    }

    // Same 'reports/<uploaderUid>/<timestamp>/<file>' shape the Head's other
    // uploads use, which the upload-document function accepts.
    final uploaderUid =
        fb_auth.FirebaseAuth.instance.currentUser?.uid ??
        currentUser?.id ??
        'user';
    final storagePath =
        'reports/$uploaderUid/${today.millisecondsSinceEpoch}/${raw.fileName}';
    final downloadUrl = await SupabaseStorageService.instance.uploadDocument(
      bytes: bytes,
      path: storagePath,
      contentType: SupabaseStorageService.contentTypeForExtension('docx'),
    );

    final document = Document(
      id: '${record.id}_contract',
      name: 'Contract of Appointment (${record.termLabel})',
      fileName: raw.fileName,
      uploadedBy: currentUser?.name ?? '',
      uploadedAt: today.toIso8601String(),
      documentType: 'Contract',
      description: 'Contract of Appointment for ${record.termLabel} (rehire)',
      filePath: storagePath,
      fileSize: raw.fileSize,
      downloadUrl: downloadUrl,
      studentId: user.id,
      studentName: user.name,
    );
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setDocument(document);
    documents = [document, ...documents.where((d) => d.id != document.id)];

    return record.copyWith(
      contractDocumentId: document.id,
      contractFileName: raw.fileName,
      contractStoragePath: storagePath,
      contractDownloadUrl: downloadUrl,
    );
  }

  /// Puts a rehire decision into effect on the roster. Safe to run more
  /// than once: it only moves the student into the state the decision asks
  /// for.
  /// - Rehired: a Student Assistant (again, if they'd been let go) in the
  ///   decision's office, with their students record active and an SA ID.
  /// - Not Rehired: off every office, students record archived, and back to
  ///   the Student role — so they can apply again later. Their SA ID and
  ///   history are kept.
  Future<void> _applyRehireRecord(RehireRecord record) async {
    final user = users.where((u) => u.id == record.studentId).firstOrNull;
    if (user != null) {
      if (record.isRehired) {
        if (user.role == 'Student') {
          await changeUserRole(user.id, 'Student Assistant', notify: false);
        } else {
          await _setStudentRecordsStatus(user, 'Active');
        }
        final officeId = record.officeIds.firstOrNull;
        if (officeId != null) await _setAssistantOffice(user, officeId);
        await ensureStudentAssistantId(user.id);
      } else {
        await _setAssistantOffice(user, null);
        await _setStudentRecordsStatus(user, 'Archived');
        if (user.role == 'Student Assistant') {
          await changeUserRole(user.id, 'Student', notify: false);
        }
      }
    }

    final applied = record.copyWith(
      applied: true,
      appliedAt: DateTime.now().toIso8601String(),
    );
    _firestoreService ??= FirestoreService();
    await _firestoreService!.setRehireRecord(applied);
    rehireRecords = rehireRecords
        .map((r) => r.id == applied.id ? applied : r)
        .toList();
  }

  /// Applies every recorded rehire decision whose term has now started.
  Future<void> _applyDueRehireDecisions() async {
    final due = rehireRecords
        .where(
          (r) => !r.applied && rehireTermHasStarted(r.academicYear, r.semester),
        )
        .toList();
    for (final record in due) {
      try {
        await _applyRehireRecord(record);
      } catch (error) {
        debugPrint('Failed to apply rehire decision ${record.id}: $error');
      }
    }
  }

  /// Makes [officeId] the only office [user] is a student assistant in (the
  /// same one-office rule as [assignStudentAssistantsToOffice]); a null
  /// [officeId] takes them off every office.
  Future<void> _setAssistantOffice(User user, String? officeId) async {
    final name = user.name.trim().toLowerCase();
    bool isUser(String? id, String? assistantName) =>
        id == user.id ||
        (assistantName != null && assistantName.trim().toLowerCase() == name);

    for (final office in offices.toList()) {
      final ids = office.assistantIds;
      final names = office.assistantNames;
      final isMember = ids.contains(user.id) || names.any((n) => isUser(null, n));
      if (office.id == officeId) {
        if (isMember) continue;
        await saveOffice(
          office.copyWith(
            assistantIds: [...ids, user.id],
            assistantNames: [...names, user.name],
          ),
        );
      } else if (isMember) {
        // The id and name lists run in parallel, so drop the same position
        // from both.
        final keptIds = <String>[];
        final keptNames = <String>[];
        final length = ids.length > names.length ? ids.length : names.length;
        for (var i = 0; i < length; i++) {
          final id = i < ids.length ? ids[i] : null;
          final assistantName = i < names.length ? names[i] : null;
          if (isUser(id, assistantName)) continue;
          if (id != null) keptIds.add(id);
          if (assistantName != null) keptNames.add(assistantName);
        }
        await saveOffice(
          office.copyWith(assistantIds: keptIds, assistantNames: keptNames),
        );
      }
    }
  }

  AttendanceRecord? get activeAttendanceRecord {
    try {
      return filteredAttendance.firstWhere(
        (r) => !r.isArchived && !r.isInvalid && r.isActive,
      );
    } catch (_) {
      return null;
    }
  }

  /// When the current user's open session started, or null when they
  /// aren't clocked in or its time can't be read.
  DateTime? get activeDutyStart {
    final record = activeAttendanceRecord;
    if (record == null) return null;
    final day = _parseFormattedDate(record.date);
    if (day == null) return null;
    return _parseTime(record.timeIn, day);
  }

  /// Hours credited to the current user from finished sessions in the
  /// current Monday–Sunday week: the figure clock-attendance checks
  /// against [weeklyHourCap].
  double get myCreditedHoursThisWeek {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    return filteredAttendance
        .where((r) {
          if (r.isActive || r.isArchived || r.isInvalid) return false;
          final day = _parseFormattedDate(r.date);
          return day != null &&
              !day.isBefore(monday) &&
              day.isBefore(nextMonday);
        })
        .fold<double>(0, (total, r) => total + (r.totalHours ?? 0));
  }

  /// Hours credited to the current user from sessions finished today.
  double get myCreditedHoursToday {
    final today = _formattedToday();
    return filteredAttendance
        .where(
          (r) =>
              r.date == today && !r.isActive && !r.isArchived && !r.isInvalid,
        )
        .fold<double>(0, (total, r) => total + (r.totalHours ?? 0));
  }

  /// Whether one of the current user's sessions today was voided because
  /// they didn't time out before it ended.
  bool get myMissedTimeOutToday {
    final today = _formattedToday();
    return filteredAttendance.any(
      (r) => r.date == today && r.isInvalid && !r.isArchived,
    );
  }

  // ─── Dashboard Stats ───────────────────────────────
  Map<String, dynamic> get dashboardStats => {
    'totalStudents': filteredStudents.length,
    'activeToday': attendance
        .where(
          (a) =>
              !a.isArchived &&
              !a.isInvalid &&
              a.academicYear == academicYear &&
              a.isActive,
        )
        .length,
    'pendingReports': reports
        .where((r) => r.status == 'Pending' && r.academicYear == academicYear)
        .length,
    'avgHoursPerWeek': _computeAvgHoursPerWeek(),
  };

  String _computeAvgHoursPerWeek() {
    if (students.isEmpty) return '0';

    // Use attendance records in the last 28 days (4 weeks) to compute
    // a per-student weekly average. For each student, sum their
    // attendance totalHours (or compute from timeIn/timeOut when missing),
    // then divide by 4 to obtain weekly hours. Finally average across students.
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 28));

    // Map by student userId or studentName when userId is not present.
    final Map<String, double> hoursByStudent = {};

    for (final rec in attendance) {
      if (rec.isArchived || rec.academicYear != academicYear) continue;
      DateTime? recDate = _parseFormattedDate(rec.date);
      if (recDate == null) continue;
      if (recDate.isBefore(cutoff)) continue;

      double recHours = 0;
      if (rec.totalHours != null && rec.totalHours! > 0) {
        recHours = rec.totalHours!;
      } else if (rec.timeOut != null && rec.timeOut!.isNotEmpty) {
        final inDt = _parseTime(rec.timeIn, recDate);
        final outDt = _parseTime(rec.timeOut!, recDate);
        if (inDt != null && outDt != null && outDt.isAfter(inDt)) {
          recHours = outDt.difference(inDt).inMinutes / 60.0;
        }
      }

      final key = (rec.studentId != null && rec.studentId!.isNotEmpty)
          ? rec.studentId!
          : rec.studentName;
      hoursByStudent[key] = (hoursByStudent[key] ?? 0) + recHours;
    }

    double sumWeekly = 0;
    for (final s in students) {
      final key = (s.userId != null && s.userId!.isNotEmpty)
          ? s.userId!
          : s.name;
      final totalHours = hoursByStudent[key] ?? 0;
      final weekly = totalHours / 4.0;
      sumWeekly += weekly;
    }

    final avg = sumWeekly / students.length;
    return avg.toStringAsFixed(1);
  }

  DateTime? _parseFormattedDate(String dateStr) {
    // Expected format: 'Mon D, YYYY' e.g. 'Jan 5, 2026'
    try {
      final parts = dateStr.split(' ');
      if (parts.length < 3) return null;
      final monthStr = parts[0];
      final dayStr = parts[1].replaceAll(',', '');
      final yearStr = parts[2];
      final months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final m = months[monthStr];
      if (m == null) return null;
      final d = int.tryParse(dayStr);
      final y = int.tryParse(yearStr);
      if (d == null || y == null) return null;
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseTime(String timeStr, DateTime baseDate) {
    // Expected format: 'h:mm AM' or 'hh:mm PM'
    try {
      final parts = timeStr.split(' ');
      if (parts.length < 2) return null;
      final hm = parts[0].split(':');
      if (hm.length != 2) return null;
      final hour = int.tryParse(hm[0]);
      final minute = int.tryParse(hm[1]);
      final period = parts[1].toUpperCase();
      if (hour == null || minute == null) return null;
      var h = hour % 12;
      if (period == 'PM') h += 12;
      return DateTime(baseDate.year, baseDate.month, baseDate.day, h, minute);
    } catch (_) {
      return null;
    }
  }

  Future<void> checkSystemStatus() async {
    _firestoreService ??= FirestoreService();
    // Check Firestore latency
    try {
      final ping = await _firestoreService!.pingAnnouncements();
      if (ping >= 0) {
        dbHealthy = true;
        responseTimeMs = ping;
      } else {
        dbHealthy = false;
        responseTimeMs = 0;
      }
    } catch (_) {
      dbHealthy = false;
      responseTimeMs = 0;
    }

    // Auth service reachable
    try {
      final _ = fb_auth.FirebaseAuth.instance;
      authHealthy = true;
    } catch (_) {
      authHealthy = false;
    }

    // Reports collection check
    try {
      final pingR = await _firestoreService!.pingReports();
      reportsHealthy = pingR >= 0;
    } catch (_) {
      reportsHealthy = false;
    }

    notifyListeners();
  }

  /// Count of student assistants per campus, in the same order as [campuses].
  /// Students whose campus doesn't match a known campus are simply not counted.
  Map<String, int> get studentsPerCampus {
    final counts = {for (final c in campuses) c: 0};
    for (final s in effectiveStudents) {
      final campus = s.campus;
      if (campus != null && counts.containsKey(campus)) {
        counts[campus] = counts[campus]! + 1;
      }
    }
    return counts;
  }

  /// Count of student assistants per department, scoped to a single campus.
  /// Only departments with at least one student assistant on that campus are included.
  Map<String, int> departmentBreakdownForCampus(String campus) {
    final counts = <String, int>{};
    for (final s in effectiveStudents) {
      if (s.campus != campus) continue;
      counts[s.department] = (counts[s.department] ?? 0) + 1;
    }
    return counts;
  }

  /// School years shown on the campus growth chart: the current year (with
  /// real enrollment counts) followed by upcoming years left empty until
  /// that data exists.
  List<String> get growthYears => const [
    'AY 2025-2026',
    'AY 2026-2027',
    'AY 2027-2028',
  ];

  /// Student-assistant headcount per campus for [growthYears]. Only the
  /// current school year (index 0) is populated, from the real student
  /// roster — future years are left null (no data yet) rather than faked.
  Map<String, List<int?>> get campusGrowthTrend {
    final current = studentsPerCampus;
    return {
      for (final c in campuses) c: [current[c] ?? 0, null, null],
    };
  }

  String _formattedToday() {
    final now = DateTime.now();
    const months = [
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
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}
