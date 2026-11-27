import CoreGraphics
import XCTest
@testable import FiveSkies

final class TimetableTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier))
    }

    private func newYork() throws -> Place {
        Place(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            timeZone: try zone("America/New_York"),
            isFallback: false
        )
    }

    private func service() -> PrayerTimesService {
        PrayerTimesService().applying(method: .northAmerica, asrRule: .standard)
    }

    private func builder(_ place: Place, adjustment: Int = 0) -> TimetableBuilder {
        TimetableBuilder(place: place, service: service(), hijriAdjustment: adjustment, locale: posix)
    }

    private func hour(_ date: Date, in place: Place) -> Int {
        place.calendar.component(.hour, from: date)
    }

    // MARK: - Row counts

    func testRowCountPerMonth() throws {
        let timetable = builder(try newYork())
        XCTAssertEqual(timetable.month(year: 2026, month: 1).rows.count, 31)
        XCTAssertEqual(timetable.month(year: 2026, month: 4).rows.count, 30)
        XCTAssertEqual(timetable.month(year: 2026, month: 2).rows.count, 28)
        XCTAssertEqual(timetable.month(year: 2028, month: 2).rows.count, 29, "2028 is a leap year")
        XCTAssertEqual(timetable.month(year: 2100, month: 2).rows.count, 28, "2100 is not a leap year")
    }

    func testYearHasTwelveMonthsAndEveryDay() throws {
        let timetable = builder(Place.makkahFallback)
        let leap = timetable.year(2028)
        XCTAssertEqual(leap.count, 12)
        XCTAssertEqual(leap.map(\.month), Array(1...12))
        XCTAssertEqual(leap.reduce(0) { $0 + $1.rows.count }, 366)
        XCTAssertEqual(timetable.year(2026).reduce(0) { $0 + $1.rows.count }, 365)
    }

    func testMonthScopeGivesOneMonthAndYearScopeTwelve() throws {
        let timetable = builder(Place.makkahFallback)
        let selection = TimetableSelection(year: 2026, month: 12)
        let single = timetable.months(for: selection, scope: .month)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single.first?.month, 12)
        XCTAssertEqual(single.first?.title, "December 2026")
        XCTAssertEqual(timetable.months(for: selection, scope: .year).count, 12)
    }

    func testRowsAreConsecutiveDaysOfTheMonthInThePlaceZone() throws {
        let place = try newYork()
        let rows = builder(place).month(year: 2026, month: 3).rows
        XCTAssertEqual(rows.map(\.gregorianDay), Array(1...31))
        for row in rows {
            let parts = place.calendar.dateComponents([.year, .month, .day], from: row.date)
            XCTAssertEqual(parts.year, 2026)
            XCTAssertEqual(parts.month, 3)
            XCTAssertEqual(parts.day, row.gregorianDay)
        }
        XCTAssertEqual(rows.first?.weekdayName, "Sun", "1 March 2026 is a Sunday")
    }

    // MARK: - Times

    func testTimesMatchTheService() throws {
        let place = try newYork()
        let rows = builder(place).month(year: 2026, month: 7).rows
        for row in rows {
            let day = try XCTUnwrap(service().prayerDay(for: place, on: row.date))
            XCTAssertEqual(row.fajr, day.fajr)
            XCTAssertEqual(row.sunrise, day.sunrise)
            XCTAssertEqual(row.dhuhr, day.dhuhr)
            XCTAssertEqual(row.asr, day.asr)
            XCTAssertEqual(row.maghrib, day.maghrib)
            XCTAssertEqual(row.isha, day.isha)
        }
    }

    func testTimesFallOnTheRowDayInNewYorkTime() throws {
        let place = try newYork()
        let rows = builder(place).month(year: 2026, month: 7).rows
        XCTAssertEqual(rows.count, 31)
        for row in rows {
            XCTAssertTrue(place.calendar.isDate(row.fajr, inSameDayAs: row.date))
            XCTAssertTrue(place.calendar.isDate(row.isha, inSameDayAs: row.date))
            XCTAssertTrue((3...5).contains(hour(row.fajr, in: place)), "Fajr in July is before dawn in New York")
            XCTAssertTrue((12...13).contains(hour(row.dhuhr, in: place)), "Dhuhr is just after 1 pm daylight time")
            XCTAssertEqual(hour(row.maghrib, in: place), 20, "Sunset in July is after 8 pm daylight time")
            XCTAssertEqual(row.times, [row.fajr, row.sunrise, row.dhuhr, row.asr, row.maghrib, row.isha])
        }
    }

    func testTimesFallOnTheRowDayInMakkahTime() throws {
        let place = Place.makkahFallback
        for month in [1, 6, 12] {
            for row in builder(place).month(year: 2026, month: month).rows {
                XCTAssertTrue(place.calendar.isDate(row.fajr, inSameDayAs: row.date))
                XCTAssertTrue((4...5).contains(hour(row.fajr, in: place)))
                XCTAssertTrue((11...12).contains(hour(row.dhuhr, in: place)))
                XCTAssertTrue((17...19).contains(hour(row.maghrib, in: place)))
            }
        }
    }

    func testTimeFormatUsesThePlaceZone() throws {
        let place = try newYork()
        let row = try XCTUnwrap(builder(place).month(year: 2026, month: 7).rows.first)
        let twentyFour = TimetableTimeFormat(timeZone: place.timeZone, locale: Locale(identifier: "en_GB"), includesPeriod: true)
        XCTAssertFalse(twentyFour.usesTwelveHourClock)
        XCTAssertTrue(twentyFour.string(row.maghrib).hasPrefix("20:"), twentyFour.string(row.maghrib))

        let twelve = TimetableTimeFormat(timeZone: place.timeZone, locale: Locale(identifier: "en_US"), includesPeriod: true)
        XCTAssertTrue(twelve.usesTwelveHourClock)
        XCTAssertTrue(twelve.string(row.maghrib).hasPrefix("8:"), twelve.string(row.maghrib))
        XCTAssertTrue(twelve.string(row.maghrib).hasSuffix("PM"), twelve.string(row.maghrib))

        let short = TimetableTimeFormat(timeZone: place.timeZone, locale: Locale(identifier: "en_US"), includesPeriod: false)
        XCTAssertFalse(short.string(row.maghrib).contains("PM"))
    }

    // MARK: - Hijri column

    func testHijriColumnMatchesUmmAlQura() throws {
        let place = Place.makkahFallback
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = place.timeZone
        for row in builder(place).month(year: 2026, month: 11).rows {
            XCTAssertEqual(row.hijriDay, hijri.component(.day, from: row.date))
            XCTAssertTrue((1...30).contains(row.hijriDay))
        }
    }

    func testHijriAdjustmentShiftsTheColumnByWholeDays() throws {
        let place = try newYork()
        let base = builder(place, adjustment: 0).month(year: 2026, month: 3).rows
        let plusOne = builder(place, adjustment: 1).month(year: 2026, month: 3).rows
        let minusTwo = builder(place, adjustment: -2).month(year: 2026, month: 3).rows
        XCTAssertEqual(base.count, plusOne.count)
        for index in 0..<(base.count - 1) {
            XCTAssertEqual(plusOne[index].hijriDay, base[index + 1].hijriDay)
        }
        for index in 2..<base.count {
            XCTAssertEqual(minusTwo[index].hijriDay, base[index - 2].hijriDay)
        }
        // The adjustment changes only the Hijri column.
        XCTAssertEqual(base.map(\.fajr), plusOne.map(\.fajr))
    }

    func testHijriTitleNamesTheHijriMonths() throws {
        let month = builder(Place.makkahFallback).month(year: 2026, month: 12)
        XCTAssertTrue(month.hijriTitle.hasSuffix(" AH"), month.hijriTitle)
        XCTAssertFalse(month.hijriTitle.isEmpty)
    }

    // MARK: - Labels and selection

    func testPlaceLabels() {
        XCTAssertEqual(TimetableBuilder.placeLabel(for: .makkahFallback), "Makkah (default)")
        let device = Place.device(Coordinate(latitude: 40.7128, longitude: -74.0060))
        XCTAssertEqual(TimetableBuilder.placeLabel(for: device), "Your location (40.71, -74.01)")
    }

    func testSelectionSteps() {
        let december = TimetableSelection(year: 2026, month: 12)
        XCTAssertEqual(december.stepped(by: 1, scope: .month), TimetableSelection(year: 2027, month: 1))
        XCTAssertEqual(december.stepped(by: -11, scope: .month), TimetableSelection(year: 2026, month: 1))
        XCTAssertEqual(TimetableSelection(year: 2026, month: 1).stepped(by: -1, scope: .month), TimetableSelection(year: 2025, month: 12))
        XCTAssertEqual(december.stepped(by: 1, scope: .year), TimetableSelection(year: 2027, month: 12))
    }

    func testFileNames() {
        let selection = TimetableSelection(year: 2026, month: 3)
        XCTAssertEqual(TimetablePDF.fileName(for: selection, scope: .month), "Five Skies timetable 2026-03.pdf")
        XCTAssertEqual(TimetablePDF.fileName(for: selection, scope: .year), "Five Skies timetable 2026.pdf")
    }

    // MARK: - PDF

    private func pageCount(_ data: Data) throws -> Int {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        return document.numberOfPages
    }

    private func info() throws -> TimetableDocumentInfo {
        TimetableDocumentInfo(
            placeLabel: "Makkah (default)",
            methodName: PrayerCalculationMethod.northAmerica.displayName,
            asrRuleName: AsrRule.standard.displayName,
            timeZone: try zone("Asia/Riyadh"),
            locale: posix
        )
    }

    func testPDFHasOnePagePerMonthOnUSLetter() throws {
        let timetable = builder(Place.makkahFallback)
        let monthData = TimetablePDF.data(months: [timetable.month(year: 2026, month: 2)], info: try info())
        XCTAssertEqual(try pageCount(monthData), 1)

        let yearData = TimetablePDF.data(months: timetable.year(2026), info: try info())
        XCTAssertEqual(try pageCount(yearData), 12)

        let provider = try XCTUnwrap(CGDataProvider(data: yearData as CFData))
        let page = try XCTUnwrap(CGPDFDocument(provider)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 612, accuracy: 0.5)
        XCTAssertEqual(box.height, 792, accuracy: 0.5)
    }

    func testWriteFileGoesToTheTemporaryDirectory() throws {
        let timetable = builder(Place.makkahFallback)
        let url = try TimetablePDF.writeFile(
            months: [timetable.month(year: 2026, month: 12)],
            info: try info(),
            fileName: "Timetable test.pdf"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try pageCount(try Data(contentsOf: url)), 1)
    }
}
