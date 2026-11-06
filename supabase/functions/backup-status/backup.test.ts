// Run with: node --test backup.test.ts   (Node 23.6 or later)
//
// Tests the "backup handler" region of index.ts. index.ts itself can't be
// imported here (Deno's npm: imports, and it starts the server), so the
// region is cut out, its types stripped, and loaded as a module. The real
// token check, profile lookup and GitHub arrive as fakes through `deps`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const start = source.indexOf("// #region backup handler");
const end = source.indexOf("// #endregion backup handler");
assert.ok(start >= 0 && end > start, "index.ts lost its backup handler region");
const {
  createHandler,
  validArtifactId,
  isBackupName,
  downloadHostAllowed,
  nextBackupAt,
  protectedArtifactId,
} = await import(
  "data:text/javascript," +
    encodeURIComponent(stripTypeScriptTypes(source.slice(start, end)))
);

// ---- pure rules ----------------------------------------------------------

test("artifact ids must be positive whole numbers", () => {
  assert.equal(validArtifactId(123), 123);
  assert.equal(validArtifactId("456"), 456);
  for (const bad of [0, -1, 1.5, "0", "01", "1e3", "12 ", "-5", "", "abc",
    null, undefined, {}, [], "99999999999999999999", Number.MAX_VALUE]) {
    assert.equal(validArtifactId(bad), null, String(bad));
  }
});

test("only the weekly backup's own names count", () => {
  assert.ok(isBackupName("sais-backup-2026-11-01_2000"));
  for (const bad of ["sais-backup-", "sais-backup-2026-11-01", "other",
    "sais-backup-2026-11-01_2000/../x", "xsais-backup-2026-11-01_2000", null]) {
    assert.equal(isBackupName(bad), false, String(bad));
  }
});

test("a download may only go to GitHub's own https hosts", () => {
  assert.ok(downloadHostAllowed(
    "https://pipelines.actions.githubusercontent.com/abc/artifact.zip?sig=1"));
  assert.ok(downloadHostAllowed(
    "https://productionresultssa1.blob.core.windows.net/x/y.zip?sig=1"));
  for (const bad of [
    null, "", "not a url", "http://pipelines.actions.githubusercontent.com/x",
    "https://evil.example.com/x", "https://githubusercontent.com.evil.com/x",
    "https://user:pw@pipelines.actions.githubusercontent.com/x",
    "ftp://github.com/x", "javascript:alert(1)",
  ]) {
    assert.equal(downloadHostAllowed(bad), false, String(bad));
  }
});

test("the next backup is the next Sunday 12:00 UTC", () => {
  // Wed 2026-11-04 -> Sun 2026-11-08
  assert.equal(nextBackupAt(new Date("2026-11-04T09:00:00Z")),
    "2026-11-08T12:00:00.000Z");
  // Sunday before noon -> the same day
  assert.equal(nextBackupAt(new Date("2026-11-08T03:00:00Z")),
    "2026-11-08T12:00:00.000Z");
  // Sunday at/after noon -> a week later
  assert.equal(nextBackupAt(new Date("2026-11-08T12:00:00Z")),
    "2026-11-15T12:00:00.000Z");
  assert.equal(nextBackupAt(new Date("2026-11-08T20:00:00Z")),
    "2026-11-15T12:00:00.000Z");
  // across a month and year end: Wed 2026-12-30 -> Sun 2027-01-03
  assert.equal(nextBackupAt(new Date("2026-12-30T00:00:00Z")),
    "2027-01-03T12:00:00.000Z");
});

const art = (id: number, createdAt: string, extra = {}) => ({
  id, name: "n", sizeBytes: 1, createdAt, expiresAt: null, expired: false,
  runId: id, fromSuccessfulRun: true, ...extra,
});

test("the protected backup is the newest good one that is still there", () => {
  assert.equal(protectedArtifactId([]), null);
  assert.equal(
    protectedArtifactId([art(1, "2026-10-25"), art(2, "2026-11-01")]), 2);
  // a failed run's artifact is never the protected one
  assert.equal(protectedArtifactId([
    art(1, "2026-10-25"),
    art(2, "2026-11-01", { fromSuccessfulRun: false }),
  ]), 1);
  // an expired one is skipped
  assert.equal(protectedArtifactId([
    art(1, "2026-10-25"),
    art(2, "2026-11-01", { expired: true }),
  ]), 1);
  assert.equal(protectedArtifactId([
    art(2, "2026-11-01", { fromSuccessfulRun: false }),
  ]), null);
});

// ---- the handler, with a fake GitHub -------------------------------------

const NOW = new Date("2026-11-04T09:00:00Z");

function ghArtifact(id: number, runId: number, created: string, name?: string,
  extra = {}) {
  return {
    id, name: name ?? `sais-backup-${created.slice(0, 10)}_2000`,
    size_in_bytes: 84_000_000, created_at: created,
    expires_at: "2026-12-01T00:00:00Z", expired: false,
    workflow_run: { id: runId }, ...extra,
  };
}

function ghRun(id: number, conclusion: string | null, created: string) {
  return { id, status: conclusion ? "completed" : "in_progress", conclusion,
    event: "schedule", created_at: created };
}

/** A fake GitHub. `calls` records each request as "METHOD path". */
function makeGithub(opts: {
  runs?: unknown[]; artifacts?: unknown[]; zipStatus?: number;
  zipLocation?: string | null; deleteStatus?: number; failWith?: number;
  rateLimited?: boolean;
} = {}) {
  const calls: string[] = [];
  const runs = opts.runs ?? [
    ghRun(30, "success", "2026-11-01T12:00:00Z"),
    ghRun(20, "failure", "2026-10-25T12:00:00Z"),
    ghRun(10, "success", "2026-10-18T12:00:00Z"),
  ];
  const artifacts = opts.artifacts ?? [
    ghArtifact(300, 30, "2026-11-01T12:05:00Z"),
    ghArtifact(200, 20, "2026-10-25T12:05:00Z"),
    ghArtifact(100, 10, "2026-10-18T12:05:00Z"),
    ghArtifact(999, 30, "2026-11-01T12:06:00Z", "something-else"),
    ghArtifact(998, 777, "2026-11-01T12:06:00Z", "sais-backup-2026-11-01_1111"),
  ];
  const fetchFake = async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    calls.push(`${method} ${url.pathname}${url.search}`);
    assert.equal(url.host, "api.github.com");
    const headers = init?.headers as Record<string, string>;
    assert.equal(headers.Authorization, "Bearer gh-token");
    if (opts.failWith) {
      return new Response("{}", {
        status: opts.failWith,
        headers: opts.rateLimited ? { "x-ratelimit-remaining": "0" } : {},
      });
    }
    const path = url.pathname.replace("/repos/owner/repo", "");
    if (path === "/actions/workflows/backup.yml/runs") {
      const onlyOk = url.searchParams.get("status") === "success";
      const list = onlyOk
        ? (runs as { conclusion: string }[]).filter((r) => r.conclusion === "success").slice(0, 1)
        : runs;
      return Response.json({ workflow_runs: list });
    }
    if (path === "/actions/artifacts") {
      return Response.json({ artifacts });
    }
    const zip = path.match(/^\/actions\/artifacts\/(\d+)\/zip$/);
    if (zip) {
      assert.equal(init?.redirect, "manual");
      const status = opts.zipStatus ?? 302;
      const location = opts.zipLocation === undefined
        ? "https://pipelines.actions.githubusercontent.com/x/a.zip?sig=1"
        : opts.zipLocation;
      return new Response(null, {
        status, headers: location && status === 302 ? { location } : {},
      });
    }
    if (method === "DELETE" && /^\/actions\/artifacts\/\d+$/.test(path)) {
      return new Response(null, { status: opts.deleteStatus ?? 204 });
    }
    return new Response("{}", { status: 404 });
  };
  return { fetchFake, calls };
}

function makeHandler(github: ReturnType<typeof makeGithub>, over: Record<string, unknown> = {}) {
  const profiles: Record<string, unknown> = {
    admin: { role: "Admin", status: "Active" },
    head: { role: "Head", status: "Active" },
    sv: { role: "Supervisor", status: "Active" },
    sa: { role: "Student Assistant", status: "Active" },
    gone: { role: "Admin", status: "Archived" },
  };
  return createHandler({
    verify: async (token: string) => {
      if (token === "bad") throw new Error("bad token");
      if (token === "unverified") return { sub: "admin", email_verified: false };
      if (token === "nosub") return { email_verified: true };
      return { sub: token, email_verified: true };
    },
    loadProfile: async (uid: string) => {
      if (uid === "outage") throw new Error("down");
      return (profiles[uid] ?? null) as never;
    },
    fetch: github.fetchFake as never,
    githubToken: "gh-token",
    repo: "owner/repo",
    now: () => NOW,
    ...over,
  });
}

function call(handler: (r: Request) => Promise<Response>, token: string | null,
  body: unknown, method = "POST") {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return handler(new Request("https://x.test/backup-status", {
    method, headers, body: method === "POST" ? JSON.stringify(body) : undefined,
  }));
}

test("list: shows the weekly backups only, newest first, with the protected one", async () => {
  const github = makeGithub();
  const response = await call(makeHandler(github), "admin", { action: "list" });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const data = await response.json();
  assert.deepEqual(data.artifacts.map((a: { id: number }) => a.id), [300, 200, 100]);
  assert.equal(data.protectedId, 300);
  assert.equal(data.artifacts[1].fromSuccessfulRun, false);
  assert.equal(data.storedBytes, 3 * 84_000_000);
  assert.equal(data.lastSuccessAt, "2026-11-01T12:00:00Z");
  assert.equal(data.nextRunAt, "2026-11-08T12:00:00.000Z");
  assert.equal(data.runs.length, 3);
  assert.equal(data.runs[1].conclusion, "failure");
});

test("list: a second call inside 30 seconds is answered from the cache", async () => {
  const github = makeGithub();
  const handler = makeHandler(github);
  await call(handler, "admin", { action: "list" });
  const before = github.calls.length;
  await call(handler, "admin", { action: "list" });
  assert.equal(github.calls.length, before);
});

test("list: keeps asking for pages while they are full", async () => {
  const many = Array.from({ length: 100 }, (_, i) =>
    ghArtifact(1000 + i, 30, "2026-11-01T12:05:00Z", "other-" + i));
  const github = makeGithub({ artifacts: many });
  const response = await call(makeHandler(github), "admin", { action: "list" });
  assert.equal(response.status, 200);
  const pages = github.calls.filter((c) => c.includes("/actions/artifacts?"));
  assert.ok(pages.length >= 2, "a full page should trigger the next page");
});

test("only an active Admin gets through", async () => {
  for (const who of ["head", "sv", "sa", "nobody"]) {
    const response = await call(makeHandler(makeGithub()), who, { action: "list" });
    assert.equal(response.status, 403, who);
  }
  assert.equal(
    (await call(makeHandler(makeGithub()), "gone", { action: "list" })).status, 403);
});

test("token problems are 401 / 403, a profile outage is 503", async () => {
  const handler = makeHandler(makeGithub());
  assert.equal((await call(handler, null, { action: "list" })).status, 401);
  assert.equal((await call(handler, "bad", { action: "list" })).status, 401);
  assert.equal((await call(handler, "nosub", { action: "list" })).status, 401);
  assert.equal((await call(handler, "unverified", { action: "list" })).status, 403);
  assert.equal((await call(handler, "outage", { action: "list" })).status, 503);
});

test("GitHub is never called for someone who isn't an Admin", async () => {
  const github = makeGithub();
  await call(makeHandler(github), "head", { action: "list" });
  await call(makeHandler(github), null, { action: "list" });
  assert.deepEqual(github.calls, []);
});

test("methods and bodies: GET is 405, junk and big bodies are refused", async () => {
  const handler = makeHandler(makeGithub());
  assert.equal((await call(handler, "admin", null, "GET")).status, 405);
  const options = await handler(new Request("https://x.test/", { method: "OPTIONS" }));
  assert.equal(options.status, 200);
  assert.equal((await call(handler, "admin", { action: "nope" })).status, 400);
  assert.equal((await call(handler, "admin", "text")).status, 400);
  const big = await handler(new Request("https://x.test/", {
    method: "POST",
    headers: { Authorization: "Bearer admin", "content-type": "application/json" },
    body: JSON.stringify({ action: "list", pad: "x".repeat(5000) }),
  }));
  assert.equal(big.status, 413);
});

test("a missing GitHub token says so, to the Admin only", async () => {
  const handler = makeHandler(makeGithub(), { githubToken: "" });
  const admin = await call(handler, "admin", { action: "list" });
  assert.equal(admin.status, 503);
  assert.match((await admin.json()).error, /GITHUB_BACKUP_TOKEN/);
  assert.equal((await call(handler, "head", { action: "list" })).status, 403);
});

test("download: returns GitHub's short-lived link and asks for no redirect", async () => {
  const github = makeGithub();
  const response = await call(makeHandler(github), "admin",
    { action: "download", artifactId: 200 });
  assert.equal(response.status, 200);
  assert.match((await response.json()).url, /^https:\/\/pipelines\.actions\.githubusercontent\.com\//);
  assert.ok(github.calls.includes("GET /repos/owner/repo/actions/artifacts/200/zip"));
});

test("download: refuses ids that aren't this repo's weekly backups", async () => {
  for (const id of [999, 998, 12345, "abc", -1, null]) {
    const github = makeGithub();
    const response = await call(makeHandler(github), "admin",
      { action: "download", artifactId: id });
    assert.ok([400, 404].includes(response.status), String(id));
    assert.ok(!github.calls.some((c) => c.includes("/zip")), String(id));
  }
});

test("download: a redirect to an unexpected place, or none, is refused", async () => {
  for (const zipLocation of ["https://evil.example.com/a.zip", "http://pipelines.actions.githubusercontent.com/a.zip", null]) {
    const response = await call(
      makeHandler(makeGithub({ zipLocation })), "admin",
      { action: "download", artifactId: 300 });
    assert.equal(response.status, 502, String(zipLocation));
    assert.equal((await response.json()).url, undefined);
  }
});

test("download: GitHub saying 410 means it expired", async () => {
  const response = await call(
    makeHandler(makeGithub({ zipStatus: 410 })), "admin",
    { action: "download", artifactId: 300 });
  assert.equal(response.status, 410);
});

test("download: an expired artifact isn't asked for", async () => {
  const github = makeGithub({
    artifacts: [ghArtifact(300, 30, "2026-11-01T12:05:00Z", undefined, { expired: true })],
  });
  const response = await call(makeHandler(github), "admin",
    { action: "download", artifactId: 300 });
  assert.equal(response.status, 410);
  assert.ok(!github.calls.some((c) => c.includes("/zip")));
});

test("delete: removes an older backup (204)", async () => {
  const github = makeGithub();
  const response = await call(makeHandler(github), "admin",
    { action: "delete", artifactId: 100 });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert.ok(github.calls.includes("DELETE /repos/owner/repo/actions/artifacts/100"));
});

test("delete: the newest good backup is protected", async () => {
  const github = makeGithub();
  const response = await call(makeHandler(github), "admin",
    { action: "delete", artifactId: 300 });
  assert.equal(response.status, 409);
  assert.ok(!github.calls.some((c) => c.startsWith("DELETE")));
});

test("delete: a failed run's artifact may go, and the newest good one stays protected", async () => {
  // The newest artifact (400) is from a failed run, so the older good one
  // (300) is the protected one.
  const github = makeGithub({
    runs: [ghRun(40, "failure", "2026-11-03T12:00:00Z"),
      ghRun(30, "success", "2026-11-01T12:00:00Z")],
    artifacts: [ghArtifact(400, 40, "2026-11-03T12:05:00Z"),
      ghArtifact(300, 30, "2026-11-01T12:05:00Z")],
  });
  const handler = makeHandler(github);
  assert.equal((await call(handler, "admin",
    { action: "delete", artifactId: 300 })).status, 409);
  assert.equal((await call(handler, "admin",
    { action: "delete", artifactId: 400 })).status, 200);
});

test("delete: an already-deleted backup (404) counts as done; other errors don't", async () => {
  const gone = await call(makeHandler(makeGithub({ deleteStatus: 404 })), "admin",
    { action: "delete", artifactId: 100 });
  assert.equal(gone.status, 200);
  const broken = await call(makeHandler(makeGithub({ deleteStatus: 500 })), "admin",
    { action: "delete", artifactId: 100 });
  assert.equal(broken.status, 502);
});

test("delete: decides on GitHub's answer right now, not a cached one", async () => {
  // The list was cached while the newest run was still going, so the older
  // backup (100) looked like the newest good one only because 300 was not
  // there yet. Once 300 has finished, deleting 300 must be refused.
  let finished = false;
  const github = makeGithub();
  const inner = github.fetchFake;
  const fetchFake = async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(input));
    if (!finished && url.pathname.endsWith("/runs") &&
      url.searchParams.get("status") !== "success") {
      github.calls.push("GET runs (before)");
      return Response.json({ workflow_runs: [
        ghRun(30, null, "2026-11-01T12:00:00Z"),
        ghRun(10, "success", "2026-10-18T12:00:00Z"),
      ] });
    }
    return inner(input, init);
  };
  const handler = makeHandler({ ...github, fetchFake });
  const first = await (await call(handler, "admin", { action: "list" })).json();
  assert.equal(first.protectedId, 100);
  finished = true;
  const response = await call(handler, "admin", { action: "delete", artifactId: 300 });
  assert.equal(response.status, 409);
  assert.ok(!github.calls.some((c) => c.startsWith("DELETE")));
});

test("delete: the list is looked at again afterwards", async () => {
  const github = makeGithub();
  const handler = makeHandler(github);
  await call(handler, "admin", { action: "list" });
  await call(handler, "admin", { action: "delete", artifactId: 100 });
  const before = github.calls.length;
  await call(handler, "admin", { action: "list" });
  assert.ok(github.calls.length > before, "the cache should be dropped");
});

test("GitHub errors are told apart in plain words", async () => {
  const cases: [number, boolean, number, RegExp][] = [
    [401, false, 502, /wrong or has expired/],
    [403, false, 502, /isn't allowed/],
    [403, true, 503, /busy/],
    [429, false, 503, /busy/],
    [404, false, 502, /can't find/],
    [500, false, 502, /didn't answer properly/],
  ];
  for (const [failWith, rateLimited, status, message] of cases) {
    const response = await call(
      makeHandler(makeGithub({ failWith, rateLimited })), "admin", { action: "list" });
    assert.equal(response.status, status, `${failWith}`);
    assert.match((await response.json()).error, message);
  }
});

test("a network failure to GitHub is a plain 502", async () => {
  const handler = makeHandler(makeGithub(), {
    fetch: async () => { throw new Error("offline"); },
  });
  const response = await call(handler, "admin", { action: "list" });
  assert.equal(response.status, 502);
});
