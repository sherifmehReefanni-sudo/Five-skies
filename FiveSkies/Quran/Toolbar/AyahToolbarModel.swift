import CoreGraphics
import Foundation

/// The ayah the toolbar is showing. Set it to show the bar, set it to nil to hide it.
struct AyahToolbarItem: Identifiable, Equatable, Hashable {
    let sura: Int
    let ayah: Int

    var id: String { "\(sura):\(ayah)" }

    init(sura: Int, ayah: Int) {
        self.sura = sura
        self.ayah = ayah
    }
}

/// What each toolbar button does. The reader supplies these; the toolbar never touches stores.
struct AyahToolbarActions {
    let play: () -> Void
    let toggleBookmark: () -> Void
    let share: () -> Void
    let copy: () -> Void
    let shareAsImage: () -> Void
    let markLastRead: () -> Void
    /// Nil hides the Words button (round E2).
    let words: (() -> Void)?
    /// Takes back an "I know this" mark. Nil hides the menu item (shown only for known ayahs).
    let removeKnownMark: (() -> Void)?

    init(
        play: @escaping () -> Void,
        toggleBookmark: @escaping () -> Void,
        share: @escaping () -> Void,
        copy: @escaping () -> Void,
        shareAsImage: @escaping () -> Void,
        markLastRead: @escaping () -> Void,
        words: (() -> Void)? = nil,
        removeKnownMark: (() -> Void)? = nil
    ) {
        self.play = play
        self.toggleBookmark = toggleBookmark
        self.share = share
        self.copy = copy
        self.shareAsImage = shareAsImage
        self.markLastRead = markLastRead
        self.words = words
        self.removeKnownMark = removeKnownMark
    }
}

/// The large buttons along the bar, in order.
enum AyahToolbarButton: CaseIterable, Equatable, Hashable {
    case play
    case bookmark
    case words
    case share
    case more

    /// The buttons to show: Play only with a reciter, Words only once it exists.
    static func visible(playTitle: String?, hasWords: Bool) -> [AyahToolbarButton] {
        allCases.filter { button in
            switch button {
            case .play:
                return playTitle != nil
            case .words:
                return hasWords
            case .bookmark, .share, .more:
                return true
            }
        }
    }

    var identifier: String {
        switch self {
        case .play: return "toolbarPlay"
        case .bookmark: return "toolbarBookmark"
        case .words: return "toolbarWords"
        case .share: return "toolbarShare"
        case .more: return "toolbarMore"
        }
    }

    /// The short label under the icon.
    func title(isBookmarked: Bool, playTitle: String?) -> String {
        switch self {
        case .play: return playTitle ?? AyahToolbarText.playFromHere
        case .bookmark: return isBookmarked ? "Saved" : "Bookmark"
        case .words: return "Words"
        case .share: return "Share"
        case .more: return "More"
        }
    }

    /// What VoiceOver says. The bookmark button names what a tap will do.
    func accessibilityLabel(isBookmarked: Bool, playTitle: String?) -> String {
        switch self {
        case .bookmark: return isBookmarked ? "Remove bookmark" : "Bookmark this ayah"
        case .words: return "Word by word"
        case .share: return "Share this ayah"
        case .more: return "More actions"
        case .play: return title(isBookmarked: isBookmarked, playTitle: playTitle)
        }
    }

    func systemImage(isBookmarked: Bool) -> String {
        switch self {
        case .play: return "play.fill"
        case .bookmark: return isBookmarked ? "bookmark.fill" : "bookmark"
        case .words: return "character.book.closed"
        case .share: return "square.and.arrow.up"
        case .more: return "ellipsis.circle"
        }
    }

    /// One shot actions close the bar. Bookmark keeps it open so the new state shows.
    var closesBar: Bool {
        switch self {
        case .bookmark, .more: return false
        case .play, .words, .share: return true
        }
    }
}

/// The items in the More menu, in order. Each closes the bar.
enum AyahToolbarMenuItem: CaseIterable, Equatable, Hashable {
    case copy
    case shareAsImage
    case markLastRead
    case removeKnownMark

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .shareAsImage: return "Share as image"
        case .markLastRead: return "Mark as last read"
        case .removeKnownMark: return "Remove known mark"
        }
    }

    var identifier: String {
        switch self {
        case .copy: return "toolbarCopy"
        case .shareAsImage: return "toolbarShareImage"
        case .markLastRead: return "toolbarLastRead"
        case .removeKnownMark: return "toolbarRemoveKnown"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .shareAsImage: return "photo"
        case .markLastRead: return "book"
        case .removeKnownMark: return "checkmark.seal"
        }
    }
}

/// Plain English copy the reader can reuse when it builds the bar.
enum AyahToolbarText {
    static let playFromHere = "Play from here"
    static let playFromStart = "Play from start"

    /// "Al-Fatiha · Ayah 2".
    static func title(suraName: String, ayah: Int) -> String {
        "\(suraName) · Ayah \(ayah)"
    }

    /// The play label: nil with no reciter, "Play from start" when this reciter cannot start mid surah.
    static func playTitle(offersPlayback: Bool, startsAtBeginning: Bool) -> String? {
        guard offersPlayback else { return nil }
        return startsAtBeginning ? playFromStart : playFromHere
    }
}

/// Sizes for the bar.
enum AyahToolbarLayout {
    /// The smallest touch target, in points.
    static let minimumTarget: CGFloat = 44

    /// All buttons in one row, or rows of three at accessibility text sizes.
    static func columns(buttonCount: Int, isAccessibilitySize: Bool) -> Int {
        let count = max(buttonCount, 1)
        return isAccessibilitySize ? min(count, 3) : count
    }
}

/// Deciding whether a tap outside the bar should close it.
/// The tap and an ayah button can fire on the same touch, in either order. So the tap waits a
/// moment and closes the bar only if the shown ayah did not change around the time of the tap:
/// tapping another ayah moves the bar to it, tapping the same ayah again or empty space closes it.
/// Times are seconds of system uptime.
enum AyahToolbarDismissal {
    /// How long the tap waits before deciding, so the ayah button's change has landed.
    static let settleDelay: Double = 0.15
    /// A change this close before the tap counts as caused by the same touch.
    static let sameTouchWindow: Double = 0.1

    static func shouldDismiss(tapAt: Double, lastChangeAt: Double?, isShowing: Bool) -> Bool {
        guard isShowing else { return false }
        guard let lastChangeAt else { return true }
        return lastChangeAt < tapAt - sameTouchWindow
    }
}
