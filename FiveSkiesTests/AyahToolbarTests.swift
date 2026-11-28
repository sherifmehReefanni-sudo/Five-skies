import XCTest
@testable import FiveSkies

/// The ayah toolbar's pure parts: which buttons show, their labels by state, and when it closes.
/// Placeholder English only; no scripture.
final class AyahToolbarTests: XCTestCase {
    func testAllButtonsShowWithReciterAndWords() {
        XCTAssertEqual(
            AyahToolbarButton.visible(playTitle: "Play from here", hasWords: true),
            [.play, .bookmark, .words, .share, .more]
        )
    }

    func testNoReciterHidesPlay() {
        XCTAssertEqual(
            AyahToolbarButton.visible(playTitle: nil, hasWords: true),
            [.bookmark, .words, .share, .more]
        )
    }

    func testNoWordsHidesWords() {
        XCTAssertEqual(
            AyahToolbarButton.visible(playTitle: "Play from here", hasWords: false),
            [.play, .bookmark, .share, .more]
        )
        XCTAssertEqual(
            AyahToolbarButton.visible(playTitle: nil, hasWords: false),
            [.bookmark, .share, .more]
        )
    }

    func testBookmarkLabelsFollowState() {
        XCTAssertEqual(AyahToolbarButton.bookmark.title(isBookmarked: false, playTitle: nil), "Bookmark")
        XCTAssertEqual(AyahToolbarButton.bookmark.title(isBookmarked: true, playTitle: nil), "Saved")
        XCTAssertEqual(AyahToolbarButton.bookmark.systemImage(isBookmarked: false), "bookmark")
        XCTAssertEqual(AyahToolbarButton.bookmark.systemImage(isBookmarked: true), "bookmark.fill")
        XCTAssertEqual(AyahToolbarButton.bookmark.accessibilityLabel(isBookmarked: false, playTitle: nil), "Bookmark this ayah")
        XCTAssertEqual(AyahToolbarButton.bookmark.accessibilityLabel(isBookmarked: true, playTitle: nil), "Remove bookmark")
    }

    func testPlayUsesTheGivenTitle() {
        XCTAssertEqual(AyahToolbarButton.play.title(isBookmarked: false, playTitle: "Play from here"), "Play from here")
        XCTAssertEqual(AyahToolbarButton.play.title(isBookmarked: false, playTitle: "Play from start"), "Play from start")
        XCTAssertEqual(AyahToolbarButton.play.accessibilityLabel(isBookmarked: false, playTitle: "Play from here"), "Play from here")
    }

    func testOtherLabels() {
        XCTAssertEqual(AyahToolbarButton.words.title(isBookmarked: false, playTitle: nil), "Words")
        XCTAssertEqual(AyahToolbarButton.share.title(isBookmarked: false, playTitle: nil), "Share")
        XCTAssertEqual(AyahToolbarButton.more.title(isBookmarked: false, playTitle: nil), "More")
        XCTAssertEqual(AyahToolbarButton.more.accessibilityLabel(isBookmarked: false, playTitle: nil), "More actions")
    }

    func testEveryLabelIsShortAndPlain() {
        let titles = AyahToolbarButton.allCases.flatMap { button in
            [true, false].map { button.title(isBookmarked: $0, playTitle: AyahToolbarText.playFromHere) }
        } + AyahToolbarMenuItem.allCases.map(\.title)
        for title in titles {
            XCTAssertFalse(title.isEmpty)
            XCTAssertLessThanOrEqual(title.count, 18, title)
            XCTAssertFalse(title.contains("\u{2014}"), title)
            XCTAssertFalse(title.lowercased().contains("missed"), title)
        }
    }

    func testIdentifiers() {
        XCTAssertEqual(AyahToolbarButton.allCases.map(\.identifier), ["toolbarPlay", "toolbarBookmark", "toolbarWords", "toolbarShare", "toolbarMore"])
        XCTAssertEqual(AyahToolbarMenuItem.allCases.map(\.identifier), ["toolbarCopy", "toolbarShareImage", "toolbarLastRead", "toolbarRemoveKnown"])
    }

    func testMenuOrderAndTitles() {
        XCTAssertEqual(AyahToolbarMenuItem.allCases.map(\.title), ["Copy", "Share as image", "Mark as last read", "Remove known mark"])
    }

    func testOneShotActionsCloseTheBarButBookmarkDoesNot() {
        XCTAssertTrue(AyahToolbarButton.play.closesBar)
        XCTAssertTrue(AyahToolbarButton.words.closesBar)
        XCTAssertTrue(AyahToolbarButton.share.closesBar)
        XCTAssertFalse(AyahToolbarButton.bookmark.closesBar)
        XCTAssertFalse(AyahToolbarButton.more.closesBar)
    }

    func testTitleAndPlayTitleHelpers() {
        XCTAssertEqual(AyahToolbarText.title(suraName: "Al-Fatiha", ayah: 2), "Al-Fatiha · Ayah 2")
        XCTAssertNil(AyahToolbarText.playTitle(offersPlayback: false, startsAtBeginning: false))
        XCTAssertNil(AyahToolbarText.playTitle(offersPlayback: false, startsAtBeginning: true))
        XCTAssertEqual(AyahToolbarText.playTitle(offersPlayback: true, startsAtBeginning: false), "Play from here")
        XCTAssertEqual(AyahToolbarText.playTitle(offersPlayback: true, startsAtBeginning: true), "Play from start")
    }

    func testColumnsWrapAtAccessibilitySizes() {
        XCTAssertEqual(AyahToolbarLayout.columns(buttonCount: 5, isAccessibilitySize: false), 5)
        XCTAssertEqual(AyahToolbarLayout.columns(buttonCount: 5, isAccessibilitySize: true), 3)
        XCTAssertEqual(AyahToolbarLayout.columns(buttonCount: 3, isAccessibilitySize: true), 3)
        XCTAssertEqual(AyahToolbarLayout.columns(buttonCount: 2, isAccessibilitySize: true), 2)
        XCTAssertEqual(AyahToolbarLayout.columns(buttonCount: 0, isAccessibilitySize: false), 1)
        XCTAssertGreaterThanOrEqual(AyahToolbarLayout.minimumTarget, 44)
    }

    func testItemIdentity() {
        let item = AyahToolbarItem(sura: 1, ayah: 2)
        XCTAssertEqual(item.id, "1:2")
        XCTAssertEqual(item, AyahToolbarItem(sura: 1, ayah: 2))
        XCTAssertNotEqual(item, AyahToolbarItem(sura: 2, ayah: 1))
    }

    func testOutsideTapDismissal() {
        // Nothing showing: never dismiss.
        XCTAssertFalse(AyahToolbarDismissal.shouldDismiss(tapAt: 10, lastChangeAt: nil, isShowing: false))
        // Shown a while ago, tap on empty space or the same ayah: dismiss.
        XCTAssertTrue(AyahToolbarDismissal.shouldDismiss(tapAt: 10, lastChangeAt: 5, isShowing: true))
        XCTAssertTrue(AyahToolbarDismissal.shouldDismiss(tapAt: 10, lastChangeAt: nil, isShowing: true))
        // The same touch moved the bar to another ayah, before or after the tap: keep it.
        XCTAssertFalse(AyahToolbarDismissal.shouldDismiss(tapAt: 10, lastChangeAt: 10.05, isShowing: true))
        XCTAssertFalse(AyahToolbarDismissal.shouldDismiss(tapAt: 10, lastChangeAt: 9.95, isShowing: true))
    }

    func testActionsDefaultToNoWords() {
        let actions = AyahToolbarActions(play: {}, toggleBookmark: {}, share: {}, copy: {}, shareAsImage: {}, markLastRead: {})
        XCTAssertNil(actions.words)
        let withWords = AyahToolbarActions(play: {}, toggleBookmark: {}, share: {}, copy: {}, shareAsImage: {}, markLastRead: {}, words: {})
        XCTAssertNotNil(withWords.words)
    }
}
