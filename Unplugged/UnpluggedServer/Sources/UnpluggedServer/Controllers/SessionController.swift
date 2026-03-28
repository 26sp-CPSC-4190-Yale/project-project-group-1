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
        sessions.get(use: list)
        sessions.get(":sessionID", use: get)
        sessions.patch(":sessionID", use: update)
        sessions.delete(":sessionID", use: delete)
    }

    @Sendable
    func create(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let room = RoomModel()
        room.roomOwner = userID
        room.startTime = Date()
        room.isActive = true
        try await room.save(on: req.db)

        let member = MemberModel()
        member.userID = userID
        member.roomID = try room.requireID()
        try await member.save(on: req.db)

        return try await buildSessionResponse(room: room, db: req.db)
    }

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

    @Sendable
    func get(req: Request) async throws -> SessionResponse {
        let room = try await requireRoom(req: req)
        return try await buildSessionResponse(room: room, db: req.db)
    }

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
            room.isActive = isActive
        }
        try await room.save(on: req.db)
        return try await buildSessionResponse(room: room, db: req.db)
    }

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
            return ParticipantResponse(
                id: memberID,
                userID: member.userID,
                username: user.username,
                status: .active
            )
        }

        let session = Session(
            id: roomID,
            code: roomID.uuidString,
            hostID: room.roomOwner,
            state: room.isActive ? .locked : .ended,
            startedAt: room.startTime,
            endedAt: room.isActive ? nil : room.startTime
        )
        return SessionResponse(session: session, participants: participants)
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
