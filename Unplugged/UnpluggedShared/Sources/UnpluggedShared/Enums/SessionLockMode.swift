import Foundation

public enum SessionLockMode: String, Codable, Sendable, Hashable, CaseIterable {
    case standard
    case coLock
}

public enum SessionExitReason {
    public static let leftVoluntarily = "left_voluntarily"
    public static let leftDueToProximity = "left_due_to_proximity"
    public static let screenTimeAuthorizationCleared = "screen_time_auth_cleared"
    public static let shieldActionAttempt = "shield_action_attempt"
}

