// Fetches and caches a Quran Foundation access token (client credentials).
// One cache per isolate. Concurrent callers share a single in-flight fetch.
// Error messages never contain the client id, secret or token.

const REFRESH_MARGIN_MS = 60 * 1000; // refresh when fewer than 60 seconds remain

export class TokenError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "TokenError";
    this.status = status; // upstream HTTP status, if any
  }
}

export class TokenManager {
  constructor({ authBase, clientId, clientSecret, fetchImpl, now }) {
    this.authBase = authBase;
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.fetchImpl = fetchImpl || ((...args) => fetch(...args));
    this.now = now || (() => Date.now());
    this.token = null;
    this.expiresAt = 0;
    this.inFlight = null;
  }

  // Returns a valid token, fetching one only when needed.
  async getToken() {
    if (this.token && this.expiresAt - this.now() > REFRESH_MARGIN_MS) {
      return this.token;
    }
    if (!this.inFlight) {
      this.inFlight = this.fetchToken().finally(() => {
        this.inFlight = null;
      });
    }
    return this.inFlight;
  }

  // Clears the cached token, but only if it is the one that failed.
  // This stops many parallel 401s from each forcing their own refresh.
  invalidate(failedToken) {
    if (failedToken === undefined || this.token === failedToken) {
      this.token = null;
      this.expiresAt = 0;
    }
  }

  async fetchToken() {
    const basic = btoa(`${this.clientId}:${this.clientSecret}`);
    let res;
    try {
      res = await this.fetchImpl(`${this.authBase}/oauth2/token`, {
        method: "POST",
        headers: {
          Authorization: `Basic ${basic}`,
          "Content-Type": "application/x-www-form-urlencoded",
          Accept: "application/json",
        },
        body: "grant_type=client_credentials&scope=content",
      });
    } catch {
      throw new TokenError("token endpoint unreachable");
    }
    if (!res.ok) {
      throw new TokenError(`token endpoint returned ${res.status}`, res.status);
    }
    let data;
    try {
      data = await res.json();
    } catch {
      throw new TokenError("token response was not JSON");
    }
    if (!data || typeof data.access_token !== "string" || !data.access_token) {
      throw new TokenError("token response had no access_token");
    }
    const seconds = Number(data.expires_in);
    const lifetimeMs = Number.isFinite(seconds) && seconds > 0 ? seconds * 1000 : 0;
    this.token = data.access_token;
    this.expiresAt = this.now() + lifetimeMs;
    return this.token;
  }
}
