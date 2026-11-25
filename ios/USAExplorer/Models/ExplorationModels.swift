import Foundation

nonisolated struct VisitedStateRecord: Sendable, Identifiable {
    var id: String { stateId }
    let stateId: String
    let name: String
    let visitedDate: Int64
}

nonisolated struct VisitedCountyRecord: Sendable, Identifiable {
    var id: String { fips }
    let fips: String
    let name: String
    let state: String
    let visitedDate: Int64
}

nonisolated struct VisitedCityRecord: Sendable, Identifiable {
    var id: String { cityId }
    let cityId: String
    let name: String
    let state: String
    let county: String
    let visitedDate: Int64
}

struct StateSummary: Identifiable {
    let id: String
    let name: String
    let totalCounties: Int
    let visitedCounties: Int
    let visitedCities: Int
    let latitude: Double
    let longitude: Double

    var explorationPercent: Double {
        guard totalCounties > 0 else { return 0 }
        return Double(visitedCounties) / Double(totalCounties) * 100
    }
}
