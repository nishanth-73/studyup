// Guards the hosted App Links association file.
//
// public/.well-known/assetlinks.json is what Vercel serves at
// https://studyup-4x7z.vercel.app/.well-known/assetlinks.json
// (public/ is the default static output directory for non-framework
// Vercel projects). supabase/assetlinks/assetlinks.json is the
// documentation copy; both must stay identical.
//
// Run from this directory:  node --test assetlinks.test.js

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const deployedPath = path.join(
  __dirname,
  '..',
  'public',
  '.well-known',
  'assetlinks.json',
);
const docsPath = path.join(
  __dirname,
  '..',
  'supabase',
  'assetlinks',
  'assetlinks.json',
);

const fingerprintPattern = /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/;

function load(file) {
  const raw = fs.readFileSync(file, 'utf8');
  return { raw, json: JSON.parse(raw) };
}

test('assetlinks: deployed copy exists, is valid JSON and matches the docs copy', () => {
  const deployed = load(deployedPath);
  const docs = load(docsPath);
  assert.deepEqual(deployed.json, docs.json);
});

test('assetlinks: targets the StudyUp package with well-formed SHA-256 fingerprints', () => {
  const { json } = load(deployedPath);
  assert.ok(Array.isArray(json) && json.length === 1);
  const [entry] = json;
  assert.deepEqual(entry.relation, [
    'delegate_permission/common.handle_all_urls',
  ]);
  assert.equal(entry.target.namespace, 'android_app');
  assert.equal(entry.target.package_name, 'com.studyup.studyup');
  const fingerprints = entry.target.sha256_cert_fingerprints;
  assert.ok(Array.isArray(fingerprints) && fingerprints.length >= 1);
  for (const fingerprint of fingerprints) {
    assert.match(
      fingerprint,
      fingerprintPattern,
      `"${fingerprint}" must be 32 colon-separated uppercase hex pairs`,
    );
  }
});

test('assetlinks: no placeholder values remain', () => {
  const { raw } = load(deployedPath);
  assert.ok(!raw.includes('REPLACE_WITH'), 'replace placeholders before deploy');
});
