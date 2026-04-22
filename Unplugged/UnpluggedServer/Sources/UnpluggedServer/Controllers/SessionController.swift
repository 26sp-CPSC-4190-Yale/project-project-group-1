//
//  SessionController.swift
//  UnpluggedServer.Controllers
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import SQLKit
import UnpluggedShared
import Vapor

extension SessionResponse: @retroactive Content {}

private struct UpdateSessionRequest: Content {
    var isActive: Bool?
}

struct SessionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let sessions = routes.grouped("sessions")
        sessions.post(use: create)
        sessions.post("join", use: join)
        sessions.get(use: list)
        sessions.get(":sessionID", use: get)
        sessions.patch(":sessionID", use: update)
        sessions.post(":sessionID", "leave", use: leave)
        sessions.delete(":sessionID", use: delete)
    }

    // MARK: create

    @Sendable
    func create(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let room = RoomModel()
        room.roomOwner = userID
        room.startTime = Date()
        room.isActive = true
        try await room.save(on: req.db)

        let member = MemberModel(userID: userID, roomID: try room.requireID())
        try await member.save(on: req.db)

        return try await buildSessionResponse(room: room, db: req.db)
    }

    // MARK: join

    @Sendable
    func join(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let body = try req.content.decode(JoinSessionRequest.self)
        guard let roomID = UUID(uuidString: body.code) else {
            throw Abort(.badRequest, reason: "Invalid session code")
        }
        guard let room = try await RoomModel.find(roomID, on: req.db) else {
            throw Abort(.notFound, reason: "Session not found")
        }
        guard room.isActive else {
            throw Abort(.gone, reason: "Session has ended")
        }

        let existing = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$roomID == roomID)
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "Already in this session")
        }

        let member = MemberModel(userID: userID, roomID: roomID)
        try await member.save(on: req.db)

        return try await buildSessionResponse(room: room, db: req.db)
    }

    // MARK: leave

    @Sendable
    func leave(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)

        guard room.roomOwner != userID else {
            throw Abort(.badRequest, reason: "Host must end the session instead of leaving")
        }

        let roomID = try room.requireID()

        try await req.db.transaction { db in
            guard let member = try await MemberModel.query(on: db)
                .filter(\.$userID == userID)
                .filter(\.$roomID == roomID)
                .first()
            else {
                throw Abort(.notFound, reason: "Not a member of this session")
            }

            guard member.leftAt == nil else {
                throw Abort(.conflict, reason: "Already left this session")
            }

            let now = Date()
            member.leftAt = now
            member.leftEarly = true
            try await member.save(on: db)

            try await awardPoints(
                to: userID,
                joinedAt: member.joinedAt,
                leftAt: now,
                on: db,
                logger: req.logger
            )
        }

        return .noContent
    }

    // MARK: list

    @Sendable
    func list(req: Request) async throws -> [SessionResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let memberships = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
        let roomIDs = memberships.map { $0.roomID }

        guard !roomIDs.isEmpty else { return [] }

        let rooms = try await RoomModel.query(on: req.db)
            .filter(\.$id ~~ roomIDs)
            .all()

        return try await rooms.asyncMap { try await buildSessionResponse(room: $0, db: req.db) }
    }

    // MARK: get

    @Sendable
    func get(req: Request) async throws -> SessionResponse {
        let room = try await requireRoom(req: req)
        return try await buildSessionResponse(room: room, db: req.db)
    }

    // MARK: update (end session)

    @Sendable
    func update(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)

        guard room.roomOwner == userID else {
            throw Abort(.forbidden)
        }

        let body = try req.content.decode(UpdateSessionRequest.self)
        if let isActive = body.isActive {
            let wasActive = room.isActive
            room.isActive = isActive

            if wasActive && !isActive {
                let now = Date()
                let roomID = try room.requireID()

                try await req.db.transaction { db in
                    room.endedAt = now
                    try await room.save(on: db)

                    // Stamp leftAt for everyone still in the session and award
                    // their points atomically. A failure in any iteration
                    // rolls back the whole end-session operation.
                    let activeMembers = try await MemberModel.query(on: db)
                        .filter(\.$roomID == roomID)
                        .filter(\.$leftAt == nil)
                        .all()

                    for member in activeMembers {
                        member.leftAt = now
                        try await member.save(on: db)
                        try await awardPoints(
                            to: member.userID,
                            joinedAt: member.joinedAt,
                            leftAt: now,
                            on: db,
                            logger: req.logger
                        )
                    }
                }
            } else {
                try await room.save(on: req.db)
            }
        }

        return try await buildSessionResponse(room: room, db: req.db)
    }

    // MARK: delete

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)

        guard room.roomOwner == userID else {
            throw Abort(.forbidden)
        }

        let roomID = try room.requireID()
        let wasActive = room.isActive
        let now = Date()

        try await req.db.transaction { db in
            // If the host deletes a live session, still credit any member
            // who hadn't already left so their stats aren't erased silently.
            if wasActive {
                let activeMembers = try await MemberModel.query(on: db)
                    .filter(\.$roomID == roomID)
                    .filter(\.$leftAt == nil)
                    .all()
                for member in activeMembers {
                    try await awardPoints(
                        to: member.userID,
                        joinedAt: member.joinedAt,
                        leftAt: now,
                        on: db,
                        logger: req.logger
                    )
                }
            }

            try await MemberModel.query(on: db)
                .filter(\.$roomID == roomID)
                .delete()
            try await room.delete(on: db)
        }
        return .noContent
    }

    // MARK: helpers

    private func requireRoom(req: Request) async throws -> RoomModel {
        guard let idString = req.parameters.get("sessionID"),
              let roomID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard let room = try await RoomModel.find(roomID, on: req.db) else {
            throw Abort(.notFound)
        }
        return room
    }

    private func buildSessionResponse(room: RoomModel, db: Database) async throws -> SessionResponse {
        let roomID = try room.requireID()
        let members = try await MemberModel.query(on: db)
            .filter(\.$roomID == roomID)
            .all()

        let userIDs = members.map { $0.userID }
        let users = try await UserModel.query(on: db)
            .filter(\.$id ~~ userIDs)
            .all()
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        let participants: [ParticipantResponse] = members.compactMap { member in
            guard let memberID = member.id,
                  let user = userMap[member.userID] else { return nil }
            // leftAt is stamped on everyone when the host ends a session,
            // so that alone doesn't mean the user bailed. leftEarly is only
            // true when the user explicitly called /leave mid-session.
            let status: ParticipantStatus = member.leftEarly ? .left : .active
            return ParticipantResponse(
                id: memberID,
                userID: member.userID,
                username: user.username,
                status: status
            )
        }

        let session = Session(
            id: roomID,
            code: roomID.uuidString,
            hostID: room.roomOwner,
            state: room.isActive ? .locked : .ended,
            startedAt: room.startTime,
            endedAt: room.endedAt
        )
        return SessionResponse(session: session, participants: participants)
    }

    //MARK: Point awarding

    /// Awards points like tax brackets.
    ///
    ///   - first 60 min           → ×1
    ///   - minutes 60–180         → ×2
    ///   - minutes beyond 180     → ×3
    ///
    /// Uses an atomic SQL increment. Time credit is given
    /// regardless of whether the user left early.
    private func awardPoints(
        to userID: UUID,
        joinedAt: Date,
        leftAt: Date,
        on db: Database,
        logger: Logger
    ) async throws {
        let minutes = Int(leftAt.timeIntervalSince(joinedAt) / 60)
        guard minutes > 0 else {
            logger.info("[Stats] Skipped award for user \(userID): duration < 1 minute")
            return
        }

        let tier1 = min(minutes, 60)                   // ×1
        let tier2 = max(0, min(minutes, 180) - 60)     // ×2
        let tier3 = max(0, minutes - 180)              // ×3
        let points = tier1 + (tier2 * 2) + (tier3 * 3)

        guard let sql = db as? SQLDatabase else {
            logger.error("[Stats] Database is not SQL-backed; cannot atomically award points to user \(userID)")
            throw Abort(.internalServerError, reason: "Points ledger unavailable")
        }
        try await sql.raw("""
            UPDATE users SET points = points + \(bind: points) WHERE id = \(bind: userID)
            """).run()
        logger.info("[Stats] Awarded \(points) points to user \(userID) for \(minutes) min (t1=\(tier1), t2=\(tier2), t3=\(tier3))")
    }
}

// MARK: async helpers

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var results = [T]()
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}
