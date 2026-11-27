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
- Nov 27, 06:15 ET: TestFlight run 45988541262 SUCCEEDED after registering Reef's iPhone as a device. Build 0.1.0 (2) uploaded with Xcode 26.3; archive and export both passed. Internal group "Owner" created with automatic distribution; Reef (sherif@steadypathcareers.com) invited. Next: Reef installs via the TestFlight app and reports what he sees on a real phone. To ship another build: Actions > TestFlight > Run workflow.

## Start here in a new chat (added Nov 27, 2026, 07:15 ET)

You are picking this up in a fresh chat with no memory of the earlier one. Read this file fully, then ROADMAP.md. Reef wants Opus to build and Fable to plan and review; the checkpoints near the top of this file say when to tell him to switch.

Working facts you will need:
- Repo: `sherifmehReefanni-sudo/Five-skies` (GitHub redirects the old lowercase name). Clone it, work on `main`, push with `git -c push.negotiate=true push origin main`. The repo is still PUBLIC; Reef wants it private later and must flip that himself (settings writes are blocked for us).
- Simulator build and tests run on every push (about 10 minutes, sometimes a queue). Watch with `gh run watch`, then `git fetch origin ci-screenshots` and LOOK at the screenshots before saying anything is done. Add `[skip ci]` for doc-only commits.
- TestFlight: `gh workflow run testflight.yml -R sherifmehReefanni-sudo/Five-skies --ref main`. It takes about 12 minutes, uploads the build, and Reef gets it automatically through the internal group "Owner". Build numbers come from the run number. The last good run was 45988541262 (build 0.1.0 (2)).
- You cannot read or set GitHub secrets or repo settings through the API here. All needed secrets already exist: APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64, FS_RELAY_APP_KEY.
- Relay: https://five-skies-relay.sherif-d13.workers.dev (health at /health). Source in `relay/`. To redeploy, Reef double-clicks `2_Deploy_Relay.bat` in `C:\Users\sheri\ClaudeWork\FiveSkies` on his PC and answers N to the credentials question. Keep the copy of `relay/src` in that folder in step with the repo before asking him to run it.
- Parallel workers: give each one strict file ownership, tell them not to run git, have each `touch /tmp/<name>.done` as its last action, then do one commit and one push yourself.
- Reef reads on his phone. Keep replies short, bottom line first, plain words, no em dashes. He handles keys and passwords himself. Ask before sending, posting, buying, deleting or changing account settings.

Reef's feedback after installing build 0.1.0 (2) on his iPhone (Nov 27):
- "Looks really well" and "operates really well". He likes every idea in ROADMAP.md.
- He wants creative screen transitions, for example a star crossing the sky when moving between screens.
- He wants the look and graphics sharpened further so it feels elite.

Checked by Reef on his iPhone (Nov 27, 07:15 ET):
- CONFIRMED: prayer times match his mosque and Pillars.
- CONFIRMED: Qibla points the same way as Pillars.
- CONFIRMED: a text downloaded through the relay and showed under the verses. He called it the transliteration, so it may have been the "Transliteration" entry and not Abdel Haleem. Either way the relay and Content Sync work from inside the app.
- UNVERIFIED: alerts. He said "I believe" one fired. Ask him to set one a few minutes ahead and confirm.

First tasks for Opus, in order:
1. Phase A0 in ROADMAP.md (transitions and visual polish).
2. Phase A rounds as listed there, one TestFlight build after each round.

Repo visibility (decided by Reef, Nov 27): stay PUBLIC for now because builds are free. Flip to private before outside testers or any public mention of the app; he does that himself in Settings. Until then, keep anything he would not want read out of the repo: no secrets, no personal details, no device IDs.

## Phase A0 status (Nov 27, 2026, Opus)

Done and passing CI (runs 45999376982 and 46001723719, commits 3f143f7 and f4eb5c5):
- Signature shooting star on Today (`FiveSkies/App/SignatureStar.swift`): plays on app open (and on return after 15+ minutes away), on prayer period change, and when a prayer is marked done. 8 second cooldown, never on tab changes, off with Reduce Motion and in fixed-phase screenshots. `-FSStarFrame <0..1>` freezes it for screenshots. It draws between the sky and the text.
- Tab arrival (`FiveSkies/App/TabArrival.swift`): 0.3 s fade and settle when a tab returns. No blur on purpose (cost on long lists).
- Sky: star dust, tinted stars with bloom and glints, faint galaxy band on deep night skies, bloom behind sun and moon, faint moon surface. `SkyLegibilityScrim` darkens the top of the Dhuhr and Asr skies on Today and Qibla only (white small text now about 6:1 or better), not wallpapers or share images.
- Glass: lit top edges on Today tiles and every `moreGlass` card, card shadow on the background only, star dust on More skies. Haptics: success on marking a prayer, light tap on the settings button.
- Rough spots fixed: Qibla "Finding your location" state (4 s, same as Today; `-FSQiblaLocating`), Listen preview screen (no scripture or reciter names), `widgets-large` screenshot, tracker legend says "Not marked".
- Nothing under `FiveSkies/Quran/` was touched (Fable checkpoint 1).

Not verified: the live star timing on a real phone (CI cannot time it; the frozen frames show the look). The star's middle passes behind the small "Now:" line; judge on device, the arc is `SignatureStarDrawing.point`.
TestFlight: Reef said yes at 08:13 ET; run 46005215756 succeeded, build 0.1.0 (3) uploaded with Phase A0. Next: Reef checks the star, tab fades and Qibla on his phone; then Phase A round 1 (A1, A2, A3).

## Phase A round 1 status (Nov 27, 2026, afternoon, Opus)

Passing CI (run 46035693325, commit c51d08b; CI now also compiles with Xcode 26 in job compile-xcode-26, so AlarmKit code is checked on every push).
- A1 Day view: `FiveSkies/DayView/`, opened by tapping the date on Today (`openDayView`). Extra times come from `DaySchedule` in `FiveSkies/Prayer/DayDefinitions.swift` (all school offsets live there). Settings `ishaEnd` and `hijriAdjustment` are on the day view itself.
- A2 Tracker 2: `FiveSkies/Tracker/` plus the rewritten `TrackerView.swift`. Pauses in UserDefaults "tracker.pauses". Choices made: a fully marked day inside a pause still counts; days before the first tracked day can be filled in from the week strip. `TrackerChipsView` sits above the Today tiles.
- A3 Alerts: window-end reminder, 64-notification cap, night alarm (`NightAlarmPlan`, `NightAlarmKit`; AlarmKit on iOS 26, time-sensitive notification otherwise, no entitlement added). `NSAlarmKitUsageDescription` added in project.yml. No Isha end control in Settings (it is on the day view).

Waiting on Reef:
- City name on the day view: `PlaceNameProvider.lookupsEnabled` is false because Apple's geocoder would receive the coordinate, and docs/privacy.html plus the location prompt say the location is never sent anywhere. If he wants city names, reword both, then flip the flag.
- A yes to run the TestFlight build for this round.
FABLE CHECKPOINT (A1) still open: the discouraged windows, Duha start and Isha end definitions need a scholar's sign-off before any tester other than Reef.
Not verified on a real phone: the night alarm on iOS 26, window-end reminders firing.
Next build work: Phase A round 2 (A4 to A8).

Note (Nov 27): App Store Connect warned on build 4 (ITMS-90725, not a failure): from April 2027 uploads need the iOS 27 SDK (Xcode 27). The TestFlight and compile-xcode-26 jobs now pick the newest Xcode 26 or later on the runner, so they move to Xcode 27 by themselves once GitHub installs it. Check before April 2027 that a run says Xcode 27.

## Phase A round 2 status (Nov 27, 2026, afternoon, Opus with six parallel builders)

Passing CI (run 46039149151, commit 0b67598; day card layout fix in 5910b2f).
- A4 Goals: `FiveSkies/Goals/` (GoalsView, GoalCreatorSheet, GoalProgress, GoalStore, DhikrLogStore). Tasbih shows a daily total, optional goal and a 7-day chart. "Fajr this month" counts days Fajr is marked (no on-time flag exists).
- A5 Day cards: `FiveSkies/DayCards/`, on Today above the tracker chips. FABLE CHECK: the builder hides fasting notes during Ramadan, on 1 Shawwal and on 10 to 13 Dhul Hijjah; Fable should confirm the rule and the wording ("Some choose to fast today").
- A6 Settings and backup: `FiveSkies/Trust/` (More tile "Settings and backup"). Greeting line on Today (name stays on device), backup to iCloud key-value storage under "fiveSkies.backup", feedback mail, mission page, what's new sheet at the app root. Restore asks the user to reopen the app.
  iCloud sync: DONE Nov 27, 13:25 ET with Reef's OK. Workflow `enable-icloud.yml` (tools/asc_enable_icloud.py) turned on ICLOUD for app.fiveskies.ios through the App Store Connect API (capabilities now APP_GROUPS, ICLOUD, IN_APP_PURCHASE), and the key-value entitlement is in FiveSkies/WidgetSupport/FiveSkies.entitlements. A signed Release archive in that run carried `com.apple.developer.ubiquity-kvstore-identifier`. Sync itself is not yet tested on a phone.
- A6 Timetable: `FiveSkies/Timetable/` (More tile "Timetable"), month or year, PDF export through the share sheet.
- A7 First run: `FiveSkies/Onboarding/`, gated by "onboarding.completed"; Today waits for it before asking for location. `-FSShowOnboarding` for screenshots.
- A8 Widgets: start and until times, live countdown, new "Today's times" Lock Screen widget. Rows now run Fajr to Fajr (after Isha they show the same day with Isha current).
Next: TestFlight for round 2 needs Reef's yes. Then Phase B planning is a Fable checkpoint (production access, default translation, audio terms).

## For Fable next (Reef is switching models, Nov 27 afternoon)

Phase A is built. TestFlight build 5 (round 2 plus iCloud) is not uploaded: Reef wants Fable to decide after its review whether to ship it.
Fable decisions, in order:
1. Review the school definitions in `FiveSkies/Prayer/DayDefinitions.swift` (after sunrise 15 min, before Dhuhr 5 min, before Maghrib 15 min, Duha between them, Isha ends at middle of night by default, `IshaEndRule`). Decide wording and defaults, and what a scholar must sign off before outside testers.
2. Review the day card rules in `FiveSkies/DayCards/DayCardRules.swift`: fasting notes hidden in Ramadan, 1 Shawwal and 10 to 13 Dhul Hijjah; wording "Some choose to fast today", "Some fast on days 13, 14 and 15"; Arafah and Eid by Umm al-Qura date with the user's adjustment.
3. City name on the day view (`PlaceNameProvider.lookupsEnabled` is false): needs a privacy wording decision with Reef.
4. Plan Phase B (ROADMAP): Quran Foundation production access, default translation, audio terms, Listen tab file ownership for Opus.
Open replies: Darussalam (no reply as of Nov 27 12:30), sunnah.com issue #4540 and Islamic Network d/365 (not checked this session; GitHub blocks that repo here and the forum fetch needs approval).

## Fable review (Nov 27, 2026, 14:00 ET)

Decisions on the "For Fable next" list:
1. School definitions: numbers left as they are (15, 5, 15, middle of night). Fable has no cited source for better numbers, so they stay UNVERIFIED. Added two notes on the day view (`DayDefinitions.discouragedNote`, `ishaEndNote`). The sign-off sheet is `docs/SCHOLAR_REVIEW.md`: 15 questions Reef takes to a scholar. Gate unchanged: no tester other than Reef until it is answered.
2. Day cards: two fixes made. (a) Fasting notes are now also hidden on 2 Shawwal and on 9 and 14 Dhul Hijjah, because the calculated date can be a day off and a fasting note must never land on a local Eid. (b) The white day card no longer says "days 13, 14 and 15" (13 Dhul Hijjah is a no-fasting day); it says "Some choose to fast today". Eid and Arafah cards now say "Calculated date. Your community may differ."
3. City name: waiting on Reef. Finding: the privacy page and the location prompt are already inaccurate, because "Mosques nearby" sends the location to Apple Maps and translations load through the relay. The wording must change before any outside tester whatever he picks. Options put to him: offline city list (Fable's pick), Apple's geocoder, or leave it off.
4. Phase B plan: `docs/PHASE_B_PLAN.md`. Key point: QF terms cap saved audio files at 1 week, so "download for offline" is a 7-day save unless QF grants more. Terms were seen through search excerpts only; reading the full page is still open.
Build 5: fine to ship to Reef only, once CI passes on this commit and he says yes.
Not done: sunnah.com #4540 and Islamic Network d/365 were not checked (page fetches need Reef's approval and timed out). Darussalam not checked.
Next: this is build work, switch to Opus for round B1 in `docs/PHASE_B_PLAN.md` and P1 once Reef answers the city name question.

## City name decision (Reef, Nov 27, 2026, 14:14 ET)

Reef chose the offline city list. Build work for Opus:
- Bundle a small city list (name, country code, latitude, longitude) and show the nearest city on the day view. No network call. Remove the CLGeocoder path from `FiveSkies/Location/PlaceNameProvider.swift` and the `lookupsEnabled` flag (replace, do not layer).
- Source: GeoNames "cities15000" (about 33,000 places). Fable's recollection is that GeoNames data is CC BY 4.0, which needs a credit line. UNVERIFIED: read the license on geonames.org before bundling, then add the credit to the "Sources and credits" page (P2 in docs/PHASE_B_PLAN.md). Fetch the file in CI with a script under `tools/`, like the Quran text; keep only the four fields.
- If the nearest city is far away (say over 50 km), show "Your location" instead of a wrong name.
- The location prompt and onboarding line can then stay true for prayer times. The privacy page still needs the P1 rewrite (Apple Maps for Mosques and halal, the relay, iCloud backup).
Reef also said yes to TestFlight build 5 (round 2, iCloud, Fable review fixes).

## Opus session, Nov 27 afternoon: city list, privacy page, round B1

Done and passing CI (run 46058474074, commit ef6023b; bar backing fix 04ba96b):
- Offline city names: `tools/fetch_cities.py` + `.github/workflows/fetch-cities.yml` fetched GeoNames cities15000 (CONFIRMED CC BY 4.0 on geonames.org/about.html) into `FiveSkies/Resources/Cities/` (34,247 rows, Latin names only, SOURCE.txt with license and changes). `CityIndex` finds the nearest city within 50 km, else "Your location". Geocoder and `lookupsEnabled` removed. GeoNames credit added to SourcesView.
- P1 privacy page rewritten and live (`docs/privacy.html`): Quran Foundation APIs named, relay on Cloudflare (no request logging, per-IP rate counting for one minute), recitations stream from QF audio servers, Apple Maps only for mosque and halal search, optional iCloud backup, feedback by mail, tips through Apple. Location prompt (project.yml) and `OnboardingGate.locationReason` now say "never sent to us. Apple Maps sees it only when you search for mosques or halal food."
- Round B1 (`FiveSkies/Listen/`): Audio (ListenPlayer, AVPlayerEngine, SimulatedEngine, lock screen, interruptions), Catalog (RelayListenCatalog with 1 hour memory cache, FakeListenCatalog), UI (ListenTabView, reciter picker, now playing bar, player sheet, credit line). Shared contracts in `FiveSkies/Listen/ListenModels.swift`. Background audio mode on. `-FSFakeListen` for tests.
- Relay: `resources/chapter_reciters` allowed, reciter and chapter_recitations answers cached 1 hour, Retry-After passed through on 429, relay's own 429 sends Retry-After 60. 23 relay tests pass. NOT DEPLOYED yet: the new `relay/src/index.js` was copied to `C:\Users\sheri\ClaudeWork\FiveSkies\relay\src` (the other relay files there already matched); Reef runs `2_Deploy_Relay.bat` and answers N. The Listen tab cannot load reciters from the live relay until then.
UNVERIFIED: audio host for relative URLs (assumed download.quranicaudio.com); real playback, lock screen controls and interruptions on a device; which reciters prelive lists.
Next: relay deploy, then a TestFlight build for B1 (needs Reef's yes). Then round B2 per docs/PHASE_B_PLAN.md (timings, 7 day save; the reader highlight hook is a Fable checkpoint).
TestFlight run 46064728004 (Reef's yes, 15:35 ET) succeeded: build 0.1.0 (6) with B1, city names and the new location wording.

## Reef's Listen and learning request (Nov 27, 15:51 ET), for Fable to plan

Reef confirmed recitation plays in the Listen tab on build 6. He wants:
1. Listen shows the Quran text while it plays, with the translation and the transliteration under each ayah, and a highlight that moves word by word (follow along).
2. Play modes instead of stopping at the end of each surah: stop at end of surah, continuous play into the next surah, and other options (Fable may suggest more creative ones).
3. Rethink the tabs: the Quran tab (text with meaning underneath) becomes the Memorize and learning section, an education piece with a guided "instructor" walk-through, audio for enunciation, and help learning faster, for example the most frequent words of the Quran (Reef recalls about 400 words; UNVERIFIED). Listen keeps the text for following along.
Fable checkpoints this touches: 1 (Quran text display and word splitting, highlight hook), 2 (source and license for word-by-word translation, transliteration and any frequent-word list or teaching content), 3 (plan and file ownership for a large feature, tab restructure).
Reef's choice (15:53 ET): fold item 2 (play modes) into Fable's plan too, then hand the plan back to Opus to build. Opus's suggested modes: stop at end of surah, continue to next surah, repeat a surah 1, 3, 7 times or always, play a range of surahs. The player already has `loopsSurah`, `loopRange` and `sleepsAtEndOfSurah` in `FiveSkies/Listen/Audio/ListenPlayer.swift`.

## Fable plan for Listen, Learn and new Muslims (Nov 27, 2026, 16:30 ET)

Plan: `docs/LEARN_LISTEN_PLAN.md`. Read it before building. Short version:
- Tabs become Today, Quran (reader plus player), Learn, Qibla, More. Listen folds into Quran.
- Follow along rules W1 to W8 are Fable checkpoint 1 rules: text never altered, word splitting by character class, and any ayah whose word count differs from the timings falls back to ayah-level highlight. Fable reviews the highlight hook and the fallback count before TestFlight.
- Play modes decided (section 3), including "Pause for prayer".
- New goal from Reef: friendly for converts and reverts. Section 5 (N1 to N7 can be built now; how-to-pray guides wait on a text source and a scholar).
- Dua handoff from Reef's study session (files `FIVE_SKIES_HANDOFF_Duas_Adhan_2026-11-27.md` and `five_skies_duas_2026-11-27.json` in his `ClaudeWork\FiveSkies` folder): reviewed in section 6. Do NOT commit or load the JSON. Only the five Quran duas ship now, by verse key. Hadith duas wait for sunnah.com. The two model-composed duas are dropped.
Next: this is build work, switch to Opus for round C1. Round B2 in docs/PHASE_B_PLAN.md is replaced by C1 (timings) and the 7 day save moves to after C1.

## Round C1 status (Nov 27, evening, Opus)

Passing CI (run for commit 9d7d171). Built: Listen folded into the Quran tab (reciter row, play buttons `quranPlay-N`, play bar in list and reader, player sheet with play modes), ListenPlayer play modes (PlayModes saved under "listen.playModes", queue resolver, ayah repeat, recite after me, loop ayahs, pause for prayer, resume spots under "listen.resume", timing aware currentAyah and currentWord), `PrayerArrivalMonitor` wired at the app root. Tabs: Today, Quran, Qibla, More.
Choices made by the builder, for Fable to confirm: "Repeat this surah 1 time" means play it twice; recite after me waits for the ayah's length at normal speed.
Not built yet: Timing builder (W2 splitter, W3 count check, W4 report) and the lead's highlight hook in SurahReaderView. They wait on `5_Probe_Prelive.bat` (in Reef's ClaudeWork\FiveSkies folder) to show which timings, word meanings and transliteration prelive offers. Without timings, the timing options are greyed out with a note.
No TestFlight for C1 yet: Fable reviews the highlight hook and the W4 fallback number first.

## Round C1 follow along: ready for FABLE review (Nov 27, 18:05 ET)

Passing CI (commit e03a174). Built: `FiveSkies/Listen/Timing/` (RelayTimingProvider, memory only, last 10 surahs; AyahWordSplitter W2; TimingAlignment W3; FollowAlongDebugReport W4) and the lead's hook in `FiveSkies/Quran/SurahReaderView.swift` (`FollowAlongAyahText`, `FollowAlongTimingsWatcher`). Diff to review: `git show e03a174 -- FiveSkies/Quran/SurahReaderView.swift`.
How the hook draws: the stored string (`SurahFollowAlong.text(forAyah:)`, equal to `Ayah.displayText`) becomes an AttributedString; the playing word's range gets a gold foreground colour; an ayah that lines up only at ayah level gets a faint gold card behind it. No string is built or joined, no animation, nothing announced to VoiceOver.
Deviation from the plan, for Fable to accept or reject: timings are fetched from `chapter_recitations/{id}/{chapter}?segments=true` when a surah plays and kept in memory only, not through Content Sync. Content Sync `chapter_recitations:{id}` does answer (RESOURCE_CREATE), so it can be used for the 7 day save later.

Prelive facts (probe through the relay, Nov 27 17:31 ET, CONFIRMED by counts): 4 reciters (ids 6, 7, 12, 173); every reciter has ayah and word timings, but only for surahs 1 and 2 (the other 112 answer 404 in prelive). Translations: 14, English only Abdel Haleem (85); Transliteration is translation id 57. Word by word through `verses/by_chapter` gives meaning for all words, transliteration and word audio for the 29 non-marker words of surah 1. Content Sync group `transliterations` does not exist (422); `word_by_word_translations:1` answers with nothing.

W4 number (computed: QF timed word positions per ayah from the relay, numbers only, vs our W2 split of the bundled Tanzil text in Python, same rules as the Swift splitter; both give 77,433 words for the whole text):
- reciter 6: 3 of 293 ayahs fall back (1.0%)
- reciter 7: 6 of 293 (2.0%)
- reciter 12: 2 of 293 (0.7%)
- reciter 173: 1 of 293 (0.3%)
Every fallback is in surah 2 (2:145, 2:181, 2:200, 2:212, 2:213, 2:214, 2:245, 2:249, 2:282); in each the timings name fewer words than our text has. Only surahs 1 and 2 could be checked in prelive, so the whole-Quran number waits for production access.
TestFlight for C1 waits on Fable's review of the hook and this number, per the plan.

## Fable review of round C1 follow along (Nov 27, 2026, 18:25 ET)

Verdict: the hook and the timing code are ACCEPTED. Reviewed `AyahWordSplitter`, `TimingAlignment` and the `SurahReaderView` diff in e03a174.
What passed: the stored string is never rebuilt (AttributedString from the same string, plain init, no markdown); colour runs begin and end at spaces, so no letter joins are cut; sign-only tokens ride with the word before; word level only when their word numbers are exactly 1 to our count; no typed Arabic in code or tests; no animation.
Deviation (timings from the regular endpoint, memory only): ACCEPTED. A memory-only copy is not an offline copy. Condition 2 below.
W4 number (0.3% to 2.0%, surahs 1 and 2 only): ACCEPTED for builds that go to Reef. Every fallback is "timings name fewer words", which is missing data on their side, and the fallback handles it.

Conditions, in order:
1. Before the C1 TestFlight build (Opus, one CI round): a UI test screenshot of the reader with one word highlighted, frozen (fake timings are numbers only; text is the bundled surah 1), plus the same ayah not highlighted. No screenshot shows the highlight today (`quran-playing.png` is the surah list), so how the gold word renders is UNVERIFIED. Compare the two: glyph shapes and positions must be the same, only the colour may differ. If shapes move, stop and come back to Fable.
2. Timing cache: drop an entry after 24 hours and never write timings to disk from this path. Saved-for-offline surahs get their timings through Content Sync (see the correction in docs/PHASE_B_PLAN.md).
3. Before any outside tester: (a) the W4 number for all 114 surahs per reciter, from production; (b) a stronger probe than counts: for each ayah compare, word by word, the letter count of Quran Foundation's word with ours (numbers only, nothing stored). Equal counts can hide two differences that cancel out; this catches it. Any ayah that fails goes on a fixed ayah-level list.
Optional: `FollowAlongAyahText` rebuilds every visible ayah on each player update; if scrolling stutters on a phone, observe only `currentAyah` and `currentWord`.

Good news from reading the Quran Foundation terms page: offline audio downloads with no time limit ARE allowed under five conditions. docs/PHASE_B_PLAN.md is corrected (new D1, D2 dropped).
Next: build work, switch to Opus: condition 1, then TestFlight (needs Reef's yes), then round C2 (Learn tab).
