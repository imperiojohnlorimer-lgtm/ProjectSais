// Attendance clock-in/out, decided on the server.
//
// The device only sends the code it scanned. Everything that matters —
// whether that code is the session's, whether the window is open, whether
// this is a clock-in or a clock-out, and how many hours were worked — is
// settled here, against this server's clock.
//
// Firestore keeps `attendance` writable by staff only, so the record is
// written with a Firebase service account rather than the student's own
// token. That is the whole point: a student calling Firestore directly
// cannot create or edit their own attendance.
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

// Set with: supabase secrets set FIREBASE_CLIENT_EMAIL=... FIREBASE_PRIVATE_KEY=...
const serviceAccountEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
const serviceAccountKey = (Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "")
  .replace(/\\n/g, "\n");

const firebaseKeys = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

const documentsRoot =
  `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents`;

// Attendance runs on Philippine wall-clock time, taken from this server.
// The phone's clock is never consulted: winding it forward was otherwise
// enough to clock in outside the allowed window.
const TZ_OFFSET_MINUTES = 8 * 60;

// The two daily sessions, in minutes past midnight. These mirror the
// windows in AppState — keep them in step.
const MORNING_START = 7 * 60 + 30; // 7:30 AM
const MORNING_END = 12 * 60; // 12:00 PM
const AFTERNOON_START = 12 * 60 + 30; // 12:30 PM
const AFTERNOON_END = 17 * 60; // 5:00 PM

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
};

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
  };
}

/** `yyyyMMdd-AM` / `yyyyMMdd-PM`, or null outside both windows. */
function sessionKeyFor(wc: WallClock): string | null {
  const minutes = wc.hour * 60 + wc.minute;
  let half: string;
  if (minutes >= MORNING_START && minutes <= MORNING_END) {
    half = "AM";
  } else if (minutes >= AFTERNOON_START && minutes <= AFTERNOON_END) {
    half = "PM";
  } else {
    return null;
  }
  const y = String(wc.year).padStart(4, "0");
  const m = String(wc.month + 1).padStart(2, "0");
  const d = String(wc.day).padStart(2, "0");
  return `${y}${m}${d}-${half}`;
}

/** `Sep 21, 2026` — the shape the app and the DTR reader already use. */
function formattedDate(wc: WallClock) {
  return `${MONTHS[wc.month]} ${wc.day}, ${wc.year}`;
}

/** `2:36 PM` — the shape the app already writes. */
function formattedTime(wc: WallClock) {
  const period = wc.hour < 12 ? "AM" : "PM";
  const hour = wc.hour % 12 === 0 ? 12 : wc.hour % 12;
  return `${hour}:${String(wc.minute).padStart(2, "0")} ${period}`;
}

function parseTimeMinutes(value: string): number | null {
  const match = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec((value ?? "").trim());
  if (!match) return null;
  let hour = parseInt(match[1], 10) % 12;
  if (match[3].toUpperCase() === "PM") hour += 12;
  return hour * 60 + parseInt(match[2], 10);
}

/**
 * Elapsed hours between time-in and time-out. Mirrors
 * AppState._hoursBetween — including returning 0 when the times can't be
 * trusted — so hours computed here match hours computed anywhere else in
 * the app. Never guess a duration: these hours are paid, and a student who
 * clocks out a few seconds after clocking in worked 0 hours, not 4.
 */
function hoursBetween(timeIn: string, timeOut: string): number {
  const start = parseTimeMinutes(timeIn);
  const end = parseTimeMinutes(timeOut);
  if (start === null || end === null) return 0.0;
  const diff = end - start;
  if (diff <= 0) return 0.0;
  return diff / 60.0;
}

// ── Firestore admin access ──────────────────────────────────────────
// Supabase has no Firebase Admin SDK, so the service account is exchanged
// for a Google access token by hand and Firestore is driven over REST.
// The token lives an hour; cache it so a burst of scans doesn't mint one
// per request.
let cachedToken: { value: string; expiresAt: number } | null = null;

async function firestoreToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  if (!serviceAccountEmail || !serviceAccountKey) {
    throw new Error(
      "FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY are not set on this function.",
    );
  }

  const key = await importPKCS8(serviceAccountKey, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/datastore",
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

async function getDocument(path: string, token: string) {
  const response = await fetch(`${documentsRoot}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`Firestore read failed (${response.status}).`);
  }
  return await response.json();
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Only POST is supported." }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json({ error: "Please sign in first." }, 401);
    }

    const verified = await jwtVerify(
      authorization.substring("Bearer ".length),
      firebaseKeys,
      {
        issuer: `https://securetoken.google.com/${firebaseProjectId}`,
        audience: firebaseProjectId,
      },
    );
    const userId = verified.payload.sub;
    if (!userId || typeof userId !== "string") {
      return json({ error: "Invalid Firebase user ID." }, 401);
    }
    // The app refuses unverified sign-ins, but a token can be minted without
    // the app, so check here too — as the Firestore rules do.
    if (verified.payload.email_verified !== true) {
      return json({ error: "Please verify your email address first." }, 403);
    }

    const body = await request.json().catch(() => ({}));
    const scanned = String(body?.token ?? "").trim();
    if (!scanned) {
      return json({ error: "No QR code was scanned." }, 400);
    }

    const token = await firestoreToken();

    const userDoc = await getDocument(
      `users/${encodeURIComponent(userId)}`,
      token,
    );
    if (!userDoc) {
      return json({ error: "This account has no profile." }, 403);
    }
    if (userDoc.fields?.status?.stringValue === "Archived") {
      return json({ error: "This account has been deactivated." }, 403);
    }
    const role = userDoc.fields?.role?.stringValue;
    if (role !== "Student Assistant") {
      return json(
        { error: "Only student assistants clock in with the attendance QR." },
        403,
      );
    }
    const studentName = userDoc.fields?.name?.stringValue ?? "";

    const wc = wallClock(new Date());
    const sessionKey = sessionKeyFor(wc);
    if (!sessionKey) {
      return json({
        error:
          "Attendance is only open 7:30 AM–12:00 PM and 12:30 PM–5:00 PM.",
      }, 409);
    }

    const qrDoc = await getDocument("meta/current_qr", token);
    if (!qrDoc) {
      return json({ error: "No attendance QR has been generated yet." }, 409);
    }
    if (qrDoc.fields?.token?.stringValue !== scanned) {
      return json({ error: "That is not this session's attendance QR." }, 403);
    }

    // Codes written before sessions existed carry no sessionKey, so fall
    // back to the session their generatedAt lands in.
    let qrSession: string | null = qrDoc.fields?.sessionKey?.stringValue ??
      null;
    if (!qrSession && qrDoc.fields?.generatedAt?.timestampValue) {
      qrSession = sessionKeyFor(
        wallClock(new Date(qrDoc.fields.generatedAt.timestampValue)),
      );
    }
    if (qrSession !== sessionKey) {
      return json({
        error:
          "That QR code was for an earlier session. Ask your supervisor for " +
          "the current one.",
      }, 409);
    }

    const today = formattedDate(wc);
    const now = formattedTime(wc);

    const queryResponse = await fetch(`${documentsRoot}:runQuery`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: "attendance" }],
          where: {
            compositeFilter: {
              op: "AND",
              filters: [
                {
                  fieldFilter: {
                    field: { fieldPath: "studentId" },
                    op: "EQUAL",
                    value: { stringValue: userId },
                  },
                },
                {
                  fieldFilter: {
                    field: { fieldPath: "date" },
                    op: "EQUAL",
                    value: { stringValue: today },
                  },
                },
              ],
            },
          },
        },
      }),
    });

    if (!queryResponse.ok) {
      throw new Error(`Firestore query failed (${queryResponse.status}).`);
    }

    const rows = await queryResponse.json();
    const open = (Array.isArray(rows) ? rows : [])
      .map((row: Record<string, unknown>) => row.document)
      .filter(Boolean)
      .find((doc: Record<string, never>) => {
        const fields = (doc as Record<string, never>).fields ?? {};
        const timeOut = (fields as Record<string, never>).timeOut as
          | { stringValue?: string }
          | undefined;
        const archived = (fields as Record<string, never>).isArchived as
          | { booleanValue?: boolean }
          | undefined;
        return !timeOut?.stringValue && archived?.booleanValue !== true;
      }) as { name: string; fields: Record<string, never> } | undefined;

    if (open) {
      const timeIn =
        (open.fields.timeIn as { stringValue?: string } | undefined)
          ?.stringValue ?? "";
      const totalHours = hoursBetween(timeIn, now);

      const patch = await fetch(
        `https://firestore.googleapis.com/v1/${open.name}` +
          "?updateMask.fieldPaths=timeOut&updateMask.fieldPaths=totalHours",
        {
          method: "PATCH",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            fields: {
              timeOut: { stringValue: now },
              totalHours: { doubleValue: totalHours },
            },
          }),
        },
      );
      if (!patch.ok) {
        throw new Error(`Could not save the time-out (${patch.status}).`);
      }
      return json({ action: "out", time: now, totalHours });
    }

    const settings = await getDocument("meta/academic_year_settings", token);
    const academicYear = settings?.fields?.academicYear?.stringValue ?? null;

    const fields: Record<string, unknown> = {
      studentName: { stringValue: studentName },
      studentId: { stringValue: userId },
      date: { stringValue: today },
      timeIn: { stringValue: now },
      // The attendance stream orders by createdAt, and Firestore drops
      // documents missing the ordered field — so this is not optional.
      createdAt: { timestampValue: new Date().toISOString() },
    };
    if (academicYear) fields.academicYear = { stringValue: academicYear };

    const created = await fetch(`${documentsRoot}/attendance`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ fields }),
    });
    if (!created.ok) {
      throw new Error(`Could not save the clock-in (${created.status}).`);
    }

    return json({ action: "in", time: now });
  } catch (error) {
    console.error("clock-attendance failed:", error);
    return json(
      { error: "The attendance server could not record that scan." },
      500,
    );
  }
});
