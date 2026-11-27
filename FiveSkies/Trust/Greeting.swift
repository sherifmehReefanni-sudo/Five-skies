import SwiftUI

/// The optional first name used for the greeting on Today. Stored on this device only and
/// never included in the iCloud backup.
enum FirstNameStore {
    static let storageKey = "trust.firstName"
    static let maxLength = 30

    /// Trims spaces and line breaks and keeps at most `maxLength` characters.
    /// Returns nil when nothing is left.
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? nil : limited
    }

    static func load(from defaults: UserDefaults = .standard) -> String? {
        normalize(defaults.string(forKey: storageKey))
    }

    /// Saves the normalized name, or removes it when the name is empty.
    static func save(_ raw: String?, to defaults: UserDefaults = .standard) {
        if let name = normalize(raw) {
            defaults.set(name, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }
}

/// "Good morning, Sherif" and friends. Pure, so tests pass a fixed time zone.
enum GreetingText {
    /// Morning from 4:00 to 11:59, afternoon from 12:00 to 16:59, evening otherwise.
    static func salutation(hour: Int) -> String {
        switch hour {
        case 4..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    /// The greeting for `now` in `timeZone`, or nil when there is no name.
    static func make(firstName: String?, now: Date, timeZone: TimeZone) -> String? {
        guard let name = FirstNameStore.normalize(firstName) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: now)
        return "\(salutation(hour: hour)), \(name)"
    }
}

/// One line of greeting for Today. Shows nothing when no name is stored.
struct GreetingLine: View {
    let now: Date
    let timeZone: TimeZone

    @AppStorage(FirstNameStore.storageKey) private var storedName: String = ""

    init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }

    var body: some View {
        if let text = GreetingText.make(firstName: storedName, now: now, timeZone: timeZone) {
            Text(verbatim: text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.35), radius: 6, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("greetingLine")
        }
    }
}
