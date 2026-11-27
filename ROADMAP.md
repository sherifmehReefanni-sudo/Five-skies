# Five Skies roadmap (written by Fable, Nov 27, 2026)

Source: Reef's screenshots of three apps he uses (Deen, Pillars, Tahajjud+) and his goal: include what they offer, and stand out.
Read HANDOFF.md first. Its rules apply to everything here.

## Position

Calm like Pillars, complete like Deen, alive at night like Tahajjud+, and unlike all three: free with no paywall or ads, no account, and every religious text shown with its source.

Design rule: borrow features, never layouts, icons or wording. Pillars already has a sun-path curve with prayer dots on its main screen, so do not build that. Our identity is the five painted skies with skyline and motion, carried through the whole app.

Tone rule: encouragement, never shame. No red "missed" totals, no counting days before the user started, no leaderboards.

## Phase A0: transitions and visual polish (Opus, first)

Reef asked for creative screen transitions (his example: a star crossing the sky) and a sharper, more elite look.

- One signature moment, used sparingly: a shooting star that crosses the sky. Use it when the app opens, when the prayer period changes, and when a prayer is marked done. Do NOT play it on every tab change; a flourish seen fifty times a day becomes an annoyance.
- Tab and screen changes: a quick sky cross-fade or gentle parallax of the skyline, under 0.35 seconds, never blocking touches.
- Everything goes through MotionPolicy: off with Reduce Motion, off in fixed-phase screenshot mode unless -FSAnimate.
- Polish pass: consistent spacing and type scale, richer sky gradients and star fields, soft glow on the sun and moon, glass cards with consistent corner radius and contrast, haptics on key taps, and check text contrast on all five skies.
- Known rough spots: widget gallery large widget is cut off in its screenshot; the Qibla tab has no "Locating" state; the Listen tab still says "Coming soon".
- Send Reef before and after contact sheets, then one TestFlight build.

## Phase A: build now (Opus). Calculation and on-device only, no licenses needed

A1. Day view
- Each prayer shows its window (start to end), plus sunrise.
- Extra times: Duha, the discouraged windows, midnight, last third of the night.
- Use adhan-swift (including its SunnahTimes for middle and last third of the night). No hand-written astronomy.
- Day navigation (previous, next, back to today), Hijri date with a user adjustment of minus 2 to plus 2 days, city name, Suhur and Iftar.
- FABLE CHECKPOINT before release: the definitions used for the discouraged windows, when Duha starts, and when Isha ends differ between schools. Build them as named settings with the offsets in one file, label the screen "common practice, check with your local mosque", and do not ship to anyone but Reef until a scholar signs off.

A2. Tracker 2
- Counts only from the first day the user tracks. Week strip, 7-day trend, current and longest streak, per-prayer totals, history by month.
- Pause mode (travel, illness, period) that holds the streak without counting days as missed.
- Fasting log. Tracker chips on Today.

A3. Alerts
- Per-prayer choice: off, silent banner, short sound. (Adhan sound waits for a license.)
- Optional reminder before a prayer window ends.
- Night alarm: wake time set relative to the last third of the night or to Fajr, with an offset. Use AlarmKit where the iOS version has it, else a time-sensitive notification. Check Apple docs through Context7 first.

A4. Goals instead of leaderboards
- Personal goals that forgive gaps (for example "40 nights, not in a row, no deadline", "9 Fajrs this month").
- Dhikr: daily total, a goal, simple stats. Phrases shown in English and transliteration only until a sourced Arabic text is licensed (no Arabic literals rule).

A5. Day-aware cards on Today
- Friday, Ramadan, the white days, Mondays and Thursdays. Plain reminders only ("It is Friday"). No hadith text until it has a licensed source.

A6. Settings and trust
- Backup and restore through iCloud key-value storage, no account.
- Feedback and feature-request buttons (mail to fiveskiesapp@gmail.com), a short mission page, a "what's new" sheet.
- Month and year timetable export as PDF.
- Optional first name for a greeting, stored on the device only.

A7. First-run flow
- Four screens at most: welcome, location (with the exact reason), alerts, done. No questionnaires, no sign-in.

A8. Widgets
- Add start and end times, a next-prayer countdown, Lock Screen sizes.

## Phase B: needs the relay (live) and Quran Foundation production access

- Transliteration under each ayah (free; competitors charge for it).
- Listen: reciter choice, speed, loop a surah, loop an ayah, sleep timer, word-by-word highlight, download for offline through the permitted sync route.
- Memorize by surah, juz or ayah, with play-this-ayah and mark-as-memorized.
- Surah background from Quran Foundation chapter info.
- FABLE CHECKPOINT: request production access; choose the default translation (prelive offers only Abdel Haleem in English); read the audio terms before building downloads.

## Phase B2: Listen, Learn and new Muslims (added Nov 27, 2026)

Plan and build rounds are in `docs/LEARN_LISTEN_PLAN.md`: Quran and Listen merge with follow along and play modes, a Learn tab (guided lessons, common words, start here path, duas from the Quran), and a "New to Islam" mode.

## Phase C: waits on license replies (Fable checkpoint for each)

- Duas and adhkar (Darussalam, emailed Nov 26).
- 99 Names and Hadith (sunnah.com issue #4540; Quran Foundation also lists a hadith scope, unchecked).
- Adhan sounds (Islamic Network post d/365).
- Learn section: wudu, how to pray, rakats, night prayer guide. Needs a named source or original text reviewed by a scholar.
- Prophet stories: no source yet.

## Phase D: Apple platform extras, all free

- Apple Watch app and complications, Shortcuts (App Intents), Live Activity countdown.
- "Pray first" app blocking: needs Apple's Family Controls entitlement, apply later.

## Phase E: community, decide later (Fable checkpoint)

Full community (dua wall with free text, discussions, stories, partners) means accounts, a backend, an age gate, report and block tools, and someone reviewing reports every day. Not for launch.
A light version worth considering: users tap one of a fixed, reviewed set of short duas and others tap Ameen; plus an opt-in anonymous count of people who prayed today. No free text, no accounts, no personal data.

## Not doing

Leaderboards for worship, paywalls, ads or cross-promotion, long onboarding funnels, red missed-prayer totals, user testimonials used as marketing, hadith used as marketing copy.

## Order of work

1. Done: Reef installed build 0.1.0 (2) and likes it. Still ask him to check prayer times, Qibla, an alert and a translation download.
1b. Phase A0.
2. Phase A in two rounds: A1, A2, A3 then A4 to A8. One TestFlight build after each round.
3. Phase B once production access is requested.
