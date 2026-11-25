import Foundation

final class UserProfileService {
    static let shared = UserProfileService()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let userId = "explorer_user_id"
        static let username = "explorer_username"
        static let avatarColor = "explorer_avatar_color"
        static let hasCompletedSetup = "explorer_has_completed_setup"
    }

    private static let avatarColors = [
        "#f5c518", "#ff6b6b", "#4ecdc4", "#45b7d1",
        "#96ceb4", "#ffeaa7", "#dfe6e9", "#fd79a8",
        "#6c5ce7", "#00b894", "#e17055", "#0984e3"
    ]

    var hasCompletedSetup: Bool {
        defaults.bool(forKey: Keys.hasCompletedSetup)
    }

    var userId: String? {
        defaults.string(forKey: Keys.userId)
    }

    var username: String? {
        defaults.string(forKey: Keys.username)
    }

    var avatarColor: String {
        defaults.string(forKey: Keys.avatarColor) ?? "#f5c518"
    }

    func setupUser(username: String) {
        let id = UUID().uuidString
        let color = Self.avatarColors.randomElement() ?? "#f5c518"
        defaults.set(id, forKey: Keys.userId)
        defaults.set(username, forKey: Keys.username)
        defaults.set(color, forKey: Keys.avatarColor)
        defaults.set(true, forKey: Keys.hasCompletedSetup)

        Task {
            await SupabaseService.shared.createUser(
                id: id,
                username: username,
                avatarColor: color
            )
        }
    }
}
