import Foundation

/// Installs and tracks marketplace layers on this device. Installed
/// definitions are persisted as JSON in UserDefaults and registered into the
/// overlay registry at launch; install counts are bumped on the server.
@MainActor
@Observable
final class MarketplaceService {
    static let shared = MarketplaceService()

    private static let installedKey = "marketplace.installed"

    private(set) var installed: [OverlayDefinitionDTO] = []
    var catalog: [OverlayDefinitionDTO] = []
    var isLoadingCatalog = false
    var lastCatalogError: String?

    private init() {
        loadInstalled()
    }

    // MARK: Queries

    func isInstalled(_ definition: OverlayDefinitionDTO) -> Bool {
        installed.contains { $0.id == definition.id }
    }

    /// Whether the given layer needs the All-Access Pass.
    static func requiresPass(_ definition: OverlayDefinitionDTO) -> Bool {
        definition.isPaid
    }

    /// The definition's category, falling back to `other`.
    static func category(_ definition: OverlayDefinitionDTO) -> OverlayCategory {
        OverlayCategory(rawValue: definition.category) ?? .other
    }

    // MARK: Install / uninstall

    /// Installs the layer locally and bumps the server install counter.
    func install(_ definition: OverlayDefinitionDTO) async {
        guard !isInstalled(definition) else { return }
        installed.append(definition)
        persistInstalled()

        OverlayRegistry.shared.register(MarketplaceOverlayProvider(definition: definition))
        OverlayRegistry.shared.setEnabled(true, for: "marketplace.\(definition.id)")

        await SupabaseService.shared.incrementOverlayInstalls(overlayId: definition.id)
        // Phase 4 analytics: daily per-overlay install event (powers sparklines).
        if let userId = UserProfileService.shared.userId {
            await SupabaseService.shared.logOverlayInstall(overlayId: definition.id, userId: userId)
        }
    }

    func uninstall(_ definition: OverlayDefinitionDTO) {
        installed.removeAll { $0.id == definition.id }
        persistInstalled()
        OverlayRegistry.shared.setEnabled(false, for: "marketplace.\(definition.id)")
        OverlayRegistry.shared.unregister(providerId: "marketplace.\(definition.id)")
    }

    // MARK: Catalog

    func refreshCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        catalog = await SupabaseService.shared.fetchPublicOverlays()
        lastCatalogError = catalog.isEmpty && SupabaseService.shared.isConfigured
            ? "Couldn't reach the marketplace. Check your connection."
            : nil
    }

    // MARK: Persistence

    private func loadInstalled() {
        guard let data = UserDefaults.standard.data(forKey: Self.installedKey) else { return }
        let definitions = try? JSONDecoder().decode([OverlayDefinitionDTO].self, from: data)
        installed = definitions ?? []
    }

    private func persistInstalled() {
        guard let data = try? JSONEncoder().encode(installed) else { return }
        UserDefaults.standard.set(data, forKey: Self.installedKey)
    }
}
