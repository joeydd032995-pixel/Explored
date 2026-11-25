import Foundation
import MapKit

/// A single installed marketplace layer as a map provider. Reads its points
/// from the layer definition's spec; contributions are read-only in v1.
@MainActor
final class MarketplaceOverlayProvider: OverlayProvider {
    let definition: OverlayDefinitionDTO

    init(definition: OverlayDefinitionDTO) {
        self.definition = definition
    }

    var id: String { "marketplace.\(definition.id)" }
    var name: String { definition.name }
    var summary: String { definition.summary }
    var systemImage: String { definition.systemImage }
    var version: String { "v\(definition.version)" }
    var isSensitive: Bool {
        OverlayCategory(rawValue: definition.category)?.isSensitive ?? false
    }
    var featureCount: Int { definition.spec.features.count }

    func features(in region: MKCoordinateRegion) async -> [OverlayFeature] {
        let box = OverlayGeometry.boundingBox(of: region)
        let now = Int64(Date().timeIntervalSince1970)
        return definition.spec.features.compactMap { point in
            let coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
            guard OverlayGeometry.contains(coordinate, in: box) else { return nil }
            let kind = OverlayFeatureKind(rawValue: definition.spec.featureKind ?? "custom") ?? .custom
            return OverlayFeature(
                id: "\(definition.id).\(point.id)",
                providerId: id,
                kind: kind,
                coordinate: coordinate,
                title: point.title,
                subtitle: point.note,
                confidence: 0.8,
                lastVerified: now,
                expiresAt: nil,
                confirmations: 0,
                source: "Creator layer · \(definition.name)",
                isUserContributed: false
            )
        }
    }

    // Marketplace layers are read-only in v1; submissions return nil.
    func submit(kind: OverlayFeatureKind, coordinate: CLLocationCoordinate2D, note: String) async -> OverlayFeature? {
        nil
    }
}
