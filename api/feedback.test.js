'use strict';

// Backend tests for api/feedback.js. Never sends real email: Resend's
// fetch is fully mocked. Run with: node --test feedback.test.js (from api/).

const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const handler = require('./feedback.js');

function mockReq({ method = 'POST', body, headers = {}, ip = '1.2.3.4' } = {}) {
  const listeners = {};
  const req = {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body,
    socket: { remoteAddress: ip },
    on: (ev, fn) => {
      listeners[ev] = fn;
    },
    destroy: () => {},
    _emit: (ev, data) => listeners[ev] && listeners[ev](data),
  };
  return req;
}

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: '',
    setHeader: (k, v) => {
      res.headers[k.toLowerCase()] = v;
    },
    end: (data) => {
      res.body = data || '';
      res.json = res.body ? JSON.parse(res.body) : null;
    },
  };
  return res;
}

function callHandler({ body, method, fetchImpl, env, ip, headers }) {
  const req = mockReq({ method, body, ip, headers });
  const res = mockRes();
  const prev = { ...process.env };
  process.env.RESEND_API_KEY = env?.RESEND_API_KEY ?? 're_test_key';
  process.env.FEEDBACK_TO_EMAIL = env?.FEEDBACK_TO_EMAIL ?? 'owner@example.com';
  process.env.FEEDBACK_FROM_EMAIL = env?.FEEDBACK_FROM_EMAIL ?? 'onboarding@resend.dev';
  return handler(req, res, { fetchImpl }).then(() => {
    Object.assign(process.env, prev);
    return { req, res };
  });
}

const okFetch = async () => ({
  ok: true,
  status: 200,
  json: async () => ({ id: 'mock-resend-id' }),
});

describe('feedback endpoint', () => {
  beforeEach(() => handler.clearRateLimit());

  it('accepts valid POST and returns the Resend id (accepted, not delivered)', async () => {
    const { res } = await callHandler({
      body: { category: 'bug', subject: 'Timer kept running', message: 'Step 1, step 2, it kept ticking.' },
      fetchImpl: okFetch,
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json.ok, true);
    assert.equal(res.json.id, 'mock-resend-id');
  });

  it('forwards optional contact email as reply_to, never as recipient', async () => {
    let sentBody = null;
    const capture = async (url, init) => {
      sentBody = JSON.parse(init.body);
      return { ok: true, status: 200, json: async () => ({ id: 'x' }) };
    };
    const { res } = await callHandler({
      body: {
        category: 'feature',
        subject: 'Dark mode please',
        message: 'Please add an even darker mode for night study sessions.',
        contactEmail: 'user@example.com',
      },
      fetchImpl: capture,
    });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(sentBody.to, ['owner@example.com']);
    assert.equal(sentBody.reply_to, 'user@example.com');
  });

  it('rejects invalid category / short message / bad email', async () => {
    const bad1 = await callHandler({
      body: { category: 'spam', subject: 'Valid subject here', message: 'A long enough message body here.' },
      fetchImpl: okFetch,
    });
    assert.equal(bad1.res.statusCode, 400);

    const bad2 = await callHandler({
      body: { category: 'bug', subject: 'Hi', message: 'short' },
      fetchImpl: okFetch,
    });
    assert.equal(bad2.res.statusCode, 400);

    const bad3 = await callHandler({
      body: {
        category: 'bug',
        subject: 'Valid subject here',
        message: 'A long enough message body here.',
        contactEmail: 'not-an-email',
      },
      fetchImpl: okFetch,
    });
    assert.equal(bad3.res.statusCode, 400);
  });

  it('rejects non-POST methods with 405 + Allow header', async () => {
    const { res } = await callHandler({ method: 'GET', body: undefined, fetchImpl: okFetch });
    assert.equal(res.statusCode, 405);
    assert.match(String(res.headers['allow'] || ''), /POST/);
  });

  it('returns non-sensitive 500 when env is missing (never leaks values)', async () => {
    const { res } = await callHandler({
      body: { category: 'bug', subject: 'Valid subject here', message: 'A long enough message body here.' },
      fetchImpl: okFetch,
      env: { RESEND_API_KEY: '', FEEDBACK_TO_EMAIL: '', FEEDBACK_FROM_EMAIL: '' },
    });
    assert.equal(res.statusCode, 500);
    assert.equal(res.json.ok, false);
    assert.doesNotMatch(JSON.stringify(res.json), /re_test|resend/i);
  });

  it('maps Resend provider failure to 502 without leaking provider detail', async () => {
    const failing = async () => ({ ok: false, status: 403, json: async () => ({ message: 'secret-provider-reason' }) });
    const { res } = await callHandler({
      body: { category: 'bug', subject: 'Valid subject here', message: 'A long enough message body here.' },
      fetchImpl: failing,
    });
    assert.equal(res.statusCode, 502);
    assert.doesNotMatch(JSON.stringify(res.json), /secret-provider-reason/);
  });

  it('rate-limits floods with 429', async () => {
    const payload = { category: 'other', subject: 'Valid subject here', message: 'A long enough message body here.' };
    for (let i = 0; i < 5; i++) {
      const r = await callHandler({ body: payload, fetchImpl: okFetch, ip: '9.9.9.9' });
      assert.equal(r.res.statusCode, 200);
    }
    const limited = await callHandler({ body: payload, fetchImpl: okFetch, ip: '9.9.9.9' });
    assert.equal(limited.res.statusCode, 429);
  });

  it('validateInput enforces length limits', () => {
    assert.ok(handler.validateInput({ category: 'bug', subject: 'ab', message: 'long enough message!!' }).error);
    assert.ok(
      handler.validateInput({ category: 'bug', subject: 'ok subject', message: 'x'.repeat(2001) }).error,
    );
    assert.ok(
      handler.validateInput({ category: 'bug', subject: 'ok subject', message: 'fine message here', contactEmail: 'a@b' })
        .error,
    );
  });
});
