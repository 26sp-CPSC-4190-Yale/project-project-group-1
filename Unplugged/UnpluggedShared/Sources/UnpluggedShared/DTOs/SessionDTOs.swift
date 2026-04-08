//
//  SessionDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct CreateSessionRequest: Codable, Sendable {
    public init() {}
}

public struct JoinSessionRequest: Codable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
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

public struct ParticipantResponse: Codable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let status: ParticipantStatus

    public init(id: UUID, userID: UUID, username: String, status: ParticipantStatus) {
        self.id = id
        self.userID = userID
        self.username = username
        self.status = status
    }
}

