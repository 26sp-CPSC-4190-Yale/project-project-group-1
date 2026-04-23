//
//  MedalDTOs.swift
//  UnpluggedShared.DTOs
//

import Foundation

public struct MedalResponse: Codable, Sendable, Hashable {
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

/// Catalog entry: one per medal that exists, with the user's unlock status.
/// `earnedAt == nil` means locked. `howToUnlock` is a short human-readable rule.
public struct MedalCatalogEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID { medal.id }
    public let medal: MedalResponse
    public let earnedAt: Date?
    public let howToUnlock: String

    public init(medal: MedalResponse, earnedAt: Date?, howToUnlock: String) {
        self.medal = medal
        self.earnedAt = earnedAt
        self.howToUnlock = howToUnlock
    }

    public var isUnlocked: Bool { earnedAt != nil }
}
