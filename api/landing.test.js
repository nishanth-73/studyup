// Guards the hosted website, routing config, and APK configuration.
// Run from this directory:  node --test landing.test.js

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const indexPath = path.join(root, 'index.html');
const apkPath = path.join(root, 'public', 'apk.json');
const vercelPath = path.join(root, 'vercel.json');

const index = fs.readFileSync(indexPath, 'utf8');
const apk = JSON.parse(fs.readFileSync(apkPath, 'utf8'));
const vercel = JSON.parse(fs.readFileSync(vercelPath, 'utf8'));

test('site: core meta and basic markup are present', () => {
  assert.match(index, /<html lang="en">/);
  assert.match(index, /<meta name="viewport"/);
  assert.match(index, /<div id="root"><\/div>/);
  assert.match(index, /<title>StudyUP<\/title>/);
});

test('site: theme color matches StudyUP dark palette', () => {
  assert.match(index, /<meta name="theme-color" content="#17181D"/);
});

test('site: no secrets or Supabase keys in index.html', () => {
  assert.ok(!/RESEND|API_KEY|SUPABASE|service_role/i.test(index));
  assert.ok(!/eyJ[A-Za-z0-9_-]{10,}/.test(index));
});

test('site: apk.json is a valid placeholder or secure release URL', () => {
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

test('vercel: invite and app routes rewrite to index.html, feedback API intact', () => {
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
