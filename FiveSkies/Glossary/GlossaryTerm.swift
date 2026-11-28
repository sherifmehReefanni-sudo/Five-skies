import Foundation

/// Every religious or Quran word the app shows, with a short plain meaning (plan N3).
/// The meanings are our own lines and go to the scholar sheet before outside testers.
enum GlossaryTerm: String, CaseIterable, Identifiable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha
    case jumuah
    case qibla
    case makkah
    case adhan
    case wudu
    case rakah
    case sunnah
    case surah
    case ayah
    case juz
    case page
    case basmala
    case tafsir
    case transliteration
    case reciter
    case hijri
    case ramadan
    case suhur
    case iftar
    case taraweeh
    case eid
    case arafah
    case dhikr
    case adhkar
    case tasbih
    case dua
    case hadith
    case zakat
    case nisab
    case halal
    case tahajjud
    case duha
    case middleOfNight
    case lastThird

    var id: String { rawValue }

    /// The word as the app spells it, in Latin letters.
    var title: String {
        switch self {
        case .fajr: return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        case .jumuah: return "Jumu'ah"
        case .qibla: return "Qibla"
        case .makkah: return "Makkah"
        case .adhan: return "Adhan"
        case .wudu: return "Wudu"
        case .rakah: return "Rakah"
        case .sunnah: return "Sunnah"
        case .surah: return "Surah"
        case .ayah: return "Ayah"
        case .juz: return "Juz"
        case .page: return "Page"
        case .basmala: return "Basmala"
        case .tafsir: return "Tafsir"
        case .transliteration: return "Transliteration"
        case .reciter: return "Reciter"
        case .hijri: return "Hijri"
        case .ramadan: return "Ramadan"
        case .suhur: return "Suhur"
        case .iftar: return "Iftar"
        case .taraweeh: return "Taraweeh"
        case .eid: return "Eid"
        case .arafah: return "Day of Arafah"
        case .dhikr: return "Dhikr"
        case .adhkar: return "Adhkar"
        case .tasbih: return "Tasbih"
        case .dua: return "Dua"
        case .hadith: return "Hadith"
        case .zakat: return "Zakat"
        case .nisab: return "Nisab"
        case .halal: return "Halal"
        case .tahajjud: return "Tahajjud"
        case .duha: return "Duha"
        case .middleOfNight: return "Middle of the night"
        case .lastThird: return "Last third of the night"
        }
    }

    /// One or two plain lines. Factual and neutral: no rulings and no claims of virtue.
    var meaning: String {
        switch self {
        case .fajr:
            return "The dawn prayer, the first of the five daily prayers. Its time runs from first light until sunrise."
        case .sunrise:
            return "When the sun comes up. It ends the time for Fajr and is not a prayer of its own."
        case .dhuhr:
            return "The midday prayer, the second of the five daily prayers. Its time begins just after the sun passes its highest point."
        case .asr:
            return "The afternoon prayer, the third of the five daily prayers. Schools differ on when it begins, so the app lets you choose."
        case .maghrib:
            return "The sunset prayer, the fourth of the five daily prayers. Its time begins when the sun has set."
        case .isha:
            return "The night prayer, the last of the five daily prayers. Its time begins when the last light of evening has gone."
        case .jumuah:
            return "The Friday prayer, held together at a mosque around midday, with a short talk before it."
        case .qibla:
            return "The direction of the Kaaba in Makkah, which Muslims face when they pray."
        case .makkah:
            return "The city in Saudi Arabia where the Kaaba stands, the place Muslims face in prayer."
        case .adhan:
            return "The call to prayer, made when the time for a prayer begins."
        case .wudu:
            return "The washing before prayer, of set parts of the body such as the hands, face, arms and feet."
        case .rakah:
            return "One unit of prayer, which includes standing, bowing and prostrating. Each prayer has a set number of units."
        case .sunnah:
            return "Here, the voluntary prayers offered before or after some of the five daily prayers, following the example of the Prophet Muhammad."
        case .surah:
            return "A chapter of the Quran. The Quran has 114 surahs."
        case .ayah:
            return "A verse of the Quran. Each surah is made of ayahs."
        case .juz:
            return "One of 30 parts of about equal length that the Quran is divided into. Many people use them to plan their reading."
        case .page:
            return "A page of the printed Quran, called the mushaf. The app uses the common 604 page layout."
        case .basmala:
            return "The opening line read at the start of most surahs, beginning in the name of God."
        case .tafsir:
            return "Explanation of the meaning of the Quran, written by scholars."
        case .transliteration:
            return "Arabic sounds written in Latin letters, to help you read along before you know Arabic script."
        case .reciter:
            return "The person whose recorded reading of the Quran you hear."
        case .hijri:
            return "The Islamic calendar, which follows the moon. Its dates move about 11 days earlier each year against the usual calendar and are marked AH."
        case .ramadan:
            return "The ninth month of the Hijri calendar. Muslims fast during it, from dawn until sunset."
        case .suhur:
            return "The meal eaten before dawn on a day of fasting."
        case .iftar:
            return "The meal that breaks the fast at sunset."
        case .taraweeh:
            return "Voluntary night prayers in Ramadan, often prayed together at a mosque after Isha."
        case .eid:
            return "One of two yearly festivals: Eid al-Fitr when Ramadan ends, and Eid al-Adha during the days of the pilgrimage."
        case .arafah:
            return "The day before Eid al-Adha, when pilgrims gather on the plain of Arafah near Makkah."
        case .dhikr:
            return "Remembering God with short words of praise, often repeated."
        case .adhkar:
            return "The plural of dhikr. Often used for the set words said in the morning, in the evening and after prayer."
        case .tasbih:
            return "Praising God with short words, often counted on beads or fingers. The Tasbih tool keeps the count for you."
        case .dua:
            return "A personal prayer to God, asking for something, in your own words or in words passed down."
        case .hadith:
            return "A report of what the Prophet Muhammad said or did, passed down through named narrators."
        case .zakat:
            return "A yearly charity, usually 2.5% of savings above a set amount, given to people in need."
        case .nisab:
            return "The set amount of wealth above which zakat is due. It is measured against the value of gold or silver."
        case .halal:
            return "Allowed in Islam. Halal food is food that meets Islamic dietary rules."
        case .tahajjud:
            return "A voluntary prayer at night, after waking from sleep and before Fajr."
        case .duha:
            return "The mid-morning, after the sun has fully risen and before Dhuhr, and the voluntary prayer offered then."
        case .middleOfNight:
            return "The halfway point between Maghrib and the next Fajr."
        case .lastThird:
            return "The last third of the time between Maghrib and the next Fajr. A time many choose for night prayer."
        }
    }

    /// The term for one of the five prayers.
    init(_ prayer: Prayer) {
        switch prayer {
        case .fajr: self = .fajr
        case .dhuhr: self = .dhuhr
        case .asr: self = .asr
        case .maghrib: self = .maghrib
        case .isha: self = .isha
        }
    }

    /// The term for a Day view row id (`DayTimeRow.id`), or nil when the row has none.
    init?(dayRowID: String) {
        switch dayRowID {
        case "fajr": self = .fajr
        case "sunrise": self = .sunrise
        case "dhuhr": self = .dhuhr
        case "asr": self = .asr
        case "maghrib": self = .maghrib
        case "isha": self = .isha
        case "duha": self = .duha
        case "middleOfNight": self = .middleOfNight
        case "lastThird": self = .lastThird
        case "suhurEnds": self = .suhur
        case "iftar": self = .iftar
        default: return nil
        }
    }

    /// Every term, A to Z by title.
    static var alphabetical: [GlossaryTerm] {
        allCases.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    /// Terms whose title or meaning contains `query`, A to Z. An empty query keeps them all.
    static func matching(_ query: String) -> [GlossaryTerm] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return alphabetical }
        return alphabetical.filter { term in
            term.title.localizedStandardContains(trimmed) || term.meaning.localizedStandardContains(trimmed)
        }
    }

    /// The matching terms grouped under their first letter, A to Z.
    static func sections(matching query: String) -> [GlossarySection] {
        var sections: [GlossarySection] = []
        for term in matching(query) {
            let letter = String(term.title.prefix(1)).uppercased()
            if let last = sections.last, last.letter == letter {
                sections[sections.count - 1].terms.append(term)
            } else {
                sections.append(GlossarySection(letter: letter, terms: [term]))
            }
        }
        return sections
    }
}

/// One letter of the glossary and its terms.
struct GlossarySection: Identifiable, Equatable {
    let letter: String
    var terms: [GlossaryTerm]

    var id: String { letter }
}
