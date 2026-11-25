import SwiftUI

struct StatsView: View {
    @State private var viewModel = StatsViewModel()
    @State private var selectedState: StateSummary?
    @State private var showGames = false
    @State private var showPrivacy = false

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MiniUSMapView(visitedStateIds: viewModel.visitedStateIds)
                        .padding(.horizontal)

                    statsCardsSection
                    gamesCard
                    kothStatsCard
                    stateListSection
                }
                .padding(.bottom, 24)
            }
            .background(darkNavy)
            .navigationTitle("Explorer Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(darkNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPrivacy = true
                    } label: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(gold)
                    }
                    .accessibilityLabel("Privacy settings")
                }
            }
        }
        .onAppear { viewModel.loadStats() }
        .sheet(item: $selectedState) { state in
            StateDrillDownSheet(stateSummary: state)
                .presentationDetents([.fraction(0.9)])
        }
        .sheet(isPresented: $showGames) {
            TerritoryGamesView()
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacySettingsView()
        }
    }

    // MARK: - Phase 4: Territory Games entry

    private var gamesCard: some View {
        Button {
            showGames = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundStyle(gold)
                    .frame(width: 44, height: 44)
                    .background(gold.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Territory Games")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("King of the Hill · Claim & Defend · Contested Nodes")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding()
            .background(cardBg)
            .clipShape(.rect(cornerRadius: 12))
        }
        .padding(.horizontal)
    }

    private var statsCardsSection: some View {
        VStack(spacing: 10) {
            StatCardView(
                icon: "\u{1F5FA}\u{FE0F}",
                title: "National Coverage",
                value: viewModel.nationalCoverageFormatted,
                subtitle: "\(viewModel.hexCount.formatted()) hexes discovered"
            )

            StatCardView(
                icon: "\u{1F3DB}\u{FE0F}",
                title: "States Visited",
                value: "\(viewModel.statesVisited) / 51",
                progress: Double(viewModel.statesVisited) / 51.0
            )

            StatCardView(
                icon: "\u{1F5C2}\u{FE0F}",
                title: "Counties Visited",
                value: "\(viewModel.countiesVisited) / 3,143",
                progress: Double(viewModel.countiesVisited) / 3143.0
            )

            StatCardView(
                icon: "\u{1F3D9}\u{FE0F}",
                title: "Cities Visited",
                value: "\(viewModel.citiesVisited) / 19,495",
                progress: Double(viewModel.citiesVisited) / 19495.0
            )

            StatCardView(
                icon: "\u{1F4CF}",
                title: "Total Distance",
                value: viewModel.distanceFormatted
            )

            StatCardView(
                icon: "\u{1F525}",
                title: "Exploration Streak",
                value: "\(viewModel.explorationStreak) day\(viewModel.explorationStreak == 1 ? "" : "s")"
            )
        }
        .padding(.horizontal)
    }

    private var kothStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\u{1F451}")
                    .font(.title3)
                Text("King of the Hill")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nodes Owned")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(viewModel.kothNodesOwned) / 19,495")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                Spacer()
            }

            GoldProgressBar(progress: Double(viewModel.kothNodesOwned) / 19495.0)
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var stateListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("States")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Spacer()

                Text("\(viewModel.statesVisited) visited")
                    .font(.caption)
                    .foregroundStyle(gold)
            }
            .padding(.horizontal)

            LazyVStack(spacing: 2) {
                ForEach(viewModel.stateSummaries) { state in
                    Button {
                        selectedState = state
                    } label: {
                        StateRowView(summary: state)
                    }
                }
            }
            .background(Color(red: 17/255, green: 24/255, blue: 39/255))
            .clipShape(.rect(cornerRadius: 12))
            .padding(.horizontal)
        }
    }
}

struct StateRowView: View {
    let summary: StateSummary

    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                Text("\(summary.visitedCounties) / \(summary.totalCounties) counties")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f%%", summary.explorationPercent))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(summary.visitedCounties > 0 ? gold : .white.opacity(0.3))

                GoldProgressBar(progress: summary.explorationPercent / 100.0)
                    .frame(width: 60)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
