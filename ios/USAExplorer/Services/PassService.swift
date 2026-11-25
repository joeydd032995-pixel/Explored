import Foundation
import RevenueCat

/// The All-Access Pass: one monthly subscription that unlocks every paid
/// marketplace layer. Ties the purchase to the app's local explorer id via
/// `Purchases.logIn`, so the pass follows the account across reinstalls and
/// devices. Validated live when possible, cached on device with a 24-hour
/// offline grace so short connectivity gaps don't lock paid layers.
@MainActor
@Observable
final class PassService {
    static let shared = PassService()

    static let entitlementId = "all_access"
    private static let cachedActiveKey = "pass.cached_active"
    private static let lastVerifiedKey = "pass.last_verified"
    /// How long a previously verified pass stays valid offline.
    private static let graceSeconds: TimeInterval = 24 * 60 * 60

    private(set) var isConfigured = false
    private(set) var isLiveVerified = false
    private(set) var monthlyPackage: Package?
    private(set) var isPurchasing = false
    private(set) var lastError: String?

    private init() {
        let apiKey = Config.allValues["RORK_PUBLIC_REVENUECAT_IOS_API_KEY"] ?? ""
        guard !apiKey.isEmpty else { return }
        Purchases.configure(withAPIKey: apiKey)
        isConfigured = true

        // Attach the purchase to the local explorer identity so the pass
        // survives reinstalls and follows the same id across devices.
        if let userId = UserProfileService.shared.userId {
            Task { try? await Purchases.shared.logIn(userId) }
        }

        Task { await refresh() }
    }

    var priceLabel: String? {
        guard let monthlyPackage else { return nil }
        return "\(monthlyPackage.localizedPriceString) / month"
    }

    /// Pass status: live check wins; otherwise a cached verification within
    /// the 24-hour grace window still counts as active.
    var isPassActive: Bool {
        if isLiveVerified {
            return UserDefaults.standard.bool(forKey: Self.cachedActiveKey)
        }
        guard UserDefaults.standard.bool(forKey: Self.cachedActiveKey) else { return false }
        let lastVerified = UserDefaults.standard.double(forKey: Self.lastVerifiedKey)
        return Date().timeIntervalSince1970 - lastVerified < Self.graceSeconds
    }

    func refresh() async {
        guard isConfigured else { return }
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            record(customerInfo.entitlements[Self.entitlementId]?.isActive == true)
            lastError = nil
        } catch {
            // Offline: keep the cached value with grace; don't clear the flag.
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            monthlyPackage = offerings.current?.monthly ?? offerings.current?.availablePackages.first
        } catch {}
    }

    /// Purchase the monthly All-Access package. Returns true when the pass
    /// is active afterwards (including users who already subscribe).
    func purchase() async -> Bool {
        guard isConfigured, let monthlyPackage else {
            lastError = "The pass is not available yet. Check your connection and try again."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: monthlyPackage)
            if result.userCancelled { return false }
            let active = result.customerInfo.entitlements[Self.entitlementId]?.isActive == true
            record(active)
            lastError = active ? nil : "Purchase completed but the pass is not active yet."
            return active
        } catch {
            lastError = Self.friendlyError(error)
            return false
        }
    }

    func restore() async -> Bool {
        guard isConfigured else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            let active = customerInfo.entitlements[Self.entitlementId]?.isActive == true
            record(active)
            lastError = active ? nil : "No previous purchase found for this account."
            return active
        } catch {
            lastError = Self.friendlyError(error)
            return false
        }
    }

    private func record(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: Self.cachedActiveKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastVerifiedKey)
        isLiveVerified = true
    }

    nonisolated private static func friendlyError(_ error: Error) -> String {
        error.localizedDescription
    }
}
