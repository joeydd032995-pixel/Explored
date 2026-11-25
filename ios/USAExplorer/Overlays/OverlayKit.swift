import Foundation
import CoreLocation
import MapKit

// MARK: - Core Overlay Types
//
// Protocol-oriented overlay system. Every data layer on the map is an
// independent, versioned provider registered with the OverlayRegistry.
// Providers source features from static GeoJSON, local crowd contributions,
// or authenticated real-time feeds — the map and UI never know the difference.

nonisolated struct OverlayFeature: Sendable, Identifiable, Hashable {
    let id: String
    let providerId: String
    let kind: OverlayFeatureKind
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    /// 0.0 – 1.0. Crowd-sourced features gain confidence with verifications.
    let confidence: Double
    /// Epoch seconds of the last human verification of this feature.
    let lastVerified: Int64
    /// Epoch seconds after which an ephemeral feature disappears. nil = permanent.
    let expiresAt: Int64?
    let confirmations: Int
    let source: String
    let isUserContributed: Bool

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (a: OverlayFeature, b: OverlayFeature) -> Bool { a.id == b.id }

    /// Time-decayed relevance in 0.0 – 1.0 for ephemeral features.
    func relevance(now: Int64, halfLifeMinutes: Double) -> Double {
        guard let expiresAt else { return confidence }
        let remaining = Double(max(0, expiresAt - now))
        let total = max(1, halfLifeMinutes * 60)
        return confidence * min(1, remaining / total)
    }
}

nonisolated enum OverlayFeatureKind: String, Sendable, CaseIterable {
    // Camera-awareness overlay
    case alprFixed = "alpr_fixed"
    case alprMobile = "alpr_mobile"
    case tollGantry = "toll_gantry"
    case redLight = "red_light"

    // Real-time hazard & enforcement overlay
    case police = "police"
    case speedTrap = "speed_trap"
    case accident = "accident"
    case roadHazard = "road_hazard"
    case construction = "construction"

    // Creator marketplace layers (generic point layers)
    case custom = "custom"

    var displayName: String {
        switch self {
        case .alprFixed: return "Fixed ALPR"
        case .alprMobile: return "Mobile ALPR"
        case .tollGantry: return "Toll Gantry"
        case .redLight: return "Red Light Cam"
        case .police: return "Police Reported"
        case .speedTrap: return "Speed Trap"
        case .accident: return "Accident"
        case .roadHazard: return "Road Hazard"
        case .construction: return "Construction"
        case .custom: return "Point"
        }
    }

    var systemImage: String {
        switch self {
        case .alprFixed: return "video.fill"
        case .alprMobile: return "video.bubble.left.fill"
        case .tollGantry: return "dollarsign.circle.fill"
        case .redLight: return "traffic.light.fill"
        case .police: return "shield.lefthalf.filled"
        case .speedTrap: return "speedometer"
        case .accident: return "car.rear.and.collision.up"
        case .roadHazard: return "exclamationmark.triangle.fill"
        case .construction: return "cone.fill"
        case .custom: return "mappin"
        }
    }

    var isEphemeral: Bool {
        switch self {
        case .police, .speedTrap, .accident, .roadHazard, .construction: return true
        default: return false
        }
    }

    /// Default lifetime in minutes for ephemeral features.
    var defaultLifetimeMinutes: Int {
        switch self {
        case .police: return 45
        case .speedTrap: return 90
        case .accident: return 120
        case .roadHazard: return 360
        case .construction: return 1440
        default: return 0
        }
    }
}

// MARK: - Provider Protocol

@MainActor
protocol OverlayProvider: Identifiable {
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    var systemImage: String { get }
    var version: String { get }
    /// True when the layer carries sensitive content (cameras, enforcement)
    /// and needs elevated moderation on contribution.
    var isSensitive: Bool { get }
    var featureCount: Int { get }

    /// Features intersecting the given region, already filtered for expiry.
    func features(in region: MKCoordinateRegion) async -> [OverlayFeature]

    /// Submit a crowd contribution. Returns the created feature on success.
    func submit(kind: OverlayFeatureKind, coordinate: CLLocationCoordinate2D, note: String) async -> OverlayFeature?

    /// Confirm an existing feature ("still there" / "confirmed"), raising
    /// confidence and, for ephemeral features, extending expiry.
    func confirm(_ feature: OverlayFeature) async -> OverlayFeature?
}

extension OverlayProvider {
    func confirm(_ feature: OverlayFeature) async -> OverlayFeature? { nil }
}

// MARK: - Registry

@Observable
@MainActor
final class OverlayRegistry {
    static let shared = OverlayRegistry()

    private(set) var providers: [any OverlayProvider] = []
    var enabledProviderIds: Set<String> = [] {
        didSet { persistEnabledIds() }
    }
    private(set) var isLoading = false

    init() {
        providers = [
            CameraOverlayProvider(),
            HazardOverlayProvider()
        ]
        for provider in MarketplaceService.shared.installed.map(MarketplaceOverlayProvider.init) {
            register(provider, enableIfNew: false)
        }
        let stored = UserDefaults.standard.stringArray(forKey: "overlay.enabled")
        enabledProviderIds = Set(stored ?? providers.map { $0.id })
    }

    /// Registers an installed provider. By default a newly installed layer
    /// starts enabled; restored-from-storage providers keep prior state.
    func register(_ provider: any OverlayProvider, enableIfNew: Bool = true) {
        guard !providers.contains(where: { $0.id == provider.id }) else { return }
        providers.append(provider)
        if enableIfNew, !((UserDefaults.standard.stringArray(forKey: "overlay.enabled") ?? []).contains(provider.id)) {
            enabledProviderIds.insert(provider.id)
        }
    }

    func unregister(providerId: String) {
        providers.removeAll { $0.id == providerId }
    }

    var enabledProviders: [any OverlayProvider] {
        providers.filter { enabledProviderIds.contains($0.id) }
    }

    func provider(_ id: String) -> (any OverlayProvider)? {
        providers.first { $0.id == id }
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        if enabled {
            enabledProviderIds.insert(id)
        } else {
            enabledProviderIds.remove(id)
        }
    }

    func isEnabled(_ id: String) -> Bool {
        enabledProviderIds.contains(id)
    }

    /// Combined feature set for the current viewport, clipped to enabled
    /// providers and expired ephemeral features removed.
    func features(in region: MKCoordinateRegion) async -> [OverlayFeature] {
        isLoading = true
        defer { isLoading = false }
        let start = CFAbsoluteTimeGetCurrent()
        let enabled = enabledProviders
        var all: [OverlayFeature] = []
        for provider in enabled {
            all.append(contentsOf: await provider.features(in: region))
        }
        // Phase 4 analytics: aggregate load timing, never coordinates.
        MetricsService.shared.recordOverlayLoad(
            ms: (CFAbsoluteTimeGetCurrent() - start) * 1000,
            activeCount: enabled.count
        )
        let now = Int64(Date().timeIntervalSince1970)
        return all.filter { feature in
            guard let expiresAt = feature.expiresAt else { return true }
            return expiresAt > now
        }
    }

    func pruneExpired() {
        for provider in providers where provider is HazardOverlayProvider {
            Task { (provider as? HazardOverlayProvider)?.pruneExpired() }
        }
    }

    private func persistEnabledIds() {
        UserDefaults.standard.set(Array(enabledProviderIds), forKey: "overlay.enabled")
    }
}

// MARK: - Region Helpers

nonisolated enum OverlayGeometry {
    static func boundingBox(of region: MKCoordinateRegion) -> (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) {
        (
            region.center.latitude - region.span.latitudeDelta / 2,
            region.center.latitude + region.span.latitudeDelta / 2,
            region.center.longitude - region.span.longitudeDelta / 2,
            region.center.longitude + region.span.longitudeDelta / 2
        )
    }

    static func contains(_ coordinate: CLLocationCoordinate2D, in box: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)) -> Bool {
        coordinate.latitude >= box.minLat && coordinate.latitude <= box.maxLat &&
        coordinate.longitude >= box.minLng && coordinate.longitude <= box.maxLng
    }
}
