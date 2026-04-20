//
//  RecapDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct JailbreakEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let detectedAt: Date
    public let reason: String?

    public init(id: UUID, userID: UUID, username: String, detectedAt: Date, reason: String? = nil) {
        self.id = id
        self.userID = userID
        self.username = username
        self.detectedAt = detectedAt
        self.reason = reason
    }
}

public struct SessionRecapResponse: Codable, Sendable, Identifiable {
    public var id: UUID { sessionID }
    public let sessionID: UUID
    public let title: String?
    public let startedAt: Date?
    public let endedAt: Date?
    public let durationSeconds: Int
    public let participants: [ParticipantResponse]
    public let jailbreaks: [JailbreakEntry]
    public let completionRate: Double

    public init(
        sessionID: UUID,
        title: String?,
        startedAt: Date?,
        endedAt: Date?,
        durationSeconds: Int,
        participants: [ParticipantResponse],
        jailbreaks: [JailbreakEntry],
        completionRate: Double
    ) {
        self.sessionID = sessionID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.participants = participants
        self.jailbreaks = jailbreaks
        self.completionRate = completionRate
    }
}
