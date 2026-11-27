import XCTest
@testable import FiveSkies

/// The offline city list: parsing, nearest city, the 50 km limit, band widening, the +-180 seam,
/// and a missing file. Small in-memory samples only, never the real bundled list.
final class CityIndexTests: XCTestCase {
    private let sample = """
    Edison\tUS\t40.5187\t-74.4121
    New York City\tUS\t40.7143\t-74.0060

    Sao Paulo\tBR\t-23.5475\t-46.6361\r
    broken line without tabs
    Too\tMany\t1.0\t2.0\textra
    Bad Number\tXX\tnorth\t2.0
    Out Of Range\tXX\t95.0\t2.0
    Null Island Town\t\t0.0000\t0.0000
    """

    // MARK: Parsing

    func testParseKeepsGoodRowsSortedByLatitude() {
        let index = CityIndex.parse(sample)
        XCTAssertEqual(index.cities.map(\.name), ["Sao Paulo", "Null Island Town", "Edison", "New York City"])
        let saoPaulo = index.cities[0]
        XCTAssertEqual(saoPaulo.countryCode, "BR")
        XCTAssertEqual(saoPaulo.latitude, -23.5475, accuracy: 1e-9)
        XCTAssertEqual(saoPaulo.longitude, -46.6361, accuracy: 1e-9)
        XCTAssertEqual(index.cities[1].displayName, "Null Island Town")
        XCTAssertEqual(index.cities[2].displayName, "Edison, US")
    }

    func testDistanceOfOneDegreeOfLatitude() {
        let metres = CityIndex.distance(from: Coordinate(latitude: 0, longitude: 0), to: Coordinate(latitude: 1, longitude: 0))
        XCTAssertEqual(metres, 111_195, accuracy: 10)
    }

    // MARK: Nearest

    func testNearestCityWithin50Kilometres() {
        let index = CityIndex.parse(sample)
        let nearEdison = Coordinate(latitude: 40.53, longitude: -74.39)
        XCTAssertEqual(index.nearest(to: nearEdison)?.displayName, "Edison, US")
        let midtown = Coordinate(latitude: 40.75, longitude: -73.99)
        XCTAssertEqual(index.nearest(to: midtown)?.displayName, "New York City, US")
    }

    func testNilBeyond50Kilometres() {
        let index = CityIndex(cities: [CityRecord(name: "Alpha", countryCode: "AA", latitude: 10, longitude: 20)])
        // 0.4 degrees north is about 44 km, 0.5 degrees about 56 km.
        XCTAssertEqual(index.nearest(to: Coordinate(latitude: 10.4, longitude: 20))?.name, "Alpha")
        XCTAssertNil(index.nearest(to: Coordinate(latitude: 10.5, longitude: 20)))
        // Mid-Atlantic, far from every sample city.
        XCTAssertNil(CityIndex.parse(sample).nearest(to: Coordinate(latitude: 30, longitude: -40)))
    }

    func testBandWidensWhenTheFirstBandIsEmpty() {
        let index = CityIndex(cities: [CityRecord(name: "North", countryCode: "NN", latitude: 5, longitude: 0)])
        let origin = Coordinate(latitude: 0, longitude: 0)
        XCTAssertNil(index.nearest(to: origin))
        XCTAssertEqual(index.nearest(to: origin, within: 1_000_000)?.name, "North")
    }

    func testBandWidensWhenTheBandCannotProveTheNearest() {
        // Far East sits inside the first band (0.9 degrees north) but about 3,300 km away;
        // Near sits outside it (1.5 degrees north) at about 167 km and is the true nearest.
        let index = CityIndex(cities: [
            CityRecord(name: "Far East", countryCode: "FE", latitude: 0.9, longitude: 30),
            CityRecord(name: "Near", countryCode: "NE", latitude: 1.5, longitude: 0),
        ])
        let origin = Coordinate(latitude: 0, longitude: 0)
        XCTAssertEqual(index.nearest(to: origin, within: 10_000_000)?.name, "Near")
        XCTAssertNil(index.nearest(to: origin))
    }

    func testLongitudeWrapNear180() {
        let index = CityIndex(cities: [
            CityRecord(name: "East Edge", countryCode: "EE", latitude: -18, longitude: 179.98),
            CityRecord(name: "Far West", countryCode: "FW", latitude: -18, longitude: 179.0),
        ])
        // Just across the seam, about 4 km from East Edge.
        let across = Coordinate(latitude: -18, longitude: -179.98)
        XCTAssertEqual(index.nearest(to: across)?.name, "East Edge")
        XCTAssertLessThan(CityIndex.distance(from: across, to: Coordinate(latitude: -18, longitude: 179.98)), 5_000)
    }

    func testEmptyIndexFindsNothing() {
        XCTAssertNil(CityIndex(cities: []).nearest(to: Coordinate(latitude: 0, longitude: 0)))
    }

    // MARK: Missing file

    func testMissingFileReturnsNil() throws {
        XCTAssertNil(CityIndex.load(contentsOf: nil))
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-cities-\(UUID().uuidString).tsv")
        XCTAssertNil(CityIndex.load(contentsOf: missing))

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("empty-cities-\(UUID().uuidString).tsv")
        try Data().write(to: empty)
        defer { try? FileManager.default.removeItem(at: empty) }
        XCTAssertNil(CityIndex.load(contentsOf: empty))
    }

    func testLoadReadsAWrittenFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cities-\(UUID().uuidString).tsv")
        try Data(sample.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let index = try XCTUnwrap(CityIndex.load(contentsOf: url))
        XCTAssertEqual(index.cities.count, 4)
    }

    // MARK: Provider

    func testProviderWithMissingListReturnsNil() async {
        let provider = PlaceNameProvider(loadIndex: { nil })
        let name = await provider.cityName(for: Place.device(Coordinate(latitude: 40.53, longitude: -74.39)))
        XCTAssertNil(name)
    }

    func testProviderNamesNearbyCityAndSkipsFallback() async {
        let text = sample
        let provider = PlaceNameProvider(loadIndex: { CityIndex.parse(text) })
        let fallback = await provider.cityName(for: Place.makkahFallback)
        XCTAssertNil(fallback)
        let edison = await provider.cityName(for: Place.device(Coordinate(latitude: 40.53, longitude: -74.39)))
        XCTAssertEqual(edison, "Edison, US")
        let again = await provider.cityName(for: Place.device(Coordinate(latitude: 40.531, longitude: -74.391)))
        XCTAssertEqual(again, "Edison, US")
        let ocean = await provider.cityName(for: Place.device(Coordinate(latitude: 30, longitude: -40)))
        XCTAssertNil(ocean)
    }

    func testCacheKeyRoundsToAboutOneKilometre() {
        XCTAssertEqual(PlaceNameProvider.cacheKey(for: Coordinate(latitude: 40.7128, longitude: -74.0060)), "40.71,-74.01")
    }
}
