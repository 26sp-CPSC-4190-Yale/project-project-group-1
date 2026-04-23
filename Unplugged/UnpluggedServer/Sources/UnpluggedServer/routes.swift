import Fluent
import UnpluggedShared
import Vapor

func routes(_ app: Application) throws {
    app.get("healthz") { _ in HTTPStatus.ok }

    app.get("readyz") { req async throws -> HTTPStatus in
        try await req.db.transaction { _ in }
        return .ok
    }

    try app.register(collection: AuthController())
    try app.register(collection: LegalController())

    let protected = app.grouped(JWTAuthMiddleware())
    try protected.register(collection: UserController())
    try protected.register(collection: SessionController())
    try protected.register(collection: FriendController())
    try protected.register(collection: MedalsController())
    try protected.register(collection: StatsController())
    try protected.register(collection: GroupController())

    // auth is a Bearer header, not a query param, the query path leaks tokens to access and proxy logs
    app.webSocket("sessions", ":sessionID", "ws") { req, ws in
        // handlers must be registered synchronously on the EventLoop, otherwise NIOLoopBoundBox crashes
        ws.onText { ws, text in
            Task {
                await handleIncomingText(req: req, ws: ws, text: text)
            }
        }
        ws.onClose.whenComplete { _ in
            Task {
                await handleClose(req: req, ws: ws)
            }
        }

        Task {
            await handleSessionWebSocket(req: req, ws: ws)
        }
    }
}

@Sendable
private func handleIncomingText(req: Request, ws: WebSocket, text: String) async {
    guard let idString = req.parameters.get("sessionID"),
          let roomID = UUID(uuidString: idString) else { return }

    guard let token = req.headers.bearerAuthorization?.token,
          let payload = try? await req.jwt.verify(token, as: UserPayload.self),
          let userID = try? payload.userID else { return }

    guard let data = text.data(using: .utf8) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let message = try? decoder.decode(WSClientMessage.self, from: data) else { return }

    switch message {
    case .heartbeat, .hello:
        break
    case .reportJailbreak(let reason):
        let record = JailbreakModel(sessionID: roomID, userID: userID, reason: reason)
        record.detectedAt = Date()
        do {
            try await record.save(on: req.db)
        } catch {
            req.logger.error("Failed to persist jailbreak report for user \(userID) in room \(roomID): \(error)")
        }
        await req.application.sessionHub.broadcast(
            roomID: roomID,
            message: .jailbreakReported(userID: userID, reason: reason)
        )
    }
}

@Sendable
private func handleClose(req: Request, ws: WebSocket) async {
    guard let idString = req.parameters.get("sessionID"),
          let roomID = UUID(uuidString: idString) else { return }

    guard let token = req.headers.bearerAuthorization?.token,
          let payload = try? await req.jwt.verify(token, as: UserPayload.self),
          let userID = try? payload.userID else { return }

    await req.application.sessionHub.leave(roomID: roomID, userID: userID)
}

@Sendable
private func handleSessionWebSocket(req: Request, ws: WebSocket) async {
    guard let token = req.headers.bearerAuthorization?.token else {
        try? await ws.send("unauthorized")
        try? await ws.close(code: .policyViolation)
        return
    }

    let payload: UserPayload
    do {
        payload = try await req.jwt.verify(token, as: UserPayload.self)
    } catch {
        try? await ws.send("unauthorized")
        try? await ws.close(code: .policyViolation)
        return
    }

    let userID: UUID
    do {
        userID = try payload.userID
    } catch {
        try? await ws.close(code: .policyViolation)
        return
    }

    guard let idString = req.parameters.get("sessionID"),
          let roomID = UUID(uuidString: idString) else {
        try? await ws.close(code: .unacceptableData)
        return
    }

    do {
        let membership = try await MemberModel.query(on: req.db)
            .filter(\.$roomID == roomID)
            .filter(\.$userID == userID)
            .first()
        guard membership != nil else {
            try? await ws.close(code: .policyViolation)
            return
        }
    } catch {
        try? await ws.close(code: .unexpectedServerError)
        return
    }

    await req.application.sessionHub.join(roomID: roomID, userID: userID, ws: ws)

    do {
        if let room = try await RoomModel.find(roomID, on: req.db) {
            let session = try await makeSessionResponse(room: room, db: req.db)
            await req.application.sessionHub.send(
                roomID: roomID,
                toUserID: userID,
                message: .stateSync(session)
            )
        }
    } catch {
        req.logger.error("Failed to send initial stateSync: \(error)")
    }
}

private func makeSessionResponse(room: RoomModel, db: Database) async throws -> SessionResponse {
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
            status: member.participantStatus,
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
        code: room.code ?? legacyRoomCode(for: roomID),
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

private func legacyRoomCode(for roomID: UUID) -> String {
    String(roomID.uuidString
        .filter { $0.isLetter || $0.isNumber }
        .prefix(InputValidation.sessionCodeLength))
        .uppercased()
}
