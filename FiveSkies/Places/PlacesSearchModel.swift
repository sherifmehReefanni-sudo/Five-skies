import Foundation

/// Where one search stands.
enum PlacesSearchOutcome: Equatable {
    case idle
    case searching
    case found([PlaceResult])
    case failed
}

/// Everything a places screen can show, worked out from location and search.
enum PlacesScreenState: Equatable {
    case locating
    case searching
    case results([PlaceResult])
    case empty
    case needsPermission
    case locationFailed
    case searchFailed

    /// The single rule for what to show.
    /// - usesSamples: the fixed screenshot mode, where location is never used.
    /// - isDenied: location permission was refused or is restricted.
    /// - isAwaitingFix: a location fix may still arrive.
    /// - hasCoordinate: a coordinate is known.
    static func resolve(
        usesSamples: Bool,
        isDenied: Bool,
        isAwaitingFix: Bool,
        hasCoordinate: Bool,
        outcome: PlacesSearchOutcome
    ) -> PlacesScreenState {
        if !usesSamples {
            if isDenied {
                return .needsPermission
            }
            if !hasCoordinate {
                return isAwaitingFix ? .locating : .locationFailed
            }
        }
        switch outcome {
        case .idle, .searching:
            return .searching
        case .found(let places):
            return places.isEmpty ? .empty : .results(places)
        case .failed:
            return .searchFailed
        }
    }
}

/// Runs one search at a time for a places screen and publishes the outcome.
final class PlacesSearchModel: ObservableObject {
    @Published private(set) var outcome: PlacesSearchOutcome = .idle

    let query: String
    let radius: Double
    private let searcher: PlaceSearching
    private var lastOrigin: Coordinate?
    private var task: Task<Void, Never>?

    init(searcher: PlaceSearching, query: String, radius: Double = PlaceKind.searchRadius) {
        self.searcher = searcher
        self.query = query
        self.radius = radius
    }

    deinit {
        task?.cancel()
    }

    /// Searches around `origin`, unless the same origin already has a result or a search in flight.
    @MainActor
    func search(near origin: Coordinate) {
        if origin == lastOrigin, outcome != .failed, outcome != .idle {
            return
        }
        start(near: origin)
    }

    /// Searches again around the last origin.
    @MainActor
    func retry() {
        guard let origin = lastOrigin else { return }
        start(near: origin)
    }

    /// Runs the search and waits for it. Used by `search(near:)` and by tests.
    @MainActor
    func run(near origin: Coordinate) async {
        start(near: origin)
        await task?.value
    }

    @MainActor
    private func start(near origin: Coordinate) {
        task?.cancel()
        lastOrigin = origin
        outcome = .searching
        let searcher = self.searcher
        let query = self.query
        let radius = self.radius
        task = Task { @MainActor [weak self] in
            do {
                let places = try await searcher.search(query: query, near: origin, radius: radius)
                guard !Task.isCancelled else { return }
                self?.outcome = .found(PlaceDistance.sorted(places))
            } catch {
                guard !Task.isCancelled else { return }
                self?.outcome = .failed
            }
        }
    }
}
