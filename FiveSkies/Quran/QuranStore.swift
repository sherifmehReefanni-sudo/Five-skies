import Foundation

/// Finds and reads the bundled Tanzil files.
enum QuranBundle {
    static let textName = "quran-uthmani"
    static let metadataName = "quran-data"

    /// The bundle that holds the Quran files: the main bundle, or the app bundle found from an app class.
    static func resourceBundle() -> Bundle {
        if Bundle.main.url(forResource: textName, withExtension: "txt") != nil {
            return Bundle.main
        }
        return Bundle(for: QuranStore.self)
    }

    static func textURL(in bundle: Bundle = resourceBundle()) -> URL? {
        bundle.url(forResource: textName, withExtension: "txt")
    }

    static func metadataURL(in bundle: Bundle = resourceBundle()) -> URL? {
        bundle.url(forResource: metadataName, withExtension: "xml")
    }

    /// Reads and parses both files. Slow enough that it should run off the main thread.
    static func load(from bundle: Bundle = resourceBundle()) throws -> QuranData {
        guard let textURL = textURL(in: bundle) else {
            throw QuranParserError.unreadableFile("\(textName).txt")
        }
        guard let metadataURL = metadataURL(in: bundle) else {
            throw QuranParserError.unreadableFile("\(metadataName).xml")
        }
        let text: String
        do {
            text = try String(contentsOf: textURL, encoding: .utf8)
        } catch {
            throw QuranParserError.unreadableFile("\(textName).txt")
        }
        let metadata: Data
        do {
            metadata = try Data(contentsOf: metadataURL)
        } catch {
            throw QuranParserError.unreadableFile("\(metadataName).xml")
        }
        return try QuranParser.build(text: text, metadata: metadata)
    }
}

/// Loads the Quran once, off the main thread, and publishes the result.
final class QuranStore: ObservableObject {
    enum LoadState: Sendable {
        case loading
        case loaded(QuranData)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading

    private let loader: @Sendable () throws -> QuranData
    private var hasStarted = false

    init(autoload: Bool = true, loader: @escaping @Sendable () throws -> QuranData = { try QuranBundle.load() }) {
        self.loader = loader
        if autoload {
            load()
        }
    }

    /// Starts loading unless a load already started or finished.
    func load() {
        guard !hasStarted else { return }
        hasStarted = true
        state = .loading
        let loader = self.loader
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> LoadState in
                do {
                    return .loaded(try loader())
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    return .failed(message)
                }
            }.value
            self.state = result
        }
    }

    var data: QuranData? {
        if case .loaded(let data) = state {
            return data
        }
        return nil
    }

    var suras: [Sura] { data?.suras ?? [] }

    var juzStarts: [AyahRef] { data?.juzStarts ?? [] }

    func sura(_ number: Int) -> Sura? {
        data?.sura(number)
    }

    func ayahs(inSura number: Int) -> [Ayah] {
        data?.ayahs(inSura: number) ?? []
    }

    func page(for ref: AyahRef) -> Int? {
        data?.page(for: ref)
    }

    func juz(for ref: AyahRef) -> Int? {
        data?.juz(for: ref)
    }

    func sajda(at ref: AyahRef) -> Sajda? {
        data?.sajda(at: ref)
    }
}
