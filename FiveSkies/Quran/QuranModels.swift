import Foundation

/// A position in the Quran, by sura and ayah number. This is all that is ever stored.
struct AyahRef: Codable, Hashable, Comparable, Sendable {
    let sura: Int
    let aya: Int

    static func < (lhs: AyahRef, rhs: AyahRef) -> Bool {
        if lhs.sura != rhs.sura {
            return lhs.sura < rhs.sura
        }
        return lhs.aya < rhs.aya
    }
}

enum RevelationType: String, Sendable {
    case meccan = "Meccan"
    case medinan = "Medinan"

    var title: String { rawValue }
}

/// One sura, as described by the Tanzil metadata.
struct Sura: Identifiable, Hashable, Sendable {
    let number: Int
    /// The Arabic name, exactly as given in the metadata file.
    let arabicName: String
    let transliteratedName: String
    let englishName: String
    let revelation: RevelationType
    let ayahCount: Int
    /// Index of this sura's first ayah among all 6236, counted from 0.
    let firstAyahIndex: Int

    var id: Int { number }
}

/// One ayah. `text` is the stored string from the text file, never changed.
struct Ayah: Identifiable, Hashable, Sendable {
    let sura: Int
    let number: Int
    let text: String

    var id: AyahRef { ref }
    var ref: AyahRef { AyahRef(sura: sura, aya: number) }

    /// In the Tanzil text the first ayah of every sura except 1 and 9 begins with the basmala.
    var startsWithBasmala: Bool {
        number == 1 && sura != 1 && sura != 9
    }

    /// The basmala, shown as its own header line. Nil when this ayah has none to separate.
    var basmala: String? {
        guard startsWithBasmala else { return nil }
        return Self.splitBasmala(text)?.basmala
    }

    /// What is shown as the ayah itself: the stored text, minus the basmala where it is shown separately.
    var displayText: String {
        guard startsWithBasmala, let split = Self.splitBasmala(text) else { return text }
        return split.remainder
    }

    /// Splits off the first four words, separated by the ASCII space character.
    /// Works on Unicode scalars so the marks of the text are never touched.
    /// Returns nil when there are not four words followed by a non-empty remainder.
    static func splitBasmala(_ text: String) -> (basmala: String, remainder: String)? {
        let scalars = text.unicodeScalars
        var spaces = 0
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if scalars[index] == " " {
                spaces += 1
                if spaces == 4 {
                    let head = String(scalars[scalars.startIndex..<index])
                    let tail = String(scalars[scalars.index(after: index)...])
                    guard !head.isEmpty, !tail.isEmpty else { return nil }
                    return (head, tail)
                }
            }
            index = scalars.index(after: index)
        }
        return nil
    }
}

struct Sajda: Hashable, Sendable {
    let number: Int
    let ref: AyahRef
    /// "recommended" or "obligatory", as given in the metadata.
    let type: String
}

/// Everything the Quran tab needs, parsed once.
struct QuranData: Sendable {
    let suras: [Sura]
    /// Ayahs for sura n are at index n - 1.
    let ayahsBySura: [[Ayah]]
    /// The first ayah of each juz, juz 1 first.
    let juzStarts: [AyahRef]
    /// The first ayah of each Madina mushaf page, page 1 first.
    let pageStarts: [AyahRef]
    let sajdas: [Sajda]

    private let juzStartIndices: [Int]
    private let pageStartIndices: [Int]
    private let juzByStart: [AyahRef: Int]
    private let pageByStart: [AyahRef: Int]
    private let sajdaByRef: [AyahRef: Sajda]

    init(suras: [Sura], ayahsBySura: [[Ayah]], juzStarts: [AyahRef], pageStarts: [AyahRef], sajdas: [Sajda]) {
        self.suras = suras
        self.ayahsBySura = ayahsBySura
        self.juzStarts = juzStarts
        self.pageStarts = pageStarts
        self.sajdas = sajdas

        func index(_ ref: AyahRef) -> Int {
            guard suras.indices.contains(ref.sura - 1) else { return Int.max }
            return suras[ref.sura - 1].firstAyahIndex + ref.aya - 1
        }
        juzStartIndices = juzStarts.map(index)
        pageStartIndices = pageStarts.map(index)

        var juzByStart: [AyahRef: Int] = [:]
        for (offset, ref) in juzStarts.enumerated() {
            juzByStart[ref] = offset + 1
        }
        self.juzByStart = juzByStart

        var pageByStart: [AyahRef: Int] = [:]
        for (offset, ref) in pageStarts.enumerated() {
            pageByStart[ref] = offset + 1
        }
        self.pageByStart = pageByStart

        var sajdaByRef: [AyahRef: Sajda] = [:]
        for sajda in sajdas {
            sajdaByRef[sajda.ref] = sajda
        }
        self.sajdaByRef = sajdaByRef
    }

    var ayahCount: Int {
        ayahsBySura.reduce(0) { $0 + $1.count }
    }

    func sura(_ number: Int) -> Sura? {
        guard suras.indices.contains(number - 1) else { return nil }
        return suras[number - 1]
    }

    func ayahs(inSura number: Int) -> [Ayah] {
        guard ayahsBySura.indices.contains(number - 1) else { return [] }
        return ayahsBySura[number - 1]
    }

    func ayah(_ ref: AyahRef) -> Ayah? {
        let list = ayahs(inSura: ref.sura)
        guard list.indices.contains(ref.aya - 1) else { return nil }
        return list[ref.aya - 1]
    }

    /// Index of the ayah among all 6236, counted from 0, or nil if it does not exist.
    func globalIndex(of ref: AyahRef) -> Int? {
        guard let sura = sura(ref.sura), ref.aya >= 1, ref.aya <= sura.ayahCount else { return nil }
        return sura.firstAyahIndex + ref.aya - 1
    }

    /// The Madina mushaf page (1...604) that contains the ayah.
    func page(for ref: AyahRef) -> Int? {
        guard let index = globalIndex(of: ref),
              let position = Self.lastPosition(atOrBelow: index, in: pageStartIndices)
        else { return nil }
        return position + 1
    }

    /// The juz (1...30) that contains the ayah.
    func juz(for ref: AyahRef) -> Int? {
        guard let index = globalIndex(of: ref),
              let position = Self.lastPosition(atOrBelow: index, in: juzStartIndices)
        else { return nil }
        return position + 1
    }

    /// The juz number when this ayah is the first of a juz.
    func juzStarting(at ref: AyahRef) -> Int? {
        juzByStart[ref]
    }

    /// The page number when this ayah is the first on a page.
    func pageStarting(at ref: AyahRef) -> Int? {
        pageByStart[ref]
    }

    func sajda(at ref: AyahRef) -> Sajda? {
        sajdaByRef[ref]
    }

    /// The last position in an ascending list whose value is at most `value`.
    static func lastPosition(atOrBelow value: Int, in sorted: [Int]) -> Int? {
        var low = 0
        var high = sorted.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if sorted[middle] <= value {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }
}
