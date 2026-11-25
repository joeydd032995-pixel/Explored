import Foundation

nonisolated struct StateStatRecord: Sendable {
    let stateId: String
    let lastVisit: Int64
    let distanceMeters: Double
}

nonisolated struct StoredOverlayPoint: Sendable, Identifiable {
    let id: String
    let subkind: String
    let latitude: Double
    let longitude: Double
    let title: String
    let note: String
    let confidence: Double
    let confirmations: Int
    let createdAt: Int64
}

nonisolated struct StoredHazardReport: Sendable, Identifiable {
    let id: String
    let kind: String
    let latitude: Double
    let longitude: Double
    let createdAt: Int64
    let expiresAt: Int64
    let confirmations: Int
}

nonisolated struct HazardReportDTO: Sendable, Identifiable, Codable {
    let id: String
    let kind: String
    let lat: Double
    let lng: Double
    let createdAt: Int64
    let expiresAt: Int64
    let confirmations: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, lat, lng
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case confirmations
    }
}

nonisolated struct HazardReportInsert: Codable {
    let id: String
    let kind: String
    let lat: Double
    let lng: Double
    let createdAt: Int64
    let expiresAt: Int64
    let confirmations: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, lat, lng, confirmations
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

nonisolated struct CameraPointInsert: Codable {
    let id: String
    let kind: String
    let lat: Double
    let lng: Double
    let note: String
    let confidence: Double
    let confirmations: Int
}

nonisolated struct ConfirmHazardReportParams: Codable {
    let pReportId: String
    let pNewExpiry: Int64

    enum CodingKeys: String, CodingKey {
        case pReportId = "p_report_id"
        case pNewExpiry = "p_new_expiry"
    }
}
