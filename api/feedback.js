'use strict';

// Vercel Serverless Function: POST /api/feedback
// Sends StudyUp app feedback via Resend. No framework required.
//
// NOTE: the primary transport is now the Supabase `send-feedback` Edge
// Function (supabase/functions/send-feedback). This endpoint is kept as a
// fallback for builds without a Supabase backend. Both share the same
// request contract and validation limits.
//
// Required server-side env vars (Vercel Dashboard -> Settings -> Environment Variables):
//   RESEND_API_KEY, FEEDBACK_TO_EMAIL, FEEDBACK_FROM_EMAIL
//
// Request contract (JSON):
//   { category: "bug"|"feature"|"improvement"|"other",
//     subject: string (3..120),
//     message: string (10..2000),
//     contactEmail: string (required, valid email, max 254) }
// Response:
//   200 { ok: true, id: "<resend-id>" }  -> accepted by Resend (NOT confirmed delivery)
//   4xx/5xx { ok: false, error: "<non-sensitive message>" }

const ALLOWED_CATEGORIES = new Set(['bug', 'feature', 'improvement', 'other']);
const MAX_BODY_BYTES = 16 * 1024;
const MESSAGE_MAX = 2000;
const MESSAGE_MIN = 10;
const SUBJECT_MAX = 120;
const SUBJECT_MIN = 3;

// Basic per-instance rate limit: 5 requests / 10 min per IP.
// Note: serverless instances do not share memory, so for strict production
// abuse protection use Vercel KV / Upstash Redis. This still blocks naive floods.
const RATE_WINDOW_MS = 10 * 60 * 1000;
const RATE_MAX = 5;
const _hits = new Map(); // ip -> number[]

function pruneHits(now) {
  for (const [ip, times] of _hits) {
    const fresh = times.filter((t) => now - t < RATE_WINDOW_MS);
    if (fresh.length === 0) _hits.delete(ip);
    else _hits.set(ip, fresh);
  }
}

function isRateLimited(ip) {
  const now = Date.now();
  if (_hits.size > 5000) pruneHits(now);
  const times = (_hits.get(ip) || []).filter((t) => now - t < RATE_WINDOW_MS);
  if (times.length >= RATE_MAX) {
    _hits.set(ip, times);
    return true;
  }
  times.push(now);
  _hits.set(ip, times);
  return false;
}

function clearRateLimit() {
  _hits.clear();
}

function clientIp(req) {
  const fwd = req.headers && req.headers['x-forwarded-for'];
  if (typeof fwd === 'string' && fwd.length > 0) return fwd.split(',')[0].trim();
  if (req.socket && req.socket.remoteAddress) return req.socket.remoteAddress;
  return 'unknown';
}

function setCors(req, res) {
  // CORS is for browser callers only; it is NOT authentication or abuse protection.
  // The Android app does not need CORS. Allow any origin for the web preview.
  const origin = (req.headers && req.headers.origin) || '*';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Max-Age', '86400');
}

function sendJson(res, status, obj) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(obj));
}

function stripControls(s) {
  // Remove ASCII control chars except \n \t; cap length defensively.
  return s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
}

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function isValidEmail(v) {
  if (typeof v !== 'string' || v.length === 0 || v.length > 254) return false;
  // Practical RFC-5322 subset; server-side only, never used for routing except reply-to.
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const declared = req.headers && req.headers['content-length'];
    if (declared && Number(declared) > MAX_BODY_BYTES) {
      const e = new Error('Request too large.');
      e.code = 'TOO_LARGE';
      reject(e);
      return;
    }
    // Vercel may pre-parse the body for us.
    if (req.body !== undefined && req.body !== null) {
      if (typeof req.body === 'object') {
        resolve(req.body);
        return;
      }
      if (typeof req.body === 'string') {
        if (Buffer.byteLength(req.body, 'utf8') > MAX_BODY_BYTES) {
          const e = new Error('Request too large.');
          e.code = 'TOO_LARGE';
          reject(e);
          return;
        }
        try {
          resolve(req.body.length === 0 ? {} : JSON.parse(req.body));
        } catch {
          const e = new Error('Malformed JSON body.');
          e.code = 'BAD_JSON';
          reject(e);
        }
        return;
      }
    }
    let bytes = 0;
    const chunks = [];
    req.on('data', (c) => {
      bytes += c.length;
      if (bytes > MAX_BODY_BYTES) {
        const e = new Error('Request too large.');
        e.code = 'TOO_LARGE';
        reject(e);
        if (typeof req.destroy === 'function') req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (raw.length === 0) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        const e = new Error('Malformed JSON body.');
        e.code = 'BAD_JSON';
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

function validateInput(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { error: 'Malformed request: expected a JSON object.' };
  }
  const rawCategory = typeof body.category === 'string' ? body.category.trim().toLowerCase() : '';
  const rawSubject = typeof body.subject === 'string' ? stripControls(body.subject).trim() : '';
  const rawMessage = typeof body.message === 'string' ? stripControls(body.message).trim() : '';
  const rawContact =
    body.contactEmail !== undefined && body.contactEmail !== null
      ? String(body.contactEmail).trim()
      : body.email !== undefined && body.email !== null
        ? String(body.email).trim()
        : '';

  if (!ALLOWED_CATEGORIES.has(rawCategory)) {
    return { error: 'Choose a valid category: bug, feature, improvement, or other.' };
  }
  if (rawSubject.length < SUBJECT_MIN || rawSubject.length > SUBJECT_MAX) {
    return { error: `Subject must be ${SUBJECT_MIN}-${SUBJECT_MAX} characters.` };
  }
  if (rawMessage.length < MESSAGE_MIN || rawMessage.length > MESSAGE_MAX) {
    return { error: `Message must be ${MESSAGE_MIN}-${MESSAGE_MAX} characters.` };
  }
  if (rawContact === '') {
    return { error: 'Contact email is required.' };
  }
  if (!isValidEmail(rawContact)) {
    return { error: 'Contact email is not a valid email address.' };
  }
  return {
    value: {
      category: rawCategory,
      subject: rawSubject,
      message: rawMessage,
      contactEmail: rawContact,
    },
  };
}

// `fetchImpl` is injectable for tests (defaults to global fetch).
async function sendViaResend({ apiKey, to, from, replyTo, subject, text, html }, fetchImpl) {
  const impl = fetchImpl || fetch;
  const res = await impl('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      text,
      html,
      ...(replyTo ? { reply_to: replyTo } : {}),
    }),
  });
  let payload = null;
  try {
    payload = await res.json();
  } catch {
    payload = null;
  }
  if (!res.ok) {
    const providerMsg =
      payload && typeof payload.message === 'string' ? payload.message : `Resend error (status ${res.status})`;
    // Returned to logs only; callers get a generic message.
    const err = new Error(providerMsg);
    err.code = 'RESEND_REJECTED';
    err.status = res.status;
    throw err;
  }
  return payload && typeof payload.id === 'string' ? payload.id : null;
}

async function handler(req, res, opts = {}) {
  setCors(req, res);

  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return;
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    sendJson(res, 405, { ok: false, error: 'Method not allowed. Use POST.' });
    return;
  }

  const ctype = String((req.headers && req.headers['content-type']) || '');
  if (!ctype.toLowerCase().includes('application/json')) {
    sendJson(res, 415, { ok: false, error: 'Content-Type must be application/json.' });
    return;
  }

  if (isRateLimited(clientIp(req))) {
    sendJson(res, 429, { ok: false, error: 'Too many requests. Please wait a few minutes and try again.' });
    return;
  }

  let body;
  try {
    body = await readJsonBody(req);
  } catch (e) {
    if (e && e.code === 'TOO_LARGE') {
      sendJson(res, 413, { ok: false, error: 'Request too large.' });
      return;
    }
    sendJson(res, 400, { ok: false, error: 'Malformed JSON body.' });
    return;
  }

  const checked = validateInput(body);
  if (checked.error) {
    sendJson(res, 400, { ok: false, error: checked.error });
    return;
  }

  const apiKey = process.env.RESEND_API_KEY || '';
  const to = (process.env.FEEDBACK_TO_EMAIL || '').trim();
  const from = (process.env.FEEDBACK_FROM_EMAIL || '').trim();
  if (!apiKey || !to || !from) {
    // Never leak which variable is missing or any value.
    console.error('feedback: email service is not configured (missing env).');
    sendJson(res, 500, { ok: false, error: 'Feedback service is not configured. Please try again later.' });
    return;
  }
  if (!isValidEmail(to) || !isValidEmail(from)) {
    console.error('feedback: email service is misconfigured (invalid address).');
    sendJson(res, 500, { ok: false, error: 'Feedback service is not configured. Please try again later.' });
    return;
  }

  const { category, subject, message, contactEmail } = checked.value;
  const emailSubject = `[StudyUp Feedback: ${category}] ${subject}`.slice(0, 160);
  const text =
    `Category: ${category}\n` +
    `Contact: ${contactEmail}\n` +
    `Subject: ${subject}\n\n${message}\n`;
  const html =
    `<h2>StudyUp feedback — ${escapeHtml(category)}</h2>` +
    `<p><strong>Subject:</strong> ${escapeHtml(subject)}<br/>` +
    `<strong>Contact:</strong> ${escapeHtml(contactEmail)}</p>` +
    `<pre style="white-space:pre-wrap;font-family:inherit">${escapeHtml(message)}</pre>`;

  try {
    const id = await sendViaResend(
      { apiKey, to, from, replyTo: contactEmail, subject: emailSubject, text, html },
      opts.fetchImpl,
    );
    // "Accepted by Resend" only — Resend queues delivery async; confirmed
    // delivery requires webhooks. Never claim delivery here.
    sendJson(res, 200, { ok: true, id });
  } catch (e) {
    console.error('feedback: resend failed:', (e && e.message) || e);
    sendJson(res, 502, { ok: false, error: 'Could not send feedback right now. Please try again later.' });
  }
}

module.exports = handler;
module.exports.validateInput = validateInput;
module.exports.isValidEmail = isValidEmail;
module.exports.clearRateLimit = clearRateLimit;
module.exports.MAX_BODY_BYTES = MAX_BODY_BYTES;
