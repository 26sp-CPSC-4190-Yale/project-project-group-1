import Foundation

public struct UserStatsResponse: Codable, Sendable {
    public let hoursUnplugged: Int
    public let rank: Int
    public let totalSessions: Int
    public let longestStreak: Int
    public let currentStreak: Int
    public let avgSessionLengthMinutes: Double
    public let friendsCount: Int
    public let totalMinutes: Int
    public let plannedMinutes: Int
    public let avgPlannedMinutes: Double
    public let earlyLeaveCount: Int

    public init(
        hoursUnplugged: Int,
        rank: Int,
        totalSessions: Int,
        longestStreak: Int,
        currentStreak: Int,
        avgSessionLengthMinutes: Double,
        friendsCount: Int,
        totalMinutes: Int,
        plannedMinutes: Int = 0,
        avgPlannedMinutes: Double = 0,
        earlyLeaveCount: Int = 0
    ) {
        self.hoursUnplugged = hoursUnplugged
        self.rank = rank
        self.totalSessions = totalSessions
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
        self.avgSessionLengthMinutes = avgSessionLengthMinutes
        self.friendsCount = friendsCount
        self.totalMinutes = totalMinutes
        self.plannedMinutes = plannedMinutes
        self.avgPlannedMinutes = avgPlannedMinutes
        self.earlyLeaveCount = earlyLeaveCount
    }
}

public struct LeaderboardEntryResponse: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let username: String
    public let hoursUnplugged: Int
    public let minutesFocused: Int
    public let rank: Int
    public let isCurrentUser: Bool

    public init(
        id: UUID,
        username: String,
        hoursUnplugged: Int,
        minutesFocused: Int,
        rank: Int,
        isCurrentUser: Bool
    ) {
        self.id = id
        self.username = username
        self.hoursUnplugged = hoursUnplugged
        self.minutesFocused = minutesFocused
        self.rank = rank
        self.isCurrentUser = isCurrentUser
    }
}
