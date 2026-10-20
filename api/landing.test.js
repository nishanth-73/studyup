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
const assetsDir = path.join(root, 'public', 'assets');

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

test('landing: the decorative web images are gone for good', () => {
  // No image markup and no decoration layer that existed only to host them.
  assert.doesNotMatch(index, /<img\b/i, 'no <img> tags may come back');
  assert.doesNotMatch(index, /class="art"/, 'the .art layer must stay removed');
  assert.doesNotMatch(index, /\.art\b/, 'no .art CSS rules may come back');
  assert.doesNotMatch(index, /@keyframes\s+float/, 'no float keyframes');
  assert.doesNotMatch(index, /\/assets\//, 'nothing may reference /assets/');
  // ...and the files themselves are deleted, not just unlinked.
  if (fs.existsSync(assetsDir)) {
    const leftovers = fs
      .readdirSync(assetsDir)
      .filter((name) => /^web-[1-4]\./i.test(name));
    assert.deepEqual(leftovers, [], 'web-1..4 image files must be deleted');
  }
});

test('landing: invitation page offers Download only via the configured URL', () => {
  // The button exists but starts hidden: JavaScript reveals it only after
  // apk.json yields a valid https destination.
  assert.match(index, /id="downloadInInvite"[^>]*hidden/);
  assert.match(index, /id="downloadMissing"/, 'unconfigured state must be shown');
  assert.match(index, /No download destination is/);
  // The code is carried into the download URL when one is configured.
  assert.match(index, /withInviteCode/);
  assert.match(index, /'invite=' \+ encodeURIComponent/);
  // Reopening the same link is the documented hand-off after installing.
  assert.match(index, /id="reopenHint"/);
  assert.match(index, /reopen this/i);
  // No invented store listing anywhere in the page.
  assert.doesNotMatch(index, /play\.google\.com/i);
  assert.doesNotMatch(index, /market:\/\/links/i);
  assert.doesNotMatch(index, /apps\.apple\.com/i);
});

test('landing: one clean invitation URL, no payloads or secrets', () => {
  assert.match(index, /\(\?:i\|invite\)/, 'token path parsing');
  assert.doesNotMatch(index, /SUP1/, 'never share the offline SUP1 payload');
  assert.doesNotMatch(index, /service_role/i);
  assert.doesNotMatch(index, /eyJ[A-Za-z0-9_-]{10,}/, 'no JWT-looking string');
});

// ---------------------------------------------------------------------------
// Behavioural tests: the page script is executed against a stubbed DOM so the
// two recipient paths are covered for real (not only by string matching).
//   installed  -> App Link/intent hands the code straight to the app
//   missing    -> a Download button appears, carrying the invitation code
// ---------------------------------------------------------------------------
const script = index.match(/<script>([\s\S]*?)<\/script>/)[1];
// id -> the opening tag it belongs to, so a stub can start out with the
// same `hidden` state the markup declares.
const elementTags = [...index.matchAll(/<[^>]*\sid="([^"]+)"[^>]*>/g)].map((m) => ({
  id: m[1],
  tag: m[0],
}));

function setGlobal(name, value) {
  Object.defineProperty(global, name, {
    value,
    configurable: true,
    writable: true,
  });
}

async function runLanding({ path: pagePath, userAgent, apk }) {
  const handlers = new Map();
  let copiedText = null;
  const makeEl = (id, tag) => ({
    id,
    hidden: /\shidden\b/.test(tag || ''),
    textContent: '',
    href: '',
    disabled: /\sdisabled\b/.test(tag || ''),
    addEventListener(event, handler) {
      handlers.set(`${id}:${event}`, handler);
    },
  });
  const els = new Map();
  for (const { id, tag } of elementTags) els.set(id, makeEl(id, tag));
  const get = (id) => {
    if (!els.has(id)) els.set(id, makeEl(id, ''));
    return els.get(id);
  };
  const saved = {};
  for (const name of ['document', 'location', 'navigator', 'fetch', 'setTimeout']) {
    saved[name] = Object.getOwnPropertyDescriptor(global, name);
  }
  setGlobal('document', { getElementById: get });
  setGlobal('location', {
    pathname: pagePath,
    href: `https://invite.example.com${pagePath}`,
  });
  setGlobal('navigator', {
    userAgent,
    clipboard: {
      writeText: async (text) => {
        copiedText = text;
      },
    },
  });
  setGlobal('setTimeout', () => 0);
  setGlobal('fetch', () =>
    Promise.resolve({ ok: true, json: () => Promise.resolve(apk) }),
  );
  try {
    // eslint-disable-next-line no-new-func
    new Function(script)();
    // Flush the fetch().then().then() chain started by the script.
    await new Promise((r) => setImmediate(r));
    await new Promise((r) => setImmediate(r));
  } finally {
    for (const name of ['document', 'location', 'navigator', 'fetch', 'setTimeout']) {
      if (saved[name]) Object.defineProperty(global, name, saved[name]);
      else delete global[name];
    }
  }
  Object.defineProperty(els, 'click', {
    value: async (id) => {
      setGlobal('navigator', {
        userAgent,
        clipboard: {
          writeText: async (text) => {
            copiedText = text;
          },
        },
      });
      setGlobal('setTimeout', () => 0);
      try {
        handlers.get(`${id}:click`)?.();
        await Promise.resolve();
        await Promise.resolve();
      } finally {
        if (saved.navigator) {
          Object.defineProperty(global, 'navigator', saved.navigator);
        } else {
          delete global.navigator;
        }
        if (saved.setTimeout) {
          Object.defineProperty(global, 'setTimeout', saved.setTimeout);
        } else {
          delete global.setTimeout;
        }
      }
    },
  });
  Object.defineProperty(els, 'copiedText', { get: () => copiedText });
  return els;
}

const TOKEN = 'aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233';
const CONFIGURED = {
  apkUrl: 'https://downloads.example.com/studyup.apk',
  version: '1.0.0',
  sizeMb: 12,
  note: 'ok',
};
const ANDROID =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120 Mobile';

test('landing: invite link with the app installed hands the code to the app', async () => {
  const els = await runLanding({
    path: `/i/${TOKEN}`,
    userAgent: ANDROID,
    apk: CONFIGURED,
  });
  assert.equal(els.get('inviteBox').hidden, false);
  assert.equal(els.get('inviteCode').textContent, TOKEN);
  assert.equal(els.get('copyCode').hidden, false);
  assert.equal(els.get('openApp').hidden, false);
  // The custom-scheme hand-off carries the invitation code itself.
  assert.match(els.get('openApp').href, /^intent:\/\/invite\//);
  assert.ok(els.get('openApp').href.includes(TOKEN));
  // The browser fallback sends the recipient back to this same link.
  assert.match(els.get('openApp').href, /S\.browser_fallback_url=/);
  await els.click('copyCode');
  assert.equal(els.copiedText, TOKEN);
  assert.equal(els.get('copyCode').textContent, 'Code copied');
});

test('landing: invite link without the app offers a real Download button', async () => {
  const els = await runLanding({
    path: `/i/${TOKEN}`,
    userAgent: ANDROID,
    apk: CONFIGURED,
  });
  assert.equal(els.get('downloadInInvite').hidden, false);
  // The invitation code survives the download hand-off.
  assert.equal(
    els.get('downloadInInvite').href,
    `https://downloads.example.com/studyup.apk?invite=${TOKEN}`,
  );
  assert.match(els.get('downloadInInvite').textContent, /Download StudyUp/);
  assert.equal(els.get('reopenHint').hidden, false, 'reopen hint shown');
  assert.equal(els.get('downloadMissing').hidden, true);
  assert.equal(els.get('apkLink').href, els.get('downloadInInvite').href);
  assert.equal(els.get('apkSoon').hidden, true);
});

test('landing: a store URL with an existing query keeps the code', async () => {
  const els = await runLanding({
    path: `/i/${TOKEN}`,
    userAgent: ANDROID,
    apk: { ...CONFIGURED, apkUrl: 'https://play.example.com/store/apps/details?id=com.studyup.studyup&hl=en' },
  });
  assert.equal(
    els.get('downloadInInvite').href,
    'https://play.example.com/store/apps/details?id=com.studyup.studyup&hl=en' +
      `&invite=${TOKEN}`,
  );
});

test('landing: no configured download destination never invents a URL', async () => {
  for (const apk of [
    { ...CONFIGURED, apkUrl: '' },
    { ...CONFIGURED, apkUrl: 'http://insecure.example.com/app.apk' },
    { ...CONFIGURED, apkUrl: 'https://example.com/debug-app.apk' },
    null,
  ]) {
    const els = await runLanding({ path: `/i/${TOKEN}`, userAgent: ANDROID, apk });
    assert.equal(els.get('downloadInInvite').hidden, true, 'no button');
    assert.equal(els.get('downloadInInvite').href, '', 'no URL invented');
    assert.equal(els.get('downloadMissing').hidden, false, 'config gap stated');
    assert.equal(els.get('apkSoon').hidden, false);
  }
});

test('landing: malformed invite path shows an actionable message', async () => {
  const els = await runLanding({ path: '/i/short', userAgent: ANDROID, apk: CONFIGURED });
  assert.equal(els.get('inviteBox').hidden, false);
  assert.equal(els.get('inviteTitle').textContent, 'Invitation unavailable');
  assert.match(els.get('inviteMessage').textContent, /malformed/);
  assert.equal(els.get('copyLink').hidden, true);
  assert.equal(els.get('openApp').hidden, true);
  assert.equal(els.get('downloadInInvite').hidden, true);
});

test('landing: the plain (non-invite) landing stays untouched', async () => {
  const els = await runLanding({ path: '/', userAgent: ANDROID, apk: CONFIGURED });
  assert.equal(els.get('inviteBox').hidden, true);
  assert.equal(els.get('openApp').hidden, true);
  assert.equal(els.get('downloadInInvite').hidden, true);
  // The download link still works, just without an invitation code.
  assert.equal(els.get('apkLink').href, CONFIGURED.apkUrl);
});

test('landing: desktop recipients get a download, never an intent link', async () => {
  const els = await runLanding({
    path: `/i/${TOKEN}`,
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120',
    apk: CONFIGURED,
  });
  assert.equal(els.get('openApp').hidden, true, 'no intent link off Android');
  assert.equal(els.get('downloadInInvite').hidden, false);
  assert.ok(els.get('downloadInInvite').href.includes(TOKEN));
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
