//
//  GroupDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct CreateGroupRequest: Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct AddGroupMemberRequest: Codable, Sendable {
    public let userID: UUID

    public init(userID: UUID) {
        self.userID = userID
    }
}

public struct GroupMemberResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let joinedAt: Date

    public init(id: UUID, userID: UUID, username: String, joinedAt: Date) {
        self.id = id
        self.userID = userID
        self.username = username
        self.joinedAt = joinedAt
    }
}

public struct GroupResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let ownerID: UUID
    public let createdAt: Date
    public let members: [GroupMemberResponse]

    public init(id: UUID, name: String, ownerID: UUID, createdAt: Date, members: [GroupMemberResponse]) {
        self.id = id
        self.name = name
        self.ownerID = ownerID
        self.createdAt = createdAt
        self.members = members
    }
}
