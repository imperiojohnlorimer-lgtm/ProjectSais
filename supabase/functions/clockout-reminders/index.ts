// Push notifications to SAIS users' phones, through Firebase Cloud
// Messaging, and the same notifications by email. Named for its first job;
// it has four:
//
// 1. Clock-out reminders, on a schedule (below).
// 2. Every other notification: right after the app saves one, it sends the
//    id here (PushService.deliver), and this pushes it to the recipient's
//    devices. Each is read from Firestore and pushed once, only while
//    fresh, so a caller can't choose what's sent or send it twice.
// 3. A test notification to the caller's own devices: the "Send a test"
//    button.
// 4. Email, for people who aren't signed in: every notification the app
//    saves, and each clock-out reminder, is also emailed to the account's
//    own verified address, through Gmail's SMTP server. An email never
//    carries a notification's text (any staff member can write that text for
//    anyone): it says what kind of update it is and links to SAIS. See
//    "email rules" below. Also a "Send a test email" for the caller.
//
// A Supabase cron job calls this at 11:30 AM and 4:30 PM Philippine time,
// 30 minutes before each attendance session ends (see schedule.sql). It
// finds the student assistants still clocked in to that session and sends
// each of their devices a notification through Firebase Cloud Messaging,
// so the reminder reaches a phone with SAIS closed. It also saves the
// in-app notification under the id the app gives it (AppState
// .clockOutReminderId), so the bell shows one reminder whichever of the two
// saves it first.
//
// Deploy with "Verify JWT" off, like clock-attendance. The cron job proves
// itself with CLOCKOUT_REMINDER_SECRET, and the app with a Firebase ID
// token.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// Pinned. Supabase blocks outgoing ports 25 and 587; Gmail takes TLS on 465.
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";
import {
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from "npm:jose@5.10.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const firebaseProjectId = "sais-6168b";
const appUrl = "https://sais-6168b.web.app/";

// The same service account clock-attendance uses (the secrets are shared by
// every function in the project). It needs permission to send messages;
// the Firebase Admin SDK account has it.
const serviceAccountEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
const serviceAccountKey = (Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "")
  .replace(/\\n/g, "\n");

// Set with: Edge Functions → Secrets, the value schedule.sql generates.
const cronSecret = Deno.env.get("CLOCKOUT_REMINDER_SECRET") ?? "";

// Email: a Gmail address and its App Password (Edge Functions → Secrets).
// Neither is ever written into the repo.
const emailFrom = Deno.env.get("EMAIL_FROM_ADDRESS") ?? "";
const emailPassword = Deno.env.get("EMAIL_APP_PASSWORD") ?? "";

const firebaseKeys = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

const documentsRoot =
  `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents`;
const fcmSendUrl =
  `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`;

// Attendance runs on Philippine wall-clock time, taken from this server.
const TZ_OFFSET_MINUTES = 8 * 60;

// #region push text
// What a push says on the lock screen. Pay, ratings, hiring decisions and
// payroll requirements are private: a push's text shows on a locked phone
// and passes through Google's servers, so these kinds are announced without
// their details. The notification itself, in the app, is unchanged.
const privateKinds = new Set([
  "payroll",
  "evaluation",
  "payroll_requirement",
  "rehire",
  "application", // a decision can carry the screening remarks
  "office", // a rehire or placement names the student
]);

export function pushTextFor(
  kind: string | undefined,
  title: string,
  body: string,
): { title: string; body: string } {
  if (kind !== undefined && privateKinds.has(kind)) {
    return { title: "SAIS", body: "You have a new update. Open SAIS to read it." };
  }
  return { title, body };
}
// #endregion push text

// #region email rules
// email.test.ts runs this region together with "push text" (which it uses),
// so it must not use anything else from the rest of this file.

/** Emails a day, across everyone, and per person. Gmail's own limit is about
 * 500 a day; this stays under it. Clock-out reminders count apart. */
export const EMAIL_DAILY_CAP = 400;
export const EMAIL_PER_PERSON_CAP = 6;
export const EMAIL_PER_PERSON_CLOCKOUT_CAP = 4;

/** A claim on sending a notification's email stays valid this long, so a
 * request that dies mid-way doesn't hold it forever. */
export const EMAIL_LEASE_MS = 2 * 60 * 1000;

/** One email gets this long, and one run stops starting new emails after
 * [EMAIL_BUDGET_MS], well inside the function's own wall-clock limit. */
export const EMAIL_SEND_TIMEOUT_MS = 20_000;
export const EMAIL_BUDGET_MS = 90_000;
export const EMAIL_CONCURRENCY = 3;

/** What an email says about each kind of notification. Fixed here, never
 * taken from the notification: staff can write any text for anyone. Kinds
 * that are private (pay, ratings, hiring decisions...) and kinds not known
 * here get the plain wording, as a push does. */
const emailKinds: Record<string, string> = {
  task: "a task",
  announcement: "an announcement",
  report: "a report",
  attendance: "your attendance",
  head_forward: "a document sent to the Head",
  dtr_report: "a DTR / Accomplishment Report",
  academic_year: "the academic year",
};

export type EmailMessage = { subject: string; text: string; html: string };

export function htmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * The email for a notification of [kind]: only its kind and a link to SAIS.
 * [about] is what the email is about when the function builds the sentence
 * itself from trusted data (the clock-out reminder).
 */
export function emailFor(
  kind: string | undefined,
  link: string,
  address: string,
  about?: { subject: string; sentence: string },
): EmailMessage {
  let subject: string;
  let sentence: string;
  if (about) {
    subject = about.subject;
    sentence = about.sentence;
  } else if (
    kind !== undefined && !privateKinds.has(kind) && emailKinds[kind]
  ) {
    subject = "SAIS: you have a new update";
    sentence = `You have a new update about ${emailKinds[kind]}.`;
  } else {
    subject = "SAIS: you have a new update";
    sentence = "You have a new update.";
  }
  const footer =
    `You get this email because email notifications are on for your SAIS ` +
    `account (${address}). To stop them, sign in, open Notifications and ` +
    `turn off "Email notifications".`;
  const text = [
    sentence,
    "",
    `Open SAIS: ${link}`,
    "",
    footer,
    "",
    "SAIS, Marinduque State University",
  ].join("\n");
  const html =
    `<p>${htmlEscape(sentence)}</p>` +
    `<p><a href="${htmlEscape(link)}">Open SAIS</a></p>` +
    `<p style="color:#64748b;font-size:12px">${htmlEscape(footer)}</p>` +
    `<p style="color:#64748b;font-size:12px">SAIS, Marinduque State University</p>`;
  return { subject, text, html };
}

/** One plain mailbox: no list, no name part, no control characters. */
export function validMailbox(address: unknown): address is string {
  return typeof address === "string" &&
    address.length <= 254 &&
    // deno-lint-ignore no-control-regex
    !/[\x00-\x1f\x7f\s,;<>"()\\]/.test(address) &&
    /^[^@]+@[^@.]+(\.[^@.]+)+$/.test(address);
}

/** Where a notification's email stands, from its stored fields. */
export function emailState(
  fields: { emailedAt?: unknown; emailClaimedAt?: string },
  nowMs: number,
): "done" | "leased" | "free" {
  if (fields.emailedAt) return "done";
  const claimed = Date.parse(fields.emailClaimedAt ?? "");
  if (Number.isFinite(claimed) && nowMs - claimed < EMAIL_LEASE_MS) {
    return "leased";
  }
  return "free";
}

/** Whether a stored timestamp is the instant [ms] (Firestore may write it
 * back with different fractional digits). */
export function sameInstant(stored: string | undefined, ms: number): boolean {
  return Date.parse(stored ?? "") === ms;
}

/**
 * Runs [work] on every item, [limit] at a time, and stops starting new ones
 * once [stop] says so. One item failing must not stop the rest, so [work]
 * handles its own errors.
 */
export async function runPool<T>(
  items: T[],
  limit: number,
  work: (item: T) => Promise<void>,
  stop: () => boolean,
): Promise<void> {
  let next = 0;
  const lanes = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length && !stop()) {
      const item = items[next++];
      await work(item);
    }
  });
  await Promise.all(lanes);
}

/** Whether a notification saved at [savedMs] is recent enough to send: not
 * older than [maxAgeMs], and not dated in the future. */
export function isFreshNotification(
  savedMs: number,
  nowMs: number,
  maxAgeMs: number,
): boolean {
  return Number.isFinite(savedMs) && savedMs <= nowMs + 60_000 &&
    nowMs - savedMs < maxAgeMs;
}

/** What the email core needs to know about a notification. */
export type NotificationView = {
  updateTime: string;
  userId?: string;
  type?: string;
  createdAtMs: number;
  emailedAt?: string;
  emailClaimedAt?: string;
};

/** A change to a notification's email state. */
export type EmailChange =
  | { claimAtMs: number }
  | { sentAtMs: number }
  | { release: true };

/** Everything the email core does to the outside world, so it can be tested
 * against a fake Firestore. [patch] applies only if the notification still
 * has [updateTime], and returns the new one (or null when refused). */
export type EmailDeps = {
  now(): number;
  read(): Promise<NotificationView | null>;
  patch(updateTime: string, change: EmailChange): Promise<string | null>;
  recipient(userId: string): Promise<string | null>;
  /** A read-only look: is there room today? Nothing is counted. */
  allowed(userId: string, kind: "other" | "clockout"): Promise<boolean>;
  /** Counts one email against today's limits, atomically, and says whether
   * it was within them. When it was not, the count is already taken back. */
  reserve(userId: string, kind: "other" | "clockout"): Promise<boolean>;
  /** Takes back a count (the email was not sent). */
  refund(userId: string, kind: "other" | "clockout"): Promise<void>;
  send(address: string, type: string | undefined): Promise<void>;
  isTimeout(error: unknown): boolean;
  log(message: string): void;
};

/**
 * Finishes our claim [stamp]: marks the email sent, or (with [release]) lets
 * go of the claim so the next request can try. Only while the claim is still
 * ours (its lease may have run out and been taken by another request), and
 * re-reading when some other write moved the update time.
 */
export async function settleEmail(
  deps: EmailDeps,
  stamp: number,
  release: boolean,
): Promise<void> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const doc = await deps.read();
    if (!doc) return;
    if (!sameInstant(doc.emailClaimedAt, stamp)) return;
    const done = await deps.patch(
      doc.updateTime,
      release ? { release: true } : { sentAtMs: deps.now() },
    );
    if (done) return;
  }
  deps.log(
    "Could not record the email; it may be sent again once its claim runs out.",
  );
}

/**
 * Emails one notification to its recipient, once. Eligibility and the day's
 * room are checked first (reads only); then it is claimed (a short lease),
 * so two requests can't both send it, and other writes to the notification
 * (it being read or pushed) cause a re-read, not a give-up. The email is
 * counted against the day's limits only once the claim is ours, and the
 * count is taken back if it isn't sent. When sent it is marked; if sending
 * failed the claim is let go, so the next request can try. If the mail
 * server didn't answer in time the claim is left to run out instead (the
 * message may still go), and one that was accepted but couldn't be recorded
 * may be sent twice: both accepted over losing it.
 */
export async function deliverEmail(
  deps: EmailDeps,
  kind: "other" | "clockout",
  maxAgeMs: number,
): Promise<"sent" | "skipped" | "failed"> {
  const first = await deps.read();
  if (!first || !first.userId) return "skipped";
  if (!isFreshNotification(first.createdAtMs, deps.now(), maxAgeMs)) {
    return "skipped";
  }
  if (emailState(first, deps.now()) !== "free") return "skipped";

  const address = await deps.recipient(first.userId);
  if (!address) return "skipped";
  if (!await deps.allowed(first.userId, kind)) {
    deps.log("Email limit reached; not emailed.");
    return "skipped";
  }

  const stamp = deps.now();
  let claimed = false;
  for (let attempt = 0; attempt < 3 && !claimed; attempt++) {
    const doc = attempt === 0 ? first : await deps.read();
    if (!doc) break;
    if (emailState(doc, deps.now()) !== "free") break;
    claimed = (await deps.patch(doc.updateTime, { claimAtMs: stamp })) !== null;
  }
  if (!claimed) return "skipped"; // sent, or claimed by another request

  // The room is taken now that the claim is ours, atomically: of several
  // requests that each saw room, only those within the limits go on.
  let within: boolean;
  try {
    within = await deps.reserve(first.userId, kind);
  } catch (error) {
    deps.log(`Email counter failed: ${error}`);
    await settleEmail(deps, stamp, true);
    return "failed";
  }
  if (!within) {
    deps.log("Email limit reached; not emailed.");
    await settleEmail(deps, stamp, true);
    return "skipped";
  }
  try {
    await deps.send(address, first.type);
  } catch (error) {
    deps.log(`Email failed: ${error}`);
    // A message that was refused takes nothing from the day's room, and the
    // claim goes back so the next request can try. One that timed out may
    // still go, so its count and claim stay until the lease runs out.
    if (!deps.isTimeout(error)) {
      await deps.refund(first.userId, kind).catch(() => {});
      await settleEmail(deps, stamp, true);
    }
    return "failed";
  }
  await settleEmail(deps, stamp, false);
  return "sent";
}
// #endregion email rules

// #region reminder rules
// reminders.test.ts runs this region on its own, so it must not use
// anything from the rest of this file. (It stays in this file so the
// function deploys as a single index.ts, as the dashboard editor needs.)

// The two daily sessions, in minutes past midnight. These mirror
// clock-attendance and AppState — keep them in step.
export const MORNING_START = 7 * 60 + 30; // 7:30 AM
export const MORNING_END = 12 * 60; // 12:00 PM
export const AFTERNOON_START = 12 * 60 + 30; // 12:30 PM
export const AFTERNOON_END = 17 * 60; // 5:00 PM

/** How long before a session ends the reminder goes out
 * (AppState.clockOutReminderLead). */
export const LEAD_MINUTES = 30;

export type SessionHalf = "AM" | "PM";

/** Minutes past midnight for a `2:36 PM`-style time, or null. */
export function parseTimeMinutes(value: string): number | null {
  const match = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec((value ?? "").trim());
  if (!match) return null;
  let hour = parseInt(match[1], 10) % 12;
  if (match[3].toUpperCase() === "PM") hour += 12;
  return hour * 60 + parseInt(match[2], 10);
}

/** The session [minutes] past midnight falls in, or null outside both. */
export function sessionHalf(minutes: number): SessionHalf | null {
  if (minutes >= MORNING_START && minutes <= MORNING_END) return "AM";
  if (minutes >= AFTERNOON_START && minutes <= AFTERNOON_END) return "PM";
  return null;
}

/** The session that ends within [LEAD_MINUTES] of [minutes] past
 * midnight, or null. */
export function endingSession(minutes: number): SessionHalf | null {
  if (minutes >= MORNING_END - LEAD_MINUTES && minutes < MORNING_END) {
    return "AM";
  }
  if (minutes >= AFTERNOON_END - LEAD_MINUTES && minutes < AFTERNOON_END) {
    return "PM";
  }
  return null;
}

/**
 * Whether a record timed in at [timeIn] is reminded as [half] ends: it
 * belongs to that session and was opened before the reminder went out.
 * Mirrors AppState.clockOutReminderTime.
 */
export function isDue(timeIn: string, half: SessionHalf): boolean {
  const minutes = parseTimeMinutes(timeIn);
  if (minutes === null || sessionHalf(minutes) !== half) return false;
  const end = half === "AM" ? MORNING_END : AFTERNOON_END;
  return minutes < end - LEAD_MINUTES;
}

/** The reminder's text, worded as AppState words it. */
export function reminderMessage(half: SessionHalf): string {
  const [session, end] = half === "AM"
    ? ["morning", "12:00 PM"]
    : ["afternoon", "5:00 PM"];
  return `Your ${session} session ends at ${end}. Scan the attendance QR ` +
    "code to clock out before then, or this session won't count toward " +
    "your hours.";
}
// #endregion reminder rules

const MONTHS = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

type WallClock = {
  year: number;
  month: number; // 0-based
  day: number;
  hour: number;
  minute: number;
  second: number;
};

type Device = { name: string; token: string; userId: string };

type Push = {
  title: string;
  body: string;
  tag: string;
  /** How long FCM keeps trying a phone that's offline. */
  ttlSeconds: number;
  /** Keeps it on a computer's screen until dismissed. */
  requireInteraction: boolean;
  /** The SAIS page a tap opens: the app's address for it, without the
   * leading slash (AppRoutes). */
  page: string;
  data: Record<string, string>;
};

/** How old a notification may be and still be pushed when the app asks. */
const FRESH_MS = 10 * 60 * 1000;

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: corsHeaders });
}

/** Philippine wall-clock fields for a UTC instant. */
function wallClock(instant: Date): WallClock {
  const shifted = new Date(instant.getTime() + TZ_OFFSET_MINUTES * 60000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth(),
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    second: shifted.getUTCSeconds(),
  };
}

/** `Sep 21, 2026`, the shape attendance records store. */
function formattedDate(wc: WallClock) {
  return `${MONTHS[wc.month]} ${wc.day}, ${wc.year}`;
}

/** Compares secrets in time that doesn't depend on where they differ. */
function sameSecret(given: string, expected: string): boolean {
  if (!expected || given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) {
    diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

// ── Google access ───────────────────────────────────────────────────
// As in clock-attendance: the service account is exchanged for an access
// token by hand, here covering Firestore and Cloud Messaging both.
let cachedToken: { value: string; expiresAt: number } | null = null;

async function googleToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  if (!serviceAccountEmail || !serviceAccountKey) {
    throw new Error(
      "FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY are not set on this project.",
    );
  }

  const key = await importPKCS8(serviceAccountKey, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/datastore " +
      "https://www.googleapis.com/auth/firebase.messaging " +
      "https://www.googleapis.com/auth/identitytoolkit",
  })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(serviceAccountEmail)
    .setSubject(serviceAccountEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google token exchange failed: ${await response.text()}`);
  }

  const data = await response.json();
  cachedToken = {
    value: data.access_token,
    expiresAt: now + (data.expires_in ?? 3600),
  };
  return cachedToken.value;
}

type FirestoreDoc = {
  name: string;
  updateTime?: string;
  fields?: Record<
    string,
    {
      stringValue?: string;
      booleanValue?: boolean;
      timestampValue?: string;
      integerValue?: string;
    }
  >;
};

async function getDocument(
  path: string,
  token: string,
): Promise<FirestoreDoc | null> {
  const response = await fetch(`${documentsRoot}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`Firestore read failed (${response.status}).`);
  }
  return await response.json();
}

async function runQuery(
  structuredQuery: unknown,
  token: string,
): Promise<FirestoreDoc[]> {
  const response = await fetch(`${documentsRoot}:runQuery`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ structuredQuery }),
  });
  if (!response.ok) {
    throw new Error(`Firestore query failed (${response.status}).`);
  }
  const rows = await response.json();
  return (Array.isArray(rows) ? rows : [])
    .map((row: { document?: FirestoreDoc }) => row.document)
    .filter((doc): doc is FirestoreDoc => Boolean(doc));
}

/** Whether the account [userId] has been deactivated. */
async function isDeactivated(userId: string, token: string): Promise<boolean> {
  const profile = await getDocument(`users/${encodeURIComponent(userId)}`, token);
  return profile?.fields?.status?.stringValue === "Archived";
}

/** Of [userIds], the accounts that haven't been deactivated. */
async function activeUsers(
  userIds: string[],
  token: string,
): Promise<Set<string>> {
  // An account whose status can't be read is left out, not a reason to
  // stop everyone else's reminder.
  const checked = await Promise.all(
    userIds.map(async (id) => {
      try {
        return [id, !(await isDeactivated(id, token))] as const;
      } catch (error) {
        console.error(`Could not check account ${id}:`, error);
        return [id, false] as const;
      }
    }),
  );
  return new Set(checked.filter(([, active]) => active).map(([id]) => id));
}

/** The devices registered under [userIds] (pushTokens, saved by the app). */
async function devicesOf(userIds: string[], token: string): Promise<Device[]> {
  const devices: Device[] = [];
  // An IN filter takes at most 30 values.
  for (let i = 0; i < userIds.length; i += 30) {
    const docs = await runQuery({
      from: [{ collectionId: "pushTokens" }],
      where: {
        fieldFilter: {
          field: { fieldPath: "userId" },
          op: "IN",
          value: {
            arrayValue: {
              values: userIds.slice(i, i + 30).map((id) => ({
                stringValue: id,
              })),
            },
          },
        },
      },
    }, token);
    for (const doc of docs) {
      const deviceToken = doc.fields?.token?.stringValue;
      const userId = doc.fields?.userId?.stringValue;
      if (deviceToken && userId) {
        devices.push({ name: doc.name, token: deviceToken, userId });
      }
    }
  }
  return devices;
}

/**
 * Sends [push] to one device. Returns "sent", "gone" when FCM no longer
 * knows the device (its entry is deleted, so it isn't tried again), or
 * what went wrong. With [validateOnly], FCM checks the message without
 * delivering it.
 */
async function send(
  device: Device,
  push: Push,
  token: string,
  validateOnly = false,
): Promise<string> {
  const response = await fetch(fcmSendUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      validate_only: validateOnly,
      message: {
        token: device.token,
        data: push.data,
        webpush: {
          headers: { TTL: String(push.ttlSeconds), Urgency: "high" },
          notification: {
            title: push.title,
            body: push.body,
            icon: `${appUrl}icons/Icon-192.png`,
            tag: push.tag,
            requireInteraction: push.requireInteraction,
          },
          fcm_options: { link: `${appUrl}${push.page}` },
        },
      },
    }),
  });
  if (response.ok) return "sent";

  const failure = await response.json().catch(() => ({}));
  const message: string = failure?.error?.message ?? "";
  const code: string | undefined = (failure?.error?.details ?? [])
    .map((d: { errorCode?: string }) => d.errorCode)
    .find(Boolean);
  const gone = response.status === 404 ||
    code === "UNREGISTERED" ||
    code === "SENDER_ID_MISMATCH" ||
    (code === "INVALID_ARGUMENT" && /registration token/i.test(message));
  if (gone) {
    await fetch(`https://firestore.googleapis.com/v1/${device.name}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    }).catch(() => {});
    return "gone";
  }
  return `${response.status} ${code ?? ""} ${message}`.trim();
}

/** Saves the in-app reminder, unless the app already has (409). */
async function saveNotification(
  id: string,
  userId: string,
  title: string,
  message: string,
  token: string,
) {
  const response = await fetch(
    `${documentsRoot}/notifications?documentId=${encodeURIComponent(id)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fields: {
          userId: { stringValue: userId },
          title: { stringValue: title },
          message: { stringValue: message },
          type: { stringValue: "attendance" },
          isRead: { booleanValue: false },
          createdAt: { timestampValue: new Date().toISOString() },
        },
      }),
    },
  );
  if (!response.ok && response.status !== 409) {
    // The push matters more; send it anyway.
    console.error(`Could not save notification ${id} (${response.status}).`);
  }
}

// ── Email ──────────────────────────────────────────────────────────────

/** Philippine calendar day, `2026-11-01`, for the day's email counters. */
function dayKey(instant: Date): string {
  const wc = wallClock(instant);
  return `${wc.year}-${String(wc.month + 1).padStart(2, "0")}-${
    String(wc.day).padStart(2, "0")
  }`;
}

// Remembered for half a minute, so a burst of notifications for one person
// looks them up once, but a changed switch or a new Auth state isn't ignored
// for as long as this worker stays warm.
const emailRecipients = new Map<
  string,
  { at: number; found: Promise<string | null> }
>();

/**
 * The address to email [userId] at, or null: they must have a profile that
 * isn't archived, an Auth account that is enabled with a verified address
 * (that address is the one used, not the profile's copy), and not have turned
 * email notifications off. Looked up once per request.
 */
function emailRecipient(
  userId: string,
  token: string,
  ignoreSwitch = false,
): Promise<string | null> {
  const key = `${userId}|${ignoreSwitch}`;
  const cached = emailRecipients.get(key);
  if (cached && Date.now() - cached.at < 30_000) return cached.found;
  {
    const found = (async () => {
      const profile = await getDocument(
        `users/${encodeURIComponent(userId)}`,
        token,
      );
      const f = profile?.fields;
      if (!f) return null;
      if (f.status?.stringValue === "Archived") return null;
      if (f.deleted?.booleanValue === true) return null;
      if (f.role?.stringValue === "Admin") return null;
      if (!ignoreSwitch && f.emailNotifications?.booleanValue === false) {
        return null;
      }
      const lookup = await fetch(
        `https://identitytoolkit.googleapis.com/v1/projects/${firebaseProjectId}/accounts:lookup`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ localId: [userId] }),
        },
      );
      if (!lookup.ok) {
        throw new Error(`Auth lookup failed (${lookup.status}).`);
      }
      const account = (await lookup.json())?.users?.[0];
      if (
        !account || account.disabled === true || account.emailVerified !== true
      ) return null;
      return validMailbox(account.email) ? account.email : null;
    })();
    emailRecipients.set(key, { at: Date.now(), found });
    found.catch(() => emailRecipients.delete(key));
    return found;
  }
}

const emailCounts = (name: string, field: string) => ({
  update: {
    name: `projects/${firebaseProjectId}/databases/(default)/documents/emailQuota/${name}`,
  },
  updateMask: { fieldPaths: [] },
  updateTransforms: [{ fieldPath: field, increment: { integerValue: "1" } }],
});

/**
 * Whether today's limits still have room for one more email to [userId]: the
 * day's total and this person's. Only reads: nothing is counted until an
 * email is actually claimed, so a notification that can't be sent (over this
 * person's limit, or claimed by someone else) never uses up anyone's room.
 * The counters are in a collection no client can read or write.
 */
async function emailAllowed(
  userId: string,
  kind: "other" | "clockout",
  token: string,
): Promise<boolean> {
  const day = dayKey(new Date());
  const [total, mine] = await Promise.all([
    getDocument(`emailQuota/${day}`, token),
    getDocument(`emailQuota/${day}_${encodeURIComponent(userId)}`, token),
  ]);
  const used = (doc: FirestoreDoc | null, field: string) =>
    Number(doc?.fields?.[field]?.integerValue ?? 0);
  const personCap = kind === "clockout"
    ? EMAIL_PER_PERSON_CLOCKOUT_CAP
    : EMAIL_PER_PERSON_CAP;
  return used(total, "count") < EMAIL_DAILY_CAP &&
    used(mine, kind) < personCap;
}

/**
 * Counts [by] emails (1, or -1 to take one back) against today's limits, and
 * returns the day's total and this person's after the change. Firestore adds
 * atomically and reports the new figures.
 */
async function bumpEmailCounts(
  userId: string,
  kind: "other" | "clockout",
  by: 1 | -1,
  token: string,
): Promise<{ total: number; mine: number }> {
  const day = dayKey(new Date());
  const bump = (name: string, field: string) => ({
    ...emailCounts(name, field),
    updateTransforms: [
      { fieldPath: field, increment: { integerValue: String(by) } },
    ],
  });
  const response = await fetch(`${documentsRoot}:commit`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      writes: [bump(day, "count"), bump(`${day}_${userId}`, kind)],
    }),
  });
  if (!response.ok) {
    throw new Error(`Email counter failed (${response.status}).`);
  }
  const results = (await response.json())?.writeResults ?? [];
  return {
    total: Number(results[0]?.transformResults?.[0]?.integerValue ?? 0),
    mine: Number(results[1]?.transformResults?.[0]?.integerValue ?? 0),
  };
}

/** Takes one email's room, atomically; false (and taken back) when that
 * passes the day's limit or this person's. */
async function reserveEmail(
  userId: string,
  kind: "other" | "clockout",
  token: string,
): Promise<boolean> {
  const { total, mine } = await bumpEmailCounts(userId, kind, 1, token);
  const personCap = kind === "clockout"
    ? EMAIL_PER_PERSON_CLOCKOUT_CAP
    : EMAIL_PER_PERSON_CAP;
  if (total <= EMAIL_DAILY_CAP && mine <= personCap) return true;
  await bumpEmailCounts(userId, kind, -1, token);
  return false;
}

class EmailTimeout extends Error {}

/** Sends one email over Gmail's SMTP server (TLS, port 465). */
async function sendEmail(to: string, message: EmailMessage): Promise<void> {
  if (!emailFrom || !emailPassword) {
    throw new Error("Email is not set up on the server.");
  }
  if (!validMailbox(to)) throw new Error("Not a valid address.");
  const client = new SMTPClient({
    connection: {
      hostname: "smtp.gmail.com",
      port: 465,
      tls: true,
      auth: { username: emailFrom, password: emailPassword },
    },
  });
  // The mail server gets [EMAIL_SEND_TIMEOUT_MS]; then the connection is
  // closed so the attempt really stops (and no more than the pool's few are
  // ever open).
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(new EmailTimeout("Email server timed out."));
      try {
        client.close();
      } catch {
        // already closed
      }
    }, EMAIL_SEND_TIMEOUT_MS);
  });
  try {
    const sending = client.send({
      from: `SAIS <${emailFrom}>`,
      to,
      subject: message.subject,
      content: message.text,
      html: message.html,
    });
    sending.catch(() => {}); // if the deadline wins, its late failure is moot
    await Promise.race([sending, late]);
  } finally {
    clearTimeout(timer);
    try {
      await client.close();
    } catch {
      // Closing a connection that has already dropped is not a failure.
    }
  }
}

/** PATCHes [fields] of a notification (and deletes the fields named in
 * [clear]), only if it is still as it was when [updateTime] was read.
 * Returns the new updateTime, or null if refused. */
async function patchNotification(
  name: string,
  fields: Record<string, unknown>,
  updateTime: string,
  clear: string[] = [],
): Promise<string | null> {
  const mask = [...Object.keys(fields), ...clear]
    .map((key) => `updateMask.fieldPaths=${key}`)
    .join("&");
  const response = await fetch(
    `https://firestore.googleapis.com/v1/${name}?${mask}` +
      `&currentDocument.updateTime=${encodeURIComponent(updateTime)}`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${await googleToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ fields }),
    },
  );
  if (!response.ok) return null;
  return (await response.json())?.updateTime ?? null;
}

/**
 * Emails the notification [id] to its recipient, once: the Firestore side of
 * [deliverEmail], which holds the rules. [about] is set for the clock-out
 * reminder, whose text the function builds itself; every other email says
 * only what kind of update it is.
 */
function emailNotification(
  id: string,
  link: string,
  token: string,
  about?: { subject: string; sentence: string },
  maxAgeMs = FRESH_MS,
): Promise<"sent" | "skipped" | "failed"> {
  const path = `notifications/${encodeURIComponent(id)}`;
  let name = "";
  const deps: EmailDeps = {
    now: () => Date.now(),
    async read() {
      const doc = await getDocument(path, token);
      const f = doc?.fields;
      if (!doc || !f || !doc.updateTime) return null;
      name = doc.name;
      return {
        updateTime: doc.updateTime,
        userId: f.userId?.stringValue,
        type: f.type?.stringValue,
        createdAtMs: Date.parse(f.createdAt?.timestampValue ?? ""),
        emailedAt: f.emailedAt?.timestampValue,
        emailClaimedAt: f.emailClaimedAt?.timestampValue,
      };
    },
    patch(updateTime, change) {
      const stamp = (ms: number) => ({
        timestampValue: new Date(ms).toISOString(),
      });
      if ("claimAtMs" in change) {
        return patchNotification(
          name,
          { emailClaimedAt: stamp(change.claimAtMs) },
          updateTime,
        );
      }
      if ("sentAtMs" in change) {
        return patchNotification(
          name,
          { emailedAt: stamp(change.sentAtMs) },
          updateTime,
        );
      }
      return patchNotification(name, {}, updateTime, ["emailClaimedAt"]);
    },
    recipient: (userId) => emailRecipient(userId, token),
    allowed: (userId, kind) => emailAllowed(userId, kind, token),
    reserve: (userId, kind) => reserveEmail(userId, kind, token),
    refund: async (userId, kind) => {
      await bumpEmailCounts(userId, kind, -1, token);
    },
    send: (address, type) =>
      sendEmail(address, emailFor(type, link, address, about)),
    isTimeout: (error) => error instanceof EmailTimeout,
    log: (message) => console.error(`${id}: ${message}`),
  };
  return deliverEmail(deps, about ? "clockout" : "other", maxAgeMs);
}

/** The cron job's run: remind everyone still clocked in to the session
 * that ends in under [LEAD_MINUTES]. */
async function sendReminders(): Promise<Response> {
  const wc = wallClock(new Date());
  const minutes = wc.hour * 60 + wc.minute;
  const half = endingSession(minutes);
  if (!half) {
    return json({ skipped: "No session ends within the next 30 minutes." });
  }

  const token = await googleToken();
  const today = await runQuery({
    from: [{ collectionId: "attendance" }],
    where: {
      fieldFilter: {
        field: { fieldPath: "date" },
        op: "EQUAL",
        value: { stringValue: formattedDate(wc) },
      },
    },
  }, token);
  const open = today.filter((doc) => {
    const f = doc.fields ?? {};
    return !f.timeOut?.stringValue &&
      f.isArchived?.booleanValue !== true &&
      f.isInvalid?.booleanValue !== true &&
      Boolean(f.studentId?.stringValue) &&
      isDue(f.timeIn?.stringValue ?? "", half);
  });
  const active = await activeUsers(
    [...new Set(open.map((d) => d.fields!.studentId!.stringValue!))],
    token,
  );
  const due = open.filter((d) => active.has(d.fields!.studentId!.stringValue!));
  if (due.length === 0) return json({ reminded: 0, sent: 0 });

  const title = "Time to Clock Out";
  const body = reminderMessage(half);
  const endMinutes = half === "AM" ? MORNING_END : AFTERNOON_END;
  // A phone that's offline until after the session ends doesn't need it.
  const ttlSeconds = Math.max(
    60,
    endMinutes * 60 - (minutes * 60 + wc.second),
  );

  const userIds = [...new Set(due.map((d) => d.fields!.studentId!.stringValue!))];
  const devices = await devicesOf(userIds, token);

  let sent = 0;
  let gone = 0;
  let emailsSent = 0;
  const errors: string[] = [];
  for (const record of due) {
    const userId = record.fields!.studentId!.stringValue!;
    const notificationId = `clockout_${record.name.split("/").pop()}`;
    // One student's failure must not stop everyone after them.
    try {
      await saveNotification(notificationId, userId, title, body, token);

      for (const device of devices.filter((d) => d.userId === userId)) {
        const result = await send(device, {
          title,
          body,
          tag: notificationId,
          ttlSeconds,
          requireInteraction: true,
          page: "attendance",
          data: { type: "clockout", notificationId, title, body },
        }, token);
        if (result === "sent") sent++;
        else if (result === "gone") gone++;
        else errors.push(result);
      }
    } catch (error) {
      console.error(`Reminder ${notificationId} failed:`, error);
      errors.push(String(error));
    }
  }
  // Emailed too, once the pushes are out (a slow mail server can't hold
  // them up), a few at a time and within a time budget. The claim on each
  // notification sees to "once", whoever saved it. The text is the
  // function's own, from attendance.
  const emailStarted = Date.now();
  await runPool(
    due,
    EMAIL_CONCURRENCY,
    async (record) => {
      const notificationId = `clockout_${record.name.split("/").pop()}`;
      try {
        const emailed = await emailNotification(
          notificationId,
          `${appUrl}attendance`,
          token,
          { subject: "SAIS: time to clock out", sentence: body },
          ttlSeconds * 1000,
        );
        if (emailed === "sent") emailsSent++;
      } catch (error) {
        console.error(`Reminder email ${notificationId} failed:`, error);
      }
    },
    () => Date.now() - emailStarted > EMAIL_BUDGET_MS,
  );
  if (errors.length) console.error("Some reminders failed:", errors);
  return json({
    reminded: due.length,
    sent,
    emailed: emailsSent,
    removedDevices: gone,
    failed: errors.length,
    ...(errors.length > 0 && { errors: errors.slice(0, 5) }),
  });
}

/** The signed-in user an app request comes from, or the response that
 * turns it away. */
async function caller(request: Request): Promise<string | Response> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Please sign in first." }, 401);
  }
  try {
    const verified = await jwtVerify(
      authorization.substring("Bearer ".length),
      firebaseKeys,
      {
        issuer: `https://securetoken.google.com/${firebaseProjectId}`,
        audience: firebaseProjectId,
      },
    );
    if (typeof verified.payload.sub !== "string") throw new Error("no uid");
    if (verified.payload.email_verified !== true) {
      return json({ error: "Please verify your email address first." }, 403);
    }
    return verified.payload.sub;
  } catch {
    return json({ error: "Please sign in again." }, 401);
  }
}

/**
 * Pushes notifications the app has just saved to their recipients'
 * devices. Whoever asks, only what's in Firestore is sent: each
 * notification once (marked `pushedAt`), and only within [FRESH_MS] of
 * being saved. Clock-out reminders are left to the cron job.
 */
async function pushNotifications(
  ids: string[],
): Promise<{ pushed: number; sent: number; failed?: number }> {
  const token = await googleToken();
  const due: { id: string; name: string; userId: string; title: string; body: string }[] =
    [];
  const deactivated = new Map<string, boolean>();
  for (const id of ids) {
    if (!id || id.includes("/") || id.startsWith("clockout_")) continue;
    // One notification that can't be read or claimed must not stop the rest.
    try {
      const doc = await getDocument(
        `notifications/${encodeURIComponent(id)}`,
        token,
      );
      const f = doc?.fields;
      const userId = f?.userId?.stringValue;
      if (!doc || !f || !userId || f.pushedAt || !doc.updateTime) continue;
      const savedAt = Date.parse(f.createdAt?.timestampValue ?? "");
      if (!(Date.now() - savedAt < FRESH_MS)) continue;

      if (!deactivated.has(userId)) {
        deactivated.set(userId, await isDeactivated(userId, token));
      }
      if (deactivated.get(userId)) continue;

      // The claim only holds if the notification is unchanged since it was
      // read: of two requests for the same one, the second is refused.
      const marked = await fetch(
        `https://firestore.googleapis.com/v1/${doc.name}` +
          "?updateMask.fieldPaths=pushedAt" +
          `&currentDocument.updateTime=${encodeURIComponent(doc.updateTime)}`,
        {
          method: "PATCH",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            fields: { pushedAt: { timestampValue: new Date().toISOString() } },
          }),
        },
      );
      if (!marked.ok) continue; // claimed by another request, or deleted
      due.push({
        id,
        name: doc.name,
        userId,
        ...pushTextFor(
          f.type?.stringValue,
          f.title?.stringValue ?? "SAIS",
          f.message?.stringValue ?? "",
        ),
      });
    } catch (error) {
      console.error(`Notification ${id} could not be claimed:`, error);
    }
  }
  if (due.length === 0) return { pushed: 0, sent: 0 };

  const devices = await devicesOf([...new Set(due.map((n) => n.userId))], token);
  let sent = 0;
  const errors: string[] = [];
  for (const n of due) {
    let delivered = 0;
    let failed = 0;
    for (const device of devices.filter((d) => d.userId === n.userId)) {
      try {
        const result = await send(device, {
          title: n.title,
          body: n.body,
          tag: n.id,
          ttlSeconds: 24 * 60 * 60,
          requireInteraction: false,
          // Every role's Notifications page is /notifications; the new one is
          // at the top, and tapping it opens what it's about.
          page: "notifications",
          data: {
            type: "notification",
            notificationId: n.id,
            title: n.title,
            body: n.body,
          },
        }, token);
        if (result === "sent") {
          sent++;
          delivered++;
        } else if (result !== "gone") {
          errors.push(result);
          failed++;
        }
      } catch (error) {
        errors.push(String(error));
        failed++;
      }
    }
    // Nothing got through and something failed (not just "no devices"):
    // let the app's retry, or the next request, try again.
    if (delivered === 0 && failed > 0) {
      await fetch(
        `https://firestore.googleapis.com/v1/${n.name}` +
          "?updateMask.fieldPaths=pushedAt&currentDocument.exists=true",
        {
          method: "PATCH",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ fields: {} }),
        },
      ).catch(() => {});
    }
  }
  if (errors.length) console.error("Some pushes failed:", errors);
  return { pushed: due.length, sent, failed: errors.length };
}

/** A test notification to [userId]'s devices, [delaySeconds] from now. */
async function sendTest(userId: string, delaySeconds: number) {
  const token = await googleToken();
  const devices = await devicesOf([userId], token);
  if (devices.length === 0) {
    return json({
      error: "Notifications aren't turned on for any of your devices yet.",
    }, 404);
  }

  const title = "Test Notification";
  const body = "SAIS notifications are working on this device.";
  const push: Push = {
    title,
    body,
    tag: "push_test",
    ttlSeconds: 300,
    requireInteraction: false,
    page: "notifications",
    data: { type: "test", notificationId: `push_test_${Date.now()}`, title, body },
  };

  // Checked now, so a setup problem reaches the app instead of only the
  // logs once the delayed send fails.
  const live: Device[] = [];
  const errors: string[] = [];
  for (const device of devices) {
    const result = await send(device, push, token, true);
    if (result === "sent") live.push(device);
    else if (result !== "gone") errors.push(result);
  }
  if (live.length === 0) {
    return json({
      error: errors.length
        ? `Firebase Cloud Messaging refused the test: ${errors[0]}`
        : "This device's registration has expired. Reload SAIS and try again.",
    }, 502);
  }

  EdgeRuntime.waitUntil((async () => {
    await new Promise((resolve) => setTimeout(resolve, delaySeconds * 1000));
    for (const device of live) {
      const result = await send(device, push, token);
      if (result !== "sent") console.error("Test push failed:", result);
    }
  })());
  return json({ devices: live.length, delaySeconds });
}

/** A test email to the caller's own verified address, once a minute. */
async function sendTestEmail(userId: string): Promise<Response> {
  if (!emailFrom || !emailPassword) {
    return json({ error: "Email isn't set up on the server yet." }, 503);
  }
  const token = await googleToken();
  let address: string | null;
  try {
    address = await emailRecipient(userId, token, true);
  } catch (error) {
    console.error("Test email: recipient check failed:", error);
    return json({
      error: "Could not check your account: " +
        (error instanceof Error ? error.message : "unknown error"),
    }, 502);
  }
  if (!address) {
    return json({
      error: "Your account has no verified email address to send to.",
    }, 400);
  }
  // One a minute per person, counted like the day's emails.
  const minute = Math.floor(Date.now() / 60000);
  const root = `projects/${firebaseProjectId}/databases/(default)/documents`;
  const counted = await fetch(`${documentsRoot}:commit`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      writes: [{
        update: { name: `${root}/emailQuota/test_${userId}_${minute}` },
        updateMask: { fieldPaths: [] },
        updateTransforms: [
          { fieldPath: "count", increment: { integerValue: "1" } },
        ],
      }],
    }),
  });
  if (!counted.ok) {
    return json({ error: "Could not check the limit. Try again." }, 502);
  }
  const n = Number(
    (await counted.json())?.writeResults?.[0]?.transformResults?.[0]
      ?.integerValue ?? 0,
  );
  if (n > 1) {
    return json({ error: "Please wait a minute before sending another." }, 429);
  }
  let within: boolean;
  try {
    within = await reserveEmail(userId, "other", token);
  } catch (error) {
    console.error("Test email: counter failed:", error);
    return json({ error: "Could not check the limit. Try again." }, 502);
  }
  if (!within) {
    return json({
      error: "Today's email limit has been reached. Try again tomorrow.",
    }, 429);
  }
  try {
    await sendEmail(
      address,
      emailFor(undefined, `${appUrl}notifications`, address, {
        subject: "SAIS: test email",
        sentence: "This is a test. Email notifications are working for your account.",
      }),
    );
  } catch (error) {
    console.error("Test email failed:", error);
    // Not sent: its room goes back.
    if (!(error instanceof EmailTimeout)) {
      await bumpEmailCounts(userId, "other", -1, token).catch(() => {});
    }
    return json({
      error: "The email server did not accept the message. Check the " +
        "sender settings.",
    }, 502);
  }
  return json({ sent: true, to: address.replace(/^(.).*(@.*)$/, "$1***$2") });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Only POST is supported." }, 405);
  }

  try {
    const secret = request.headers.get("x-reminder-secret");
    if (secret !== null) {
      if (!sameSecret(secret, cronSecret)) {
        return json({ error: "Wrong reminder secret." }, 401);
      }
      return await sendReminders();
    }

    const userId = await caller(request);
    if (userId instanceof Response) return userId;
    if (await isDeactivated(userId, await googleToken())) {
      return json({ error: "This account has been deactivated." }, 403);
    }
    const body = await request.json().catch(() => ({}));

    if (Array.isArray(body?.notificationIds)) {
      const ids = body.notificationIds
        .filter((id: unknown): id is string => typeof id === "string")
        .slice(0, 50);
      // Push and email are separate channels, each with its own claim: one
      // failing must not lose the other.
      let pushed: { pushed: number; sent: number; failed?: number } = {
        pushed: 0,
        sent: 0,
      };
      let pushError = false;
      try {
        pushed = await pushNotifications(ids);
      } catch (error) {
        console.error("Push step failed:", error);
        pushError = true;
      }
      let emailed = 0;
      let emailFailed = 0;
      try {
        const token = await googleToken();
        const started = Date.now();
        await runPool(
          (ids as string[]).filter((id: string) =>
            id && !id.includes("/") && !id.startsWith("clockout_")
          ),
          EMAIL_CONCURRENCY,
          async (id: string) => {
            try {
              const result = await emailNotification(
                id,
                `${appUrl}notifications`,
                token,
              );
              if (result === "sent") emailed++;
              else if (result === "failed") emailFailed++;
            } catch (error) {
              console.error(`Email for ${id} could not be prepared:`, error);
              emailFailed++;
            }
          },
          () => Date.now() - started > EMAIL_BUDGET_MS,
        );
        if (Date.now() - started > EMAIL_BUDGET_MS) {
          console.error("Email time budget used up; the rest were not emailed.");
        }
      } catch (error) {
        console.error("Email step failed:", error);
      }
      return json({ ...pushed, pushError, emailed, emailFailed });
    }
    if (body?.testEmail === true) return await sendTestEmail(userId);
    if (body?.test === true) {
      const delay = Math.min(30, Math.max(0, Number(body?.delaySeconds) || 0));
      return await sendTest(userId, delay);
    }
    return json({ error: "Nothing to send." }, 400);
  } catch (error) {
    console.error("clockout-reminders failed:", error);
    return json({ error: "The reminder server could not finish." }, 500);
  }
});
