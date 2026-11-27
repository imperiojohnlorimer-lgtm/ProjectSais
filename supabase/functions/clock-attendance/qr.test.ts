// Run with: node --test qr.test.ts   (Node 23.6 or later)
//
// Tests the "qr rules" region of index.ts: which scanned codes let a
// student assistant clock in, now that every office has its own code.
// index.ts itself can't be imported here (it needs Deno's npm:/jsr: imports
// and starts the server), so the region is cut out, its types stripped, and
// loaded as a module.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const start = source.indexOf("// #region qr rules");
const end = source.indexOf("// #endregion qr rules");
assert.ok(start >= 0 && end > start, "index.ts lost its qr rules region");
const { qrVerdict } = await import(
  "data:text/javascript," +
    encodeURIComponent(stripTypeScriptTypes(source.slice(start, end)))
);

const NOW = "20261127-AM";
const office = (
  officeId: string,
  officeName: string,
  token: string | null,
  sessionKey: string | null = NOW,
) => ({ officeId, officeName, token, sessionKey });

test("a student in no office is told to ask the Head", () => {
  const v = qrVerdict("CODE", NOW, [], null);
  assert.equal(v.ok, false);
  assert.equal(v.status, 409);
  assert.match(v.error, /aren't placed in an office/);
});

test("their own office's code for this session is accepted", () => {
  const v = qrVerdict("CODE", NOW, [office("o1", "Library", "CODE")], null);
  assert.deepEqual(v, { ok: true, officeId: "o1" });
});

test("their office's code from an earlier session is refused", () => {
  const v = qrVerdict(
    "CODE",
    NOW,
    [office("o1", "Library", "CODE", "20261126-PM")],
    null,
  );
  assert.equal(v.ok, false);
  assert.equal(v.status, 409);
  assert.match(v.error, /earlier session/);
});

test("another office's code names both offices", () => {
  const v = qrVerdict(
    "OTHER",
    NOW,
    [office("o1", "Library", "CODE")],
    "Registrar",
  );
  assert.equal(v.ok, false);
  assert.equal(v.status, 403);
  assert.equal(
    v.error,
    "That QR code is for Registrar. Scan the one posted in Library.",
  );
});

test("an unknown or copied code names no office", () => {
  // The server passes no office name when no office, or more than one
  // (a copied code), has the scanned token.
  const v = qrVerdict("OLD", NOW, [office("o1", "Library", "CODE")], null);
  assert.equal(v.ok, false);
  assert.equal(v.status, 403);
  assert.match(v.error, /not a current attendance QR/);
  assert.doesNotMatch(v.error, /Library|Registrar/);
});

test("an office with no code yet accepts nothing", () => {
  const v = qrVerdict("CODE", NOW, [office("o1", "Library", null, null)], null);
  assert.equal(v.ok, false);
  assert.match(v.error, /not a current attendance QR/);
});

test("a student in two offices may use either office's code", () => {
  const both = [
    office("o1", "Library", "CODE1"),
    office("o2", "Clinic", "CODE2"),
  ];
  assert.deepEqual(qrVerdict("CODE2", NOW, both, null), {
    ok: true,
    officeId: "o2",
  });
  const v = qrVerdict("X", NOW, both, "Registrar");
  assert.equal(
    v.error,
    "That QR code is for Registrar. Scan the one posted in Library or Clinic.",
  );
});

test("an office saved without a name still gets a sensible message", () => {
  const v = qrVerdict("X", NOW, [office("o1", "", "CODE")], "Registrar");
  assert.equal(
    v.error,
    "That QR code is for Registrar. Scan the one posted in your own office.",
  );
});
