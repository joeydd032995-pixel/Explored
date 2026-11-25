import Foundation
import CoreLocation

@Observable
final class StatsViewModel {
    var hexCount: Int = 0
    var statesVisited: Int = 0
    var countiesVisited: Int = 0
    var citiesVisited: Int = 0
    var totalDistanceMiles: Double = 0
    var explorationStreak: Int = 0
    var stateSummaries: [StateSummary] = []
    var visitedStateIds: Set<String> = []
    var isLoading: Bool = false
    var kothNodesOwned: Int = 0

    private let database = DatabaseService.shared

    func loadStats() {
        isLoading = true
        hexCount = database.fetchDiscoveredHexCount()
        statesVisited = database.fetchVisitedStatesCount()
        countiesVisited = database.fetchVisitedCountiesCount()
        citiesVisited = database.fetchVisitedCitiesCount()
        totalDistanceMiles = computeTotalDistance()
        explorationStreak = computeStreak()
        stateSummaries = buildStateSummaries()
        visitedStateIds = Set(database.fetchVisitedStates().map { $0.stateId })
        isLoading = false

        Task {
            if let userId = UserProfileService.shared.userId {
                let count = await SupabaseService.shared.fetchNodesCount(userId: userId)
                kothNodesOwned = count
            }
        }
    }

    var nationalCoveragePercent: Double {
        Double(hexCount) / 3_200_000.0 * 100.0
    }

    var nationalCoverageFormatted: String {
        String(format: "%.3f%%", nationalCoveragePercent)
    }

    var distanceFormatted: String {
        if totalDistanceMiles >= 1000 {
            return String(format: "%.0f mi", totalDistanceMiles)
        }
        return String(format: "%.1f mi", totalDistanceMiles)
    }

    private func computeTotalDistance() -> Double {
        let coords = database.fetchAllCoordinates()
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let prev = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let curr = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            total += curr.distance(from: prev)
        }
        return total * 0.000621371
    }

    private func computeStreak() -> Int {
        let days = database.fetchDistinctCoordinateDays()
        guard !days.isEmpty else { return 0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let daySet = Set(days)

        var streak = 0
        var currentDate = Date()

        for _ in 0..<365 {
            let dateString = formatter.string(from: currentDate)
            if daySet.contains(dateString) {
                streak += 1
                guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) else { break }
                currentDate = prev
            } else {
                break
            }
        }

        return streak
    }

    private func buildStateSummaries() -> [StateSummary] {
        USStateData.allStates.map { state in
            let countiesForState = database.fetchCountiesForState(state: state.name)
            let citiesForState = database.fetchCitiesForState(state: state.name)

            return StateSummary(
                id: state.id,
                name: state.name,
                totalCounties: state.countyCount,
                visitedCounties: countiesForState.count,
                visitedCities: citiesForState.count,
                latitude: state.latitude,
                longitude: state.longitude
            )
        }.sorted { $0.explorationPercent > $1.explorationPercent }
    }
}
