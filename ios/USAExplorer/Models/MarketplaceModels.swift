import Foundation

// MARK: - Marketplace DTOs
//
// Typed Codable structs for the overlay_definitions / overlay_reviews tables
// (see supabase/migrations). The layer's `spec` JSONB carries the plugin
// contract: feature kind, category, style, and the point features.

nonisolated struct OverlaySpecFeature: Sendable, Codable, Identifiable {
    let id: String
    let lat: Double
    let lng: Double
    var title: String
    var note: String
}

nonisolated struct OverlaySpec: Sendable, Codable {
    /// Raw OverlayFeatureKind value for rendering ("custom" when absent).
    let featureKind: String?
    /// Category id: "navigation", "cameras", "enforcement", "fun", "other".
    let category: String?
    let features: [OverlaySpecFeature]

    enum CodingKeys: String, CodingKey {
        case featureKind = "feature_kind"
        case category
        case features
    }
}

nonisolated struct OverlayDefinitionDTO: Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let version: Int
    let spec: OverlaySpec
    let visibility: String
    let pricing: String
    let priceUsd: Double?
    let category: String
    let summary: String
    let systemImage: String
    let status: String
    let ratingAvg: Double
    let ratingCount: Int
    let installs: Int
    let creatorUserId: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, version, spec, visibility, pricing, category, summary, status, installs
        case priceUsd = "price_usd"
        case systemImage = "system_image"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case creatorUserId = "creator_user_id"
        case updatedAt = "updated_at"
    }

    var isPaid: Bool { pricing == "paid" }
    var isLive: Bool { status == "active" && visibility == "public" }
    var statusLabel: String {
        switch status {
        case "pending_review": return "Pending review"
        case "hidden": return "Hidden"
        default: return "Active"
        }
    }
}

nonisolated struct OverlayDefinitionInsert: Codable {
    let id: String
    let creatorUserId: String
    let name: String
    let version: Int
    let spec: OverlaySpec
    let visibility: String
    let pricing: String
    let category: String
    let summary: String
    let systemImage: String
    let status: String
    let coordinateSystem: String

    enum CodingKeys: String, CodingKey {
        case id, name, version, spec, visibility, pricing, category, summary, status
        case creatorUserId = "creator_user_id"
        case systemImage = "system_image"
        case coordinateSystem = "coordinate_system"
    }
}

nonisolated struct OverlayReviewDTO: Sendable, Identifiable, Codable {
    let id: String
    let overlayId: String
    let userId: String
    let rating: Int
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, rating, body
        case overlayId = "overlay_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct OverlayReviewInsert: Codable {
    let overlayId: String
    let userId: String
    let rating: Int
    let body: String

    enum CodingKeys: String, CodingKey {
        case rating, body
        case overlayId = "overlay_id"
        case userId = "user_id"
    }
}

nonisolated struct OverlayReportInsert: Codable {
    let overlayId: String
    let reporterUserId: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case reason
        case overlayId = "overlay_id"
        case reporterUserId = "reporter_user_id"
    }
}

nonisolated struct IncrementOverlayInstallsParams: Codable {
    let pOverlayId: String

    enum CodingKeys: String, CodingKey {
        case pOverlayId = "p_overlay_id"
    }
}

nonisolated struct OverlaySpecUpdate: Codable {
    let spec: OverlaySpec
    let version: Int
}

// MARK: - Categories

nonisolated enum OverlayCategory: String, CaseIterable, Sendable, Identifiable {
    case navigation
    case cameras
    case enforcement
    case fun
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .navigation: return "Navigation"
        case .cameras: return "Cameras"
        case .enforcement: return "Enforcement"
        case .fun: return "Fun"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .navigation: return "mappin.and.ellipse"
        case .cameras: return "video.fill"
        case .enforcement: return "shield.lefthalf.filled"
        case .fun: return "sparkles"
        case .other: return "square.grid.2x2"
        }
    }

    /// Cameras and enforcement get elevated moderation before going live.
    var isSensitive: Bool {
        switch self {
        case .cameras, .enforcement: return true
        default: return false
        }
    }
}
