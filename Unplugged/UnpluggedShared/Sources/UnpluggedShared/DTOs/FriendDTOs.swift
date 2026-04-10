//
//  FriendDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct AddFriendRequest: Codable, Sendable {
    public let username: String

    public init(username: String) {
        self.username = username
    }
}

public struct FriendResponse: Codable, Sendable {
    public let id: UUID
    public let username: String
    // optional: "pending" | "accepted"
    public let status: String?

    public init(id: UUID, username: String, status: String? = nil) {
        self.id = id
        self.username = username
        self.status = status
    }
}
