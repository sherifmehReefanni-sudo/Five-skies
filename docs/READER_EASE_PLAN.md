# Reader ease of use: plan for the next rounds (Fable, Nov 27, 2026, 21:10 ET)

Read HANDOFF.md first. This plans the list under "Reef's ask (Nov 27, 19:49 ET)". It comes BEFORE the Learn tab, because Learn is built on the same pieces. It replaces the round order in docs/LEARN_LISTEN_PLAN.md section 7 (sections 1 to 6 of that file still stand).

## What is actually wrong

The reader has the features; it hides them. Three causes, and the fix for each:
1. Tapping an ayah opens a system menu of seven text buttons. Fix: one toolbar (E1.1).
2. Sound and meaning are set with separate switches in separate places. Fix: three presets and one Reading sheet (E1.3, E2.1).
3. It is not obvious how to start listening or where you are. Fix: a Play button on the surah header, a bar that takes you to the playing ayah, a next surah button (E1.2).

Rule for every item: one tap to the common action, at most one sheet deep, and no new switch unless one is removed.

## Round E1: the reader itself (no new content, build now)

E1.1 Ayah toolbar (U1). Tap an ayah: a bar slides up with icons and short labels: Play from here, Bookmark, Words, Share, More (copy, share as image, mark as last read). Remove the confirmation dialog (replace, do not layer). Tafsir gets a slot later (E3).
E1.2 Finding your way. (a) A Play button on the surah header card. (b) Tapping the now playing bar opens the reader at the playing ayah (U4). (c) "Next surah" and "Previous surah" at the end and top of a surah. (d) Go to: one field that accepts "2:255", a surah number or name, "page 50", "juz 30" (U6, first half). Pages and juz come from the Tanzil metadata already bundled.
E1.3 One Reading sheet behind the "Aa" button (U5): Arabic size, translation on/off and which, transliteration on/off, background (Sky or Plain dark). Every reading switch that lives elsewhere moves here. No sepia: it needs a second colour set for the whole reader and has not earned it.
E1.4 Continue card on Today (U7): ONE card, "Continue: Al-Baqara, ayah 45", for whichever of reading or listening was last. Not two cards; Today is already full.
E1.5 Meaning shown by default: once a translation has been downloaded, it shows under each ayah without the user finding a switch.

FABLE checkpoint 1 note: E1 does not change how the Arabic is drawn. `FollowAlongAyahText` stays as it is.

## Round E2: presets and words (prelive is enough)

E2.1 Presets (U3, U8). Three buttons at the top of the player sheet; each sets the existing play modes in one tap, and "Custom" keeps the detailed controls below.
- Listen: plays through, text follows.
- Understand: meaning and transliteration on, meaning read after each ayah.
- Memorize: repeat each ayah 3 times, then hide the Arabic and wait ("recite after me"), tap to peek, "I know this" marks it known. This is the guided lesson (L1) from the Learn plan. There is one implementation: Learn launches the reader in this preset.
E2.2 Words sheet (U2). From the toolbar's Words button: the ayah's words in order, each row with the word, its transliteration, its meaning and a play button.
- FABLE checkpoint 1 decision: showing one word is allowed only as a slice of the stored string by its W2 range, with nothing trimmed or added. Use the W3 count check; if the ayah does not line up, show meanings from Quran Foundation's own list without our Arabic slices and say "Word view is not available for this ayah".
- Tapping a word inside the running text is NOT in this round. SwiftUI cannot hit-test a word in joined Arabic text without replacing the text drawing, and that drawing is the part we verified. Revisit after production data.
- Word audio: CONFIRMED by Fable's read of the terms (fetched summary) that word recordings fall under the same audio rules: stream from their hosts, credit, no keeping unless the user downloads. Meanings load on demand; nothing stored.
E2.3 Search in the meaning (U6, second half): search the downloaded translation, results jump to the ayah. Searching the Arabic by typing Arabic is later; it needs a marks-free search index, which is a checkpoint 1 item.

## Round E3: Learn tab and reading plan

As in docs/LEARN_LISTEN_PLAN.md sections 4 and 6, slimmed because E2 built the lesson: Start here path (L5), common words (L4), review schedule (L3), Duas from the Quran.
Add C5: a reading plan. "Finish in 30, 60 or 365 days, or my own pace": today's portion by pages from the bundled metadata, a quiet progress ring, and when a day is skipped the plan re-spreads the rest. Nothing says behind or missed.
Tafsir (C2), only if prelive lists one: a Tafsir button in the ayah toolbar that loads that ayah's commentary on demand, shown as plain text with the author's name, nothing stored. Opus: list what `resources/tafsirs` returns in English first. Which tafsir is the default is a FABLE decision once the list is known. Strip any HTML to plain text; never a web view.

## Round E4: New to Islam

docs/LEARN_LISTEN_PLAN.md section 5, N1 to N7, unchanged.

## Decided: not now

- C1 Mushaf page view. Worth doing: people who memorize know the page. But it means showing Quran Foundation's page text and fonts beside our Tanzil text, a second text source. The terms allow caching their fonts and page images with credit. It gets its own plan after E4. Until then E1.2 gives page and juz jumps.
- C3 Tajweed colours. Needs their marked-up text, so it travels with C1. Not before.
- "Read like a book" translation mode: after E4.
- Voice search and mistake detection: still no (plan L6).

## C4: more reciters, and the one thing only Reef can do

More reciters, The Clear Quran and Saheeh International, timings beyond surahs 1 and 2, and review condition 3 ALL wait on Quran Foundation production access. The request has not been sent. The privacy page and the credits page it needs are done. Reef opens Developer Console, requests production for the scopes the app uses, and pastes:

> Five Skies is a free iPhone app for prayer times, Qibla and Quran reading and listening. No ads, no account, no tracking; optional tips only. Calls go through our own relay, which stores no content. Offline copies of translations use Content Sync and sync at least every 7 days. Recitations stream from your hosts with credit to the reciter and Quran Foundation; offline downloads happen only when the user asks, stay in the app's private storage, and follow your offline download conditions. Privacy policy: https://sherifmehreefanni-sudo.github.io/Five-skies/privacy.html. Contact: fiveskiesapp@gmail.com.

Opus: confirm the privacy page address and list the exact scope names for him before he sends it.

## File ownership (Opus)

Round E1
| Builder | Owns | Job |
| --- | --- | --- |
| 1 | `FiveSkies/Quran/Toolbar/` (new) | E1.1 toolbar view and actions |
| 2 | `FiveSkies/Quran/GoTo/` (new), `FiveSkies/Quran/QuranSearch.swift` | E1.2 (d) parser and sheet; unit tests for every accepted form |
| 3 | `FiveSkies/Quran/ReadingSettings/` (new), `FiveSkies/Quran/QuranStyle.swift` | E1.3 sheet, plain dark background |
| 4 | `FiveSkies/Today/ContinueCard.swift` (new) | E1.4 |
| Lead | `FiveSkies/Quran/SurahReaderView.swift`, `QuranTabView.swift`, `FiveSkies/Listen/UI/QuranPlayBar.swift`, `TodayView.swift` | wiring, E1.2 (a) to (c), E1.5, removing the dialog and the moved switches |

Round E2
| Builder | Owns | Job |
| --- | --- | --- |
| 5 | `FiveSkies/Listen/Presets/` (new), `FiveSkies/Listen/UI/ListenPlayModesSection.swift` | E2.1 |
| 6 | `FiveSkies/Quran/Words/` (new) | E2.2 sheet, word lookups through RelayClient, fake data for tests |
| 7 | `FiveSkies/Translations/TranslationSearch.swift` (new) | E2.3 |
| Lead | reader hide and peek for Memorize | FABLE reviews this one diff: hiding must not change the stored text or the drawing path |

One TestFlight build to Reef after each round. Screenshots for every new sheet, looked at before reporting done.

## How we will know it worked

Reef does these on his phone after E1, without being told how: start a surah playing; jump to 2:255; turn the meaning on; bookmark an ayah; get back to where the audio is. If any takes more than two taps or he has to hunt, that item is not done.
