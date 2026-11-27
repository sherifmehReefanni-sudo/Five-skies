import Foundation

/// One city from the bundled GeoNames list: Latin script name, two letter country code, position in degrees.
struct CityRecord: Equatable {
    let name: String
    let countryCode: String
    let latitude: Double
    let longitude: Double

    /// "Edison, US" style text, or the bare name when the country code is empty.
    var displayName: String {
        countryCode.isEmpty ? name : "\(name), \(countryCode)"
    }

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// The offline city list and its nearest-city lookup. Pure and synchronous: callers keep it off the main thread.
/// File format (written by tools/fetch_cities.py): one city per line, four tab-separated columns
/// name, country code, latitude, longitude, sorted by latitude.
struct CityIndex {
    static let resourceName = "cities15000"
    static let resourceExtension = "tsv"
    /// Beyond this, screens show "Your location" instead of a city that may be wrong.
    static let maxDistance: Double = 50_000
    static let earthRadius: Double = 6_371_000
    /// Half height, in degrees of latitude, of the first band scanned around the coordinate.
    static let initialBand: Double = 1

    /// Sorted by latitude, south to north.
    let cities: [CityRecord]

    init(cities: [CityRecord]) {
        self.cities = cities.sorted { $0.latitude < $1.latitude }
    }

    // MARK: Loading

    /// The bundled list, nil until the fetch-cities workflow has added it to the repository.
    static func bundledURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }

    /// Reads and parses a list file. Nil when the URL is nil, the file is missing or unreadable, or it has no usable rows.
    static func load(contentsOf url: URL?) -> CityIndex? {
        guard let url = url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let index = parse(text)
        return index.cities.isEmpty ? nil : index
    }

    /// Parses the four column format. Lines that do not fit are skipped.
    static func parse(_ text: String) -> CityIndex {
        var records: [CityRecord] = []
        records.reserveCapacity(40_000)
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  let latitude = Double(fields[2]),
                  let longitude = Double(fields[3]),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude)
            else { continue }
            let country = fields[1].trimmingCharacters(in: .whitespaces)
            records.append(CityRecord(name: name, countryCode: country, latitude: latitude, longitude: longitude))
        }
        return CityIndex(cities: records)
    }

    // MARK: Lookup

    /// The nearest city within `maxDistance` metres, or nil. Scans only a latitude band around the
    /// coordinate, starting at about one degree and doubling while the band cannot yet prove the answer.
    func nearest(to coordinate: Coordinate, within maxDistance: Double = CityIndex.maxDistance) -> CityRecord? {
        guard !cities.isEmpty else { return nil }
        var band = Self.initialBand
        while true {
            let best = nearestInBand(to: coordinate, band: band)
            // Every city outside the band is at least this far away.
            let reach = band * .pi / 180 * Self.earthRadius
            let coversEverything = band >= 180
            if let best = best, best.distance <= reach || coversEverything {
                return best.distance <= maxDistance ? best.city : nil
            }
            if reach >= maxDistance || coversEverything {
                return nil
            }
            band *= 2
        }
    }

    private func nearestInBand(to coordinate: Coordinate, band: Double) -> (city: CityRecord, distance: Double)? {
        let lowest = coordinate.latitude - band
        let highest = coordinate.latitude + band
        let start = firstIndex(atOrAbove: lowest)
        var best: (city: CityRecord, distance: Double)?
        for city in cities[start...] {
            if city.latitude > highest {
                break
            }
            let metres = Self.distance(from: coordinate, to: city.coordinate)
            if best.map({ metres < $0.distance }) ?? true {
                best = (city, metres)
            }
        }
        return best
    }

    /// Binary search: the first city whose latitude is at or above `latitude`.
    private func firstIndex(atOrAbove latitude: Double) -> Int {
        var low = 0
        var high = cities.count
        while low < high {
            let middle = (low + high) / 2
            if cities[middle].latitude < latitude {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// Great-circle distance in metres (haversine). Longitude wrap at +-180 needs no special case.
    static func distance(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}
