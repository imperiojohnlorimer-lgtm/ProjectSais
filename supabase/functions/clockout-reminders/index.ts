// Push notifications to SAIS users' phones, through Firebase Cloud
// Messaging. Named for its first job; it has three:
//
// 1. Clock-out reminders, on a schedule (below).
// 2. Every other notification: right after the app saves one, it sends the
//    id here (PushService.deliver), and this pushes it to the recipient's
//    devices. Each is read from Firestore and pushed once, only while
//    fresh, so a caller can't choose what's sent or send it twice.
// 3. A test notification to the caller's own devices: the "Send a test"
//    button.
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
      "https://www.googleapis.com/auth/firebase.messaging",
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
  fields?: Record<
    string,
    { stringValue?: string; booleanValue?: boolean; timestampValue?: string }
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
  const due = today.filter((doc) => {
    const f = doc.fields ?? {};
    return !f.timeOut?.stringValue &&
      f.isArchived?.booleanValue !== true &&
      f.isInvalid?.booleanValue !== true &&
      Boolean(f.studentId?.stringValue) &&
      isDue(f.timeIn?.stringValue ?? "", half);
  });
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
  const errors: string[] = [];
  for (const record of due) {
    const userId = record.fields!.studentId!.stringValue!;
    const notificationId = `clockout_${record.name.split("/").pop()}`;
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
  }
  if (errors.length) console.error("Some reminders failed:", errors);
  return json({
    reminded: due.length,
    sent,
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
async function pushNotifications(ids: string[]): Promise<Response> {
  const token = await googleToken();
  const due: { id: string; userId: string; title: string; body: string }[] =
    [];
  for (const id of ids) {
    if (!id || id.includes("/") || id.startsWith("clockout_")) continue;
    const doc = await getDocument(
      `notifications/${encodeURIComponent(id)}`,
      token,
    );
    const f = doc?.fields;
    const userId = f?.userId?.stringValue;
    if (!doc || !f || !userId || f.pushedAt) continue;
    const savedAt = Date.parse(f.createdAt?.timestampValue ?? "");
    if (!(Date.now() - savedAt < FRESH_MS)) continue;

    const marked = await fetch(
      `https://firestore.googleapis.com/v1/${doc.name}` +
        "?updateMask.fieldPaths=pushedAt&currentDocument.exists=true",
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
    if (!marked.ok) continue; // deleted meanwhile
    due.push({
      id,
      userId,
      title: f.title?.stringValue ?? "SAIS",
      body: f.message?.stringValue ?? "",
    });
  }
  if (due.length === 0) return json({ pushed: 0, sent: 0 });

  const devices = await devicesOf([...new Set(due.map((n) => n.userId))], token);
  let sent = 0;
  const errors: string[] = [];
  for (const n of due) {
    for (const device of devices.filter((d) => d.userId === n.userId)) {
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
      if (result === "sent") sent++;
      else if (result !== "gone") errors.push(result);
    }
  }
  if (errors.length) console.error("Some pushes failed:", errors);
  return json({ pushed: due.length, sent, failed: errors.length });
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
    const body = await request.json().catch(() => ({}));

    if (Array.isArray(body?.notificationIds)) {
      const ids = body.notificationIds
        .filter((id: unknown): id is string => typeof id === "string")
        .slice(0, 50);
      return await pushNotifications(ids);
    }
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
