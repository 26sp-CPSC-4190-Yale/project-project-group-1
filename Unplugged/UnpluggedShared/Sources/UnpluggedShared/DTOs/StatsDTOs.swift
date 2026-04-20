//
//  StatsDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

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

    public init(
        hoursUnplugged: Int,
        rank: Int,
        totalSessions: Int,
        longestStreak: Int,
        currentStreak: Int,
        avgSessionLengthMinutes: Double,
        friendsCount: Int,
        totalMinutes: Int
    ) {
        self.hoursUnplugged = hoursUnplugged
        self.rank = rank
        self.totalSessions = totalSessions
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
        self.avgSessionLengthMinutes = avgSessionLengthMinutes
        self.friendsCount = friendsCount
        self.totalMinutes = totalMinutes
    }
}
