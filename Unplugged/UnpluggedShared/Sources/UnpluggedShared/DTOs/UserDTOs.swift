//
//  UserDTOs.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct UpdateUserRequest: Codable, Sendable {
    public let username: String

    public init(username: String) {
        self.username = username
    }
}

public struct DeviceTokenRequest: Codable, Sendable {
    public let deviceToken: String

    public init(deviceToken: String) {
        self.deviceToken = deviceToken
    }
}

public struct DeleteAccountRequest: Codable, Sendable {
    public let password: String?

    public init(password: String?) {
        self.password = password
    }
}

public struct ReportUserRequest: Codable, Sendable {
    public let reason: String
    public let details: String?

    public init(reason: String, details: String? = nil) {
        self.reason = reason
        self.details = details
    }
}

public struct BlockedUser: Codable, Sendable, Identifiable {
    public let id: UUID
    public let username: String
    public let blockedAt: Date

    public init(id: UUID, username: String, blockedAt: Date) {
        self.id = id
        self.username = username
        self.blockedAt = blockedAt
    }
}
