//
//  FriendController.swift
//  UnpluggedServer.Controllers
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import UnpluggedShared
import Vapor

extension FriendResponse: @retroactive Content {}

struct NudgeResponse: Content {
    let message: String
}

struct FriendController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let friends = routes.grouped("friends")
        friends.post("add", use: add)
        friends.delete(":friendID", use: remove)
        friends.get(use: list)
        friends.post(":friendID", "nudge", use: nudge)
    }

    @Sendable
    func add(req: Request) async throws -> FriendResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let body = try req.content.decode(AddFriendRequest.self)

        guard let target = try await UserModel.query(on: req.db)
            .filter(\.$username == body.username)
            .first()
        else {
            throw Abort(.notFound, reason: "User not found.")
        }
        let targetID = try target.requireID()

        guard targetID != userID else {
            throw Abort(.badRequest, reason: "Cannot add yourself as a friend.")
        }

        let existing = try await FriendshipModel.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$user1ID == userID)
                    g.filter(\.$user2ID == targetID)
                }
                group.group(.and) { g in
                    g.filter(\.$user1ID == targetID)
                    g.filter(\.$user2ID == userID)
                }
            }
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "Already friends.")
        }

        let friendship = FriendshipModel()
        friendship.user1ID = userID
        friendship.user2ID = targetID
        friendship.status = "accepted"
        try await friendship.save(on: req.db)

        return FriendResponse(id: targetID, username: target.username)
    }

    @Sendable
    func remove(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("friendID"),
              let friendID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        try await FriendshipModel.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$user1ID == userID)
                    g.filter(\.$user2ID == friendID)
                }
                group.group(.and) { g in
                    g.filter(\.$user1ID == friendID)
                    g.filter(\.$user2ID == userID)
                }
            }
            .delete()
        return .noContent
    }

    @Sendable
    func list(req: Request) async throws -> [FriendResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let friendships = try await FriendshipModel.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$user1ID == userID)
                group.filter(\.$user2ID == userID)
            }
            .all()

        let friendIDs = friendships.map { f in
            f.user1ID == userID ? f.user2ID : f.user1ID
        }

        guard !friendIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ friendIDs)
            .all()

        return try users.map { user in
            FriendResponse(id: try user.requireID(), username: user.username)
        }
    }

    @Sendable
    func nudge(req: Request) async throws -> NudgeResponse {
        // APNs push not yet implemented - stub returns success
        return NudgeResponse(message: "nudge sent")
    }
}
