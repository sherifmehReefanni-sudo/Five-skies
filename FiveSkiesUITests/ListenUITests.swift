import XCTest

/// Listening inside the Quran tab, with fake reciters and a simulated player (`-FSFakeListen`):
/// no network, no audio.
final class ListenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuranTabPlaysASurahAndShowsThePlayModes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSFakeListen"]
        app.launch()

        let tab = app.tabBars.buttons["Quran"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Quran tab button did not appear")
        tab.tap()

        XCTAssertTrue(app.buttons["listenReciterButton"].waitForExistence(timeout: 20), "The fake reciters did not load")
        let play = app.buttons["quranPlay-1"]
        XCTAssertTrue(play.waitForExistence(timeout: 20), "The surah play button did not appear")
        XCTAssertTrue(app.buttons["suraRow-1"].exists, "The surah row is missing")
        attachScreenshot(named: "quran-list")

        play.tap()
        let bar = app.descendants(matching: .any)["nowPlayingBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "The now playing bar did not appear")
        attachScreenshot(named: "quran-playing")

        let open = app.buttons["nowPlayingOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "The now playing bar has no open button")
        // From the list, the bar opens the reader at the playing ayah; there it opens the player.
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["readerTitle"].waitForExistence(timeout: 20), "The bar did not open the reader")
        let openInReader = app.buttons["nowPlayingOpen"]
        XCTAssertTrue(openInReader.waitForExistence(timeout: 10), "The now playing bar is missing in the reader")
        openInReader.tap()
        XCTAssertTrue(app.buttons["playerPlayPause"].waitForExistence(timeout: 20), "The player sheet did not open")
        XCTAssertTrue(app.descendants(matching: .any)["playerCredit"].exists, "The credit line is missing from the player")
        attachScreenshot(named: "listen-player")

        let surahEnd = app.descendants(matching: .any)["playerSurahEnd"]
        XCTAssertTrue(surahEnd.waitForExistence(timeout: 10), "The play modes are missing from the player")
        let startOver = app.buttons["playerStartOver"]
        var swipes = 0
        while !(startOver.exists && startOver.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(startOver.isHittable, "Could not scroll to the play modes")
        XCTAssertTrue(app.switches["playerPauseForPrayer"].exists, "Pause for prayer is missing")
        attachScreenshot(named: "listen-modes")

        let done = app.buttons["playerDone"]
        swipes = 0
        while !(done.exists && done.isHittable) && swipes < 6 {
            app.swipeDown()
            swipes += 1
        }
        if done.exists && done.isHittable {
            done.tap()
        }
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.buttons["playerPlayPause"]
        )
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "The player sheet did not close")

        // The bar opened the reader, so go back to the surah list first.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if !app.buttons["suraRow-2"].exists && back.exists {
            back.tap()
        }
        let second = app.buttons["suraRow-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 10), "The second surah row did not appear")
        second.tap()
        XCTAssertTrue(app.buttons["readerPlaySurah"].waitForExistence(timeout: 20), "The reader does not offer Play this surah")
        XCTAssertTrue(app.descendants(matching: .any)["nowPlayingBar"].exists, "The now playing bar is missing in the reader")
        app.terminate()
    }

    /// "Play from this ayah" in the ayah dialog starts this surah in the player.
    @MainActor
    func testReaderPlaysFromAnAyah() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSFakeListen"]
        app.launch()

        let tab = app.tabBars.buttons["Quran"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Quran tab button did not appear")
        tab.tap()
        XCTAssertTrue(app.buttons["listenReciterButton"].waitForExistence(timeout: 20), "The fake reciters did not load")

        let firstSura = app.buttons["suraRow-1"]
        XCTAssertTrue(firstSura.waitForExistence(timeout: 20), "The sura list did not load")
        firstSura.tap()

        let ayah = app.buttons["ayah-2"]
        XCTAssertTrue(ayah.waitForExistence(timeout: 20), "Ayah 2 did not appear")
        ayah.tap()

        // Dialog buttons may not keep their identifier, so the label prefix is the fallback.
        let byIdentifier = app.buttons.matching(identifier: "toolbarPlay").firstMatch
        let byLabel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play from")).firstMatch
        var found = false
        let deadline = Date().addingTimeInterval(10)
        while !found && Date() < deadline {
            found = byIdentifier.exists || byLabel.exists
            if !found {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        XCTAssertTrue(found, "The ayah toolbar has no Play button")
        if byIdentifier.exists {
            byIdentifier.tap()
        } else {
            byLabel.tap()
        }

        let bar = app.descendants(matching: .any)["nowPlayingBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "The now playing bar did not appear")
        attachScreenshot(named: "reader-play-from")
        app.terminate()
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
