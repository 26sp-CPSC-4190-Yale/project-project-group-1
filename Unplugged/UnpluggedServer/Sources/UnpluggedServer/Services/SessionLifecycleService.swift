import Fluent
import SQLKit
import UnpluggedShared
import Vapor

enum SessionLifecycleService {
    @discardableResult
    static func expireIfNeeded(room: RoomModel, req: Request) async throws -> Bool {
        guard room.endedAt == nil,
              let endsAt = room.endsAt,
              endsAt <= Date() else {
            return false
        }

        try await finish(room: room, endedAt: endsAt, req: req, reason: "timer_expired")
        return true
    }

    static func expireIfNeeded(rooms: [RoomModel], req: Request) async throws {
        for room in rooms {
            try await expireIfNeeded(room: room, req: req)
        }
    }

    static func expireActiveRooms(roomIDs: [UUID], req: Request) async throws {
        guard !roomIDs.isEmpty else { return }
        let rooms = try await RoomModel.query(on: req.db)
            .filter(\.$id ~~ roomIDs)
            .filter(\.$endedAt == nil)
            .all()
        try await expireIfNeeded(rooms: rooms, req: req)
    }

    @discardableResult
    static func finish(
        room: RoomModel,
        endedAt: Date,
        req: Request,
        reason: String
    ) async throws -> [MemberModel] {
        let roomID = try room.requireID()
        let lockedAt = room.lockedAt

        try await req.db.transaction { db in
            room.endedAt = endedAt
            try await room.save(on: db)

            let members = try await MemberModel.query(on: db)
                .filter(\.$roomID == roomID)
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

        req.logger.info("[SessionLifecycle] Finished room \(roomID) reason=\(reason)")
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

        for member in members {
            await MedalService.evaluateAndAward(userID: member.userID, on: req.db, logger: req.logger)
        }

        return members
    }

    private static func awardPoints(
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

        let tier1 = min(minutes, 60)
        let tier2 = max(0, min(minutes, 180) - 60)
        let tier3 = max(0, minutes - 180)
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
