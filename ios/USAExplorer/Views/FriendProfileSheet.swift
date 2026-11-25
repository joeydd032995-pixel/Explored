import SwiftUI
import MapKit

struct FriendProfileSheet: View {
    let friend: FriendInfo
    /// My local aggregates for the phase-4 side-by-side comparison.
    var myStats: UserStats?

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let secondary = Color(red: 136/255, green: 153/255, blue: 170/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    statsGrid
                    compareSection
                    kothCard
                }
                .padding()
            }
            .background(darkNavy)
            .navigationTitle(friend.profile.username)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(darkNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color(hex: friend.profile.avatarColor))
                .frame(width: 56, height: 56)
                .overlay(
                    Text(String(friend.profile.username.prefix(1)).uppercased())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.profile.username)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let stats = friend.stats {
                    Text(String(format: "%.3f%% explored", stats.nationalPct))
                        .font(.subheadline)
                        .foregroundStyle(gold)
                }
            }

            Spacer()
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let stats = friend.stats {
                friendStatCard(icon: "flag.fill", label: "States", value: "\(stats.statesVisited)")
                friendStatCard(icon: "building.columns.fill", label: "Counties", value: "\(stats.countiesVisited)")
                friendStatCard(icon: "building.2.fill", label: "Cities", value: "\(stats.citiesVisited)")
                friendStatCard(icon: "point.bottomleft.forward.to.point.topright.scurvepath.fill", label: "Miles", value: String(format: "%.0f", stats.totalMiles))
            } else {
                friendStatCard(icon: "questionmark.circle", label: "Stats", value: "N/A")
            }
        }
    }

    // MARK: - Phase 4: side-by-side comparison

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You vs \(friend.profile.username)")
                .font(.headline)
                .foregroundStyle(.white)

            compareRow(
                label: "National",
                friendValue: friend.stats.map { String(format: "%.3f%%", $0.nationalPct) } ?? "—",
                friendProgress: (friend.stats?.nationalPct ?? 0) / 0.05, // scale: 0.05% fills the bar
                myValue: myStats.map { String(format: "%.3f%%", $0.nationalPct) } ?? "—",
                myProgress: (myStats?.nationalPct ?? 0) / 0.05
            )
            compareRow(
                label: "States",
                friendValue: "\(friend.stats?.statesVisited ?? 0)",
                friendProgress: Double(friend.stats?.statesVisited ?? 0) / 51.0,
                myValue: "\(myStats?.statesVisited ?? 0)",
                myProgress: Double(myStats?.statesVisited ?? 0) / 51.0
            )
            compareRow(
                label: "Counties",
                friendValue: "\(friend.stats?.countiesVisited ?? 0)",
                friendProgress: Double(friend.stats?.countiesVisited ?? 0) / 3143.0,
                myValue: "\(myStats?.countiesVisited ?? 0)",
                myProgress: Double(myStats?.countiesVisited ?? 0) / 3143.0
            )
            compareRow(
                label: "Cities",
                friendValue: "\(friend.stats?.citiesVisited ?? 0)",
                friendProgress: Double(friend.stats?.citiesVisited ?? 0) / 19495.0,
                myValue: "\(myStats?.citiesVisited ?? 0)",
                myProgress: Double(myStats?.citiesVisited ?? 0) / 19495.0
            )
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func compareRow(label: String, friendValue: String, friendProgress: Double, myValue: String, myProgress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Text(friendValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .frame(width: 70, alignment: .leading)
                GoldProgressBar(progress: min(1, max(0, friendProgress)))
                Text(friend.profile.username)
                    .font(.caption2)
                    .foregroundStyle(secondary)
                    .frame(width: 60, alignment: .trailing)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Text(myValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .frame(width: 70, alignment: .leading)
                GoldProgressBar(progress: min(1, max(0, myProgress)))
                Text("You")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(gold)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    private func friendStatCard(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(gold)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var kothCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\u{1F451}")
                    .font(.title3)
                Text("King of the Hill")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            HStack {
                Text("Nodes Owned")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
                Spacer()
                Text("\(friend.nodesOwned)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(gold)
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
    }
}
