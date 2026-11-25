import Foundation
import CoreLocation
import SwiftyH3

/// Hierarchical discovery-progress engine.
///
/// Computes precise floating-point exploration percentages for real-world
/// administrative entities (states, counties) from the H3 visit grid:
///
///     progress % = unique claimed H3 cells inside the entity
///                  / total H3 cells covering the entity
///
/// Denominators come from an exact H3 res-7 polyfill of the state's
/// authoritative boundary polygon (computed once, cached in
/// `boundary_cell_counts`). Until a state's polyfill is available the
/// engine falls back to the Census land-area estimate (ALand ÷ 5.161 km²)
/// and flags the value. The result is a stable, monotonic percentage from
/// 0.0000 % to 100.00 % that only moves when real cells are claimed —
/// highway transit at speed cannot complete a state.
@MainActor
final class DiscoveryProgressEngine {
    static let shared = DiscoveryProgressEngine()

    private let database = DatabaseService.shared

    /// Mean area of a res-7 H3 hexagon in km².
    nonisolated static let res7CellAreaKm2 = 5.161

    /// U.S. Census Bureau land areas (km²), keyed by state abbreviation.
    nonisolated static let stateLandAreaKm2: [String: Double] = [
        "AL": 131171, "AK": 1458505, "AZ": 294207, "AR": 134856, "CA": 403466,
        "CO": 268431, "CT": 12542, "DE": 5047, "DC": 158, "FL": 137375,
        "GA": 149976, "HI": 16635, "ID": 214045, "IL": 143793, "IN": 92689,
        "IA": 144669, "KS": 213096, "KY": 102269, "LA": 112238, "ME": 79883,
        "MD": 25142, "MA": 20202, "MI": 150587, "MN": 206231, "MS": 121531,
        "MO": 180540, "MT": 380838, "NE": 199800, "NV": 286380, "NH": 23186,
        "NJ": 19211, "NM": 314918, "NY": 125059, "NC": 126292, "ND": 180570,
        "OH": 106200, "OK": 178440, "OR": 248608, "PA": 116095, "RI": 2678,
        "SC": 78050, "SD": 197580, "TN": 109153, "TX": 695662, "UT": 212699,
        "VT": 23871, "VA": 102232, "WA": 172119, "WV": 62756, "WI": 138656,
        "WY": 253335
    ]

    nonisolated struct StateProgress: Sendable, Identifiable {
        let stateId: String
        let name: String
        let claimedHexes: Int
        let totalHexes: Int
        let firstVisit: Int64
        let countiesVisited: Int
        let citiesVisited: Int
        let lastVisit: Int64
        let distanceKm: Double
        let usesExactDenominator: Bool
        let polygonAreaKm2: Double?

        var id: String { stateId }

        /// 0.00 – 100.00, precise to four decimals for tiny values.
        var percent: Double {
            guard totalHexes > 0 else { return 0 }
            return min(100.0, Double(claimedHexes) / Double(totalHexes) * 100.0)
        }

        var percentLabel: String {
            if percent < 0.01 {
                return String(format: "%.4f%%", percent)
            }
            return String(format: "%.2f%%", percent)
        }

        /// Geodesic-equivalent unexplored surface, preferring the exact
        /// boundary-polygon area over the Census land-area table.
        var unexploredKm2: Double {
            let area = polygonAreaKm2 ?? DiscoveryProgressEngine.stateLandAreaKm2[stateId] ?? 0
            return max(0, area - Double(claimedHexes) * DiscoveryProgressEngine.res7CellAreaKm2)
        }
    }

    struct NationalProgress {
        let claimedHexes: Int
        let totalHexes: Int
        var percent: Double {
            guard totalHexes > 0 else { return 0 }
            return min(100.0, Double(claimedHexes) / Double(totalHexes) * 100.0)
        }
    }

    /// County- and city-level progress against their boundary polygons.
    nonisolated struct RegionProgress: Sendable, Identifiable {
        let key: String          // "Texas-Harris" / "Texas-Houston"
        let name: String         // "Harris" / "Houston"
        let state: String        // "Texas"
        let level: String        // "county" / "city"
        let claimedHexes: Int
        let totalHexes: Int
        let firstVisit: Int64
        let usesExactDenominator: Bool
        let polygonAreaKm2: Double?

        var id: String { key }

        var percent: Double {
            guard totalHexes > 0 else { return 0 }
            return min(100.0, Double(claimedHexes) / Double(totalHexes) * 100.0)
        }

        var percentLabel: String {
            if percent < 0.01 {
                return String(format: "%.4f%%", percent)
            }
            return String(format: "%.2f%%", percent)
        }

        var unexploredKm2: Double {
            let area = polygonAreaKm2 ?? 0
            return max(0, area - Double(claimedHexes) * DiscoveryProgressEngine.res7CellAreaKm2)
        }
    }

    /// In-memory cache of exact polyfill totals and polygon areas,
    /// populated by `refreshExactTotals()`.
    private var exactTotals: [String: Int] = [:]
    private var polygonAreas: [String: Double] = [:]

    /// Warms exact denominators for every visited entity (states, counties,
    /// cities). Reads the local cache when present; otherwise polyfills the
    /// boundary polygon once on a background task and persists the result.
    func refreshExactTotals() async {
        let boundary = BoundaryService.shared
        var keys = database.fetchVisitedStates().map { $0.stateId }
        keys += database.fetchVisitedCounties().map { $0.fips }
        keys += database.fetchVisitedCities().map { $0.cityId }

        for key in keys {
            if exactTotals[key] == nil,
               let total = await boundary.exactTotalCells(forKey: key) {
                exactTotals[key] = total
            }
            if polygonAreas[key] == nil,
               let area = boundary.areaKm2(forKey: key) {
                polygonAreas[key] = area
            }
        }
    }

    /// Progress for every visited county, exact denominators preferred.
    func countyProgresses() -> [RegionProgress] {
        let hexCounts = database.fetchCountyHexCounts()
        return database.fetchVisitedCounties().map { county in
            regionProgress(
                key: county.fips,
                name: county.name,
                state: county.state,
                level: "county",
                claimedHexes: hexCounts[county.fips] ?? 0,
                firstVisit: county.visitedDate
            )
        }
        .sorted { $0.percent > $1.percent }
    }

    /// Progress for every visited city/place. Denominator floors at 1 cell:
    /// small places may contain no res-7 cell center, but a fix inside the
    /// boundary still claims its containing cell.
    func cityProgresses() -> [RegionProgress] {
        let hexCounts = database.fetchCityHexCounts()
        return database.fetchVisitedCities().map { city in
            regionProgress(
                key: city.cityId,
                name: city.name,
                state: city.state,
                level: "city",
                claimedHexes: hexCounts[city.cityId] ?? 0,
                firstVisit: city.visitedDate,
                minimumTotal: 1
            )
        }
        .sorted { $0.percent > $1.percent }
    }

    private func regionProgress(
        key: String,
        name: String,
        state: String,
        level: String,
        claimedHexes: Int,
        firstVisit: Int64,
        minimumTotal: Int = 0
    ) -> RegionProgress {
        let boundary = BoundaryService.shared
        let area = boundary.areaKm2(forKey: key)
        if let exact = exactTotals[key] {
            return RegionProgress(
                key: key,
                name: name,
                state: state,
                level: level,
                claimedHexes: claimedHexes,
                totalHexes: max(exact, minimumTotal),
                firstVisit: firstVisit,
                usesExactDenominator: true,
                polygonAreaKm2: area
            )
        }
        let estimated = area.map { max(1, Int($0 / Self.res7CellAreaKm2)) } ?? max(1, minimumTotal)
        return RegionProgress(
            key: key,
            name: name,
            state: state,
            level: level,
            claimedHexes: claimedHexes,
            totalHexes: max(estimated, minimumTotal),
            firstVisit: firstVisit,
            usesExactDenominator: false,
            polygonAreaKm2: area
        )
    }

    func stateProgresses() -> [StateProgress] {
        let states = database.fetchVisitedStates()
        let hexCounts = database.fetchStateHexCounts()
        let countyCounts = database.fetchCountyCountsByState()
        let cityCounts = database.fetchCityCountsByState()
        let stats = database.fetchStateStats()

        return states.map { state in
            let claimed = hexCounts[state.stateId] ?? 0
            let area = Self.stateLandAreaKm2[state.stateId] ?? 0
            let stat = stats[state.stateId]
            if let exact = exactTotals[state.stateId] {
                return StateProgress(
                    stateId: state.stateId,
                    name: state.name,
                    claimedHexes: claimed,
                    totalHexes: exact,
                    firstVisit: state.visitedDate,
                    countiesVisited: countyCounts[state.stateId] ?? 0,
                    citiesVisited: cityCounts[state.stateId] ?? 0,
                    lastVisit: stat?.lastVisit ?? 0,
                    distanceKm: (stat?.distanceMeters ?? 0) / 1000.0,
                    usesExactDenominator: true,
                    polygonAreaKm2: polygonAreas[state.stateId]
                )
            }
            return StateProgress(
                stateId: state.stateId,
                name: state.name,
                claimedHexes: claimed,
                totalHexes: Int(area / Self.res7CellAreaKm2),
                firstVisit: state.visitedDate,
                countiesVisited: countyCounts[state.stateId] ?? 0,
                citiesVisited: cityCounts[state.stateId] ?? 0,
                lastVisit: stat?.lastVisit ?? 0,
                distanceKm: (stat?.distanceMeters ?? 0) / 1000.0,
                usesExactDenominator: false,
                polygonAreaKm2: polygonAreas[state.stateId]
            )
        }
        .sorted { $0.percent > $1.percent }
    }

    func nationalProgress() -> NationalProgress {
        // US land area ≈ 9,147,593 km² (Census) → res-7 cell count.
        let totalHexes = Int(9_147_593.0 / Self.res7CellAreaKm2)
        return NationalProgress(
            claimedHexes: database.fetchDiscoveredHexCount(),
            totalHexes: totalHexes
        )
    }

    func cellId(at coordinate: CLLocationCoordinate2D) -> String? {
        let h3LatLng = H3LatLng(latitudeDegs: coordinate.latitude, longitudeDegs: coordinate.longitude)
        return (try? h3LatLng.cell(at: .res7))?.description
    }
}
