import SwiftUI

/// The Layers tab: overlay registry status, hierarchical discovery progress
/// against real-world boundaries, and the creator marketplace — presented as
/// a dashboard on the shared navy/gold token system.
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
    @State private var countiesExpanded = false
    @State private var citiesExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryNavy.ignoresSafeArea()

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
            AppTheme.eyebrow("United States")

            if let national {
                Text(national.percent < 0.01
                     ? String(format: "%.4f%%", national.percent)
                     : String(format: "%.2f%%", national.percent))
                    .font(AppTheme.display(52))
                    .foregroundStyle(AppTheme.gold)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: national.percent)

                // Thin gold accent bar.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.gold, AppTheme.goldHighlight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 64, height: 4)

                Text("\(national.claimedHexes) H3 cells claimed · res 7 grid")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            ZStack {
                LinearGradient(colors: [AppTheme.gold.opacity(0.14), AppTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                HexParticleField()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppTheme.gold.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    // MARK: Discovery progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppTheme.eyebrow("Discovery Progress")

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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RingGauge(progress: progress.percent / 100, size: 26, lineWidth: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(progress.stateId) · \(progress.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    exactBadge(usesExact: progress.usesExactDenominator)
                }

                Spacer()

                Text(progress.percentLabel)
                    .font(.subheadline.weight(.bold).monospaced())
                    .foregroundStyle(AppTheme.gold)
            }

            ThemedProgressBar(percent: progress.percent)

            Text("\(progress.claimedHexes)/\(progress.totalHexes) cells · \(progress.countiesVisited) counties · \(progress.citiesVisited) cities · \(Int(progress.unexploredKm2)) km² left")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))

            if progress.distanceKm > 0.01 || progress.lastVisit > 0 {
                Text(Self.visitSummary(progress))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    /// Solid gold "EXACT" once polyfill finishes; dashed muted "≈" meanwhile.
    private func exactBadge(usesExact: Bool) -> some View {
        Text(usesExact ? "EXACT" : "≈ EST")
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(usesExact ? AppTheme.primaryNavy : AppTheme.goldMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(usesExact ? AppTheme.gold : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(AppTheme.goldMuted.opacity(usesExact ? 0 : 0.6),
                                  style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            )
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
                DisclosureGroup(isExpanded: $countiesExpanded) {
                    VStack(spacing: 8) {
                        ForEach(countyProgresses) { regionRow($0) }
                    }
                    .padding(.top, 8)
                } label: {
                    sectionHeader("Counties", count: countyProgresses.count)
                }
            }

            if !cityProgresses.isEmpty {
                DisclosureGroup(isExpanded: $citiesExpanded) {
                    VStack(spacing: 8) {
                        ForEach(cityProgresses) { regionRow($0) }
                    }
                    .padding(.top, 8)
                } label: {
                    sectionHeader("Cities & Places", count: cityProgresses.count)
                }
            }
        }
        .tint(.white.opacity(0.4))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            AppTheme.eyebrow(title)
            Text("\(count)")
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(AppTheme.gold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.gold.opacity(0.15))
                .clipShape(Capsule())
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
                    .foregroundStyle(AppTheme.gold)
            }

            ThemedProgressBar(percent: region.percent, height: 6)

            Text("\(region.claimedHexes)/\(region.totalHexes) cells · \(String(format: "%.1f", region.unexploredKm2)) km² left")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
        .background(AppTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Overlays

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppTheme.eyebrow("Active Overlays")

            ForEach(registry.providers, id: \.id) { provider in
                overlayRow(provider)
            }

            Text("Enable layers from the chips or filter button on the map. New providers register through the plugin interface without core changes.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func overlayRow(_ provider: any OverlayProvider) -> some View {
        let enabled = registry.isEnabled(provider.id)

        return HStack(spacing: 12) {
            // Sensitive providers carry a danger accent on their left edge.
            if provider.isSensitive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.danger.opacity(0.8))
                    .frame(width: 3, height: 34)
            }

            ZStack(alignment: .bottomTrailing) {
                Image(systemName: provider.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(enabled ? AppTheme.gold : .white.opacity(0.3))
                    .frame(width: 34, height: 34)
                    .background(AppTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                StatusDot(state: enabled ? (provider.isSensitive ? .idle : .active) : .muted)
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(provider.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if provider.isSensitive {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.danger)
                    }
                }
                Text(provider.summary)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }

            Spacer()

            Text("\(provider.featureCount)")
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(AppTheme.primaryNavy)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(enabled ? AppTheme.gold : AppTheme.gold.opacity(0.25))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: Marketplace

    private var marketplaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppTheme.eyebrow("Creator Marketplace")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    marketplaceCard(
                        icon: "storefront",
                        title: "Browse Layers",
                        subtitle: "Search, review, and install community layers",
                        badge: marketplace.catalog.isEmpty ? nil : "\(marketplace.catalog.count) available",
                        prominent: true,
                        action: { showBrowse = true }
                    )

                    if !marketplace.installed.isEmpty {
                        marketplaceCard(
                            icon: "square.on.square.intersection.dashed",
                            title: "Installed",
                            subtitle: "Manage the community layers you've added",
                            badge: "\(marketplace.installed.count) installed",
                            prominent: false,
                            action: { showBrowse = true }
                        )
                    }

                    marketplaceCard(
                        icon: "paintbrush.pointed.fill",
                        title: "Creator Studio",
                        subtitle: "Author a layer, drop pins, publish it",
                        badge: nil,
                        prominent: false,
                        action: { showCreatorStudio = true }
                    )

                    marketplaceCard(
                        icon: "chart.bar.fill",
                        title: "My Layers",
                        subtitle: "Installs and ratings for what you've published",
                        badge: nil,
                        prominent: false,
                        action: { showMyLayers = true }
                    )
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 4)
            }
        }
    }

    private func marketplaceCard(
        icon: String,
        title: String,
        subtitle: String,
        badge: String?,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(prominent ? AppTheme.primaryNavy : AppTheme.gold)
                    .frame(width: 40, height: 40)
                    .background(prominent ? AppTheme.gold : AppTheme.gold.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(AppTheme.gold)
                        .lineLimit(1)
                } else {
                    Text("Open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(14)
            .frame(width: 190, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [AppTheme.gold.opacity(prominent ? 0.16 : 0.08), AppTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.gold.opacity(prominent ? 0.3 : 0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
    }
}
