//
//  CompletionDTOs.swift
//  UnpluggedShared.DTOs
//

import Foundation

public struct CompletionRequest: Codable, Sendable {
    public let proofText: String

    public init(proofText: String) {
        self.proofText = proofText
    }
}

public struct CompletionResponse: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let submitterID: UUID
    public let proofText: String
    public let status: CompletionStatus
    public let createdAt: Date

    public init(id: UUID, sessionID: UUID, submitterID: UUID, proofText: String, status: CompletionStatus, createdAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.submitterID = submitterID
        self.proofText = proofText
        self.status = status
        self.createdAt = createdAt
    }
}

public struct VerifyRequest: Codable, Sendable {
    public let note: String?

    public init(note: String? = nil) {
        self.note = note
    }
}
