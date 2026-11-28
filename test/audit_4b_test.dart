import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

class _Store extends FirestoreService {}

User _user(
  String id,
  String name,
  String role, {
  String status = 'Active',
  String? requestedRole,
}) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  role: role,
  status: status,
  requestedRole: requestedRole,
);

Evaluation _evaluation(String id, String studentId, String name) => Evaluation(
  id: id,
  studentId: studentId,
  studentName: name,
  office: 'Library',
  term: 'First Semester',
  periodCovered: 'Aug to Dec 2026',
  dateOfRating: '11/11/2026',
  eligibleForRehire: true,
  ratings: const {},
  overallRating: 4,
  departmentHeadComments: '',
  supervisorId: 'sv1',
  supervisorName: 'Sue Supervisor',
  status: 'Submitted',
);

void main() {
  late AppState state;
  setUp(() => state = AppState(firestoreService: _Store()));

  group('same-name students', () {
    final supervisor = _user('sv1', 'Sue Supervisor', 'Supervisor');
    final mine = _user('sa1', 'Ana Reyes', 'Student Assistant');
    final namesake = _user('sa9', 'Ana Reyes', 'Student Assistant');

    setUp(() {
      state
        ..currentUser = supervisor
        ..users = [supervisor, mine, namesake]
        ..offices = const [
          Office(
            id: 'o1',
            name: 'Library',
            code: 'LIB',
            headIds: ['sv1'],
            headNames: ['Sue Supervisor'],
            assistantIds: ['sa1'],
            assistantNames: ['Ana Reyes'],
          ),
          Office(
            id: 'o2',
            name: 'Registrar',
            code: 'REG',
            assistantIds: ['sa9'],
            assistantNames: ['Ana Reyes'],
          ),
        ]
        ..evaluations = [
          _evaluation('e1', 'sa1', 'Ana Reyes'),
          _evaluation('e9', 'sa9', 'Ana Reyes'),
        ]
        ..reports = [
          Report(
            id: 'r9',
            applicantId: 'sa9',
            title: 'Week 1',
            content: '',
            studentName: 'Ana Reyes',
            status: 'Pending',
          ),
          // Saved before reports carried the student's id.
          Report(
            id: 'r0',
            title: 'Old week',
            content: '',
            studentName: 'Ana Reyes',
            status: 'Approved',
          ),
        ];
    });

    test("a Supervisor sees only their own student's evaluation", () {
      expect(state.filteredEvaluations.map((e) => e.id), ['e1']);
    });

    test("another office's namesake's report stays out; an old report "
        'without an id goes by the name', () {
      expect(state.filteredReports.map((r) => r.id), ['r0']);
    });

    test("the rehire decision follows the person's own evaluation", () {
      expect(state.latestEvaluationForUser(namesake)?.id, 'e9');
      expect(state.latestEvaluationForUser(mine)?.id, 'e1');
    });

    test('someone the office lists by name alone still counts by their '
        'account', () {
      state.offices = [
        state.offices.first.copyWith(
          assistantIds: [''],
          assistantNames: ['Ana Reyes'],
        ),
        state.offices.last,
      ];
      // sa1's evaluation is theirs (listed by name); sa9's is in Registrar.
      expect(state.filteredEvaluations.map((e) => e.id), contains('e1'));
    });
  });

  group('mentions', () {
    test('a staff sign-up waiting for the Head, or declined, is not '
        'mentioned', () {
      state.users = [
        _user(
          's1',
          'Pat Pending',
          'Student',
          status: 'Pending',
          requestedRole: 'Supervisor',
        ),
        _user(
          's2',
          'Dee Declined',
          'Student',
          status: 'Declined',
          requestedRole: 'Head',
        ),
        _user('s3', 'Ana Reyes', 'Student'),
      ];
      final found = state.mentionedUsers(
        '@Pat Pending @Dee Declined @Ana Reyes',
      );
      expect(found.map((u) => u.id), ['s3']);
    });

    test('a mention notification finds its announcement, whose id has an '
        'underscore', () {
      state.announcements = [
        Announcement(
          id: 'ann_1700000000000',
          title: 'Orientation',
          body: 'See you there',
          postedBy: 'Hana Head',
          postedByRole: 'Head',
          postedAt: '2026-11-28',
        ),
      ];
      AppNotification note(String id) => AppNotification(
        id: id,
        userId: 'sa_1',
        title: 'You were mentioned',
        message: '',
        type: 'announcement',
        createdAt: 'Nov 28, 2026',
      );
      expect(
        state
            .announcementMentionedIn(note('mention_ann_1700000000000_sa_1'))
            ?.id,
        'ann_1700000000000',
      );
      expect(state.announcementMentionedIn(note('n_123_sa_1')), isNull);
      expect(
        state.announcementMentionedIn(note('mention_ann_gone_sa_1')),
        isNull,
      );
    });
  });

  test(
    'a skill or department name with "/" is refused before saving',
    () async {
      expect(AppState.listNameProblem('UI/UX Design'), contains('/'));
      expect(AppState.listNameProblem('__name__'), isNotNull);
      expect(AppState.listNameProblem('..'), isNotNull);
      expect(AppState.listNameProblem('UI-UX Design'), isNull);
      state.currentUser = _user('h1', 'Hana Head', 'Head');
      expect(await state.addSkill('UI/UX Design'), isFalse);
      expect(await state.addDepartment('A/B'), isFalse);
    },
  );
}
