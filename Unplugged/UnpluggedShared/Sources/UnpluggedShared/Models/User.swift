//
//  User.swift
//  UnpluggedShared.Models
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct User: Codable, Identifiable, Sendable {
    public let id: UUID
    public let username: String
    public let createdAt: Date

    public init(id: UUID, username: String, createdAt: Date) {
        self.id = id
        self.username = username
        self.createdAt = createdAt
    }
}

