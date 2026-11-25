import SwiftUI

/// The Layers tab: overlay registry status, hierarchical discovery progress
/// against real-world boundaries, and the creator marketplace.
struct LayersTabView: View {
    @State private var registry = OverlayRegistry.shared
    @State private var engine = DiscoveryProgressEngine.shared
    @State private var marketplace = MarketplaceService.shared
    @State private var showBrowse = false
    @State private var showCreatorStudio = false
    @State private var showMyLayers = false
    @State private var stateProgresses: [DiscoveryProgressEngine.StateProgress] = []
    @State private var countyProgresses: [DiscoveryProgressEngine.RegionProgress] = []
    @State private var cityProgresses: [DiscoveryProgressEngine.RegionProgress] = []
    @State private var national: DiscoveryProgressEngine.NationalProgress?

    private let surface = Color(red: 0.07, green: 0.09, blue: 0.16)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        nationalCard
                        progressSection
                        regionSection
                        overlaySection
                        marketplaceSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { reload() }
        .refreshable { reload() }
        .sheet(isPresented: $showBrowse) {
            NavigationStack { MarketplaceBrowseView() }
        }
        .sheet(isPresented: $showCreatorStudio) {
            NavigationStack { CreatorStudioView() }
        }
        .sheet(isPresented: $showMyLayers) {
            NavigationStack { MyLayersView() }
        }
    }

    private func reload() {
        stateProgresses = engine.stateProgresses()
        countyProgresses = engine.countyProgresses()
        cityProgresses = engine.cityProgresses()
        national = engine.nationalProgress()
        registry.pruneExpired()

        // Warm exact polygon denominators in the background, then re-render
        // with authoritative totals replacing the area estimates.
        Task {
            await engine.refreshExactTotals()
            stateProgresses = engine.stateProgresses()
            countyProgresses = engine.countyProgresses()
            cityProgresses = engine.cityProgresses()
        }
    }

    // MARK: National

    private var nationalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UNITED STATES")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.5))

            if let national {
                Text(national.percent < 0.01
                     ? String(format: "%.4f%%", national.percent)
                     : String(format: "%.2f%%", national.percent))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(gold)

                Text("\(national.claimedHexes) H3 cells claimed · res 7 grid")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [gold.opacity(0.14), surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Discovery progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovery Progress")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Unique H3 cells claimed inside each state's authoritative boundary polygon. Totals are exact once the polygon polyfill finishes — ≈ marks the interim area estimate. Transit at highway speed cannot complete a state; deliberate exploration can.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))

            if stateProgresses.isEmpty {
                Text("Start moving to claim your first cells.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 20)
            } else {
                ForEach(stateProgresses) { progress in
                    stateRow(progress)
                }
            }
        }
    }

    private func stateRow(_ progress: DiscoveryProgressEngine.StateProgress) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(progress.stateId) · \(progress.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(progress.percentLabel)
                    .font(.subheadline.weight(.bold).monospaced())
                    .foregroundStyle(gold)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [gold, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * min(1, progress.percent / 100)))
                }
            }
            .frame(height: 6)

            Text("\(progress.claimedHexes)/\(progress.totalHexes) cells\(progress.usesExactDenominator ? "" : " ≈") · \(progress.countiesVisited) counties · \(progress.citiesVisited) cities · \(Int(progress.unexploredKm2)) km² left")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))

            if progress.distanceKm > 0.01 || progress.lastVisit > 0 {
                Text(Self.visitSummary(progress))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(14)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private static let visitFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static func visitSummary(_ progress: DiscoveryProgressEngine.StateProgress) -> String {
        var parts: [String] = []
        if progress.distanceKm > 0.01 {
            parts.append(String(format: "%.1f km traveled in state", progress.distanceKm))
        }
        if progress.lastVisit > 0 {
            parts.append("last visit \(visitFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(progress.lastVisit))))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Counties & cities

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !countyProgresses.isEmpty {
                Text("Counties")
                    .font(.headline)
                    .foregroundStyle(.white)
                ForEach(countyProgresses) { regionRow($0) }
            }

            if !cityProgresses.isEmpty {
                Text("Cities & Places")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                ForEach(cityProgresses) { regionRow($0) }
            }
        }
    }

    private func regionRow(_ region: DiscoveryProgressEngine.RegionProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(region.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(region.state)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(region.percentLabel)
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(gold)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [gold, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * min(1, region.percent / 100)))
                }
            }
            .frame(height: 5)

            Text("\(region.claimedHexes)/\(region.totalHexes) cells\(region.usesExactDenominator ? "" : " ≈") · \(String(format: "%.1f", region.unexploredKm2)) km² left")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Overlays

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Overlays")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(registry.providers, id: \.id) { provider in
                HStack(spacing: 12) {
                    Image(systemName: provider.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(registry.isEnabled(provider.id) ? gold : .white.opacity(0.3))
                        .frame(width: 34, height: 34)
                        .background(surface)
                        .clipShape(RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(provider.summary)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }

                    Spacer()

                    Text("\(provider.featureCount)")
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(gold)
                }
                .padding(12)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("Enable layers from the filter button on the map. New providers register through the plugin interface without core changes.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: Marketplace

    private var marketplaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Creator Marketplace")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                marketplaceEntry(
                    icon: "storefront", title: "Browse layers",
                    subtitle: "Search, review, and install community layers",
                    badge: marketplace.catalog.isEmpty ? nil : "\(marketplace.catalog.count)",
                    action: { showBrowse = true }
                )

                if !marketplace.installed.isEmpty {
                    marketplaceEntry(
                        icon: "square.on.square.intersection.dashed",
                        title: "Installed layers (\(marketplace.installed.count))",
                        subtitle: "Manage the community layers you've added",
                        badge: nil,
                        action: { showBrowse = true }
                    )
                }

                marketplaceEntry(
                    icon: "paintbrush.pointed.fill", title: "Creator Studio",
                    subtitle: "Author a layer, drop pins, publish it",
                    badge: nil,
                    action: { showCreatorStudio = true }
                )

                marketplaceEntry(
                    icon: "chart.bar.fill", title: "My Layers",
                    subtitle: "Installs and ratings for what you've published",
                    badge: nil,
                    action: { showMyLayers = true }
                )
            }
        }
    }

    private func marketplaceEntry(icon: String, title: String, subtitle: String, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(gold)
                    .frame(width: 36, height: 36)
                    .background(surface)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(Color(red: 10/255, green: 15/255, blue: 30/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(gold)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(12)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
