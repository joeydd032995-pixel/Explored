import Foundation
import CoreLocation
import Compression
import SwiftyH3

/// Authoritative U.S. boundary engine for states, counties, and cities.
///
/// Loads versioned Census-derived cartographic boundary polygons (public
/// domain, bundled by `tools/make-*-boundaries.js`) and provides:
///  - offline point-in-polygon attribution for any WGS 84 coordinate
///  - exact spherical polygon area (Chamberlain–Duquette)
///  - exact H3 res-7 cell totals per entity (polyfill against the real
///    polygon, cached locally), replacing the area-estimate denominator.
///
/// Entity keys:
///  - states:   abbreviation ("TX")
///  - counties: "StateName-CountyName" ("Texas-Harris")
///  - cities:   "StateName-PlaceName"   ("Texas-Houston")
/// County/city keys match the geocoder's fips/city-id conventions so the
/// hex attribution tables stay unified. The boundary engine owns hex→entity
/// attribution; reverse geocoding only supplies celebrations and names.
@MainActor
final class BoundaryService {
    static let shared = BoundaryService()

    /// Bumped when a bundled boundary file is replaced.
    static let boundaryVersion = "census-cb.2"

    private(set) var states: [StateBoundary] = []
    private(set) var counties: [StateBoundary] = []
    private(set) var cities: [StateBoundary] = []

    private let database = DatabaseService.shared

    private init() {
        // States: small, load synchronously so attribution works immediately.
        if let data = Self.bundledData("USStateBoundaries", fileExtension: "json") {
            states = Self.parse(data)
        }
        // Counties (~1.2 MB) and cities (~7 MB raw): parse on a background
        // task; attribution calls return nil until each level is ready.
        loadDeferred("USCountyBoundaries")
        loadDeferred("USCityBoundaries")
    }

    private func loadDeferred(_ resource: String) {
        guard let data = Self.bundledData(resource, fileExtension: "deflate") else { return }
        Task.detached(priority: .utility) { [weak self] in
            let parsed = Self.inflate(data).map { Self.parse($0) } ?? []
            await MainActor.run { [weak self] in
                switch resource {
                case "USCountyBoundaries": self?.counties = parsed
                default: self?.cities = parsed
                }
            }
        }
    }

    private static func bundledData(_ resource: String, fileExtension: String) -> Data? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Raw-deflate decompression (Compression framework, no dependencies).
    nonisolated private static func inflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        let capacity = input.count * 8
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let size = input.withUnsafeBytes { bytes -> Int in
            guard let source = bytes.baseAddress else { return 0 }
            return compression_decode_buffer(
                destination, capacity,
                source, input.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard size > 0 else { return nil }
        return Data(bytes: destination, count: size)
    }

    // MARK: - Attribution

    func boundary(forKey key: String) -> StateBoundary? {
        if let state = states.first(where: { $0.stateId == key }) { return state }
        if let county = counties.first(where: { $0.stateId == key }) { return county }
        return cities.first(where: { $0.stateId == key })
    }

    /// Offline state attribution: bbox prefilter then ray-casting point-in-polygon.
    func stateId(at coordinate: CLLocationCoordinate2D) -> String? {
        for boundary in states where boundary.contains(lat: coordinate.latitude, lng: coordinate.longitude) {
            return boundary.stateId
        }
        return nil
    }

    /// Offline county attribution. Key format: "Texas-Harris".
    func countyKey(at coordinate: CLLocationCoordinate2D) -> String? {
        for boundary in counties where boundary.contains(lat: coordinate.latitude, lng: coordinate.longitude) {
            return boundary.stateId
        }
        return nil
    }

    /// Offline city/place attribution. Key format: "Texas-Houston".
    func cityKey(at coordinate: CLLocationCoordinate2D) -> String? {
        for boundary in cities where boundary.contains(lat: coordinate.latitude, lng: coordinate.longitude) {
            return boundary.stateId
        }
        return nil
    }

    func areaKm2(forKey key: String) -> Double? {
        boundary(forKey: key)?.areaKm2
    }

    /// Exact number of H3 res-7 cells whose center lies inside the entity
    /// polygon. Computed once per entity via polyfill and cached in
    /// `boundary_cell_counts`; returns nil when the polygon is unavailable.
    func exactTotalCells(forKey key: String) async -> Int? {
        if let cached = database.fetchBoundaryCellCount(stateId: key) {
            return cached
        }
        guard let boundary = boundary(forKey: key) else { return nil }
        let count = await Task.detached(priority: .utility) {
            Self.polyfillCellCount(boundary)
        }.value

        guard let count, count > 0 else { return nil }
        database.upsertBoundaryCellCount(
            stateId: key,
            totalCells: count,
            boundaryVersion: Self.boundaryVersion
        )
        return count
    }

    // MARK: - Nonisolated geometry

    nonisolated static func polyfillCellCount(_ boundary: StateBoundary) -> Int? {
        var total = 0
        for ring in boundary.rings where ring.count >= 3 {
            let h3Points = ring.map { H3LatLng(latitudeDegs: $0.lat, longitudeDegs: $0.lng) }
            let polygon = H3Polygon(h3Points)
            guard let cells = try? polygon.cells(at: .res7) else { continue }
            total += cells.count
        }
        return total > 0 ? total : nil
    }

    nonisolated static func parse(_ data: Data) -> [StateBoundary] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }

        var result: [StateBoundary] = []
        result.reserveCapacity(features.count)
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let geometryType = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else { continue }

            var entityKey: String
            var displayName: String
            if let state = properties["state"] as? String, let name = properties["name"] as? String {
                // County / city file: entity key already unified.
                entityKey = "\(state)-\(name)"
                let kind = properties["kind"] as? String
                displayName = kind.map { "\(name) (\($0))" } ?? "\(name), \(state)"
            } else if let name = properties["name"] as? String {
                // State file: full name → abbreviation key.
                entityKey = USStateData.abbreviation(for: name) ?? name
                displayName = name
            } else {
                continue
            }

            var rings: [[BoundaryPoint]] = []
            switch (geometryType, coordinates) {
            case ("Polygon", let ringsOfPolygon as [[[Double]]]):
                // First ring is the exterior.
                if let exterior = ringsOfPolygon.first {
                    rings.append(Self.ring(from: exterior))
                }
            case ("MultiPolygon", let multi as [[[[Double]]]]):
                for polygon in multi {
                    if let exterior = polygon.first {
                        rings.append(Self.ring(from: exterior))
                    }
                }
            default:
                continue
            }

            guard !rings.isEmpty else { continue }
            result.append(StateBoundary(stateId: entityKey, name: displayName, rings: rings))
        }
        return result
    }

    nonisolated private static func ring(from coordinates: [[Double]]) -> [BoundaryPoint] {
        coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return BoundaryPoint(lat: pair[1], lng: pair[0])
        }
    }
}

// MARK: - Geometry Types

nonisolated struct BoundaryPoint: Sendable {
    let lat: Double
    let lng: Double
}

/// A named boundary entity (state, county, or city): exterior rings,
/// precomputed bounds for fast bbox prefiltering, exact spherical area.
nonisolated struct StateBoundary: Sendable {
    let stateId: String
    let name: String
    let rings: [[BoundaryPoint]]
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double

    init(stateId: String, name: String, rings: [[BoundaryPoint]]) {
        self.stateId = stateId
        self.name = name
        self.rings = rings

        var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0
        for ring in rings {
            for point in ring {
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
                minLng = min(minLng, point.lng)
                maxLng = max(maxLng, point.lng)
            }
        }
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLng = minLng
        self.maxLng = maxLng
    }

    func contains(lat: Double, lng: Double) -> Bool {
        guard lat >= minLat, lat <= maxLat, lng >= minLng, lng <= maxLng else { return false }

        var inside = false
        for ring in rings where ring.count >= 3 {
            var j = ring.count - 1
            for i in 0..<ring.count {
                let p1 = ring[i]
                let p2 = ring[j]

                if (p1.lat > lat) != (p2.lat > lat) {
                    let slope = (p2.lng - p1.lng) / (p2.lat - p1.lat)
                    let crossingLng = slope * (lat - p1.lat) + p1.lng
                    if lng < crossingLng {
                        inside.toggle()
                    }
                }
                j = i
            }
        }
        return inside
    }

    /// Spherical polygon area (Chamberlain & Duquette), km².
    var areaKm2: Double {
        let earthRadiusKm = 6371.0088
        var total = 0.0
        for ring in rings where ring.count >= 3 {
            var sum = 0.0
            var j = ring.count - 1
            for i in 0..<ring.count {
                let p1 = ring[j]
                let p2 = ring[i]
                let lat1 = p1.lat * .pi / 180
                let lat2 = p2.lat * .pi / 180
                let dLng = (p2.lng - p1.lng) * .pi / 180
                sum += dLng * (2.0 + sin(lat1) + sin(lat2))
                j = i
            }
            total += sum * earthRadiusKm * earthRadiusKm / 2.0
        }
        return abs(total)
    }
}
