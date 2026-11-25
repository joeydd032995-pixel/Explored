import Foundation

/// Phase 4 leaderboard metrics beyond city nodes.
nonisolated enum LeaderboardMetric: String, CaseIterable, Identifiable, Sendable {
    case nodes
    case states
    case counties
    case cities

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nodes: return "Nodes"
        case .states: return "States"
        case .counties: return "Counties"
        case .cities: return "Cities"
        }
    }

    var systemImage: String {
        switch self {
        case .nodes: return "crown.fill"
        case .states: return "flag.fill"
        case .counties: return "building.columns.fill"
        case .cities: return "building.2.fill"
        }
    }
}

nonisolated struct LeaderboardEntry: Identifiable, Sendable {
    let id: String
    let username: String
    let color: String
    let stats: UserStats?
    let nodes: Int
    let isMe: Bool

    func value(for metric: LeaderboardMetric) -> Int {
        switch metric {
        case .nodes: return nodes
        case .states: return stats?.statesVisited ?? 0
        case .counties: return stats?.countiesVisited ?? 0
        case .cities: return stats?.citiesVisited ?? 0
        }
    }
}

@Observable
final class FriendsViewModel {
    var friends: [FriendInfo] = []
    var pendingRequests: [(Friendship, UserProfile)] = []
    var searchQuery: String = ""
    var searchResults: [UserProfile] = []
    var isSearching: Bool = false
    var isLoading: Bool = false
    var leaderboard: [LeaderboardEntry] = []
    var myNodesOwned: Int = 0
    var feed: [SocialEventDTO] = []
    var selectedMetric: LeaderboardMetric = .nodes

    private let supabase = SupabaseService.shared
    private let profileService = UserProfileService.shared

    func loadFriends() async {
        guard let userId = profileService.userId else { return }
        isLoading = true

        let friendships = await supabase.fetchFriendships(userId: userId)

        var friendInfos: [FriendInfo] = []
        var pending: [(Friendship, UserProfile)] = []

        for friendship in friendships {
            let friendUserId = friendship.userId1 == userId ? friendship.userId2 : friendship.userId1

            if friendship.status == "pending" && friendship.userId2 == userId {
                if let profile = await supabase.fetchUserProfile(userId: friendUserId) {
                    pending.append((friendship, profile))
                }
            } else if friendship.status == "accepted" {
                if let profile = await supabase.fetchUserProfile(userId: friendUserId) {
                    let stats = await supabase.fetchUserStats(userId: friendUserId)
                    let nodes = await supabase.fetchNodesCount(userId: friendUserId)
                    friendInfos.append(FriendInfo(profile: profile, stats: stats, nodesOwned: nodes))
                }
            }
        }

        friends = friendInfos
        pendingRequests = pending
        myNodesOwned = await supabase.fetchNodesCount(userId: userId)
        feed = await SocialService.fetchFeed(friends: friendInfos)
        await loadLeaderboard()
        isLoading = false
    }

    func searchUsers() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        let results = await supabase.searchUsers(query: searchQuery)
        let myId = profileService.userId ?? ""
        searchResults = results.filter { $0.id != myId }
        isSearching = false
    }

    func sendRequest(to userId: String) async {
        guard let myId = profileService.userId else { return }
        let success = await supabase.sendFriendRequest(fromUserId: myId, toUserId: userId)
        if success {
            searchResults.removeAll { $0.id == userId }
        }
    }

    func acceptRequest(_ friendship: Friendship) async {
        let success = await supabase.acceptFriendRequest(friendshipId: friendship.id)
        if success {
            pendingRequests.removeAll { $0.0.id == friendship.id }
            await loadFriends()
        }
    }

    func declineRequest(_ friendship: Friendship) async {
        let success = await supabase.declineFriendRequest(friendshipId: friendship.id)
        if success {
            pendingRequests.removeAll { $0.0.id == friendship.id }
        }
    }

    func pushStats() async {
        await supabase.upsertUserStats(localStats())
    }

    /// Local aggregate stats straight from SQLite (no network).
    func localStats() -> UserStats {
        let db = DatabaseService.shared
        let hexCount = db.fetchDiscoveredHexCount()
        let nationalPct = Double(hexCount) / 3_200_000.0 * 100.0

        let coords = db.fetchAllCoordinates()
        var totalMeters: Double = 0
        if coords.count >= 2 {
            for i in 1..<coords.count {
                let lat1 = coords[i-1].latitude, lon1 = coords[i-1].longitude
                let lat2 = coords[i].latitude, lon2 = coords[i].longitude
                let dLat = (lat2 - lat1) * .pi / 180
                let dLon = (lon2 - lon1) * .pi / 180
                let a = sin(dLat/2) * sin(dLat/2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon/2) * sin(dLon/2)
                let c = 2 * atan2(sqrt(a), sqrt(1-a))
                totalMeters += 6371000 * c
            }
        }

        return UserStats(
            userId: profileService.userId ?? "",
            nationalPct: nationalPct,
            statesVisited: db.fetchVisitedStatesCount(),
            countiesVisited: db.fetchVisitedCountiesCount(),
            citiesVisited: db.fetchVisitedCitiesCount(),
            totalMiles: totalMeters * 0.000621371,
            updatedAt: Date()
        )
    }

    private func loadLeaderboard() async {
        guard let userId = profileService.userId else { return }
        var entries: [LeaderboardEntry] = []

        let myStats = localStats()
        entries.append(LeaderboardEntry(
            id: userId,
            username: profileService.username ?? "You",
            color: profileService.avatarColor,
            stats: myStats,
            nodes: myNodesOwned,
            isMe: true
        ))

        for friend in friends {
            entries.append(LeaderboardEntry(
                id: friend.profile.id,
                username: friend.profile.username,
                color: friend.profile.avatarColor,
                stats: friend.stats,
                nodes: friend.nodesOwned,
                isMe: false
            ))
        }

        leaderboard = entries.sorted { $0.value(for: selectedMetric) > $1.value(for: selectedMetric) }
    }

    /// Re-sorts in place when the metric tab changes (no refetch needed).
    func resortLeaderboard() {
        leaderboard.sort { $0.value(for: selectedMetric) > $1.value(for: selectedMetric) }
    }
}
