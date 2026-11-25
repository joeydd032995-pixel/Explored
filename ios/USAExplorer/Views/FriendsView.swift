import SwiftUI

struct FriendsView: View {
    @State private var viewModel = FriendsViewModel()
    @State private var selectedFriend: FriendInfo?

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let secondary = Color(red: 136/255, green: 153/255, blue: 170/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    feedSection
                    leaderboardSection
                    searchSection
                    pendingSection
                    friendsListSection
                }
                .padding(.bottom, 24)
            }
            .background(darkNavy)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(darkNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task { await viewModel.loadFriends() }
        .sheet(item: $selectedFriend) { friend in
            FriendProfileSheet(friend: friend, myStats: viewModel.localStats())
                .presentationDetents([.fraction(0.8)])
        }
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.selectedMetric.systemImage)
                    .font(.title3)
                    .foregroundStyle(gold)
                Text("Leaderboard")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            Picker("Metric", selection: $viewModel.selectedMetric) {
                ForEach(LeaderboardMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedMetric) { _, _ in
                viewModel.resortLeaderboard()
            }

            if viewModel.leaderboard.isEmpty {
                Text("Add friends to see the leaderboard")
                    .font(.caption)
                    .foregroundStyle(secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(viewModel.leaderboard.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 12) {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(index == 0 ? gold : secondary)
                            .frame(width: 28)

                        Circle()
                            .fill(Color(hex: entry.color))
                            .frame(width: 10, height: 10)

                        Text(entry.username)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)

                        Spacer()

                        Text("\(entry.value(for: viewModel.selectedMetric))")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Friend")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                TextField("", text: $viewModel.searchQuery, prompt: Text("Search by username").foregroundStyle(.white.opacity(0.3)))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(.rect(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    Task { await viewModel.searchUsers() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(darkNavy)
                        .padding(12)
                        .background(gold)
                        .clipShape(.rect(cornerRadius: 10))
                }
            }

            ForEach(viewModel.searchResults) { user in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: user.avatarColor))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(user.username.prefix(1)).uppercased())
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        )

                    Text(user.username)
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        Task { await viewModel.sendRequest(to: user.id) }
                    } label: {
                        Text("Add")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(darkNavy)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(gold)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var pendingSection: some View {
        Group {
            if !viewModel.pendingRequests.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pending Requests")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ForEach(viewModel.pendingRequests, id: \.0.id) { friendship, profile in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: profile.avatarColor))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(String(profile.username.prefix(1)).uppercased())
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                )

                            Text(profile.username)
                                .font(.subheadline)
                                .foregroundStyle(.white)

                            Spacer()

                            Button {
                                Task { await viewModel.acceptRequest(friendship) }
                            } label: {
                                Text("Accept")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(darkNavy)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(gold)
                                    .clipShape(.rect(cornerRadius: 8))
                            }

                            Button {
                                Task { await viewModel.declineRequest(friendship) }
                            } label: {
                                Text("Decline")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding()
                .background(cardBg)
                .clipShape(.rect(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Friends")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(viewModel.friends.count)")
                    .font(.caption)
                    .foregroundStyle(gold)
            }

            if viewModel.friends.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.15))
                    Text("No friends yet")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Search for explorers to add")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.friends) { friend in
                    Button {
                        selectedFriend = friend
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: friend.profile.avatarColor))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(String(friend.profile.username.prefix(1)).uppercased())
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.profile.username)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)

                                if let stats = friend.stats {
                                    Text(String(format: "%.3f%% \u{00B7} %d states \u{00B7} %d counties", stats.nationalPct, stats.statesVisited, stats.countiesVisited))
                                        .font(.caption2)
                                        .foregroundStyle(secondary)
                                }
                            }

                            Spacer()

                            if friend.nodesOwned > 0 {
                                HStack(spacing: 4) {
                                    Text("\u{1F451}")
                                        .font(.caption2)
                                    Text("\(friend.nodesOwned)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(gold)
                                }
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.2))
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Phase 4: activity feed

    private var feedSection: some View {
        Group {
            if !viewModel.feed.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ForEach(viewModel.feed.prefix(8)) { event in
                        HStack(spacing: 10) {
                            Image(systemName: event.systemImage)
                                .font(.caption)
                                .foregroundStyle(gold)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())

                            (Text(event.username + " ")
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                             + Text(event.title)
                                .foregroundStyle(secondary))
                                .font(.caption)
                                .lineLimit(2)

                            Spacer()

                            if let createdAt = Self.parseDate(event.createdAt) {
                                Text(createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(cardBg)
                .clipShape(.rect(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    nonisolated private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
