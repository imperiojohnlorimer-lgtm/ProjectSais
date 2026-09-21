import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/payroll_document_service.dart';

PayrollRecord _record(
  int i, {
  required String campus,
  List<PayrollMonthBreakdown>? months,
}) {
  return PayrollRecord(
    id: 'pay_$i',
    studentId: 'student_$i',
    studentName: 'Student ${i.toString().padLeft(2, '0')}',
    office: 'Registrar',
    campus: campus,
    periodStart: '2025-08-01',
    periodEnd: '2025-12-31',
    periodLabel: '1st Semester, AY 2025-2026',
    monthlyBreakdown:
        months ??
        const [
          PayrollMonthBreakdown(
            month: 9,
            year: 2025,
            hoursWorked: 40,
            payableHours: 40,
          ),
          PayrollMonthBreakdown(
            month: 10,
            year: 2025,
            hoursWorked: 40,
            payableHours: 40,
          ),
        ],
    dtrVerified: true,
    reportVerified: true,
    status: 'Approved',
  );
}

PayrollSheet _sheet(List<PayrollRecord> records) => PayrollSheet.fromRecords(
  periodStart: '2025-08-01',
  periodEnd: '2025-12-31',
  periodLabel: '1st Semester, AY 2025-2026',
  records: records,
);

Future<String> _documentXml(PayrollSheet sheet) async {
  final doc = await const PayrollDocumentService().generatePayroll(
    sheet: sheet,
  );
  expect(doc.fileName, startsWith('hourly-wage-payroll-'));
  expect(doc.fileName, endsWith('.docx'));
  expect(doc.bytes!.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
  final archive = ZipDecoder().decodeBytes(doc.bytes!);
  final file = archive.files.firstWhere((f) => f.name == 'word/document.xml');
  return utf8.decode(file.content as List<int>);
}

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // loads the template asset via rootBundle

  group('PayrollSheet', () {
    test('starts from the system records, sorted by campus then name', () {
      final sheet = PayrollSheet.fromRecords(
        periodStart: '2025-08-01',
        periodEnd: '2025-12-31',
        periodLabel: '1st Semester, AY 2025-2026',
        records: [
          _record(2, campus: 'Gasan Campus'),
          _record(3, campus: 'Boac Campus'),
          _record(1, campus: 'Boac Campus'),
        ],
        previous: const PayrollSheet(
          id: 'older',
          periodStart: '2025-01-01',
          periodEnd: '2025-05-31',
          periodLabel: '2nd Semester',
          payrollNo: '2025-05-001',
          fundCluster: '01',
          signatories: [
            PayrollSignatory(name: 'New VP', title: 'VP'),
            PayrollSignatory(name: 'New Accountant', title: 'Accountant'),
            PayrollSignatory(name: 'New President', title: 'President'),
            PayrollSignatory(name: 'New Officer', title: 'Officer'),
          ],
        ),
      );

      expect(sheet.id, PayrollSheet.idForPeriod('2025-08-01', '2025-12-31'));
      expect(sheet.entries.map((e) => e.name), [
        'Student 01',
        'Student 03',
        'Student 02',
      ]);
      expect(sheet.entries.first.hoursWorked, 80);
      expect(sheet.entries.first.remarks, 'Sept.-Oct. 2025');
      // Signatories and fund cluster carry over; the payroll number doesn't.
      expect(sheet.signatories.first.name, 'New VP');
      expect(sheet.fundCluster, '01');
      expect(sheet.payrollNo, isEmpty);
    });

    test('computes each row from its edited columns', () {
      const entry = PayrollSheetEntry(
        campus: 'Boac Campus',
        name: 'Added By Hand',
        hoursWorked: 80,
        ratePerHour: 25,
        undertimeHours: 1,
        undertimeMinutes: 30,
        taxesWithheld: 100,
        sss: 50,
      );
      expect(entry.totalAmount, 2000);
      expect(entry.undertimeAmount, 37.5);
      expect(entry.grossAmount, 1962.5);
      expect(entry.netPay, 1812.5);
    });

    test('survives a save and load', () {
      final sheet = _sheet([
        _record(1, campus: 'Boac Campus'),
      ]).copyWith(payrollNo: '2025-12-004', fundCluster: '06');
      final restored = PayrollSheet.fromJson({
        ...sheet.toJson(),
        'id': sheet.id,
      });
      expect(restored.payrollNo, '2025-12-004');
      expect(restored.fundCluster, '06');
      expect(restored.entries.single.toJson(), sheet.entries.single.toJson());
      expect(restored.signatories.length, 4);
    });
  });

  group('PayrollDocumentService', () {
    test('fills a single sheet ending with the grand total', () async {
      final xml = await _documentXml(
        _sheet([
          _record(1, campus: 'Gasan Campus'),
          _record(2, campus: 'Boac Campus'),
        ]),
      );

      expect(xml, isNot(contains('{{')));
      expect(_count(xml, '>TOTAL<'), 1);
      expect(xml, isNot(contains('CARRIED FORWARD')));
      expect(xml, isNot(contains('pageBreakBefore')));
      // Campuses are listed alphabetically: Boac before Gasan.
      expect(
        xml.indexOf('>Boac Campus<'),
        lessThan(xml.indexOf('>Gasan Campus<')),
      );
      // 80 payable hours at 25.00/hr, twice.
      expect(_count(xml, '>2,000.00<'), 2 * 3);
      expect(xml, contains('>4,000.00<'));
      expect(xml, contains('>Sept.-Oct. 2025<'));
      // Blank header fields print the sample's blank lines; the default
      // signatories are printed.
      expect(xml, contains('> MARINDUQUE STATE UNIVERSITY<'));
      expect(xml, contains('> _______________________<'));
      expect(xml, contains('>MARICEL P. GALANG<'));
    });

    test('prints the edited header, rows and signatories', () async {
      final base = _sheet([_record(1, campus: 'Boac Campus')]);
      final xml = await _documentXml(
        base.copyWith(
          payrollNo: '2025-12-004',
          fundCluster: 'Regular Agency Fund',
          entries: [
            const PayrollSheetEntry(
              campus: 'Boac Campus',
              name: 'Dela Cruz, Juan & Co.',
              hoursWorked: 80,
              undertimeHours: 2,
              undertimeMinutes: 0,
              taxesWithheld: 100,
              remarks: 'Sept. 2025',
            ),
          ],
          signatories: [
            ...base.signatories.take(3),
            const PayrollSignatory(name: 'JUAN P. REYES', title: 'Cashier III'),
          ],
        ),
      );

      expect(xml, contains('> 2025-12-004<'));
      expect(xml, contains('> Regular Agency Fund<'));
      expect(xml, contains('>Dela Cruz, Juan &amp; Co.<'));
      // 80 × 25 = 2,000; 2 hrs undertime = 50; less 100 tax = 1,850 net.
      expect(xml, contains('>50.00<'));
      expect(xml, contains('>1,950.00<'));
      expect(xml, contains('>100.00<'));
      expect(_count(xml, '>1,850.00<'), 2); // the row and the TOTAL
      expect(xml, contains('>JUAN P. REYES<'));
      expect(xml, contains('>Cashier III<'));
      expect(xml, isNot(contains('MARICEL P. GALANG')));
    });

    test('splits long payrolls into sheets with carried totals', () async {
      final xml = await _documentXml(
        _sheet([
          for (var i = 1; i <= 30; i++) _record(i, campus: 'Boac Campus'),
          for (var i = 31; i <= 40; i++) _record(i, campus: 'Torrijos Campus'),
        ]),
      );

      const sheets = 2;
      expect(_count(xml, 'TOTAL CARRIED FORWARD'), sheets - 1);
      expect(_count(xml, 'TOTAL BROUGHT FORWARD'), sheets - 1);
      expect(_count(xml, '<w:pageBreakBefore/>'), sheets - 1);
      // Every sheet repeats the heading and the signatory block.
      expect(_count(xml, 'HOURLY WAGE PAYROLL'), sheets);
      expect(_count(xml, 'APPROVED FOR PAYMENT'), sheets);
      // Boac continues onto the second sheet, so its heading repeats there.
      expect(_count(xml, '>Boac Campus<'), 2);
      // 23 students fit under the first heading; carried forward = 23 × 2,000.
      expect(xml, contains('>46,000.00<'));
      expect(xml, contains('>80,000.00<'));
      // Numbering runs straight through both sheets.
      expect(xml, contains('>40<'));
    });

    test('writes the months worked as the Remarks column', () async {
      final xml = await _documentXml(
        _sheet([
          _record(
            1,
            campus: 'Boac Campus',
            months: const [
              PayrollMonthBreakdown(
                month: 12,
                year: 2025,
                hoursWorked: 30,
                payableHours: 30,
              ),
              PayrollMonthBreakdown(
                month: 1,
                year: 2026,
                hoursWorked: 25.5,
                payableHours: 25.5,
              ),
            ],
          ),
          _record(
            2,
            campus: 'Boac Campus',
            months: const [
              PayrollMonthBreakdown(
                month: 10,
                year: 2025,
                hoursWorked: 0,
                payableHours: 0,
              ),
              PayrollMonthBreakdown(
                month: 11,
                year: 2025,
                hoursWorked: 32,
                payableHours: 32,
              ),
            ],
          ),
        ]),
      );

      expect(xml, contains('>Dec. 2025-Jan. 2026<'));
      expect(xml, contains('>55.5<'));
      expect(xml, contains('>1,387.50<'));
      // A month with no hours doesn't widen the range.
      expect(xml, contains('>Nov. 2025<'));
    });
  });
}
