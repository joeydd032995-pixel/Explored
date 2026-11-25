import Foundation
import CoreLocation

/// Phase 4 privacy pillar. Breadcrumbs live on-device; these are the controls:
/// a tracking master gate, date-range deletion, JSON export, and full
/// erasure (local wipe + server-side claim/metric/feed deletion).
@MainActor
@Observable
final class PrivacyService {
    static let shared = PrivacyService()

    enum DeleteRange: String, CaseIterable, Identifiable {
        case last24Hours
        case last7Days
        case last30Days
        case all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .last24Hours: return "Last 24 hours"
            case .last7Days: return "Last 7 days"
            case .last30Days: return "Last 30 days"
            case .all: return "All time"
            }
        }

        var from: Int64 {
            let now = Int64(Date().timeIntervalSince1970)
            switch self {
            case .last24Hours: return now - 86_400
            case .last7Days: return now - 7 * 86_400
            case .last30Days: return now - 30 * 86_400
            case .all: return 0
            }
        }
    }

    var isTrackingPaused: Bool {
        didSet {
            UserDefaults.standard.set(isTrackingPaused, forKey: "privacy.tracking_paused")
            if isTrackingPaused { locationService?.stopTracking() }
        }
    }
    private(set) var lastExportURL: URL?
    var lastMessage: String?

    private let database = DatabaseService.shared
    private weak var locationService: LocationService?

    private init() {
        isTrackingPaused = UserDefaults.standard.bool(forKey: "privacy.tracking_paused")
    }

    /// Called from ContentView next to GameService.configure.
    func configure(locationService: LocationService) {
        self.locationService = locationService
        if isTrackingPaused { locationService.stopTracking() }
    }

    // MARK: Range deletion

    /// Deletes raw breadcrumbs and visit rows in the range. Unique-cell
    /// discoveries and aggregate attribution are identity-level: they are
    /// erased only through full erasure below.
    func deleteData(in range: DeleteRange) {
        database.deleteRange(from: range.from, to: Int64(Date().timeIntervalSince1970))
        lastMessage = "Deleted exploration data: \(range.label.lowercased())."
    }

    // MARK: Export

    /// Builds a JSON file of all local discovery data and returns its URL for
    /// the share sheet.
    @discardableResult
    func exportJSON() -> URL? {
        let states = database.fetchVisitedStates().map { ["id": $0.stateId, "name": $0.name, "visited_at": String($0.visitedDate)] }
        let visits = database.fetchAllHexVisits().map { ["hex": $0.hexId, "visits": String($0.visits), "last_visit": String($0.lastVisit)] }

        let export: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "explorer": [
                "id": UserProfileService.shared.userId ?? "",
                "username": UserProfileService.shared.username ?? "",
            ],
            "unique_hexes": database.fetchDiscoveredHexCount(),
            "states": states,
            "hex_visits": visits,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys]) else {
            lastMessage = "Couldn't build the export file."
            return nil
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-export.json")
        do {
            try data.write(to: url, options: .atomic)
            lastExportURL = url
            lastMessage = "Export ready — share it from the sheet."
            return url
        } catch {
            lastMessage = "Couldn't write the export file."
            return nil
        }
    }

    // MARK: Full erasure

    /// One-tap erasure: deletes cell claims, metrics and social events
    /// server-side under the client identity, then wipes local discovery data.
    func eraseEverything() async {
        if let userId = UserProfileService.shared.userId {
            await SupabaseService.shared.deleteMyCellClaims(userId: userId)
            await SupabaseService.shared.deleteMyMetrics(userId: userId)
            await SupabaseService.shared.deleteMySocialEvents(userId: userId)
        }
        database.wipeDiscoveryData()
        lastMessage = "All exploration data erased on this device and on the server."
    }
}
