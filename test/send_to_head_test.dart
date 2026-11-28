import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Keeps forwards, reports and notifications in memory.
class _Store extends FirestoreService {
  final forwards = <String, HeadForward>{};
  final reports = <String, Report>{};
  final notifications = <Map<String, dynamic>>[];

  /// The next report save fails (a dropped connection, say).
  bool failNextReportSave = false;

  @override
  Future<bool> addHeadForwardOnce(String id, HeadForward forward) async {
    if (forwards.containsKey(id)) return false;
    forwards[id] = forward;
    return true;
  }

  @override
  Future<String> addHeadForward(HeadForward forward) async {
    final id = 'auto_${forwards.length}';
    forwards[id] = forward;
    return id;
  }

  @override
  Future<void> setReport(Report r) async {
    if (failNextReportSave) {
      failNextReportSave = false;
      throw Exception('unavailable');
    }
    reports[r.id] = r;
  }

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);
}

final _supervisor = User(
  id: 'sup1',
  name: 'Sid Supervisor',
  email: 'sup@example.com',
  role: 'Supervisor',
);
final _head = User(
  id: 'head1',
  name: 'Hana Head',
  email: 'head@example.com',
  role: 'Head',
);
User _assistant(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  role: 'Student Assistant',
);

Report _report({String? applicantId, String name = 'Ana Reyes'}) => Report(
  id: 'r1',
  applicantId: applicantId,
  title: 'Week 1',
  content: 'Did things',
  studentName: name,
  status: 'Approved',
);

void main() {
  late _Store store;
  late AppState state;

  setUp(() {
    store = _Store();
    state = AppState(firestoreService: store)
      ..currentUser = _supervisor
      ..users = [_supervisor, _head, _assistant('sa1', 'Ana Reyes')]
      ..offices = const [
        Office(
          id: 'o1',
          name: 'Library',
          code: 'LIB',
          headIds: ['sup1'],
          headNames: ['Sid Supervisor'],
          assistantIds: ['sa1'],
          assistantNames: ['Ana Reyes'],
        ),
      ];
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a send that failed half way can be retried without a second '
      'forward', () async {
    state.reports = [_report(applicantId: 'sa1')];
    store.failNextReportSave = true;

    await expectLater(state.sendReportToHead('r1'), throwsException);
    // The forward went first; the report isn't marked sent, so the button
    // is still there.
    expect(store.forwards.keys, ['report_r1']);
    expect(state.reports.single.sentToHead, isFalse);

    expect(await state.sendReportToHead('r1'), isTrue);
    await settle();

    expect(store.forwards.keys, ['report_r1']);
    expect(store.reports['r1']!.sentToHead, isTrue);
    // The Head was told once.
    expect(
      store.notifications.where((n) => n['type'] == 'head_forward'),
      hasLength(1),
    );
  });

  test('an older report without a student id is forwarded under the '
      "student's account", () async {
    state.reports = [_report()];

    expect(await state.sendReportToHead('r1'), isTrue);

    expect(store.forwards['report_r1']!.studentId, 'sa1');
  });

  test(
    'a report whose student can\'t be told apart is not forwarded',
    () async {
      state.users = [...state.users, _assistant('sa2', 'Ana Reyes')];
      state.offices = [
        state.offices.single.copyWith(
          assistantIds: ['sa1', 'sa2'],
          assistantNames: ['Ana Reyes', 'Ana Reyes'],
        ),
      ];
      state.reports = [_report()];

      await expectLater(
        state.sendReportToHead('r1'),
        throwsA(isA<SendToHeadProblem>()),
      );
      expect(store.forwards, isEmpty);
      expect(store.reports, isEmpty);
    },
  );
}
