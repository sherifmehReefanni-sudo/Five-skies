# Listen, Learn and new Muslims: plan (Fable, Nov 27, 2026, 16:30 ET)

Read HANDOFF.md first. This plans the section "Reef's Listen and learning request", reviews the dua handoff from Reef's study session, and adds Reef's new goal: the app must be friendly for converts and reverts. Opus builds from this file. FABLE marks a checkpoint.

## 1. Tabs (decision)

Today | Quran | Learn | Qibla | More.

- **Quran** is the reader and the player in one place: the text, the meaning under each ayah, and a play bar. Today's Listen tab folds into it. Reading silently still works with nothing playing.
- **Learn** is new: guided lessons, memorize, common words, the new Muslim path.
- Why not keep a tab called Listen that holds the text: someone who wants to read will not look under "Listen". Same features as Reef asked for, clearer names. Reef can overrule the names; the structure stays.
- Replace, do not layer: `ListenTabView` becomes the reciter and surah browser inside Quran; the Memorize tile in More moves to Learn.

## 2. Follow along (FABLE checkpoint 1 rules)

The Arabic on screen stays the bundled Tanzil text, unchanged. Highlighting is drawing only.

W1. Never build, edit or re-join the ayah string. Highlight by ranges over the string exactly as stored.
W2. Word splitting: split the stored ayah on spaces. A token counts as a word only if it contains at least one Arabic letter. Tokens made only of signs (pause marks, the sajdah sign, the quarter sign) attach to the word before them. Test this with character classes, not with typed Arabic.
W3. Timings come from Quran Foundation (`chapter_recitations` through Content Sync). Their word numbers follow their own text. For each ayah, compare their word count with ours. If the counts differ, that ayah gets an ayah-level highlight only. Never guess a mapping.
W4. Log (in debug builds only) how many of the 6,236 ayahs fall back, per reciter. FABLE looks at that number before the feature ships. If it is more than a few percent, stop and come back.
W5. Basmala: the reader already splits it (`Ayah.splitBasmala`). Timings for ayah 1 may or may not include it; treat a mismatch under W3.
W6. Under each ayah, in this order, each with its own on/off switch: transliteration, translation. Both are Quran Foundation resources through Content Sync and show the name of their source.
W7. Word by word meaning (tap a word): Quran Foundation `word_by_word_translations` through Content Sync, same W3 count check. UNVERIFIED that prelive offers it; check before building.
W8. Reduce Motion: highlight changes without animation. VoiceOver: the highlight is not announced.

## 3. Play modes (decision)

One "When this surah ends" choice, plus repeat controls.

- When the surah ends: stop (default) | play the next surah | repeat this surah (1, 3, 7 times, or until stopped) | play a set (a juz, or surahs from A to B).
- Repeat each ayah 1, 2, 3, 5 or 10 times before moving on. This is the mode people use to memorize.
- Recite after me: after each ayah the player waits for as long as that ayah lasted, then goes on.
- Loop a range of ayahs (the player already has `loopRange`).
- Pause for prayer: playback pauses when a prayer time arrives and offers to resume. On by default. This is ours; no other app ties the player to the prayer times.
- Sleep timer (exists) and resume where I stopped (per surah and reciter).
- Not doing: shuffle. Random order does not suit the Quran.

## 4. Learn tab

Everything in Learn is built from licensed text and audio. No teaching text about religion is typed by a model and shipped unreviewed.

L1. Guided lesson (the "instructor") for one ayah at a time: listen, follow word by word, see the meaning, repeat it N times, hide the text and recall, mark as known. The steps are app labels only ("Listen", "Now try without the text").
L2. Hear a word: tap a word to hear it alone. UNVERIFIED: Quran Foundation word audio is on a public file server; check that the terms cover it like other audio (stream, no keeping past 7 days).
L3. Review: known ayahs come back after 1, 3, 7, 14, 30 days. No streak pressure, no red.
L4. Common words. Do not ship anyone's "400 words" claim. Compute it: count exact word forms in the bundled Tanzil text on the device (W2 splitting), sort by count, and show "these N words are X percent of all words in the Quran" from our own arithmetic. Meaning for each word comes from L1's word-by-word source, shown with one example ayah. Limit: this counts written forms, not roots. Grouping by root needs a morphology data set, which is a license decision for later (FABLE checkpoint 2).
L5. Start here path (see section 5): Al-Fatihah, then the last three surahs, then the other short ones at the end. Order is by ayah key in a small manifest, no text.
L6. Not now: grading the user's own recitation, tajweed rule lessons. Both need a teacher's content or speech recognition we cannot vouch for.

## 5. New Muslims (converts and reverts)

Position: someone who took the shahada last week can open the app and not feel lost or judged. UI wording: "New to Islam".

Ships with licensed or calculated content only:
N1. First run: one optional switch, "I am new to Islam or new to prayer". No other questions. It can be changed in Settings.
N2. With it on: transliteration on by default; prayer names carry a plain label ("Fajr, the dawn prayer"); Learn opens on the Start here path; Goals offers a small first goal ("One prayer a day").
N3. Tap to explain: every term the app itself uses (Fajr, Qibla, wudu, rakah, surah, ayah, juz, Hijri, dhikr and so on) opens a one or two line plain meaning. These lines are ours; add them to docs/SCHOLAR_REVIEW.md before outside testers.
N4. Rakah count on each prayer row of the day view: the obligatory count only (2, 4, 4, 3, 4). Sunnah prayers are left out because schools count them differently. On the scholar sheet.
N5. Settings in plain words: the calculation method and Asr choice say "If you are not sure, keep this and ask your mosque". Show how Fajr and Isha move between methods so a user can match their mosque.
N6. Private mode: alerts say only "Reminder" with no prayer name, for people who have not told family or coworkers. Off by default.
N7. Tone check on every screen: no assumed knowledge, no Arabic term without the plain label the first time, nothing that says "missed".

Blocked until a text source exists (Phase C, each a FABLE checkpoint):
N8. How to pray and how to make wudu, step by step. The words said in prayer other than Quran come from hadith, so they need the sunnah.com key or the Darussalam license, and the steps need a scholar's review. Fable can draft the non-scripture step text for that review; it does not ship before it.
N9. Shahada and "what now" guide. Same gate.

## 6. Review of the dua handoff (files in Reef's `ClaudeWork\FiveSkies` folder, not in this repo)

Verdict: good research, and its rules are adopted. The JSON file must NOT be committed or loaded as it is. It breaks three HANDOFF rules: typed Arabic, model-written translations of Quran and hadith, and a public repo.

| Part | Decision |
| --- | --- |
| Quran duas (1, 3, 5, 8, 14) | Ship now as "Duas from the Quran": a manifest of verse keys, titles and categories only. Arabic from the bundled Tanzil text, English from the user's chosen translation. Always whole ayahs (3:173 shows the full ayah). |
| Hadith duas (2, 4, 6, 7, 10, 12, 13) | Wait for the sunnah.com key. Arabic and English then come from their published text by hadith number, with the grading they give. The handoff's own English is a model translation and does not ship. |
| Personal duas (9, 11) | Dropped from the app. They are Arabic supplications composed by a model. Fine for Reef's own use, not for a public app. |
| Backgrounds | Kept as drafts outside the repo. They mix tafsir reports and gradings, so each needs a scholar's read. Candidates for the Learn tab later. |
| "CONFIRMED by a verifier agent" | Downgraded to UNVERIFIED. A model checking a model is not a qualified reader. For the Quran items the check becomes mechanical (verse key lookup), so it no longer matters. |
| Duas 12 to 14 review | Not done as a text review; 14 is covered by the verse key route and 12 and 13 by the sunnah.com route. |
| Content rules (source badge, whole verses, weak narrations labelled, no "say this for 7 nights" promises, tafsir labelled as tafsir) | Adopted as rules for all dua and hadith screens. |
| Read aloud | English computer voice for English text only. No computer voice for any Arabic, Quran or dua. |
| Tahajjud wake flow | Good niche, keep. The night alarm exists; the guided steps need Bukhari 1154 from sunnah.com, so it waits on the key. |
| Myth check, Jumu'ah notes | Later, written by hand, scholar read first. No AI checking of transcripts. |
| Adhan research | Already met: adhan-swift, on-device times, no trackers. New from it: N5 (match your mosque) and a manual city choice if the app lacks one (Opus: check). |

## 7. Build rounds and file ownership (Opus)

Round C1: Quran and Listen merge, play modes (prelive, no new sources)
| Builder | Owns | Job |
| --- | --- | --- |
| 1 | `FiveSkies/Listen/Audio/` | Play modes in section 3, queue, resume position |
| 2 | `FiveSkies/Listen/UI/`, `FiveSkies/Quran/QuranTabView.swift` | Reader with play bar, reciter and surah browser inside Quran, mode picker |
| 3 | `FiveSkies/Listen/Timing/` | Timings through Content Sync, W2 splitter, W3 count check, W4 report |
| 4 | `FiveSkies/Prayer/` hook only | "Pause for prayer" signal to the player |
| Lead | `FiveSkiesApp.swift`, `project.yml`, `FiveSkies/Quran/SurahReaderView.swift` highlight hook | FABLE reviews the highlight hook and the W4 number before TestFlight |

Round C2: Learn tab
| Builder | Owns | Job |
| --- | --- | --- |
| 5 | `FiveSkies/Learn/Lesson/` | L1 guided lesson, L3 review schedule (move `FiveSkies/Memorize/` here) |
| 6 | `FiveSkies/Learn/Words/` | L4 counts from the bundled text, W7 meanings |
| 7 | `FiveSkies/Learn/Path/`, `FiveSkies/Learn/QuranDuas/` | L5 path manifest, Duas from the Quran manifest (keys only) |
| Lead | tab wiring, More tile removal | |

Round C3: New to Islam (N1 to N7)
| Builder | Owns | Job |
| --- | --- | --- |
| 8 | `FiveSkies/Onboarding/`, `FiveSkies/Settings/` | N1, N2, N5 |
| 9 | `FiveSkies/Glossary/` | N3 terms and the tap-to-explain view |
| 10 | `FiveSkies/Notifications/`, `FiveSkies/DayView/` | N6 private mode, N4 rakah counts |

One TestFlight build to Reef after each round. Tests use fake data and character classes; no scripture typed in tests.

## 8. Open questions

- Does prelive offer word-by-word translation, transliteration and timings for more than one reciter? (Opus, first hour of C1.)
- Terms for word audio files (L2). FABLE reads the full Quran Foundation terms page; still not read in full.
- Who is the scholar. Sections 4, 5 and 6 all queue behind one reviewer. This is now the tightest bottleneck in the project.
