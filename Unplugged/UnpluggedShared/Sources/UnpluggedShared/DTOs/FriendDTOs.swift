//
//  FriendDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public enum PresenceStatus: String, Codable, Sendable, Hashable {
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

public struct FriendResponse: Codable, Sendable, Identifiable, Hashable {
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

/// Expanded profile view for a single friend — richer than FriendResponse's summary.
public struct FriendProfileResponse: Codable, Sendable, Identifiable {
    public var id: UUID { friend.id }
    public let friend: FriendResponse
    public let stats: UserStatsResponse
    public let medals: [UserMedalResponse]

    public init(
        friend: FriendResponse,
        stats: UserStatsResponse,
        medals: [UserMedalResponse]
    ) {
        self.friend = friend
        self.stats = stats
        self.medals = medals
    }
}
