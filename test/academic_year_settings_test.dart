import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Keeps the academic year settings and archive list in memory, and pushes
/// every save to the settings listener the way Firestore would.
class _FakeSettingsFirestore extends FirestoreService {
  Map<String, dynamic>? settings;
  final archives = <String, Map<String, dynamic>>{};
  final _settingsDoc = StreamController<Map<String, dynamic>?>.broadcast();

  void push(Map<String, dynamic> data) {
    settings = Map.of(data);
    _settingsDoc.add(Map.of(data));
  }

  @override
  Future<Map<String, dynamic>?> getAcademicYearSettings() async =>
      settings == null ? null : Map.of(settings!);

  @override
  Future<void> saveAcademicYearSettings(Map<String, dynamic> data) async =>
      push(data);

  @override
  Future<void> archiveAcademicYearSettings(
    String academicYear,
    Map<String, dynamic> settings, {
    bool archiveAttendance = false,
    Map<String, int>? headcountByCampus,
  }) async {
    archives.putIfAbsent(
      academicYear,
      () => {
        'academicYear': academicYear,
        'archiveAttendance': archiveAttendance,
        'dataArchived': false,
        'headcountByCampus': ?headcountByCampus,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getAcademicYearArchives() async => [
    for (final entry in archives.entries) {...entry.value, 'id': entry.key},
  ];

  @override
  Future<void> deleteUnprocessedAcademicYearArchive(String academicYear) async {
    if (archives[academicYear]?['dataArchived'] == false) {
      archives.remove(academicYear);
    }
  }

  @override
  Stream<Map<String, dynamic>?> docStream(String collection, String id) =>
      id == 'academic_year_settings'
      ? _settingsDoc.stream
      : const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> collectionStream(
    String collection, {
    bool newestFirst = false,
  }) => const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> whereStream(
    String collection,
    String field,
    Object value, {
    bool newestFirst = false,
  }) => const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> whereInStream(
    String collection,
    String field,
    List<Object> values,
  ) => const Stream.empty();

  @override
  Future<List<String>> getStudentIdsForUser(String uid) async => [];
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final _admin = User(
  id: 'admin1',
  name: 'Ana Admin',
  email: 'admin@example.com',
  role: 'Admin',
);

final _firstSemester = <String, dynamic>{
  'academicYear': '2026-2027',
  'semester': '1st Semester',
  'startDate': DateTime(2026, 8, 1).toIso8601String(),
  'endDate': DateTime(2027, 7, 31).toIso8601String(),
  'autoArchiveLogs': true,
  'milestones': [
    {
      'title': 'Application deadline',
      'date': DateTime(2026, 8, 15).toIso8601String(),
    },
  ],
};

Future<(AppState, _FakeSettingsFirestore)> _signedIn() async {
  final fake = _FakeSettingsFirestore()..settings = Map.of(_firstSemester);
  final state = AppState(firestoreService: fake)..currentUser = _admin;
  await state.init();
  fake.push(_firstSemester);
  await _settle();
  return (state, fake);
}

Future<void> _save(
  AppState state, {
  required String year,
  required String semester,
  bool allowApplications = true,
  List<Map<String, dynamic>> milestones = const [],
}) {
  final firstYear = int.parse(year.substring(0, 4));
  return state.updateAcademicYearSettings(
    year: year,
    semester: semester,
    startDate: DateTime(firstYear, 8, 1),
    endDate: DateTime(firstYear + 1, 7, 31),
    allowApplications: allowApplications,
    enforceHourCap: true,
    autoArchiveLogs: true,
    milestones: milestones,
  );
}

void main() {
  test('moving to the next year can be undone', () async {
    final (state, fake) = await _signedIn();

    await _save(state, year: '2027-2028', semester: '1st Semester');
    expect(fake.archives.keys, ['2026-2027']);
    expect(state.canUndoTermChange, isTrue);
    expect(state.previousTermLabel, '1st Semester, AY 2026-2027');

    await state.undoTermChange();
    await _settle();

    expect(state.academicYear, '2026-2027');
    expect(state.academicSemester, '1st Semester');
    expect(state.academicYearEnd, DateTime(2027, 7, 31));
    // The new year was saved without them; they come back with the year.
    expect(state.academicMilestones.map((m) => m['title']), [
      'Application deadline',
    ]);
    expect(fake.archives, isEmpty);
    expect(state.academicYearArchives, isEmpty);
    // So the Head's session moves records made meanwhile back.
    expect(fake.settings!['undoneAcademicYear'], '2027-2028');
    expect(state.canUndoTermChange, isFalse);
  });

  test('moving to the next year saves its headcount per campus', () async {
    final (state, fake) = await _signedIn();
    state.students = [
      for (final (id, campus) in const [
        ('s1', 'Boac Campus'),
        ('s2', 'Boac Campus'),
        ('s3', 'Gasan Campus'),
      ])
        Student(
          id: id,
          name: 'Student $id',
          email: '$id@example.com',
          department: 'College of Information and Computing Sciences',
          campus: campus,
        ),
    ];

    await _save(state, year: '2027-2028', semester: '1st Semester');
    expect(fake.archives['2026-2027']!['headcountByCampus'], {
      'Boac Campus': 2,
      'Mogpog Campus': 0,
      'Sta. Cruz Campus': 0,
      'Torrijos Campus': 0,
      'Gasan Campus': 1,
    });

    // As the Head's dashboard reads it back.
    state.academicYearArchives = await fake.getAcademicYearArchives();
    expect(
      [
        for (final year in state.enrollmentHistory)
          (year.academicYear, year.byCampus['Boac Campus']),
      ],
      [('2026-2027', 2), ('2027-2028', 2)],
    );
  });

  test('saving other settings keeps the change undoable', () async {
    final (state, fake) = await _signedIn();

    await _save(state, year: '2027-2028', semester: '1st Semester');
    await _save(
      state,
      year: '2027-2028',
      semester: '1st Semester',
      allowApplications: false,
    );

    expect(state.canUndoTermChange, isTrue);
    expect(state.previousTermLabel, '1st Semester, AY 2026-2027');

    await state.undoTermChange();
    await _settle();

    expect(state.academicYear, '2026-2027');
    // Only the term goes back.
    expect(state.allowAcademicApplications, isFalse);
  });

  test('a change can no longer be undone once the window has passed', () async {
    final (state, fake) = await _signedIn();

    fake.push({
      ..._firstSemester,
      'academicYear': '2027-2028',
      'previous': {..._firstSemester},
      'termChangedAt': DateTime.now()
          .subtract(AppState.termChangeUndoWindow + const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    });
    await _settle();

    expect(state.canUndoTermChange, isFalse);
    await expectLater(state.undoTermChange(), throwsStateError);
    expect(state.academicYear, '2027-2028');
  });

  test('rehire decisions for a new term wait until its change can no longer be '
      'undone', () async {
    final (state, fake) = await _signedIn();

    await _save(state, year: '2026-2027', semester: '2nd Semester');

    expect(state.rehireTermHasStarted('2026-2027', '1st Semester'), isTrue);
    expect(state.rehireTermHasStarted('2026-2027', '2nd Semester'), isFalse);

    fake.push({
      ...fake.settings!,
      'termChangedAt': DateTime.now()
          .subtract(AppState.termChangeUndoWindow + const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    });
    await _settle();

    expect(state.rehireTermHasStarted('2026-2027', '2nd Semester'), isTrue);
  });

  test('counts the days left until the academic year ends', () async {
    final (state, fake) = await _signedIn();
    final now = DateTime.now();

    Future<int> daysLeftWhenEndingIn(int days) async {
      final end = DateTime(now.year, now.month, now.day + days);
      fake.push({..._firstSemester, 'endDate': end.toIso8601String()});
      await _settle();
      return state.daysUntilAcademicYearEnds;
    }

    expect(await daysLeftWhenEndingIn(14), 14);
    expect(await daysLeftWhenEndingIn(0), 0);
    expect(await daysLeftWhenEndingIn(-1), -1);
  });
}
