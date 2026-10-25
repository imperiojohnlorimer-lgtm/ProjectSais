// Run with: node --test paths.test.ts   (Node 23.6 or later)
//
// Tests the "path rules" region of index.ts. index.ts itself can't be
// imported here — it needs Deno's npm:/jsr: imports and starts the server —
// so the region is cut out, its types stripped, and loaded as a module.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const start = source.indexOf("// #region path rules");
const end = source.indexOf("// #endregion path rules");
assert.ok(start >= 0 && end > start, "index.ts lost its path rules region");
const { staffMayRead, ownedPath, isPublicAnnouncementPath } = await import(
  "data:text/javascript," +
    encodeURIComponent(stripTypeScriptTypes(source.slice(start, end)))
);

test("a file is the owner's when their id is the second part", () => {
  assert.equal(ownedPath("reports/u1/1700000000/a.pdf", "u1"), true);
  assert.equal(ownedPath("reports/u1/1700000000/a.pdf", "u2"), false);
  assert.equal(ownedPath("secrets/u1/1700000000/a.pdf", "u1"), false);
  assert.equal(ownedPath("reports/u1/../u2/a.pdf", "u1"), false);
});

test("the Head reads reports, applications, announcements and archives", () => {
  for (const path of [
    "reports/u1/1700000000/a.pdf",
    "applications/u1/app_u1_2026/doc/a.pdf",
    "announcements/u1/1700000000/a.pdf",
    "academic_year_archives/2026-2027/reports/r1/My File.pdf",
  ]) {
    assert.equal(staffMayRead(path, "Head"), true, path);
  }
});

test("a Supervisor reads reports and announcements only", () => {
  assert.equal(staffMayRead("reports/u1/1700000000/a.pdf", "Supervisor"), true);
  assert.equal(
    staffMayRead("announcements/u1/1700000000/a.pdf", "Supervisor"),
    true,
  );
  assert.equal(
    staffMayRead("applications/u1/app_u1_2026/doc/a.pdf", "Supervisor"),
    false,
  );
  assert.equal(
    staffMayRead("academic_year_archives/2026-2027/reports/r1/a.pdf", "Supervisor"),
    false,
  );
});

test("nobody else reads other people's files, and odd paths are refused", () => {
  for (const role of ["Student", "Student Assistant", "Admin", undefined]) {
    assert.equal(staffMayRead("reports/u1/1700000000/a.pdf", role), false);
  }
  assert.equal(staffMayRead("reports/u1/../../x/a.pdf", "Head"), false);
  assert.equal(staffMayRead("reports//1700000000/a.pdf", "Head"), false);
  assert.equal(staffMayRead("other/u1/1700000000/a.pdf", "Head"), false);
  assert.equal(staffMayRead("reports/a.pdf", "Head"), false);
  assert.equal(staffMayRead("reports/" + "x/".repeat(300) + "a.pdf", "Head"), false);
});

test("announcement attachments are public to the signed in", () => {
  assert.equal(isPublicAnnouncementPath("announcements/u1/1700/a.pdf"), true);
  assert.equal(isPublicAnnouncementPath("reports/u1/1700/a.pdf"), false);
});

test("encoded or backslash tricks cannot climb out of a checked folder", () => {
  for (const path of [
    "reports/%2e%2e/applications/u1/app1/doc.pdf",
    "reports/%2E%2E/applications/u1/app1/doc.pdf",
    "reports/u1/%2e%2e/doc.pdf",
    "reports/u1/a%2fb/doc.pdf",
    "reports\\..\\applications/u1/app1/doc.pdf",
    "reports/u1/1700/doc\u0000.pdf",
  ]) {
    assert.equal(staffMayRead(path, "Head"), false, path);
    assert.equal(staffMayRead(path, "Supervisor"), false, path);
  }
});
