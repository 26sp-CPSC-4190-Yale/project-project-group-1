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
    /// Planned duration of the session, in seconds.
    public let durationSeconds: Int
    /// Actual time the room was locked in — `endedAt - lockedAt`, clamped into
    /// `[0, durationSeconds]`. Less than `durationSeconds` means the host ended
    /// early (or the room never reached its scheduled end for other reasons).
    public let actualFocusedSeconds: Int
    /// `true` when the room ended before its planned end (with a small
    /// tolerance to absorb clock drift).
    public let endedEarly: Bool
    public let participants: [ParticipantResponse]
    public let jailbreaks: [JailbreakEntry]
    /// Fraction of the planned duration the room actually stayed locked for —
    /// `actualFocusedSeconds / durationSeconds`, in `[0, 1]`.
    public let completionRate: Double

    public init(
        sessionID: UUID,
        title: String?,
        startedAt: Date?,
        endedAt: Date?,
        durationSeconds: Int,
        actualFocusedSeconds: Int,
        endedEarly: Bool,
        participants: [ParticipantResponse],
        jailbreaks: [JailbreakEntry],
        completionRate: Double
    ) {
        self.sessionID = sessionID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.actualFocusedSeconds = actualFocusedSeconds
        self.endedEarly = endedEarly
        self.participants = participants
        self.jailbreaks = jailbreaks
        self.completionRate = completionRate
    }
}
