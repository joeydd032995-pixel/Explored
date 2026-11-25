import Foundation

nonisolated struct MilestoneEntry: Sendable {
    let id: String
    let threshold: Double
    let label: String
}

nonisolated enum MilestoneDefinitions: Sendable {
    static let national: [MilestoneEntry] = [
        MilestoneEntry(id: "national_0.1", threshold: 0.1, label: "You've explored 0.1% of the US!"),
        MilestoneEntry(id: "national_1", threshold: 1.0, label: "You've explored 1% of the US!"),
    ]

    static let counties: [MilestoneEntry] = [
        MilestoneEntry(id: "counties_100", threshold: 100, label: "100 counties visited!"),
        MilestoneEntry(id: "counties_500", threshold: 500, label: "500 counties visited!"),
        MilestoneEntry(id: "counties_1000", threshold: 1000, label: "1,000 counties visited!"),
    ]

    static let stateThresholds: [(threshold: Double, format: (String) -> String)] = [
        (25, { "25% of \($0) explored!" }),
        (50, { "Halfway through \($0)!" }),
        (100, { "You've completed \($0)!" }),
    ]
}
