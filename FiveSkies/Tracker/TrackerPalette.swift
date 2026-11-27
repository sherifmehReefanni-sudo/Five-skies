import SwiftUI

/// Tracker colors on top of MorePalette. Paused days use a soft periwinkle, never red.
enum TrackerPalette {
    static let pause = Color(hex: 0xB8C2FF)
    /// Days before the user started tracking: a faint blank, not an unmarked ring.
    static let notStarted = Color.white.opacity(0.2)
    static let track = Color.white.opacity(0.1)
}
