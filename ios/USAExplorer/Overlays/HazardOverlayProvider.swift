import Foundation
import CoreLocation
import MapKit

/// Real-time hazard & enforcement overlay (Waze-style reference
/// implementation). Ephemeral, community-reported features — police presence,
/// speed traps, accidents, road hazards, construction — that cluster in the
/// UI, decay over time, and expire automatically.
///
/// Reports are persisted locally (offline-first) and mirrored to the
/// `hazard_reports` table when the backend is configured; remote reports are
/// merged by id so the layer converges across devices.
@MainActor
final class HazardOverlayProvider: OverlayProvider {
    let id = "hazards"
    let name = "Live Hazards"
    let summary = "Community-reported police, speed traps, accidents and road hazards. Decays over time."
    let systemImage = "exclamationmark.triangle.fill"
    let version = "1.0.0"
    let isSensitive = true

    private let database = DatabaseService.shared
    private var reports: [OverlayFeature] = []
    private var lastRemoteFetch: Date?
    private(set) var featureCount = 0

    func features(in region: MKCoordinateRegion) async -> [OverlayFeature] {
        pruneExpired()
        refreshRemoteIfNeeded()

        let box = OverlayGeometry.boundingBox(of: region)
        let now = Int64(Date().timeIntervalSince1970)
        return reports
            .filter { $0.expiresAt == nil || $0.expiresAt! > now }
            .filter { OverlayGeometry.contains($0.coordinate, in: box) }
    }

    func submit(kind: OverlayFeatureKind, coordinate: CLLocationCoordinate2D, note: String) async -> OverlayFeature? {
        let now = Int64(Date().timeIntervalSince1970)
        let feature = OverlayFeature(
            id: "hz-\(UUID().uuidString.prefix(8)).\(now)",
            providerId: id,
            kind: kind,
            coordinate: coordinate,
            title: kind.displayName,
            subtitle: note.isEmpty ? "Community report" : note,
            confidence: 0.6,
            lastVerified: now,
            expiresAt: now + Int64(kind.defaultLifetimeMinutes) * 60,
            confirmations: 0,
            source: "community",
            isUserContributed: true
        )

        database.insertHazardReport(
            id: feature.id,
            kind: kind.rawValue,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            createdAt: now,
            expiresAt: feature.expiresAt ?? 0,
            confirmations: 0
        )

        Task {
            await SupabaseService.shared.uploadHazardReport(
                id: feature.id,
                kind: kind.rawValue,
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                createdAt: now,
                expiresAt: feature.expiresAt ?? 0
            )
        }

        reloadFromLocal()
        HapticService.shared.reportSubmitted()
        return feature
    }

    /// Confirming an ephemeral report extends its expiry and bumps confidence.
    func confirm(_ feature: OverlayFeature) async -> OverlayFeature? {
        guard feature.kind.isEphemeral else { return nil }
        let now = Int64(Date().timeIntervalSince1970)
        let extendedExpiry = max(feature.expiresAt ?? 0, now) + Int64(feature.kind.defaultLifetimeMinutes / 2) * 60
        let updated = OverlayFeature(
            id: feature.id,
            providerId: feature.providerId,
            kind: feature.kind,
            coordinate: feature.coordinate,
            title: feature.title,
            subtitle: feature.subtitle,
            confidence: min(0.99, feature.confidence + 0.08),
            lastVerified: now,
            expiresAt: extendedExpiry,
            confirmations: feature.confirmations + 1,
            source: feature.source,
            isUserContributed: feature.isUserContributed
        )
        database.updateHazardReport(
            id: feature.id,
            expiresAt: extendedExpiry,
            confirmations: updated.confirmations
        )
        Task { await SupabaseService.shared.confirmHazardReport(id: feature.id, expiresAt: extendedExpiry) }
        reloadFromLocal()
        return updated
    }

    func pruneExpired() {
        let now = Int64(Date().timeIntervalSince1970)
        if database.deleteExpiredHazardReports(now: now) {
            reloadFromLocal()
        } else {
            recomputeCount()
        }
    }

    private func reloadFromLocal() {
        reports = database.fetchActiveHazardReports(now: Int64(Date().timeIntervalSince1970)).map { row in
            OverlayFeature(
                id: row.id,
                providerId: id,
                kind: OverlayFeatureKind(rawValue: row.kind) ?? .roadHazard,
                coordinate: CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude),
                title: (OverlayFeatureKind(rawValue: row.kind) ?? .roadHazard).displayName,
                subtitle: "Community report",
                confidence: min(0.99, 0.6 + Double(row.confirmations) * 0.08),
                lastVerified: row.createdAt,
                expiresAt: row.expiresAt,
                confirmations: row.confirmations,
                source: "community",
                isUserContributed: true
            )
        }
        recomputeCount()
    }

    private func recomputeCount() {
        let now = Int64(Date().timeIntervalSince1970)
        featureCount = reports.filter { $0.expiresAt == nil || $0.expiresAt! > now }.count
    }

    /// Remote merge, throttled to one fetch per 30 s.
    private func refreshRemoteIfNeeded() {
        if let lastRemoteFetch, Date().timeIntervalSince(lastRemoteFetch) < 30 { return }
        lastRemoteFetch = Date()
        Task { [weak self] in
            let remote = await SupabaseService.shared.fetchActiveHazardReports()
            guard let self, !remote.isEmpty else { return }
            for dto in remote {
                self.database.insertHazardReport(
                    id: dto.id,
                    kind: dto.kind,
                    latitude: dto.lat,
                    longitude: dto.lng,
                    createdAt: dto.createdAt,
                    expiresAt: dto.expiresAt,
                    confirmations: dto.confirmations
                )
            }
            self.reloadFromLocal()
        }
    }
}
