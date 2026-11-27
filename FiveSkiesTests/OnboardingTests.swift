import XCTest
@testable import FiveSkies

final class OnboardingTests: XCTestCase {
    private func gate(
        completed: Bool = false,
        fixedPhase: Bool = false,
        unitTestHost: Bool = false,
        forced: Bool = false
    ) -> OnboardingGate {
        OnboardingGate(
            isCompleted: completed,
            isFixedPhase: fixedPhase,
            isUnitTestHost: unitTestHost,
            isForced: forced
        )
    }

    // MARK: - When it shows

    func testShowsOnFirstLaunch() {
        XCTAssertTrue(gate().shouldShow)
    }

    func testHiddenOnceCompleted() {
        XCTAssertFalse(gate(completed: true).shouldShow)
    }

    func testNeverShowsInFixedPhaseMode() {
        XCTAssertFalse(gate(fixedPhase: true).shouldShow)
    }

    func testNeverShowsInUnitTestHost() {
        XCTAssertFalse(gate(unitTestHost: true).shouldShow)
    }

    func testShowArgumentWinsOverEverything() {
        XCTAssertTrue(gate(forced: true).shouldShow)
        XCTAssertTrue(gate(fixedPhase: true, forced: true).shouldShow)
        XCTAssertTrue(gate(completed: true, fixedPhase: true, forced: true).shouldShow)
        XCTAssertTrue(gate(unitTestHost: true, forced: true).shouldShow)
    }

    func testLiveGateStaysHiddenInThisTestHost() {
        XCTAssertFalse(OnboardingGate.live().shouldShow)
        XCTAssertFalse(OnboardingGate.live().requestsPermissions)
    }

    // MARK: - What it may do

    func testRealFirstRunMayAskForPermissionsAndRecordsCompletion() {
        let real = gate()
        XCTAssertTrue(real.requestsPermissions)
        XCTAssertTrue(real.recordsCompletion)
    }

    func testScreenshotModeNeverAsksAndRecordsNothing() {
        let screenshots = gate(fixedPhase: true, forced: true)
        XCTAssertFalse(screenshots.requestsPermissions)
        XCTAssertFalse(screenshots.recordsCompletion)
        XCTAssertFalse(gate(forced: true).requestsPermissions, "The show argument alone also asks for nothing")
    }

    // MARK: - Reading launch state

    func testReadsCompletionFromDefaultsAndArguments() throws {
        let suiteName = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let launch = LaunchOptions()
        let before = OnboardingGate(defaults: defaults, launch: launch, arguments: [])
        XCTAssertFalse(before.isCompleted)
        XCTAssertFalse(before.isForced)

        OnboardingGate.markCompleted(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: "onboarding.completed"))
        let after = OnboardingGate(defaults: defaults, launch: launch, arguments: [])
        XCTAssertTrue(after.isCompleted)

        let forced = OnboardingGate(
            defaults: defaults,
            launch: launch,
            arguments: ["-FSFixedPhase", "isha", "-FSShowOnboarding"]
        )
        XCTAssertTrue(forced.isForced)
        XCTAssertTrue(forced.shouldShow)
    }

    // MARK: - Pages

    func testAtMostFourPagesInOrder() {
        XCTAssertLessThanOrEqual(OnboardingPage.allCases.count, 4)
        XCTAssertEqual(OnboardingPage.allCases, [.welcome, .location, .alerts, .done])
        XCTAssertEqual(OnboardingPage.welcome.next, .location)
        XCTAssertEqual(OnboardingPage.location.next, .alerts)
        XCTAssertEqual(OnboardingPage.alerts.next, .done)
        XCTAssertNil(OnboardingPage.done.next)
        XCTAssertNil(OnboardingPage.welcome.previous)
        XCTAssertTrue(OnboardingPage.done.isLast)
        XCTAssertEqual(OnboardingPage.allCases.map(\.number), [1, 2, 3, 4])
    }

    func testEachPageHasItsOwnSky() {
        let skies = OnboardingPage.allCases.map(\.sky)
        XCTAssertEqual(skies, [.fajr, .dhuhr, .maghrib, .isha])
        XCTAssertEqual(Set(skies).count, skies.count)
    }

    func testButtonIdentifiers() {
        XCTAssertEqual(OnboardingPage.welcome.primaryIdentifier, "onboardingNext")
        XCTAssertEqual(OnboardingPage.location.primaryIdentifier, "onboardingNext")
        XCTAssertEqual(OnboardingPage.alerts.primaryIdentifier, "onboardingNext")
        XCTAssertEqual(OnboardingPage.done.primaryIdentifier, "onboardingDone")
        XCTAssertEqual(OnboardingPage.alerts.primaryTitle, "Allow alerts")
    }

    func testLocationReasonMatchesUsageDescription() throws {
        let reason = OnboardingPage.location.message
        XCTAssertTrue(reason.contains("calculated on your iPhone"))
        XCTAssertTrue(reason.contains("never sent to us"))
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String else {
            throw XCTSkip("The app Info.plist is not visible from this test host")
        }
        XCTAssertTrue(usage.contains("never sent to us"))
        XCTAssertTrue(usage.contains("prayer times"))
    }

    func testCopyIsPlainAndShort() {
        for page in OnboardingPage.allCases {
            let texts = [page.title, page.message, page.primaryTitle, page.secondaryTitle ?? ""]
            for text in texts {
                XCTAssertFalse(text.contains("\u{2014}"), "No em dashes: \(text)")
                XCTAssertFalse(text.lowercased().contains("missed"), "No shame words: \(text)")
            }
            XCTAssertLessThanOrEqual(page.message.count, 180, "Keep \(page) short")
        }
    }
}
