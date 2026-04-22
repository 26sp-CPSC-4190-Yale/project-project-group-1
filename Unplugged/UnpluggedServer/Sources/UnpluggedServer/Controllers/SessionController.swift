//
//  SessionController.swift
//  UnpluggedServer.Controllers
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
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
        guard let member = try await MemberModel.query(on: req.db)
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
        try await member.save(on: req.db)

        try await awardPoints(to: userID, joinedAt: member.joinedAt, leftAt: now, db: req.db)

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
                room.endedAt = now
                try await room.save(on: req.db)

                // Stamp leftAt for everyone still in the session and award their points
                let roomID = try room.requireID()
                let activeMembers = try await MemberModel.query(on: req.db)
                    .filter(\.$roomID == roomID)
                    .filter(\.$leftAt == nil)
                    .all()

                for member in activeMembers {
                    member.leftAt = now
                    try await member.save(on: req.db)
                    try await awardPoints(to: member.userID, joinedAt: member.joinedAt, leftAt: now, db: req.db)
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
        try await MemberModel.query(on: req.db)
            .filter(\.$roomID == roomID)
            .delete()
        try await room.delete(on: req.db)
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
            let status: ParticipantStatus = member.leftAt != nil ? .left : .active
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

    /// Awards 1 point per minute of session participation.
    private func awardPoints(to userID: UUID, joinedAt: Date, leftAt: Date, db: Database) async throws {
        let minutes = Int(leftAt.timeIntervalSince(joinedAt) / 60)
        guard minutes > 0 else { return }
        guard let user = try await UserModel.find(userID, on: db) else { return }
        user.points += minutes
        try await user.save(on: db)
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
