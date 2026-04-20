//
//  FriendDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public enum PresenceStatus: String, Codable, Sendable {
    case online
    case unplugged
    case offline
}

public struct AddFriendRequest: Codable, Sendable {
    public let username: String

    public init(username: String) {
        self.username = username
    }
}

public struct FriendResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let username: String
    // "pending" | "accepted"
    public let status: String?
    public let presence: PresenceStatus
    public let hoursUnplugged: Int
    public let lastActiveAt: Date?

    public init(
        id: UUID,
        username: String,
        status: String? = nil,
        presence: PresenceStatus = .offline,
        hoursUnplugged: Int = 0,
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.status = status
        self.presence = presence
        self.hoursUnplugged = hoursUnplugged
        self.lastActiveAt = lastActiveAt
    }
}

public struct NudgeResponse: Codable, Sendable {
    public let status: String

    public init(status: String = "nudge sent") {
        self.status = status
    }
}
