# Five Skies: handoff and working rules

Read this file first in any new session, whichever model you are. Then read `docs/TESTFLIGHT.md` and `relay/README.md` if the task touches them.

## Which model does what

The owner (Reef) switches models himself in the Claude app. Your job is to tell him when to switch.

**Opus does the build work.** Writing Swift, tests, workflows, fixing build and TestFlight failures, screens, wiring, mechanical checks.

**Fable does planning and review.** If you are Opus and the task reaches one of the checkpoints below, STOP, say plainly "This is a Fable checkpoint, please switch to Fable for this step", and say what Fable needs to decide. Do not push through it.

Fable checkpoints:
1. Any change to how Quran text is fetched, stored, parsed, split or displayed (files under `FiveSkies/Quran/`, `FiveSkies/Resources/Quran/`, `tools/fetch_quran_content.py`), and any new religious content source.
2. Reading or deciding on license terms (Quran Foundation, Tanzil, sunnah.com, Darussalam, adhan audio, anything new).
3. Planning a new phase or a large feature (Listen tab and audio, Hadith, duas, stories): Fable writes the plan and file ownership, Opus builds it.
4. Review before the first TestFlight build that goes to anyone other than Reef.
5. Review before App Store submission.
6. Anything hard to undo: ownership or entity questions, the name, registering domains or trademarks, making the repo public or private, spending money.
7. A build problem Opus has failed to fix twice.

If you are Fable and the remaining work is plain building, say "This is build work, switch to Opus" once the plan is written down here.

## Rules that must never be broken

- No Arabic literals and no typed scripture anywhere in code or tests. Quran text comes only from the files CI fetched from tanzil.net, stored verbatim. Never edit files in `FiveSkies/Resources/Quran/`.
- No religious text is typed from memory or generated. Every text has a named, licensed source and is shown exactly as published, with credit.
- Quran Foundation content never goes in this repository and is never bundled at build time. Offline copies only through Content Sync, refreshed at least every 7 days.
- Reef handles every key, password and secret himself. Never ask him to paste one into chat. For steps that need one, give him a double-click helper in `C:\Users\sheri\ClaudeWork\FiveSkies` that asks only for that one thing.
- Ask and wait for a clear yes before sending a message, posting, submitting a form, buying, deleting, or changing account settings. One yes covers one action.
- Anything free at launch stays free. Tips only, no ads.
- Writing style for anything Reef reads: bottom line first, plain words, short, no em dashes.

## How the build loop works (no Mac)

- Native SwiftUI, iOS 17+, XcodeGen (`project.yml`), bundle id `app.fiveskies.ios`, widget `app.fiveskies.ios.widgets`, App Group `group.app.fiveskies.ios`.
- Push to `main` runs `.github/workflows/ios.yml` on a cloud Mac: build, unit tests, UI tests. Screenshots are force-pushed to the `ci-screenshots` branch. Fetch that branch and look at the images before reporting anything as done.
- Add `[skip ci]` to commits that change no code.
- Parallel workers: strict file ownership per worker, workers do not run git, one commit and one push per round.
- The ten files shared with the widget target (listed in `project.yml`) must not gain UIKit or app-only references.
- TestFlight: manual workflow `.github/workflows/testflight.yml`, uses Xcode 26, needs four repository secrets that Reef adds.

## State on Nov 26, 2026

Done and passing on CI: Today (five skies), prayer times (adhan-swift), Qibla, alerts, Quran reader (Tanzil text, Amiri Quran font), search, bookmarks, tracker, Tasbih, Zakat, Hijri calendar, Ramadan, themes and wallpapers, share cards, mosques and halal (Apple Maps), memorize, widgets, tip jar, translations feature (built against the relay, tested only with fake data), relay (Cloudflare Worker, not deployed), TestFlight setup (never run), app icon.

Waiting on Reef:
- App contact email is fiveskiesapp@gmail.com (set Nov 27, 2026).
- Apple steps in `docs/TESTFLIGHT.md`, then run the TestFlight workflow.
- Sign up at dev-console.quran.foundation and community.islamic.network.
- Run `2_Deploy_Relay.bat` once Quran Foundation credentials exist.

Waiting on others: Darussalam reply (duas and prophet stories license, emailed Nov 26); sunnah.com API request posted Nov 27 as issue #4540 on sunnah-com/api. Not yet posted: Islamic Network adhan permission post (needs Reef to sign up on the forum). Apple: App Group, both App IDs and the App Store Connect record "Five Skies" exist (team M9443JJCHM); APPLE_TEAM_ID secret is set; the other three secrets wait on Reef creating the API key.

Next build work (Opus): add `FSRelayBaseURL` and `FSRelayAppKey` to the app's Info.plist via `project.yml` once the relay is up; fix the first TestFlight failures; Listen tab once credentials exist.

Not verified: Arabic rendering by a qualified reader (gate before launch); everything on a real device; translations against the live API; the name "Five Skies" (trademark, domain, App Store).

Blocked content with no acceptable source yet: prophet stories, Makkah and Madinah adhan recordings.

## Update Nov 27, 2026 (morning)

- Relay is live at https://five-skies-relay.sherif-d13.workers.dev (Cloudflare account of Steady Path, prelive Quran Foundation credentials). Real calls work. New QF apps use granular scopes (content.quran.read and so on), not "content"; the relay handles this.
- Prelive offers only 14 translations; the only English one is M.A.S. Abdel Haleem (id 85). The Clear Quran (131) and Saheeh International (20) are not in prelive. Production access needs Quran Foundation review. Choosing the default translation is a Fable checkpoint.
- Content Sync shape confirmed live: RESOURCE_CREATE mutation with snapshot_url `/api/v4/resources/snapshots/translations/<id>`.
- The app reads the relay address and key from build settings FS_RELAY_BASE_URL and FS_RELAY_APP_KEY (TestFlight workflow passes them; secret FS_RELAY_APP_KEY).
- All GitHub secrets are set. First TestFlight run (45987281910) failed at archive: "Your team has no devices". Fix in progress: register Reef's iPhone under Devices, then rerun. Compile under Xcode 26 is still unproven.
- Posted: sunnah.com issue #4540; Islamic Network adhan request https://community.islamic.network/d/365 (account fiveskies). Darussalam email sent Nov 26. All three await replies.
- QF scopes include content.hadith.read, so QF may be a second hadith source. Not checked.
