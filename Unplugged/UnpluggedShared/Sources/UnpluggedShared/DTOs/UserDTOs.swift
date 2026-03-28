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
