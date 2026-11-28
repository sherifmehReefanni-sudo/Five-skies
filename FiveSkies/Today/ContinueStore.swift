import Foundation

/// What the user was last doing in the Quran.
enum ContinueKind: String, Codable, Sendable {
    case reading
    case listening
}

/// The one place Today offers to pick up again: the newest of reading or listening.
struct ContinueEntry: Codable, Equatable, Sendable {
    let kind: ContinueKind
    let sura: Int
    /// Nil when a surah was played without a known ayah.
    let ayah: Int?
    /// Set for listening only.
    let reciterName: String?
    let date: Date
}

/// Keeps one `ContinueEntry` under "continue.last". Each note replaces the stored entry when
/// it is at least as new, whichever kind it is, so the card always shows the last thing done.
/// Call from the main thread (the reader and the player do), since the card observes it.
final class ContinueStore: ObservableObject {
    static let shared = ContinueStore()

    static let storageKey = "continue.last"
    /// Entries older than this are not shown (30 days).
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    @Published private(set) var stored: ContinueEntry?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            stored = try? JSONDecoder().decode(ContinueEntry.self, from: data)
        } else {
            stored = nil
        }
    }

    /// The reader's last read position changed.
    func noteReading(sura: Int, ayah: Int, at date: Date) {
        save(ContinueEntry(kind: .reading, sura: sura, ayah: ayah, reciterName: nil, date: date))
    }

    /// A surah started playing.
    func noteListening(sura: Int, ayah: Int?, reciterName: String, at date: Date) {
        save(ContinueEntry(kind: .listening, sura: sura, ayah: ayah, reciterName: reciterName, date: date))
    }

    /// The entry to show at `now`, or nil when there is none or it is older than 30 days.
    func entry(now: Date) -> ContinueEntry? {
        Self.visible(stored, now: now)
    }

    static func visible(_ entry: ContinueEntry?, now: Date) -> ContinueEntry? {
        guard let entry else { return nil }
        guard now.timeIntervalSince(entry.date) <= maxAge else { return nil }
        return entry
    }

    private func save(_ entry: ContinueEntry) {
        if let current = stored {
            // Newest wins across both kinds; an older note never replaces a newer one.
            guard entry.date >= current.date else { return }
            // The reader notes often while scrolling; skip the write when nothing changed.
            if current.kind == entry.kind, current.sura == entry.sura, current.ayah == entry.ayah,
               current.reciterName == entry.reciterName,
               entry.date.timeIntervalSince(current.date) < 60 {
                return
            }
        }
        stored = entry
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
