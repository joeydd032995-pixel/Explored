import SwiftUI

@main
struct USAExplorerApp: App {
    init() {
        NotificationService.shared.requestPermission()
        // All-Access Pass: configures RevenueCat and links the local explorer
        // identity. No-ops when the store isn't set up yet (empty API key).
        _ = PassService.shared

        // Phase 4 background wiring: cell-claim sync loop (push/pull every
        // 5 min), boundary-release launch check, and the daily metrics flush.
        Task { @MainActor in
            CellClaimSyncService.shared.start()
            await BoundaryReleaseService.shared.checkOnLaunch()
            MetricsService.shared.flushIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
