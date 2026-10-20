// StudyUp `send-feedback` Supabase Edge Function.
// POST-only endpoint that relays app feedback via Resend to the support inbox.
//
// Secrets (server-side ONLY — set with `supabase secrets set`, never in the app):
//   RESEND_API_KEY, FEEDBACK_TO_EMAIL, FEEDBACK_FROM_EMAIL
//
// Request contract (JSON):
//   { category: "bug"|"feature"|"improvement"|"other",
//     subject: string (3..120),
//     message: string (10..2000),
//     contactEmail: string (required, valid email, max 254),
//     appVersion?: string (optional diagnostic, max 32),
//     platform?: string (optional diagnostic, max 32) }
// Response:
//   200 { ok: true, id: "<resend-id>" }  -> accepted by Resend (NOT confirmed delivery)
//   4xx/5xx { ok: false, error: "<non-sensitive message>" }
//
// Abuse protection: strict validation + 16 KB body cap + per-isolate
// sliding-window rate limit (5 req / 10 min / IP) + required Supabase
// gateway headers. In-memory limits do not span isolates; for strict
// production limiting, front this with a shared store. This is NOT an
// unrestricted public email relay: the recipient is fixed server-side.

const ALLOWED_CATEGORIES = new Set(["bug", "feature", "improvement", "other"]);
export const MAX_BODY_BYTES = 16 * 1024;
const MESSAGE_MIN = 10;
const MESSAGE_MAX = 2000;
const SUBJECT_MIN = 3;
const SUBJECT_MAX = 120;
const DIAG_MAX = 32;

const RATE_WINDOW_MS = 10 * 60 * 1000;
const RATE_MAX = 5;
const hits = new Map<string, number[]>();

export function clearRateLimit(): void {
  hits.clear();
}

function prune(now: number): void {
  for (const [ip, times] of hits) {
    const fresh = times.filter((t) => now - t < RATE_WINDOW_MS);
    if (fresh.length === 0) hits.delete(ip);
    else hits.set(ip, fresh);
  }
}

export function isRateLimited(ip: string): boolean {
  const now = Date.now();
  if (hits.size > 5000) prune(now);
  const times = (hits.get(ip) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
  if (times.length >= RATE_MAX) {
    hits.set(ip, times);
    return true;
  }
  times.push(now);
  hits.set(ip, times);
  return false;
}

export function isValidEmail(v: string): boolean {
  if (v.length === 0 || v.length > 254) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v);
}

function stripControls(s: string): string {
  // deno-lint-ignore no-control-regex
  return s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "");
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export interface ValidFeedback {
  category: string;
  subject: string;
  message: string;
  contactEmail: string;
  appVersion: string | null;
  platform: string | null;
}

export function validateInput(body: unknown): { error: string } | { value: ValidFeedback } {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { error: "Malformed request: expected a JSON object." };
  }
  const b = body as Record<string, unknown>;
  const rawCategory = typeof b.category === "string" ? b.category.trim().toLowerCase() : "";
  const rawSubject = typeof b.subject === "string" ? stripControls(b.subject).trim() : "";
  const rawMessage = typeof b.message === "string" ? stripControls(b.message).trim() : "";
  const rawContact = b.contactEmail != null
    ? String(b.contactEmail).trim()
    : b.email != null
    ? String(b.email).trim()
    : "";
  const rawVersion = typeof b.appVersion === "string" ? stripControls(b.appVersion).trim().slice(0, DIAG_MAX) : "";
  const rawPlatform = typeof b.platform === "string" ? stripControls(b.platform).trim().slice(0, DIAG_MAX) : "";

  if (!ALLOWED_CATEGORIES.has(rawCategory)) {
    return { error: "Choose a valid category: bug, feature, improvement, or other." };
  }
  if (rawSubject.length < SUBJECT_MIN || rawSubject.length > SUBJECT_MAX) {
    return { error: `Subject must be ${SUBJECT_MIN}-${SUBJECT_MAX} characters.` };
  }
  if (rawMessage.length < MESSAGE_MIN || rawMessage.length > MESSAGE_MAX) {
    return { error: `Message must be ${MESSAGE_MIN}-${MESSAGE_MAX} characters.` };
  }
  if (rawContact === "") {
    return { error: "Contact email is required." };
  }
  if (!isValidEmail(rawContact)) {
    return { error: "Contact email is not a valid email address." };
  }
  return {
    value: {
      category: rawCategory,
      subject: rawSubject,
      message: rawMessage,
      contactEmail: rawContact,
      appVersion: rawVersion === "" ? null : rawVersion,
      platform: rawPlatform === "" ? null : rawPlatform,
    },
  };
}

function json(status: number, obj: Record<string, unknown>, cors: Headers): Response {
  const headers = new Headers(cors);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  return new Response(JSON.stringify(obj), { status, headers });
}

export function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0].trim();
  return "unknown";
}

// `fetchImpl` is injectable for tests (defaults to global fetch).
export async function sendViaResend(
  args: { apiKey: string; to: string; from: string; replyTo: string | null; subject: string; text: string; html: string },
  fetchImpl: typeof fetch = fetch,
): Promise<string | null> {
  const res = await fetchImpl("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${args.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: args.from,
      to: [args.to],
      subject: args.subject,
      text: args.text,
      html: args.html,
      ...(args.replyTo ? { reply_to: args.replyTo } : {}),
    }),
  });
  let payload: unknown = null;
  try {
    payload = await res.json();
  } catch {
    payload = null;
  }
  if (!res.ok) {
    const msg = payload !== null && typeof payload === "object" && "message" in payload &&
        typeof (payload as { message: unknown }).message === "string"
      ? (payload as { message: string }).message
      : `Resend error (status ${res.status})`;
    throw new Error(msg);
  }
  if (payload !== null && typeof payload === "object" && "id" in payload &&
    typeof (payload as { id: unknown }).id === "string") {
    return (payload as { id: string }).id;
  }
  return null;
}

export async function handleRequest(
  req: Request,
  env: Record<string, string | undefined>,
  fetchImpl: typeof fetch = fetch,
): Promise<Response> {
  // CORS is for browser callers only; it is NOT authentication.
  // The Android app does not need CORS.
  const origin = req.headers.get("origin") ?? "*";
  const cors = new Headers({
    "Access-Control-Allow-Origin": origin,
    "Vary": "Origin",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
    "Access-Control-Max-Age": "86400",
  });

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    cors.set("Allow", "POST, OPTIONS");
    return json(405, { ok: false, error: "Method not allowed. Use POST." }, cors);
  }

  // Baseline gateway gating: invocations through the Supabase client always
  // carry the project anon key. Direct anonymous floods without it are refused.
  // (Full JWT auth is intentionally off — see config.toml — so demo-mode and
  // signed-out users can still send feedback.)
  if (!req.headers.get("apikey")) {
    return json(401, { ok: false, error: "Missing API key." }, cors);
  }

  const ctype = req.headers.get("content-type") ?? "";
  if (!ctype.toLowerCase().includes("application/json")) {
    return json(415, { ok: false, error: "Content-Type must be application/json." }, cors);
  }

  if (isRateLimited(clientIp(req))) {
    return json(429, { ok: false, error: "Too many requests. Please wait a few minutes and try again." }, cors);
  }

  let body: unknown;
  try {
    const text = await req.text();
    if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
      return json(413, { ok: false, error: "Request too large." }, cors);
    }
    body = text.length === 0 ? {} : JSON.parse(text);
  } catch {
    return json(400, { ok: false, error: "Malformed JSON body." }, cors);
  }

  const checked = validateInput(body);
  if ("error" in checked) {
    return json(400, { ok: false, error: checked.error }, cors);
  }

  const apiKey = env.RESEND_API_KEY ?? "";
  const to = (env.FEEDBACK_TO_EMAIL ?? "").trim();
  const from = (env.FEEDBACK_FROM_EMAIL ?? "").trim();
  if (!apiKey || !to || !from || !isValidEmail(to) || !isValidEmail(from)) {
    // Never leak which variable is missing or any value.
    console.error("send-feedback: email service is not configured (missing/invalid env).");
    return json(500, { ok: false, error: "Feedback service is not configured. Please try again later." }, cors);
  }

  const { category, subject, message, contactEmail, appVersion, platform } = checked.value;
  const emailSubject = `[StudyUp Feedback: ${category}] ${subject}`.slice(0, 160);
  const diag = appVersion || platform
    ? `\nApp: ${appVersion ?? "(unknown version)"} / ${platform ?? "(unknown platform)"}\n`
    : "";
  const text = `Category: ${category}\n` +
    (contactEmail ? `Contact: ${contactEmail}\n` : "Contact: (not provided)\n") +
    `Subject: ${subject}\n${diag}\n${message}\n`;
  const html = `<h2>StudyUp feedback — ${escapeHtml(category)}</h2>` +
    `<p><strong>Subject:</strong> ${escapeHtml(subject)}<br/>` +
    `<strong>Contact:</strong> ${contactEmail ? escapeHtml(contactEmail) : "(not provided)"}<br/>` +
    ((appVersion || platform)
      ? `<strong>App:</strong> ${escapeHtml(appVersion ?? "?")} / ${escapeHtml(platform ?? "?")}</p>`
      : "</p>") +
    `<pre style="white-space:pre-wrap;font-family:inherit">${escapeHtml(message)}</pre>`;

  try {
    const id = await sendViaResend(
      { apiKey, to, from, replyTo: contactEmail, subject: emailSubject, text, html },
      fetchImpl,
    );
    // "Accepted by Resend" only — Resend queues delivery async; confirmed
    // delivery requires webhooks. Never claim delivery here.
    return json(200, { ok: true, id }, cors);
  } catch (e) {
    console.error("send-feedback: resend failed:", e instanceof Error ? e.message : e);
    return json(502, { ok: false, error: "Could not send feedback right now. Please try again later." }, cors);
  }
}

function denoEnv(): Record<string, string | undefined> {
  return {
    // deno-lint-ignore no-explicit-any
    RESEND_API_KEY: (globalThis as any).Deno?.env.get("RESEND_API_KEY"),
    // deno-lint-ignore no-explicit-any
    FEEDBACK_TO_EMAIL: (globalThis as any).Deno?.env.get("FEEDBACK_TO_EMAIL"),
    // deno-lint-ignore no-explicit-any
    FEEDBACK_FROM_EMAIL: (globalThis as any).Deno?.env.get("FEEDBACK_FROM_EMAIL"),
  };
}

if (import.meta.main) {
  Deno.serve((req: Request) => handleRequest(req, denoEnv()));
}
