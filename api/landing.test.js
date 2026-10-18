// Guards the hosted landing page, invitation route, APK placeholder and
// Vercel routing config. Everything here must stay:
//   - self-contained (no third-party requests, no trackers),
//   - secret-free (no Resend keys, no Supabase refs),
//   - non-destructive for invitations (the page must never call any
//     accept endpoint; acceptance happens only inside the app).
//
// Run from this directory:  node --test landing.test.js

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const indexPath = path.join(root, 'public', 'index.html');
const apkPath = path.join(root, 'public', 'apk.json');
const vercelPath = path.join(root, 'vercel.json');

const index = fs.readFileSync(indexPath, 'utf8');
const apk = JSON.parse(fs.readFileSync(apkPath, 'utf8'));
const vercel = JSON.parse(fs.readFileSync(vercelPath, 'utf8'));

test('landing: core meta and accessibility basics are present', () => {
  assert.match(index, /<html lang="en">/);
  assert.match(index, /<meta name="viewport"/);
  assert.match(index, /<meta name="robots" content="noindex/);
  assert.match(index, /prefers-reduced-motion/);
  assert.match(index, /<main id="main"/);
  assert.match(index, /Skip to content/);
  assert.match(index, /aria-live="polite"/);
});

test('landing: uses all four decorative images', () => {
  for (let i = 1; i <= 4; i += 1) {
    const ref = `/assets/web-${i}.png`;
    assert.ok(index.includes(ref), `index.html must reference ${ref}`);
    const file = path.join(root, 'public', 'assets', `web-${i}.png`);
    const stat = fs.statSync(file);
    assert.ok(stat.size > 10_000, `web-${i}.png looks broken (too small)`);
    assert.ok(
      stat.size < 1_000_000,
      `web-${i}.png exceeds the 1 MB budget (transparent 1024px renders)`,
    );
  }
});

test('landing: every subresource is same-origin or a data URI', () => {
  const refs = index.match(/(?:src|href)="[^"]+"/g) || [];
  for (const ref of refs) {
    const value = ref.slice(ref.indexOf('"') + 1, -1);
    assert.ok(
      value.startsWith('/') || value.startsWith('data:') || value.startsWith('#'),
      `external-looking reference "${value}" — the page must be self-contained`,
    );
  }
});

test('landing: no secrets, no Supabase, no external API calls', () => {
  assert.ok(!/RESEND|API_KEY|SUPABASE|YOUR_|REPLACE_WITH/i.test(index));
  assert.ok(!/supabase/i.test(index));
});

test('landing: no innerHTML / document.write and no accept call', () => {
  assert.ok(!/innerHTML/.test(index), 'dynamic HTML injection is forbidden');
  assert.ok(!/document\.write/.test(index));
  assert.ok(
    !/accept_invitation|acceptInvitation|\/rest\/v1/i.test(index),
    'the page must never accept invitations server-side',
  );
});

test('landing: invitation mode is token-guarded and Android-only', () => {
  assert.match(index, /\[0-9a-fA-F\]\{32,128\}/, 'token must be validated');
  assert.match(index, /intent:\/\/invite\//, 'Android intent link expected');
  assert.match(index, /scheme=studyup/);
  assert.match(index, /package=com\.studyup\.studyup/);
  assert.match(index, /S\.browser_fallback_url=/);
  assert.match(index, /navigator\.clipboard/);
});

test('landing: malformed invite paths show a safe, actionable error', () => {
  assert.match(index, /var invitePath =/);
  assert.match(index, /Invitation unavailable/);
  assert.match(index, /This invitation link is malformed/);
});

test('landing: apk.json is a safe placeholder until a release URL exists', () => {
  assert.equal(typeof apk.apkUrl, 'string');
  if (apk.apkUrl !== '') {
    assert.match(apk.apkUrl, /^https:\/\//, 'APK URL must be https');
    assert.ok(!/debug/i.test(apk.apkUrl), 'never link a debug APK');
  } else {
    assert.ok(
      typeof apk.note === 'string' && apk.note.length > 0,
      'placeholder needs an explanatory note',
    );
  }
});

test('vercel: invite routes rewrite to the landing page, feedback API intact', () => {
  const rewrites = vercel.rewrites || [];
  const targets = rewrites
    .filter((r) => r.destination === '/index.html')
    .map((r) => r.source);
  assert.ok(targets.includes('/i/:token'), '/i/:token must rewrite');
  assert.ok(targets.includes('/invite/:token'), '/invite/:token must rewrite');
  assert.equal(vercel.functions['api/feedback.js'].maxDuration, 10);

  const apkHeaders = (vercel.headers || []).find(
    (h) => h.source === '/apk.json',
  );
  assert.ok(apkHeaders, 'apk.json must have cache headers');
  assert.ok(apkHeaders.headers.some((h) => /no-cache/i.test(h.value)));
});
