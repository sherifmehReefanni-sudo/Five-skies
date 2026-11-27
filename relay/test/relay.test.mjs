// Run with: node --test test/
// Uses a stubbed global fetch that pretends to be Quran Foundation.

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker, { __test } from "../src/index.js";

const TOKEN_A = "stub-token-AAAA-1111";
const TOKEN_B = "stub-token-BBBB-2222";
const CLIENT_ID = "stub-client-id-xyz";
const SECRET = "stub-secret-do-not-leak";
const APP_KEY = "stub-app-key-123";
const SENSITIVE = [TOKEN_A, TOKEN_B, CLIENT_ID, SECRET, btoa(`${CLIENT_ID}:${SECRET}`)];

const realFetch = globalThis.fetch;
let qf; // simulated QF state

function makeQF() {
  return {
    tokenCalls: 0,
    contentCalls: 0,
    tokens: [TOKEN_A, TOKEN_B],
    expiresIn: 3600,
    contentStatus: () => 200,
    lastContent: null,
    tokenDelayMs: 20,
  };
}

function installStub() {
  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    if (url.endsWith("/oauth2/token")) {
      qf.tokenCalls++;
      assert.equal(init.method, "POST");
      assert.equal(init.headers["Content-Type"], "application/x-www-form-urlencoded");
      assert.equal(init.headers.Authorization, `Basic ${btoa(`${CLIENT_ID}:${SECRET}`)}`);
      assert.equal(init.body, "grant_type=client_credentials&scope=content");
      await new Promise((r) => setTimeout(r, qf.tokenDelayMs));
      const token = qf.tokens[Math.min(qf.tokenCalls - 1, qf.tokens.length - 1)];
      return Response.json({ access_token: token, expires_in: qf.expiresIn, token_type: "bearer" });
    }
    if (url.includes("/content/api/v4/")) {
      qf.contentCalls++;
      qf.lastContent = { url, headers: { ...init.headers }, method: init.method };
      const status = qf.contentStatus(init.headers["x-auth-token"], qf.contentCalls);
      const body = status === 200 ? { data: "ok", path: new URL(url).pathname } : { error: `status ${status}` };
      return new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json", "set-cookie": "upstream=1", "x-upstream": "1" },
      });
    }
    throw new Error(`unexpected fetch to ${url}`);
  };
}

function baseEnv(extra = {}) {
  return { QF_ENV: "prelive", QF_CLIENT_ID: CLIENT_ID, QF_CLIENT_SECRET: SECRET, ...extra };
}

async function call(path, { method = "GET", headers = {}, env = baseEnv(), raw = false } = {}) {
  const url = `https://relay.example${path}`;
  // raw: hand the worker an unnormalized URL string, as a hostile client might.
  const request = raw
    ? { url, method, headers: new Headers(headers) }
    : new Request(url, { method, headers });
  return worker.fetch(request, env, undefined);
}

// Every response must be free of credentials, in headers and body.
async function assertClean(res) {
  const text = await res.clone().text();
  const headerText = [...res.headers].map(([k, v]) => `${k}: ${v}`).join("\n");
  for (const s of SENSITIVE) {
    assert.ok(!text.includes(s), `body leaked ${s}`);
    assert.ok(!headerText.includes(s), `headers leaked ${s}`);
  }
  return text;
}

beforeEach(() => {
  __test.reset();
  qf = makeQF();
  installStub();
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

test("health returns ok and environment, nothing sensitive", async () => {
  let res = await call("/health");
  assert.equal(res.status, 200);
  assert.deepEqual(JSON.parse(await assertClean(res)), { ok: true, environment: "prelive" });
  res = await call("/health", { env: baseEnv({ QF_ENV: "production" }) });
  assert.deepEqual(await res.json(), { ok: true, environment: "production" });
  res = await call("/health", { env: {} });
  assert.deepEqual(await res.json(), { ok: true, environment: "prelive" });
  assert.equal(qf.tokenCalls, 0);
});

test("only GET and HEAD are allowed", async () => {
  for (const method of ["POST", "PUT", "DELETE", "PATCH", "OPTIONS"]) {
    const res = await call("/content/api/v4/chapters", { method });
    assert.equal(res.status, 405, method);
    await assertClean(res);
  }
  const head = await call("/content/api/v4/chapters", { method: "HEAD" });
  assert.equal(head.status, 200);
  assert.equal(qf.lastContent.method, "HEAD");
});

test("paths outside /content/api/v4/ return 404", async () => {
  for (const p of ["/", "/oauth2/token", "/content/api/v3/chapters", "/content/api/v4", "/content/api/v4/", "/api/v4/chapters"]) {
    const res = await call(p);
    assert.equal(res.status, 404, p);
    await assertClean(res);
  }
  assert.equal(qf.contentCalls, 0);
});

test("allow-list: permitted prefixes pass, others 404", async () => {
  const allowed = [
    "/content/api/v4/chapters",
    "/content/api/v4/chapters/1/info",
    "/content/api/v4/resources/translations",
    "/content/api/v4/resources/tafsirs",
    "/content/api/v4/resources/recitations",
    "/content/api/v4/resources/languages",
    "/content/api/v4/resources/sync?since=2026-01-01",
    "/content/api/v4/resources/snapshots/abc/files",
    "/content/api/v4/verses/by_key/2:255?translations=20",
    "/content/api/v4/quran/verses/uthmani?chapter_number=1",
    "/content/api/v4/chapter_recitations/7/1",
    "/content/api/v4/recitations/7/by_chapter/1",
    "/content/api/v4/audio/reciters",
  ];
  for (const p of allowed) {
    const res = await call(p);
    assert.equal(res.status, 200, p);
    await assertClean(res);
  }
  const blocked = [
    "/content/api/v4/search?q=x",
    "/content/api/v4/resources/chapter_infos",
    "/content/api/v4/resources",
    "/content/api/v4/verses",
    "/content/api/v4/chaptersX",
    "/content/api/v4/users/me",
    "/content/api/v4/foo/chapters",
  ];
  for (const p of blocked) {
    const res = await call(p);
    assert.equal(res.status, 404, p);
  }
  assert.equal(qf.contentCalls, allowed.length);
});

test("query string is passed through and auth headers are added upstream", async () => {
  const res = await call("/content/api/v4/verses/by_chapter/1?language=en&per_page=10", {
    headers: { Cookie: "session=abc", Authorization: "Bearer app-user-token", "x-app-key": "whatever" },
  });
  assert.equal(res.status, 200);
  assert.equal(qf.lastContent.url, "https://apis-prelive.quran.foundation/content/api/v4/verses/by_chapter/1?language=en&per_page=10");
  const h = qf.lastContent.headers;
  assert.equal(h["x-auth-token"], TOKEN_A);
  assert.equal(h["x-client-id"], CLIENT_ID);
  const names = Object.keys(h).map((k) => k.toLowerCase());
  assert.ok(!names.includes("cookie"));
  assert.ok(!names.includes("authorization"));
  assert.ok(!names.includes("x-app-key"));
  // Upstream cookies and odd headers are not copied back to the app.
  assert.equal(res.headers.get("set-cookie"), null);
  assert.equal(res.headers.get("x-upstream"), null);
  assert.equal(res.headers.get("content-type"), "application/json");
});

test("production switches both base URLs", async () => {
  const urls = [];
  const stub = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    urls.push(typeof input === "string" ? input : input.url);
    return stub(input, init);
  };
  const res = await call("/content/api/v4/chapters", { env: baseEnv({ QF_ENV: "production" }) });
  assert.equal(res.status, 200);
  assert.equal(urls[0], "https://oauth2.quran.foundation/oauth2/token");
  assert.equal(urls[1], "https://apis.quran.foundation/content/api/v4/chapters");
});

test("path traversal and absolute URLs are rejected", async () => {
  const raw = [
    "/content/api/v4/../../oauth2/token",
    "/content/api/v4/chapters/../../../admin",
    "/content/api/v4/%2e%2e/%2e%2e/oauth2/token",
    "/content/api/v4/chapters/%2E%2E/secret",
    "/content/api/v4/chapters/..%2f..%2fadmin",
    "/content/api/v4/chapters/%252e%252e/%252e%252e/admin",
    "/content/api/v4/chapters%5c..%5cadmin",
    "/content/api/v4/chapters\\..\\admin",
    "/content/api/v4//evil.example/chapters",
    "/content/api/v4/verses/https://evil.example/x",
    "/content/api/v4/verses/http%3A%2F%2Fevil.example",
    "/content/api/v4/chapters?next=https://evil.example",
    "/content/api/v4/chapters/%00",
    "/content/api/v4/chapters/%zz",
  ];
  for (const p of raw) {
    const res = await call(p, { raw: true });
    assert.equal(res.status, 404, `raw ${p}`);
    await assertClean(res);
    // Same attempt through a real Request (which normalizes the URL).
    const res2 = await call(p);
    assert.equal(res2.status, 404, `request ${p}`);
  }
  assert.equal(qf.contentCalls, 0);
  assert.equal(qf.tokenCalls, 0);
});

test("app key: missing or wrong returns 401, right key passes", async () => {
  const env = baseEnv({ APP_KEY });
  let res = await call("/content/api/v4/chapters", { env });
  assert.equal(res.status, 401);
  await assertClean(res);
  res = await call("/content/api/v4/chapters", { env, headers: { "x-app-key": "wrong" } });
  assert.equal(res.status, 401);
  res = await call("/content/api/v4/chapters", { env, headers: { "x-app-key": `${APP_KEY}x` } });
  assert.equal(res.status, 401);
  res = await call("/content/api/v4/chapters", { env, headers: { "x-app-key": APP_KEY } });
  assert.equal(res.status, 200);
  assert.equal(qf.contentCalls, 1);
  // Health stays open for monitoring.
  res = await call("/health", { env });
  assert.equal(res.status, 200);
});

test("token is fetched once for many concurrent requests", async () => {
  qf.tokenDelayMs = 50;
  const results = await Promise.all(
    Array.from({ length: 25 }, (_, i) => call(`/content/api/v4/verses/by_chapter/${(i % 114) + 1}`))
  );
  for (const res of results) {
    assert.equal(res.status, 200);
    await assertClean(res);
  }
  assert.equal(qf.tokenCalls, 1);
  assert.equal(qf.contentCalls, 25);
});

test("token is reused until fewer than 60 seconds remain", async () => {
  let now = 1_000_000;
  __test.setNow(() => now);
  qf.expiresIn = 300; // 5 minutes
  await call("/content/api/v4/chapters/1");
  assert.equal(qf.tokenCalls, 1);
  now += 200_000; // 100 s left
  await call("/content/api/v4/chapters/2");
  assert.equal(qf.tokenCalls, 1);
  now += 41_000; // 59 s left: refresh
  await call("/content/api/v4/chapters/3");
  assert.equal(qf.tokenCalls, 2);
  assert.equal(qf.lastContent.headers["x-auth-token"], TOKEN_B);
  await call("/content/api/v4/chapters/4");
  assert.equal(qf.tokenCalls, 2);
});

test("upstream 401 triggers exactly one token refresh and one retry", async () => {
  qf.contentStatus = (token) => (token === TOKEN_A ? 401 : 200);
  const res = await call("/content/api/v4/verses/by_key/1:1");
  assert.equal(res.status, 200);
  await assertClean(res);
  assert.equal(qf.tokenCalls, 2);
  assert.equal(qf.contentCalls, 2);
});

test("persistent 401 does not loop: one retry then pass through", async () => {
  qf.contentStatus = () => 401;
  const res = await call("/content/api/v4/verses/by_key/1:1");
  assert.equal(res.status, 401);
  await assertClean(res);
  assert.equal(qf.tokenCalls, 2);
  assert.equal(qf.contentCalls, 2);
  assert.equal(res.headers.get("cache-control"), "no-store");
});

test("concurrent 401s share one refresh", async () => {
  qf.contentStatus = (token) => (token === TOKEN_A ? 401 : 200);
  const results = await Promise.all(Array.from({ length: 10 }, () => call("/content/api/v4/quran/verses/uthmani")));
  for (const res of results) assert.equal(res.status, 200);
  assert.equal(qf.tokenCalls, 2);
});

test("upstream 500 is passed through", async () => {
  qf.contentStatus = () => 500;
  const res = await call("/content/api/v4/chapters");
  assert.equal(res.status, 500);
  assert.equal(res.headers.get("cache-control"), "no-store");
  assert.deepEqual(JSON.parse(await assertClean(res)), { error: "status 500" });
  assert.equal(qf.tokenCalls, 1);
});

test("token endpoint failure gives a clean 502", async () => {
  const stub = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const url = typeof input === "string" ? input : input.url;
    if (url.endsWith("/oauth2/token")) {
      return new Response(`invalid_client for ${CLIENT_ID}`, { status: 401 });
    }
    return stub(input, init);
  };
  const logs = [];
  const origError = console.error;
  console.error = (...a) => logs.push(a.join(" "));
  try {
    const res = await call("/content/api/v4/chapters");
    assert.equal(res.status, 502);
    await assertClean(res);
  } finally {
    console.error = origError;
  }
  for (const line of logs) for (const s of SENSITIVE) assert.ok(!line.includes(s), "log leaked");
});

test("missing secrets give 500 without calling QF", async () => {
  const res = await call("/content/api/v4/chapters", { env: { QF_ENV: "prelive" } });
  assert.equal(res.status, 500);
  assert.equal(qf.tokenCalls + qf.contentCalls, 0);
});

test("non-cached endpoints carry Cache-Control: no-store; metadata gets 1 hour", async () => {
  const noStore = [
    "/content/api/v4/resources/sync?since=1",
    "/content/api/v4/resources/snapshots/x/manifest",
    "/content/api/v4/verses/by_chapter/1",
    "/content/api/v4/quran/verses/uthmani",
    "/content/api/v4/quran/translations/20?chapter_number=1",
    "/content/api/v4/recitations/7/by_chapter/1",
    "/content/api/v4/chapter_recitations/7",
    "/content/api/v4/audio/reciters",
  ];
  for (const p of noStore) {
    const res = await call(p);
    assert.equal(res.headers.get("cache-control"), "no-store", p);
  }
  for (const p of ["/content/api/v4/chapters", "/content/api/v4/resources/translations", "/content/api/v4/resources/languages"]) {
    const res = await call(p);
    assert.equal(res.headers.get("cache-control"), "public, max-age=3600", p);
  }
  // Error responses on cacheable paths are not cached.
  qf.contentStatus = () => 500;
  const res = await call("/content/api/v4/chapters");
  assert.equal(res.headers.get("cache-control"), "no-store");
  // Relay-generated errors are no-store too.
  assert.equal((await call("/content/api/v4/nope")).headers.get("cache-control"), "no-store");
});

test("edge cache is used for metadata when caches.default exists", async () => {
  const store = new Map();
  globalThis.caches = {
    default: {
      async match(req) {
        const hit = store.get(req.url);
        return hit ? hit.clone() : undefined;
      },
      async put(req, res) {
        store.set(req.url, res);
      },
    },
  };
  try {
    const env = baseEnv({ APP_KEY });
    const headers = { "x-app-key": APP_KEY };
    await call("/content/api/v4/chapters?language=en", { env, headers });
    await call("/content/api/v4/chapters?language=en", { env, headers });
    assert.equal(qf.contentCalls, 1);
    await call("/content/api/v4/verses/by_chapter/1", { env, headers });
    await call("/content/api/v4/verses/by_chapter/1", { env, headers });
    await call("/content/api/v4/resources/sync", { env, headers });
    assert.equal(qf.contentCalls, 4);
    assert.deepEqual([...store.keys()], ["https://relay.example/content/api/v4/chapters?language=en"]);
    // Cache still sits behind the app key.
    assert.equal((await call("/content/api/v4/chapters?language=en", { env })).status, 401);
  } finally {
    delete globalThis.caches;
  }
});

test("rate limiter binding returns 429 when over the limit", async () => {
  const seenKeys = [];
  const env = baseEnv({
    RATE_LIMITER: {
      async limit({ key }) {
        seenKeys.push(key);
        return { success: seenKeys.length <= 2 };
      },
    },
  });
  const headers = { "cf-connecting-ip": "203.0.113.9" };
  assert.equal((await call("/content/api/v4/chapters", { env, headers })).status, 200);
  assert.equal((await call("/content/api/v4/chapters", { env, headers })).status, 200);
  const res = await call("/content/api/v4/chapters", { env, headers });
  assert.equal(res.status, 429);
  assert.ok(!(await res.text()).includes("203.0.113.9"));
  assert.deepEqual(seenKeys, ["203.0.113.9", "203.0.113.9", "203.0.113.9"]);
});
