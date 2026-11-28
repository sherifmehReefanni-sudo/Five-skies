import SwiftUI

/// The tabs, so any screen can bring one forward.
enum AppTab: Hashable {
    case today
    case quran
    case learn
    case qibla
    case more
}

/// App-wide requests to show a place in the Quran. Owned by the lead (round E1).
/// Today's continue card, the now playing bar and Go to call `open(_:)`; the app root switches
/// to the Quran tab and the Quran tab opens the reader at that ayah.
final class QuranNavigator: ObservableObject {
    @Published var selectedTab: AppTab = .today
    /// The reader to show next. The Quran tab clears it once it has opened it.
    @Published var pending: QuranReaderTarget?

    func open(_ target: QuranReaderTarget) {
        pending = target
        selectedTab = .quran
    }
}
