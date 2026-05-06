import Fluent
import SQLKit
import UnpluggedShared
import Vapor

extension SessionResponse: @retroactive Content {}
extension SessionHistoryResponse: @retroactive Content {}
extension SessionMemoryPhotoResponse: @retroactive Content {}

private struct UpdateSessionRequest: Content {
    var title: String?
    var description: String?
    var latitude: Double?
    var longitude: Double?
}

struct SessionController: RouteCollection {
    private static let shieldAttemptThrottle: TimeInterval = 60

    func boot(routes: RoutesBuilder) throws {
        let sessions = routes.grouped("sessions")
        sessions.post(use: create)
        sessions.get(use: list)
        sessions.get("history", use: history)
        sessions.get(":sessionID", use: get)
        sessions.patch(":sessionID", use: update)
        sessions.patch(":sessionID", "metadata", use: updateMetadata)
        sessions.delete(":sessionID", use: delete)
        sessions.post(":sessionID", "join", use: join)
        sessions.post(":sessionID", "start", use: start)
        sessions.post(":sessionID", "end", use: end)
        sessions.post(":sessionID", "leave", use: leave)
        sessions.post(":sessionID", "co-lock", "ready", use: setCoLockReady)
        sessions.post(":sessionID", "co-lock", "release", use: requestCoLockRelease)
        sessions.post(":sessionID", "co-lock", "release", "approve", use: approveCoLockRelease)
        sessions.post(":sessionID", "proximity-exit", use: reportProximityExit)
        sessions.post(":sessionID", "shield-attempt", use: reportShieldAttempt)
        sessions.get(":sessionID", "photos", use: listPhotos)
        sessions.post(":sessionID", "photos", use: uploadPhoto)
        sessions.delete(":sessionID", "photos", ":photoID", use: deletePhoto)
        sessions.get(":sessionID", "recap", use: recap)
        sessions.post(":sessionID", "jailbreaks", use: reportJailbreak)
    }

    // MARK: - Create / Join / List / Get

    @Sendable
    func create(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let body = try req.content.decode(CreateSessionRequest.self)

        guard InputValidation.isValidSessionTitle(body.title) else {
            throw Abort(.badRequest, reason: "Title must be 1-\(InputValidation.sessionTitleMaxLength) characters.")
        }
        guard InputValidation.isValidSessionDescription(body.description) else {
            throw Abort(.badRequest, reason: "Description is too long.")
        }
        guard InputValidation.isValidDurationSeconds(body.durationSeconds) else {
            throw Abort(.badRequest, reason: "Duration must be between 1 second and 24 hours.")
        }
        guard InputValidation.isValidLatitude(body.latitude), InputValidation.isValidLongitude(body.longitude) else {
            throw Abort(.badRequest, reason: "Invalid coordinates.")
        }

        let code = try await Self.generateSessionCode(on: req.db)
        let session = SessionModel(
            roomOwner: userID,
            code: code,
            title: InputValidation.normalizedOptionalText(body.title, maxLength: InputValidation.sessionTitleMaxLength) ?? body.title,
            description: nil,
            durationSeconds: body.durationSeconds,
            lockMode: body.lockMode,
            latitude: nil,
            longitude: nil
        )

        // session plus owner-membership must be atomic, otherwise a ghost session passes auth checks but cannot be joined or ended
        try await req.db.transaction { db in
            try await session.save(on: db)
            let member = MemberModel()
            member.userID = userID
            member.sessionID = try session.requireID()
            try await member.save(on: db)
        }

        return try await buildSessionResponse(session: session, db: req.db)
    }

    @Sendable
    func list(req: Request) async throws -> [SessionResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let memberships = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
        let sessionIDs = memberships
            .filter { $0.participantStatus == .active }
            .map { $0.sessionID }

        guard !sessionIDs.isEmpty else { return [] }

        let sessions = try await SessionModel.query(on: req.db)
            .filter(\.$id ~~ sessionIDs)
            .filter(\.$endedAt == nil)
            .all()

        try await SessionLifecycleService.expireIfNeeded(sessions: sessions, req: req)
        return try await buildSessionResponses(sessions: sessions.filter { $0.endedAt == nil }, db: req.db)
    }

    @Sendable
    func history(req: Request) async throws -> [SessionHistoryResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let limit = min(max(req.query[Int.self, at: "limit"] ?? 25, 1), 100)
        let before = req.query[Date.self, at: "before"]

        let memberships = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
        let sessionIDs = memberships.map { $0.sessionID }

        guard !sessionIDs.isEmpty else { return [] }
        try await SessionLifecycleService.expireActiveSessions(sessionIDs: sessionIDs, req: req)

        var query = SessionModel.query(on: req.db)
            .filter(\.$id ~~ sessionIDs)
            .filter(\.$endedAt != nil)
        if let before {
            query = query.filter(\.$endedAt < before)
        }
        let sessions = try await query
            .sort(\.$endedAt, .descending)
            .limit(limit)
            .all()

        let returnedSessionIDs = sessions.compactMap { try? $0.requireID() }
        let jailbreaks: [JailbreakModel]
        if returnedSessionIDs.isEmpty {
            jailbreaks = []
        } else {
            jailbreaks = try await JailbreakModel.query(on: req.db)
                .filter(\.$userID == userID)
                .filter(\.$sessionID ~~ returnedSessionIDs)
                .all()
        }
        var leaveMap: [UUID: (at: Date, reason: String?)] = [:]
        for jb in jailbreaks {
            if let existing = leaveMap[jb.sessionID], existing.at <= jb.detectedAt {
                continue
            }
            leaveMap[jb.sessionID] = (jb.detectedAt, jb.reason)
        }

        let allMembers: [MemberModel]
        let allPhotos: [SessionMemoryPhotoModel]
        if returnedSessionIDs.isEmpty {
            allMembers = []
            allPhotos = []
        } else {
            allMembers = try await MemberModel.query(on: req.db)
                .filter(\.$sessionID ~~ returnedSessionIDs)
                .all()
            allPhotos = try await SessionMemoryPhotoModel.query(on: req.db)
                .filter(\.$sessionID ~~ returnedSessionIDs)
                .sort(\.$createdAt, .ascending)
                .all()
        }
        let participantCounts = Dictionary(grouping: allMembers, by: \.sessionID).mapValues(\.count)
        let photosBySession = Dictionary(grouping: allPhotos, by: \.sessionID)
            .mapValues { $0.compactMap(SessionResponseBuilder.photoResponse) }

        var results: [SessionHistoryResponse] = []
        for session in sessions {
            let sessionID = try session.requireID()
            let leave = leaveMap[sessionID]
            let focused = StatsService.focusedSeconds(session: session, earliestLeaveAt: leave?.at)
            let planned = max(0, session.durationSeconds ?? 0)
            let leftEarly = focused + StatsService.earlyLeaveToleranceSeconds < planned

            results.append(
                SessionHistoryResponse(
                    id: sessionID,
                    title: session.title,
                    description: session.description,
                    startedAt: session.lockedAt ?? session.startTime,
                    endedAt: session.endedAt,
                    durationSeconds: session.durationSeconds,
                    participantCount: participantCounts[sessionID] ?? 0,
                    latitude: session.latitude,
                    longitude: session.longitude,
                    memoryPhotos: photosBySession[sessionID] ?? [],
                    actualFocusedSeconds: focused,
                    leftEarly: leftEarly,
                    leftAt: leave?.at,
                    leaveReason: leave?.reason
                )
            )
        }
        return results
    }

    @Sendable
    func get(req: Request) async throws -> SessionResponse {
        let session = try await requireSession(req: req)
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let sessionID = try session.requireID()
        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }
        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        return try await buildSessionResponse(session: session, db: req.db)
    }

    @Sendable
    func update(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)

        guard session.roomOwner == userID else {
            throw Abort(.forbidden)
        }
        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)

        let body = try req.content.decode(UpdateSessionRequest.self)
        if session.endedAt == nil,
           body.description != nil || body.latitude != nil || body.longitude != nil {
            throw Abort(.conflict, reason: "Mementos can be edited after the session ends.")
        }
        try applyUpdateBody(body, to: session)
        try await session.save(on: req.db)
        return try await buildSessionResponse(session: session, db: req.db)
    }

    @Sendable
    func updateMetadata(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }
        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt != nil else {
            throw Abort(.conflict, reason: "Mementos can be edited after the session ends.")
        }

        let body = try req.content.decode(SessionMetadataRequest.self)
        guard InputValidation.isValidSessionDescription(body.description) else {
            throw Abort(.badRequest, reason: "Description is too long.")
        }
        guard InputValidation.isValidLatitude(body.latitude), InputValidation.isValidLongitude(body.longitude) else {
            throw Abort(.badRequest, reason: "Invalid coordinates.")
        }
        session.description = InputValidation.normalizedOptionalText(body.description, maxLength: InputValidation.sessionDescriptionMaxLength)
        session.latitude = body.latitude
        session.longitude = body.longitude
        try await session.save(on: req.db)
        return try await buildSessionResponse(session: session, db: req.db)
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)

        guard session.roomOwner == userID else {
            throw Abort(.forbidden)
        }

        let sessionID = try session.requireID()
        try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .delete()
        try await session.delete(on: req.db)
        return .noContent
    }

    @Sendable
    func join(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)

        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session is no longer active")
        }
        guard session.lockedAt == nil else {
            throw Abort(.forbidden, reason: "Session is locked; cannot join an in-progress session.")
        }

        let sessionID = try session.requireID()
        let existing = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$sessionID == sessionID)
            .first()

        var reactivatedExistingMember = false
        if let existing {
            if existing.participantStatus != .active || existing.leftAt != nil || existing.leftEarly || existing.coLockReady {
                try await req.db.transaction { db in
                    existing.config = nil
                    existing.leftAt = nil
                    existing.leftEarly = false
                    existing.coLockReady = false
                    existing.joinedAt = Date()
                    try await existing.save(on: db)

                    try await JailbreakModel.query(on: db)
                        .filter(\.$sessionID == sessionID)
                        .filter(\.$userID == userID)
                        .group(.or) { group in
                            group.filter(\.$reason == SessionExitReason.leftVoluntarily)
                            group.filter(\.$reason == SessionExitReason.leftDueToProximity)
                        }
                        .delete()
                }
                reactivatedExistingMember = true
            }
        } else {
            let member = MemberModel(userID: userID, sessionID: sessionID)
            try await member.save(on: req.db)

            if let user = try await UserModel.find(userID, on: req.db) {
                let response = ParticipantResponse(
                    id: try member.requireID(),
                    userID: userID,
                    username: user.username,
                    status: member.participantStatus,
                    joinedAt: Date(),
                    isHost: false
                )
                await req.sessionHub.broadcast(sessionID: sessionID, message: .participantJoined(response))
            }
        }

        if reactivatedExistingMember,
           let member = try await MemberModel.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$sessionID == sessionID)
            .first(),
           let user = try await UserModel.find(userID, on: req.db) {
            let response = ParticipantResponse(
                id: try member.requireID(),
                userID: userID,
                username: user.username,
                status: member.participantStatus,
                joinedAt: member.joinedAt,
                isHost: session.lockMode == .coLock ? false : userID == session.roomOwner
            )
            await req.sessionHub.broadcast(sessionID: sessionID, message: .participantJoined(response))
        }

        return try await buildSessionResponse(session: session, db: req.db)
    }

    // MARK: - Lifecycle: start / end

    @Sendable
    func start(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        if session.lockMode == .coLock {
            guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
                throw Abort(.forbidden)
            }
            let activeMembers = try await MemberModel.query(on: req.db)
                .filter(\.$sessionID == sessionID)
                .all()
                .filter { $0.participantStatus == .active }
            guard activeMembers.count >= 2 else {
                throw Abort(.conflict, reason: "Co-lock requires at least two active participants.")
            }
            guard !activeMembers.isEmpty, activeMembers.allSatisfy(\.coLockReady) else {
                throw Abort(.conflict, reason: "Everyone must be ready before a co-lock can start.")
            }
        } else {
            guard session.roomOwner == userID else {
                throw Abort(.forbidden, reason: "Only the host can start the session.")
            }
        }
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session has already ended.")
        }
        guard session.lockedAt == nil else {
            throw Abort(.conflict, reason: "Session is already locked.")
        }

        let now = Date()
        session.lockedAt = now
        try await session.save(on: req.db)

        let endsAt = session.endsAt ?? Date.distantFuture
        await req.sessionHub.broadcast(sessionID: sessionID, message: .sessionLocked(endsAt: endsAt))

        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()
        for member in members {
            await NotificationService.sendSilent(
                to: member.userID,
                type: NotificationService.NotificationType.sessionLocked,
                sessionID: sessionID,
                endsAt: session.endsAt,
                on: req.db,
                application: req.application
            )
        }

        return try await buildSessionResponse(session: session, db: req.db)
    }

    @Sendable
    func end(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        if session.lockMode == .coLock {
            guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
                throw Abort(.forbidden)
            }
            guard try await hasUnanimousCoLockRelease(sessionID: sessionID, db: req.db) else {
                throw Abort(.conflict, reason: "Everyone must approve ending this co-lock.")
            }
        } else {
            guard session.roomOwner == userID else {
                throw Abort(.forbidden, reason: "Only the host can end the session.")
            }
        }
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }

        try await SessionLifecycleService.finish(
            session: session,
            endedAt: Date(),
            req: req,
            reason: "manual_end"
        )

        return try await buildSessionResponse(session: session, db: req.db)
    }

    @Sendable
    func leave(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }
        if session.lockMode == .coLock, session.lockedAt != nil {
            if try await SessionLifecycleService.closeCoLockIfStranded(
                session: session,
                req: req,
                reason: "co_lock_last_member_leave"
            ) {
                return .noContent
            }
            throw Abort(.conflict, reason: "Co-lock sessions require everyone to approve release.")
        }
        // hosts must end via /end, letting the host leave here silently drops the session without notifying members
        guard session.lockMode == .coLock || session.roomOwner != userID else {
            throw Abort(.forbidden, reason: "Hosts must end the session instead of leaving.")
        }

        guard let member = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$userID == userID)
            .first() else {
            throw Abort(.forbidden)
        }

        let now = Date()
        let alreadyExited = member.config == MemberModel.voluntaryExitConfig
            || member.config == MemberModel.proximityExitConfig

        if !alreadyExited {
            try await req.db.transaction { db in
                member.config = MemberModel.voluntaryExitConfig
                if member.leftAt == nil {
                    member.leftAt = now
                    member.leftEarly = session.lockedAt != nil
                }
                try await member.save(on: db)

                if let lockedAt = session.lockedAt {
                    try await SessionLifecycleService.awardPoints(
                        to: userID,
                        from: lockedAt,
                        to: now,
                        on: db,
                        logger: req.logger
                    )
                }
            }
        }

        if session.lockMode == .coLock, session.lockedAt == nil {
            try await clearCoLockReadinessIfBelowStartMinimum(sessionID: sessionID, db: req.db)
        } else if try await SessionLifecycleService.closeCoLockIfStranded(
            session: session,
            req: req,
            reason: "co_lock_lobby_stranded"
        ) {
            return .noContent
        }

        // recap and history read left-early from JailbreakModel rows, skip on duplicate so a double-tap does not double-count
        let reason = SessionExitReason.leftVoluntarily
        if session.lockedAt != nil {
            let existingReport = try await JailbreakModel.query(on: req.db)
                .filter(\.$sessionID == sessionID)
                .filter(\.$userID == userID)
                .filter(\.$reason == reason)
                .first()
            if existingReport == nil {
                let record = JailbreakModel(sessionID: sessionID, userID: userID, reason: reason)
                record.detectedAt = now
                try await record.save(on: req.db)
            }
        }

        if session.lockMode == .coLock, session.lockedAt == nil {
            let response = try await buildSessionResponse(session: session, db: req.db)
            await req.sessionHub.broadcast(sessionID: sessionID, message: .stateSync(response))
        } else {
            await req.sessionHub.broadcast(sessionID: sessionID, message: .participantLeft(userID: userID))
        }

        let username = (try await UserModel.find(userID, on: req.db))?.username ?? "A participant"
        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()
        if session.lockedAt != nil {
            for recipient in members where recipient.userID != userID && recipient.config != MemberModel.voluntaryExitConfig {
                await NotificationService.send(
                    to: recipient.userID,
                    title: "Oh no!",
                    body: "\(username) left the session.",
                    type: NotificationService.NotificationType.sessionJailbreak,
                    on: req.db,
                    application: req.application
                )
            }
        }

        return .noContent
    }

    // MARK: - Co-lock

    @Sendable
    func setCoLockReady(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()
        guard session.lockMode == .coLock else {
            throw Abort(.badRequest, reason: "This session is not a co-lock.")
        }
        guard session.lockedAt == nil, session.endedAt == nil else {
            throw Abort(.conflict, reason: "Readiness can only change before lock-in starts.")
        }
        guard let member = try await membership(userID: userID, sessionID: sessionID, db: req.db) else {
            throw Abort(.forbidden)
        }
        let body = try req.content.decode(CoLockReadyRequest.self)
        guard member.participantStatus == .active else {
            throw Abort(.forbidden, reason: "Only active co-lock participants can set readiness.")
        }
        if body.isReady {
            let activeCount = try await MemberModel.query(on: req.db)
                .filter(\.$sessionID == sessionID)
                .all()
                .filter { $0.participantStatus == .active }
                .count
            guard activeCount >= 2 else {
                throw Abort(.conflict, reason: "Co-lock requires at least two active participants.")
            }
        }
        member.coLockReady = body.isReady
        try await member.save(on: req.db)
        let response = try await buildSessionResponse(session: session, db: req.db)
        await req.sessionHub.broadcast(sessionID: sessionID, message: .stateSync(response))
        return response
    }

    @Sendable
    func requestCoLockRelease(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()
        guard session.lockMode == .coLock else {
            throw Abort(.badRequest, reason: "This session is not a co-lock.")
        }
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }
        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }

        try await CoLockReleaseApprovalModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .delete()
        let approval = CoLockReleaseApprovalModel(sessionID: sessionID, requesterID: userID, approverID: userID)
        try await approval.save(on: req.db)

        if session.lockedAt != nil,
           try await hasUnanimousCoLockRelease(sessionID: sessionID, db: req.db) {
            try await SessionLifecycleService.finish(
                session: session,
                endedAt: Date(),
                req: req,
                reason: "co_lock_release_approved"
            )
            return try await buildSessionResponse(session: session, db: req.db)
        }

        let response = try await buildSessionResponse(session: session, db: req.db)
        await req.sessionHub.broadcast(sessionID: sessionID, message: .stateSync(response))
        return response
    }

    @Sendable
    func approveCoLockRelease(req: Request) async throws -> SessionResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()
        guard session.lockMode == .coLock else {
            throw Abort(.badRequest, reason: "This session is not a co-lock.")
        }
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }
        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }
        guard let releaseRequest = try await CoLockReleaseApprovalModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .sort(\.$createdAt, .ascending)
            .first() else {
            throw Abort(.conflict, reason: "No co-lock release has been requested.")
        }
        let requesterID = releaseRequest.requesterID

        let existing = try await CoLockReleaseApprovalModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$requesterID == requesterID)
            .filter(\.$approverID == userID)
            .first()
        if existing == nil {
            try await CoLockReleaseApprovalModel(sessionID: sessionID, requesterID: requesterID, approverID: userID)
                .save(on: req.db)
        }

        if try await hasUnanimousCoLockRelease(sessionID: sessionID, db: req.db) {
            return try await end(req: req)
        }

        let response = try await buildSessionResponse(session: session, db: req.db)
        await req.sessionHub.broadcast(sessionID: sessionID, message: .stateSync(response))
        return response
    }

    // MARK: - Photos

    @Sendable
    func listPhotos(req: Request) async throws -> [SessionMemoryPhotoResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()
        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }
        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        return try await SessionResponseBuilder.photoResponses(sessionID: sessionID, db: req.db)
    }

    @Sendable
    func uploadPhoto(req: Request) async throws -> SessionMemoryPhotoResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()
        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }
        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt != nil else {
            throw Abort(.conflict, reason: "Photos can be added after the session ends.")
        }
        let body = try req.content.decode(UploadSessionPhotoRequest.self)
        guard body.mimeType == "image/jpeg" || body.mimeType == "image/png" else {
            throw Abort(.badRequest, reason: "Unsupported image type.")
        }
        guard body.imageData.count <= InputValidation.maxPhotoBytes,
              (body.thumbnailData?.count ?? 0) <= InputValidation.maxPhotoThumbnailBytes else {
            throw Abort(.payloadTooLarge, reason: "Photo is too large.")
        }
        let photo = SessionMemoryPhotoModel(
            sessionID: sessionID,
            uploaderID: userID,
            mimeType: body.mimeType,
            imageData: body.imageData,
            thumbnailData: body.thumbnailData
        )
        try await photo.save(on: req.db)
        let response = SessionMemoryPhotoResponse(
            id: try photo.requireID(),
            sessionID: sessionID,
            uploaderID: userID,
            mimeType: photo.mimeType,
            byteCount: photo.imageData.count,
            thumbnailData: photo.thumbnailData,
            createdAt: photo.createdAt ?? Date()
        )
        let updated = try await buildSessionResponse(session: session, db: req.db)
        await req.sessionHub.broadcast(sessionID: sessionID, message: .stateSync(updated))
        return response
    }

    @Sendable
    func deletePhoto(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()
        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }
        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt != nil else {
            throw Abort(.conflict, reason: "Photos can be edited after the session ends.")
        }
        guard let photoID = req.parameters.get("photoID", as: UUID.self),
              let photo = try await SessionMemoryPhotoModel.find(photoID, on: req.db),
              photo.sessionID == sessionID else {
            throw Abort(.notFound)
        }
        guard photo.uploaderID == userID || session.roomOwner == userID else {
            throw Abort(.forbidden)
        }
        try await photo.delete(on: req.db)
        let updated = try await buildSessionResponse(session: session, db: req.db)
        await req.sessionHub.broadcast(sessionID: sessionID, message: .stateSync(updated))
        return .noContent
    }

    // MARK: - Recap

    @Sendable
    func recap(req: Request) async throws -> SessionRecapResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        let membership = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$userID == userID)
            .first()
        guard membership != nil else {
            throw Abort(.forbidden)
        }
        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt != nil else {
            throw Abort(.badRequest, reason: "Session has not ended yet.")
        }

        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()
        let userIDs = members.map { $0.userID }
        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ userIDs)
            .filter(\.$deletedAt == nil)
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
                isHost: session.lockMode == .coLock ? false : member.userID == session.roomOwner
            )
        }

        let jbRecords = try await JailbreakModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
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

        let planned = session.durationSeconds.map { max(0, $0) }
        // session-lifetime metric, not per-user, ignore jailbreak rows so host-ending-early is the only shortener
        let actualFocusedSeconds = StatsService.focusedSeconds(
            session: session,
            earliestLeaveAt: nil
        )
        let endedEarly = planned.map {
            $0 > 0 && actualFocusedSeconds + StatsService.earlyLeaveToleranceSeconds < $0
        } ?? false
        let completionRate: Double = (planned ?? 0) > 0
            ? min(1.0, Double(actualFocusedSeconds) / Double(planned ?? 1))
            : 0
        let photos = try await SessionResponseBuilder.photoResponses(sessionID: sessionID, db: req.db)

        return SessionRecapResponse(
            sessionID: sessionID,
            title: session.title,
            description: session.description,
            startedAt: session.lockedAt ?? session.startTime,
            endedAt: session.endedAt,
            durationSeconds: planned,
            actualFocusedSeconds: actualFocusedSeconds,
            endedEarly: endedEarly,
            participants: participants,
            jailbreaks: jailbreaks,
            completionRate: completionRate,
            latitude: session.latitude,
            longitude: session.longitude,
            memoryPhotos: photos
        )
    }

    // MARK: - Jailbreak reporting

    @Sendable
    func reportJailbreak(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }
        guard session.lockedAt != nil else {
            throw Abort(.badRequest, reason: "Jailbreak reports only apply to locked sessions.")
        }

        let body = try req.content.decode(ReportJailbreakRequest.self)
        guard InputValidation.isValidJailbreakReason(body.reason) else {
            throw Abort(.badRequest, reason: "Invalid jailbreak reason.")
        }
        let detectedAt = Date()
        let reason = InputValidation.normalizedJailbreakReason(body.reason)

        guard let member = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$userID == userID)
            .first() else {
            throw Abort(.forbidden)
        }

        try await req.db.transaction { db in
            if member.participantStatus == .active {
                member.config = MemberModel.jailbreakConfig
                member.leftAt = detectedAt
                member.leftEarly = true
                try await member.save(on: db)
            }

            let record = JailbreakModel(sessionID: sessionID, userID: userID, reason: reason)
            record.detectedAt = detectedAt
            try await record.save(on: db)
        }

        await req.sessionHub.broadcast(
            sessionID: sessionID,
            message: .jailbreakReported(userID: userID, reason: reason)
        )

        if try await SessionLifecycleService.closeCoLockIfStranded(
            session: session,
            req: req,
            reason: "co_lock_jailbreak_stranded"
        ) {
            return .noContent
        }

        // notify everyone still in the session, already-exited members are skipped so they are not pinged after detaching
        let reporter = try await UserModel.find(userID, on: req.db)
        let reporterName = reporter?.username ?? "A participant"
        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()
        for recipient in members where recipient.userID != userID
            && recipient.config != MemberModel.voluntaryExitConfig
            && recipient.config != MemberModel.proximityExitConfig {
            await NotificationService.send(
                to: recipient.userID,
                title: "Oh no!",
                body: "\(reporterName) broke the shield during your session.",
                type: NotificationService.NotificationType.sessionJailbreak,
                on: req.db,
                application: req.application
            )
        }

        return .noContent
    }

    @Sendable
    func reportProximityExit(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }
        guard let lockedAt = session.lockedAt else {
            throw Abort(.badRequest, reason: "Proximity exits only apply to locked sessions.")
        }

        guard let member = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$userID == userID)
            .first() else {
            throw Abort(.forbidden)
        }

        let now = Date()
        let alreadyExited = member.config == MemberModel.proximityExitConfig
            || member.config == MemberModel.voluntaryExitConfig

        if !alreadyExited {
            try await req.db.transaction { db in
                member.config = MemberModel.proximityExitConfig
                if member.leftAt == nil {
                    member.leftAt = now
                    member.leftEarly = true
                }
                try await member.save(on: db)

                try await SessionLifecycleService.awardPoints(
                    to: userID,
                    from: lockedAt,
                    to: now,
                    on: db,
                    logger: req.logger
                )
            }
        }

        let reason = SessionExitReason.leftDueToProximity
        let existingReport = try await JailbreakModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$userID == userID)
            .filter(\.$reason == reason)
            .first()
        if existingReport == nil {
            let record = JailbreakModel(sessionID: sessionID, userID: userID, reason: reason)
            record.detectedAt = now
            try await record.save(on: req.db)
        }

        let username = (try await UserModel.find(userID, on: req.db))?.username ?? "A participant"
        await req.sessionHub.broadcast(
            sessionID: sessionID,
            message: .participantLeftDueToProximity(userID: userID, username: username)
        )

        if try await SessionLifecycleService.closeCoLockIfStranded(
            session: session,
            req: req,
            reason: "co_lock_proximity_stranded"
        ) {
            return .noContent
        }

        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()
        for recipient in members where recipient.userID != userID && recipient.config != MemberModel.proximityExitConfig {
            await NotificationService.send(
                to: recipient.userID,
                title: "Oh no!",
                body: "\(username) drifted too far from the group and left the session.",
                type: NotificationService.NotificationType.sessionProximityExit,
                on: req.db,
                application: req.application
            )
        }

        return .noContent
    }

    @Sendable
    func reportShieldAttempt(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        let session = try await requireSession(req: req)
        let sessionID = try session.requireID()

        try await SessionLifecycleService.expireIfNeeded(session: session, req: req)
        guard session.endedAt == nil else {
            throw Abort(.gone, reason: "Session already ended.")
        }
        guard session.lockedAt != nil else {
            throw Abort(.badRequest, reason: "Shield attempts only apply to locked sessions.")
        }
        guard try await membership(userID: userID, sessionID: sessionID, db: req.db) != nil else {
            throw Abort(.forbidden)
        }

        let body = try req.content.decode(ShieldActionAttemptRequest.self)
        guard InputValidation.isValidJailbreakReason(body.reason) else {
            throw Abort(.badRequest, reason: "Invalid shield attempt reason.")
        }
        let reason = InputValidation.normalizedJailbreakReason(body.reason)
        let cutoff = body.occurredAt.addingTimeInterval(-Self.shieldAttemptThrottle)
        let recentAttempt = try await JailbreakModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$userID == userID)
            .filter(\.$reason == reason)
            .filter(\.$detectedAt > cutoff)
            .first()
        let shouldNotify = recentAttempt == nil

        let record = JailbreakModel(sessionID: sessionID, userID: userID, reason: reason)
        record.detectedAt = body.occurredAt
        try await record.save(on: req.db)

        guard shouldNotify else {
            return .noContent
        }

        let reporterName = (try await UserVisibilityService.visibleUser(userID, on: req.db))?.username ?? "A participant"
        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()
        for recipient in members where recipient.userID != userID && recipient.participantStatus == .active {
            await NotificationService.send(
                to: recipient.userID,
                title: "Shield attempt",
                body: "\(reporterName) tried to open a blocked app.",
                type: NotificationService.NotificationType.sessionShieldAttempt,
                on: req.db,
                application: req.application
            )
        }

        await req.sessionHub.broadcast(
            sessionID: sessionID,
            message: .jailbreakReported(userID: userID, reason: reason)
        )
        return .noContent
    }

    // MARK: - Helpers

    private func requireSession(req: Request) async throws -> SessionModel {
        guard let idString = req.parameters.get("sessionID") else {
            throw Abort(.badRequest)
        }
        if let sessionID = UUID(uuidString: idString) {
            if let session = try await SessionModel.find(sessionID, on: req.db) {
                return session
            }
        } else {
            let normalizedCode = idString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if InputValidation.isValidSessionCode(normalizedCode) {
                if let session = try await SessionModel.query(on: req.db)
                    .filter(\.$code == normalizedCode)
                    .filter(\.$endedAt == nil)
                    .first() {
                    return session
                }
            }
        }
        throw Abort(.notFound)
    }

    private static let sessionCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    private static func generateSessionCode(on db: Database) async throws -> String {
        for _ in 0..<10 {
            let code = String((0..<InputValidation.sessionCodeLength).compactMap { _ in
                sessionCodeAlphabet.randomElement()
            })
            let existing = try await SessionModel.query(on: db)
                .filter(\.$code == code)
                .first()
            if existing == nil {
                return code
            }
        }

        throw Abort(.internalServerError, reason: "Could not generate a session code.")
    }

    private func membership(userID: UUID, sessionID: UUID, db: Database) async throws -> MemberModel? {
        try await MemberModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$userID == userID)
            .first()
    }

    private func clearCoLockReadinessIfBelowStartMinimum(sessionID: UUID, db: Database) async throws {
        let members = try await MemberModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .all()
        let activeMembers = members.filter { $0.participantStatus == .active }
        guard activeMembers.count < 2 else { return }
        for member in activeMembers where member.coLockReady {
            member.coLockReady = false
            try await member.save(on: db)
        }
    }

    private func applyUpdateBody(_ body: UpdateSessionRequest, to session: SessionModel) throws {
        if let title = body.title {
            guard InputValidation.isValidSessionTitle(title) else {
                throw Abort(.badRequest, reason: "Title must be 1-\(InputValidation.sessionTitleMaxLength) characters.")
            }
            session.title = InputValidation.normalizedOptionalText(title, maxLength: InputValidation.sessionTitleMaxLength)
        }
        if let description = body.description {
            guard InputValidation.isValidSessionDescription(description) else {
                throw Abort(.badRequest, reason: "Description is too long.")
            }
            session.description = InputValidation.normalizedOptionalText(description, maxLength: InputValidation.sessionDescriptionMaxLength)
        }
        if let lat = body.latitude {
            guard InputValidation.isValidLatitude(lat) else {
                throw Abort(.badRequest, reason: "Invalid latitude.")
            }
            session.latitude = lat
        }
        if let lng = body.longitude {
            guard InputValidation.isValidLongitude(lng) else {
                throw Abort(.badRequest, reason: "Invalid longitude.")
            }
            session.longitude = lng
        }
    }

    private func hasUnanimousCoLockRelease(sessionID: UUID, db: Database) async throws -> Bool {
        let activeMembers = try await MemberModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .all()
            .filter { $0.participantStatus == .active }
        guard !activeMembers.isEmpty else { return false }
        guard let releaseRequest = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .sort(\.$createdAt, .ascending)
            .first() else {
            return false
        }
        let requesterID = releaseRequest.requesterID
        let approvals = try await CoLockReleaseApprovalModel.query(on: db)
            .filter(\.$sessionID == sessionID)
            .filter(\.$requesterID == requesterID)
            .all()
        let approved = Set(approvals.map(\.approverID))
        return activeMembers.allSatisfy { approved.contains($0.userID) }
    }

    private func buildSessionResponse(session: SessionModel, db: Database) async throws -> SessionResponse {
        try await SessionResponseBuilder.build(session: session, db: db)
    }

    private func buildSessionResponses(sessions: [SessionModel], db: Database) async throws -> [SessionResponse] {
        try await SessionResponseBuilder.build(sessions: sessions, db: db)
    }

    private static func legacySessionCode(for sessionID: UUID) -> String {
        SessionResponseBuilder.legacySessionCode(for: sessionID)
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
