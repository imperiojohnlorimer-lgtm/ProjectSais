// Run with: node --test sessions.test.ts   (Node 23.6 or later)
//
// Tests the "session rules" region of index.ts. index.ts itself can't be
// imported here — it needs Deno's npm:/jsr: imports and starts the server —
// so the region is cut out, its types stripped, and loaded as a module.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const start = source.indexOf("// #region session rules");
const end = source.indexOf("// #endregion session rules");
assert.ok(start >= 0 && end > start, "index.ts lost its session rules region");
const { parseTimeMinutes, sessionHalf, sortOpenRecords } = await import(
  "data:text/javascript," +
    encodeURIComponent(stripTypeScriptTypes(source.slice(start, end)))
);

const rec = (timeIn: string, isInvalid = false) => ({ timeIn, isInvalid });

test("parses times and sessions", () => {
  assert.equal(parseTimeMinutes("8:00 AM"), 480);
  assert.equal(parseTimeMinutes("12:00 PM"), 720);
  assert.equal(parseTimeMinutes("12:15 AM"), 15);
  assert.equal(parseTimeMinutes("junk"), null);
  assert.equal(sessionHalf(480), "AM");
  assert.equal(sessionHalf(720), "AM");
  assert.equal(sessionHalf(750), "PM");
  assert.equal(sessionHalf(735), null); // lunch break
});

test("a scan in the same session clocks out of that session's record", () => {
  const morning = rec("8:00 AM");
  const r = sortOpenRecords([morning], "AM");
  assert.equal(r.current, morning);
  assert.deepEqual(r.stale, []);
});

test("an afternoon scan never closes a morning record", () => {
  const morning = rec("8:00 AM");
  const r = sortOpenRecords([morning], "PM");
  assert.equal(r.current, undefined);
  assert.deepEqual(r.stale, [morning]);
});

test("with a stale morning and an open afternoon, the afternoon one closes", () => {
  const morning = rec("8:00 AM", true);
  const afternoon = rec("1:00 PM");
  const r = sortOpenRecords([morning, afternoon], "PM");
  assert.equal(r.current, afternoon);
  assert.deepEqual(r.stale, [morning]);
});

test("an invalid or unreadable record is never closed", () => {
  const flagged = rec("1:00 PM", true);
  const unreadable = rec("??");
  const r = sortOpenRecords([flagged, unreadable], "PM");
  assert.equal(r.current, undefined);
  assert.deepEqual(r.stale, [flagged, unreadable]);
});
