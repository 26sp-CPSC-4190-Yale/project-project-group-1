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

    func acceptRequest(friendID: UUID) async throws -> FriendResponse {
        try await client.send(.acceptFriend(id: friendID))
    }

    func rejectRequest(friendID: UUID) async throws {
        try await client.sendVoid(.rejectFriend(id: friendID))
    }

    func nudge(friendID: UUID) async throws {
        try await client.sendVoid(.nudgeFriend(id: friendID))
    }

    func listIncoming() async throws -> [FriendResponse] {
        try await client.send(.incomingFriendRequests)
    }

    func listOutgoing() async throws -> [FriendResponse] {
        try await client.send(.outgoingFriendRequests)
    }
}
