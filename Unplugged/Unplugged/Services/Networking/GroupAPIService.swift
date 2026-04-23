import Foundation
import UnpluggedShared

struct GroupAPIService {
    let client: APIClient

    func listGroups() async throws -> [GroupResponse] {
        try await client.send(.listGroups)
    }

    func getGroup(id: UUID) async throws -> GroupResponse {
        try await client.send(.getGroup(id: id))
    }

    func createGroup(name: String) async throws -> GroupResponse {
        try await client.send(.createGroup(CreateGroupRequest(name: name)))
    }

    func addMember(groupID: UUID, userID: UUID) async throws -> GroupResponse {
        try await client.send(.addGroupMember(id: groupID, body: AddGroupMemberRequest(userID: userID)))
    }

    func removeMember(groupID: UUID, userID: UUID) async throws {
        try await client.sendVoid(.removeGroupMember(id: groupID, userID: userID))
    }

    func deleteGroup(id: UUID) async throws {
        try await client.sendVoid(.deleteGroup(id: id))
    }
}
