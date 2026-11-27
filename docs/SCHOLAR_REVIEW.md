# Five Skies: questions for a scholar (written by Fable, Nov 27, 2026)

Purpose: one page Reef can hand to an imam or scholar he trusts. Nothing below goes to any tester other than Reef until each line has a yes, a no, or a corrected value. Record the answer, who gave it and the date next to each line.

All values live in `FiveSkies/Prayer/DayDefinitions.swift` and `FiveSkies/DayCards/DayCardRules.swift`.

## A. Times on the day view

1. After sunrise, voluntary prayer is shown as discouraged for 15 minutes. Is 15 right, or should it be 20, or something else?
2. Before Dhuhr (sun at its height), the discouraged time is shown as the 5 minutes before Dhuhr. Is 5 right, or should it be 10?
3. Before Maghrib (sun setting), the discouraged time is shown as the last 15 minutes. Is 15 right?
4. Duha is shown from the end of window 1 to the start of window 2. Correct?
5. The app shows only these three clock windows. It does not show "after praying Fajr until sunrise" and "after praying Asr until sunset", because they depend on when the person prayed. Should the screen mention them in a line of text?
6. The screen says: "These times are about voluntary prayers. If you have not prayed today's Asr, pray it before Maghrib." Is that wording acceptable?
7. Isha: the app lets the user choose "Middle of the night" (default) or "Fajr" as the end. The note says: "Schools differ. Many hold that the preferred time for Isha ends at the middle of the night and that it can still be prayed until Fajr." Is the default right, and is the note acceptable?
8. Middle of the night and the last third are counted from Maghrib to the next Fajr (the adhan-swift library does this). Correct, or should the night end at sunrise?
9. The other windows: Fajr ends at sunrise, Dhuhr at Asr, Asr at Maghrib, Maghrib at Isha. Any objection to showing these as the windows?
10. The heading on the screen is "Discouraged for voluntary prayer". Is "discouraged" the right word, or should it say "not allowed"?

## B. Day cards on Today

11. Fasting notes ("Some choose to fast today") show on Mondays, Thursdays and the 13th to 15th of the month. They are hidden in Ramadan, on 1 and 2 Shawwal, and on 9 to 14 Dhul Hijjah. Days 2 Shawwal, 9 and 14 Dhul Hijjah are hidden only because the calculated date can be a day off from the local sighting. Is anything missing (for example the last day of Sha'ban)?
12. Is "Some choose to fast today" acceptable wording, with no hadith quoted?
13. Eid and Arafah cards follow the Umm al-Qura calendar plus the user's own adjustment, and say "Calculated date. Your community may differ." Acceptable?
14. The Arafah card does not mention fasting. Should it?
15. "The last ten days" shows from day 21 of Ramadan. Correct?

## Status

No answers yet. Default numbers (15, 5, 15) were chosen by the builder as common practice; Fable did not change them because it has no cited source for a better number. They are UNVERIFIED.
