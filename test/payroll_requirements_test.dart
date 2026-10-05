import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Records what the app saves.
class _FakeFirestore extends FirestoreService {
  final notifications = <Map<String, dynamic>>[];
  final items = <String, PayrollCheckMark?>{};
  final exclusions = <String, PayrollExclusion?>{};
  final payroll = <String, Map<String, dynamic>>{};

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);

  @override
  Future<void> setPayrollCheckItem({
    required String studentId,
    required String studentName,
    required String key,
    required PayrollCheckMark? mark,
  }) async => items['$studentId/$key'] = mark;

  @override
  Future<void> setPayrollExclusion({
    required String studentId,
    required String studentName,
    required String termLabel,
    required PayrollExclusion? exclusion,
  }) async => exclusions['$studentId/$termLabel'] = exclusion;

  @override
  Future<bool> createPayrollRecord(PayrollRecord record) async {
    if (payroll.containsKey(record.id)) return false;
    payroll[record.id] = record.toJson();
    return true;
  }
}

const _term = '1st Semester, AY 2026-2027';
final _start = DateTime(2026, 8, 1);
final _end = DateTime(2026, 12, 31);

User _assistant(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  role: 'Student Assistant',
);

AttendanceRecord _hours(String id, String studentId, String date) =>
    AttendanceRecord(
      id: id,
      studentId: studentId,
      studentName: studentId,
      date: date,
      timeIn: '8:00 AM',
      timeOut: '12:00 PM',
      totalHours: 4,
    );

const _checked = PayrollCheckMark(
  status: PayrollCheckMark.checked,
  by: 'Hana Head',
  at: '2026-12-01T09:00:00.000',
);

/// Every requirement checked for a student who worked in [months] of 2026.
PayrollCheck _allChecked(String studentId, List<int> months) => PayrollCheck(
  studentId: studentId,
  items: {
    PayrollRequirement.requirementsKey: _checked,
    PayrollRequirement.endorsementKey: _checked,
    PayrollRequirement.contractKey(_term): _checked,
    for (final m in months) PayrollRequirement.dtrKey(2026, m): _checked,
  },
);

HeadForward _dtr(String id, String studentId, String month, String sentAt) =>
    HeadForward(
      id: id,
      type: 'dtr_report',
      studentId: studentId,
      studentName: studentId,
      title: 'DTR/Accomplishment Report ($month)',
      fileName: '$id.docx',
      storagePath: 'reports/sv1/$id.docx',
      sentByName: 'Sam Supervisor',
      sentById: 'sv1',
      sentAt: sentAt,
    );

void main() {
  late _FakeFirestore fake;
  late AppState state;

  setUp(() {
    fake = _FakeFirestore();
    state = AppState(firestoreService: fake)
      ..currentUser = User(
        id: 'head1',
        name: 'Hana Head',
        email: 'head@example.com',
        role: 'Head',
      )
      ..users = [_assistant('sa1', 'Ana Reyes'), _assistant('sa2', 'Ben Cruz')]
      ..offices = [
        const Office(
          id: 'o1',
          name: 'Registrar',
          code: 'REG',
          headIds: ['sv1'],
          headNames: ['Sam Supervisor'],
          assistantIds: ['sa1', 'sa2'],
          assistantNames: ['Ana Reyes', 'Ben Cruz'],
        ),
      ]
      ..attendance = [
        _hours('a1', 'sa1', 'Sep 10, 2026'),
        _hours('a2', 'sa1', 'Oct 8, 2026'),
        _hours('b1', 'sa2', 'Sep 11, 2026'),
      ];
  });

  List<PayrollRecord> preview() => state.buildPayrollPreview(
    start: _start,
    endInclusive: _end,
    periodLabel: _term,
  );

  PayrollRecord rowOf(String id) =>
      preview().firstWhere((r) => r.studentId == id);

  group('checklist', () {
    test('lists the requirements and a DTR for each month worked', () {
      expect(rowOf('sa1').requirements.map((r) => r.key), [
        'requirements',
        'endorsement',
        'contract|$_term',
        'dtr|2026-09',
        'dtr|2026-10',
      ]);
      // Months without hours need no DTR.
      expect(
        rowOf(
          'sa2',
        ).requirements.where((r) => r.kind == PayrollRequirementKind.dtr),
        hasLength(1),
      );
    });

    test('finds the files the Head checks', () {
      state
        ..applications = [
          Application(
            id: 'app1',
            announcementId: 'ann1',
            announcementTitle: 'Registrar',
            applicantId: 'sa1',
            applicantName: 'Ana Reyes',
            appliedAt: '2026-07-20T10:00:00.000',
            status: 'Approved',
            submittedDocuments: [
              ApplicationDocument(
                id: 'd1',
                applicationId: 'app1',
                requirementName: 'Certificate of Registration',
                fileName: 'cor.pdf',
                uploadedAt: '2026-07-20T10:00:00.000',
              ),
              ApplicationDocument(
                id: 'd2',
                applicationId: 'app1',
                requirementName: 'Contract of Appointment',
                fileName: 'contract-of-appointment-ana.docx',
                uploadedAt: '2026-07-25T10:00:00.000',
              ),
              ApplicationDocument(
                id: 'd3',
                applicationId: 'app1',
                requirementName: 'Endorsement Letter',
                fileName: 'endorsement-letter-ana.docx',
                uploadedAt: '2026-07-25T10:00:00.000',
              ),
            ],
          ),
        ]
        ..headForwards = [_dtr('f1', 'sa1', 'September 2026', 'Oct 2, 2026')];

      final files = {
        for (final r in rowOf('sa1').requirements)
          r.key: [for (final f in r.files) f.ref],
      };
      expect(files['requirements'], ['d1']);
      expect(files['endorsement'], ['d3']);
      expect(files['contract|$_term'], ['d2']);
      expect(files['dtr|2026-09'], ['f1']);
      expect(files['dtr|2026-10'], isEmpty);
    });

    test("a rehire's contract is the one for its own term", () {
      RehireRecord rehire(String id, String semester) => RehireRecord(
        id: id,
        studentId: 'sa1',
        studentName: 'Ana Reyes',
        academicYear: '2026-2027',
        semester: semester,
        decision: RehireRecord.rehired,
        decidedById: 'head1',
        decidedByName: 'Hana Head',
        decidedAt: '2026-07-30T10:00:00.000',
        contractDocumentId: '${id}_contract',
        contractStoragePath: 'reports/head1/$id.docx',
      );
      state.rehireRecords = [
        rehire('r1', '1st Semester'),
        rehire('r2', '2nd Semester'),
      ];

      final contract = rowOf('sa1').requirements.firstWhere(
        (r) => r.kind == PayrollRequirementKind.contract,
      );
      expect(contract.files.map((f) => f.ref), ['r1_contract']);
    });

    test('reads the month off a forwarded DTR', () {
      expect(_dtr('f', 'sa1', 'September 2026', '').dtrMonth, (2026, 9));
      expect(
        HeadForward(
          id: 'e',
          type: 'evaluation',
          studentId: 'sa1',
          studentName: 'Ana',
          title: 'Performance Evaluation (1st Semester)',
          fileName: 'e.docx',
          sentByName: 'Sam',
          sentAt: '',
        ).dtrMonth,
        isNull,
      );
    });

    test('term dates', () {
      expect(
        RehireRecord.termEnd('2026-2027', '1st Semester'),
        DateTime(2026, 12, 31),
      );
      expect(
        RehireRecord.termEnd('2026-2027', '2nd Semester'),
        DateTime(2027, 5, 31),
      );
      expect(
        RehireRecord.termEnd('2026-2027', 'Summer'),
        DateTime(2027, 7, 31),
      );
    });
  });

  group('the whole payroll waits', () {
    test('one student not checked holds up everyone', () async {
      state.payrollChecks = [
        _allChecked('sa1', [9, 10]),
      ];

      final rows = preview();
      expect(
        {for (final r in rows) r.studentId: r.status},
        {'sa1': 'Ready', 'sa2': 'Incomplete'},
      );
      expect(AppState.payrollHeldBy(rows).map((r) => r.studentId), ['sa2']);
      await expectLater(state.approvePayroll(rows), throwsStateError);
      expect(fake.payroll, isEmpty);
    });

    test('once everyone is checked, everyone is approved', () async {
      state.payrollChecks = [
        _allChecked('sa1', [9, 10]),
        _allChecked('sa2', [9]),
      ];

      final (count, total) = await state.approvePayroll(preview());

      expect(count, 2);
      expect(total, 12 * PayrollRecord.ratePerHour);
    });

    test('a student left out no longer holds it up, and is not paid', () async {
      state.payrollChecks = [
        _allChecked('sa1', [9, 10]),
        const PayrollCheck(
          studentId: 'sa2',
          exclusions: {
            _term: PayrollExclusion(
              reason: 'Resigned',
              by: 'Hana Head',
              at: '2026-12-01',
            ),
          },
        ),
      ];

      final rows = preview();
      expect(rowOf('sa2').status, 'Excluded');
      expect(rowOf('sa2').isPayable, isFalse);
      expect((await state.approvePayroll(rows)).$1, 1);
      expect(fake.payroll.keys.single, contains('sa1'));
    });

    test("a student with no hours doesn't hold it up", () {
      state
        ..users = [...state.users, _assistant('sa3', 'Cy Tan')]
        ..payrollChecks = [
          _allChecked('sa1', [9, 10]),
          _allChecked('sa2', [9]),
        ];

      expect(rowOf('sa3').status, 'No hours');
      expect(AppState.payrollHeldBy(preview()), isEmpty);
    });

    test("one month's check doesn't cover another", () {
      state.payrollChecks = [
        _allChecked('sa1', [9]),
      ];

      final row = rowOf('sa1');
      expect(row.status, 'Incomplete');
      expect(row.unchecked.map((r) => r.key), ['dtr|2026-10']);
    });
  });

  group('the Head', () {
    test('checking saves the mark and counts at once', () async {
      state.headForwards = [_dtr('f1', 'sa2', 'September 2026', 'Oct 2, 2026')];
      final row = rowOf('sa2');
      final dtr = row.requirements.firstWhere(
        (r) => r.kind == PayrollRequirementKind.dtr,
      );

      await state.checkPayrollRequirement(row, dtr);

      expect(fake.items['sa2/dtr|2026-09']?.isChecked, isTrue);
      expect(fake.items['sa2/dtr|2026-09']?.fileRef, 'f1');
      expect(fake.items['sa2/dtr|2026-09']?.by, 'Hana Head');
      expect(
        rowOf('sa2').unchecked.map((r) => r.key),
        isNot(contains('dtr|2026-09')),
      );
    });

    test(
      'returning one tells the student, their supervisor and the sender',
      () async {
        // Sent by a supervisor from another office.
        state.headForwards = [
          HeadForward(
            id: 'f1',
            type: 'dtr_report',
            studentId: 'sa2',
            studentName: 'Ben Cruz',
            title: 'DTR/Accomplishment Report (September 2026)',
            fileName: 'f1.docx',
            sentByName: 'Other Supervisor',
            sentById: 'sv2',
            sentAt: 'Oct 2, 2026',
          ),
        ];
        final row = rowOf('sa2');
        final dtr = row.requirements.firstWhere(
          (r) => r.kind == PayrollRequirementKind.dtr,
        );

        await state.returnPayrollRequirement(
          row,
          dtr,
          '  Sep 12 has no time-out ',
        );

        final mark = fake.items['sa2/dtr|2026-09']!;
        expect(mark.isReturned, isTrue);
        expect(mark.note, 'Sep 12 has no time-out');
        expect(fake.notifications.map((n) => n['userId']).toSet(), {
          'sa2',
          'sv1',
          'sv2',
        });
        expect(
          fake.notifications.every((n) => n['type'] == 'payroll_requirement'),
          isTrue,
        );
        expect(rowOf('sa2').status, 'Incomplete');
      },
    );

    test('a copy sent after a return is flagged to check again', () {
      state
        ..headForwards = [
          _dtr('old', 'sa2', 'September 2026', 'Oct 2, 2026'),
          _dtr('new', 'sa2', 'September 2026', 'Oct 2, 2026'),
        ]
        ..payrollChecks = [
          const PayrollCheck(
            studentId: 'sa2',
            items: {
              'dtr|2026-09': PayrollCheckMark(
                status: PayrollCheckMark.returned,
                note: 'Wrong month',
                by: 'Hana Head',
                at: '2026-10-02T09:00:00.000',
                fileRef: 'old',
              ),
            },
          ),
        ];

      final dtr = rowOf(
        'sa2',
      ).requirements.firstWhere((r) => r.kind == PayrollRequirementKind.dtr);
      // Same day: the returned copy goes behind the new one.
      expect(dtr.files.map((f) => f.ref), ['new', 'old']);
      expect(dtr.isResent, isTrue);
      expect(dtr.needsAction, isFalse);

      state.headForwards = [
        _dtr('old', 'sa2', 'September 2026', 'Oct 2, 2026'),
      ];
      final waiting = rowOf(
        'sa2',
      ).requirements.firstWhere((r) => r.kind == PayrollRequirementKind.dtr);
      expect(waiting.isResent, isFalse);
      expect(waiting.needsAction, isTrue);
    });

    test('leaving out and putting back', () async {
      await state.excludeFromPayroll(rowOf('sa2'), ' Resigned in October ');

      expect(fake.exclusions['sa2/$_term']?.reason, 'Resigned in October');
      expect(rowOf('sa2').status, 'Excluded');
      expect(fake.notifications.single['userId'], 'sa2');

      await state.includeInPayroll(rowOf('sa2'));

      expect(fake.exclusions['sa2/$_term'], isNull);
      expect(rowOf('sa2').status, 'Incomplete');
    });

    test("reminders name only what's missing, not what waits for the Head", () {
      state
        ..headForwards = [_dtr('f1', 'sa1', 'September 2026', 'Oct 2, 2026')]
        ..payrollChecks = [
          PayrollCheck(
            studentId: 'sa1',
            items: {
              PayrollRequirement.requirementsKey: _checked,
              PayrollRequirement.endorsementKey: _checked,
              PayrollRequirement.contractKey(_term): _checked,
            },
          ),
          _allChecked('sa2', [9]),
        ];

      final reminded = state.remindPayrollRequirements(preview());

      expect(reminded, 1);
      final toStudent = fake.notifications.firstWhere(
        (n) => n['userId'] == 'sa1',
      );
      // September was sent and waits for the Head; October wasn't sent.
      expect(toStudent['message'], contains('October 2026'));
      expect(toStudent['message'], isNot(contains('September 2026')));
      expect(fake.notifications.map((n) => n['userId']).toSet(), {
        'sa1',
        'sv1',
      });
    });
  });
}
