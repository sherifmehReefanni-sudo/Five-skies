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

## C. Duas from the Quran (Learn tab, added Nov 28, 2026)

Each row shows the whole ayah from the bundled text and the meaning from the user's chosen translation. Only the title below is ours.

16. 28:24, title "For provision". Acceptable as a dua for provision?
17. 3:173, title "Relying on Allah". Acceptable?
18. 2:201, title "Good in this life and the next". Acceptable?
19. 25:74, title "For spouse and children". Acceptable?
20. 17:24, title "For parents". Acceptable?

## D. Words used in the app (tap to explain, added Nov 28, 2026)

Each line is our own plain meaning, shown when a word is tapped. Is each one accurate and neutral?

21. Fajr: The dawn prayer, the first of the five daily prayers. Its time runs from first light until sunrise.
22. Sunrise: When the sun comes up. It ends the time for Fajr and is not a prayer of its own.
23. Dhuhr: The midday prayer, the second of the five daily prayers. Its time begins just after the sun passes its highest point.
24. Asr: The afternoon prayer, the third of the five daily prayers. Schools differ on when it begins, so the app lets you choose.
25. Maghrib: The sunset prayer, the fourth of the five daily prayers. Its time begins when the sun has set.
26. Isha: The night prayer, the last of the five daily prayers. Its time begins when the last light of evening has gone.
27. Jumu'ah: The Friday prayer, held together at a mosque around midday, with a short talk before it.
28. Qibla: The direction of the Kaaba in Makkah, which Muslims face when they pray.
29. Makkah: The city in Saudi Arabia where the Kaaba stands, the place Muslims face in prayer.
30. Adhan: The call to prayer, made when the time for a prayer begins.
31. Wudu: The washing before prayer, of set parts of the body such as the hands, face, arms and feet.
32. Rakah: One unit of prayer, which includes standing, bowing and prostrating. Each prayer has a set number of units.
33. Sunnah: Here, the voluntary prayers offered before or after some of the five daily prayers, following the example of the Prophet Muhammad.
34. Surah: A chapter of the Quran. The Quran has 114 surahs.
35. Ayah: A verse of the Quran. Each surah is made of ayahs.
36. Juz: One of 30 parts of about equal length that the Quran is divided into. Many people use them to plan their reading.
37. Page: A page of the printed Quran, called the mushaf. The app uses the common 604 page layout.
38. Basmala: The opening line read at the start of most surahs, beginning in the name of God.
39. Tafsir: Explanation of the meaning of the Quran, written by scholars.
40. Transliteration: Arabic sounds written in Latin letters, to help you read along before you know Arabic script.
41. Reciter: The person whose recorded reading of the Quran you hear.
42. Hijri: The Islamic calendar, which follows the moon. Its dates move about 11 days earlier each year against the usual calendar and are marked AH.
43. Ramadan: The ninth month of the Hijri calendar. Muslims fast during it, from dawn until sunset.
44. Suhur: The meal eaten before dawn on a day of fasting.
45. Iftar: The meal that breaks the fast at sunset.
46. Taraweeh: Voluntary night prayers in Ramadan, often prayed together at a mosque after Isha.
47. Eid: One of two yearly festivals: Eid al-Fitr when Ramadan ends, and Eid al-Adha during the days of the pilgrimage.
48. Day of Arafah: The day before Eid al-Adha, when pilgrims gather on the plain of Arafah near Makkah.
49. Dhikr: Remembering God with short words of praise, often repeated.
50. Adhkar: The plural of dhikr. Often used for the set words said in the morning, in the evening and after prayer.
51. Tasbih: Praising God with short words, often counted on beads or fingers. The Tasbih tool keeps the count for you.
52. Dua: A personal prayer to God, asking for something, in your own words or in words passed down.
53. Hadith: A report of what the Prophet Muhammad said or did, passed down through named narrators.
54. Zakat: A yearly charity, usually 2.5% of savings above a set amount, given to people in need.
55. Nisab: The set amount of wealth above which zakat is due. It is measured against the value of gold or silver.
56. Halal: Allowed in Islam. Halal food is food that meets Islamic dietary rules.
57. Tahajjud: A voluntary prayer at night, after waking from sleep and before Fajr.
58. Duha: The mid-morning, after the sun has fully risen and before Dhuhr, and the voluntary prayer offered then.
59. Middle of the night: The halfway point between Maghrib and the next Fajr.
60. Last third of the night: The last third of the time between Maghrib and the next Fajr. A time many choose for night prayer.

## E. Rakah counts on the day view

61. Each prayer row shows the obligatory count only: Fajr 2, Dhuhr 4, Asr 4, Maghrib 3, Isha 4. Sunnah prayers are left out because schools count them differently. Friday shows Dhuhr as 4 with no Jumu'ah note. Correct, and should Friday say something?

## F. New to Islam wording

62. First run switch: "I am new to Islam or new to prayer", with "We will explain terms and keep things simple. You can change this in Settings." Acceptable?
63. Prayer names show a plain label when that switch is on: Fajr, the dawn prayer; Dhuhr, the midday prayer; Asr, the afternoon prayer; Maghrib, the sunset prayer; Isha, the night prayer. Acceptable?
64. Calculation method and Asr choice say: "If you are not sure, keep this and ask your mosque." The Match your mosque screen says: "Methods differ mostly in when Fajr and Isha begin. Find the row whose times match your mosque's timetable, then tap it." Acceptable?
65. Goals offers "One prayer a day" as a small first goal ("Counts days you mark any prayer. No deadline, any days you like."). Acceptable as a starting goal for someone new?
