import Fluent
import Foundation
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

    // auth is a Bearer header, not a query param, the query path leaks tokens to access and proxy logs
    app.webSocket("sessions", ":sessionID", "ws") { req, ws in
        // handlers must be registered synchronously on the EventLoop, otherwise NIOLoopBoundBox crashes
        ws.onText { ws, text in
            Task {
                await handleIncomingData(req: req, ws: ws, data: Data(text.utf8))
            }
        }
        ws.onBinary { ws, buffer in
            Task {
                let data = Data(buffer.readableBytesView)
                await handleIncomingData(req: req, ws: ws, data: data)
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
private func handleIncomingData(req: Request, ws: WebSocket, data: Data) async {
    guard let idString = req.parameters.get("sessionID"),
          let sessionID = UUID(uuidString: idString) else { return }

    guard let token = req.headers.bearerAuthorization?.token,
          let payload = try? await req.jwt.verify(token, as: UserPayload.self),
          let userID = try? payload.userID else { return }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let message = try? decoder.decode(WSClientMessage.self, from: data) else { return }

    switch message {
    case .heartbeat, .hello:
        break
    case .reportJailbreak(let reason):
        guard InputValidation.isValidJailbreakReason(reason) else { return }
        let normalizedReason = InputValidation.normalizedJailbreakReason(reason)
        let detectedAt = Date()
        do {
            guard let session = try await SessionModel.find(sessionID, on: req.db),
                  session.endedAt == nil,
                  session.lockedAt != nil,
                  let member = try await MemberModel.query(on: req.db)
                    .filter(\.$sessionID == sessionID)
                    .filter(\.$userID == userID)
                    .first() else { return }

            try await req.db.transaction { db in
                if member.participantStatus == .active {
                    member.config = MemberModel.jailbreakConfig
                    member.leftAt = detectedAt
                    member.leftEarly = true
                    try await member.save(on: db)
                }

                let record = JailbreakModel(sessionID: sessionID, userID: userID, reason: normalizedReason)
                record.detectedAt = detectedAt
                try await record.save(on: db)
            }
        } catch {
            req.logger.error("Failed to persist jailbreak report for user \(userID) in session \(sessionID): \(error)")
            return
        }
        await req.application.sessionHub.broadcast(
            sessionID: sessionID,
            message: .jailbreakReported(userID: userID, reason: normalizedReason)
        )
        do {
            if let session = try await SessionModel.find(sessionID, on: req.db) {
                _ = try await SessionLifecycleService.closeCoLockIfStranded(
                    session: session,
                    req: req,
                    reason: "co_lock_jailbreak_stranded"
                )
            }
        } catch {
            req.logger.error("Failed to close stranded co-lock session \(sessionID) after jailbreak report: \(error)")
        }
    }
}

@Sendable
private func handleClose(req: Request, ws: WebSocket) async {
    guard let idString = req.parameters.get("sessionID"),
          let sessionID = UUID(uuidString: idString) else { return }

    guard let token = req.headers.bearerAuthorization?.token,
          let payload = try? await req.jwt.verify(token, as: UserPayload.self),
          let userID = try? payload.userID else { return }

    await req.application.sessionHub.leave(sessionID: sessionID, userID: userID)
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
          let sessionID = UUID(uuidString: idString) else {
        try? await ws.close(code: .unacceptableData)
        return
    }

    do {
        let membership = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
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

    await req.application.sessionHub.join(sessionID: sessionID, userID: userID, ws: ws)

    do {
        if let session = try await SessionModel.find(sessionID, on: req.db) {
            let response = try await SessionResponseBuilder.build(session: session, db: req.db)
            await req.application.sessionHub.send(
                sessionID: sessionID,
                toUserID: userID,
                message: .stateSync(response)
            )
        }
    } catch {
        req.logger.error("Failed to send initial stateSync: \(error)")
    }
}
