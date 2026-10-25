import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  createRemoteJWKSet,
  jwtVerify,
} from "npm:jose@5.10.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const firebaseProjectId = "sais-6168b";

const adminClient = createClient(
  supabaseUrl,
  serviceRoleKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  },
);

const firebaseKeys = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

const allowedTypes: Record<string, string> = {
  pdf: "application/pdf",
  doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
};

function json(data: unknown, status = 200) {
  return Response.json(data, {
    status,
    headers: corsHeaders,
  });
}

// #region path rules
// paths.test.ts runs this region on its own, so it must not use anything
// from the rest of this file.
function validPathParts(path: string) {
  const parts = path.split("/");

  const validShape =
    parts.length === 4 || parts.length === 5;

  const validRoot =
    parts[0] === "reports" ||
    parts[0] === "applications" ||
    // Files a Head attaches to a broadcast Announcement. These are meant
    // to be downloadable by every signed-in user (any Student/Student
    // Assistant the announcement is visible to), not just the uploader
    // or Head/Supervisor staff — see isPublicAnnouncementPath below.
    parts[0] === "announcements";

  const safeParts = parts.every(
    (part) =>
      part.length > 0 &&
      part !== "." &&
      part !== ".." &&
      /^[a-zA-Z0-9._-]+$/.test(part),
  );

  return validShape && validRoot && safeParts;
}

// Where staff (not the file's owner) may ask for a download link. The Head
// reads applicants' documents and the archived copies of past years; a
// Supervisor only the reports their students send, plus announcement
// attachments (public to every signed-in user). Every part must be a real
// name: no empty parts, "." or "..", and a bounded length.
const headRoots = [
  "reports",
  "applications",
  "announcements",
  "academic_year_archives",
];
const supervisorRoots = ["reports", "announcements"];

export function staffMayRead(path: string, role: string | undefined) {
  if (path.length > 400) return false;
  // Storage decodes the path it is given, so "%2e%2e" would climb out of the
  // folder that was checked. No real file name here contains these.
  if (path.includes("%") || path.includes("\\") || /[\u0000-\u001f]/.test(path)) {
    return false;
  }
  const parts = path.split("/");
  if (parts.length < 4 || parts.length > 6) return false;
  if (parts.some((part) => part.length === 0 || part === "." || part === "..")) {
    return false;
  }
  if (role === "Head") return headRoots.includes(parts[0]);
  if (role === "Supervisor") return supervisorRoots.includes(parts[0]);
  return false;
}

export function ownedPath(path: string, userId: string) {
  return validPathParts(path) && path.split("/")[1] === userId;
}

// Announcement attachments are public broadcast content once posted, so
// any authenticated user may request a fresh signed download URL for one
// regardless of who uploaded it. Uploading still requires ownedPath (or
// isStaffUser via the caller), so only the Head posting the announcement
// can write into this root in normal app usage.
export function isPublicAnnouncementPath(path: string) {
  return validPathParts(path) && path.split("/")[0] === "announcements";
}

// #endregion path rules

/** Thrown when the profile can't be read for a reason other than "none". */
class ProfileUnavailable extends Error {}

/**
 * The caller's own profile, read with their own token (the Firestore rules
 * let any signed-in user read their own document), or null if there isn't
 * one. Throws [ProfileUnavailable] when Firestore can't answer (an outage or
 * its quota), so a failed lookup never reads as "not staff, not archived".
 */
async function loadProfile(
  userId: string,
  firebaseToken: string,
): Promise<{ role?: string; status?: string } | null> {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents/users/${encodeURIComponent(userId)}`,
    {
      headers: {
        Authorization: `Bearer ${firebaseToken}`,
      },
    },
  );

  if (response.status === 404) return null;
  if (!response.ok) throw new ProfileUnavailable();

  const document = await response.json();
  return {
    role: document.fields?.role?.stringValue,
    status: document.fields?.status?.stringValue,
  };
}

function isStaffProfile(profile: { role?: string } | null) {
  // Admin no longer manages Reports or Applications — that moved to Head.
  // Supervisor still owns the Reports/DTR approval flow.
  return profile?.role === "Head" || profile?.role === "Supervisor";
}

// The largest file the app uploads is 10 MB; the rest is the multipart
// framing around it.
const maxFileBytes = 10 * 1024 * 1024;
const maxBodyBytes = maxFileBytes + 512 * 1024;

/**
 * The request's body, read no further than [maxBodyBytes]: a declared
 * length can lie, and formData() would otherwise buffer whatever arrives.
 * Null when it is larger than that.
 */
async function readBodyWithin(request: Request): Promise<Blob | null> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > maxBodyBytes) return null;
  const reader = request.body?.getReader();
  if (!reader) return new Blob([]);
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > maxBodyBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  return new Blob(chunks);
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
      return json({ error: "Missing Firebase token." }, 401);
    }

    const token = authorization.substring("Bearer ".length);

    let verified;
    try {
      verified = await jwtVerify(token, firebaseKeys, {
        issuer: `https://securetoken.google.com/${firebaseProjectId}`,
        audience: firebaseProjectId,
      });
    } catch (_) {
      return json({ error: "Please sign in again." }, 401);
    }

    const userId = verified.payload.sub;

    if (!userId || typeof userId !== "string") {
      return json({ error: "Invalid Firebase user ID." }, 401);
    }

    // The app refuses unverified and deactivated accounts at login, but a
    // token can be minted without the app, so check here too — as the
    // Firestore rules do.
    if (verified.payload.email_verified !== true) {
      return json({ error: "Please verify your email address first." }, 403);
    }
    const profile = await loadProfile(userId, token);
    if (profile?.status === "Archived") {
      return json({ error: "This account has been deactivated." }, 403);
    }

    const requestContentType =
      request.headers.get("content-type") ?? "";

    // Generate a fresh signed URL.
    if (requestContentType.includes("application/json")) {
      const body = await request.json();

      if (body.action !== "sign" || typeof body.path !== "string") {
        return json({ error: "Invalid signing request." }, 400);
      }

      const requestedPath = body.path;
      const ownsFile = ownedPath(requestedPath, userId);
      const publicAnnouncement = isPublicAnnouncementPath(requestedPath);
      const staffUser = !publicAnnouncement &&
        staffMayRead(requestedPath, profile?.role);

      if (!ownsFile && !publicAnnouncement && !staffUser) {
        return json({ error: "Invalid document path." }, 403);
      }

      const { data: signedFile, error: signedUrlError } =
        await adminClient.storage
          .from("Documents")
          .createSignedUrl(requestedPath, 3600);

      if (signedUrlError || !signedFile) {
        return json({ error: "Document not found." }, 404);
      }

      return json({
        path: requestedPath,
        downloadUrl: signedFile.signedUrl,
      });
    }

    // Upload a new file.
    const body = await readBodyWithin(request);
    if (!body) {
      return json({ error: "Files must be between 1 byte and 10 MB." }, 413);
    }
    const form = await new Response(body, {
      headers: { "content-type": requestContentType },
    }).formData().catch(() => null);
    if (!form) {
      return json({ error: "That upload could not be read." }, 400);
    }
    const file = form.get("file");
    const requestedPath = form.get("path");

    if (!(file instanceof File)) {
      return json({ error: "A file is required." }, 400);
    }

    if (typeof requestedPath !== "string") {
      return json({ error: "A storage path is required." }, 400);
    }

    // New uploads must always use the current Firebase UID.
    if (!ownedPath(requestedPath, userId)) {
      return json({ error: "Invalid upload path." }, 403);
    }
    // Announcement attachments are public to every signed-in user, so only
    // the staff who post announcements may add them.
    if (
      requestedPath.split("/")[0] === "announcements" &&
      !isStaffProfile(profile)
    ) {
      return json({ error: "Invalid upload path." }, 403);
    }

    if (file.size === 0 || file.size > maxFileBytes) {
      return json(
        { error: "Files must be between 1 byte and 10 MB." },
        400,
      );
    }

    const filename = requestedPath.split("/").pop()!;
    const extension = filename.split(".").pop()?.toLowerCase();
    const contentType = extension
      ? allowedTypes[extension]
      : undefined;

    if (!extension || !contentType) {
      return json({ error: "File type is not allowed." }, 400);
    }

    const fileBytes = new Uint8Array(
      await file.arrayBuffer(),
    );

    const { error: uploadError } = await adminClient.storage
      .from("Documents")
      .upload(requestedPath, fileBytes, {
        contentType,
        upsert: false,
      });

    if (uploadError) {
      console.error("upload-document: upload failed:", uploadError.message);
      return json({ error: "The file could not be saved." }, 500);
    }

    const { data: signedFile, error: signedUrlError } =
      await adminClient.storage
        .from("Documents")
        .createSignedUrl(requestedPath, 3600);

    if (signedUrlError || !signedFile) {
      console.error("upload-document: signing failed:", signedUrlError?.message);
      return json({ error: "Unable to create a download link." }, 500);
    }

    return json({
      path: requestedPath,
      downloadUrl: signedFile.signedUrl,
    });
  } catch (error) {
    console.error("upload-document failed:", error);

    if (error instanceof ProfileUnavailable) {
      return json(
        { error: "Could not check your account right now. Try again." },
        503,
      );
    }
    return json({ error: "The request could not be completed." }, 500);
  }
});
