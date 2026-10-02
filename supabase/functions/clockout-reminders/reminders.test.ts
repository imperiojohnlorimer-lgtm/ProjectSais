// Run with: node --test reminders.test.ts   (Node 23.6 or later)
//
// Tests the "reminder rules" region of index.ts. index.ts itself can't be
// imported here — it needs Deno's npm:/jsr: imports and starts the server —
// so the region is cut out, its types stripped, and loaded as a module.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const start = source.indexOf("// #region reminder rules");
const end = source.indexOf("// #endregion reminder rules");
assert.ok(start >= 0 && end > start, "index.ts lost its reminder rules region");
const { endingSession, isDue, reminderMessage } = await import(
  "data:text/javascript," +
    encodeURIComponent(stripTypeScriptTypes(source.slice(start, end)))
);

const at = (hour: number, minute: number) => hour * 60 + minute;

test("runs only in the last 30 minutes of a session", () => {
  assert.equal(endingSession(at(11, 29)), null);
  assert.equal(endingSession(at(11, 30)), "AM");
  assert.equal(endingSession(at(11, 59)), "AM");
  assert.equal(endingSession(at(12, 0)), null);
  assert.equal(endingSession(at(16, 29)), null);
  assert.equal(endingSession(at(16, 30)), "PM");
  assert.equal(endingSession(at(16, 59)), "PM");
  assert.equal(endingSession(at(17, 0)), null);
});

test("reminds a record clocked in to the ending session before 30 minutes " +
  "to go", () => {
  assert.equal(isDue("8:05 AM", "AM"), true);
  assert.equal(isDue("11:29 AM", "AM"), true);
  assert.equal(isDue("12:45 PM", "PM"), true);
  assert.equal(isDue("4:29 PM", "PM"), true);
});

test("leaves out a later clock-in, another session's record, or an " +
  "unreadable time", () => {
  assert.equal(isDue("11:30 AM", "AM"), false);
  assert.equal(isDue("11:45 AM", "AM"), false);
  assert.equal(isDue("4:30 PM", "PM"), false);
  assert.equal(isDue("8:05 AM", "PM"), false);
  assert.equal(isDue("1:00 PM", "AM"), false);
  assert.equal(isDue("soon", "AM"), false);
});

test("words the reminder as the app does", () => {
  assert.equal(
    reminderMessage("AM"),
    "Your morning session ends at 12:00 PM. Scan the attendance QR code " +
      "to clock out before then, or this session won't count toward your " +
      "hours.",
  );
  assert.match(reminderMessage("PM"), /^Your afternoon session ends at 5:00 PM\./);
});
