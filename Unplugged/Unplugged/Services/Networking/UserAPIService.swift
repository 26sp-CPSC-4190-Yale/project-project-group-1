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

    // password required for password accounts, ignored for OAuth, missing password returns 400
    func deleteAccount(password: String?) async throws {
        try await client.sendVoid(.deleteMe(DeleteAccountRequest(password: password)))
    }

    func blockUser(id: UUID) async throws {
        try await client.sendVoid(.blockUser(id: id))
    }

    func unblockUser(id: UUID) async throws {
        try await client.sendVoid(.unblockUser(id: id))
    }

    func listBlocks() async throws -> [BlockedUser] {
        try await client.send(.listBlocks)
    }

    func reportUser(id: UUID, reason: String, details: String?) async throws {
        try await client.sendVoid(.reportUser(id: id, body: ReportUserRequest(reason: reason, details: details)))
    }
}
