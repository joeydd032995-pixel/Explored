import Foundation

/// Phase 4 analytics: daily aggregate rollups posted to `app_metrics`.
/// Never coordinates — only timing distributions and counts.
@MainActor
final class MetricsService {
    static let shared = MetricsService()

    private var frameTimes: [Double] = []          // map frame ms samples (capped)
    private var overlayLoadMs: [Double] = []       // overlay viewport load ms
    private var overlaysActive: Int = 0
    private var gameSessionCount = 0
    private var lastFlushDay: String

    private init() {
        lastFlushDay = UserDefaults.standard.string(forKey: "metrics.last_flush_day") ?? ""
    }

    func recordMapFrame(ms: Double) {
        guard frameTimes.count < 400 else { return }
        frameTimes.append(ms)
    }

    func recordOverlayLoad(ms: Double, activeCount: Int) {
        overlayLoadMs.append(ms)
        if overlayLoadMs.count > 400 { overlayLoadMs.removeFirst(overlayLoadMs.count - 400) }
        overlaysActive = activeCount
    }

    func recordGameSessionStart() {
        gameSessionCount += 1
        flushIfNeeded()
    }

    /// Posts one aggregate row per metric for the current day; runs at most
    /// once per calendar day.
    func flushIfNeeded() {
        guard let userId = UserProfileService.shared.userId, SupabaseService.shared.isConfigured else { return }
        let today = Self.dayString(Date())
        guard today != lastFlushDay else { return }
        guard hasData else { return }
        lastFlushDay = today
        UserDefaults.standard.set(today, forKey: "metrics.last_flush_day")

        var inserts: [AppMetricInsert] = []
        if frameTimes.count >= 10 {
            inserts.append(AppMetricInsert(userId: userId, metric: "map_frame_ms_p90", value: Self.percentile(frameTimes, 0.9)))
        }
        if !overlayLoadMs.isEmpty {
            inserts.append(AppMetricInsert(userId: userId, metric: "overlay_load_ms", value: overlayLoadMs.reduce(0, +) / Double(overlayLoadMs.count)))
        }
        inserts.append(AppMetricInsert(userId: userId, metric: "overlays_active", value: Double(overlaysActive)))
        if gameSessionCount > 0 {
            inserts.append(AppMetricInsert(userId: userId, metric: "game_sessions", value: Double(gameSessionCount)))
        }
        frameTimes.removeAll(keepingCapacity: true)
        overlayLoadMs.removeAll(keepingCapacity: true)
        gameSessionCount = 0

        Task {
            for insert in inserts {
                await SupabaseService.shared.logMetric(insert)
            }
        }
    }

    private var hasData: Bool {
        frameTimes.count >= 10 || !overlayLoadMs.isEmpty || gameSessionCount > 0
    }

    nonisolated static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    nonisolated static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int(p * Double(sorted.count - 1))))
        return sorted[index]
    }
}
