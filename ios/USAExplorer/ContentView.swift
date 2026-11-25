import SwiftUI

struct ContentView: View {
    @State private var fogService = HexFogService()
    @State private var locationService: LocationService?
    @State private var selectedTab: Int = 0
    @State private var hasCompletedSetup = UserProfileService.shared.hasCompletedSetup

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        Group {
            if hasCompletedSetup {
                mainTabView
            } else {
                UsernameSetupView {
                    hasCompletedSetup = true
                }
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Map", systemImage: "mappin.and.ellipse", value: 0) {
                if let locationService {
                    MapTabView(locationService: locationService, fogService: fogService)
                }
            }

            Tab("Layers", systemImage: "square.3.layers.3d.top.filled", value: 1) {
                LayersTabView()
            }

            Tab("Stats", systemImage: "chart.bar.fill", value: 2) {
                StatsView()
            }

            Tab("Friends", systemImage: "person.2.fill", value: 3) {
                FriendsView()
            }
        }
        .tint(gold)
        .onAppear {
            configureTabBarAppearance()
            if locationService == nil {
                let service = LocationService(fogService: fogService)
                locationService = service
                // Phase 4: the game engine and privacy gate share the
                // injected LocationService (no singletons).
                GameService.shared.configure(locationService: service)
                PrivacyService.shared.configure(locationService: service)
                service.requestPermissions()
            }
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 10/255, green: 15/255, blue: 30/255, alpha: 1)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.4)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1)
        ]

        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.4)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
