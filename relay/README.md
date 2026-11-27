# Five Skies relay

A small Cloudflare Worker that sits between the Five Skies app and the Quran Foundation (QF) Content API.

## What it is for

QF gives us a client id and a client secret. The secret must never ship inside the app, because anything inside an app can be pulled out. So the app calls this relay instead. The relay holds the secret, gets a short-lived access token from QF, adds it to each request, and passes QF's answer back to the app.

The app calls the relay with the same paths it would use on QF:

```
GET https://<your-relay>/content/api/v4/chapters?language=en
GET https://<your-relay>/content/api/v4/verses/by_key/2:255
GET https://<your-relay>/health
```

Content Sync answers contain relative paths that start with `/api/v4/...`. The app should put `/content` in front of them before calling the relay (for example `/api/v4/resources/snapshots/...` becomes `/content/api/v4/resources/snapshots/...`).

## What it allows

- Only `GET` and `HEAD`. Anything else gets 405.
- Only paths under `/content/api/v4/` that start with one of these (the `ALLOWED_PREFIXES` list in `src/index.js`): `chapters`, `resources/translations`, `resources/tafsirs`, `resources/recitations`, `resources/languages`, `resources/sync`, `resources/snapshots`, `verses/`, `quran/`, `chapter_recitations/`, `recitations/`, `audio/`. Everything else gets 404.
- Paths with `..`, backslashes, double slashes, encoded tricks or full URLs inside them get 404.
- The app's cookies and authorization headers are never sent to QF. QF's cookies are never sent back to the app.

## What it does not store

- No Quran content. Verses, translations text, tafsir text, audio, Content Sync and snapshot answers all pass straight through with `Cache-Control: no-store`. QF's terms limit stored content to one week and ask for Content Sync for offline copies, so offline copies are the app's job, done through Content Sync.
- No personal data. It writes no logs about users and never logs IP addresses. The visitor's IP is used only as the counter key for Cloudflare's rate limiter.
- Small metadata lists (`chapters`, `resources/translations`, `resources/tafsirs`, `resources/recitations`, `resources/languages`, plus their `/info` pages) may be kept in Cloudflare's edge cache for 1 hour to save calls. Only successful answers are cached.
- The QF access token lives only in the Worker's memory and is renewed when less than 60 seconds remain. It is never put in any response, header or log line.

## The three secrets

| Name | What it is | Required |
| --- | --- | --- |
| `QF_CLIENT_ID` | Your QF client id | Yes |
| `QF_CLIENT_SECRET` | Your QF client secret | Yes |
| `APP_KEY` | A random string the app sends in the `x-app-key` header | Optional, recommended |

No secret values are kept in this folder. If `APP_KEY` is set, any request without the right `x-app-key` gets 401 (except `/health`).

## Deploy

From this folder:

```
npx wrangler deploy
npx wrangler secret put QF_CLIENT_ID
npx wrangler secret put QF_CLIENT_SECRET
npx wrangler secret put APP_KEY
```

Each `secret put` asks you to paste the value. Then open `https://<your-relay>/health`. It should show `{"ok":true,"environment":"prelive"}`.

The rate limit binding needs Wrangler 4.36.0 or later.

## Switch from prelive to production

1. Get production credentials from QF.
2. In `wrangler.toml`, change `QF_ENV = "prelive"` to `QF_ENV = "production"`.
3. Run `npx wrangler secret put QF_CLIENT_ID` and `npx wrangler secret put QF_CLIENT_SECRET` again with the production values.
4. Run `npx wrangler deploy`.
5. Check `/health` shows `"environment":"production"`.

Any value other than `production` means prelive.

## Run the tests

Needs Node 18 or later. No installs needed.

```
npm test
```

(This runs `node --test`, which finds `test/relay.test.mjs`. On Node 22, `node --test test/` with a folder name does not work; use `npm test` or `node --test`.)

## Limits

- `APP_KEY` is only a speed bump. Anyone who unpacks the app can find it. It stops casual misuse, not a determined person.
- The rate limit (120 requests per minute per IP, set in `wrangler.toml`) is counted per Cloudflare location, so it is rough, not exact. Many users behind one shared IP (a school or mobile carrier) share one limit.
- The token cache is per Worker instance. Several instances around the world will each get their own token. That is normal and fine.
- The edge cache only works when the Worker runs on a custom domain. On a plain `workers.dev` address the cache calls may do nothing, which is safe but means no savings.
- The relay forwards QF's status and body as they are. If QF is down, the app sees QF's error (or a 502 from the relay).
- Query strings that contain a full URL (like `?next=https://...`) are refused, to be safe.
