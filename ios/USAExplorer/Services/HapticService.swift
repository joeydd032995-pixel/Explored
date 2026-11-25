import UIKit

final class HapticService {
    static let shared = HapticService()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        lightImpact.prepare()
        mediumImpact.prepare()
        notification.prepare()
    }

    func hexDiscovered() {
        lightImpact.impactOccurred()
    }

    func countyDiscovered() {
        mediumImpact.impactOccurred()
    }

    func stateDiscovered() {
        notification.notificationOccurred(.success)
    }

    func checkInConfirmed() {
        notification.notificationOccurred(.success)
    }

    func nodeCapture() {
        notification.notificationOccurred(.success)
    }

    func nodeLost() {
        notification.notificationOccurred(.warning)
    }

    func reportSubmitted() {
        mediumImpact.impactOccurred()
    }

    func reportConfirmed() {
        lightImpact.impactOccurred()
    }

    // Territory Games (phase 4)

    func gameStart() {
        notification.notificationOccurred(.success)
    }

    func gameEnd() {
        notification.notificationOccurred(.success)
    }

    func gameCapture() {
        notification.notificationOccurred(.success)
    }

    func gameTick() {
        lightImpact.impactOccurred()
    }
}
