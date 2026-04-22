//
//  StatsDTOs.swift
//  UnpluggedShared.DTOs
//

import Foundation

public struct UserStatsResponse: Codable, Sendable {
    public let totalSessions: Int
    public let completedSessions: Int
    public let totalMinutes: Int
    public let jailbreakCount: Int
    public let points: Int

    public init(
        totalSessions: Int,
        completedSessions: Int,
        totalMinutes: Int,
        jailbreakCount: Int,
        points: Int
    ) {
        self.totalSessions = totalSessions
        self.completedSessions = completedSessions
        self.totalMinutes = totalMinutes
        self.jailbreakCount = jailbreakCount
        self.points = points
    }
}
