import Foundation

/// Phase 4 offline reconciliation: pushes unsynced cell claims to the
/// server and pulls this explorer's claims from other devices, union-merging
/// into the local SQLite store. Cells are additive; first_seen keeps the min,
/// last_seen/visits keep the max — conflict-free by construction.
@MainActor
@Observable
final class CellClaimSyncService {
    static let shared = CellClaimSyncService()

    var isSyncing = false
    var lastSyncAt: Date?
    var lastMergedCount = 0

    /// Posted on NotificationCenter when remote claims changed local progress.
    static let claimsMergedNotification = Notification.Name("explorer.claimsMerged")

    private let database = DatabaseService.shared
    private var periodicTask: Task<Void, Never>?
    private static let interval: TimeInterval = 5 * 60

    private init() {}

    func start() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func syncNow() async {
        guard !isSyncing, SupabaseService.shared.isConfigured, let userId = UserProfileService.shared.userId else { return }
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncAt = Date()
        }

        await pushUnsyncedClaims(userId: userId)
        await pullRemoteClaims(userId: userId)
    }

    // MARK: Push

    private struct PushLevel {
        let table: String
        let idColumn: String
        let level: Int
    }

    private func pushUnsyncedClaims(userId: String) async {
        let levels = [
            PushLevel(table: "state_hexes", idColumn: "state_id", level: 2),
            PushLevel(table: "county_hexes", idColumn: "fips", level: 3),
            PushLevel(table: "city_hexes", idColumn: "city_id", level: 4),
        ]

        for level in levels {
            let claims = database.fetchUnsyncedClaims(table: level.table, idColumn: level.idColumn)
            guard !claims.isEmpty else { continue }
            let visits = visitsByHex()

            var pushed: [Int64] = []
            for claim in claims {
                let visit = visits[claim.hexId]
                let params = UpsertCellClaimParams(
                    pUserId: userId,
                    pCell: claim.hexId,
                    pLevel: level.level,
                    pEntityId: claim.entityId,
                    pFirstSeen: visit?.lastVisit ?? 0,
                    pLastSeen: visit?.lastVisit ?? 0,
                    pVisits: visit?.visits ?? 1
                )
                if await SupabaseService.shared.pushCellClaim(params) {
                    pushed.append(claim.rowId)
                }
            }
            database.markClaimsSynced(table: level.table, rowIds: pushed)
        }
    }

    private func visitsByHex() -> [String: (visits: Int, lastVisit: Int64)] {
        var result: [String: (Int, Int64)] = [:]
        for visit in database.fetchAllHexVisits() {
            result[visit.hexId] = (visit.visits, visit.lastVisit)
        }
        return result
    }

    // MARK: Pull

    private func pullRemoteClaims(userId: String) async {
        let remote = await SupabaseService.shared.fetchMyCellClaims(userId: userId)
        guard !remote.isEmpty else { return }

        var mergedAny = false
        for claim in remote {
            let changed = database.mergeRemoteClaim(
                level: Int16(clamping: claim.entityLevel),
                entityId: claim.entityId,
                hexId: claim.cell,
                visits: claim.visits,
                lastSeen: claim.lastSeen
            )
            mergedAny = mergedAny || changed
        }

        if mergedAny {
            lastMergedCount = remote.count
            MilestoneService.shared.checkAndFireMilestones()
            NotificationCenter.default.post(name: Self.claimsMergedNotification, object: nil)
        }
    }
}
