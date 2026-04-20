//
//  UserAPIService.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

struct UserAPIService {
    let client: APIClient

    func getMe() async throws -> User {
        try await client.send(.getMe)
    }

    func searchUsers(query: String) async throws -> [User] {
        try await client.send(.searchUsers(query: query))
    }

    func updateMe(username: String) async throws -> User {
        try await client.send(.updateMe(UpdateUserRequest(username: username)))
    }

    func registerDeviceToken(_ token: String) async throws {
        try await client.sendVoid(.registerDeviceToken(token))
    }
}
