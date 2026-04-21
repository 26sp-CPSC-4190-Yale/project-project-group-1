//
//  MedalDTOs.swift
//  UnpluggedShared.DTOs
//

import Foundation

public struct MedalResponse: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let icon: String

    public init(id: UUID, name: String, description: String, icon: String) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
    }
}

public struct UserMedalResponse: Codable, Sendable {
    public let medal: MedalResponse
    public let earnedAt: Date

    public init(medal: MedalResponse, earnedAt: Date) {
        self.medal = medal
        self.earnedAt = earnedAt
    }
}
