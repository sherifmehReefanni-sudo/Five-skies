# Phase B plan: Listen, translations, production access (Fable, Nov 27, 2026)

Read HANDOFF.md first. This is the plan Opus builds from. Anything marked FABLE is a checkpoint.

## What the Quran Foundation terms say (and how sure we are)

Source: Quran Foundation Developer Terms, "Last updated 2026-11-19", https://api-docs.quran.foundation/legal/developer-terms/ and the docs FAQ. Fable saw these through search excerpts only; the page fetch was not approved in this session. Treat every line as UNVERIFIED until someone reads the full page. FABLE: read the full terms before the production request is sent.

1. Text, translations, timings: an offline copy is allowed only through Content Sync, and it must sync at least every 7 days when online. The app already works this way.
2. Audio recording files: credit Quran Foundation and the reciter, keep downloaded files no longer than 1 week, do not rehost. Content Sync covers the audio URLs and timings, not the files. So a permanent offline audio library is NOT allowed by default.
3. Longer storage is possible only where QF has expressly permitted it. Their own app offers offline downloads, so it is worth asking.
4. A backend may serve devices; that alone is not redistribution. Our relay stores nothing, so it is fine.
5. A public repository that contains QF content counts as redistribution. We keep none in the repo (HANDOFF rule). Keep it that way.
6. Tips and donations are allowed.
7. The privacy policy must name the app and say it uses the Quran Foundation APIs (Developer Privacy Policy requirements).
8. Production access: request the scopes in Developer Console; a person at QF reviews it.

## Decisions (Fable)

D1. Audio is stream first. "Save for offline" keeps a surah for 7 days, shows the days left, then removes the file. Label it honestly: "Saved for 7 days". No permanent downloads unless QF says yes in writing.
D2. In the production request, ask QF for permission to keep downloaded recitations longer than a week on the user's own device. If they say yes, D1 gets a longer limit; nothing else changes.
D3. Audio files play straight from the QF hosts that the API returns. Never through the relay, never copied to our own storage.
D4. Reciters: the list comes from the API at run time (`resources/chapter_reciters`). No reciter names typed in code. "Follow along" is offered only for reciters whose files come with timings.
D5. Default translation: The Clear Quran by Mustafa Khattab (id 131) if production offers it, else Saheeh International (id 20), else Abdel Haleem (id 85). UNVERIFIED that 131 and 20 are in production; prelive has only 85. Store the order as one constant; the app picks the first one the API lists and the user can change it at any time. Show the translator's name under the text.
D6. Transliteration is a Content Sync resource like a translation. Show it as its own toggle, not as a "translation".
D7. Surah background: fetch chapter info when the user opens it. Do not store it.
D8. Quran text on screen stays the Tanzil text. Highlighting a word while audio plays changes display only. FABLE reviews that one diff (checkpoint 1).
D9. Credit line on every player and saved item: reciter name as the API gives it, plus "Quran Foundation".

## Before the production request (Opus, then Reef)

P1. Rewrite `docs/privacy.html`. It is already wrong for the current build: it says the app contacts no server and that location goes to no one, but translations load through the relay and "Mosques nearby" sends the location to Apple Maps. It must say: uses Quran Foundation APIs through our relay on Cloudflare (IP address visible to both, nothing logged); Apple Maps receives your location only when you open Mosques and halal; iCloud backup if turned on; tips through Apple. Match the wording in `project.yml` (NSLocationWhenInUseUsageDescription) and `OnboardingGate.locationReason`. Depends on Reef's city name answer (HANDOFF).
P2. Add a "Sources and credits" page in the app listing Tanzil, Quran Foundation and each translator.
P3. Reef submits the production request in Developer Console (his account, his click). Draft text:

> Five Skies is a free iPhone app for prayer times, Qibla and Quran reading. No ads, no account, no tracking; optional tips only. We ask for production access to: content.quran.read, translations, chapter info, recitations and audio. Calls go through our own relay, which stores no content. Offline copies of translations and timings use Content Sync and sync at least every 7 days. Audio is streamed from your hosts with credit to the reciter and Quran Foundation, and saved files are removed after 7 days. One request: may users keep downloaded recitations on their own device for longer than a week, as in your Quran Audio app? Privacy policy: [link]. Contact: fiveskiesapp@gmail.com.

Opus: fill in the exact scope names from Developer Console before Reef sends it.

## Build rounds and file ownership (Opus)

New folder `FiveSkies/Listen/`. One builder per row, no builder touches another row's files, builders do not run git.

Round B1: streaming player (can be built and tested on prelive now)
| Builder | Owns | Job |
| --- | --- | --- |
| 1 | `FiveSkies/Listen/Audio/` | AVPlayer engine: play, pause, seek, speed, loop surah, loop ayah range, sleep timer, lock screen controls, interruptions |
| 2 | `FiveSkies/Listen/Catalog/` | Reciter list and chapter audio lookups through RelayClient; models; fake data for tests |
| 3 | `FiveSkies/Listen/UI/` | Listen tab, reciter picker, now playing bar, credit line (D9) |
| 4 | `relay/` | Add `resources/chapter_reciters` to ALLOWED_PREFIXES and the 1 hour metadata cache; tests |
| Lead | `project.yml`, tab wiring, `FiveSkiesTests/Listen*` merge | Background audio mode, ATS check for the QF audio hosts |

Round B2: follow along and 7 day save
| Builder | Owns | Job |
| --- | --- | --- |
| 5 | `FiveSkies/Listen/Timing/` | Timings through Content Sync (`chapter_recitations`), current ayah and word from playback time |
| 6 | `FiveSkies/Listen/Saved/` | Save a surah for 7 days, expiry sweep on launch, storage used, delete all (D1) |
| Lead | reader highlight hook under `FiveSkies/Quran/` | FABLE reviews before merge (D8) |

Round B3: transliteration toggle (D6), memorize with play this ayah, surah background (D7), privacy page and credits (P1, P2).

After B1 passes CI: one TestFlight build to Reef. Tests use fake data only; no scripture typed in tests.

## Open questions

- Which reciters have timings in production, and how many. Check once production credentials exist.
- Whether QF allows longer audio storage (D2).
- Rate limits for production; the relay must honour 429 Retry-After. Opus: check `relay/src/index.js` passes Retry-After through.
