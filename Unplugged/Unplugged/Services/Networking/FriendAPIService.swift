//
//  FriendAPIService.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

struct FriendAPIService {
    let client: APIClient

    func listFriends() async throws -> [FriendResponse] {
        try await client.send(.listFriends)
    }

    func addFriend(username: String) async throws -> FriendResponse {
        try await client.send(.addFriend(AddFriendRequest(username: username)))
    }

    func removeFriend(id: UUID) async throws {
        try await client.sendVoid(.removeFriend(id: id))
    }
}
