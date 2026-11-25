import Foundation

final class MilestoneService {
    static let shared = MilestoneService()

    private let database = DatabaseService.shared

    func checkAndFireMilestones() {
        let triggered = database.fetchTriggeredMilestones()

        let hexCount = database.fetchDiscoveredHexCount()
        let nationalPercent = Double(hexCount) / 3_200_000.0 * 100.0

        for milestone in MilestoneDefinitions.national {
            if nationalPercent >= milestone.threshold && !triggered.contains(milestone.id) {
                fire(milestoneId: milestone.id, label: milestone.label)
            }
        }

        let countiesCount = database.fetchVisitedCountiesCount()
        for milestone in MilestoneDefinitions.counties {
            if Double(countiesCount) >= milestone.threshold && !triggered.contains(milestone.id) {
                fire(milestoneId: milestone.id, label: milestone.label)
            }
        }

        let visitedStates = database.fetchVisitedStates()
        for stateRecord in visitedStates {
            guard let info = USStateData.stateInfo(for: stateRecord.stateId) else { continue }
            let countiesInState = database.fetchCountiesForState(state: stateRecord.name).count
            let statePercent = Double(countiesInState) / Double(info.countyCount) * 100.0

            for entry in MilestoneDefinitions.stateThresholds {
                let milestoneId = "state_\(info.id)_\(Int(entry.threshold))"
                if statePercent >= entry.threshold && !triggered.contains(milestoneId) {
                    let label = entry.format(info.name)
                    fire(milestoneId: milestoneId, label: label)
                }
            }
        }
    }

    private func fire(milestoneId: String, label: String) {
        database.insertTriggeredMilestone(milestoneId)
        NotificationService.shared.sendNotification(title: "🏆 Milestone!", body: label)
        // Phase 4: milestones also land in the friends' activity feed.
        Task { await SocialService.post(kind: "milestone", title: label) }
    }
}
