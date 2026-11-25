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

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        ZStack {
            darkNavy.ignoresSafeArea()

            MapScreenView(
                userLocation: locationService.currentLocation?.coordinate,
                travelPath: locationService.travelPath,
                fogPolygons: fogService.fogPolygons,
                glowCircles: fogService.glowCircles,
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

            VStack {
                HStack {
                    Button {
                        shareExplorationCard()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(gold)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Spacer()

                    Button {
                        fogService.cycleDisplayMode()
                        recomputeHexLayer()
                    } label: {
                        Image(systemName: fogService.displayMode.icon)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                fogService.displayMode == .off
                                    ? Color.white.opacity(0.35)
                                    : gold
                            )
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Hex layer: \(fogService.displayMode.label)")

                    if overlayRegistry.isLoading {
                        ProgressView()
                            .tint(gold)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showHazardReport = true
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(red: 0.98, green: 0.68, blue: 0.15))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(gold)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

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
            .presentationDetents([.fraction(0.45)])
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
