// Run with: node --test email.test.ts   (Node 23.6 or later)
//
// Tests the "email rules" region of index.ts (with "push text", which it
// uses). index.ts itself can't be imported here: it needs Deno's imports and
// starts the server. So the regions are cut out, their types stripped, and
// loaded as a module.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
function region(name: string): string {
  const start = source.indexOf(`// #region ${name}`);
  const end = source.indexOf(`// #endregion ${name}`);
  assert.ok(start >= 0 && end > start, `index.ts lost its ${name} region`);
  return source.slice(start, end);
}
const {
  EMAIL_DAILY_CAP,
  EMAIL_LEASE_MS,
  EMAIL_PER_PERSON_CAP,
  EMAIL_PER_PERSON_CLOCKOUT_CAP,
  emailFailureReason,
  emailFor,
  emailState,
  htmlEscape,
  isFreshNotification,
  validMailbox,
} = await import(
  "data:text/javascript," +
    encodeURIComponent(
      stripTypeScriptTypes(region("push text") + region("email rules")),
    )
);

const link = "https://sais-6168b.web.app/notifications";

test("an email says what kind of update it is, never the notification's own words", () => {
  const mail = emailFor("task", link, "sam@gmail.com");
  assert.equal(mail.subject, "SAIS: you have a new update");
  assert.match(mail.text, /You have a new update about a task\./);
  assert.ok(mail.text.includes(link));
  assert.ok(mail.html.includes(`href="${link}"`));
  // emailFor is not given the notification's title or message at all, so
  // nothing a sender typed can reach the email.
});

test("private kinds and unknown kinds get the plain wording", () => {
  for (const kind of [
    "payroll",
    "evaluation",
    "payroll_requirement",
    "rehire",
    "application",
    "office",
    "system",
    "something_new",
    undefined,
  ]) {
    const mail = emailFor(kind, link, "sam@gmail.com");
    assert.match(mail.text, /^You have a new update\.\n/, String(kind));
  }
});

test("the clock-out reminder uses the sentence the function builds", () => {
  const mail = emailFor("attendance", link, "sam@gmail.com", {
    subject: "SAIS: time to clock out",
    sentence: "Your morning session ends at 12:00 PM.",
  });
  assert.equal(mail.subject, "SAIS: time to clock out");
  assert.match(mail.text, /^Your morning session ends at 12:00 PM\./);
});

test("the footer says why, names the address, and how to stop", () => {
  const mail = emailFor("task", link, "sam@gmail.com");
  assert.match(mail.text, /sam@gmail\.com/);
  assert.match(mail.text, /turn off "Email notifications"/);
});

test("html is escaped", () => {
  assert.equal(
    htmlEscape(`<a href="x">&'`),
    "&lt;a href=&quot;x&quot;&gt;&amp;&#39;",
  );
  const mail = emailFor("task", link, `a"b<c>@x.com`);
  assert.ok(!mail.html.includes("<c>"));
});

test("only one plain address is accepted", () => {
  for (const ok of ["sam@gmail.com", "sam.santos+reg1@marsu.edu.ph"]) {
    assert.equal(validMailbox(ok), true, ok);
  }
  for (
    const bad of [
      "",
      "sam",
      "sam@",
      "@gmail.com",
      "sam@gmail",
      "a@b.com, c@d.com",
      "a@b.com;c@d.com",
      "Sam <sam@gmail.com>",
      "sam@gmail.com\r\nBcc: x@y.com",
      "sam@gmail.com\nBcc: x@y.com",
      "sam @gmail.com",
      'sam"@gmail.com',
      "sam@@gmail.com",
      "a".repeat(250) + "@x.com",
      null,
      42,
    ]
  ) {
    assert.equal(validMailbox(bad), false, String(bad));
  }
});

test("a notification's email is free, leased or done", () => {
  const now = Date.parse("2026-11-01T08:00:00Z");
  assert.equal(emailState({}, now), "free");
  assert.equal(
    emailState({ emailedAt: "2026-11-01T07:59:00Z" }, now),
    "done",
  );
  assert.equal(
    emailState({ emailClaimedAt: "2026-11-01T07:59:30Z" }, now),
    "leased",
  );
  // A claim from a request that died is let go after the lease.
  assert.equal(
    emailState(
      { emailClaimedAt: new Date(now - EMAIL_LEASE_MS - 1).toISOString() },
      now,
    ),
    "free",
  );
  // Sent beats leased.
  assert.equal(
    emailState({
      emailedAt: "2026-11-01T07:59:00Z",
      emailClaimedAt: "2026-11-01T07:59:30Z",
    }, now),
    "done",
  );
  assert.equal(emailState({ emailClaimedAt: "garbage" }, now), "free");
});

test("a notification is fresh only if recent and not from the future", () => {
  const now = Date.parse("2026-11-01T08:00:00Z");
  const tenMin = 10 * 60 * 1000;
  assert.equal(isFreshNotification(now - 1000, now, tenMin), true);
  assert.equal(isFreshNotification(now - tenMin - 1, now, tenMin), false);
  assert.equal(isFreshNotification(now + 30_000, now, tenMin), true);
  assert.equal(isFreshNotification(now + 120_000, now, tenMin), false);
  assert.equal(isFreshNotification(NaN, now, tenMin), false);
});

test("the limits stay under Gmail's own", () => {
  assert.ok(EMAIL_DAILY_CAP < 500);
  assert.ok(EMAIL_PER_PERSON_CAP >= 1);
  assert.ok(EMAIL_PER_PERSON_CLOCKOUT_CAP >= 2); // morning and afternoon
});

test("a failed test email says the likely cause in plain words", () => {
  const cases: [unknown, RegExp][] = [
    [new Error("535 5.7.8 Username and Password not accepted"), /refused the sign-in/],
    [new Error("invalid cred: BadCredentials"), /refused the sign-in/],
    [new Error("Email server timed out."), /did not answer in time/],
    [new Error("Connection refused (os error 111)"), /could not connect/],
    [new Error("NotCapable: net access to smtp.gmail.com:465 is blocked"), /could not connect/],
    [new Error("something odd"), /did not accept the message/],
  ];
  for (const [error, expected] of cases) {
    assert.match(emailFailureReason(error), expected, String(error));
  }
  assert.match(emailFailureReason(new Error("x")), /\(x\)$/);
});

test("the reason never contains the secrets, and stays short", () => {
  const reason = emailFailureReason(
    new Error("login failed for sais@gmail.com with abcdefghijklmnop " + "z".repeat(500)),
    ["abcdefghijklmnop", "sais@gmail.com", ""],
  );
  assert.ok(!reason.includes("abcdefghijklmnop"));
  assert.ok(!reason.includes("sais@gmail.com"));
  assert.ok(reason.length < 400);
  assert.equal(emailFailureReason(""), "The email server did not accept the message.");
});
