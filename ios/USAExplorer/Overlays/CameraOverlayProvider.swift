import Foundation
import CoreLocation
import MapKit

/// Camera-awareness overlay (DeFlock-style reference implementation).
///
/// Two feature sources are merged:
/// 1. A versioned seed dataset of publicly documented fixed camera sites
///    (toll gantries, red-light corridors) shipped with the app.
/// 2. Crowd-contributed ALPR sightings persisted locally and synced to the
///    `camera_points` table, with photographic-verification metadata
///    (confirmations raise confidence; the overlay shows provenance).
@MainActor
final class CameraOverlayProvider: OverlayProvider {

    // Conformance is intentionally main-actor isolated (see OverlayProvider).
    let id = "cameras"
    let name = "Camera Awareness"
    let summary = "Fixed ALPR, toll gantries and red-light cameras with provenance and confidence."
    let systemImage = "video.fill"
    let version = "seed-1.0.1"
    let isSensitive = true

    private let database = DatabaseService.shared
    private var seedFeatures: [OverlayFeature] = []
    private var contributedFeatures: [OverlayFeature] = []
    private(set) var featureCount = 0

    init() {
        loadSeedData()
        reloadContributions()
    }

    private func loadSeedData() {
        guard let url = Bundle.main.url(forResource: "CameraSeedData", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        guard let records = try? decoder.decode([SeedCamera].self, from: data) else { return }
        seedFeatures = records.map { record in
            OverlayFeature(
                id: "seed.\(record.id)",
                providerId: id,
                kind: OverlayFeatureKind(rawValue: record.kind) ?? .alprFixed,
                coordinate: CLLocationCoordinate2D(latitude: record.lat, longitude: record.lng),
                title: record.name,
                subtitle: record.note,
                confidence: record.confidence,
                lastVerified: record.lastVerified,
                expiresAt: nil,
                confirmations: record.confirmations,
                source: record.source,
                isUserContributed: false
            )
        }
        recomputeCount()
    }

    private func reloadContributions() {
        contributedFeatures = database.fetchOverlayPoints(kind: "camera").map { point in
            OverlayFeature(
                id: point.id,
                providerId: id,
                kind: OverlayFeatureKind(rawValue: point.subkind) ?? .alprFixed,
                coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                title: point.title,
                subtitle: point.note,
                confidence: point.confidence,
                lastVerified: point.createdAt,
                expiresAt: nil,
                confirmations: point.confirmations,
                source: "community",
                isUserContributed: true
            )
        }
        recomputeCount()
    }

    private func recomputeCount() {
        featureCount = seedFeatures.count + contributedFeatures.count
    }

    func features(in region: MKCoordinateRegion) async -> [OverlayFeature] {
        let box = OverlayGeometry.boundingBox(of: region)
        return (seedFeatures + contributedFeatures)
            .filter { OverlayGeometry.contains($0.coordinate, in: box) }
    }

    func submit(kind: OverlayFeatureKind, coordinate: CLLocationCoordinate2D, note: String) async -> OverlayFeature? {
        let featureId = "cam-\(UUID().uuidString.prefix(8)).\(Int64(Date().timeIntervalSince1970))"
        let feature = OverlayFeature(
            id: featureId,
            providerId: id,
            kind: kind,
            coordinate: coordinate,
            title: kind.displayName,
            subtitle: note.isEmpty ? "Community reported" : note,
            confidence: 0.4,
            lastVerified: Int64(Date().timeIntervalSince1970),
            expiresAt: nil,
            confirmations: 0,
            source: "community",
            isUserContributed: true
        )

        database.insertOverlayPoint(
            id: feature.id,
            family: "camera",
            subkind: kind.rawValue,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            title: feature.title,
            note: feature.subtitle,
            confidence: feature.confidence,
            confirmations: 0,
            createdAt: feature.lastVerified
        )

        Task {
            await SupabaseService.shared.uploadCameraPoint(
                id: feature.id,
                kind: kind.rawValue,
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                note: feature.subtitle
            )
        }

        reloadContributions()
        return feature
    }

    /// "Still there" verification: each confirmation raises confidence toward 0.99.
    func confirm(_ feature: OverlayFeature) async -> OverlayFeature? {
        let updated = OverlayFeature(
            id: feature.id,
            providerId: feature.providerId,
            kind: feature.kind,
            coordinate: feature.coordinate,
            title: feature.title,
            subtitle: feature.subtitle,
            confidence: min(0.99, feature.confidence + 0.1),
            lastVerified: Int64(Date().timeIntervalSince1970),
            expiresAt: nil,
            confirmations: feature.confirmations + 1,
            source: feature.source,
            isUserContributed: feature.isUserContributed
        )
        database.updateOverlayPointVerification(
            id: feature.id,
            confidence: updated.confidence,
            confirmations: updated.confirmations,
            verifiedAt: updated.lastVerified
        )
        reloadContributions()
        return updated
    }
}

nonisolated private struct SeedCamera: Sendable, Decodable {
    let id: String
    let name: String
    let kind: String
    let lat: Double
    let lng: Double
    let confidence: Double
    let lastVerified: Int64
    let confirmations: Int
    let source: String
    let note: String
}
