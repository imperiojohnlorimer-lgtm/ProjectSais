// Run with: node --test email-core.test.ts   (Node 23.6 or later)
//
// Tests the delivery core of the "email rules" region of index.ts against a
// fake Firestore: claims, races with other writes, failures, timeouts and
// limits. (See email.test.ts for how the region is loaded.)
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
const { EMAIL_LEASE_MS, deliverEmail, runPool, sameInstant } = await import(
  "data:text/javascript," +
    encodeURIComponent(
      stripTypeScriptTypes(region("push text") + region("email rules")),
    )
);

const NOW = Date.parse("2026-11-01T08:00:00Z");
const tenMin = 10 * 60 * 1000;

test("sameInstant compares moments, not strings", () => {
  const ms = Date.parse("2026-11-01T08:00:00.123Z");
  assert.equal(sameInstant("2026-11-01T08:00:00.123Z", ms), true);
  assert.equal(sameInstant("2026-11-01T08:00:00.123000Z", ms), true);
  assert.equal(sameInstant("2026-11-01T08:00:00.124Z", ms), false);
  assert.equal(sameInstant(undefined, ms), false);
});

test("runPool runs a few at a time and can be stopped", async () => {
  let running = 0;
  let most = 0;
  const done: number[] = [];
  await runPool([1, 2, 3, 4, 5, 6, 7], 3, async (n: number) => {
    running++;
    most = Math.max(most, running);
    await new Promise((r) => setTimeout(r, 5));
    done.push(n);
    running--;
  }, () => false);
  assert.equal(most, 3);
  assert.deepEqual(done.sort(), [1, 2, 3, 4, 5, 6, 7]);

  const first: number[] = [];
  await runPool([1, 2, 3, 4, 5], 1, async (n: number) => {
    first.push(n);
  }, () => first.length >= 2);
  assert.deepEqual(first, [1, 2]);
  await runPool([], 3, async () => {}, () => false); // nothing to do
});

/** One notification and the world around it. */
function world(over: Record<string, unknown> = {}) {
  const w = {
    clock: NOW,
    updateTime: 1,
    emailedAt: undefined as string | undefined,
    emailClaimedAt: undefined as string | undefined,
    createdAtMs: NOW - 1000,
    userId: "u1" as string | undefined,
    type: "task",
    address: "sam@gmail.com" as string | null,
    allowed: true,
    // Today's room, shared by every notification of the same person.
    quota: { used: 0, cap: 99, fails: false },
    sent: [] as string[],
    logs: [] as string[],
    patches: 0,
    // Runs just before the next write, to model someone else's write landing
    // between our read and our write.
    beforeNextPatch: null as null | (() => void),
    sendError: null as unknown,
    ...over,
  };
  const touch = () => {
    w.updateTime++;
  };
  const deps = {
    now: () => w.clock,
    async read() {
      return {
        updateTime: String(w.updateTime),
        userId: w.userId,
        type: w.type,
        createdAtMs: w.createdAtMs,
        emailedAt: w.emailedAt,
        emailClaimedAt: w.emailClaimedAt,
      };
    },
    async patch(updateTime: string, change: Record<string, unknown>) {
      if (w.beforeNextPatch) {
        const run = w.beforeNextPatch;
        w.beforeNextPatch = null;
        run();
      }
      if (String(w.updateTime) !== updateTime) return null;
      w.patches++;
      if ("claimAtMs" in change) {
        w.emailClaimedAt = new Date(change.claimAtMs as number).toISOString();
      } else if ("sentAtMs" in change) {
        w.emailedAt = new Date(change.sentAtMs as number).toISOString();
      } else {
        w.emailClaimedAt = undefined;
      }
      touch();
      return String(w.updateTime);
    },
    async recipient() {
      return w.address;
    },
    async allowed() {
      return w.allowed;
    },
    async reserve() {
      if (w.quota.fails) throw new Error("counter down");
      await new Promise((r) => setTimeout(r, 1));
      if (w.quota.used + 1 > w.quota.cap) return false;
      w.quota.used++;
      return true;
    },
    async refund() {
      w.quota.used--;
    },
    async send(address: string) {
      await new Promise((r) => setTimeout(r, 1));
      if (w.sendError) throw w.sendError;
      w.sent.push(address);
    },
    isTimeout: (e: unknown) => e instanceof Error && e.message === "timeout",
    log: (m: string) => {
      w.logs.push(m);
    },
  };
  return { w, deps, touch };
}

test("a notification is emailed once: claimed, counted, marked", async () => {
  const { w, deps } = world();
  assert.equal(await deliverEmail(deps, "other", tenMin), "sent");
  assert.deepEqual(w.sent, ["sam@gmail.com"]);
  assert.equal(w.quota.used, 1);
  assert.ok(w.emailedAt);
  // A second request finds it done.
  assert.equal(await deliverEmail(deps, "other", tenMin), "skipped");
  assert.equal(w.sent.length, 1);
  assert.equal(w.quota.used, 1);
});

test("another write between the read and the claim does not lose it", async () => {
  const { w, deps, touch } = world();
  w.beforeNextPatch = touch; // e.g. the push marks pushedAt first
  assert.equal(await deliverEmail(deps, "other", tenMin), "sent");
  assert.equal(w.sent.length, 1);
});

test("a write while sending (it being read) still lets the send be recorded", async () => {
  const { w, deps, touch } = world();
  const send = deps.send;
  deps.send = async (a: string) => {
    await send(a);
    touch(); // the person marks it read while the email is going out
  };
  assert.equal(await deliverEmail(deps, "other", tenMin), "sent");
  assert.ok(w.emailedAt, "recorded, so it is not sent again");
  w.clock += EMAIL_LEASE_MS + 1;
  assert.equal(await deliverEmail(deps, "other", 60 * 60 * 1000), "skipped");
  assert.equal(w.sent.length, 1);
});

test("two requests at once send it once", async () => {
  const { w, deps } = world();
  const results = await Promise.all([
    deliverEmail(deps, "other", tenMin),
    deliverEmail(deps, "other", tenMin),
  ]);
  assert.deepEqual([...results].sort(), ["sent", "skipped"]);
  assert.equal(w.sent.length, 1);
  assert.equal(w.quota.used, 1);
});

test("a failed send lets go of the claim, so the next request tries again", async () => {
  const { w, deps } = world({ sendError: new Error("auth failed") });
  assert.equal(await deliverEmail(deps, "other", tenMin), "failed");
  assert.equal(w.emailClaimedAt, undefined);
  assert.equal(w.emailedAt, undefined);
  w.sendError = null;
  assert.equal(await deliverEmail(deps, "other", tenMin), "sent");
  assert.equal(w.sent.length, 1);
});

test("a send that never answers keeps the claim until the lease runs out", async () => {
  const { w, deps } = world({ sendError: new Error("timeout") });
  assert.equal(await deliverEmail(deps, "other", tenMin), "failed");
  assert.ok(w.emailClaimedAt, "the message may still go, so it is held");
  w.sendError = null;
  assert.equal(await deliverEmail(deps, "other", tenMin), "skipped");
  w.clock += EMAIL_LEASE_MS + 1;
  assert.equal(await deliverEmail(deps, "other", 60 * 60 * 1000), "sent");
});

test("a claim someone else took in the meantime is not overwritten", async () => {
  const { w, deps, touch } = world();
  const send = deps.send;
  const theirs = new Date(NOW + 999).toISOString();
  deps.send = async (a: string) => {
    // Our lease ran out and another request claimed it.
    w.emailClaimedAt = theirs;
    touch();
    await send(a);
  };
  assert.equal(await deliverEmail(deps, "other", tenMin), "sent");
  assert.equal(w.emailedAt, undefined, "it is not ours to mark");
  assert.equal(w.emailClaimedAt, theirs);
});

test("nothing is claimed or counted when it cannot be sent", async () => {
  for (
    const over of [
      { allowed: false },
      { address: null },
      { userId: undefined },
      { createdAtMs: NOW - tenMin - 1 },
      { createdAtMs: NOW + 5 * 60 * 1000 },
      { emailedAt: new Date(NOW - 1).toISOString() },
      { emailClaimedAt: new Date(NOW - 1000).toISOString() },
    ]
  ) {
    const { w, deps } = world(over);
    assert.equal(
      await deliverEmail(deps, "other", tenMin),
      "skipped",
      JSON.stringify(over),
    );
    assert.equal(w.quota.used, 0, JSON.stringify(over));
    assert.equal(w.sent.length, 0);
    assert.equal(w.patches, 0);
  }
});

test("a claim lost to a race is not counted against anyone", async () => {
  const { w, deps } = world();
  deps.patch = async () => null; // every attempt finds it changed again
  assert.equal(await deliverEmail(deps, "other", tenMin), "skipped");
  assert.equal(w.quota.used, 0);
});

test("a refused message takes nothing from the day's room", async () => {
  const { w, deps } = world({ sendError: new Error("auth failed") });
  assert.equal(await deliverEmail(deps, "other", tenMin), "failed");
  assert.equal(w.quota.used, 0);
  // Six failed attempts must not use up six slots.
  for (let i = 0; i < 6; i++) await deliverEmail(deps, "other", tenMin);
  assert.equal(w.quota.used, 0);
  w.sendError = null;
  assert.equal(await deliverEmail(deps, "other", tenMin), "sent");
  assert.equal(w.quota.used, 1);
});

test("a message that timed out keeps its room and its claim", async () => {
  const { w, deps } = world({ sendError: new Error("timeout") });
  assert.equal(await deliverEmail(deps, "other", tenMin), "failed");
  assert.equal(w.quota.used, 1);
  assert.ok(w.emailClaimedAt);
});

test("over the limit at the moment of counting: not sent, claim let go, not kept", async () => {
  const { w, deps } = world();
  w.quota.cap = 0; // the pre-check saw room, then someone else took it
  assert.equal(await deliverEmail(deps, "other", tenMin), "skipped");
  assert.equal(w.sent.length, 0);
  assert.equal(w.quota.used, 0);
  assert.equal(w.emailClaimedAt, undefined);
});

test("several requests that each saw room cannot go past the limit", async () => {
  const quota = { used: 0, cap: 2, fails: false };
  const worlds = [0, 1, 2, 3, 4].map(() => world({ quota }));
  const results = await Promise.all(
    worlds.map(({ deps }) => deliverEmail(deps, "other", tenMin)),
  );
  assert.equal(results.filter((r: string) => r === "sent").length, 2);
  assert.equal(results.filter((r: string) => r === "skipped").length, 3);
  assert.equal(quota.used, 2);
  const sent = worlds.reduce((n, { w }) => n + w.sent.length, 0);
  assert.equal(sent, 2);
});

test("a counter that is down releases the claim instead of stranding it", async () => {
  const { w, deps } = world();
  w.quota.fails = true;
  assert.equal(await deliverEmail(deps, "other", tenMin), "failed");
  assert.equal(w.sent.length, 0);
  assert.equal(w.emailClaimedAt, undefined);
  w.quota.fails = false;
  assert.equal(await deliverEmail(deps, "other", tenMin), "sent");
});
