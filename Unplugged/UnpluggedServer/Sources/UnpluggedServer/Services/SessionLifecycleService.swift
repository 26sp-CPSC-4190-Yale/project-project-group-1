import Fluent
import SQLKit
import UnpluggedShared
import Vapor

enum SessionLifecycleService {
    @discardableResult
    static func expireIfNeeded(session: SessionModel, req: Request) async throws -> Bool {
        guard session.endedAt == nil,
              let endsAt = session.endsAt,
              endsAt <= Date() else {
            return false
        }

        try await finish(session: session, endedAt: endsAt, req: req, reason: "timer_expired")
        return true
    }

    static func expireIfNeeded(sessions: [SessionModel], req: Request) async throws {
        for session in sessions {
            try await expireIfNeeded(session: session, req: req)
        }
    }

    static func expireActiveSessions(sessionIDs: [UUID], req: Request) async throws {
        guard !sessionIDs.isEmpty else { return }
        let sessions = try await SessionModel.query(on: req.db)
            .filter(\.$id ~~ sessionIDs)
            .filter(\.$endedAt == nil)
            .all()
        try await expireIfNeeded(sessions: sessions, req: req)
    }

    @discardableResult
    static func closeCoLockIfStranded(
        session: SessionModel,
        req: Request,
        reason: String
    ) async throws -> Bool {
        guard session.lockMode == .coLock,
              session.endedAt == nil else {
            return false
        }

        let sessionID = try session.requireID()
        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()
        let activeMembers = members.filter { $0.participantStatus == .active }
        guard activeMembers.count <= 1 else { return false }

        if session.lockedAt == nil {
            guard members.count > 1 else { return false }
            try await req.db.transaction { db in
                try await MemberModel.query(on: db)
                    .filter(\.$sessionID == sessionID)
                    .delete()
                try await session.delete(on: db)
            }

            req.logger.info("[SessionLifecycle] Closed stranded co-lock lobby \(sessionID) reason=\(reason)")
            await req.sessionHub.broadcast(sessionID: sessionID, message: .sessionEnded)
            return true
        }

        try await req.db.transaction { db in
            for member in activeMembers {
                member.config = MemberModel.voluntaryExitConfig
                member.leftEarly = true
                try await member.save(on: db)
            }
        }

        try await finish(session: session, endedAt: Date(), req: req, reason: reason)
        return true
    }

    @discardableResult
    static func finish(
        session: SessionModel,
        endedAt: Date,
        req: Request,
        reason: String
    ) async throws -> [MemberModel] {
        let sessionID = try session.requireID()
        let lockedAt = session.lockedAt

        try await req.db.transaction { db in
            session.endedAt = endedAt
            try await session.save(on: db)

            let members = try await MemberModel.query(on: db)
                .filter(\.$sessionID == sessionID)
                .all()

            for member in members {
                let wasAlreadyExited = member.leftAt != nil
                if member.leftAt == nil {
                    member.leftAt = endedAt
                    try await member.save(on: db)
                }

                guard !wasAlreadyExited, let lockedAt else { continue }
                try await awardPoints(
                    to: member.userID,
                    from: lockedAt,
                    to: member.leftAt ?? endedAt,
                    on: db,
                    logger: req.logger
                )
            }
        }

        req.logger.info("[SessionLifecycle] Finished session \(sessionID) reason=\(reason)")
        await req.sessionHub.broadcast(sessionID: sessionID, message: .sessionEnded)

        let members = try await MemberModel.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()

        for member in members {
            await NotificationService.sendSilent(
                to: member.userID,
                type: NotificationService.NotificationType.sessionEnded,
                sessionID: sessionID,
                endsAt: nil,
                on: req.db,
                application: req.application
            )
        }

        for member in members {
            await MedalService.evaluateAndAward(userID: member.userID, on: req.db, logger: req.logger)
        }

        return members
    }

    static func awardPoints(
        to userID: UUID,
        from start: Date,
        to end: Date,
        on db: Database,
        logger: Logger
    ) async throws {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else {
            logger.info("[Stats] Skipped award for user \(userID): duration < 1 minute")
            return
        }

        var quarterPoints = 0
        var remaining = minutes

        let tieredMinutes = min(remaining, 180)
        var tieredRemaining = tieredMinutes
        var tier = 1
        while tieredRemaining > 0 {
            let chunk = min(tieredRemaining, 30)
            quarterPoints += chunk * tier
            tieredRemaining -= chunk
            tier += 1
        }
        remaining -= tieredMinutes

        quarterPoints += remaining * 8

        let points = quarterPoints / 4

        guard let sql = db as? SQLDatabase else {
            logger.error("[Stats] Database is not SQL-backed; cannot atomically award points to user \(userID)")
            throw Abort(.internalServerError, reason: "Points ledger unavailable")
        }
        try await sql.raw("""
            UPDATE users SET points = points + \(bind: points) WHERE id = \(bind: userID)
            """).run()
        logger.info("[Stats] Awarded \(points) points to user \(userID) for \(minutes) min")
    }
}
