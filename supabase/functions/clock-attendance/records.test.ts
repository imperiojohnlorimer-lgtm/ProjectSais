// Run with: node --test records.test.ts   (Node 23.6 or later)
//
// Tests the "record rules" region of index.ts. index.ts itself can't be
// imported here — it needs Deno's npm:/jsr: imports and starts the server —
// so the region is cut out, its types stripped, and loaded as a module.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const start = source.indexOf("// #region record rules");
const end = source.indexOf("// #endregion record rules");
assert.ok(start >= 0 && end > start, "index.ts lost its record rules region");
const { nextAttendanceId, justClockedOut, justClockedIn } = await import(
  "data:text/javascript," +
    encodeURIComponent(stripTypeScriptTypes(source.slice(start, end)))
);

const doc = (id: string) =>
  `projects/sais-6168b/databases/(default)/documents/attendance/${id}`;

test("the first clock-in of a day is number 0", () => {
  assert.equal(nextAttendanceId("u1_20261025", []), "u1_20261025_0");
});

test("a legacy record with a random id doesn't count", () => {
  assert.equal(
    nextAttendanceId("u1_20261025", [doc("Xk39sLq02mZpA8vN1bQe")]),
    "u1_20261025_0",
  );
});

test("each clock-in takes the next number, so a double tap collides", () => {
  const first = nextAttendanceId("u1_20261025", []);
  const second = nextAttendanceId("u1_20261025", [doc(first)]);
  assert.equal(second, "u1_20261025_1");
  // Two scans of the same clock-in see the same records: the same id.
  assert.equal(nextAttendanceId("u1_20261025", []), first);
});

test("numbering follows the highest one, so a deleted record's id isn't reused", () => {
  const names = [doc("u1_20261025_0"), doc("u1_20261025_1")];
  assert.equal(nextAttendanceId("u1_20261025", names), "u1_20261025_2");
  // Record 0 deleted: one record left, but 1 is still taken.
  assert.equal(nextAttendanceId("u1_20261025", [doc("u1_20261025_1")]), "u1_20261025_2");
});

test("another student's or another day's records are ignored", () => {
  const names = [doc("u2_20261025_5"), doc("u1_20261024_3")];
  assert.equal(nextAttendanceId("u1_20261025", names), "u1_20261025_0");
});

test("a scan in the minute of a clock-out is a second tap", () => {
  assert.equal(justClockedOut(["11:58 AM"], "11:58 AM"), true);
  assert.equal(justClockedOut(["11:58 AM"], "11:59 AM"), false);
  assert.equal(justClockedOut(["", "10:00 AM"], "12:30 PM"), false);
  assert.equal(justClockedOut([], "12:30 PM"), false);
});

test("a scan in the minute of a clock-in is a second tap, not a clock-out", () => {
  assert.equal(justClockedIn("8:02 AM", "8:02 AM"), true);
  assert.equal(justClockedIn("8:02 AM", "8:03 AM"), false);
  assert.equal(justClockedIn("", ""), false);
});
