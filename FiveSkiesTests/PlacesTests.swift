import XCTest
@testable import FiveSkies

final class PlacesTests: XCTestCase {
    private let origin = Coordinate(latitude: 40, longitude: -74)

    // MARK: - Distance maths

    func testDistanceIsZeroAtTheSamePoint() {
        XCTAssertEqual(PlaceDistance.metres(from: origin, to: origin), 0, accuracy: 0.001)
    }

    func testOneDegreeOfLatitudeIsAbout111Kilometres() {
        let north = Coordinate(latitude: 41, longitude: -74)
        // pi * 6371 km / 180 = 111.195 km.
        XCTAssertEqual(PlaceDistance.metres(from: origin, to: north), 111_195, accuracy: 10)
    }

    func testDistanceIsSymmetric() {
        let other = Coordinate(latitude: 40.05, longitude: -73.9)
        XCTAssertEqual(
            PlaceDistance.metres(from: origin, to: other),
            PlaceDistance.metres(from: other, to: origin),
            accuracy: 0.001
        )
    }

    func testLongitudeShrinksAwayFromTheEquator() {
        let atEquator = PlaceDistance.metres(
            from: Coordinate(latitude: 0, longitude: 0),
            to: Coordinate(latitude: 0, longitude: 1)
        )
        let atSixty = PlaceDistance.metres(
            from: Coordinate(latitude: 60, longitude: 0),
            to: Coordinate(latitude: 60, longitude: 1)
        )
        // At 60 degrees a degree of longitude is about half as long.
        XCTAssertEqual(atSixty / atEquator, 0.5, accuracy: 0.001)
    }

    // MARK: - Fake search and sorting

    func testFakeSearchSortsByDistanceAndComputesIt() async throws {
        let search = FakePlaceSearch(entries: [
            .init(name: "Far", coordinate: Coordinate(latitude: 40.03, longitude: -74), address: nil),
            .init(name: "Near", coordinate: Coordinate(latitude: 40.001, longitude: -74), address: "1 Main St"),
            .init(name: "Middle", coordinate: Coordinate(latitude: 40.01, longitude: -74), address: nil)
        ])
        let results = try await search.search(query: "mosque", near: origin, radius: 10_000)
        XCTAssertEqual(results.map(\.name), ["Near", "Middle", "Far"])
        XCTAssertEqual(results[0].distance, 111.195, accuracy: 0.5)
        XCTAssertEqual(results[1].distance, 1_111.95, accuracy: 1)
        XCTAssertEqual(results[2].distance, 3_335.85, accuracy: 2)
        XCTAssertEqual(results[0].address, "1 Main St")
    }

    func testSortingBreaksTiesByName() {
        let point = Coordinate(latitude: 1, longitude: 1)
        let places = [
            PlaceResult(name: "B", coordinate: point, distance: 50, address: nil, phone: nil, url: nil),
            PlaceResult(name: "A", coordinate: point, distance: 50, address: nil, phone: nil, url: nil),
            PlaceResult(name: "C", coordinate: point, distance: 10, address: nil, phone: nil, url: nil)
        ]
        XCTAssertEqual(PlaceDistance.sorted(places).map(\.name), ["C", "A", "B"])
    }

    func testSamplesAreGenericSortedAndDeterministic() async throws {
        let mosques = try await FakePlaceSearch.samples(for: .mosques)
            .search(query: PlaceKind.mosques.query, near: FakePlaceSearch.sampleOrigin, radius: PlaceKind.searchRadius)
        XCTAssertEqual(mosques.map(\.name), ["Sample mosque 1", "Sample mosque 2", "Sample mosque 3"])
        XCTAssertTrue(mosques.allSatisfy { $0.phone == nil && $0.url == nil })

        let halal = try await FakePlaceSearch.samples(for: .halal)
            .search(query: PlaceKind.halal.query, near: FakePlaceSearch.sampleOrigin, radius: PlaceKind.searchRadius)
        XCTAssertEqual(halal.map(\.name), ["Sample restaurant 1", "Sample restaurant 2", "Sample restaurant 3"])
        XCTAssertEqual(halal.map(\.distance), mosques.map(\.distance))
    }

    func testQueries() {
        XCTAssertEqual(PlaceKind.mosques.query, "mosque")
        XCTAssertEqual(PlaceKind.halal.query, "halal restaurant")
        XCTAssertEqual(PlaceKind.searchRadius, 10_000)
    }

    func testDistanceTextIsNotEmpty() {
        XCTAssertFalse(PlaceFormatting.distanceText(1_250).isEmpty)
    }

    // MARK: - Model

    @MainActor
    func testModelPublishesSortedResults() async {
        let search = FakePlaceSearch(entries: [
            .init(name: "Far", coordinate: Coordinate(latitude: 40.02, longitude: -74), address: nil),
            .init(name: "Near", coordinate: Coordinate(latitude: 40.002, longitude: -74), address: nil)
        ])
        let model = PlacesSearchModel(searcher: search, query: "mosque")
        XCTAssertEqual(model.outcome, .idle)
        await model.run(near: origin)
        guard case .found(let places) = model.outcome else {
            return XCTFail("Expected results, got \(model.outcome)")
        }
        XCTAssertEqual(places.map(\.name), ["Near", "Far"])
    }

    @MainActor
    func testModelReportsFailure() async {
        let model = PlacesSearchModel(searcher: FakePlaceSearch(entries: [], fails: true), query: "mosque")
        await model.run(near: origin)
        XCTAssertEqual(model.outcome, .failed)
    }

    @MainActor
    func testModelReportsEmpty() async {
        let model = PlacesSearchModel(searcher: FakePlaceSearch(entries: []), query: "mosque")
        await model.run(near: origin)
        XCTAssertEqual(model.outcome, .found([]))
    }

    // MARK: - Screen state

    private func resolve(
        samples: Bool = false,
        denied: Bool = false,
        awaiting: Bool = false,
        coordinate: Bool = true,
        outcome: PlacesSearchOutcome = .idle
    ) -> PlacesScreenState {
        PlacesScreenState.resolve(
            usesSamples: samples,
            isDenied: denied,
            isAwaitingFix: awaiting,
            hasCoordinate: coordinate,
            outcome: outcome
        )
    }

    func testStateWithoutLocation() {
        XCTAssertEqual(resolve(denied: true, coordinate: false), .needsPermission)
        XCTAssertEqual(resolve(awaiting: true, coordinate: false), .locating)
        XCTAssertEqual(resolve(awaiting: false, coordinate: false), .locationFailed)
    }

    func testStateFollowsTheSearch() {
        let place = PlaceResult(name: "A", coordinate: origin, distance: 1, address: nil, phone: nil, url: nil)
        XCTAssertEqual(resolve(outcome: .idle), .searching)
        XCTAssertEqual(resolve(outcome: .searching), .searching)
        XCTAssertEqual(resolve(outcome: .found([])), .empty)
        XCTAssertEqual(resolve(outcome: .found([place])), .results([place]))
        XCTAssertEqual(resolve(outcome: .failed), .searchFailed)
    }

    func testSampleModeIgnoresLocation() {
        XCTAssertEqual(resolve(samples: true, denied: true, coordinate: false, outcome: .searching), .searching)
        XCTAssertEqual(resolve(samples: true, denied: true, coordinate: false, outcome: .found([])), .empty)
    }
}
