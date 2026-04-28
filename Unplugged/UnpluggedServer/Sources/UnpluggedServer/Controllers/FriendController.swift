import Fluent
import UnpluggedShared
import Vapor

extension FriendResponse: @retroactive Content {}
extension NudgeResponse: @retroactive Content {}
extension FriendProfileResponse: @retroactive Content {}
extension LeaderboardEntryResponse: @retroactive Content {}

struct FriendController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let friends = routes.grouped("friends")
        // POST sends, or accepts if a reciprocal pending request already exists
        friends.post(use: add)
        friends.delete(":friendID", use: remove)
        friends.get(use: list)
        friends.get("leaderboard", use: leaderboard)
        friends.post(":friendID", "nudge", use: nudge)
        friends.post(":friendID", "accept", use: acceptFromUser)
        friends.post(":friendID", "reject", use: rejectFromUser)
        friends.get(":friendID", "profile", use: profile)

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

        // 404 rather than a dedicated status hides "this user blocked you" from the sender
        if try await BlockService.isBlocked(between: userID, and: targetID, on: req.db) {
            throw Abort(.notFound, reason: "User not found.")
        }

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
            if existing.status == "pending" && existing.user1ID == targetID && existing.user2ID == userID {
                existing.status = "accepted"
                try await existing.save(on: req.db)
                try await Self.deletePendingFriendships(between: userID, and: targetID, on: req.db)
                guard let sender = try await UserModel.find(userID, on: req.db) else {
                    throw Abort(.internalServerError)
                }
                await NotificationService.send(
                    to: targetID,
                    title: "Friend Request Accepted",
                    body: "\(sender.username) accepted your friend request.",
                    type: NotificationService.NotificationType.friendAccepted,
                    on: req.db,
                    application: req.application
                )
                await Self.sendFriendshipUpdate(
                    to: targetID,
                    on: req.db,
                    application: req.application
                )
                return try await Self.buildFriendResponse(user: target, status: "accepted", db: req.db)
            }
            throw Abort(.conflict, reason: "Friend request already exists.")
        }

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
        await Self.sendFriendshipUpdate(
            to: targetID,
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

        let friendships = try await FriendshipModel.query(on: req.db)
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
            .all()

        for friendship in friendships {
            try await friendship.delete(on: req.db)
        }

        if !friendships.isEmpty {
            await Self.sendFriendshipUpdate(
                to: friendID,
                on: req.db,
                application: req.application
            )
        }
        return .noContent
    }

    @Sendable
    func list(req: Request) async throws -> [FriendResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

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

        let hiddenIDs = try await BlockService.hiddenUserIDs(for: userID, on: req.db)
        let friendIDs = friendships.compactMap { f -> UUID? in
            let other = f.user1ID == userID ? f.user2ID : f.user1ID
            return hiddenIDs.contains(other) ? nil : other
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

    @Sendable
    func listIncoming(req: Request) async throws -> [FriendResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let hiddenIDs = try await BlockService.hiddenUserIDs(for: userID, on: req.db)

        let acceptedIDs = try await Self.acceptedFriendIDs(for: userID, on: req.db)

        let incoming = try await FriendshipModel.query(on: req.db)
            .filter(\.$user2ID == userID)
            .filter(\.$status == "pending")
            .all()

        let visibleIncoming = incoming.filter {
            !hiddenIDs.contains($0.user1ID) && !acceptedIDs.contains($0.user1ID)
        }
        if visibleIncoming.count != incoming.count {
            req.logger.warning("incoming friend request list suppressed reconciled rows", metadata: [
                "user_id": "\(userID)",
                "incoming_count": "\(incoming.count)",
                "visible_count": "\(visibleIncoming.count)"
            ])
        }
        let requesterIDs = visibleIncoming.map { $0.user1ID }
        guard !requesterIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ requesterIDs)
            .all()

        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        var results: [FriendResponse] = []
        for friendship in visibleIncoming {
            guard let user = userMap[friendship.user1ID] else { continue }
            results.append(try await Self.buildFriendResponse(
                user: user,
                status: "pending",
                overrideID: nil,
                db: req.db
            ))
        }
        return results
    }

    @Sendable
    func listOutgoing(req: Request) async throws -> [FriendResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let hiddenIDs = try await BlockService.hiddenUserIDs(for: userID, on: req.db)

        let acceptedIDs = try await Self.acceptedFriendIDs(for: userID, on: req.db)

        let outgoing = try await FriendshipModel.query(on: req.db)
            .filter(\.$user1ID == userID)
            .filter(\.$status == "pending")
            .all()

        let visibleOutgoing = outgoing.filter {
            !hiddenIDs.contains($0.user2ID) && !acceptedIDs.contains($0.user2ID)
        }
        if visibleOutgoing.count != outgoing.count {
            req.logger.warning("outgoing friend request list suppressed reconciled rows", metadata: [
                "user_id": "\(userID)",
                "outgoing_count": "\(outgoing.count)",
                "visible_count": "\(visibleOutgoing.count)"
            ])
        }
        let targetIDs = visibleOutgoing.map { $0.user2ID }
        guard !targetIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ targetIDs)
            .all()

        var results: [FriendResponse] = []
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        for friendship in visibleOutgoing {
            guard let user = userMap[friendship.user2ID] else { continue }
            results.append(try await Self.buildFriendResponse(user: user, status: "pending", db: req.db))
        }
        return results
    }

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

        req.logger.info("friend accept by request id", metadata: [
            "user_id": "\(userID)",
            "request_id": "\(id)"
        ])

        guard friendship.user2ID == userID else {
            throw Abort(.forbidden)
        }

        let otherUser = try await UserModel.find(friendship.user1ID, on: req.db)
            ?? { throw Abort(.internalServerError) }()

        if friendship.status == "accepted" {
            req.logger.warning("friend accept by request id was already accepted", metadata: [
                "user_id": "\(userID)",
                "request_id": "\(id)",
                "other_user_id": "\(friendship.user1ID)"
            ])
            return try await Self.buildFriendResponse(user: otherUser, status: "accepted", db: req.db)
        }

        guard friendship.status == "pending" else {
            throw Abort(.badRequest, reason: "Request is not pending")
        }

        friendship.status = "accepted"
        try await friendship.save(on: req.db)
        try await Self.deletePendingFriendships(between: userID, and: friendship.user1ID, on: req.db)
        req.logger.info("friend accept by request id applied", metadata: [
            "user_id": "\(userID)",
            "request_id": "\(id)",
            "other_user_id": "\(friendship.user1ID)"
        ])

        await NotificationService.send(
            to: friendship.user1ID,
            title: "Friend Request Accepted",
            body: "\(otherUser.username) accepted your friend request.",
            type: NotificationService.NotificationType.friendAccepted,
            on: req.db,
            application: req.application
        )
        await Self.sendFriendshipUpdate(
            to: friendship.user1ID,
            on: req.db,
            application: req.application
        )

        return try await Self.buildFriendResponse(user: otherUser, status: "accepted", db: req.db)
    }

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
        await Self.sendFriendshipUpdate(
            to: friendship.user1ID,
            on: req.db,
            application: req.application
        )
        return .noContent
    }

    @Sendable
    func acceptFromUser(req: Request) async throws -> FriendResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("friendID"), let requesterID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        let friendships = try await FriendshipModel.query(on: req.db)
            .filter(\.$user1ID == requesterID)
            .filter(\.$user2ID == userID)
            .all()

        req.logger.info("friend accept by user id", metadata: [
            "user_id": "\(userID)",
            "requester_id": "\(requesterID)",
            "matching_rows": "\(friendships.count)"
        ])
        if friendships.count > 1 {
            req.logger.warning("multiple friendship rows found while accepting friend", metadata: [
                "user_id": "\(userID)",
                "requester_id": "\(requesterID)",
                "matching_rows": "\(friendships.count)"
            ])
        }

        guard let friendship = friendships.first(where: { $0.status == "pending" })
            ?? friendships.first(where: { $0.status == "accepted" }) else {
            throw Abort(.notFound)
        }

        let otherUser = try await UserModel.find(requesterID, on: req.db)
            ?? { throw Abort(.internalServerError) }()

        if friendship.status == "accepted" {
            req.logger.warning("friend accept by user id was already accepted", metadata: [
                "user_id": "\(userID)",
                "requester_id": "\(requesterID)"
            ])
            return try await Self.buildFriendResponse(user: otherUser, status: "accepted", db: req.db)
        }

        guard friendship.status == "pending" else {
            throw Abort(.badRequest, reason: "Request is not pending")
        }

        friendship.status = "accepted"
        try await friendship.save(on: req.db)
        try await Self.deletePendingFriendships(between: userID, and: requesterID, on: req.db)
        req.logger.info("friend accept by user id applied", metadata: [
            "user_id": "\(userID)",
            "requester_id": "\(requesterID)"
        ])

        await NotificationService.send(
            to: requesterID,
            title: "Friend Request Accepted",
            body: "\(otherUser.username) accepted your friend request.",
            type: NotificationService.NotificationType.friendAccepted,
            on: req.db,
            application: req.application
        )
        await Self.sendFriendshipUpdate(
            to: requesterID,
            on: req.db,
            application: req.application
        )

        return try await Self.buildFriendResponse(user: otherUser, status: "accepted", db: req.db)
    }

    // rejects an incoming OR cancels an outgoing, the direction is resolved server side from the other user's ID
    @Sendable
    func rejectFromUser(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("friendID"), let otherID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        let friendships = try await FriendshipModel.query(on: req.db)
            .filter(\.$status == "pending")
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$user1ID == otherID)
                    g.filter(\.$user2ID == userID)
                }
                group.group(.and) { g in
                    g.filter(\.$user1ID == userID)
                    g.filter(\.$user2ID == otherID)
                }
            }
            .all()

        for friendship in friendships {
            try await friendship.delete(on: req.db)
        }

        if !friendships.isEmpty {
            await Self.sendFriendshipUpdate(
                to: otherID,
                on: req.db,
                application: req.application
            )
        }

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

        let friendship = try await FriendshipModel.query(on: req.db)
            .filter(\.$status == "accepted")
            .group(.or) { group in
                group
                    .group(.and) { $0.filter(\.$user1ID == senderID).filter(\.$user2ID == friendID) }
                    .group(.and) { $0.filter(\.$user1ID == friendID).filter(\.$user2ID == senderID) }
            }
            .first()
        guard friendship != nil else {
            throw Abort(.forbidden, reason: "You can only nudge accepted friends.")
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

    // gated on accepted friendship or self, otherwise the endpoint becomes a user data scraper
    @Sendable
    func profile(req: Request) async throws -> FriendProfileResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let idString = req.parameters.get("friendID"),
              let friendID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        if friendID != userID {
            if try await BlockService.isBlocked(between: userID, and: friendID, on: req.db) {
                throw Abort(.notFound)
            }
            let friendship = try await FriendshipModel.query(on: req.db)
                .filter(\.$status == "accepted")
                .group(.or) { group in
                    group
                        .group(.and) { $0.filter(\.$user1ID == userID).filter(\.$user2ID == friendID) }
                        .group(.and) { $0.filter(\.$user1ID == friendID).filter(\.$user2ID == userID) }
                }
                .first()
            guard friendship != nil else {
                throw Abort(.forbidden, reason: "Not friends with this user.")
            }
        }

        guard let user = try await UserModel.find(friendID, on: req.db) else {
            throw Abort(.notFound)
        }

        async let friendResponse = Self.buildFriendResponse(
            user: user,
            status: friendID == userID ? nil : "accepted",
            db: req.db
        )
        async let stats = StatsService.getStats(for: friendID, on: req.db)
        async let medals = MedalService.getUserMedals(userID: friendID, on: req.db)

        let (f, s, m) = try await (friendResponse, stats, medals)
        return FriendProfileResponse(friend: f, stats: s, medals: m)
    }

    @Sendable
    func leaderboard(req: Request) async throws -> [LeaderboardEntryResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let friendships = try await FriendshipModel.query(on: req.db)
            .filter(\.$status == "accepted")
            .group(.or) { group in
                group.filter(\.$user1ID == userID)
                group.filter(\.$user2ID == userID)
            }
            .all()
        let hiddenIDs = try await BlockService.hiddenUserIDs(for: userID, on: req.db)

        var participantIDs: Set<UUID> = [userID]
        for f in friendships {
            let other = f.user1ID == userID ? f.user2ID : f.user1ID
            if !hiddenIDs.contains(other) {
                participantIDs.insert(other)
            }
        }

        return try await StatsService.buildLeaderboard(
            userIDs: Array(participantIDs),
            currentUserID: userID,
            on: req.db
        )
    }

    // MARK: - Helpers

    static func acceptedFriendIDs(for userID: UUID, on db: Database) async throws -> Set<UUID> {
        let friendships = try await FriendshipModel.query(on: db)
            .filter(\.$status == "accepted")
            .group(.or) { group in
                group.filter(\.$user1ID == userID)
                group.filter(\.$user2ID == userID)
            }
            .all()

        return Set(friendships.map { friendship in
            friendship.user1ID == userID ? friendship.user2ID : friendship.user1ID
        })
    }

    static func deletePendingFriendships(between firstID: UUID, and secondID: UUID, on db: Database) async throws {
        try await FriendshipModel.query(on: db)
            .filter(\.$status == "pending")
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$user1ID == firstID)
                    g.filter(\.$user2ID == secondID)
                }
                group.group(.and) { g in
                    g.filter(\.$user1ID == secondID)
                    g.filter(\.$user2ID == firstID)
                }
            }
            .delete()
    }

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

    static func sendFriendshipUpdate(
        to userID: UUID,
        on db: Database,
        application: Application
    ) async {
        await NotificationService.sendSilent(
            to: userID,
            type: NotificationService.NotificationType.friendshipUpdated,
            on: db,
            application: application
        )
    }

    // unplugged if in an active locked room, online if last_seen within 5 minutes, else offline
    private static func computePresence(for userID: UUID, lastSeenAt: Date?, db: Database) async throws -> PresenceStatus {
        let memberships = try await MemberModel.query(on: db)
            .filter(\.$userID == userID)
            .all()
        let roomIDs = memberships
            .filter { $0.config != MemberModel.proximityExitConfig }
            .map { $0.roomID }

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
