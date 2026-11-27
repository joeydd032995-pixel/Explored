import SwiftUI
import MapKit
import CoreLocation

struct MapTabView: View {
    let locationService: LocationService
    let fogService: HexFogService

    @State private var overlayRegistry = OverlayRegistry.shared
    @State private var activeFeatures: [OverlayFeature] = []
    @State private var selectedFeature: OverlayFeature?
    @State private var showFilterSheet: Bool = false
    @State private var showHazardReport: Bool = false
    @State private var showCameraReport: Bool = false
    @State private var showCheckIn: Bool = false
    @State private var checkInCoordinate: CLLocationCoordinate2D?
    @State private var checkInAddress: String = ""
    @State private var currentRegion: MKCoordinateRegion?
    @State private var fogComputeTask: Task<Void, Never>?
    @State private var claimPulses: [ClaimPulse] = []
    @State private var pulseAnimationTasks: [String: Task<Void, Never>] = [:]

    private let darkNavy = AppTheme.primaryNavy
    private let gold = AppTheme.gold

    var body: some View {
        ZStack {
            darkNavy.ignoresSafeArea()

            MapScreenView(
                userLocation: locationService.currentLocation?.coordinate,
                travelPath: locationService.travelPath,
                fogPolygons: fogService.fogPolygons,
                glowCircles: fogService.glowCircles,
                claimPulses: claimPulses,
                overlayFeatures: activeFeatures,
                onFeatureTap: { feature in
                    selectedFeature = feature
                },
                onRegionChanged: { region in
                    currentRegion = region
                    refreshOverlayFeatures()
                    // Debounce fog recompute: region events fire continuously
                    // while panning, and the H3 tiling shouldn't race the pan.
                    scheduleFogCompute(region)
                },
                onLongPress: { coordinate in
                    handleLongPress(coordinate)
                }
            )
            .ignoresSafeArea()

            // Light navy wash unifying the basemap with the fog; gestures
            // pass straight through to the map.
            AppTheme.primaryNavy
                .opacity(0.2)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack(spacing: 10) {
                    hudMenu

                    Spacer()

                    if overlayRegistry.isLoading {
                        ProgressView()
                            .tint(gold)
                            .padding(10)
                            .hudChrome()
                    }

                    Button {
                        fogService.cycleDisplayMode()
                        recomputeHexLayer()
                    } label: {
                        hudIcon(
                            fogService.displayMode.icon,
                            tint: fogService.displayMode == .off ? .white.opacity(0.35) : gold
                        )
                    }
                    .accessibilityLabel("Hex layer: \(fogService.displayMode.label)")

                    Button {
                        showFilterSheet = true
                    } label: {
                        hudIcon("line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Layer filters")
                }
                .padding(.horizontal)
                .padding(.top, 8)

                filterChipRow

                Spacer()
            }

            CelebrationOverlay(
                stateName: locationService.celebrationStateName,
                isVisible: locationService.showStateCelebration
            )
            .animation(.spring(duration: 0.5, bounce: 0.3), value: locationService.showStateCelebration)
        }
        .onAppear {
            locationService.onHexDiscovered = { [fogService] in
                spawnClaimPulse()
                if let region = currentRegion {
                    scheduleFogCompute(region)
                } else {
                    let defaultRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 50)
                    )
                    scheduleFogCompute(defaultRegion)
                }
            }
            refreshOverlayFeatures()
        }
        .sheet(isPresented: $showCheckIn) {
            if let coord = checkInCoordinate {
                CheckInSheet(
                    coordinate: coord,
                    address: checkInAddress,
                    onConfirm: {
                        locationService.manualCheckIn(at: coord)
                    }
                )
                .presentationDetents([.fraction(0.35)])
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            OverlayFilterSheet(registry: overlayRegistry)
                .presentationDetents([.fraction(0.6), .large])
        }
        .sheet(isPresented: $showHazardReport) {
            ReportHazardSheet(
                coordinate: reportCoordinate(),
                registry: overlayRegistry
            ) {
                refreshOverlayFeatures()
            }
            .presentationDetents([.fraction(0.55)])
        }
        .sheet(isPresented: $showCameraReport) {
            ReportCameraSheet(
                coordinate: reportCoordinate(),
                registry: overlayRegistry
            ) {
                refreshOverlayFeatures()
            }
            .presentationDetents([.fraction(0.55)])
        }
        .sheet(item: $selectedFeature) { feature in
            OverlayFeatureDetailSheet(
                feature: feature,
                registry: overlayRegistry
            ) {
                refreshOverlayFeatures()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: HUD chrome

    /// Frosted navy circle button.
    private func hudIcon(_ systemName: String, tint: Color = AppTheme.gold) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(10)
            .frame(minWidth: 38, minHeight: 38)
            .hudChrome()
    }

    /// Overflow menu for the less-used actions, keeping the primary HUD minimal.
    private var hudMenu: some View {
        Menu {
            Button {
                shareExplorationCard()
            } label: {
                Label("Share exploration card", systemImage: "square.and.arrow.up")
            }

            Button {
                showHazardReport = true
            } label: {
                Label("Report hazard", systemImage: "exclamationmark.triangle")
            }

            Button {
                showCameraReport = true
            } label: {
                Label("Add camera point", systemImage: "camera.fill")
            }
        } label: {
            hudIcon("ellipsis")
        }
    }

    /// Quick layer toggles as a floating chip row.
    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(overlayRegistry.providers, id: \.id) { provider in
                    filterChip(provider)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 10)
    }

    private func filterChip(_ provider: any OverlayProvider) -> some View {
        let enabled = overlayRegistry.isEnabled(provider.id)

        return Button {
            overlayRegistry.setEnabled(!enabled, for: provider.id)
            refreshOverlayFeatures()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                if provider.isSensitive {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 8))
                } else {
                    StatusDot(state: enabled ? .active : .muted)
                }
                Text(provider.name)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(enabled ? AppTheme.primaryNavy : .white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(enabled ? AppTheme.gold : AppTheme.primaryNavy.opacity(0.75))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: enabled)
        }
    }

    // MARK: Claim pulse

    /// New hex claim → expanding gold ring under the explorer + light haptic.
    private func spawnClaimPulse() {
        guard let coordinate = locationService.currentLocation?.coordinate else { return }
        let pulse = ClaimPulse(center: coordinate, radius: 1_400)
        claimPulses.append(pulse)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let id = pulse.id
        pulseAnimationTasks[id]?.cancel()
        pulseAnimationTasks[id] = Task {
            var phase = 0.0
            while phase < 1 {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                phase += 0.12
                for index in claimPulses.indices where claimPulses[index].id == id {
                    claimPulses[index].phase = min(phase, 1)
                }
            }
            claimPulses.removeAll { $0.id == id }
            pulseAnimationTasks[id] = nil
        }
    }

    private func recomputeHexLayer() {
        if let region = currentRegion {
            scheduleFogCompute(region)
        } else {
            scheduleFogCompute(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                    span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 50)
                )
            )
        }
    }

    private func scheduleFogCompute(_ region: MKCoordinateRegion) {
        fogComputeTask?.cancel()
        fogComputeTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            fogService.computeFog(for: region)
        }
    }

    private func reportCoordinate() -> CLLocationCoordinate2D {
        locationService.currentLocation?.coordinate
            ?? currentRegion?.center
            ?? CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35)
    }

    private func refreshOverlayFeatures() {
        guard let region = currentRegion else { return }
        Task {
            activeFeatures = await overlayRegistry.features(in: region)
        }
    }

    private func handleLongPress(_ coordinate: CLLocationCoordinate2D) {
        checkInCoordinate = coordinate
        checkInAddress = ""
        showCheckIn = true

        Task {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                var parts: [String] = []
                if let name = placemark.name { parts.append(name) }
                if let city = placemark.locality { parts.append(city) }
                if let state = placemark.administrativeArea { parts.append(state) }
                checkInAddress = parts.joined(separator: ", ")
            }
        }
    }

    private func shareExplorationCard() {
        let db = DatabaseService.shared
        let hexCount = db.fetchDiscoveredHexCount()
        let nationalPct = String(format: "%.3f%%", Double(hexCount) / 3_200_000.0 * 100.0)
        let statesVisited = db.fetchVisitedStatesCount()
        let countiesVisited = db.fetchVisitedCountiesCount()
        let visitedStateIds = Set(db.fetchVisitedStates().map { $0.stateId })

        let card = ShareCardView(
            nationalPercent: nationalPct,
            statesVisited: statesVisited,
            countiesVisited: countiesVisited,
            visitedStateIds: visitedStateIds
        )
        ShareService.shareCard(view: card)
    }
}
