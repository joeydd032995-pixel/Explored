import Foundation

/// Phase 4 social expansion: client-written activity events (first visits,
/// layer publishes, game starts, milestones) plus the boundary-release
/// launch check that turns Census updates into local notifications.
@MainActor
enum SocialService {
    /// Fire-and-forget feed post under the local explorer identity.
    static func post(kind: String, title: String) async {
        guard let userId = UserProfileService.shared.userId else { return }
        let insert = SocialEventInsert(
            userId: userId,
            username: UserProfileService.shared.username ?? "explorer",
            kind: kind,
            title: title
        )
        await SupabaseService.shared.postSocialEvent(insert)
    }

    /// Feed for me + my friends, newest first.
    static func fetchFeed(friends: [FriendInfo]) async -> [SocialEventDTO] {
        guard let myId = UserProfileService.shared.userId else { return [] }
        let userIds = [myId] + friends.map { $0.profile.id }
        return await SupabaseService.shared.fetchSocialEvents(userIds: userIds)
    }
}

@MainActor
final class BoundaryReleaseService {
    static let shared = BoundaryReleaseService()

    private static let seenKey = "boundary.last_seen_version"

    /// On launch: compares the server's latest boundary release to the last
    /// seen version. A new release posts a notification listing the changed
    /// areas; the boundary engine re-derives attribution as data refreshes.
    func checkOnLaunch() async {
        guard let release = await SupabaseService.shared.fetchLatestBoundaryRelease() else { return }
        let seen = UserDefaults.standard.string(forKey: Self.seenKey) ?? BoundaryService.boundaryVersion
        guard release.version != seen else { return }
        UserDefaults.standard.set(release.version, forKey: Self.seenKey)

        let changed = release.changedEntities
        let names = changed.map { $0.name }.prefix(3).joined(separator: ", ")
        let body: String
        if changed.isEmpty {
            body = "Boundary data was refreshed. Your percentages re-derive as you explore."
        } else if changed.count <= 3 {
            body = "\(names) boundaries changed — your progress there was re-derived."
        } else {
            body = "\(names) +\(changed.count - 3) more areas changed. Your percentages were re-derived."
        }
        NotificationService.shared.sendNotification(title: "🗺️ Boundaries updated", body: body)
    }
}
