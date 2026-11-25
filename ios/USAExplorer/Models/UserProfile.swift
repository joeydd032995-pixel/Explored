import Foundation

nonisolated struct UserProfile: Codable, Sendable, Identifiable {
    let id: String
    let username: String
    let avatarColor: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case avatarColor = "avatar_color"
        case createdAt = "created_at"
    }
}

nonisolated struct UserStats: Codable, Sendable {
    let userId: String
    let nationalPct: Double
    let statesVisited: Int
    let countiesVisited: Int
    let citiesVisited: Int
    let totalMiles: Double
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case nationalPct = "national_pct"
        case statesVisited = "states_visited"
        case countiesVisited = "counties_visited"
        case citiesVisited = "cities_visited"
        case totalMiles = "total_miles"
        case updatedAt = "updated_at"
    }
}

nonisolated struct Friendship: Codable, Sendable, Identifiable {
    let id: String
    let userId1: String
    let userId2: String
    let status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId1 = "user_id_1"
        case userId2 = "user_id_2"
        case status
        case createdAt = "created_at"
    }
}

nonisolated struct CityNode: Codable, Sendable, Identifiable {
    var id: String { cityId }
    let cityId: String
    let cityName: String
    let state: String
    let latitude: Double
    let longitude: Double
    let ownerUserId: String?
    let ownerUsername: String?
    let ownerColor: String?
    let capturedAt: Date?

    enum CodingKeys: String, CodingKey {
        case cityId = "city_id"
        case cityName = "city_name"
        case state
        case latitude
        case longitude
        case ownerUserId = "owner_user_id"
        case ownerUsername = "owner_username"
        case ownerColor = "owner_color"
        case capturedAt = "captured_at"
    }
}

struct FriendInfo: Identifiable {
    var id: String { profile.id }
    let profile: UserProfile
    let stats: UserStats?
    let nodesOwned: Int
}

nonisolated enum DiscoveryType: Sendable {
    case hex
    case county(name: String, state: String)
    case state(name: String)
    case city(name: String, state: String)
}
