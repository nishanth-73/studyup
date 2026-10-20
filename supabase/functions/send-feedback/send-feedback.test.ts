// Tests for the `send-feedback` Edge Function.
// Never sends real email: Resend's fetch is fully mocked.
// Run from the repo root: deno test --allow-env supabase/functions/send-feedback/

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  clearRateLimit,
  handleRequest,
  isValidEmail,
  validateInput,
} from "./index.ts";

const ENV = {
  RESEND_API_KEY: "re_test_key",
  FEEDBACK_TO_EMAIL: "owner@example.com",
  FEEDBACK_FROM_EMAIL: "onboarding@resend.dev",
};

function req(body: unknown, init?: RequestInit): Request {
  return new Request("http://localhost/functions/v1/send-feedback", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: "test-anon-key",
    },
    body: JSON.stringify(body),
    ...init,
  });
}

const okFetch = () =>
  Promise.resolve(new Response(JSON.stringify({ id: "mock-resend-id" }), { status: 200 }));

Deno.test("accepts valid POST and returns the Resend id (accepted, not delivered)", async () => {
  clearRateLimit();
  const res = await handleRequest(
    req({
      category: "bug",
      subject: "Timer kept running",
      message: "Step 1, step 2, it kept ticking.",
      contactEmail: "user@example.com",
    }),
    ENV,
    okFetch as typeof fetch,
  );
  assertEquals(res.status, 200);
  const data = await res.json();
  assertEquals(data, { ok: true, id: "mock-resend-id" });
});

Deno.test("forwards required contact email as reply_to, never as recipient", async () => {
  clearRateLimit();
  let sent: Record<string, unknown> = {};
  const capture = ((_url: string | URL | Request, init?: RequestInit) => {
    sent = JSON.parse(init?.body as string) as Record<string, unknown>;
    return Promise.resolve(new Response(JSON.stringify({ id: "x" }), { status: 200 }));
  }) as typeof fetch;
  const res = await handleRequest(
    req({
      category: "feature",
      subject: "Dark mode please",
      message: "Please add an even darker mode for night study sessions.",
      contactEmail: "user@example.com",
      appVersion: "1.0.0+1",
      platform: "android",
    }),
    ENV,
    capture,
  );
  assertEquals(res.status, 200);
  assertEquals(sent["to"], ["owner@example.com"]);
  assertEquals(sent["reply_to"], "user@example.com");
  assert((sent["text"] as string).includes("1.0.0+1"));
});

Deno.test("rejects invalid category / short message / bad email", async () => {
  clearRateLimit();
  for (const body of [
    { category: "spam", subject: "Valid subject here", message: "A long enough message body here." },
    { category: "bug", subject: "Hi", message: "short" },
    {
      category: "bug",
      subject: "Valid subject here",
      message: "A long enough message body here.",
      contactEmail: "not-an-email",
    },
  ]) {
    const res = await handleRequest(req(body), ENV, okFetch as typeof fetch);
    assertEquals(res.status, 400);
  }
  const missingEmail = await handleRequest(
    req({
      category: "bug",
      subject: "Valid subject here",
      message: "A long enough message body here.",
    }),
    ENV,
    okFetch as typeof fetch,
  );
  assertEquals(missingEmail.status, 400);
  assert((await missingEmail.text()).includes("Contact email is required."));
});

Deno.test("rejects non-POST methods with 405 + Allow header", async () => {
  const res = await handleRequest(
    new Request("http://localhost/", { method: "GET", headers: { apikey: "k" } }),
    ENV,
    okFetch as typeof fetch,
  );
  assertEquals(res.status, 405);
  assert((res.headers.get("Allow") ?? "").includes("POST"));
});

Deno.test("refuses requests without the gateway apikey header", async () => {
  const res = await handleRequest(
    new Request("http://localhost/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    }),
    ENV,
    okFetch as typeof fetch,
  );
  assertEquals(res.status, 401);
});

Deno.test("returns non-sensitive 500 when env is missing (never leaks values)", async () => {
  clearRateLimit();
  const res = await handleRequest(
    req({
      category: "bug",
      subject: "Valid subject here",
      message: "A long enough message body here.",
      contactEmail: "user@example.com",
    }),
    { RESEND_API_KEY: "", FEEDBACK_TO_EMAIL: "", FEEDBACK_FROM_EMAIL: "" },
    okFetch as typeof fetch,
  );
  assertEquals(res.status, 500);
  const text = JSON.stringify(await res.json());
  assert(!/re_test|resend/i.test(text));
});

Deno.test("maps Resend provider failure to 502 without leaking provider detail", async () => {
  clearRateLimit();
  const failing = (() =>
    Promise.resolve(
      new Response(JSON.stringify({ message: "secret-provider-reason" }), { status: 403 }),
    )) as typeof fetch;
  const res = await handleRequest(
    req({
      category: "bug",
      subject: "Valid subject here",
      message: "A long enough message body here.",
      contactEmail: "user@example.com",
    }),
    ENV,
    failing,
  );
  assertEquals(res.status, 502);
  const text = JSON.stringify(await res.json());
  assert(!text.includes("secret-provider-reason"));
});

Deno.test("rate-limits floods with 429", async () => {
  clearRateLimit();
  const payload = {
    category: "other",
    subject: "Valid subject here",
    message: "A long enough message body here.",
    contactEmail: "user@example.com",
  };
  for (let i = 0; i < 5; i++) {
    const r = await handleRequest(
      new Request("http://localhost/", {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: "k", "x-forwarded-for": "9.9.9.9" },
        body: JSON.stringify(payload),
      }),
      ENV,
      okFetch as typeof fetch,
    );
    assertEquals(r.status, 200);
  }
  const limited = await handleRequest(
    new Request("http://localhost/", {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: "k", "x-forwarded-for": "9.9.9.9" },
      body: JSON.stringify(payload),
    }),
    ENV,
    okFetch as typeof fetch,
  );
  assertEquals(limited.status, 429);
});

Deno.test("validateInput enforces length limits", () => {
  assert("error" in validateInput({ category: "bug", subject: "ab", message: "long enough message!!" }));
  assert("error" in validateInput({ category: "bug", subject: "ok subject", message: "x".repeat(2001) }));
  assert(
    "error" in
      validateInput({ category: "bug", subject: "ok subject", message: "fine message here", contactEmail: "a@b" }),
  );
  assert(isValidEmail("user@example.com"));
  assert(!isValidEmail("a@b"));
});
