// Run with: node --test pushtext.test.ts   (Node 23.6 or later)
//
// Tests the "push text" region of index.ts. index.ts itself can't be
// imported here — it needs Deno's npm:/jsr: imports and starts the server —
// so the region is cut out, its types stripped, and loaded as a module.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const start = source.indexOf("// #region push text");
const end = source.indexOf("// #endregion push text");
assert.ok(start >= 0 && end > start, "index.ts lost its push text region");
const { pushTextFor } = await import(
  "data:text/javascript," +
    encodeURIComponent(stripTypeScriptTypes(source.slice(start, end)))
);

test("pay, ratings, rehire and requirements are announced without details", () => {
  for (const kind of ["payroll", "evaluation", "payroll_requirement", "rehire", "application", "office"]) {
    const text = pushTextFor(kind, "Payout Released", "Your pay for September: ₱4,200.00");
    assert.equal(text.title, "SAIS", kind);
    assert.equal(text.body, "You have a new update. Open SAIS to read it.", kind);
  }
});

test("everything else keeps its own words", () => {
  for (const kind of ["task", "announcement", undefined]) {
    assert.deepEqual(pushTextFor(kind, "New Task", "File the forms"), {
      title: "New Task",
      body: "File the forms",
    });
  }
});
