//
//  GroupController.swift
//  UnpluggedServer.Controllers
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import UnpluggedShared
import Vapor

extension GroupResponse: @retroactive Content {}

struct GroupController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let groups = routes.grouped("groups")
        groups.post(use: create)
        groups.get(use: list)
        groups.get(":groupID", use: get)
        groups.delete(":groupID", use: delete)
        groups.post(":groupID", "members", use: addMember)
        groups.delete(":groupID", "members", ":userID", use: removeMember)
    }

    @Sendable
    func create(req: Request) async throws -> GroupResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let body = try req.content.decode(CreateGroupRequest.self)

        let trimmed = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 50 else {
            throw Abort(.badRequest, reason: "Group name must be 1-50 characters.")
        }

        let group = GroupModel(name: trimmed, ownerID: userID)
        try await group.save(on: req.db)

        // Owner is always a member
        let member = GroupMemberModel(groupID: try group.requireID(), userID: userID)
        try await member.save(on: req.db)

        return try await buildGroupResponse(group: group, db: req.db)
    }

    @Sendable
    func list(req: Request) async throws -> [GroupResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let memberships = try await GroupMemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
        let groupIDs = memberships.map { $0.groupID }
        guard !groupIDs.isEmpty else { return [] }

        let groups = try await GroupModel.query(on: req.db)
            .filter(\.$id ~~ groupIDs)
            .all()

        var results: [GroupResponse] = []
        for group in groups {
            results.append(try await buildGroupResponse(group: group, db: req.db))
        }
        return results
    }

    @Sendable
    func get(req: Request) async throws -> GroupResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let group = try await requireGroup(req: req)
        let groupID = try group.requireID()

        // Must be a member
        let membership = try await GroupMemberModel.query(on: req.db)
            .filter(\.$groupID == groupID)
            .filter(\.$userID == userID)
            .first()
        guard membership != nil else { throw Abort(.forbidden) }

        return try await buildGroupResponse(group: group, db: req.db)
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let group = try await requireGroup(req: req)

        guard group.ownerID == userID else { throw Abort(.forbidden) }

        let groupID = try group.requireID()
        try await GroupMemberModel.query(on: req.db)
            .filter(\.$groupID == groupID)
            .delete()
        try await group.delete(on: req.db)
        return .noContent
    }

    @Sendable
    func addMember(req: Request) async throws -> GroupResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let group = try await requireGroup(req: req)
        let groupID = try group.requireID()

        guard group.ownerID == userID else { throw Abort(.forbidden) }

        let body = try req.content.decode(AddGroupMemberRequest.self)

        guard try await UserModel.find(body.userID, on: req.db) != nil else {
            throw Abort(.notFound, reason: "User not found.")
        }

        let existing = try await GroupMemberModel.query(on: req.db)
            .filter(\.$groupID == groupID)
            .filter(\.$userID == body.userID)
            .first()
        if existing == nil {
            let member = GroupMemberModel(groupID: groupID, userID: body.userID)
            try await member.save(on: req.db)
        }

        return try await buildGroupResponse(group: group, db: req.db)
    }

    @Sendable
    func removeMember(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let group = try await requireGroup(req: req)
        let groupID = try group.requireID()

        guard let idString = req.parameters.get("userID"),
              let targetID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        // Owner can remove anyone; otherwise users can only remove themselves
        guard group.ownerID == userID || targetID == userID else {
            throw Abort(.forbidden)
        }

        // Cannot remove the owner
        if targetID == group.ownerID {
            throw Abort(.badRequest, reason: "Cannot remove the group owner.")
        }

        try await GroupMemberModel.query(on: req.db)
            .filter(\.$groupID == groupID)
            .filter(\.$userID == targetID)
            .delete()
        return .noContent
    }

    // MARK: - Helpers

    private func requireGroup(req: Request) async throws -> GroupModel {
        guard let idString = req.parameters.get("groupID"),
              let groupID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard let group = try await GroupModel.find(groupID, on: req.db) else {
            throw Abort(.notFound)
        }
        return group
    }

    private func buildGroupResponse(group: GroupModel, db: Database) async throws -> GroupResponse {
        let groupID = try group.requireID()
        let members = try await GroupMemberModel.query(on: db)
            .filter(\.$groupID == groupID)
            .all()
        let userIDs = members.map { $0.userID }
        let users = try await UserModel.query(on: db)
            .filter(\.$id ~~ userIDs)
            .all()
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        let memberResponses: [GroupMemberResponse] = members.compactMap { member in
            guard let memberID = member.id,
                  let user = userMap[member.userID] else { return nil }
            return GroupMemberResponse(
                id: memberID,
                userID: member.userID,
                username: user.username,
                joinedAt: member.joinedAt
            )
        }

        return GroupResponse(
            id: groupID,
            name: group.name,
            ownerID: group.ownerID,
            createdAt: group.createdAt ?? Date(),
            members: memberResponses
        )
    }
}
