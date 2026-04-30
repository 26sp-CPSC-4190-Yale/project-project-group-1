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
        do {
            return try await client.send(.acceptFriend(id: friendID))
        } catch {
            guard Self.shouldTryRequestIDFallback(after: error) else { throw error }
            return try await client.send(.acceptFriendRequest(id: friendID))
        }
    }

    func rejectIncomingRequest(requestID: UUID) async throws {
        do {
            try await client.sendVoid(.rejectFriendRequest(id: requestID))
        } catch {
            guard Self.shouldTryRequestIDFallback(after: error) else { throw error }
            try await client.sendVoid(.rejectFriend(id: requestID))
        }
    }

    func cancelOutgoingRequest(targetID: UUID) async throws {
        try await client.sendVoid(.rejectFriend(id: targetID))
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

    func getProfile(id: UUID) async throws -> FriendProfileResponse {
        try await client.send(.getFriendProfile(id: id))
    }

    func getLeaderboard() async throws -> [LeaderboardEntryResponse] {
        try await client.send(.getLeaderboard)
    }

    private static func shouldTryRequestIDFallback(after error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "Vapor" else { return false }
        return [400, 403, 404, 409, 422].contains(nsError.code)
    }
}
