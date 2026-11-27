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
