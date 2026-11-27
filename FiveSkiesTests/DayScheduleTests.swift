import XCTest
@testable import FiveSkies

final class DayScheduleTests: XCTestCase {
    private func newYork() throws -> (place: Place, date: Date, service: PrayerTimesService) {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let place = Place(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            timeZone: zone,
            isFallback: false
        )
        let date = try XCTUnwrap(place.calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))
        return (place, date, PrayerTimesService(timeZone: zone))
    }

    private func makeSchedule() throws -> DaySchedule {
        let fixture = try newYork()
        return try XCTUnwrap(fixture.service.daySchedule(for: fixture.place, on: fixture.date))
    }

    // MARK: Windows

    func testPrayerWindowsRunToTheNextBoundary() throws {
        let schedule = try makeSchedule()
        let day = schedule.day

        let fajr = schedule.window(of: .fajr, ishaEnd: .middleOfNight)
        XCTAssertEqual(fajr.start, day.fajr)
        XCTAssertEqual(fajr.end, day.sunrise, "Fajr ends at sunrise")

        XCTAssertEqual(schedule.window(of: .dhuhr, ishaEnd: .fajr), DateInterval(start: day.dhuhr, end: day.asr))
        XCTAssertEqual(schedule.window(of: .asr, ishaEnd: .fajr), DateInterval(start: day.asr, end: day.maghrib))
        XCTAssertEqual(schedule.window(of: .maghrib, ishaEnd: .fajr), DateInterval(start: day.maghrib, end: day.isha))
    }

    func testIshaEndsByTheChosenRule() throws {
        let schedule = try makeSchedule()
        let day = schedule.day

        let middle = schedule.window(of: .isha, ishaEnd: .middleOfNight)
        XCTAssertEqual(middle.start, day.isha)
        XCTAssertEqual(middle.end, schedule.middleOfNight)

        let fajr = schedule.window(of: .isha, ishaEnd: .fajr)
        XCTAssertEqual(fajr.start, day.isha)
        XCTAssertEqual(fajr.end, day.tomorrowFajr)

        XCTAssertLessThan(middle.end, fajr.end)
    }

    func testWindowRulesOnAFixedDay() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }
        let day = PrayerDay(
            fajr: at(5), sunrise: at(6.5), dhuhr: at(12), asr: at(15.5),
            maghrib: at(18), isha: at(19.5), tomorrowFajr: at(29)
        )
        let schedule = DaySchedule.make(day: day, middleOfNight: at(23.5), lastThirdOfNight: at(25.33))

        XCTAssertEqual(schedule.window(of: .fajr, ishaEnd: .fajr), DateInterval(start: at(5), end: at(6.5)))
        XCTAssertEqual(schedule.window(of: .isha, ishaEnd: .middleOfNight), DateInterval(start: at(19.5), end: at(23.5)))
        XCTAssertEqual(schedule.window(of: .isha, ishaEnd: .fajr), DateInterval(start: at(19.5), end: at(29)))
        XCTAssertEqual(schedule.suhurEnds, at(5))
        XCTAssertEqual(schedule.iftar, at(18))
    }

    // MARK: Discouraged windows and Duha

    func testDiscouragedWindowsSitAtTheConfiguredOffsets() throws {
        let schedule = try makeSchedule()
        let day = schedule.day
        XCTAssertEqual(schedule.discouraged.map(\.kind), [.sunrise, .zenith, .sunset])

        let sunrise = schedule.discouraged[0].interval
        XCTAssertEqual(sunrise.start, day.sunrise)
        XCTAssertEqual(sunrise.duration, DayDefinitions.afterSunriseMinutes * 60, accuracy: 0.001)

        let zenith = schedule.discouraged[1].interval
        XCTAssertEqual(zenith.end, day.dhuhr)
        XCTAssertEqual(zenith.duration, DayDefinitions.beforeDhuhrMinutes * 60, accuracy: 0.001)

        let sunset = schedule.discouraged[2].interval
        XCTAssertEqual(sunset.end, day.maghrib)
        XCTAssertEqual(sunset.duration, DayDefinitions.beforeMaghribMinutes * 60, accuracy: 0.001)
    }

    func testDuhaSitsBetweenTheMorningDiscouragedWindows() throws {
        let schedule = try makeSchedule()
        let afterSunrise = schedule.discouraged[0].interval
        let beforeDhuhr = schedule.discouraged[1].interval

        XCTAssertEqual(schedule.duha.start, afterSunrise.end)
        XCTAssertEqual(schedule.duha.end, beforeDhuhr.start)
        XCTAssertGreaterThan(schedule.duha.start, schedule.day.sunrise)
        XCTAssertLessThan(schedule.duha.end, schedule.day.dhuhr)
        XCTAssertGreaterThan(schedule.duha.duration, 0)
    }

    // MARK: Night

    func testLastThirdFollowsTheMiddleOfTheNightAndPrecedesFajr() throws {
        let schedule = try makeSchedule()
        let day = schedule.day

        XCTAssertGreaterThan(schedule.middleOfNight, day.maghrib)
        XCTAssertGreaterThan(schedule.lastThirdOfNight, schedule.middleOfNight)
        XCTAssertLessThan(schedule.lastThirdOfNight, day.tomorrowFajr)
    }

    // MARK: Rows

    func testPrayerRowsListTheFivePrayersAndSunriseInOrder() throws {
        let schedule = try makeSchedule()
        let rows = DayViewContent.prayerRows(for: schedule, ishaEnd: .middleOfNight)
        XCTAssertEqual(rows.map(\.id), ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"])
        XCTAssertNil(rows[1].end, "Sunrise is a single moment")
        XCTAssertEqual(rows[0].end, schedule.day.sunrise)
        XCTAssertEqual(rows[5].end, schedule.middleOfNight)

        let fajrRule = DayViewContent.prayerRows(for: schedule, ishaEnd: .fajr)
        XCTAssertEqual(fajrRule[5].end, schedule.day.tomorrowFajr)
    }

    func testRowsReadAsOneSentence() throws {
        let fixture = try newYork()
        let schedule = try makeSchedule()
        let format = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_US"), timeZone: fixture.place.timeZone)
        let rows = DayViewContent.prayerRows(for: schedule, ishaEnd: .middleOfNight)

        let fajr = rows[0].spokenText(format)
        XCTAssertTrue(fajr.hasPrefix("Fajr, "), fajr)
        XCTAssertTrue(fajr.contains(" to "), fajr)

        let sunrise = rows[1].spokenText(format)
        XCTAssertTrue(sunrise.hasPrefix("Sunrise, "), sunrise)
        XCTAssertFalse(sunrise.contains(" to "), sunrise)
    }

    func testCurrentRowIsThePrayerWhoseWindowHoldsNow() throws {
        let schedule = try makeSchedule()
        let day = schedule.day
        let rows = DayViewContent.prayerRows(for: schedule, ishaEnd: .middleOfNight)

        XCTAssertEqual(DayViewContent.currentRowID(in: rows, at: day.dhuhr.addingTimeInterval(60)), "dhuhr")
        XCTAssertEqual(DayViewContent.currentRowID(in: rows, at: day.fajr), "fajr")
        XCTAssertNil(DayViewContent.currentRowID(in: rows, at: day.fajr.addingTimeInterval(-60)))
        XCTAssertNil(DayViewContent.currentRowID(in: rows, at: day.sunrise.addingTimeInterval(3600)))
        XCTAssertEqual(DayViewContent.currentRowID(in: rows, at: day.isha.addingTimeInterval(60)), "isha")
    }

    func testExtraRowsUseTheScheduleTimes() throws {
        let schedule = try makeSchedule()
        XCTAssertEqual(DayViewContent.duhaRow(for: schedule).end, schedule.duha.end)
        XCTAssertEqual(
            DayViewContent.discouragedRows(for: schedule).map(\.title),
            DiscouragedKind.allCases.map(\.displayName)
        )
        XCTAssertEqual(DayViewContent.nightRows(for: schedule).map(\.start), [schedule.middleOfNight, schedule.lastThirdOfNight])
        XCTAssertEqual(DayViewContent.fastingRows(for: schedule).map(\.start), [schedule.day.fajr, schedule.day.maghrib])
    }

    // MARK: Hijri adjustment

    func testHijriAdjustmentShiftsTheDay() throws {
        let fixture = try newYork()
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = fixture.place.timeZone
        let parts: Set<Calendar.Component> = [.year, .month, .day]

        for adjustment in AppSettings.hijriAdjustmentRange {
            let shifted = DayHijriDate.adjustedDate(fixture.date, adjustment: adjustment, calendar: fixture.place.calendar)
            let expected = try XCTUnwrap(hijri.date(byAdding: .day, value: adjustment, to: fixture.date))
            XCTAssertEqual(
                hijri.dateComponents(parts, from: shifted),
                hijri.dateComponents(parts, from: expected),
                "adjustment \(adjustment)"
            )
        }

        let plain = DayHijriDate.text(for: fixture.date, adjustment: 0, timeZone: fixture.place.timeZone)
        let moved = DayHijriDate.text(for: fixture.date, adjustment: 1, timeZone: fixture.place.timeZone)
        XCTAssertTrue(plain.hasSuffix(" AH"), plain)
        XCTAssertNotEqual(plain, moved)
    }

    func testHijriAdjustmentText() {
        XCTAssertEqual(DayViewContent.hijriAdjustmentText(0), "No change")
        XCTAssertEqual(DayViewContent.hijriAdjustmentText(1), "+1 day")
        XCTAssertEqual(DayViewContent.hijriAdjustmentText(2), "+2 days")
        XCTAssertEqual(DayViewContent.hijriAdjustmentText(-1), "-1 day")
        XCTAssertEqual(DayViewContent.hijriAdjustmentText(-2), "-2 days")
    }
}
