//
//  SessionDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct CreateSessionRequest: Codable, Sendable {
    public let title: String
    public let durationSeconds: Int
    public let latitude: Double?
    public let longitude: Double?

    public init(title: String, durationSeconds: Int, latitude: Double? = nil, longitude: Double? = nil) {
        self.title = title
        self.durationSeconds = durationSeconds
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct StartSessionRequest: Codable, Sendable {
    public init() {}
}

public struct EndSessionRequest: Codable, Sendable {
    public init() {}
}

public struct JoinSessionRequest: Codable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct ReportJailbreakRequest: Codable, Sendable {
    public let reason: String
    public let detectedAt: Date

    public init(reason: String, detectedAt: Date = Date()) {
        self.reason = reason
        self.detectedAt = detectedAt
    }
}

public struct SessionResponse: Codable, Sendable, Identifiable {
    public var id: UUID { session.id }
    public let session: Session
    public let participants: [ParticipantResponse]

    public init(session: Session, participants: [ParticipantResponse]) {
        self.session = session
        self.participants = participants
    }
}

public struct ParticipantResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let status: ParticipantStatus
    public let joinedAt: Date?
    public let isHost: Bool

    public init(
        id: UUID,
        userID: UUID,
        username: String,
        status: ParticipantStatus,
        joinedAt: Date? = nil,
        isHost: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.username = username
        self.status = status
        self.joinedAt = joinedAt
        self.isHost = isHost
    }
}

public struct SessionHistoryResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String?
    public let startedAt: Date?
    public let endedAt: Date?
    public let durationSeconds: Int?
    public let participantCount: Int
    public let latitude: Double?
    public let longitude: Double?

    public init(
        id: UUID,
        title: String?,
        startedAt: Date?,
        endedAt: Date?,
        durationSeconds: Int?,
        participantCount: Int,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.participantCount = participantCount
        self.latitude = latitude
        self.longitude = longitude
    }
}
