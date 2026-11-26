import Foundation

/// The three tasbih phrases, shown in Latin transliteration.
enum TasbihPhrase: String, CaseIterable, Identifiable {
    case subhanAllah = "SubhanAllah"
    case alhamdulillah = "Alhamdulillah"
    case allahuAkbar = "Allahu Akbar"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// Pure counting logic for the tasbih: counts up to the target, then starts a new round.
struct TasbihCounter: Equatable {
    static let targets = [33, 99, 100]
    static let defaultTarget = 33

    var count: Int
    var target: Int
    var rounds: Int

    init(count: Int = 0, target: Int = TasbihCounter.defaultTarget, rounds: Int = 0) {
        self.target = TasbihCounter.targets.contains(target) ? target : TasbihCounter.defaultTarget
        self.count = min(max(0, count), self.target)
        self.rounds = max(0, rounds)
    }

    /// How far around the ring the count is, from 0 to 1.
    var progress: Double {
        target > 0 ? min(Double(count) / Double(target), 1) : 0
    }

    /// Counts one. After the target is reached, the next tap starts a new round at 1.
    /// Reaching the target adds one completed round.
    mutating func increment() {
        if count >= target {
            count = 1
        } else {
            count += 1
        }
        if count == target {
            rounds += 1
        }
    }

    /// Clears the count and the completed rounds.
    mutating func reset() {
        count = 0
        rounds = 0
    }

    /// Changes the target; a count already past the new target starts over.
    mutating func setTarget(_ newTarget: Int) {
        guard TasbihCounter.targets.contains(newTarget) else { return }
        target = newTarget
        if count > newTarget {
            count = 0
        }
    }
}
