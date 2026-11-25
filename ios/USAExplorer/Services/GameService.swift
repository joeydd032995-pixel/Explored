import Foundation
import CoreLocation

/// Phase 4 centerpiece: the shared multiplayer Territory Games engine.
///
/// Friends/honor model: each device computes its own score locally on a 1s
/// tick, publishes position + score every ~2s via PostgREST upserts, and polls
/// the other players' rows to keep the map live. No Supabase Realtime
/// dependency in v1. Live location is shared ONLY while a session is live:
/// position rows are deleted on leave and at session end.
@MainActor
@Observable
final class GameService {
    static let shared = GameService()

    // MARK: Published state

    private(set) var session: GameSessionDTO?
    private(set) var players: [GamePlayerDTO] = []
    var myScore: Double = 0.0
    var timeRemaining: Int = 0
    var lastError: String?
    /// Per-hill value 0...1 for claim_and_defend (decays when unattended).
    private(set) var hillValues: [Double] = []
    /// Node owner (user id) per target index for contested_nodes.
    private(set) var nodeOwners: [Int: String] = [:]
    private(set) var capturedCount = 0

    var isHost: Bool { session?.hostUserId == UserProfileService.shared.userId }
    var isInSession: Bool { session != nil }

    private weak var locationService: LocationService?
    private var tickTask: Task<Void, Never>?
    private var lastPublishAt: Date = .distantPast
    private var holdSeconds: [Int: Int] = [:]
    private var lastEventsAt: Date = .distantPast
    private var haptics = HapticService.shared

    private init() {}

    /// Called from ContentView right after the LocationService is created.
    func configure(locationService: LocationService) {
        self.locationService = locationService
    }

    // MARK: Lobby

    func fetchOpenSessions() async -> [GameSessionDTO] {
        await SupabaseService.shared.fetchOpenSessions()
    }

    /// Host creates a session with hills/nodes seeded around their location.
    @discardableResult
    func createSession(mode: GameMode, durationMinutes: Int) async -> Bool {
        lastError = nil
        guard session == nil, let userId = UserProfileService.shared.userId else {
            lastError = "Finish setting up your explorer profile first."
            return false
        }
        guard let here = locationService?.currentLocation?.coordinate else {
            lastError = "Need your location to place the hills. Enable location and try again."
            return false
        }

        let params = Self.makeParams(mode: mode, around: here)
        let insert = GameSessionInsert(
            id: UUID().uuidString,
            mode: mode.rawValue,
            hostUserId: userId,
            hostName: UserProfileService.shared.username ?? "explorer",
            status: "lobby",
            params: params,
            inviteCode: InviteCode.generate(),
            durationS: durationMinutes * 60
        )

        guard let created = await SupabaseService.shared.createGameSession(insert) else {
            lastError = "Couldn't reach the game server. Check your connection."
            return false
        }

        beginSession(created, isHost: true)
        await SupabaseService.shared.logGameEvent(GameEventInsert(
            sessionId: created.id, userId: userId, kind: "start",
            payload: GameEventPayload(label: mode.displayName)
        ))
        await SocialService.post(kind: "game", title: "started a \(mode.displayName) game — code \(created.inviteCode)")
        MetricsService.shared.recordGameSessionStart()
        return true
    }

    @discardableResult
    func joinByCode(_ rawCode: String) async -> Bool {
        lastError = nil
        guard session == nil, let userId = UserProfileService.shared.userId else {
            lastError = "Finish setting up your explorer profile first."
            return false
        }
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else {
            lastError = "Invite codes are 6 characters."
            return false
        }
        guard let target = await SupabaseService.shared.fetchSessionByCode(code: code), !target.isEnded else {
            lastError = "No open game found for \(code)."
            return false
        }

        beginSession(target, isHost: target.hostUserId == userId)
        await publishPresence()
        return true
    }

    @discardableResult
    func join(session: GameSessionDTO) async -> Bool {
        lastError = nil
        guard self.session == nil, let userId = UserProfileService.shared.userId else { return false }
        guard !session.isEnded else {
            lastError = "That game already ended."
            return false
        }
        beginSession(session, isHost: session.hostUserId == userId)
        await publishPresence()
        return true
    }

    // MARK: Session lifecycle

    func startGame() async {
        guard let session, isHost, session.status == "lobby" else { return }
        let patch = GameSessionPatch(status: "live", startedAt: Self.isoNow())
        if await SupabaseService.shared.updateSession(id: session.id, patch: patch) {
            self.session = await SupabaseService.shared.fetchSession(id: session.id)
        }
        haptics.gameStart()
    }

    func endGame() async {
        guard let session else { return }
        if isHost && !session.isEnded {
            let patch = GameSessionPatch(status: "ended", endedAt: Self.isoNow())
            _ = await SupabaseService.shared.updateSession(id: session.id, patch: patch)
        }
        stopLoops()
        if let userId = UserProfileService.shared.userId {
            await SupabaseService.shared.removeGamePlayer(sessionId: session.id, userId: userId)
        }
        if let current = await SupabaseService.shared.fetchSession(id: session.id) {
            self.session = current
        }
        haptics.gameEnd()
    }

    /// Leave without ending: deletes my live position row immediately.
    func leave() async {
        guard let session else { return }
        stopLoops()
        if let userId = UserProfileService.shared.userId {
            await SupabaseService.shared.removeGamePlayer(sessionId: session.id, userId: userId)
        }
        self.session = nil
        players = []
        myScore = 0
        hillValues = []
        nodeOwners = [:]
        holdSeconds = [:]
        capturedCount = 0
    }

    func dismissResults() {
        session = nil
        players = []
        myScore = 0
        hillValues = []
        nodeOwners = [:]
        holdSeconds = [:]
        capturedCount = 0
    }

    // MARK: Engine

    private func beginSession(_ session: GameSessionDTO, isHost: Bool) {
        self.session = session
        myScore = 0
        capturedCount = 0
        let targetCount = session.params?.targets.count ?? 0
        hillValues = Array(repeating: 1.0, count: targetCount)
        nodeOwners = [:]
        holdSeconds = [:]
        players = []

        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopLoops() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// 1s tick: local scoring, countdown, presence publishing, opponent polling.
    private func tick() {
        guard let session else {
            stopLoops()
            return
        }
        guard session.status == "live" else {
            Task { await poll() }   // lobby: keep presence + status fresh
            return
        }

        // Countdown from started_at + duration.
        if let started = Self.parseISO(session.startedAt) {
            let elapsed = Date().timeIntervalSince(started)
            timeRemaining = max(0, session.durationS - Int(elapsed))
            if timeRemaining == 0 {
                Task { await endGame() }
                return
            }
        }

        scoreTick(session: session)
        Task { await poll() }

        if Date().timeIntervalSince(lastPublishAt) >= 2 {
            lastPublishAt = Date()
            Task { await publishPresence() }
        }
    }

    private func scoreTick(session: GameSessionDTO) {
        guard let params = session.params, let loc = locationService?.currentLocation?.coordinate else { return }

        switch session.gameMode {
        case .kingOfTheHill:
            if let hill = params.targets.first, Self.meters(loc, hill) <= params.radiusM {
                myScore += 1
            }

        case .claimAndDefend:
            for (index, hill) in params.targets.enumerated() {
                if Self.meters(loc, hill) <= params.radiusM {
                    // Attending refills and pays the hill's value.
                    hillValues[index] = min(1.0, hillValues[index] + 0.25)
                    myScore += hillValues[index]
                } else {
                    // Unattended hills decay ~2%/s — keep moving.
                    hillValues[index] = max(0.0, hillValues[index] - 0.02)
                }
            }

        case .contestedNodes:
            let myId = UserProfileService.shared.userId ?? ""
            for (index, node) in params.targets.enumerated() {
                if Self.meters(loc, node) <= params.radiusM {
                    let held = (holdSeconds[index] ?? 0) + 1
                    holdSeconds[index] = held
                    if nodeOwners[index] == nil || nodeOwners[index] == myId {
                        if nodeOwners[index] == nil, held >= params.holdSeconds {
                            nodeOwners[index] = myId
                            capturedCount += 1
                            haptics.gameCapture()
                            Task {
                                await SupabaseService.shared.logGameEvent(GameEventInsert(
                                    sessionId: session.id, userId: myId, kind: "capture",
                                    payload: GameEventPayload(targetIndex: index, label: node.label)
                                ))
                            }
                        }
                        if nodeOwners[index] == myId { myScore += 0.5 }
                    }
                } else if nodeOwners[index] == myId {
                    holdSeconds[index] = max(0, (holdSeconds[index] ?? 0) - 1)
                }
            }

        case .none:
            break
        }
    }

    private func poll() async {
        guard let session else { return }
        async let playersTask = SupabaseService.shared.fetchGamePlayers(sessionId: session.id)
        async let eventsTask = SupabaseService.shared.fetchGameEvents(sessionId: session.id)
        let fetchedPlayers = await playersTask
        let events = await eventsTask
        players = fetchedPlayers

        // Apply other players' captures to my ownership view.
        let myId = UserProfileService.shared.userId ?? ""
        for event in events where event.kind == "capture" {
            guard let index = event.payload?.targetIndex, event.userId != myId else { continue }
            if let captured = Self.parseISO(event.createdAt), captured > lastEventsAt {
                nodeOwners[index] = event.userId
                holdSeconds[index] = 0
            }
        }
        lastEventsAt = events.compactMap { Self.parseISO($0.createdAt) }.max() ?? lastEventsAt

        // Remote ended / transitioned sessions.
        if !session.isEnded, let remote = await SupabaseService.shared.fetchSession(id: session.id), remote.status != session.status {
            self.session = remote
            if remote.isEnded {
                stopLoops()
                haptics.gameEnd()
            }
        }
    }

    private func publishPresence() async {
        guard let session, !session.isEnded, let userId = UserProfileService.shared.userId else { return }
        let coord = locationService?.currentLocation?.coordinate
        let upsert = GamePlayerUpsert(
            sessionId: session.id,
            userId: userId,
            displayName: UserProfileService.shared.username ?? "explorer",
            color: UserProfileService.shared.avatarColor,
            lat: coord?.latitude,
            lng: coord?.longitude,
            score: myScore,
            lastPing: Int64(Date().timeIntervalSince1970)
        )
        await SupabaseService.shared.upsertGamePlayer(upsert)
    }

    // MARK: Seeding & helpers

    /// Host seeds hills/nodes around their location: a walkable ring so the
    /// game starts with real targets instead of a blank map.
    private static func makeParams(mode: GameMode, around center: CLLocationCoordinate2D) -> GameParams {
        func offset(meters: Double, bearing: Double) -> GameTarget {
            let dLat = meters * cos(bearing) / 111_320
            let dLng = meters * sin(bearing) / (111_320 * max(0.1, cos(center.latitude * .pi / 180)))
            return GameTarget(
                lat: center.latitude + dLat,
                lng: center.longitude + dLng,
                label: ""
            )
        }

        let count: Int
        let spread: Double
        switch mode {
        case .kingOfTheHill: count = 1; spread = 40
        case .claimAndDefend: count = 3; spread = 140
        case .contestedNodes: count = 4; spread = 200
        }

        var targets: [GameTarget] = []
        if mode == .kingOfTheHill {
            targets.append(GameTarget(lat: center.latitude, lng: center.longitude, label: "The Hill"))
        } else {
            for i in 0..<count {
                var target = offset(meters: spread, bearing: Double(i) * (2 * .pi / Double(count)))
                target.label = mode == .claimAndDefend ? "Hill \(i + 1)" : "Node \(i + 1)"
                targets.append(target)
            }
        }

        return GameParams(
            targets: targets,
            radiusM: 60,
            holdSeconds: mode == .contestedNodes ? 5 : 0
        )
    }

    nonisolated static func meters(_ a: CLLocationCoordinate2D, _ b: GameTarget) -> Double {
        let theta1 = a.latitude * .pi / 180, theta2 = b.lat * .pi / 180
        let dTheta = (b.lat - a.latitude) * .pi / 180
        let dLambda = (b.lng - a.longitude) * .pi / 180
        let h = sin(dTheta / 2) * sin(dTheta / 2) + cos(theta1) * cos(theta2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 6_371_000 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    nonisolated static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    nonisolated static func parseISO(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
