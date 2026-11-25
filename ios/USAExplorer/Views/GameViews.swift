import SwiftUI
import MapKit

// MARK: - Territory Games (phase 4)
//
// Lobby (open sessions, join by code, create) → live game (map with players,
// hills/nodes, score strip, countdown) → results sheet with rematch.

struct TerritoryGamesView: View {
    @State private var game = GameService.shared
    @Environment(\.dismiss) private var dismiss

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        NavigationStack {
            Group {
                if let session = game.session {
                    GameSessionView(game: game, session: session, onExit: { dismiss() })
                } else {
                    GameLobbyView(game: game)
                }
            }
            .background(darkNavy)
            .navigationTitle("Territory Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(darkNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(gold)
                }
            }
        }
    }
}

// MARK: Lobby

private struct GameLobbyView: View {
    @Bindable var game: GameService
    @State private var openSessions: [GameSessionDTO] = []
    @State private var inviteCode = ""
    @State private var selectedMode: GameMode = .kingOfTheHill
    @State private var durationMinutes = 10
    @State private var isBusy = false

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let secondary = Color(red: 136/255, green: 153/255, blue: 170/255)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                modeSection
                createSection
                joinSection
                openSessionsSection
                if let error = game.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        openSessions = await game.fetchOpenSessions()
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a mode")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(GameMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.systemImage)
                            .font(.title3)
                            .foregroundStyle(selectedMode == mode ? gold : secondary)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            Text(mode.rules)
                                .font(.caption2)
                                .foregroundStyle(secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedMode == mode ? gold : .white.opacity(0.2))
                    }
                    .padding(12)
                    .background(selectedMode == mode ? gold.opacity(0.08) : Color.white.opacity(0.03))
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedMode == mode ? gold.opacity(0.5) : .clear, lineWidth: 1)
                    )
                }
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Host a game")
                .font(.headline)
                .foregroundStyle(.white)

            Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5...30, step: 5)
                .font(.subheadline)
                .foregroundStyle(.white)

            Button {
                isBusy = true
                Task {
                    if await game.createSession(mode: selectedMode, durationMinutes: durationMinutes) {
                        await refresh()
                    }
                    isBusy = false
                }
            } label: {
                HStack {
                    if isBusy { ProgressView().tint(darkNavy) }
                    Image(systemName: selectedMode.systemImage)
                    Text("Create \(selectedMode.displayName)")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
                .foregroundStyle(darkNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(gold)
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(isBusy)

            Text("Hills and nodes are placed around your current location. Friends can join from this list, or with your invite code.")
                .font(.caption2)
                .foregroundStyle(secondary)
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Join with a code")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                TextField("ABC123", text: $inviteCode)
                    .font(.title3.monospaced())
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(.rect(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                Button {
                    isBusy = true
                    Task {
                        if await game.joinByCode(inviteCode) {
                            await refresh()
                        }
                        isBusy = false
                    }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(darkNavy)
                        .padding(12)
                        .background(gold)
                        .clipShape(.rect(cornerRadius: 10))
                }
                .disabled(inviteCode.count < 6 || isBusy)
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var openSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Open games")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(openSessions.count)")
                    .font(.caption)
                    .foregroundStyle(gold)
            }

            if openSessions.isEmpty {
                Text("No open games right now. Host one, or share a code with friends.")
                    .font(.caption)
                    .foregroundStyle(secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(openSessions) { session in
                    Button {
                        isBusy = true
                        Task {
                            if await game.join(session: session) {
                                await refresh()
                            }
                            isBusy = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: session.gameMode?.systemImage ?? "gamecontroller.fill")
                                .foregroundStyle(gold)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.gameMode?.displayName ?? "Game")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                Text("Hosted by \(session.hostName) \u{00B7} code \(session.inviteCode)")
                                    .font(.caption2)
                                    .foregroundStyle(secondary)
                            }

                            Spacer()

                            Text(session.isLive ? "LIVE" : "Lobby")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(session.isLive ? Color.red : secondary)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .disabled(isBusy)
                }
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: Live session

private struct GameSessionView: View {
    @Bindable var game: GameService
    let session: GameSessionDTO
    let onExit: () -> Void
    @State private var showResults = false

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let secondary = Color(red: 136/255, green: 153/255, blue: 170/255)

    var body: some View {
        VStack(spacing: 0) {
            if session.isEnded {
                resultsList
            } else {
                gameMap
                scoreStrip
                actionRow
            }
        }
        .onChange(of: session.isEnded) { _, ended in
            if ended { showResults = true }
        }
        .sheet(isPresented: $showResults) {
            GameResultsSheet(game: game, session: session, onExit: onExit)
                .presentationDetents([.fraction(0.6)])
        }
    }

    private var gameMap: some View {
        Map {
            if let params = session.params {
                ForEach(Array(params.targets.enumerated()), id: \.offset) { index, target in
                    let ownerColor = nodeColor(index: index)
                    MapCircle(
                        center: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng),
                        radius: params.radiusM
                    )
                    .foregroundStyle(ownerColor.opacity(0.25))
                    .stroke(ownerColor, lineWidth: 3)
                }
            }
            ForEach(game.players.filter { $0.lat != nil && $0.lng != nil }) { player in
                Annotation(player.displayName, coordinate: CLLocationCoordinate2D(latitude: player.lat ?? 0, longitude: player.lng ?? 0)) {
                    VStack(spacing: 2) {
                        Text(String(player.displayName.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color(hex: player.color))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                        Text("\(Int(player.score))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func nodeColor(index: Int) -> Color {
        guard session.gameMode == .contestedNodes, let owner = game.nodeOwners[index] else { return gold }
        return game.players.first { $0.userId == owner }.map { Color(hex: $0.color) } ?? gold
    }

    private var scoreStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.gameMode?.displayName ?? "Game")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(gold)
                    Text("Code \(session.inviteCode) \u{00B7} \(game.players.count) player\(game.players.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Your score")
                        .font(.caption2)
                        .foregroundStyle(secondary)
                    Text(String(format: "%.0f", game.myScore))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Time left")
                        .font(.caption2)
                        .foregroundStyle(secondary)
                    Text(Self.formatTime(game.timeRemaining))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(game.timeRemaining < 60 ? .red : gold)
                        .monospacedDigit()
                }
            }

            if session.gameMode == .claimAndDefend, let params = session.params, !game.hillValues.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(params.targets.enumerated()), id: \.offset) { index, _ in
                        VStack(spacing: 2) {
                            GoldProgressBar(progress: game.hillValues[index])
                            Text("H\(index + 1)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if game.isHost && session.status == "lobby" {
                Button {
                    Task { await game.startGame() }
                } label: {
                    Text("Start Game")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(darkNavy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(gold)
                        .clipShape(.rect(cornerRadius: 12))
                }
            } else if game.isHost {
                Button(role: .destructive) {
                    Task {
                        await game.endGame()
                        showResults = true
                    }
                } label: {
                    Text("End Game")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.2))
                        .clipShape(.rect(cornerRadius: 12))
                }
            }

            Button {
                Task {
                    await game.leave()
                    onExit()
                }
            } label: {
                Text("Leave")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var resultsList: some View {
        GameResultsContent(game: game, session: session)
    }

    nonisolated static func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: Results

private struct GameResultsSheet: View {
    @Bindable var game: GameService
    let session: GameSessionDTO
    let onExit: () -> Void

    var body: some View {
        NavigationStack {
            GameResultsContent(game: game, session: session)
                .navigationTitle("Results")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            game.dismissResults()
                            onExit()
                        }
                    }
                }
        }
    }
}

private struct GameResultsContent: View {
    @Bindable var game: GameService
    let session: GameSessionDTO

    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let secondary = Color(red: 136/255, green: 153/255, blue: 170/255)

    private var standings: [GamePlayerDTO] {
        var combined = game.players
        // Make sure my row shows even if the last upsert raced the read.
        let myId = UserProfileService.shared.userId ?? ""
        if !combined.contains(where: { $0.userId == myId }) {
            combined.append(GamePlayerDTO(
                sessionId: session.id, userId: myId,
                displayName: UserProfileService.shared.username ?? "You",
                color: UserProfileService.shared.avatarColor,
                lat: nil, lng: nil, score: game.myScore, lastPing: 0
            ))
        }
        return combined.sorted { $0.score > $1.score }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(session.gameMode?.displayName ?? "Game")
                    .font(.headline)
                    .foregroundStyle(gold)

                ForEach(Array(standings.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 12) {
                        Text(index == 0 ? "\u{1F947}" : "#\(index + 1)")
                            .font(.subheadline)
                            .frame(width: 36)

                        Circle()
                            .fill(Color(hex: player.color))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Text(String(player.displayName.prefix(1)).uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            )

                        Text(player.displayName)
                            .font(.subheadline)
                            .fontWeight(index == 0 ? .bold : .regular)
                            .foregroundStyle(.white)

                        Spacer()

                        Text(String(format: "%.0f pts", player.score))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(index == 0 ? gold : secondary)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(index == 0 ? gold.opacity(0.1) : Color.white.opacity(0.03))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal)
                }

                if game.isHost {
                    Button {
                        let mode = session.gameMode ?? .kingOfTheHill
                        Task {
                            await game.dismissResults()
                            _ = await game.createSession(mode: mode, durationMinutes: max(5, session.durationS / 60))
                        }
                    } label: {
                        Text("Rematch")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color(red: 10/255, green: 15/255, blue: 30/255))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(gold)
                            .clipShape(.rect(cornerRadius: 12))
                            .padding(.horizontal)
                    }
                } else {
                    Text("The host can start a rematch.")
                        .font(.caption)
                        .foregroundStyle(secondary)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(red: 10/255, green: 15/255, blue: 30/255))
    }
}
