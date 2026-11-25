import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var travelPath: [CLLocationCoordinate2D] = []
    var lastDiscoveryEvents: [DiscoveryType] = []
    var showStateCelebration: Bool = false
    var celebrationStateName: String = ""

    private let database = DatabaseService.shared
    var onHexDiscovered: (() -> Void)?
    private let fogService: HexFogService
    private let geocodingService = GeocodingService()
    private var isGeocoding: Bool = false
    private var isTracking: Bool = false
    private var isMonitoringSignificantChanges: Bool = false
    private var hasRequestedAlwaysAuthorization: Bool = false
    private var lastFixLocation: CLLocation?
    private var lastFixStateId: String?

    init(fogService: HexFogService) {
        self.fogService = fogService
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true

        fogService.loadDiscoveredHexes()
        loadStoredCoordinates()
    }

    func requestPermissions() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysAuthorizationIfNeeded()
            startTracking()
        case .authorizedAlways:
            startTracking()
        default:
            break
        }
    }

    func startTracking() {
        guard !isTracking else { return }
        // Phase 4 privacy master gate: when paused, no location updates run
        // and nothing is written to the local store.
        guard !PrivacyService.shared.isTrackingPaused else { return }
        applyBackgroundUpdatesPolicy()
        manager.startUpdatingLocation()
        isTracking = true
        startSignificantChangeMonitoringIfNeeded()
    }

    func stopTracking() {
        guard isTracking || isMonitoringSignificantChanges else { return }
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
        isTracking = false
        stopSignificantChangeMonitoringIfNeeded()
    }

    private func requestAlwaysAuthorizationIfNeeded() {
        guard !hasRequestedAlwaysAuthorization else { return }
        hasRequestedAlwaysAuthorization = true
        manager.requestAlwaysAuthorization()
    }

    /// Enabling background updates is only legal once the app is truly
    /// backgroundable (UIBackgroundModes: location + always permission);
    /// setting it earlier crashes with a CoreLocation assertion.
    private func applyBackgroundUpdatesPolicy() {
        let backgroundable = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = backgroundable
    }

    private func startSignificantChangeMonitoringIfNeeded() {
        guard !isMonitoringSignificantChanges else { return }
        manager.startMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = true
    }

    private func stopSignificantChangeMonitoringIfNeeded() {
        guard isMonitoringSignificantChanges else { return }
        manager.stopMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = false
    }

    private func loadStoredCoordinates() {
        let stored = database.fetchAllCoordinates()
        travelPath = stored.map { $0.coordinate }
    }

    private func saveAndAppend(_ location: CLLocation) {
        let timestamp = Int64(location.timestamp.timeIntervalSince1970)
        database.insertCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: timestamp
        )
        travelPath.append(location.coordinate)

        let hexId = fogService.discoverHex(at: location.coordinate)
        recordBoundaryAttribution(location: location, hexId: hexId)

        if let hexId {
            HapticService.shared.hexDiscovered()
            onHexDiscovered?()
            geocodeAndProcess(location, attributedHexId: hexId)
        } else if let cellId = fogService.cellId(at: location.coordinate) {
            fogService.recordVisit(hexId: cellId)
        }
    }

    /// Offline, boundary-based attribution: authoritative state/county/city
    /// polygons decide which entities a fix (and its hex) belongs to,
    /// independent of network geocoding. Also accumulates per-state visit
    /// stats and records first visits for counties and cities offline.
    private func recordBoundaryAttribution(location: CLLocation, hexId: String?) {
        let timestamp = Int64(location.timestamp.timeIntervalSince1970)
        let stateId = BoundaryService.shared.stateId(at: location.coordinate)
        let countyKey = BoundaryService.shared.countyKey(at: location.coordinate)
        let cityKey = BoundaryService.shared.cityKey(at: location.coordinate)

        if let stateId {
            let distance: Double
            if let previous = lastFixLocation, lastFixStateId == stateId {
                distance = previous.distance(from: location)
            } else {
                distance = 0
            }
            database.updateStateVisit(stateId: stateId, at: timestamp, addDistance: distance)
            lastFixLocation = location
            lastFixStateId = stateId
        }

        // The boundary engine owns hex→entity attribution (exact, offline).
        if let hexId {
            if let stateId {
                database.insertStateHex(stateId: stateId, hexId: hexId)
            }
            if let countyKey {
                database.insertCountyHex(fips: countyKey, hexId: hexId)
            }
            if let cityKey {
                database.insertCityHex(cityId: cityKey, hexId: hexId)
            }
        }

        // First visits recorded without geocoding too.
        if let countyKey {
            let parts = countyKey.split(separator: "-", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                database.insertVisitedCounty(fips: countyKey, name: parts[1], state: parts[0], visitedDate: timestamp)
            }
        }
        if let cityKey {
            let parts = cityKey.split(separator: "-", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                database.insertVisitedCity(cityId: cityKey, name: parts[1], state: parts[0], county: "", visitedDate: timestamp)
            }
        }
    }

    func manualCheckIn(at coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let timestamp = Int64(Date().timeIntervalSince1970)
        database.insertCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timestamp: timestamp
        )
        travelPath.append(coordinate)

        let _ = fogService.discoverHex(at: coordinate)
        let attributedHex = fogService.cellId(at: coordinate)
        recordBoundaryAttribution(location: location, hexId: attributedHex)
        HapticService.shared.checkInConfirmed()
        onHexDiscovered?()
        geocodeAndProcess(location, attributedHexId: attributedHex)
        pushStatsToSupabase()
    }

    private func geocodeAndProcess(_ location: CLLocation, attributedHexId: String? = nil) {
        guard !isGeocoding else { return }
        isGeocoding = true

        Task {
            defer { isGeocoding = false }

            guard let result = await geocodingService.reverseGeocode(location) else { return }
            let now = Int64(Date().timeIntervalSince1970)
            var events: [DiscoveryType] = []

            if let stateName = result.state {
                let stateId = USStateData.abbreviation(for: stateName) ?? stateName
                let existingStates = database.fetchVisitedStates().map { $0.stateId }
                let isNewState = !existingStates.contains(stateId)
                database.insertVisitedState(stateId: stateId, name: stateName, visitedDate: now)

                // Hex attribution lives in the boundary engine
                // (recordBoundaryAttribution); geocoding adds names + celebrations.

                if isNewState {
                    events.append(.state(name: stateName))
                    HapticService.shared.stateDiscovered()
                    celebrationStateName = stateName
                    showStateCelebration = true

                    try? await Task.sleep(for: .seconds(2.5))
                    showStateCelebration = false
                }
            }

            if let county = result.county, let stateName = result.state {
                let fips = "\(stateName)-\(county)"
                let existingCounties = database.fetchCountiesForState(state: stateName).map { $0.fips }
                let isNewCounty = !existingCounties.contains(fips)
                database.insertVisitedCounty(fips: fips, name: county, state: stateName, visitedDate: now)

                if isNewCounty {
                    events.append(.county(name: county, state: stateName))
                    HapticService.shared.countyDiscovered()
                }
            }

            if let city = result.city, let stateName = result.state {
                let cityId = "\(stateName)-\(city)"
                let county = result.county ?? ""
                database.insertVisitedCity(cityId: cityId, name: city, state: stateName, county: county, visitedDate: now)
                events.append(.city(name: city, state: stateName))

                attemptNodeCapture(cityId: cityId, cityName: city, state: stateName, lat: location.coordinate.latitude, lng: location.coordinate.longitude)
            }

            lastDiscoveryEvents = events
            MilestoneService.shared.checkAndFireMilestones()
            pushStatsToSupabase()
        }
    }

    private func attemptNodeCapture(cityId: String, cityName: String, state: String, lat: Double, lng: Double) {
        guard let userId = UserProfileService.shared.userId,
              let username = UserProfileService.shared.username else { return }
        let color = UserProfileService.shared.avatarColor

        Task {
            let existingNode = await SupabaseService.shared.fetchNode(cityId: cityId)

            if existingNode?.ownerUserId == userId { return }

            let previousOwner = existingNode?.ownerUsername

            let _ = await SupabaseService.shared.captureNode(
                cityId: cityId,
                cityName: cityName,
                state: state,
                lat: lat,
                lng: lng,
                userId: userId,
                username: username,
                color: color
            )

            HapticService.shared.nodeCapture()

            if let prev = previousOwner {
                NotificationService.shared.sendNotification(
                    title: "⚔️ Node Captured!",
                    body: "You captured \(cityName) from \(prev)!"
                )
            }
        }
    }

    private func pushStatsToSupabase() {
        Task {
            let vm = FriendsViewModel()
            await vm.pushStats()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                currentLocation = location
                saveAndAppend(location)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse:
                requestAlwaysAuthorizationIfNeeded()
                startTracking()
            case .authorizedAlways:
                startTracking()
            default:
                stopTracking()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}
