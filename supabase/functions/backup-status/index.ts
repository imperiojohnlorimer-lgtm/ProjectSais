// backup-status: lets the Admin see, download and delete the weekly backups
// that the GitHub Actions workflow "SAIS Weekly Backup" makes, without opening
// the private repository. The GitHub token lives only here, as the secret
// GITHUB_BACKUP_TOKEN (a fine-grained token for that one repository with the
// single permission "Actions: Read and write"). Verify JWT must be OFF: the
// function checks the caller's Firebase ID token itself and lets only an
// active Admin account through.
//
// Secrets: GITHUB_BACKUP_TOKEN, and optionally GITHUB_BACKUP_REPO
// ("owner/name", default below).
//
// POST (JSON, Authorization: Bearer <Firebase ID token>):
//   {"action":"list", "fresh":true?}   -> the overview below
//   {"action":"download","artifactId"} -> {"url": short-lived GitHub link}
//   {"action":"delete","artifactId"}   -> {"ok": true}
//
// The backups are encrypted (.sais); nothing here can open one, and the
// passphrase never reaches this function.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.10.0";

const firebaseProjectId = "sais-6168b";
const defaultRepo = "imperiojohnlorimer-lgtm/ProjectSaisBackup";

const firebaseKeys = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

/** The caller's own profile, read with their own token (the Firestore rules
 * let anyone read their own document). Null when there is none; throws when
 * Firestore can't answer, so an outage never reads as "not an Admin". */
async function loadProfile(
  userId: string,
  firebaseToken: string,
): Promise<{ role?: string; status?: string } | null> {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${encodeURIComponent(userId)}`,
    { headers: { Authorization: `Bearer ${firebaseToken}` } },
  );
  if (response.status === 404) return null;
  if (!response.ok) throw new Error("profile unavailable");
  const document = await response.json();
  return {
    role: document.fields?.role?.stringValue,
    status: document.fields?.status?.stringValue,
  };
}

// #region backup handler
// backup.test.ts runs this region on its own, so it must not use anything
// from the rest of this file (the real jose / fetch / secrets arrive through
// `deps`).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const workflowFile = "backup.yml";
const maxBodyChars = 2000;
const cacheMs = 30_000;
// "Refresh" may skip the cache, but not more often than this.
const freshAfterMs = 5_000;
const maxArtifactPages = 10;

function json(data: unknown, status = 200) {
  return Response.json(data, {
    status,
    headers: { ...corsHeaders, "Cache-Control": "no-store" },
  });
}

/** A positive whole number from the app, as a number or a digit string. */
export function validArtifactId(value: unknown): number | null {
  if (typeof value === "number") {
    return Number.isSafeInteger(value) && value > 0 ? value : null;
  }
  if (typeof value === "string" && /^[1-9][0-9]{0,15}$/.test(value)) {
    const number = Number(value);
    return Number.isSafeInteger(number) ? number : null;
  }
  return null;
}

/** Only the weekly backup's own artifacts: sais-backup-2026-11-01_2000. */
export function isBackupName(name: unknown): boolean {
  return typeof name === "string" &&
    /^sais-backup-\d{4}-\d{2}-\d{2}_\d{4}$/.test(name);
}

/** Where GitHub may send a download: https, no credentials, and one of
 * GitHub's own storage hosts. Anything else is refused, never followed. */
export function downloadHostAllowed(location: string | null): boolean {
  if (!location) return false;
  let url: URL;
  try {
    url = new URL(location);
  } catch (_) {
    return false;
  }
  if (url.protocol !== "https:") return false;
  if (url.username || url.password) return false;
  const host = url.hostname.toLowerCase();
  return ["githubusercontent.com", "blob.core.windows.net", "github.com"]
    .some((suffix) => host === suffix || host.endsWith("." + suffix));
}

/** The next Sunday 12:00 UTC (8 PM in Manila) after [now]: the schedule in
 * the backup repo's workflow. */
export function nextBackupAt(now: Date): string {
  const day = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
    12,
  ));
  day.setUTCDate(day.getUTCDate() + ((7 - day.getUTCDay()) % 7));
  if (day.getTime() <= now.getTime()) day.setUTCDate(day.getUTCDate() + 7);
  return day.toISOString();
}

type Artifact = {
  id: number;
  name: string;
  sizeBytes: number;
  createdAt: string;
  expiresAt: string | null;
  expired: boolean;
  runId: number;
  fromSuccessfulRun: boolean;
};

/** The newest backup that is still there and came from a successful run.
 * It is the one that must always remain. */
export function protectedArtifactId(artifacts: Artifact[]): number | null {
  let best: Artifact | null = null;
  for (const artifact of artifacts) {
    if (artifact.expired || !artifact.fromSuccessfulRun) continue;
    if (!best || artifact.createdAt > best.createdAt) best = artifact;
  }
  return best ? best.id : null;
}

// deno-lint-ignore no-explicit-any
function mapRun(run: any) {
  return {
    id: run.id as number,
    status: String(run.status ?? ""),
    conclusion: run.conclusion == null ? null : String(run.conclusion),
    event: String(run.event ?? ""),
    createdAt: String(run.created_at ?? ""),
  };
}

type Deps = {
  /** The verified payload of a Firebase ID token; throws when it isn't one. */
  verify: (token: string) => Promise<{ sub?: unknown; email_verified?: unknown }>;
  loadProfile: (
    userId: string,
    token: string,
  ) => Promise<{ role?: string; status?: string } | null>;
  fetch: typeof fetch;
  githubToken: string;
  repo: string;
  now: () => Date;
};

class GithubFailure extends Error {
  response: Response;
  constructor(response: Response) {
    super("github");
    this.response = response;
  }
}

/** Plain words for a GitHub answer that wasn't a success. */
function githubFailure(upstream: Response): Response {
  const status = upstream.status;
  if (status === 401) {
    return json({
      error:
        "The GitHub token is wrong or has expired. Make a new one and replace GITHUB_BACKUP_TOKEN in Supabase.",
    }, 502);
  }
  if (status === 429 || (status === 403 &&
    upstream.headers.get("x-ratelimit-remaining") === "0")) {
    return json({
      error: "GitHub is busy right now. Try again in a minute.",
    }, 503);
  }
  if (status === 403) {
    return json({
      error:
        "The GitHub token isn't allowed to do that. It needs 'Actions: Read and write' on the backup repository.",
    }, 502);
  }
  if (status === 404) {
    return json({
      error:
        "GitHub can't find the backup repository or its workflow. Check GITHUB_BACKUP_REPO and the token's repository.",
    }, 502);
  }
  return json({
    error: `GitHub didn't answer properly (${status}). Try again later.`,
  }, 502);
}

export function createHandler(deps: Deps) {
  let cache: { at: number; data: unknown } | null = null;

  async function gh(path: string, init: RequestInit = {}) {
    return await deps.fetch(
      `https://api.github.com/repos/${deps.repo}${path}`,
      {
        ...init,
        headers: {
          Authorization: `Bearer ${deps.githubToken}`,
          Accept: "application/vnd.github+json",
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": "sais-backup-status",
        },
        signal: AbortSignal.timeout(10_000),
      },
    );
  }

  async function ghJson(path: string) {
    const response = await gh(path);
    if (!response.ok) throw new GithubFailure(response);
    return await response.json();
  }

  async function buildOverview() {
    const [runsBody, successBody] = await Promise.all([
      ghJson(`/actions/workflows/${workflowFile}/runs?per_page=100`),
      ghJson(
        `/actions/workflows/${workflowFile}/runs?status=success&per_page=1`,
      ),
    ]);
    // deno-lint-ignore no-explicit-any
    const runs: any[] = runsBody.workflow_runs ?? [];
    const runIds = new Set<number>(runs.map((run) => run.id));
    const successIds = new Set<number>(
      runs.filter((run) => run.conclusion === "success").map((run) => run.id),
    );

    // The name filter in the API is exact-match only, so list every page and
    // keep the weekly backups' own names.
    // deno-lint-ignore no-explicit-any
    const found: any[] = [];
    for (let page = 1; page <= maxArtifactPages; page++) {
      const body = await ghJson(
        `/actions/artifacts?per_page=100&page=${page}`,
      );
      const items = body.artifacts ?? [];
      found.push(...items);
      if (items.length < 100) break;
    }

    const artifacts: Artifact[] = found
      .filter((artifact) =>
        isBackupName(artifact.name) &&
        runIds.has(artifact.workflow_run?.id)
      )
      .map((artifact) => ({
        id: artifact.id as number,
        name: String(artifact.name),
        sizeBytes: Number(artifact.size_in_bytes ?? 0),
        createdAt: String(artifact.created_at ?? ""),
        expiresAt: artifact.expires_at == null
          ? null
          : String(artifact.expires_at),
        expired: artifact.expired === true,
        runId: artifact.workflow_run.id as number,
        fromSuccessfulRun: successIds.has(artifact.workflow_run.id),
      }))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));

    const lastSuccess = (successBody.workflow_runs ?? [])[0];
    return {
      runs: runs.slice(0, 10).map(mapRun),
      lastSuccessAt: lastSuccess ? String(lastSuccess.created_at ?? "") : null,
      artifacts,
      storedBytes: artifacts
        .filter((artifact) => !artifact.expired)
        .reduce((sum, artifact) => sum + artifact.sizeBytes, 0),
      protectedId: protectedArtifactId(artifacts),
      nextRunAt: nextBackupAt(deps.now()),
      fetchedAt: deps.now().toISOString(),
    };
  }

  /** The overview, from the short-lived cache when allowed. [fresh] is the
   * Refresh button (it may reuse an answer under 5 seconds old); [force] is
   * for a delete, which must decide on what GitHub says right now. */
  async function overview(fresh: boolean, force = false) {
    const nowMs = deps.now().getTime();
    if (cache && !force) {
      const age = nowMs - cache.at;
      if (age < cacheMs && !(fresh && age > freshAfterMs)) {
        return cache.data as Awaited<ReturnType<typeof buildOverview>>;
      }
    }
    const data = await buildOverview();
    cache = { at: nowMs, data };
    return data;
  }

  return async function handle(request: Request): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return json({ error: "Only POST is supported." }, 405);
    }

    try {
      const authorization = request.headers.get("Authorization");
      if (!authorization?.startsWith("Bearer ")) {
        return json({ error: "Missing Firebase token." }, 401);
      }
      const token = authorization.substring("Bearer ".length);

      let payload;
      try {
        payload = await deps.verify(token);
      } catch (_) {
        return json({ error: "Please sign in again." }, 401);
      }
      const userId = payload.sub;
      if (!userId || typeof userId !== "string") {
        return json({ error: "Invalid Firebase user ID." }, 401);
      }
      if (payload.email_verified !== true) {
        return json({ error: "Please verify your email address first." }, 403);
      }

      let profile;
      try {
        profile = await deps.loadProfile(userId, token);
      } catch (_) {
        return json(
          { error: "Could not check your account. Try again in a moment." },
          503,
        );
      }
      if (profile?.status === "Archived") {
        return json({ error: "This account has been deactivated." }, 403);
      }
      if (profile?.role !== "Admin") {
        return json({ error: "Only the Admin can use backups." }, 403);
      }

      if (!deps.githubToken) {
        return json({
          error:
            "Backups aren't set up yet: add the GITHUB_BACKUP_TOKEN secret in Supabase.",
        }, 503);
      }

      const declared = Number(request.headers.get("content-length") ?? "0");
      if (declared > maxBodyChars) {
        return json({ error: "That request is too large." }, 413);
      }
      const text = await request.text();
      if (text.length > maxBodyChars) {
        return json({ error: "That request is too large." }, 413);
      }
      let body;
      try {
        body = JSON.parse(text);
      } catch (_) {
        return json({ error: "Invalid request." }, 400);
      }
      if (!body || typeof body !== "object") {
        return json({ error: "Invalid request." }, 400);
      }

      if (body.action === "list") {
        return json(await overview(body.fresh === true));
      }

      if (body.action === "download" || body.action === "delete") {
        const id = validArtifactId(body.artifactId);
        if (id === null) {
          return json({ error: "Invalid backup." }, 400);
        }
        // Deleting decides on GitHub's answer right now, never the cache (a
        // run may have finished since); downloading may use the cache.
        const current = await overview(false, body.action === "delete");
        const artifact = current.artifacts.find((item) => item.id === id);
        if (!artifact) {
          return json({ error: "That backup was not found." }, 404);
        }

        if (body.action === "download") {
          if (artifact.expired) {
            return json({ error: "That backup has expired." }, 410);
          }
          const upstream = await gh(`/actions/artifacts/${id}/zip`, {
            redirect: "manual",
          });
          if (upstream.status === 410) {
            return json({ error: "That backup has expired." }, 410);
          }
          if (upstream.status !== 302) throw new GithubFailure(upstream);
          const location = upstream.headers.get("location");
          if (!downloadHostAllowed(location)) {
            return json(
              { error: "GitHub sent the download somewhere unexpected." },
              502,
            );
          }
          return json({ url: location });
        }

        if (id === current.protectedId) {
          return json({
            error:
              "That is the newest good backup. SAIS keeps it so a backup always exists. Delete the older ones instead.",
          }, 409);
        }
        const upstream = await gh(`/actions/artifacts/${id}`, {
          method: "DELETE",
        });
        // 204 = deleted; 404 = already gone, which is what was wanted.
        if (upstream.status !== 204 && upstream.status !== 404) {
          throw new GithubFailure(upstream);
        }
        cache = null;
        return json({ ok: true });
      }

      return json({ error: "Invalid request." }, 400);
    } catch (error) {
      if (error instanceof GithubFailure) return githubFailure(error.response);
      console.error("backup-status failed:", String(error).slice(0, 300));
      return json({
        error: "Could not reach GitHub. Try again in a moment.",
      }, 502);
    }
  };
}
// #endregion backup handler

Deno.serve(
  createHandler({
    verify: async (token) =>
      (await jwtVerify(token, firebaseKeys, {
        issuer: `https://securetoken.google.com/${firebaseProjectId}`,
        audience: firebaseProjectId,
      })).payload,
    loadProfile,
    fetch,
    githubToken: Deno.env.get("GITHUB_BACKUP_TOKEN") ?? "",
    repo: Deno.env.get("GITHUB_BACKUP_REPO") ?? defaultRepo,
    now: () => new Date(),
  }),
);
