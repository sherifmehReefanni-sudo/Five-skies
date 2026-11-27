// Five Skies relay: lets the app read Quran Foundation (QF) content
// without the app ever holding QF's client secret.
// The relay stores no Quran content; only small metadata lists are edge cached.

import { TokenManager, TokenError } from "./token.js";

const ENVIRONMENTS = {
  prelive: {
    authBase: "https://prelive-oauth2.quran.foundation",
    apiBase: "https://apis-prelive.quran.foundation",
  },
  production: {
    authBase: "https://oauth2.quran.foundation",
    apiBase: "https://apis.quran.foundation",
  },
};

const CONTENT_PREFIX = "/content/api/v4/";

// Paths (after /content/api/v4/) the app may call.
// An entry ending in "/" needs something after it. Other entries match
// the exact path or anything below it.
export const ALLOWED_PREFIXES = [
  "chapters",
  "resources/translations",
  "resources/tafsirs",
  "resources/recitations",
  "resources/languages",
  "resources/sync",
  "resources/snapshots",
  "verses/",
  "quran/",
  "chapter_recitations/",
  "recitations/",
  "audio/",
];

// Metadata endpoints that may be edge cached for 1 hour. Nothing else is cached.
// Sync, snapshots and all verse content are never cached here.
const CACHEABLE_PATTERNS = [
  /^chapters$/,
  /^chapters\/\d{1,3}$/,
  /^chapters\/\d{1,3}\/info$/,
  /^resources\/(translations|tafsirs|recitations|languages)$/,
  /^resources\/(translations|tafsirs|recitations)\/\d+\/info$/,
];
const CACHE_SECONDS = 3600;

// One token manager per isolate, rebuilt only if the config changes.
let tokenManager = null;
let tokenManagerKey = "";
let clock = () => Date.now();

function getTokenManager(env, config) {
  const key = `${config.name}|${env.QF_CLIENT_ID}|${env.QF_CLIENT_SECRET}`;
  if (!tokenManager || tokenManagerKey !== key) {
    tokenManager = new TokenManager({
      authBase: config.authBase,
      clientId: env.QF_CLIENT_ID,
      clientSecret: env.QF_CLIENT_SECRET,
      now: () => clock(),
      scopes: typeof env.QF_SCOPES === "string" && env.QF_SCOPES.trim() ? env.QF_SCOPES.trim().split(/\s+/) : undefined,
    });
    tokenManagerKey = key;
  }
  return tokenManager;
}

// Test hooks only. Not reachable over HTTP.
export const __test = {
  reset() {
    tokenManager = null;
    tokenManagerKey = "";
    clock = () => Date.now();
  },
  setNow(fn) {
    clock = fn;
  },
};

function resolveEnv(env) {
  const name = env.QF_ENV === "production" ? "production" : "prelive";
  return { name, ...ENVIRONMENTS[name] };
}

function json(status, body, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...extraHeaders,
    },
  });
}

// Constant-time string compare (time does not depend on where they differ).
function safeEqual(a, b) {
  const enc = new TextEncoder();
  const x = enc.encode(String(a));
  const y = enc.encode(String(b));
  const len = Math.max(x.length, y.length);
  let diff = x.length ^ y.length;
  for (let i = 0; i < len; i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}

// Returns the sub path after /content/api/v4/ or null if the request is unsafe.
function safeSubPath(rawUrl, pathname) {
  // Absolute URL or scheme smuggled into the path or query.
  const afterOrigin = rawUrl.replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]*/i, "");
  if (/[a-z][a-z0-9+.-]*:\/\//i.test(afterOrigin)) return null;

  // Decode a few times to catch double encoding like %252e%252e.
  let decoded = afterOrigin;
  for (let i = 0; i < 3; i++) {
    let next;
    try {
      next = decodeURIComponent(decoded);
    } catch {
      return null;
    }
    if (next === decoded) break;
    decoded = next;
  }
  const decodedPath = decoded.split("?")[0];
  if (decodedPath.includes("..")) return null;
  if (decodedPath.includes("\\")) return null;
  if (decodedPath.includes("//")) return null;
  if (/[\u0000-\u001f\u007f]/.test(decoded)) return null;

  if (!pathname.startsWith(CONTENT_PREFIX)) return null;
  const sub = pathname.slice(CONTENT_PREFIX.length);
  // Only plain path characters in the part we forward. Colon is allowed
  // for verse keys such as verses/by_key/2:255 (schemes were rejected above).
  if (!/^[A-Za-z0-9_\-.:/]+$/.test(sub)) return null;
  return sub;
}

function isAllowed(sub) {
  const path = sub.replace(/\/+$/, "");
  return ALLOWED_PREFIXES.some((p) =>
    p.endsWith("/")
      ? path.startsWith(p) && path.length > p.length
      : path === p || path.startsWith(`${p}/`)
  );
}

function isCacheable(sub) {
  const path = sub.replace(/\/+$/, "");
  return CACHEABLE_PATTERNS.some((re) => re.test(path));
}

function getCache() {
  return typeof caches !== "undefined" && caches && caches.default ? caches.default : null;
}

// Calls QF content API once with the given token.
function callUpstream(method, upstreamUrl, token, clientId) {
  return fetch(upstreamUrl, {
    method,
    headers: {
      "x-auth-token": token,
      "x-client-id": clientId,
      Accept: "application/json",
    },
  });
}

// Build the response for the app. Only the status, body and content type
// come from upstream. No upstream headers (cookies etc.) are copied.
function relayResponse(upstream, method, cacheControl) {
  const headers = {
    "Cache-Control": cacheControl,
    "X-Content-Type-Options": "nosniff",
  };
  const type = upstream.headers.get("content-type");
  if (type) headers["Content-Type"] = type;
  const body = method === "HEAD" ? null : upstream.body;
  return new Response(body, { status: upstream.status, headers });
}

async function proxyContent(request, env, ctx, url, sub, config) {
  if (!env.QF_CLIENT_ID || !env.QF_CLIENT_SECRET) {
    console.error("relay not configured: missing QF secrets");
    return json(500, { error: "relay_not_configured" });
  }

  const method = request.method;
  const cacheable = method === "GET" && isCacheable(sub);
  const cache = cacheable ? getCache() : null;
  // Cache key is the relay URL only, so the app key header never becomes part of it.
  const cacheKey = cache ? new Request(`${url.origin}${url.pathname}${url.search}`, { method: "GET" }) : null;

  if (cache) {
    const hit = await cache.match(cacheKey);
    if (hit) return hit;
  }

  const upstreamUrl = `${config.apiBase}${CONTENT_PREFIX}${sub}${url.search}`;
  if (new URL(upstreamUrl).origin !== new URL(config.apiBase).origin) {
    return json(404, { error: "not_found" });
  }

  const tokens = getTokenManager(env, config);
  let upstream;
  try {
    let token = await tokens.getToken();
    upstream = await callUpstream(method, upstreamUrl, token, env.QF_CLIENT_ID);
    if (upstream.status === 401) {
      // Clear, fetch a new token once, retry once. Never loop.
      tokens.invalidate(token);
      token = await tokens.getToken();
      upstream = await callUpstream(method, upstreamUrl, token, env.QF_CLIENT_ID);
    }
  } catch (err) {
    if (err instanceof TokenError) {
      console.error(`QF token error: ${err.message}`);
      return json(502, { error: "upstream_auth_failed" });
    }
    console.error("QF content request failed");
    return json(502, { error: "upstream_unreachable" });
  }

  if (cacheable && upstream.status === 200) {
    const response = relayResponse(upstream, method, `public, max-age=${CACHE_SECONDS}`);
    if (cache) {
      const put = cache.put(cacheKey, response.clone()).catch(() => {});
      if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(put);
      else await put;
    }
    return response;
  }
  return relayResponse(upstream, method, "no-store");
}

export default {
  async fetch(request, env = {}, ctx) {
    let url;
    try {
      url = new URL(request.url);
    } catch {
      return json(400, { error: "bad_request" });
    }

    // Per-IP rate limit (Workers Rate Limiting binding). The IP is used only
    // as the counter key and is never logged or stored by the relay.
    if (env.RATE_LIMITER && typeof env.RATE_LIMITER.limit === "function") {
      const ip = request.headers.get("cf-connecting-ip") || "unknown";
      const { success } = await env.RATE_LIMITER.limit({ key: ip });
      if (!success) return json(429, { error: "rate_limited" });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return json(405, { error: "method_not_allowed" }, { Allow: "GET, HEAD" });
    }

    const config = resolveEnv(env);

    if (url.pathname === "/health") {
      return json(200, { ok: true, environment: config.name });
    }

    // Speed bump only: anything shipped in an app can be extracted.
    if (env.APP_KEY) {
      const given = request.headers.get("x-app-key") || "";
      if (!safeEqual(given, env.APP_KEY)) {
        return json(401, { error: "unauthorized" });
      }
    }

    const sub = safeSubPath(request.url, url.pathname);
    if (sub === null || !isAllowed(sub)) {
      return json(404, { error: "not_found" });
    }

    return proxyContent(request, env, ctx, url, sub, config);
  },
};
