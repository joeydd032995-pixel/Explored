import Foundation
import Supabase

final class SupabaseService: @unchecked Sendable {
    static let shared = SupabaseService()

    private var client: SupabaseClient?

    private init() {
        let url = Config.allValues["EXPO_PUBLIC_SUPABASE_URL"] ?? ""
        let key = Config.allValues["EXPO_PUBLIC_SUPABASE_ANON_KEY"] ?? ""
        guard !url.isEmpty, !key.isEmpty, let supabaseURL = URL(string: url) else { return }
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: key)
    }

    var isConfigured: Bool { client != nil }

    func createUser(id: String, username: String, avatarColor: String) async {
        guard let client else { return }
        do {
            try await client.from("users").insert([
                "id": id,
                "username": username,
                "avatar_color": avatarColor
            ]).execute()
        } catch {}
    }

    func searchUsers(query: String) async -> [UserProfile] {
        guard let client, !query.isEmpty else { return [] }
        do {
            let response: [UserProfile] = try await client.from("users")
                .select()
                .ilike("username", pattern: "%\(query)%")
                .limit(10)
                .execute()
                .value
            return response
        } catch { return [] }
    }

    func sendFriendRequest(fromUserId: String, toUserId: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("friendships").insert([
                "id": UUID().uuidString,
                "user_id_1": fromUserId,
                "user_id_2": toUserId,
                "status": "pending"
            ]).execute()
            return true
        } catch { return false }
    }

    func acceptFriendRequest(friendshipId: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("friendships")
                .update(["status": "accepted"])
                .eq("id", value: friendshipId)
                .execute()
            return true
        } catch { return false }
    }

    func declineFriendRequest(friendshipId: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("friendships")
                .delete()
                .eq("id", value: friendshipId)
                .execute()
            return true
        } catch { return false }
    }

    func fetchFriendships(userId: String) async -> [Friendship] {
        guard let client else { return [] }
        do {
            let sent: [Friendship] = try await client.from("friendships")
                .select()
                .eq("user_id_1", value: userId)
                .execute()
                .value

            let received: [Friendship] = try await client.from("friendships")
                .select()
                .eq("user_id_2", value: userId)
                .execute()
                .value

            return sent + received
        } catch { return [] }
    }

    func fetchUserProfile(userId: String) async -> UserProfile? {
        guard let client else { return nil }
        do {
            let profiles: [UserProfile] = try await client.from("users")
                .select()
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            return profiles.first
        } catch { return nil }
    }

    func fetchUserStats(userId: String) async -> UserStats? {
        guard let client else { return nil }
        do {
            let stats: [UserStats] = try await client.from("user_stats")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            return stats.first
        } catch { return nil }
    }

    func upsertUserStats(_ stats: UserStats) async {
        guard let client else { return }
        do {
            try await client.from("user_stats").upsert(stats).execute()
        } catch {}
    }

    func captureNode(cityId: String, cityName: String, state: String, lat: Double, lng: Double, userId: String, username: String, color: String) async -> CityNode? {
        guard let client else { return nil }
        do {
            let node = CityNode(
                cityId: cityId,
                cityName: cityName,
                state: state,
                latitude: lat,
                longitude: lng,
                ownerUserId: userId,
                ownerUsername: username,
                ownerColor: color,
                capturedAt: Date()
            )
            try await client.from("city_nodes").upsert(node).execute()
            return node
        } catch { return nil }
    }

    func fetchNode(cityId: String) async -> CityNode? {
        guard let client else { return nil }
        do {
            let nodes: [CityNode] = try await client.from("city_nodes")
                .select()
                .eq("city_id", value: cityId)
                .limit(1)
                .execute()
                .value
            return nodes.first
        } catch { return nil }
    }

    func fetchNodesOwnedBy(userId: String) async -> [CityNode] {
        guard let client else { return [] }
        do {
            let nodes: [CityNode] = try await client.from("city_nodes")
                .select()
                .eq("owner_user_id", value: userId)
                .execute()
                .value
            return nodes
        } catch { return [] }
    }

    func fetchNodesCount(userId: String) async -> Int {
        guard let client else { return 0 }
        do {
            let nodes: [CityNode] = try await client.from("city_nodes")
                .select("city_id")
                .eq("owner_user_id", value: userId)
                .execute()
                .value
            return nodes.count
        } catch { return 0 }
    }

    // MARK: - Overlay Sync (hazard reports + camera points)

    func uploadHazardReport(id: String, kind: String, lat: Double, lng: Double, createdAt: Int64, expiresAt: Int64) async {
        guard let client else { return }
        do {
            try await client.from("hazard_reports").insert(
                HazardReportInsert(id: id, kind: kind, lat: lat, lng: lng, createdAt: createdAt, expiresAt: expiresAt, confirmations: 0)
            ).execute()
        } catch {}
    }

    func confirmHazardReport(id: String, expiresAt: Int64) async {
        guard let client else { return }
        do {
            // RPC increments confirmations and extends expiry atomically.
            try await client.rpc("confirm_hazard_report", params: ConfirmHazardReportParams(pReportId: id, pNewExpiry: expiresAt)).execute()
        } catch {}
    }

    func fetchActiveHazardReports() async -> [HazardReportDTO] {
        guard let client else { return [] }
        let now = Int64(Date().timeIntervalSince1970)
        do {
            let reports: [HazardReportDTO] = try await client.from("hazard_reports")
                .select()
                .gt("expires_at", value: Int(now))
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            return reports
        } catch { return [] }
    }

    func uploadCameraPoint(id: String, kind: String, lat: Double, lng: Double, note: String) async {
        guard let client else { return }
        do {
            try await client.from("camera_points").insert(
                CameraPointInsert(id: id, kind: kind, lat: lat, lng: lng, note: note, confidence: 0.4, confirmations: 0)
            ).execute()
        } catch {}
    }

    func fetchLeaderboard(userIds: [String]) async -> [(String, Int)] {
        guard let client, !userIds.isEmpty else { return [] }
        var results: [(String, Int)] = []
        for uid in userIds {
            let count = await fetchNodesCount(userId: uid)
            results.append((uid, count))
        }
        return results.sorted { $0.1 > $1.1 }
    }

    // MARK: - Creator Marketplace (phase 3)

    /// Public catalog: live layers, newest first.
    func fetchPublicOverlays() async -> [OverlayDefinitionDTO] {
        guard let client else { return [] }
        do {
            let rows: [OverlayDefinitionDTO] = try await client.from("overlay_definitions")
                .select()
                .eq("visibility", value: "public")
                .eq("status", value: "active")
                .order("updated_at", ascending: false)
                .limit(200)
                .execute()
                .value
            return rows
        } catch { return [] }
    }

    /// The signed-in creator's own layers, any visibility/status.
    func fetchMyOverlays(creatorId: String) async -> [OverlayDefinitionDTO] {
        guard let client else { return [] }
        do {
            let rows: [OverlayDefinitionDTO] = try await client.from("overlay_definitions")
                .select()
                .eq("creator_user_id", value: creatorId)
                .order("updated_at", ascending: false)
                .limit(200)
                .execute()
                .value
            return rows
        } catch { return [] }
    }

    func publishOverlay(_ insert: OverlayDefinitionInsert) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("overlay_definitions").insert(insert).execute()
            return true
        } catch { return false }
    }

    /// Bump the version and swap the spec (point edits) for an owned layer.
    func updateOverlaySpec(overlayId: String, creatorId: String, spec: OverlaySpec, version: Int) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("overlay_definitions")
                .update(OverlaySpecUpdate(spec: spec, version: version))
                .eq("id", value: overlayId)
                .eq("creator_user_id", value: creatorId)
                .execute()
            return true
        } catch { return false }
    }

    func deleteOverlay(overlayId: String, creatorId: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("overlay_definitions")
                .delete()
                .eq("id", value: overlayId)
                .eq("creator_user_id", value: creatorId)
                .execute()
            return true
        } catch { return false }
    }

    /// One review per person per layer; upsert overwrites the previous rating.
    func submitOverlayReview(_ insert: OverlayReviewInsert) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("overlay_reviews")
                .upsert(insert, onConflict: "overlay_id,user_id")
                .execute()
            return true
        } catch { return false }
    }

    func fetchOverlayReviews(overlayId: String) async -> [OverlayReviewDTO] {
        guard let client else { return [] }
        do {
            let rows: [OverlayReviewDTO] = try await client.from("overlay_reviews")
                .select()
                .eq("overlay_id", value: overlayId)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            return rows
        } catch { return [] }
    }

    func reportOverlay(_ insert: OverlayReportInsert) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("overlay_reports").insert(insert).execute()
            return true
        } catch { return false }
    }

    func incrementOverlayInstalls(overlayId: String) async {
        guard let client else { return }
        do {
            try await client.rpc("increment_overlay_installs", params: IncrementOverlayInstallsParams(pOverlayId: overlayId)).execute()
        } catch {}
    }

    // MARK: - Phase 4: Social feed

    func postSocialEvent(_ insert: SocialEventInsert) async {
        guard let client else { return }
        do {
            try await client.from("social_events").insert(insert).execute()
        } catch {}
    }

    func fetchSocialEvents(userIds: [String], limit: Int = 40) async -> [SocialEventDTO] {
        guard let client, !userIds.isEmpty else { return [] }
        do {
            let rows: [SocialEventDTO] = try await client.from("social_events")
                .select()
                .in("user_id", values: userIds)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch { return [] }
    }

    func deleteMySocialEvents(userId: String) async {
        guard let client else { return }
        do { try await client.from("social_events").delete().eq("user_id", value: userId).execute() } catch {}
    }

    // MARK: - Phase 4: Cell-claim sync

    func pushCellClaim(_ params: UpsertCellClaimParams) async -> Bool {
        guard let client else { return false }
        do {
            try await client.rpc("upsert_cell_claim", params: params).execute()
            return true
        } catch { return false }
    }

    func fetchMyCellClaims(userId: String) async -> [CellClaimDTO] {
        guard let client else { return [] }
        do {
            let rows: [CellClaimDTO] = try await client.from("cell_claims")
                .select()
                .eq("user_id", value: userId)
                .limit(20000)
                .execute()
                .value
            return rows
        } catch { return [] }
    }

    func deleteMyCellClaims(userId: String) async {
        guard let client else { return }
        do {
            try await client.rpc("delete_my_cell_claims", params: DeleteMyCellClaimsParams(pUserId: userId)).execute()
        } catch {}
    }

    // MARK: - Phase 4: Territory Games

    func createGameSession(_ insert: GameSessionInsert) async -> GameSessionDTO? {
        guard let client else { return nil }
        do {
            try await client.from("game_sessions").insert(insert).execute()
            var sessions: [GameSessionDTO] = try await client.from("game_sessions")
                .select()
                .eq("id", value: insert.id)
                .limit(1)
                .execute()
                .value
            return sessions.first
        } catch { return nil }
    }

    func fetchSession(id: String) async -> GameSessionDTO? {
        guard let client else { return nil }
        do {
            let sessions: [GameSessionDTO] = try await client.from("game_sessions")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            return sessions.first
        } catch { return nil }
    }

    func fetchSessionByCode(code: String) async -> GameSessionDTO? {
        guard let client else { return nil }
        do {
            let sessions: [GameSessionDTO] = try await client.from("game_sessions")
                .select()
                .eq("invite_code", value: code)
                .limit(1)
                .execute()
                .value
            return sessions.first
        } catch { return nil }
    }

    /// Open (lobby/live) sessions, newest first — the lobby list.
    func fetchOpenSessions() async -> [GameSessionDTO] {
        guard let client else { return [] }
        do {
            let sessions: [GameSessionDTO] = try await client.from("game_sessions")
                .select()
                .in("status", values: ["lobby", "live"])
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value
            return sessions
        } catch { return [] }
    }

    func updateSession(id: String, patch: GameSessionPatch) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("game_sessions").update(patch).eq("id", value: id).execute()
            return true
        } catch { return false }
    }

    func upsertGamePlayer(_ player: GamePlayerUpsert) async -> Bool {
        guard let client else { return false }
        do {
            try await client.from("game_players")
                .upsert(player, onConflict: "session_id,user_id")
                .execute()
            return true
        } catch { return false }
    }

    func fetchGamePlayers(sessionId: String) async -> [GamePlayerDTO] {
        guard let client else { return [] }
        do {
            let players: [GamePlayerDTO] = try await client.from("game_players")
                .select()
                .eq("session_id", value: sessionId)
                .execute()
                .value
            return players
        } catch { return [] }
    }

    /// Removes the player's live position row (leave / session end).
    func removeGamePlayer(sessionId: String, userId: String) async {
        guard let client else { return }
        do {
            try await client.from("game_players")
                .delete()
                .eq("session_id", value: sessionId)
                .eq("user_id", value: userId)
                .execute()
        } catch {}
    }

    func logGameEvent(_ insert: GameEventInsert) async {
        guard let client else { return }
        do { try await client.from("game_events").insert(insert).execute() } catch {}
    }

    func fetchGameEvents(sessionId: String, limit: Int = 100) async -> [GameEventDTO] {
        guard let client else { return [] }
        do {
            let events: [GameEventDTO] = try await client.from("game_events")
                .select()
                .eq("session_id", value: sessionId)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return events
        } catch { return [] }
    }

    // MARK: - Phase 4: Metrics & analytics

    func logMetric(_ insert: AppMetricInsert) async {
        guard let client else { return }
        do { try await client.from("app_metrics").insert(insert).execute() } catch {}
    }

    func logOverlayInstall(overlayId: String, userId: String) async {
        guard let client else { return }
        do {
            try await client.from("overlay_install_events").insert(
                OverlayInstallEventInsert(overlayId: overlayId, userId: userId)
            ).execute()
        } catch {}
    }

    func deleteMyMetrics(userId: String) async {
        guard let client else { return }
        do { try await client.from("app_metrics").delete().eq("user_id", value: userId).execute() } catch {}
    }

    func fetchOverlayDailyInstalls(overlayId: String) async -> [DailyInstallDTO] {
        guard let client else { return [] }
        do {
            let rows: [DailyInstallDTO] = try await client.rpc(
                "overlay_daily_installs",
                params: OverlayDailyInstallsParams(pOverlayId: overlayId)
            ).execute().value
            return rows
        } catch { return [] }
    }

    // MARK: - Phase 4: Boundary releases

    func fetchLatestBoundaryRelease() async -> BoundaryReleaseDTO? {
        guard let client else { return nil }
        do {
            let rows: [BoundaryReleaseDTO] = try await client.from("boundary_releases")
                .select()
                .order("released_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }
}
