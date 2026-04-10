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
extension NudgeResponse: @retroactive Content {}

struct FriendController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let friends = routes.grouped("friends")
        // POST /friends -> send friend request (or accept if reciprocal exists)
        friends.post(use: add)
        friends.delete(":friendID", use: remove)
        friends.get(use: list) // list accepted friends
        friends.post(":friendID", "nudge", use: nudge)
        friends.post(":friendID", "accept", use: acceptFromUser)
        friends.post(":friendID", "reject", use: rejectFromUser)

        let requests = friends.grouped("requests")
        requests.get("incoming", use: listIncoming)
        requests.get("outgoing", use: listOutgoing)
        requests.post(":requestID", "accept", use: acceptRequest)
        requests.post(":requestID", "reject", use: rejectRequest)
    }

    @Sendable
    func add(req: Request) async throws -> FriendResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let body = try req.content.decode(AddFriendRequest.self)

        guard let target = try await UserModel.query(on: req.db)
            .filter(\.$username, .custom("ILIKE"), body.username)
            .first()
        else {
            throw Abort(.notFound, reason: "User not found.")
        }
        let targetID = try target.requireID()

        guard targetID != userID else {
            throw Abort(.badRequest, reason: "Cannot add yourself as a friend.")
        }
        // check for existing relationship
        let existingQuery = try await FriendshipModel.query(on: req.db)
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
        if let existing = existingQuery {
            if existing.status == "accepted" {
                throw Abort(.conflict, reason: "Already friends.")
            }
            // if there is a pending from the other user, accept it
            if existing.status == "pending" && existing.user1ID == targetID && existing.user2ID == userID {
                existing.status = "accepted"
                try await existing.save(on: req.db)
                return try await Self.buildFriendResponse(user: target, status: "accepted", db: req.db)
            }
            // if there's already a pending from this user, inform conflict
            throw Abort(.conflict, reason: "Friend request already exists.")
        }

        // create pending request
        let friendship = FriendshipModel()
        friendship.user1ID = userID
        friendship.user2ID = targetID
        friendship.status = "pending"
        try await friendship.save(on: req.db)

        guard let sender = try await UserModel.find(userID, on: req.db) else {
            throw Abort(.internalServerError)
        }
        await NotificationService.send(
            to: targetID,
            title: "New Friend Request",
            body: "\(sender.username) sent you a friend request.",
            type: NotificationService.NotificationType.friendRequest,
            on: req.db,
            application: req.application
        )

        return try await Self.buildFriendResponse(user: target, status: "pending", db: req.db)
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

        // only return accepted friendships
        let friendships = try await FriendshipModel.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$user1ID == userID)
                    g.filter(\.$status == "accepted")
                }
                group.group(.and) { g in
                    g.filter(\.$user2ID == userID)
                    g.filter(\.$status == "accepted")
                }
            }
            .all()

        let friendIDs = friendships.map { f in
            f.user1ID == userID ? f.user2ID : f.user1ID
        }

        guard !friendIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ friendIDs)
            .all()

        var results: [FriendResponse] = []
        for user in users {
            results.append(try await Self.buildFriendResponse(user: user, status: "accepted", db: req.db))
        }
        return results
    }

    // List incoming (requests where current user is recipient)
    @Sendable
    func listIncoming(req: Request) async throws -> [FriendResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let incoming = try await FriendshipModel.query(on: req.db)
            .filter(\.$user2ID == userID)
            .filter(\.$status == "pending")
            .all()

        let requesterIDs = incoming.map { $0.user1ID }
        guard !requesterIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ requesterIDs)
            .all()

        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        var results: [FriendResponse] = []
        for friendship in incoming {
            guard let friendshipID = friendship.id,
                  let user = userMap[friendship.user1ID] else { continue }
            results.append(try await Self.buildFriendResponse(
                user: user,
                status: "pending",
                overrideID: nil,
                db: req.db
            ))
        }
        return results
    }

    // List outgoing (requests current user sent)
    @Sendable
    func listOutgoing(req: Request) async throws -> [FriendResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let outgoing = try await FriendshipModel.query(on: req.db)
            .filter(\.$user1ID == userID)
            .filter(\.$status == "pending")
            .all()

        let targetIDs = outgoing.map { $0.user2ID }
        guard !targetIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ targetIDs)
            .all()

        var results: [FriendResponse] = []
        for user in users {
            results.append(try await Self.buildFriendResponse(user: user, status: "pending", db: req.db))
        }
        return results
    }

    // Accept an incoming friend request by friendship ID
    @Sendable
    func acceptRequest(req: Request) async throws -> FriendResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("requestID"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        guard let friendship = try await FriendshipModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        guard friendship.user2ID == userID else {
            throw Abort(.forbidden)
        }

        guard friendship.status == "pending" else {
            throw Abort(.badRequest, reason: "Request is not pending")
        }

        friendship.status = "accepted"
        try await friendship.save(on: req.db)

        let otherUser = try await UserModel.find(friendship.user1ID, on: req.db)
            ?? { throw Abort(.internalServerError) }()

        await NotificationService.send(
            to: friendship.user1ID,
            title: "Friend Request Accepted",
            body: "\(otherUser.username) accepted your friend request.",
            type: NotificationService.NotificationType.friendAccepted,
            on: req.db,
            application: req.application
        )

        return try await Self.buildFriendResponse(user: otherUser, status: "accepted", db: req.db)
    }

    // Reject an incoming friend request (delete)
    @Sendable
    func rejectRequest(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("requestID"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        guard let friendship = try await FriendshipModel.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        guard friendship.user2ID == userID else {
            throw Abort(.forbidden)
        }

        guard friendship.status == "pending" else {
            throw Abort(.badRequest, reason: "Request is not pending")
        }

        try await friendship.delete(on: req.db)
        return .noContent
    }

    // Accept request by requester user ID (friendly client path)
    @Sendable
    func acceptFromUser(req: Request) async throws -> FriendResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("friendID"), let requesterID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        guard let friendship = try await FriendshipModel.query(on: req.db)
            .filter(\.$user1ID == requesterID)
            .filter(\.$user2ID == userID)
            .first() else {
            throw Abort(.notFound)
        }

        guard friendship.status == "pending" else {
            throw Abort(.badRequest, reason: "Request is not pending")
        }

        friendship.status = "accepted"
        try await friendship.save(on: req.db)

        let otherUser = try await UserModel.find(requesterID, on: req.db)
            ?? { throw Abort(.internalServerError) }()

        await NotificationService.send(
            to: requesterID,
            title: "Friend Request Accepted",
            body: "\(otherUser.username) accepted your friend request.",
            type: NotificationService.NotificationType.friendAccepted,
            on: req.db,
            application: req.application
        )

        return try await Self.buildFriendResponse(user: otherUser, status: "accepted", db: req.db)
    }

    // Reject request by requester user ID
    @Sendable
    func rejectFromUser(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("friendID"), let requesterID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        try await FriendshipModel.query(on: req.db)
            .filter(\.$user1ID == requesterID)
            .filter(\.$user2ID == userID)
            .filter(\.$status == "pending")
            .delete()

        return .noContent
    }

    @Sendable
    func nudge(req: Request) async throws -> NudgeResponse {
        let payload = try req.auth.require(UserPayload.self)
        let senderID = try payload.userID

        guard let idString = req.parameters.get("friendID"),
              let friendID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        guard let sender = try await UserModel.find(senderID, on: req.db) else {
            throw Abort(.notFound)
        }

        await NotificationService.send(
            to: friendID,
            title: "Lock In",
            body: "\(sender.username) says: Lock in!",
            type: NotificationService.NotificationType.nudge,
            on: req.db,
            application: req.application
        )

        return NudgeResponse(status: "nudge sent")
    }

    // MARK: - Helpers

    /// Build a FriendResponse with computed presence and hoursUnplugged for the given user.
    /// - Parameter overrideID: if non-nil, used as the response ID (useful when
    ///   representing a friendship-request row rather than the user itself).
    static func buildFriendResponse(
        user: UserModel,
        status: String?,
        overrideID: UUID? = nil,
        db: Database
    ) async throws -> FriendResponse {
        let userID = try user.requireID()
        let presence = try await computePresence(for: userID, lastSeenAt: user.lastSeenAt, db: db)
        let stats = try await StatsService.getStats(for: userID, on: db)
        return FriendResponse(
            id: overrideID ?? userID,
            username: user.username,
            status: status,
            presence: presence,
            hoursUnplugged: stats.hoursUnplugged,
            lastActiveAt: user.lastSeenAt
        )
    }

    /// Presence rules:
    /// - `.unplugged` if user is currently a member of an active locked room (`locked_at != nil` and `ended_at == nil`).
    /// - `.online` if `last_seen_at` is within the last 5 minutes.
    /// - `.offline` otherwise.
    private static func computePresence(for userID: UUID, lastSeenAt: Date?, db: Database) async throws -> PresenceStatus {
        let memberships = try await MemberModel.query(on: db)
            .filter(\.$userID == userID)
            .all()
        let roomIDs = memberships.map { $0.roomID }

        if !roomIDs.isEmpty {
            let lockedActive = try await RoomModel.query(on: db)
                .filter(\.$id ~~ roomIDs)
                .filter(\.$lockedAt != nil)
                .filter(\.$endedAt == nil)
                .count()
            if lockedActive > 0 {
                return .unplugged
            }
        }

        if let lastSeen = lastSeenAt,
           Date().timeIntervalSince(lastSeen) < 5 * 60 {
            return .online
        }
        return .offline
    }
}
