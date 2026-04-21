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
extension SessionHistoryResponse: @retroactive Content {}

private struct UpdateSessionRequest: Content {
    var title: String?
    var latitude: Double?
    var longitude: Double?
}

struct SessionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let sessions = routes.grouped("sessions")
        sessions.post(use: create)
        sessions.get(use: list)
        sessions.get("history", use: history)
        sessions.get(":sessionID", use: get)
        sessions.patch(":sessionID", use: update)
        sessions.delete(":sessionID", use: delete)
        sessions.post(":sessionID", "join", use: join)
        sessions.post(":sessionID", "start", use: start)
        sessions.post(":sessionID", "end", use: end)
        sessions.get(":sessionID", "recap", use: recap)
        sessions.post(":sessionID", "jailbreaks", use: reportJailbreak)
    }

    // MARK: - Create / Join / List / Get

    @Sendable
    func create(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let body = try req.content.decode(CreateSessionRequest.self)

        guard body.durationSeconds > 0, body.durationSeconds <= 60 * 60 * 24 else {
            throw Abort(.badRequest, reason: "Duration must be between 1 second and 24 hours.")
        }

        let code = try await Self.generateRoomCode(on: req.db)
        let room = RoomModel(
            roomOwner: userID,
            isActive: true,
            code: code,
            title: body.title,
            durationSeconds: body.durationSeconds,
            latitude: body.latitude,
            longitude: body.longitude
        )

        // Room + owner-membership must be atomic — a room with no host row is
        // a ghost that passes auth checks but can never be joined or ended.
        try await req.db.transaction { db in
            try await room.save(on: db)
            let member = MemberModel()
            member.userID = userID
            member.roomID = try room.requireID()
            try await member.save(on: db)
        }

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
            .filter(\.$endedAt == nil)
            .all()

        return try await rooms.asyncMap { try await buildSessionResponse(room: $0, db: req.db) }
    }

    @Sendable
    func history(req: Request) async throws -> [SessionHistoryResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        // Cursor pagination: `before` is the endedAt of the last row from the
        // previous page; clients request older rows by passing it back. Limit
        // is clamped to [1, 100] with a default of 25 so unbounded queries
        // can't blow up on users with long histories.
        let limit = min(max(req.query[Int.self, at: "limit"] ?? 25, 1), 100)
        let before = req.query[Date.self, at: "before"]

        let memberships = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
        let roomIDs = memberships.map { $0.roomID }

        guard !roomIDs.isEmpty else { return [] }

        var query = RoomModel.query(on: req.db)
            .filter(\.$id ~~ roomIDs)
            .filter(\.$endedAt != nil)
        if let before {
            query = query.filter(\.$endedAt < before)
        }
        let rooms = try await query
            .sort(\.$endedAt, .descending)
            .limit(limit)
            .all()

        var results: [SessionHistoryResponse] = []
        for room in rooms {
            let roomID = try room.requireID()
            let participantCount = try await MemberModel.query(on: req.db)
                .filter(\.$roomID == roomID)
                .count()
            results.append(
                SessionHistoryResponse(
                    id: roomID,
                    title: room.title,
                    startedAt: room.lockedAt ?? room.startTime,
                    endedAt: room.endedAt,
                    durationSeconds: room.durationSeconds,
                    participantCount: participantCount,
                    latitude: room.latitude,
                    longitude: room.longitude
                )
            )
        }
        return results
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
        if let title = body.title { room.title = title }
        if let lat = body.latitude { room.latitude = lat }
        if let lng = body.longitude { room.longitude = lng }
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

    @Sendable
    func join(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)

        guard room.isActive, room.endedAt == nil else {
            throw Abort(.gone, reason: "Room is no longer active")
        }
        // Once a room has been locked, you cannot join mid-session.
        guard room.lockedAt == nil else {
            throw Abort(.forbidden, reason: "Room is locked; cannot join an in-progress session.")
        }

        let roomID = try room.requireID()
        let existing = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$roomID == roomID)
            .first()

        if existing == nil {
            let member = MemberModel(userID: userID, roomID: roomID)
            try await member.save(on: req.db)

            // Announce to everyone else in the lobby via WebSocket
            if let user = try await UserModel.find(userID, on: req.db) {
                let response = ParticipantResponse(
                    id: try member.requireID(),
                    userID: userID,
                    username: user.username,
                    status: .active,
                    joinedAt: Date(),
                    isHost: false
                )
                await req.sessionHub.broadcast(roomID: roomID, message: .participantJoined(response))
            }
        }

        return try await buildSessionResponse(room: room, db: req.db)
    }

    // MARK: - Lifecycle: start / end

    @Sendable
    func start(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)

        guard room.roomOwner == userID else {
            throw Abort(.forbidden, reason: "Only the host can start the session.")
        }
        guard room.endedAt == nil else {
            throw Abort(.gone, reason: "Session has already ended.")
        }
        guard room.lockedAt == nil else {
            throw Abort(.conflict, reason: "Session is already locked.")
        }
        guard let duration = room.durationSeconds else {
            throw Abort(.badRequest, reason: "Session has no duration.")
        }

        let now = Date()
        let endsAt = now.addingTimeInterval(TimeInterval(duration))
        room.lockedAt = now
        room.endsAt = endsAt
        try await room.save(on: req.db)

        let roomID = try room.requireID()

        // Broadcast to any live WebSocket listeners
        await req.sessionHub.broadcast(roomID: roomID, message: .sessionLocked(endsAt: endsAt))

        // Silent APNS fallback for backgrounded clients
        let members = try await MemberModel.query(on: req.db)
            .filter(\.$roomID == roomID)
            .all()
        for member in members {
            await NotificationService.sendSilent(
                to: member.userID,
                type: NotificationService.NotificationType.sessionLocked,
                sessionID: roomID,
                endsAt: endsAt,
                on: req.db,
                application: req.application
            )
        }

        return try await buildSessionResponse(room: room, db: req.db)
    }

    @Sendable
    func end(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)

        guard room.roomOwner == userID else {
            throw Abort(.forbidden, reason: "Only the host can end the session.")
        }
        guard room.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }

        room.endedAt = Date()
        room.isActive = false
        try await room.save(on: req.db)

        let roomID = try room.requireID()
        await req.sessionHub.broadcast(roomID: roomID, message: .sessionEnded)

        let members = try await MemberModel.query(on: req.db)
            .filter(\.$roomID == roomID)
            .all()
        for member in members {
            await NotificationService.sendSilent(
                to: member.userID,
                type: NotificationService.NotificationType.sessionEnded,
                sessionID: roomID,
                endsAt: nil,
                on: req.db,
                application: req.application
            )
        }

        return try await buildSessionResponse(room: room, db: req.db)
    }

    // MARK: - Recap

    @Sendable
    func recap(req: Request) async throws -> SessionRecapResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)

        guard room.endedAt != nil else {
            throw Abort(.badRequest, reason: "Session has not ended yet.")
        }

        let roomID = try room.requireID()

        // Only members can read recap
        let membership = try await MemberModel.query(on: req.db)
            .filter(\.$roomID == roomID)
            .filter(\.$userID == userID)
            .first()
        guard membership != nil else {
            throw Abort(.forbidden)
        }

        let members = try await MemberModel.query(on: req.db)
            .filter(\.$roomID == roomID)
            .all()
        let userIDs = members.map { $0.userID }
        let users = try await UserModel.query(on: req.db)
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
                status: .active,
                joinedAt: nil,
                isHost: member.userID == room.roomOwner
            )
        }

        let jbRecords = try await JailbreakModel.query(on: req.db)
            .filter(\.$sessionID == roomID)
            .all()
        let jailbreaks: [JailbreakEntry] = jbRecords.compactMap { jb in
            guard let id = jb.id else { return nil }
            let username = userMap[jb.userID]?.username ?? "unknown"
            return JailbreakEntry(
                id: id,
                userID: jb.userID,
                username: username,
                detectedAt: jb.detectedAt,
                reason: jb.reason
            )
        }

        let duration = room.durationSeconds ?? 0
        let completionRate: Double
        if participants.isEmpty {
            completionRate = 0
        } else {
            let jbUsers = Set(jbRecords.map { $0.userID })
            let finishers = participants.filter { !jbUsers.contains($0.userID) }.count
            completionRate = Double(finishers) / Double(participants.count)
        }

        return SessionRecapResponse(
            sessionID: roomID,
            title: room.title,
            startedAt: room.lockedAt ?? room.startTime,
            endedAt: room.endedAt,
            durationSeconds: duration,
            participants: participants,
            jailbreaks: jailbreaks,
            completionRate: completionRate
        )
    }

    // MARK: - Jailbreak reporting

    @Sendable
    func reportJailbreak(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let room = try await requireRoom(req: req)
        let roomID = try room.requireID()

        let body = try req.content.decode(ReportJailbreakRequest.self)

        let record = JailbreakModel(sessionID: roomID, userID: userID, reason: body.reason)
        record.detectedAt = body.detectedAt
        try await record.save(on: req.db)

        await req.sessionHub.broadcast(
            roomID: roomID,
            message: .jailbreakReported(userID: userID, reason: body.reason)
        )

        if room.roomOwner != userID {
            if let reporter = try await UserModel.find(userID, on: req.db) {
                await NotificationService.send(
                    to: room.roomOwner,
                    title: "Shield broken",
                    body: "\(reporter.username) left the shield during your session.",
                    type: NotificationService.NotificationType.sessionJailbreak,
                    on: req.db,
                    application: req.application
                )
            }
        }

        return .noContent
    }

    // MARK: - Helpers

    private func requireRoom(req: Request) async throws -> RoomModel {
        guard let idString = req.parameters.get("sessionID") else {
            throw Abort(.badRequest)
        }
        if let roomID = UUID(uuidString: idString) {
            if let room = try await RoomModel.find(roomID, on: req.db) {
                return room
            }
        } else {
            let normalizedCode = idString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if InputValidation.isValidSessionCode(normalizedCode) {
                if let room = try await RoomModel.query(on: req.db)
                    .filter(\.$code == normalizedCode)
                    .filter(\.$isActive == true)
                    .filter(\.$endedAt == nil)
                    .first() {
                    return room
                }
            }
        }
        throw Abort(.notFound)
    }

    private static let roomCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    private static func generateRoomCode(on db: Database) async throws -> String {
        for _ in 0..<10 {
            let code = String((0..<InputValidation.sessionCodeLength).compactMap { _ in
                roomCodeAlphabet.randomElement()
            })
            let existing = try await RoomModel.query(on: db)
                .filter(\.$code == code)
                .first()
            if existing == nil {
                return code
            }
        }

        throw Abort(.internalServerError, reason: "Could not generate a room code.")
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
                status: .active,
                joinedAt: nil,
                isHost: member.userID == room.roomOwner
            )
        }

        let state: RoomState
        if room.endedAt != nil {
            state = .ended
        } else if room.lockedAt != nil {
            state = .locked
        } else {
            state = .idle
        }

        let session = Session(
            id: roomID,
            code: room.code ?? Self.legacyRoomCode(for: roomID),
            hostID: room.roomOwner,
            state: state,
            title: room.title,
            durationSeconds: room.durationSeconds,
            startedAt: room.startTime,
            lockedAt: room.lockedAt,
            endsAt: room.endsAt,
            endedAt: room.endedAt,
            latitude: room.latitude,
            longitude: room.longitude
        )
        return SessionResponse(session: session, participants: participants)
    }

    private static func legacyRoomCode(for roomID: UUID) -> String {
        String(roomID.uuidString
            .filter { $0.isLetter || $0.isNumber }
            .prefix(InputValidation.sessionCodeLength))
            .uppercased()
    }
}

extension SessionRecapResponse: @retroactive Content {}

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
