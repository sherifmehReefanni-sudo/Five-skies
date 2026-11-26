import Foundation

enum QuranParserError: Error, Equatable, LocalizedError {
    case unreadableFile(String)
    case malformedTextLine(line: Int)
    case wrongAyahCount(expected: Int, found: Int)
    case wrongSuraCount(expected: Int, found: Int)
    case unknownSura(Int)
    case suraAyahCountMismatch(sura: Int, expected: Int, found: Int)
    case ayahNumberingGap(sura: Int, expected: Int, found: Int)
    case suraStartMismatch(sura: Int, expected: Int, found: Int)
    case malformedMetadata(String)
    case wrongMarkerCount(kind: String, expected: Int, found: Int)
    case markerOutOfRange(kind: String, index: Int)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name):
            return "Could not read \(name)."
        case .malformedTextLine(let line):
            return "Line \(line) of the Quran text is not in the form sura|aya|text."
        case .wrongAyahCount(let expected, let found):
            return "Expected \(expected) ayahs in the Quran text, found \(found)."
        case .wrongSuraCount(let expected, let found):
            return "Expected \(expected) suras, found \(found)."
        case .unknownSura(let sura):
            return "The Quran text refers to sura \(sura), which is not in the metadata."
        case .suraAyahCountMismatch(let sura, let expected, let found):
            return "Sura \(sura) should have \(expected) ayahs but the text has \(found)."
        case .ayahNumberingGap(let sura, let expected, let found):
            return "Sura \(sura): expected ayah \(expected), found ayah \(found)."
        case .suraStartMismatch(let sura, let expected, let found):
            return "Sura \(sura) should start at ayah index \(expected), the metadata says \(found)."
        case .malformedMetadata(let detail):
            return "The Quran metadata is malformed: \(detail)."
        case .wrongMarkerCount(let kind, let expected, let found):
            return "Expected \(expected) \(kind) entries in the metadata, found \(found)."
        case .markerOutOfRange(let kind, let index):
            return "The metadata \(kind) entry \(index) points to an ayah that does not exist."
        }
    }
}

/// The Tanzil metadata, as parsed from quran-data.xml.
struct QuranMetadata: Sendable {
    struct SuraEntry: Sendable {
        let index: Int
        let ayahCount: Int
        let start: Int
        let arabicName: String
        let transliteratedName: String
        let englishName: String
        let revelation: RevelationType
    }

    struct Marker: Sendable {
        let index: Int
        let ref: AyahRef
    }

    let suras: [SuraEntry]
    let juzs: [Marker]
    let pages: [Marker]
    let sajdas: [Sajda]
}

/// One line of the text file, split into its three fields. `text` is exactly the bytes after the second `|`.
struct QuranTextLine: Equatable, Sendable {
    let sura: Int
    let aya: Int
    let text: String
}

/// Pure parsing of the Tanzil files. Nothing here touches the bundle or the main thread.
enum QuranParser {
    static let expectedSuraCount = 114
    static let expectedAyahCount = 6236
    static let expectedJuzCount = 30
    static let expectedPageCount = 604

    // MARK: - Text

    /// Splits the text file into ayah lines. Empty lines and the `#` license lines are skipped.
    /// Each line is split on its first two `|` only; the rest is kept exactly as stored.
    static func parseText(_ contents: String) throws -> [QuranTextLine] {
        var result: [QuranTextLine] = []
        result.reserveCapacity(expectedAyahCount)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, line) in lines.enumerated() {
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            let scalars = line.unicodeScalars
            guard let firstBar = scalars.firstIndex(of: "|") else {
                throw QuranParserError.malformedTextLine(line: offset + 1)
            }
            let afterFirst = scalars.index(after: firstBar)
            guard let secondBar = scalars[afterFirst...].firstIndex(of: "|") else {
                throw QuranParserError.malformedTextLine(line: offset + 1)
            }
            let suraField = String(scalars[scalars.startIndex..<firstBar])
            let ayaField = String(scalars[afterFirst..<secondBar])
            let text = String(scalars[scalars.index(after: secondBar)...])
            guard let sura = Int(suraField), let aya = Int(ayaField), !text.isEmpty else {
                throw QuranParserError.malformedTextLine(line: offset + 1)
            }
            result.append(QuranTextLine(sura: sura, aya: aya, text: text))
        }
        return result
    }

    // MARK: - Metadata

    static func parseMetadata(_ data: Data) throws -> QuranMetadata {
        let collector = MetadataCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        let parsed = parser.parse()
        if let failure = collector.failure {
            throw QuranParserError.malformedMetadata(failure)
        }
        guard parsed else {
            let detail = parser.parserError.map { String(describing: $0) } ?? "the XML could not be read"
            throw QuranParserError.malformedMetadata(detail)
        }
        return QuranMetadata(
            suras: collector.suras.sorted { $0.index < $1.index },
            juzs: collector.juzs.sorted { $0.index < $1.index },
            pages: collector.pages.sorted { $0.index < $1.index },
            sajdas: collector.sajdas.sorted { $0.number < $1.number }
        )
    }

    // MARK: - Assembly

    static func build(text contents: String, metadata data: Data) throws -> QuranData {
        let metadata = try parseMetadata(data)
        let lines = try parseText(contents)
        return try assemble(lines: lines, metadata: metadata)
    }

    static func assemble(lines: [QuranTextLine], metadata: QuranMetadata) throws -> QuranData {
        guard metadata.suras.count == expectedSuraCount else {
            throw QuranParserError.wrongSuraCount(expected: expectedSuraCount, found: metadata.suras.count)
        }
        guard lines.count == expectedAyahCount else {
            throw QuranParserError.wrongAyahCount(expected: expectedAyahCount, found: lines.count)
        }

        var suras: [Sura] = []
        suras.reserveCapacity(expectedSuraCount)
        var runningStart = 0
        for (offset, entry) in metadata.suras.enumerated() {
            guard entry.index == offset + 1 else {
                throw QuranParserError.malformedMetadata("sura entries are not numbered 1 to \(expectedSuraCount)")
            }
            guard entry.ayahCount > 0 else {
                throw QuranParserError.malformedMetadata("sura \(entry.index) has no ayahs")
            }
            guard entry.start == runningStart else {
                throw QuranParserError.suraStartMismatch(sura: entry.index, expected: runningStart, found: entry.start)
            }
            suras.append(Sura(
                number: entry.index,
                arabicName: entry.arabicName,
                transliteratedName: entry.transliteratedName,
                englishName: entry.englishName,
                revelation: entry.revelation,
                ayahCount: entry.ayahCount,
                firstAyahIndex: runningStart
            ))
            runningStart += entry.ayahCount
        }
        guard runningStart == expectedAyahCount else {
            throw QuranParserError.wrongAyahCount(expected: expectedAyahCount, found: runningStart)
        }

        var ayahsBySura: [[Ayah]] = Array(repeating: [], count: expectedSuraCount)
        for line in lines {
            guard ayahsBySura.indices.contains(line.sura - 1) else {
                throw QuranParserError.unknownSura(line.sura)
            }
            let expected = ayahsBySura[line.sura - 1].count + 1
            guard line.aya == expected else {
                throw QuranParserError.ayahNumberingGap(sura: line.sura, expected: expected, found: line.aya)
            }
            ayahsBySura[line.sura - 1].append(Ayah(sura: line.sura, number: line.aya, text: line.text))
        }
        for sura in suras {
            let found = ayahsBySura[sura.number - 1].count
            guard found == sura.ayahCount else {
                throw QuranParserError.suraAyahCountMismatch(sura: sura.number, expected: sura.ayahCount, found: found)
            }
        }

        let juzStarts = try markers(metadata.juzs, kind: "juz", expected: expectedJuzCount, suras: suras)
        let pageStarts = try markers(metadata.pages, kind: "page", expected: expectedPageCount, suras: suras)
        for sajda in metadata.sajdas {
            guard isValid(sajda.ref, in: suras) else {
                throw QuranParserError.markerOutOfRange(kind: "sajda", index: sajda.number)
            }
        }

        return QuranData(
            suras: suras,
            ayahsBySura: ayahsBySura,
            juzStarts: juzStarts,
            pageStarts: pageStarts,
            sajdas: metadata.sajdas
        )
    }

    private static func markers(
        _ list: [QuranMetadata.Marker],
        kind: String,
        expected: Int,
        suras: [Sura]
    ) throws -> [AyahRef] {
        guard list.count == expected else {
            throw QuranParserError.wrongMarkerCount(kind: kind, expected: expected, found: list.count)
        }
        var previous: AyahRef?
        for (offset, marker) in list.enumerated() {
            guard marker.index == offset + 1 else {
                throw QuranParserError.malformedMetadata("\(kind) entries are not numbered 1 to \(expected)")
            }
            guard isValid(marker.ref, in: suras) else {
                throw QuranParserError.markerOutOfRange(kind: kind, index: marker.index)
            }
            if let previous, !(previous < marker.ref) {
                throw QuranParserError.malformedMetadata("\(kind) entries are not in order")
            }
            previous = marker.ref
        }
        return list.map(\.ref)
    }

    private static func isValid(_ ref: AyahRef, in suras: [Sura]) -> Bool {
        guard suras.indices.contains(ref.sura - 1) else { return false }
        return ref.aya >= 1 && ref.aya <= suras[ref.sura - 1].ayahCount
    }
}

/// Collects the attributes of the metadata elements the app uses.
private final class MetadataCollector: NSObject, XMLParserDelegate {
    var suras: [QuranMetadata.SuraEntry] = []
    var juzs: [QuranMetadata.Marker] = []
    var pages: [QuranMetadata.Marker] = []
    var sajdas: [Sajda] = []
    var failure: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard failure == nil else { return }
        switch elementName {
        case "sura":
            guard let index = int(attributeDict["index"]),
                  let ayahCount = int(attributeDict["ayas"]),
                  let start = int(attributeDict["start"]),
                  let arabicName = attributeDict["name"],
                  let transliteratedName = attributeDict["tname"],
                  let englishName = attributeDict["ename"],
                  let typeName = attributeDict["type"],
                  let revelation = RevelationType(rawValue: typeName)
            else {
                fail(parser, "a sura element is missing an attribute")
                return
            }
            suras.append(QuranMetadata.SuraEntry(
                index: index,
                ayahCount: ayahCount,
                start: start,
                arabicName: arabicName,
                transliteratedName: transliteratedName,
                englishName: englishName,
                revelation: revelation
            ))
        case "juz", "page":
            guard let index = int(attributeDict["index"]),
                  let sura = int(attributeDict["sura"]),
                  let aya = int(attributeDict["aya"])
            else {
                fail(parser, "a \(elementName) element is missing an attribute")
                return
            }
            let marker = QuranMetadata.Marker(index: index, ref: AyahRef(sura: sura, aya: aya))
            if elementName == "juz" {
                juzs.append(marker)
            } else {
                pages.append(marker)
            }
        case "sajda":
            guard let index = int(attributeDict["index"]),
                  let sura = int(attributeDict["sura"]),
                  let aya = int(attributeDict["aya"])
            else {
                fail(parser, "a sajda element is missing an attribute")
                return
            }
            sajdas.append(Sajda(number: index, ref: AyahRef(sura: sura, aya: aya), type: attributeDict["type"] ?? ""))
        default:
            break
        }
    }

    private func int(_ value: String?) -> Int? {
        value.flatMap { Int($0) }
    }

    private func fail(_ parser: XMLParser, _ message: String) {
        failure = message
        parser.abortParsing()
    }
}
