import Foundation
import CoreLocation
import MapKit
import SwiftyH3

enum FogDisplayMode: String {
    case off
    /// Undiscovered cells shaded — classic fog of war.
    case undiscovered
    /// Discovered cells highlighted — territory you own.
    case discovered
}

enum FogPolygonKind: String {
    case fog
    case discovered
    /// Zoomed-out stand-in: the parent cell of discovered hexes, rendered
    /// as a faint glow so discoveries stay visible at country zoom.
    case discoveredGlow
}

extension FogDisplayMode {
    var icon: String {
        switch self {
        case .off: return "hexagon"
        case .discovered: return "hexagon.fill"
        case .undiscovered: return "cloud.fog"
        }
    }

    var label: String {
        switch self {
        case .off: return "off"
        case .discovered: return "discovered territory"
        case .undiscovered: return "fog of war"
        }
    }
}

@Observable
final class HexFogService {
    var fogPolygons: [FogHexPolygon] = []
    /// Zoomed-out stand-in for discovered territory: one soft circle per
    /// promoted parent cell. MapKit renders huge polygons unreliably, but
    /// circles are its bread and butter.
    var glowCircles: [FogGlowCircle] = []
    var isComputing: Bool = false

    /// What the hex layer shows. Persisted; defaults to celebrating
    /// discoveries (the map lights up as you explore).
    var displayMode: FogDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
        }
    }
    private static let displayModeKey = "fog.display_mode"

    private var discoveredHexes: Set<String> = []
    private var lastVisitRecordTimes: [String: Int64] = [:]
    private let visitThrottleSeconds: Int64 = 300
    private let database = DatabaseService.shared
    private let maxFogPolygons = 2000
    private var generation = 0

    init() {
        displayMode = FogDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: Self.displayModeKey) ?? ""
        ) ?? .discovered
    }

    func loadDiscoveredHexes() {
        discoveredHexes = database.fetchAllDiscoveredHexes()
    }

    /// Claims a cell for the first time. Returns the H3 cell id, or nil when
    /// the cell was already claimed.
    func discoverHex(at coordinate: CLLocationCoordinate2D) -> String? {
        guard let cell = try? coordinate.h3LatLng.cell(at: .res7) else { return nil }
        let hexId = cell.description
        guard !discoveredHexes.contains(hexId) else { return nil }
        discoveredHexes.insert(hexId)
        database.insertDiscoveredHex(hexId)
        return hexId
    }

    /// H3 cell id at res 7 for a coordinate (used to attribute visits to
    /// administrative entities discovered via geocoding).
    func cellId(at coordinate: CLLocationCoordinate2D) -> String? {
        guard let cell = try? coordinate.h3LatLng.cell(at: .res7) else { return nil }
        return cell.description
    }

    /// Dwell weighting: records a visit for the cell, throttled to one write
    /// per cell per 5 minutes so continuous tracking doesn't hammer the store.
    func recordVisit(hexId: String) {
        let now = Int64(Date().timeIntervalSince1970)
        if let last = lastVisitRecordTimes[hexId], now - last < visitThrottleSeconds { return }
        lastVisitRecordTimes[hexId] = now
        database.recordHexVisit(hexId: hexId, at: now)
    }

    func cycleDisplayMode() {
        switch displayMode {
        case .off: displayMode = .discovered
        case .discovered: displayMode = .undiscovered
        case .undiscovered: displayMode = .off
        }
    }

    /// Hex tiling runs OFF the main thread — H3 over a whole bounding box
    /// costs up to 2,000 polygons and must never block the UI on a pan.
    /// Coalesced by generation: only the newest region requested wins, so
    /// rapid panning never queues a backlog of stale work.
    func computeFog(for region: MKCoordinateRegion) {
        generation += 1
        let currentGeneration = generation
        let discovered = discoveredHexes
        let maxPolygons = maxFogPolygons
        let mode = displayMode
        isComputing = true

        Task.detached(priority: .utility) {
            var polygons: [FogHexPolygon] = []
            var circles: [FogGlowCircle] = []
            switch mode {
            case .off:
                break
            case .undiscovered:
                polygons = Self.undiscoveredPolygons(
                    region: region,
                    discoveredHexes: discovered,
                    maxFogPolygons: maxPolygons
                )
            case .discovered:
                (polygons, circles) = Self.discoveredContent(
                    region: region,
                    discoveredHexes: discovered,
                    maxFogPolygons: maxPolygons
                )
            }
            await MainActor.run {
                guard currentGeneration == self.generation else { return }
                self.fogPolygons = polygons
                self.glowCircles = circles
                self.isComputing = false
            }
        }
    }

    // MARK: - Polygon builders (background only)

    /// Coarse-to-fine ladder per zoom band; when a tiling would blow past
    /// the polygon cap, drop to the coarser step so the haze stays
    /// continuous instead of truncating to a random sparse subset.
    private static func fogLadder(for latDelta: Double) -> [H3Cell.Resolution] {
        if latDelta > 20 {
            return [.res4, .res2]
        } else if latDelta > 5 {
            return [.res6, .res4]
        } else {
            return [.res7, .res6]
        }
    }

    private static func undiscoveredPolygons(
        region: MKCoordinateRegion,
        discoveredHexes: Set<String>,
        maxFogPolygons: Int
    ) -> [FogHexPolygon] {
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2

        let boundingBox: [H3LatLng] = [
            H3LatLng(latitudeDegs: north, longitudeDegs: west),
            H3LatLng(latitudeDegs: north, longitudeDegs: east),
            H3LatLng(latitudeDegs: south, longitudeDegs: east),
            H3LatLng(latitudeDegs: south, longitudeDegs: west),
        ]

        for res in fogLadder(for: region.span.latitudeDelta) {
            guard let allCells = try? H3Polygon(boundingBox).cells(at: res) else { continue }
            let undiscoveredCells = allCells.filter { !discoveredHexes.contains($0.description) }
            guard undiscoveredCells.count <= maxFogPolygons else { continue }
            return polygons(for: undiscoveredCells, kind: .fog)
        }

        // Even the coarsest step overflows — emit a capped sample so some
        // occlusion still shows rather than none.
        guard let coarsest = try? H3Polygon(boundingBox).cells(at: .res1) else { return [] }
        return polygons(for: Array(coarsest.prefix(maxFogPolygons)), kind: .fog)
    }

    /// The discovered layer is zoom-aware: close up it renders the exact
    /// claimed res-7 cells; zoomed out those would be sub-pixel, so it shows
    /// one soft glow circle per promoted parent cell that resolves into
    /// exact gold hexes as you zoom in. H3 resolutions are fine-grained
    /// (res 4 ≈ 50 km, res 2 ≈ 400 km), so pick coarser ancestors than the
    /// fog occluder uses — a highlight must stay legible at each zoom.
    private static func discoveredContent(
        region: MKCoordinateRegion,
        discoveredHexes: Set<String>,
        maxFogPolygons: Int
    ) -> ([FogHexPolygon], [FogGlowCircle]) {
        guard !discoveredHexes.isEmpty else { return ([], []) }

        let exact = region.span.latitudeDelta <= 5

        if exact {
            let cells = Array(discoveredHexes.compactMap(H3Cell.init).prefix(maxFogPolygons))
            return (polygons(for: cells, kind: .discovered), [])
        }

        let baseResolution: H3Cell.Resolution = region.span.latitudeDelta > 20 ? .res2 : .res4

        // Promote discovered res-7 cells to the zoom-appropriate ancestor.
        var promoted = Set<String>()
        for hexId in discoveredHexes {
            guard let cell = H3Cell(hexId),
                  let parent = try? cell.parent(at: baseResolution) else { continue }
            promoted.insert(parent.description)
        }

        guard !promoted.isEmpty else { return ([], []) }

        var circles: [FogGlowCircle] = []
        for hexId in promoted.sorted() {
            guard let cell = H3Cell(hexId),
                  let boundary = try? cell.boundary, !boundary.isEmpty else { continue }
            let coords = boundary.map { CLLocationCoordinate2D(latitude: $0.latitudeDegs, longitude: $0.longitudeDegs) }
            circles.append(FogGlowCircle(hexId: hexId, coords: coords))
        }
        return ([], Array(circles.prefix(maxFogPolygons)))
    }

    private static func polygons(for cells: [H3Cell], kind: FogPolygonKind) -> [FogHexPolygon] {
        var result: [FogHexPolygon] = []
        result.reserveCapacity(cells.count)

        for cell in cells {
            guard let boundary = try? cell.boundary else { continue }
            let coords = boundary.map { CLLocationCoordinate2D(latitude: $0.latitudeDegs, longitude: $0.longitudeDegs) }
            result.append(FogHexPolygon(hexId: cell.description, kind: kind, coordinates: coords))
        }

        return result
    }
}

nonisolated struct FogHexPolygon: Sendable, Identifiable {
    let hexId: String
    var kind: FogPolygonKind = .fog
    let coordinates: [CLLocationCoordinate2D]
    var id: String { "\(kind.rawValue)-\(hexId)" }
}

/// A soft glow over a discovered parent region, drawn as an MKCircle when
/// zoomed too far out for exact hexes (or even their polygons) to read.
nonisolated struct FogGlowCircle: Sendable, Identifiable {
    let id: String
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance

    /// Centroid + circumradius of the parent cell's boundary vertices.
    init(hexId: String, coords: [CLLocationCoordinate2D]) {
        self.id = "glow-\(hexId)"
        let lat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
        let lng = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
        self.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let centerLoc = CLLocation(latitude: lat, longitude: lng)
        self.radius = coords.map { centerLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }.max() ?? 50_000
    }
}
