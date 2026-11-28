// Unit tests of the MarSU School ID parser
// (web/schedule-reader/sais-id-parser.js):
//   cd tool/schedule_reader_check && npm test
const test = require('node:test');
const assert = require('node:assert/strict');
const P = require('../../web/schedule-reader/sais-id-parser.js');

test('accepts a valid MarSU university or college school ID', () => {
  const uni = P.parseSchoolId(
    'MARINDUQUE STATE UNIVERSITY\nSTUDENT IDENTIFICATION CARD\nJUAN DELA CRUZ\n23B0626\nBS Information Technology',
  );
  assert.deepEqual(uni, { ok: true, studentId: '23B0626', reason: null });

  const college = P.parseSchoolId(
    'MARINDUQUE STATE COLLEGE\nMSC Boac\n21a1234',
  );
  assert.deepEqual(college, { ok: true, studentId: '21A1234', reason: null });
});

test('handles common OCR digit confusions in Student IDs', () => {
  const res = P.parseSchoolId('MarSU\nID No: 23BO62O');
  assert.equal(res.ok, true);
  assert.equal(res.studentId, '23B0620');

  const fuzzySchool = P.parseSchoolId('MARINDUQVE STATE\n24C1111');
  assert.equal(fuzzySchool.ok, true);
  assert.equal(fuzzySchool.studentId, '24C1111');
});

test('rejects pure 7-digit numbers and bare IDs without MarSU markers', () => {
  const pureDigits = P.parseSchoolId('MARINDUQUE STATE UNIVERSITY\n1234567');
  assert.equal(pureDigits.ok, false);
  assert.equal(pureDigits.studentId, null);

  const noSchool = P.parseSchoolId('ACME GYM MEMBERSHIP\nID: 23B0626');
  assert.equal(noSchool.ok, false);
  assert.equal(noSchool.studentId, null);
  assert.match(noSchool.reason, /does not look like a MarSU school ID/i);
});

test('rejects blank text, selfies/random text, and class schedules', () => {
  assert.equal(P.parseSchoolId('').ok, false);
  assert.equal(P.parseSchoolId('Happy birthday!').ok, false);

  const schedule = P.parseSchoolId(
    'MARINDUQUE STATE UNIVERSITY\nCLASS SCHEDULE\n23B0626\nMonday Tuesday Wednesday Thursday',
  );
  assert.equal(schedule.ok, false);
  assert.match(schedule.reason, /class schedule/i);
});

test('recovers campus letter when OCR reads bold B/S/G/T as 8/5/6/7 on MarSU IDs', () => {
  const realOcr = P.parseSchoolId(
    'Marintiwie State College\nPanFito M. MANGUERA SR Roap\nTANZA. BoOAC, MARINDUQUE\n2381402\nJOHN LORIMER D. IMPERIO',
  );
  assert.deepEqual(realOcr, { ok: true, studentId: '23B1402', reason: null });

  // High-res OCR where only "State College" and the number are clear.
  const stateCollegeOnly = P.parseSchoolId('Sarindine State College\n2381402');
  assert.deepEqual(stateCollegeOnly, { ok: true, studentId: '23B1402', reason: null });

  assert.equal(
    P.parseSchoolId('MarSU\n2250415').studentId,
    '22S0415',
  );
  assert.equal(
    P.parseSchoolId('MarSU\n2460123').studentId,
    '24G0123',
  );
  assert.equal(
    P.parseSchoolId('MarSU\n2170088').studentId,
    '21T0088',
  );

  // Lookalike digits without MarSU markers or outside year bounds stay rejected.
  assert.equal(P.parseSchoolId('ACME CARD\n2381402').ok, false);
  assert.equal(P.parseSchoolId('MARINDUQUE STATE UNIVERSITY\n2026001').ok, false);
  assert.equal(P.parseSchoolId('MARINDUQUE STATE UNIVERSITY\n1234567').ok, false);
});

test('a scan keeps the most telling reason across crops and turns', () => {
  const schedule = P.parseSchoolId('CLASS SCHEDULE\nMonday Tuesday Wednesday');
  const notMarsu = P.parseSchoolId('SOME OTHER SCHOOL\n23B0626');
  const noId = P.parseSchoolId('MARINDUQUE STATE UNIVERSITY');
  const ok = P.parseSchoolId('MARINDUQUE STATE UNIVERSITY\n23B0626');

  assert.equal(schedule.kind, 'schedule');
  assert.equal(notMarsu.kind, 'notMarsu');
  assert.equal(noId.kind, 'noId');
  assert.ok(P.failureRank(ok) > P.failureRank(schedule));
  assert.ok(P.failureRank(schedule) > P.failureRank(notMarsu));
  assert.ok(P.failureRank(notMarsu) > P.failureRank(noId));

  // A later, vaguer failure doesn't replace a clearer one.
  assert.equal(P.betterResult(notMarsu, noId), notMarsu);
  assert.equal(P.betterResult(noId, notMarsu), notMarsu);
  assert.equal(P.betterResult(noId, noId), noId);
  assert.equal(P.betterResult(null, noId), noId);

  // Only a schedule or registration form ends the scan early.
  assert.equal(P.isFinalFailure(schedule), true);
  assert.equal(P.isFinalFailure(notMarsu), false);
  assert.equal(P.isFinalFailure(ok), false);
});
