import Foundation

// MARK: - Territory Games (phase 4)
//
// Typed DTOs for game_sessions / game_players / game_events plus the social
// feed, metrics, cell-claim sync and boundary-release payloads. All
// client-identified (no auth): user ids come from UserProfileService.

// MARK: Game mode

nonisolated enum GameMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case kingOfTheHill = "king_of_the_hill"
    case claimAndDefend = "claim_and_defend"
    case contestedNodes = "contested_nodes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kingOfTheHill: return "King of the Hill"
        case .claimAndDefend: return "Claim & Defend"
        case .contestedNodes: return "Contested Nodes"
        }
    }

    var systemImage: String {
        switch self {
        case .kingOfTheHill: return "crown.fill"
        case .claimAndDefend: return "shield.lefthalf.filled"
        case .contestedNodes: return "dot.circle.and.cursorarrow"
        }
    }

    var rules: String {
        switch self {
        case .kingOfTheHill:
            return "One hill. Stay inside its circle to earn a point every second. Last explorer standing on the hill wins."
        case .claimAndDefend:
            return "Three hills whose value decays while nobody attends them. Rotate constantly — abandoned hills are worth nothing."
        case .contestedNodes:
            return "Four nodes. Stand on a node longer than its owner to flip it. Owned nodes drip points until someone takes them."
        }
    }
}

// MARK: Session params (JSONB)

nonisolated struct GameTarget: Codable, Sendable, Hashable {
    let lat: Double
    let lng: Double
    var label: String
}

nonisolated struct GameParams: Codable, Sendable {
    /// Hills for KOTH/claim&defend, nodes for contested_nodes.
    var targets: [GameTarget]
    /// Capture radius in meters.
    var radiusM: Double
    /// Seconds of unbroken presence needed to flip a contested node.
    var holdSeconds: Int

    enum CodingKeys: String, CodingKey {
        case targets
        case radiusM = "radius_m"
        case holdSeconds = "hold_seconds"
    }
}

// MARK: Sessions

nonisolated struct GameSessionDTO: Codable, Sendable, Identifiable {
    let id: String
    let mode: String
    let hostUserId: String
    let hostName: String
    let status: String
    let params: GameParams?
    let inviteCode: String
    let durationS: Int
    let createdAt: String?
    let startedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, mode, status, params
        case hostUserId = "host_user_id"
        case hostName = "host_name"
        case inviteCode = "invite_code"
        case durationS = "duration_s"
        case createdAt = "created_at"
        case startedAt = "started_at"
    }

    var gameMode: GameMode? { GameMode(rawValue: mode) }
    var isLive: Bool { status == "live" }
    var isEnded: Bool { status == "ended" }
}

nonisolated struct GameSessionInsert: Codable {
    let id: String
    let mode: String
    let hostUserId: String
    let hostName: String
    let status: String
    let params: GameParams
    let inviteCode: String
    let durationS: Int

    enum CodingKeys: String, CodingKey {
        case id, mode, status, params
        case hostUserId = "host_user_id"
        case hostName = "host_name"
        case inviteCode = "invite_code"
        case durationS = "duration_s"
    }
}

/// Partial update for a session (start / end / patch params).
nonisolated struct GameSessionPatch: Codable {
    var status: String?
    var params: GameParams?
    var startedAt: String?
    var endedAt: String?

    enum CodingKeys: String, CodingKey {
        case status, params
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

// MARK: Players

nonisolated struct GamePlayerDTO: Codable, Sendable, Identifiable {
    let sessionId: String
    let userId: String
    let displayName: String
    let color: String
    let lat: Double?
    let lng: Double?
    let score: Double
    let lastPing: Int64

    var id: String { "\(sessionId)-\(userId)" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sessionId = "session_id"
        case displayName = "display_name"
        case color, lat, lng, score
        case lastPing = "last_ping"
    }
}

nonisolated struct GamePlayerUpsert: Codable {
    let sessionId: String
    let userId: String
    let displayName: String
    let color: String
    var lat: Double?
    var lng: Double?
    var score: Double
    var lastPing: Int64

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sessionId = "session_id"
        case displayName = "display_name"
        case color, lat, lng, score
        case lastPing = "last_ping"
    }
}

// MARK: Events (append-only scoring log)

nonisolated struct GameEventPayload: Codable, Sendable {
    var targetIndex: Int?
    var label: String?

    enum CodingKeys: String, CodingKey {
        case targetIndex = "target_index"
        case label
    }
}

nonisolated struct GameEventDTO: Codable, Sendable, Identifiable {
    let id: String
    let sessionId: String
    let userId: String
    let kind: String
    let payload: GameEventPayload?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, payload
        case sessionId = "session_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct GameEventInsert: Codable {
    let sessionId: String
    let userId: String
    let kind: String
    let payload: GameEventPayload

    enum CodingKeys: String, CodingKey {
        case kind, payload
        case sessionId = "session_id"
        case userId = "user_id"
    }
}

// MARK: - Social feed

nonisolated struct SocialEventDTO: Codable, Sendable, Identifiable {
    let id: String
    let userId: String
    let username: String
    let kind: String
    let title: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case userId = "user_id"
        case username
        case createdAt = "created_at"
    }

    var systemImage: String {
        switch kind {
        case "state": return "flag.fill"
        case "county": return "building.columns.fill"
        case "city": return "building.2.fill"
        case "layer": return "square.3.layers.3d.top.filled"
        case "game": return "gamecontroller.fill"
        case "milestone": return "trophy.fill"
        default: return "sparkles"
        }
    }
}

nonisolated struct SocialEventInsert: Codable {
    let userId: String
    let username: String
    let kind: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case kind, title, username
        case userId = "user_id"
    }
}

// MARK: - Metrics (aggregates only, never coordinates)

nonisolated struct AppMetricInsert: Codable {
    let userId: String
    let metric: String
    let value: Double

    enum CodingKeys: String, CodingKey {
        case metric, value
        case userId = "user_id"
    }
}

nonisolated struct DailyInstallDTO: Codable, Sendable, Identifiable {
    let day: String
    let installs: Int

    var id: String { day }
}

// MARK: - Cell-claim sync

nonisolated struct UpsertCellClaimParams: Codable {
    let pUserId: String
    let pCell: String
    let pLevel: Int
    let pEntityId: String
    let pFirstSeen: Int64
    let pLastSeen: Int64
    let pVisits: Int

    enum CodingKeys: String, CodingKey {
        case pUserId = "p_user_id"
        case pCell = "p_cell"
        case pLevel = "p_level"
        case pEntityId = "p_entity_id"
        case pFirstSeen = "p_first_seen"
        case pLastSeen = "p_last_seen"
        case pVisits = "p_visits"
    }
}

nonisolated struct CellClaimDTO: Codable, Sendable {
    let cell: String
    let entityLevel: Int
    let entityId: String
    let firstSeen: Int64
    let lastSeen: Int64
    let visits: Int

    enum CodingKeys: String, CodingKey {
        case cell, visits
        case entityLevel = "entity_level"
        case entityId = "entity_id"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }
}

nonisolated struct OverlayDailyInstallsParams: Codable {
    let pOverlayId: String

    enum CodingKeys: String, CodingKey {
        case pOverlayId = "p_overlay_id"
    }
}

nonisolated struct DeleteMyCellClaimsParams: Codable {
    let pUserId: String

    enum CodingKeys: String, CodingKey {
        case pUserId = "p_user_id"
    }
}

// MARK: - Overlay install events + boundary releases

nonisolated struct OverlayInstallEventInsert: Codable {
    let overlayId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case overlayId = "overlay_id"
        case userId = "user_id"
    }
}

nonisolated struct BoundaryReleaseDTO: Codable, Sendable, Identifiable {
    struct ChangedEntity: Codable, Sendable {
        let level: Int
        let id: String
        let name: String
    }

    let version: String
    let changedEntities: [ChangedEntity]
    let releasedAt: String?

    var id: String { version }

    enum CodingKeys: String, CodingKey {
        case version
        case changedEntities = "changed_entities"
        case releasedAt = "released_at"
    }
}

// MARK: - Invite codes

nonisolated enum InviteCode {
    /// Unambiguous alphabet (no 0/O/1/I).
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func generate() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
